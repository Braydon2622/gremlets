import AppKit
import ServiceManagement
import GremletsCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var species: [String: LoadedSpecies] = [:]
    private let world = World()
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var currentRate: Double = 0
    private var lastTick = CACurrentMediaTime()
    private var lastWindowPoll: Double = 0
    private var lastWindowChange: Double = -10
    private var lastWindowSignature: [Int: Rect] = [:]
    private var paused = false
    private let perf = PerfMonitor(enabled: ProcessInfo.processInfo.environment["GREMLETS_PERF"] == "1")

    private let rosterKey = "roster"

    func applicationDidFinishLaunching(_ note: Notification) {
        species = SpriteLibrary.loadAll()
        guard !species.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Gremlet sprites found"
            alert.informativeText = "Expected sprite sheets in the app's Species folder or \(SpriteLibrary.userSpeciesFolder.path)."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        overlay = OverlayController(world: world, species: species)
        refreshEnvironment()
        restoreRoster()
        setUpMenuBar()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.overlay.rebuildScreens()
            self?.refreshEnvironment()
        }
        // Spaces switch: the visible windows change all at once, so re-read them right away.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshEnvironment()
        }
        schedule(rate: 60)
    }

    // MARK: Loop

    private func schedule(rate: Double) {
        guard rate != currentRate else { return }
        currentRate = rate
        timer?.invalidate()
        let t = Timer(timeInterval: 1 / rate, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2 / rate // let macOS coalesce wakeups to save power
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now
        guard !paused else { return }

        // Window polling is the most expensive thing we do, so its rate adapts: fast while a window that a
        // creature stands on is moving (so riding a dragged window is smooth), slow otherwise.
        let movingRecently = now - lastWindowChange < 0.6
        let pollInterval = movingRecently ? 1.0 / 60 : (world.desiredTickRate <= 8 ? 0.25 : 0.1)
        if now - lastWindowPoll >= pollInterval { refreshEnvironment() }

        world.cursor = Vec2(Double(NSEvent.mouseLocation.x), Double(NSEvent.mouseLocation.y))
        world.step(dt)
        overlay.handle(world.drainEvents())
        overlay.render()
        overlay.updateClickThrough()
        perf.tick(now: now, rate: currentRate)

        let wanted = movingRecently || overlay.isInteracting ? 60 : world.desiredTickRate
        schedule(rate: wanted)
    }

    private func refreshEnvironment() {
        lastWindowPoll = CACurrentMediaTime()
        let wins = WindowTracker.snapshot()
        var sig: [Int: Rect] = [:]
        for w in wins { sig[w.id] = w.frame }
        if sig != lastWindowSignature {
            // Only count it as "moving" if a window someone is standing on changed.
            let ridden = Set(world.creatures.compactMap { $0.groundOwner }.filter { $0 >= 0 })
            if ridden.contains(where: { lastWindowSignature[$0] != sig[$0] }) { lastWindowChange = lastWindowPoll }
            lastWindowSignature = sig
        }
        world.setEnvironment(screens: WindowTracker.screens(), windowsFrontToBack: wins)
    }

    // MARK: Roster

    private func restoreRoster() {
        let args = CommandLine.arguments
        var ids: [String]
        if let i = args.firstIndex(of: "--spawn"), i + 1 < args.count {
            ids = args[i + 1].split(separator: ",").map(String.init)
        } else {
            ids = UserDefaults.standard.stringArray(forKey: rosterKey) ?? []
        }
        ids = ids.filter { species[$0] != nil }
        if ids.isEmpty { ids = [species["kindlet"] != nil ? "kindlet" : species.keys.sorted()[0]] }
        for id in ids { world.spawn(species[id]!.info) }
        saveRoster()
    }

    private func saveRoster() {
        UserDefaults.standard.set(world.creatures.map(\.species.id), forKey: rosterKey)
    }

    // MARK: Menu bar

    private func setUpMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let sp = species["kindlet"] ?? species.values.first, let frame = sp.frames.first {
            let img = NSImage(cgImage: frame, size: NSSize(width: 20, height: 20))
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "G"
        }
        statusItem.button?.toolTip = "Gremlets"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Gremlets: \(world.creatures.count) out", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let add = NSMenuItem(title: "Add Gremlet", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for sp in species.values.sorted(by: { $0.info.name < $1.info.name }) {
            let item = NSMenuItem(title: "\(sp.info.name)  ·  \(sp.info.element)", action: #selector(addCreature(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sp.info.id
            item.image = NSImage(cgImage: sp.frames[0], size: NSSize(width: 18, height: 18))
            sub.addItem(item)
        }
        add.submenu = sub
        menu.addItem(add)

        if !world.creatures.isEmpty {
            let remove = NSMenuItem(title: "Send Home", action: nil, keyEquivalent: "")
            let rsub = NSMenu()
            for c in world.creatures {
                let item = NSMenuItem(title: "\(c.species.name) #\(c.id)", action: #selector(removeCreature(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = c.id
                rsub.addItem(item)
            }
            remove.submenu = rsub
            menu.addItem(remove)
        }

        let pause = NSMenuItem(title: paused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let folder = NSMenuItem(title: "Open Custom Sprites Folder…", action: #selector(openSpritesFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Gremlets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func addCreature(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let sp = species[id] else { return }
        // Drop in from the top of the screen the cursor is on.
        let m = NSEvent.mouseLocation
        let scr = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main
        let vf = scr?.visibleFrame ?? .zero
        let x = min(max(Double(m.x), vf.minX + 60), vf.maxX - 60)
        world.spawn(sp.info, at: Vec2(x, Double(vf.maxY) - sp.info.pointSize.y - 4))
        saveRoster()
        rebuildMenu()
        schedule(rate: 60)
    }

    @objc private func removeCreature(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int else { return }
        world.remove(id)
        overlay.render()
        saveRoster()
        rebuildMenu()
    }

    @objc private func togglePause() {
        paused.toggle()
        overlay.paused = paused
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "This works when Gremlets runs from Gremlets.app (not `swift run`).\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func openSpritesFolder() {
        let url = SpriteLibrary.userSpeciesFolder
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

/// Logs average CPU usage of this process (set GREMLETS_PERF=1). Used for the README's performance numbers.
final class PerfMonitor {
    private let enabled: Bool
    private var windowStart = CACurrentMediaTime()
    private var cpuStart = PerfMonitor.cpuSeconds()
    private var ticks = 0

    init(enabled: Bool) { self.enabled = enabled }

    static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }

    func tick(now: Double, rate: Double) {
        guard enabled else { return }
        ticks += 1
        if now - windowStart >= 10 {
            let cpu = PerfMonitor.cpuSeconds()
            let pct = (cpu - cpuStart) / (now - windowStart) * 100
            print(String(format: "[perf] cpu %.2f%%  ticks/s %.1f  rate %.0f Hz", pct, Double(ticks) / (now - windowStart), rate))
            fflush(stdout)
            windowStart = now; cpuStart = cpu; ticks = 0
        }
    }
}
