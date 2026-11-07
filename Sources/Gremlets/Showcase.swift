import AppKit
import GremletsCore

/// `gremlet demo`: a forty-second scripted Claude session on the front window, so you can record what Gremlets do
/// while Claude works without waiting for a real session to go through every beat. A Gremlet comes to the window,
/// the project's bonsai takes root on its top edge, edits place blocks and leaves, ivy creeps along the frame and
/// mossy ledges grow out of its side, two helpers arrive for the subagents, a failed test brings a storm, a passing
/// one a rainbow, the finished task puts a flower on the tree, and when the session ends the building moves down
/// to the village and the tree to the nursery.
///
/// Nothing sticks: the grove, village and bonsai book are restored when the show is over.
final class Showcase {
    private let world: World
    private let buddy: ClaudeBuddy
    private var timer: Timer?
    private var steps: [(at: Double, run: () -> Void)] = []
    private var began: CFTimeInterval = 0
    private var savedGrove: Data?
    private var savedBook: BonsaiBook?
    private(set) var running = false
    var onFinish: () -> Void = {}

    init(world: World, buddy: ClaudeBuddy) { self.world = world; self.buddy = buddy }

    /// The front window with room above it for a tree, as (id, frame in y-up points).
    static func stage(preferring pid: Int32? = nil) -> WindowInfo? {
        let wins = WindowTracker.snapshot()
        let screens = WindowTracker.screens()
        func fits(_ w: WindowInfo) -> Bool {
            guard w.frame.w >= 420, w.frame.h >= 200,
                  let scr = screens.first(where: { w.frame.minX + w.frame.w / 2 >= $0.minX && w.frame.minX + w.frame.w / 2 < $0.maxX }) else { return false }
            return scr.maxY - w.frame.maxY >= 140 && w.frame.minX - scr.minX >= 60 && scr.maxX - w.frame.maxX >= 60
        }
        if let pid, let id = ProcessTree.frontWindow(forDescendant: pid), let w = wins.first(where: { $0.id == id && fits($0) }) { return w }
        return wins.first(where: fits)
    }

    /// Starts the show. Returns the screen region worth recording (top-left based points, for `screencapture -R`).
    func start(seconds: Double = 42, pid: Int32? = nil) -> CGRect? {
        guard !running, let w = Showcase.stage(preferring: pid) else { return nil }
        running = true
        savedGrove = world.grove.encoded()
        savedBook = world.bonsaiBook
        world.workClockScale = 70   // ivy covers the window in a quarter of a minute instead of a quarter of an hour
        // An established tree with a few sessions behind it, so what grows during the show is visible.
        var tree = Bonsai(project: "Gremlets", now: Date().timeIntervalSince1970 - 86400 * 12)
        for (n, e) in [38, 27, 16, 9].enumerated() {
            _ = tree.startSession("seed\(n)", now: tree.firstSeen + Double(n) * 3600)
            tree.branches[n].edits = e
            tree.branches[n].blooms = n == 0 ? 3 : 1
        }
        tree.branches[0].fruit = 2
        tree.endSession()
        world.seedBonsai(tree)
        steps.removeAll()
        let session = "showcase-\(Int(Date().timeIntervalSince1970))"
        func send(_ at: Double, _ event: String, _ extra: [String: String] = [:]) {
            steps.append((at, { [weak self] in
                var q = ["event": event, "session": session, "project": "Gremlets", "window": String(w.id)]
                for (k, v) in extra { q[k] = v }
                _ = self?.buddy.handle(q)
            }))
        }
        send(0, "start")
        var t = 6.0   // the Gremlet needs a moment to get to the window
        for n in 0..<30 {
            send(t, "tool", ["tool": n % 9 == 4 ? "Read" : "Edit"])
            t += 0.5
        }
        send(8.2, "tool", ["tool": "Bash"])
        send(10.0, "tool", ["tool": "Task"])
        send(14.0, "tool", ["tool": "WebFetch"])
        send(15.5, "tool", ["tool": "Task"])
        send(17.0, "tool", ["tool": "TodoWrite"])
        send(20.5, "toolfail", ["tool": "Bash"])
        send(22.8, "toolfail", ["tool": "Bash", "kind": "test"])
        send(26.0, "helperdone")
        send(28.5, "tool", ["tool": "Bash", "kind": "test"])
        send(31.0, "done")
        send(32.5, "helperdone")
        send(max(35, seconds - 7), "end")
        steps.append((seconds, { [weak self] in self?.finish() }))
        began = CACurrentMediaTime()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        // Record the window's top half and the air above it, where it all happens.
        let primary = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var r = CGRect(x: w.frame.minX - 110, y: Double(primary.maxY) - w.frame.maxY - 320, width: w.frame.w + 220, height: 320 + min(w.frame.h, 360))
        // Keep the region on the main display (screencapture wants top-left based points).
        let bounds = CGRect(x: primary.minX, y: 0, width: primary.width, height: primary.height)
        r = r.intersection(bounds)
        return r.isNull ? nil : r
    }

    private func tick() {
        let now = CACurrentMediaTime() - began
        let due = steps.filter { $0.at <= now }
        steps.removeAll { $0.at <= now }
        for s in due { s.run() }
    }

    func finish() {
        guard running else { return }
        running = false
        timer?.invalidate(); timer = nil
        steps.removeAll()
        world.workClockScale = 1
        if let d = savedGrove, let g = Grove.decode(d) { world.loadGrove(g) }
        if let b = savedBook { world.loadBonsai(b) }
        savedGrove = nil; savedBook = nil
        onFinish()
    }
}
