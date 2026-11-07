import AppKit
import GremletsCore

/// Claude buddy, platform side. Claude Code's hooks (scripts/gremlet-claude-hook) report each session's events here:
/// start (you sent a prompt), done (Claude finished its turn), attention (Claude needs your OK or is waiting), end.
/// A Gremlet goes to that session's window and works on a little creation until Claude is done.
final class ClaudeBuddy {
    private struct Session { var creatureID: Int; var project: String; var lastEvent: Date; var finishedAt: Date?; var tty: String? = nil; var app: String? = nil }
    private var lastTabCheck = Date.distantPast
    private var tabLookup: Process?
    private var sessions: [String: Session] = [:]
    private let world: World
    private let overlay: OverlayController
    private var lastCraft: Craft?
    let log = CreationLog()
    let sessionLog = SessionLog()
    var onChange: () -> Void = {}
    /// A session closed with its record and the project's tree as it is now.
    var onSessionEnded: (SessionRecord, Bonsai?) -> Void = { _, _ in }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "claudeBuddy.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "claudeBuddy.enabled"); if !newValue { endAll() } }
    }

    init(world: World, overlay: OverlayController) { self.world = world; self.overlay = overlay }

    func handle(_ q: [String: String]) -> (Int, String) {
        guard enabled else { return (200, #"{"ok":true,"buddy":"off"}"#) }
        let session = String((q["session"] ?? "default").filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(64))
        let project = String((SpeechText.clean(q["project"]) ?? "Claude").prefix(40))
        let pid = q["pid"].flatMap { Int32($0) }
        switch q["event"] ?? "" {
        case "start":
            // The window comes from the hook's process (or, for the demo, is named outright).
            let windowID = q["window"].flatMap { Int($0) } ?? pid.flatMap { ProcessTree.frontWindow(forDescendant: $0) }
            let prefer = sessions[session].map(\.creatureID)
            let craft = Craft.allCases.filter { $0 != lastCraft }.randomElement() ?? .garden
            guard let id = world.startJob(windowID: windowID, craft: craft, prefer: prefer) else {
                return (409, #"{"ok":false,"error":"no Gremlets are out"}"#)
            }
            if let c = world.creatures.first(where: { $0.id == id }), c.job?.craft == craft { lastCraft = craft }
            sessions[session] = Session(creatureID: id, project: project, lastEvent: Date(), finishedAt: nil,
                                        tty: pid.flatMap { ProcessTree.tty(forDescendant: $0) }, app: pid.flatMap { ProcessTree.terminalApp(forDescendant: $0) })
            world.labelJob(workerID: id, project)
            // The scripted demo is not a session of yours: it stays out of the log, the journal and the recap cards.
            if !session.hasPrefix("showcase-") { sessionLog.begin(session, project: project, before: world.bonsaiBook[project]) }
            // The project's bonsai takes root on this window (a new session grows a new branch).
            world.bonsaiStart(project: project, session: session, windowID: windowID,
                              repoCommits: q["commits"].flatMap { Int($0) }, repoSince: q["since"].flatMap { Double($0) })
        case "done":
            // Every finished Claude task grows the grove, and puts a flower on the project's bonsai.
            world.feedGrove()
            world.bonsaiGrow(project: project, .bloom)
            sessionLog.task(session)
            let text = "\(project): Claude is done ✓"
            if var s = sessions[session], let c = worker(s.creatureID), let j = c.job, j.phase != .finished {
                world.finishJob(c.id)
                log.add(j.craft)
                s.finishedAt = Date(); s.lastEvent = Date(); sessions[session] = s
                overlay.showBubble(text, on: c.id, seconds: 10)
                onChange()
            } else if let id = world.say() {
                overlay.showBubble(text, on: id, seconds: 10)
            }
        case "attention":
            let permission = q["kind"] == "permission"
            sessionLog.attention(session)
            if let s = sessions[session], !permission, let f = s.finishedAt, Date().timeIntervalSince(f) < 120 {
                break   // "waiting for your input" right after "done" would be a double nag
            }
            let text = permission ? "\(project): Claude needs your OK" : "\(project): Claude is waiting for you"
            if let s = sessions[session], let c = worker(s.creatureID) {
                world.jobNeedsAttention(c.id)
                overlay.showBubble(text, on: c.id, seconds: 12)
            } else if let id = world.say() {
                overlay.showBubble(text, on: id, seconds: 12)
            }
        case "tool":
            // Claude used a tool: the Gremlet beside its window acts it out (an edit places a block, and so on).
            if var s = sessions[session], let c = worker(s.creatureID) {
                let tool = ClaudeTool.from(q["tool"] ?? "")
                world.claudeTool(workerID: c.id, tool)
                if q["kind"] == "test" { world.claudeTestsPassed(workerID: c.id) }
                if let t = q["todos"].flatMap(Int.init), let d = q["done"].flatMap(Int.init) { world.claudePlan(workerID: c.id, total: t, done: d) }
                sessionLog.tool(session, edit: tool == .build, failed: false, test: q["kind"] == "test")
                s.lastEvent = Date(); sessions[session] = s
            }
        case "context":
            if let s = sessions[session], let p = q["pct"].flatMap(Int.init) { world.claudeContext(workerID: s.creatureID, pct: p) }
        case "toolfail":
            if let s = sessions[session] { world.claudeToolFailed(workerID: s.creatureID, tests: q["kind"] == "test") }
            sessionLog.tool(session, edit: false, failed: true, test: q["kind"] == "test")
        case "helperdone":
            if let s = sessions[session] { world.claudeHelperDone(workerID: s.creatureID) }
            sessionLog.helper(session)
        case "compact":
            if let s = sessions[session] { world.claudeCompact(workerID: s.creatureID) }
        case "end":
            if let s = sessions.removeValue(forKey: session) { world.endJob(s.creatureID); world.bonsaiEnd(project: s.project) }
            close(session)
        default:
            return (400, #"{"ok":false,"error":"event must be start, done, attention, end, tool, toolfail, helperdone or compact"}"#)
        }
        return (200, #"{"ok":true}"#)
    }

    /// Once a second: finished Gremlets go back to normal life after a while (the creation lingers a minute more);
    /// sessions that went quiet for 45 minutes are dropped.
    func tick() {
        let now = Date()
        followTabs(now)
        for (key, s) in sessions {
            guard let c = worker(s.creatureID) else { world.bonsaiEnd(project: s.project); sessions[key] = nil; close(key); continue }
            if let f = s.finishedAt, now.timeIntervalSince(f) > 40, c.job != nil { world.endJob(c.id) }
            if now.timeIntervalSince(s.lastEvent) > 45 * 60 { world.endJob(c.id); world.bonsaiEnd(project: s.project); sessions[key] = nil; close(key) }
        }
    }

    private func worker(_ id: Int) -> Creature? { world.creatures.first { $0.id == id } }

    /// Every few seconds, asks Terminal (or iTerm) which window holds each Claude session's tab, by its tty, so the
    /// tree, ivy and ledges follow a tab dragged out into its own window. macOS asks once whether Gremlets may
    /// control Terminal; if you say no, everything stays where the session started.
    private func followTabs(_ now: Date) {
        guard now.timeIntervalSince(lastTabCheck) > 3, tabLookup == nil else { return }
        lastTabCheck = now
        let live = sessions.filter { $0.value.tty != nil && $0.value.finishedAt == nil && ["Terminal", "iTerm2"].contains($0.value.app ?? "") }
        guard !live.isEmpty, UserDefaults.standard.object(forKey: "followTabs") as? Bool ?? true else { return }
        var lines: [String] = []
        for (key, s) in live {
            guard let tty = s.tty else { continue }
            if s.app == "Terminal" {
                lines.append(#"tell application "Terminal""#)
                lines.append(#"repeat with w in windows"#)
                lines.append(#"repeat with t in tabs of w"#)
                lines.append(#"if tty of t is "/dev/\#(tty)" then set out to out & "\#(key)=" & (id of w) & linefeed"#)
                lines.append("end repeat")
                lines.append("end repeat")
                lines.append("end tell")
            } else {
                // iTerm's window ids aren't window-server ids: it can't be followed this way.
                continue
            }
        }
        guard !lines.isEmpty else { return }
        let script = (["set out to \"\""] + lines + ["return out"]).joined(separator: "\n")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.tabLookup = nil
                if proc.terminationStatus != 0 { return }
                for line in out.split(separator: "\n") {
                    let parts = line.split(separator: "=")
                    guard parts.count == 2, let s = self.sessions[String(parts[0])], let wid = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
                    if let c = self.worker(s.creatureID), c.job?.windowID != wid {
                        self.world.moveClaudeSession(workerID: s.creatureID, project: s.project, to: wid)
                    }
                }
            }
        }
        tabLookup = p
        do { try p.run() } catch { tabLookup = nil }
    }

    private func close(_ session: String) {
        if let r = sessionLog.end(session) { onSessionEnded(r, world.bonsaiBook[r.project]) }
    }

    private func endAll() {
        for (key, s) in sessions { world.endJob(s.creatureID); world.bonsaiEnd(project: s.project); close(key) }
        sessions.removeAll()
    }
}

/// How many things the Gremlets made while Claude worked, per day (UserDefaults).
final class CreationLog {
    private let key = "creations.v1"
    private var days: [String: [String: Int]] = [:]

    init() { days = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Int]] ?? [:] }

    func add(_ craft: Craft) {
        days[BondStore.dayKey(), default: [:]][craft.rawValue, default: 0] += 1
        UserDefaults.standard.set(days, forKey: key)
    }

    var total: Int { days.values.reduce(0) { $0 + $1.values.reduce(0, +) } }
    var todayCount: Int { (days[BondStore.dayKey()] ?? [:]).values.reduce(0, +) }

    /// e.g. "2 flowers · 1 painting", or nil if nothing yet today.
    var todaySummary: String? {
        let today = days[BondStore.dayKey()] ?? [:]
        let parts = Craft.allCases.compactMap { c -> String? in
            guard let n = today[c.rawValue], n > 0 else { return nil }
            return "\(n) \(c.noun)\(n == 1 ? "" : c.noun.hasSuffix("x") ? "es" : "s")"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Finds the window a Claude session runs in: walk up from the hook's process to its ancestors (shell → claude →
/// Terminal / VS Code / the Claude app...) and take the front-most window any of them owns. Uses only process ids and
/// window bounds, never window titles or contents.
enum ProcessTree {
    static func parent(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let pp = info.kp_eproc.e_ppid
        return pp > 1 ? pp : nil
    }

    static func ancestors(of pid: Int32) -> [Int32] {
        var out: [Int32] = [pid]
        var cur = pid
        while out.count < 32, let p = parent(of: cur) { out.append(p); cur = p }
        return out
    }

    /// The controlling terminal (e.g. "ttys003") of the nearest ancestor that has one.
    static func tty(forDescendant pid: Int32) -> String? {
        for p in ancestors(of: pid) {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, p]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { continue }
            let dev = info.kp_eproc.e_tdev
            if dev != -1, let name = devname(dev, S_IFCHR) { return String(cString: name) }
        }
        return nil
    }

    /// The name of the app the session's window belongs to ("Terminal", "iTerm2", "Code"...).
    static func terminalApp(forDescendant pid: Int32) -> String? {
        let family = Set(ancestors(of: pid).map { pid_t($0) })
        return NSWorkspace.shared.runningApplications.first { family.contains($0.processIdentifier) }?.localizedName
    }

    static func frontWindow(forDescendant pid: Int32) -> Int? {
        let family = Set(ancestors(of: pid).map(Int.init))
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let owner = w[kCGWindowOwnerPID as String] as? Int, family.contains(owner),
                  let b = w[kCGWindowBounds as String] as? [String: Double], (b["Width"] ?? 0) >= 80, (b["Height"] ?? 0) >= 40
            else { continue }
            return w[kCGWindowNumber as String] as? Int
        }
        return nil
    }
}
