import AppKit
import GremletsCore

/// Claude buddy, platform side. Claude Code's hooks (scripts/gremlet-claude-hook) report each session's events here:
/// start (you sent a prompt), done (Claude finished its turn), attention (Claude needs your OK or is waiting), end.
/// A Gremlet goes to that session's window and works on a little creation until Claude is done.
final class ClaudeBuddy {
    private struct Session { var creatureID: Int; var project: String; var lastEvent: Date; var finishedAt: Date? }
    private var sessions: [String: Session] = [:]
    private let world: World
    private let overlay: OverlayController
    private var lastCraft: Craft?
    let log = CreationLog()
    var onChange: () -> Void = {}

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
            let windowID = pid.flatMap { ProcessTree.frontWindow(forDescendant: $0) }
            let prefer = sessions[session].map(\.creatureID)
            let craft = Craft.allCases.filter { $0 != lastCraft }.randomElement() ?? .garden
            guard let id = world.startJob(windowID: windowID, craft: craft, prefer: prefer) else {
                return (409, #"{"ok":false,"error":"no Gremlets are out"}"#)
            }
            if let c = world.creatures.first(where: { $0.id == id }), c.job?.craft == craft { lastCraft = craft }
            sessions[session] = Session(creatureID: id, project: project, lastEvent: Date(), finishedAt: nil)
        case "done":
            // Every finished Claude task grows the grove.
            world.feedGrove()
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
        case "end":
            if let s = sessions.removeValue(forKey: session) { world.endJob(s.creatureID) }
        default:
            return (400, #"{"ok":false,"error":"event must be start, done, attention or end"}"#)
        }
        return (200, #"{"ok":true}"#)
    }

    /// Once a second: finished Gremlets go back to normal life after a while (the creation lingers a minute more);
    /// sessions that went quiet for 45 minutes are dropped.
    func tick() {
        let now = Date()
        for (key, s) in sessions {
            guard let c = worker(s.creatureID) else { sessions[key] = nil; continue }
            if let f = s.finishedAt, now.timeIntervalSince(f) > 40, c.job != nil { world.endJob(c.id) }
            if now.timeIntervalSince(s.lastEvent) > 45 * 60 { world.endJob(c.id); sessions[key] = nil }
        }
    }

    private func worker(_ id: Int) -> Creature? { world.creatures.first { $0.id == id } }

    private func endAll() {
        for s in sessions.values { world.endJob(s.creatureID) }
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
