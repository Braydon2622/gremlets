import AppKit
import Carbon.HIToolbox
import ServiceManagement
import GremletsCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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

    // Companion features.
    private let bonds = BondStore()
    private let focus = FocusTimer()
    private var control: ControlServer?
    private var lastHousekeeping = CACurrentMediaTime()
    private var lastTitle: String? = ""
    private var remindersOn: Bool {
        get { UserDefaults.standard.bool(forKey: "reminders") }
        set { UserDefaults.standard.set(newValue, forKey: "reminders") }
    }
    private var lastReminder = Date()
    /// Big events (boss fights, meteor showers, festivals) on or off.
    private var epicEvents: Bool {
        get { UserDefaults.standard.object(forKey: "events.epic") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "events.epic") }
    }
    private let groveKey = "grove.v1"
    private var nextReminderIsWater = true

    // Ownership: NFT holders keep their Gremlets; everyone else can try any Gremlet in a demo.
    private var access = Access(tokens: [:], gatingEnabled: false)
    private var wallet: WalletLink?
    private var demoNotice: String?

    // Presence: hide on calls / boss key, nap while you're away, calmer on Low Power Mode.
    private var presence = PresenceTracker()
    private var manuallyHidden = false
    private var hideHotKey: HotKey?
    private let focusLog = FocusLogStore()
    private let phone = PhoneLink()
    private let icons = DesktopIcons()
    private let companion = CompanionAI()
    private var lastMorning = UserDefaults.standard.string(forKey: "companion.lastMorning") ?? ""
    private var lastEvening = UserDefaults.standard.string(forKey: "companion.lastEvening") ?? ""
    private lazy var buddy: ClaudeBuddy = {
        let b = ClaudeBuddy(world: world, overlay: overlay)
        b.onChange = { [weak self] in self?.rebuildMenu() }
        return b
    }()
    private var hideDuringCalls: Bool {
        get { UserDefaults.standard.object(forKey: "hideDuringCalls") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hideDuringCalls") }
    }

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
        overlay.onGardenChange = { [weak self] in self?.rebuildMenu() }
        refreshEnvironment()
        world.loadGrove(UserDefaults.standard.data(forKey: groveKey).flatMap(Grove.decode) ?? Grove())
        setUpAccess()
        restoreRoster()
        setUpCompanion()
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
        if now - lastHousekeeping >= 1 { housekeeping(elapsed: now - lastHousekeeping); lastHousekeeping = now }
        guard !paused, !presence.isHidden else {
            if presence.isHidden { schedule(rate: 2) }   // nothing on screen: just keep an ear out for "show"
            return
        }

        // Window polling is the most expensive thing we do, so its rate adapts: fast while a window that a
        // creature stands on is moving (so riding a dragged window is smooth), slow otherwise.
        let movingRecently = now - lastWindowChange < 0.6
        // Window frames matter most for creatures standing on a window (they ride it); otherwise they only
        // affect jump targets and landings, which tolerate a few hundred ms of staleness.
        let anyoneOnWindow = world.creatures.contains { ($0.groundOwner ?? -1) >= 0 || $0.activity == .airborne || $0.job?.windowID != nil }
        let pollInterval = movingRecently ? 1.0 / 60 : (anyoneOnWindow ? 0.1 : 0.35)
        if now - lastWindowPoll >= pollInterval { refreshEnvironment() }

        world.cursor = Vec2(Double(NSEvent.mouseLocation.x), Double(NSEvent.mouseLocation.y))
        world.step(dt)
        let events = world.drainEvents()
        trackBond(events)
        overlay.handle(events)
        let groveEvents = world.drainGroveEvents()
        overlay.fx.handle(groveEvents)
        if groveEvents.contains(where: { if case .fed = $0 { return true }; if case .wish = $0 { return true }; return false }) { saveGrove() }
        overlay.fx.handle(world.drainSpectacleEvents())
        overlay.render()
        overlay.updateClickThrough()
        perf.tick(now: now, rate: currentRate)

        var wanted = movingRecently || overlay.isInteracting ? 60 : world.desiredTickRate
        if overlay.hasBubbles { wanted = max(wanted, 30) }
        if world.spectacle != nil || !world.playBalls.isEmpty { wanted = 60 }
        if overlay.hasProps { wanted = max(wanted, 12) }   // creations follow their window   // keep a speech bubble following its Gremlet smoothly
        if let cap = presence.maxTickRate(presenceInput()), !overlay.isInteracting { wanted = min(wanted, cap) }
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
        if icons.enabled {
            icons.updateVisibility(windows: wins)
            world.iconSurfaces = icons.surfaces(excluding: overlay.liftedIcons)
        } else if !world.iconSurfaces.isEmpty {
            world.iconSurfaces = []
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
        ids = ids.filter { species[$0] != nil && !phone.onPhone.contains($0) }
        if ids.isEmpty {
            // First launch: your own Gremlets if you have any, otherwise the three starters as a demo.
            let owned = access.ownedSpecies.filter { species[$0] != nil }.sorted()
            ids = owned.isEmpty ? ["kindlet", "flurrie", "dandelet"].filter { species[$0] != nil } : Array(owned.prefix(3))
        }
        if ids.isEmpty, let first = species.keys.sorted().first { ids = [first] }
        ids = access.filterRestore(ids)
        for id in ids {
            world.spawn(species[id]!.info)
            if access.isDemo(id) { access.noteDemoAdded(now: Date().timeIntervalSince1970) }
        }
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

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        // Refresh in place so countdowns are current (swapping the menu object while it opens isn't allowed).
        menu.removeAllItems()
        for item in buildMenuItems() { menu.addItem(item) }
    }

    private func rebuildMenu() {
        guard statusItem != nil else { return }      // callbacks can fire during launch, before the menu bar item exists
        let menu = NSMenu()
        menu.delegate = self
        for item in buildMenuItems() { menu.addItem(item) }
        statusItem.menu = menu
    }

    private func buildMenuItems() -> [NSMenuItem] {
        let menu = NSMenu()
        var headerText = "Gremlets: \(world.creatures.count) out"
        switch presence.hidden {
        case .call?: headerText = "Gremlets: hiding while you're on a call"
        case .manual?: headerText = "Gremlets: hidden (⌃⌥G to bring them back)"
        case nil: if presence.isAway { headerText += " · napping until you're back" }
        }
        let header = NSMenuItem(title: headerText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let add = NSMenuItem(title: "Add Gremlet", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        // Group the 50 species by family so the menu stays browsable.
        let families: [(String, String)] = [("animal", "Animals"), ("insect", "Insects & Bugs"), ("dragon", "Dragons"),
                                            ("dino", "Dinosaurs"), ("mythic", "Mythical Beasts"), ("spirit", "Spirits"), ("guardian", "Guardians")]
        let known = Set(families.map(\.0))
        for (key, title) in families + [("", "Custom")] {
            let members = species.values
                .filter { key.isEmpty ? !known.contains($0.info.family) : $0.info.family == key }
                .sorted { $0.info.name < $1.info.name }
            guard !members.isEmpty else { continue }
            let famItem = NSMenuItem(title: "\(title) (\(members.count))", action: nil, keyEquivalent: "")
            let famMenu = NSMenu()
            for sp in members {
                let kind = access.kind(sp.info.id)
                let item = NSMenuItem(title: "\(sp.info.name)  ·  \(sp.info.element)\(kind == .demo ? "  ·  demo" : "")", action: #selector(addCreature(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = sp.info.id
                item.image = NSImage(cgImage: sp.frames[0], size: NSSize(width: 22, height: 22))
                item.toolTip = sp.info.blurb
                if kind == .owned { item.state = .on; item.toolTip = "Yours (you hold this Gremlet). " + sp.info.blurb }
                famMenu.addItem(item)
            }
            famItem.submenu = famMenu
            sub.addItem(famItem)
        }
        sub.addItem(.separator())
        let party = NSMenuItem(title: access.gatingEnabled ? "Surprise Party (random)" : "Surprise Party (5 random)", action: #selector(addRandomParty), keyEquivalent: "")
        party.target = self
        sub.addItem(party)
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

        // Your Gremlets: bond with each one that's out.
        if !world.creatures.isEmpty {
            let mine = NSMenuItem(title: "Your Gremlets", action: nil, keyEquivalent: "")
            let msub = NSMenu()
            var seen = Set<String>()
            for c in world.creatures where seen.insert(c.species.id).inserted {
                let b = bonds.bond(c.species.id)
                let hearts = String(repeating: "♥", count: b.level + 1) + String(repeating: "♡", count: 4 - b.level)
                let item = NSMenuItem(title: "\(c.species.name)   \(hearts)  \(b.name)", action: nil, keyEquivalent: "")
                if let img = species[c.species.id]?.frames.first { item.image = NSImage(cgImage: img, size: NSSize(width: 22, height: 22)) }
                let detail = NSMenu()
                let hours = b.hoursTogether < 1 ? "\(Int(b.hoursTogether * 60)) min" : String(format: "%.1f h", b.hoursTogether)
                var lines = ["Together \(b.daysTogether) day\(b.daysTogether == 1 ? "" : "s") · \(hours)",
                             "Petted \(b.pets)× · Poked \(b.pokes)×"]
                if let next = b.pointsToNext { lines.append("\(Int(next.rounded(.up))) points to \(Bond.levelNames[b.level + 1])") }
                else { lines.append("The closest bond there is") }
                if b.level >= 2 { lines.append("Shows off its signature move when petted") }
                for l in lines { let li = NSMenuItem(title: l, action: nil, keyEquivalent: ""); li.isEnabled = false; detail.addItem(li) }
                item.submenu = detail
                msub.addItem(item)
            }
            let tip = NSMenuItem(title: "Pet them (rub the cursor over them) to grow your bond", action: nil, keyEquivalent: "")
            tip.isEnabled = false
            msub.addItem(.separator()); msub.addItem(tip)
            mine.submenu = msub
            menu.addItem(mine)
        }
        menu.addItem(.separator())
        for item in walletMenuItems() { menu.addItem(item) }
        menu.addItem(.separator())

        // Focus buddy.
        if let label = focus.label {
            let state = NSMenuItem(title: focus.isFocusing ? "Focusing · \(label) left" : label + " left", action: nil, keyEquivalent: "")
            state.isEnabled = false
            menu.addItem(state)
            let stop = NSMenuItem(title: "Stop Focus Timer", action: #selector(stopFocus), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        } else {
            for m in [25, 50] {
                let f = NSMenuItem(title: "Focus for \(m) min", action: #selector(startFocus(_:)), keyEquivalent: "")
                f.target = self
                f.representedObject = m
                menu.addItem(f)
            }
        }
        let mins = Int(focusLog.todayMinutes.rounded()), streak = focusLog.streak
        if mins > 0 || streak > 0 {
            let line = "Today: \(mins) min focused" + (streak > 0 ? " · \(streak)-day streak" : "")
            let st = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            st.isEnabled = false
            st.toolTip = "Gremlets that keep you company through a focus session grow closer to you."
            menu.addItem(st)
        }
        let ic = NSMenuItem(title: "Play with Desktop Icons", action: #selector(toggleIcons), keyEquivalent: "")
        ic.target = self
        ic.state = icons.enabled ? .on : .off
        ic.toolTip = icons.lastError ?? "Gremlets sit on your desktop icons, make them boing, and borrow them for a bit. Nothing on your desktop is moved. macOS will ask once to let Gremlets read icon positions from Finder."
        menu.addItem(ic)
        if icons.enabled, let err = icons.lastError {
            let e = NSMenuItem(title: "  ⚠︎ " + err, action: nil, keyEquivalent: ""); e.isEnabled = false
            menu.addItem(e)
        }
        let chat = NSMenuItem(title: "Chat with a Gremlet…", action: #selector(openChatMenu), keyEquivalent: "")
        chat.target = self
        chat.toolTip = "Talk with any of your Gremlets (or double-click one). Replies come from Claude when you add an API key."
        menu.addItem(chat)
        let bud = NSMenuItem(title: "Claude Buddy", action: #selector(toggleBuddy), keyEquivalent: "")
        bud.target = self
        bud.state = buddy.enabled ? .on : .off
        bud.toolTip = "While Claude Code works, a Gremlet works next to its window, and tells you when Claude is done or needs you."
        menu.addItem(bud)
        if let made = buddy.log.todaySummary {
            let m = NSMenuItem(title: "Made with Claude today: \(made)", action: nil, keyEquivalent: "")
            m.isEnabled = false
            menu.addItem(m)
        }
        menu.addItem(groveMenuItem())
        // The seed book: which plants you've grown so far.
        let book = overlay.seedBook
        // Phone: pair, send a Gremlet over, see who's visiting.
        if !phone.isPaired {
            let pairItem = NSMenuItem(title: "Pair with Phone…", action: #selector(pairPhone), keyEquivalent: "")
            pairItem.target = self
            pairItem.toolTip = "Gremlets can hop over to your iPhone's web habitat and come back with what they grew."
            menu.addItem(pairItem)
        } else {
            let ph = NSMenuItem(title: phone.connected ? "Phone · linked" : "Phone · connecting…", action: nil, keyEquivalent: "")
            let phMenu = NSMenu()
            if !world.creatures.isEmpty {
                let send = NSMenuItem(title: "Send to Phone", action: nil, keyEquivalent: "")
                let sendMenu = NSMenu()
                for c in world.creatures {
                    let it = NSMenuItem(title: c.species.name, action: #selector(sendToPhone(_:)), keyEquivalent: "")
                    it.target = self
                    it.representedObject = c.id
                    sendMenu.addItem(it)
                }
                send.submenu = sendMenu
                phMenu.addItem(send)
            }
            let away = phone.onPhone.compactMap { species[$0]?.info.name }
            if !away.isEmpty {
                let it = NSMenuItem(title: "On your phone: " + away.joined(separator: ", "), action: nil, keyEquivalent: "")
                it.isEnabled = false
                phMenu.addItem(it)
            }
            let show = NSMenuItem(title: "Show Pairing Code…", action: #selector(pairPhone), keyEquivalent: "")
            show.target = self
            phMenu.addItem(show)
            phMenu.addItem(.separator())
            let unlink = NSMenuItem(title: "Unlink Phone", action: #selector(unlinkPhone), keyEquivalent: "")
            unlink.target = self
            phMenu.addItem(unlink)
            ph.submenu = phMenu
            menu.addItem(ph)
        }
        let sb = NSMenuItem(title: "Seed Book (\(book.found)/\(PlantKind.allCases.count))", action: nil, keyEquivalent: "")
        let sbMenu = NSMenu()
        for rarity in 0...4 {
            if rarity > 0 { sbMenu.addItem(.separator()) }
            for k in PlantKind.allCases where k.rarity == rarity {
                let n = book.count(k), gold = book.goldenCount(k)
                let when = k.seasonName.map { " · \($0) only" } ?? ""
                var line = n > 0 ? "\(k.name) · \(k.rarityName) · grown \(n)×" : "??? · \(k.rarityName)\(when)"
                if gold > 0 { line += " · ✨ \(gold) golden" }
                let it = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                it.isEnabled = false
                sbMenu.addItem(it)
            }
        }
        sbMenu.addItem(.separator())
        for text in ["Rare seeds turn up more often during focus sessions", "Some plants only grow in their season, or at night",
                     "Legend says poking a busy gardener can dig something up"] {
            let tip = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            tip.isEnabled = false
            sbMenu.addItem(tip)
        }
        sb.submenu = sbMenu
        menu.addItem(sb)
        if world.wishes > 0 {
            let wi = NSMenuItem(title: "✨ A wish is waiting: the next seed will be special", action: nil, keyEquivalent: "")
            wi.isEnabled = false
            menu.addItem(wi)
        }
        if book.today > 0 {
            let t = NSMenuItem(title: "Grown today: \(book.today) plant\(book.today == 1 ? "" : "s")", action: nil, keyEquivalent: "")
            t.isEnabled = false
            menu.addItem(t)
        }
        if overlay.keepsakeCount > 0 {
            let g = NSMenuItem(title: "Clear Garden (\(overlay.keepsakeCount))", action: #selector(clearGarden), keyEquivalent: "")
            g.target = self
            g.toolTip = "Flowers and paintings your Gremlets finished, along the bottom of the screen."
            menu.addItem(g)
        }
        let rem = NSMenuItem(title: "Water & Stretch Reminders", action: #selector(toggleReminders), keyEquivalent: "")
        rem.target = self
        rem.state = remindersOn ? .on : .off
        menu.addItem(rem)
        let cli = NSMenuItem(title: "Copy Terminal Command Setup", action: #selector(copyCLISetup), keyEquivalent: "")
        cli.target = self
        cli.toolTip = "Lets scripts and test runners make your Gremlets react (gremlet pass / fail / done)."
        menu.addItem(cli)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: paused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        let hide = NSMenuItem(title: manuallyHidden ? "Show Gremlets" : "Hide Gremlets", action: #selector(toggleHidden), keyEquivalent: "g")
        hide.keyEquivalentModifierMask = [.control, .option]
        hide.target = self
        hide.toolTip = "Works anywhere with ⌃⌥G"
        menu.addItem(hide)
        let calls = NSMenuItem(title: "Hide During Calls", action: #selector(toggleHideDuringCalls), keyEquivalent: "")
        calls.target = self
        calls.state = hideDuringCalls ? .on : .off
        calls.toolTip = "Slip away whenever an app uses your camera or microphone (Zoom, Meet, FaceTime…), so they never end up in a screen share."
        menu.addItem(calls)
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
        let items = menu.items
        menu.removeAllItems()
        return items
    }

    @objc private func addCreature(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let sp = species[id] else { return }
        guard admit(id) else { return }
        // Drop in from the top of the screen the cursor is on.
        let m = NSEvent.mouseLocation
        let scr = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main
        let vf = scr?.visibleFrame ?? .zero
        let x = min(max(Double(m.x), vf.minX + 60), vf.maxX - 60)
        world.spawn(sp.info, at: Vec2(x, Double(vf.maxY) - sp.info.pointSize.y - 4))
        bonds.markSeenToday(id)
        world.setBond(bonds.bond(id).strength, forSpecies: id)
        saveRoster()
        rebuildMenu()
        schedule(rate: 60)
    }

    func applicationWillTerminate(_ notification: Notification) { bonds.save() }

    @objc private func addRandomParty() {
        var picks: [LoadedSpecies] = []
        var out = world.creatures.map(\.species.id)
        let now = Date().timeIntervalSince1970
        // Yours first, then demos while there's room.
        let pool = species.values.shuffled().sorted { !access.isDemo($0.info.id) && access.isDemo($1.info.id) }
        for sp in pool where picks.count < 5 && access.canAdd(sp.info.id, out: out, now: now) == .ok {
            picks.append(sp); out.append(sp.info.id)
            if access.isDemo(sp.info.id) { access.noteDemoAdded(now: now) }
        }
        if picks.isEmpty { _ = admit(species.values.first { access.isDemo($0.info.id) }?.info.id ?? ""); return }
        let m = NSEvent.mouseLocation
        let vf = (NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main)?.visibleFrame ?? .zero
        for (i, sp) in picks.enumerated() {
            let x = Double(vf.minX) + Double(vf.width) * (0.2 + 0.15 * Double(i))
            world.spawn(sp.info, at: Vec2(x, Double(vf.maxY) - sp.info.pointSize.y - 4))
            bonds.markSeenToday(sp.info.id)
            world.setBond(bonds.bond(sp.info.id).strength, forSpecies: sp.info.id)
        }
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

    // MARK: Ownership & demo

    private func setUpAccess() {
        let args = CommandLine.arguments, env = ProcessInfo.processInfo.environment
        let deployment = Deployment.load()
        var policy = DemoPolicy()
        if let s = env["GREMLETS_DEMO_SECONDS"].flatMap(Double.init) { policy.sessionSeconds = s }   // for testing
        // Gating starts once the collection is on testnet (deployment.json present). Until then this is a preview
        // build with everything unlocked. --visitor previews demo mode; --unlock-all is a developer override.
        let gated = (deployment != nil || args.contains("--visitor")) && !args.contains("--unlock-all")
        access = Access(tokens: Resources.tokens(), ownership: args.contains("--visitor") ? Ownership() : OwnershipStore.load(),
                        policy: policy, gatingEnabled: gated)
        guard let deployment, gated else { return }
        let link = WalletLink(deployment: deployment, tokenIDs: access.tokens.keys.sorted())
        link.onOwnership = { [weak self] o in
            guard let self else { return }
            let before = self.access.ownedSpecies
            self.access.ownership = o
            OwnershipStore.save(o)
            let gained = self.access.ownedSpecies.subtracting(before)
            for c in self.world.creatures where gained.contains(c.species.id) { self.overlay.bondLevelUp(c) }  // hearts: it's yours now
            self.rebuildMenu()
        }
        link.onStateChange = { [weak self] in self?.rebuildMenu() }
        wallet = link
        link.refresh(access.ownership)
    }

    /// Checks the demo rules before a Gremlet comes out; explains kindly if it can't.
    private func admit(_ id: String) -> Bool {
        let now = Date().timeIntervalSince1970
        switch access.canAdd(id, out: world.creatures.map(\.species.id), now: now) {
        case .ok:
            if access.isDemo(id) { access.noteDemoAdded(now: now); demoNotice = nil }
            return true
        case .demoFull(let max):
            let alert = NSAlert()
            alert.messageText = "Demo Gremlets: \(max) at a time"
            alert.informativeText = "Send one of your demo Gremlets home to try another.\n\nGremlets you own stay out as long as you like. Link your wallet from the menu bar (Connect Wallet…), or visit all 50 in the web habitat."
            alert.runModal()
        case .cooldown(let left):
            let alert = NSAlert()
            alert.messageText = "The demo Gremlets are resting"
            alert.informativeText = "You can start another demo in \(Int(left / 60) + 1) min."
            alert.runModal()
        }
        return false
    }

    /// Demo time's up: each demo Gremlet waves goodbye, then heads home.
    private func endDemoSession() {
        let leaving = world.creatures.filter { access.isDemo($0.species.id) }.map(\.id)
        guard !leaving.isEmpty else { return }
        for id in leaving { world.sayGoodbye(id) }
        schedule(rate: 60)
        demoNotice = "Demo over: they waved goodbye. Start another any time."
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self else { return }
            for id in leaving where self.world.creatures.contains(where: { $0.id == id && self.access.isDemo($0.species.id) }) {
                self.world.remove(id)
            }
            self.overlay.render()
            self.saveRoster()
            self.rebuildMenu()
        }
    }

    private func walletMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        func info(_ t: String) { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; items.append(i) }
        func action(_ t: String, _ sel: Selector) { let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; items.append(i) }

        guard access.gatingEnabled else {
            info("Preview build: all Gremlets unlocked")
            return items
        }
        let now = Date().timeIntervalSince1970
        if let left = access.secondsLeft(now: now) {
            let demoOut = world.creatures.filter { access.isDemo($0.species.id) }.count
            info(String(format: "Demo: %d:%02d left · %d/%d out", Int(left) / 60, Int(left) % 60, demoOut, access.policy.maxOut))
        } else if let n = demoNotice {
            info(n)
        }
        if let addr = access.ownership.address {
            let n = access.ownedSpecies.count
            info("Wallet \(Ethereum.shortAddress(addr)) · owns \(n) Gremlet\(n == 1 ? "" : "s")")
            if wallet != nil { action("Check Ownership Again", #selector(recheckOwnership)) }
            action("Unlink Wallet", #selector(unlinkWallet))
        } else if wallet != nil {
            action("Connect Wallet…", #selector(connectWallet))
            items.last?.toolTip = "Prove you hold Gremlets with a free signature in your browser wallet. No transaction, no seed phrase."
        } else {
            info("Visitor preview (no collection configured)")
        }
        switch wallet?.state {
        case .waiting?: info("Waiting for your browser wallet…")
        case .checking?: info("Checking ownership on Base Sepolia…")
        case .failed(let m)?: info(m)
        default: break
        }
        return items
    }

    @objc private func connectWallet() { wallet?.begin() }

    @objc private func recheckOwnership() { wallet?.refresh(access.ownership, force: true) }

    @objc private func unlinkWallet() {
        access.ownership = Ownership()
        OwnershipStore.save(access.ownership)
        // Anything that was yours is now a demo; trim to the demo limit right away.
        let demos = world.creatures.filter { access.isDemo($0.species.id) }
        for c in demos.dropFirst(access.policy.maxOut) { world.remove(c.id) }
        if !demos.isEmpty { access.noteDemoAdded(now: Date().timeIntervalSince1970) }
        overlay.render()
        saveRoster()
        rebuildMenu()
    }

    // MARK: Companion

    private func setUpCompanion() {
        for c in world.creatures {
            bonds.markSeenToday(c.species.id)
            world.setBond(bonds.bond(c.species.id).strength, forSpecies: c.species.id)
        }
        bonds.save()
        focus.onFocusStart = { [weak self] in self?.world.focusMode = true; self?.rebuildMenu() }
        focus.onBreakStart = { [weak self] in
            guard let self else { return }
            // A finished session: log it, and every Gremlet that kept you company grows a little closer.
            self.focusLog.record(minutes: self.focus.focusMinutes)
            for id in Set(self.world.creatures.map(\.species.id)) {
                let before = self.bonds.bond(id).level
                self.bonds.addFocusSession(id)
                let after = self.bonds.bond(id)
                if after.level > before, let c = self.world.creatures.first(where: { $0.species.id == id }) {
                    self.world.setBond(after.strength, forSpecies: id); self.overlay.bondLevelUp(c)
                }
            }
            self.bonds.save()
            self.world.receive(.pass); self.schedule(rate: 60); self.rebuildMenu()
        }
        focus.onBreakEnd = { [weak self] in self?.world.receive(.done); self?.rebuildMenu() }
        let server = ControlServer { [weak self] method, path, query in
            guard let self else { return (404, "{}") }
            return self.handleControl(method: method, path: path, query: query)
        }
        server.pages["/connect"] = { [weak self] in self?.wallet?.page() ?? "<p>Wallet linking isn't set up in this build.</p>" }
        server.pages["/pair"] = { [weak self] in self?.phone.pairPage() ?? "" }
        server.pages["/chat"] = { [weak self] in self?.chatPage() ?? "" }
        overlay.onDoubleClick = { [weak self] id in self?.openChat(with: id) }
        overlay.icons = icons
        icons.onChange = { [weak self] in self?.rebuildMenu() }
        icons.refresh()
        phone.onArrive = { [weak self] arrival in self?.arriveFromPhone(arrival) }
        phone.onStatus = { [weak self] in self?.rebuildMenu() }
        if phone.isPaired { phone.start() }
        server.start()
        control = server
        // Boss key: ⌃⌥G hides/shows every Gremlet instantly.
        hideHotKey = HotKey(keyCode: kVK_ANSI_G, modifiers: controlKey | optionKey, id: 1) { [weak self] in self?.toggleHidden() }
        if CommandLine.arguments.contains("--focus-demo") { focus.breakMinutes = 0.25; focus.startFocus(minutes: 0.25) }
    }

    private func handleControl(method: String, path: String, query: [String: String]) -> (Int, String) {
        let name = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if name == "wallet/test-begin", method == "POST", ProcessInfo.processInfo.environment["GREMLETS_WALLET_TEST"] == "1", let w = wallet {
            return (200, w.beginForTest())
        }
        if name == "wallet/status" { return (200, wallet?.statusJSON() ?? #"{"state":"idle"}"#) }
        if name == "wallet/proof" {
            guard method == "POST" else { return (405, #"{"ok":false,"error":"use POST"}"#) }
            return wallet?.handleProof(query) ?? (404, #"{"ok":false,"error":"wallet linking isn't set up in this build"}"#)
        }
        if name == "status" {
            let ids = world.creatures.map { "\"\($0.species.id)\"" }.joined(separator: ",")
            let primaryTop = Double(NSScreen.screens.first?.frame.maxY ?? 0)
            let busy = world.creatures.compactMap { c -> String? in
                guard let j = c.job else { return nil }
                // Top-left based screen coordinates, the same as `screencapture -R`.
                return #"{"gremlet":"\#(c.species.id)","craft":"\#(j.craft.rawValue)","shelf":\#(j.shelfSide != nil),"x":\#(Int(c.pos.x)),"y":\#(Int(primaryTop - c.pos.y))}"#
            }.joined(separator: ",")
            let f = focus.label.map { "\"\($0)\"" } ?? "null"
            let h = presence.hidden.map { "\"\($0.rawValue)\"" } ?? "null"
            return (200, #"{"ok":true,"gremlets":[\#(ids)],"focus":\#(f),"paused":\#(paused),"hidden":\#(h),"away":\#(presence.isAway),"focusToday":\#(Int(focusLog.todayMinutes)),"streak":\#(focusLog.streak),"busy":[\#(busy)]}"#)
        }
        guard method == "POST" else { return (405, #"{"ok":false,"error":"use POST"}"#) }
        switch name {
        case "focus":
            let minutes = Double(query["minutes"] ?? "") ?? 25
            focus.startFocus(minutes: min(max(minutes, 1), 180))
        case "hide", "show":
            manuallyHidden = name == "hide"
            updatePresence()
            return (200, #"{"ok":true}"#)
        case "unfocus":
            focus.stop(); world.focusMode = false; rebuildMenu()
        case "chat/state":
            return (200, chatState(query["name"]))
        case "chat/send":
            guard let c = chatTarget(query["name"]), let raw = query["_body"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return (400, #"{"ok":false,"error":"say something"}"#)
            }
            sendChat(String(raw.prefix(800)), to: c)
            return (202, #"{"ok":true,"pending":true}"#)
        case "chat/key":
            companion.setKey(query["_body"]?.trimmingCharacters(in: .whitespacesAndNewlines))
            return (200, #"{"ok":true,"ai":\#(companion.hasKey)}"#)
        case "chat/nick":
            guard let c = chatTarget(query["name"]) else { return (404, "{}") }
            companion.setNickname(c.species.id, query["_body"])
            rebuildMenu()
            return (200, #"{"ok":true}"#)
        case "chat/me":
            companion.userName = query["_body"].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return (200, #"{"ok":true}"#)
        case "chat/forget":
            if let c = chatTarget(query["name"]) { companion.forget(c.species.id) }
            return (200, #"{"ok":true}"#)
        case "phone/pair":
            phone.pair()
            rebuildMenu()
            return (200, #"{"ok":true,"url":"\#(phone.pairURL ?? "")"}"#)
        case "phone/send":
            guard phone.isPaired else { return (409, #"{"ok":false,"error":"not paired: run gremlet pair first"}"#) }
            let want = (query["name"] ?? "").lowercased()
            guard let c = world.creatures.first(where: { $0.species.id == want || $0.species.name.lowercased() == want }) ?? (want.isEmpty ? world.creatures.first : nil) else {
                return (404, #"{"ok":false,"error":"no Gremlet by that name is out"}"#)
            }
            let item = NSMenuItem(); item.representedObject = c.id
            sendToPhone(item)
            return (200, #"{"ok":true}"#)
        case "event":
            let k = SpectacleKind(rawValue: query["kind"] ?? "boss") ?? .boss
            guard world.startEvent(k) else { return (409, #"{"ok":false,"error":"an event is already running"}"#) }
            schedule(rate: 60)
            return (200, #"{"ok":true}"#)
        case "grove/feed":
            let n = min(50, max(1, Int(query["tasks"] ?? "") ?? 1))
            for _ in 0..<n { world.feedGrove() }
            saveGrove()
            return (200, #"{"ok":true,"tasks":\#(world.grove.tasks)}"#)
        case "wish":   // shh: a little easter egg, not in the help text
            wishOnAStar()
            return (200, #"{"ok":true,"wish":"granted"}"#)
        case "hobby":
            let craft = query["craft"].flatMap { Craft(rawValue: $0) }
            let shelf: Bool? = query["shelf"].map { $0 == "1" }
            let style = query["style"].flatMap { ShelfStyle(rawValue: $0) }
            guard world.startHobbyNearCursor(craft: craft, onWindow: shelf, style: style) else {
                return (409, #"{"ok":false,"error":"no free Gremlet on the floor or a window"}"#)
            }
        case "claude":
            let r = buddy.handle(query)
            schedule(rate: 60)
            return r
        case "say":
            guard let text = SpeechText.clean(query["text"]) else { return (400, #"{"ok":false,"error":"text is required"}"#) }
            let seconds = min(max(Double(query["seconds"] ?? "") ?? 8, 2), 60)
            guard let id = world.say() else { return (409, #"{"ok":false,"error":"no Gremlets are out"}"#) }
            overlay.handle(world.drainEvents())
            overlay.render()
            overlay.showBubble(text, on: id, seconds: seconds)
        default:
            guard let signal = Signal(rawValue: name) else { return (404, #"{"ok":false,"error":"unknown action"}"#) }
            world.receive(signal)
        }
        schedule(rate: 60)
        return (200, #"{"ok":true}"#)
    }

    /// Bond bookkeeping from world events; celebrates when a bond levels up.
    private func trackBond(_ events: [WorldEvent]) {
        for e in events {
            let id: Int, petted: Bool
            switch e {
            case .petted(let i): id = i; petted = true
            case .poked(let i): id = i; petted = false
            default: continue
            }
            guard let c = world.creatures.first(where: { $0.id == id }) else { continue }
            let before = bonds.bond(c.species.id).level
            if petted { bonds.addPet(c.species.id) } else { bonds.addPoke(c.species.id) }
            let after = bonds.bond(c.species.id)
            if after.level > before {
                world.setBond(after.strength, forSpecies: c.species.id)
                overlay.bondLevelUp(c)
                rebuildMenu()
            }
        }
    }

    /// Once a second: menu bar timer text, focus phases, reminders, time-together and late-night sleepiness.
    private func presenceInput() -> PresenceInput {
        PresenceInput(now: CACurrentMediaTime(), manuallyHidden: manuallyHidden, inCall: inCall,
                      hideDuringCalls: hideDuringCalls, idleSeconds: idleSeconds, lowPower: lowPower)
    }
    private var inCall = false, idleSeconds = 0.0, lowPower = false

    /// Reads camera/mic/idle/power once a second and applies hide / show / away / welcome-back.
    private func updatePresence() {
        inCall = hideDuringCalls && (SystemSignals.cameraInUse() || SystemSignals.microphoneInUse())
        idleSeconds = SystemSignals.idleSeconds()
        world.userActive = idleSeconds < 90 && !presence.isHidden
        lowPower = SystemSignals.lowPowerMode
        for e in presence.update(presenceInput()) {
            switch e {
            case .hide:
                overlay.hidden = true
            case .show:
                overlay.hidden = false
                lastTick = CACurrentMediaTime()       // don't simulate the time they were away in one giant step
                refreshEnvironment()
                schedule(rate: 30)
            case .away:
                world.receive(.sleep)
            case .welcomeBack:
                world.receive(.wake)
                schedule(rate: 60)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.world.receive(.wave) }
            }
            rebuildMenu()
        }
    }

    @objc private func toggleHidden() {
        manuallyHidden.toggle()
        updatePresence()
    }

    @objc private func toggleHideDuringCalls() {
        hideDuringCalls.toggle()
        updatePresence()
        rebuildMenu()
    }

    private func saveGrove() {
        if let d = world.grove.encoded() { UserDefaults.standard.set(d, forKey: groveKey) }
    }

    private func housekeeping(elapsed: Double) {
        updatePresence()
        world.eventsAllowed = epicEvents && !paused && !presence.isHidden && !focus.isFocusing
        if Int(CACurrentMediaTime()) % 60 == 0 {
            world.checkWishwillow(day: Int(Date().timeIntervalSinceReferenceDate / 86400))
            saveGrove()
        }
        // Clear nights bring the odd meteor shower (about one every couple of hours of evening work).
        if world.isNight && world.userActive && world.spectacle == nil && Double.random(in: 0..<1) < elapsed / (100 * 60) {
            world.requestEvent(.meteors)
        }
        focus.update()
        buddy.tick()
        dailyMoments()
        if icons.enabled && Int(Date().timeIntervalSince1970) % 15 == 0 { icons.refresh() }
        // Seasons and night-time for the garden; now and then a shooting star at night grants a wish.
        let cal = Calendar.current, nowDate = Date()
        world.month = cal.component(.month, from: nowDate)
        world.isNight = PropArt.isEvening
        if world.isNight && world.userActive && !presence.isHidden && Double.random(in: 0..<1) < elapsed / (40 * 60) {
            wishOnAStar()
        }
        let title = focus.label
        if title != lastTitle {
            statusItem.button?.title = title.map { " " + $0 } ?? ""
            statusItem.button?.imagePosition = .imageLeading
            if (title == nil) != (lastTitle == nil) { rebuildMenu() }
            lastTitle = title
        }
        if !paused && !presence.isHidden && !presence.isAway {
            for id in Set(world.creatures.map(\.species.id)) { bonds.addTime(id, seconds: elapsed) }
        }
        if remindersOn && !focus.isFocusing && Date().timeIntervalSince(lastReminder) > 45 * 60 {
            world.receive(nextReminderIsWater ? .water : .stretch)
            nextReminderIsWater.toggle()
            lastReminder = Date()
            schedule(rate: 60)
        }
        let out = world.creatures.map(\.species.id)
        if access.tick(out: out, now: Date().timeIntervalSince1970) { endDemoSession() }
        if Int(CACurrentMediaTime()) % 600 == 0 { wallet?.refresh(access.ownership) }
        let hour = Calendar.current.component(.hour, from: Date())
        world.sleepyFactor = (hour >= 23 || hour < 5) ? 3 : 1     // gentle "time to log off" hint
        if Int(CACurrentMediaTime()) % 60 == 0 {
            for id in Set(world.creatures.map(\.species.id)) { bonds.markSeenToday(id) }
            bonds.save()
        }
    }

    @objc private func startFocus(_ sender: NSMenuItem) {
        focus.startFocus(minutes: Double(sender.representedObject as? Int ?? 25))
    }

    @objc private func stopFocus() {
        focus.stop()
        world.focusMode = false
        world.receive(.wake)
        rebuildMenu()
    }

    // MARK: AI companion

    private func dayStats() -> CompanionAI.Day {
        var d = CompanionAI.Day()
        d.focusMinutes = Int(focusLog.todayMinutes.rounded())
        d.streak = focusLog.streak
        d.plantsToday = overlay.seedBook.today
        d.seedsFound = overlay.seedBook.found
        d.seedsTotal = PlantKind.allCases.count
        d.claudeToday = buddy.log.todayCount
        d.gremletsOut = world.creatures.map { companion.nickname($0.species.id) ?? $0.species.name }
        return d
    }

    private func chatTarget(_ name: String?) -> Creature? {
        let want = (name ?? "").lowercased()
        return world.creatures.first { $0.species.id == want } ?? (want.isEmpty ? world.creatures.first : nil)
    }

    /// The chat page talks to a Gremlet; the reply also pops up in a speech bubble on the desktop, and any action
    /// it asks for (focus, garden, dance...) happens.
    private func sendChat(_ text: String, to c: Creature) {
        guard let sp = species[c.species.id] else { return }
        let bond = bonds.bond(c.species.id)
        world.receive(.wave)
        companion.reply(to: text, as: sp.info, bond: bond, day: dayStats()) { [weak self] reply, action in
            guard let self, let c = self.world.creatures.first(where: { $0.species.id == sp.info.id }) else { return }
            self.overlay.showBubble(String(reply.prefix(118)) + (reply.count > 118 ? "…" : ""), on: c.id, seconds: 7)
            if let action { self.perform(action, by: c) }
            self.bonds.addPet(c.species.id)        // talking counts as quality time
            self.schedule(rate: 60)
        }
    }

    private func perform(_ action: CompanionAI.Action, by c: Creature) {
        switch action {
        case .focus: focus.startFocus(minutes: 25); rebuildMenu()
        case .garden: _ = world.startHobby(c) || world.startHobbyNearCursor()
        case .dance: world.receive(.dance)
        case .wave: world.receive(.wave)
        case .hide: manuallyHidden = true; updatePresence(); rebuildMenu()
        case .nap: world.receive(.sleep)
        case .wish: wishOnAStar()
        case .water: for w in world.workers { _ = world.helpGarden(workerID: w.id) }
        }
    }

    private func openChat(with id: Int) {
        let name = world.creatures.first { $0.id == id }?.species.id ?? ""
        if let url = URL(string: "http://127.0.0.1:\(ControlServer.defaultPort)/chat#\(name)") { NSWorkspace.shared.open(url) }
    }

    @objc private func openChatMenu() { openChat(with: world.creatures.first?.id ?? 0) }

    /// Good morning the first time you're around each day; a recap of the day in the evening.
    private func dailyMoments() {
        guard world.userActive, !presence.isHidden, let c = world.creatures.filter({ $0.isGrounded && $0.job == nil }).randomElement(),
              let sp = species[c.species.id] else { return }
        let today = BondStore.dayKey()
        let hour = Calendar.current.component(.hour, from: Date())
        var kind: String?
        if lastMorning != today && hour >= 5 && hour < 12 { kind = "morning"; lastMorning = today; UserDefaults.standard.set(today, forKey: "companion.lastMorning") }
        else if lastEvening != today && hour >= 18 { kind = "evening"; lastEvening = today; UserDefaults.standard.set(today, forKey: "companion.lastEvening") }
        guard let kind else { return }
        let id = c.id
        companion.moment(kind, as: sp.info, bond: bonds.bond(sp.info.id), day: dayStats()) { [weak self] line in
            self?.world.receive(.wave)
            self?.overlay.showBubble(line, on: id, seconds: 8)
        }
    }

    /// gremlets://say?text=…, gremlets://focus?minutes=50, gremlets://hobby, gremlets://chat?name=kindlet,
    /// gremlets://send?name=kindlet, gremlets://wish, gremlets://dance … (for Shortcuts, Raycast, Alfred, scripts).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "gremlets" {
            let action = (url.host ?? "") + url.path
            var q: [String: String] = [:]
            for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { q[item.name] = item.value.map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 } }
            switch action {
            case "chat": openChat(with: chatTarget(q["name"])?.id ?? 0)
            case "pair": pairPhone()
            case "send": _ = handleControl(method: "POST", path: "/phone/send", query: q)
            default: _ = handleControl(method: "POST", path: "/" + action, query: q)
            }
        }
    }

    /// A shooting star: the next seed planted will be something special.
    private func wishOnAStar() {
        overlay.shootingStar()
        world.makeWish()
        if let c = world.creatures.filter({ $0.isGrounded }).randomElement() {
            overlay.showBubble("A shooting star! Make a wish ✨", on: c.id, seconds: 4)
        }
        schedule(rate: 60)
        rebuildMenu()
    }

    @objc private func pairPhone() {
        phone.pair()
        if let url = URL(string: "http://127.0.0.1:\(ControlServer.defaultPort)/pair") { NSWorkspace.shared.open(url) }
        rebuildMenu()
    }

    @objc private func unlinkPhone() {
        phone.unpair()
        rebuildMenu()
    }

    /// Into the portal it goes; it pops out on the phone.
    @objc private func sendToPhone(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int, let c = world.creatures.first(where: { $0.id == id }) else { return }
        let speciesID = c.species.id
        world.endJob(id)
        overlay.showBubble("Off to your phone! 📱", on: id, seconds: 1.5)
        overlay.portal(at: Vec2(c.pos.x, c.pos.y + c.size.y * 0.45))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.world.remove(id)
            self.overlay.render()
            self.phone.sendToPhone(species: speciesID)
            self.saveRoster()
            self.rebuildMenu()
        }
    }

    /// Back from the phone: out of a portal near the bottom of the screen, with whatever it grew there.
    private func arriveFromPhone(_ a: PhoneLink.Arrival) {
        guard let sp = species[a.species] else { return }
        phone.onPhone = phone.onPhone.filter { $0 != a.species }
        let screens = WindowTracker.screens()
        guard let main = screens.first else { return }
        let x = main.maxX - 160
        let at = Vec2(x, main.minY + 60)
        overlay.portal(at: at)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let c = self.world.spawn(sp.info, at: Vec2(x, main.minY + 20))
            self.saveRoster()
            self.overlay.render()
            let grew = a.harvest.map { ($0.golden ? "golden " : "") + $0.kind.name.lowercased() }
            let text = grew.isEmpty ? "I'm back! 📱→💻" : "I'm back! Grew: " + grew.prefix(4).joined(separator: ", ") + (grew.count > 4 ? "…" : "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.overlay.showBubble(text, on: c.id, seconds: 6) }
            self.overlay.receiveHarvest(a.harvest, nearX: x)
            self.schedule(rate: 60)
            self.rebuildMenu()
        }
    }

    private func chatState(_ name: String?) -> String {
        func esc(_ s: String) -> String {
            let d = try? JSONSerialization.data(withJSONObject: [s])
            return String(String(data: d ?? Data(), encoding: .utf8)?.dropFirst().dropLast() ?? "\"\"")
        }
        let target = chatTarget(name)
        let gremlets = world.creatures.map { c -> String in
            let b = bonds.bond(c.species.id)
            let busy = c.job != nil ? "gardening" : c.isAsleep ? "napping" : "around"
            return #"{"id":\#(esc(c.species.id)),"name":\#(esc(c.species.name)),"nick":\#(esc(companion.nickname(c.species.id) ?? "")),"bond":\#(esc(b.name)),"element":\#(esc(c.species.element)),"family":\#(esc(c.species.family)),"doing":\#(esc(busy))}"#
        }.joined(separator: ",")
        let history = target.map { companion.history($0.species.id).suffix(40).map { #"{"role":\#(esc($0.role)),"text":\#(esc($0.text))}"# }.joined(separator: ",") } ?? ""
        let day = dayStats()
        return #"{"ai":\#(companion.hasKey),"problem":\#(esc(companion.lastProblem ?? "")),"me":\#(esc(companion.userName ?? "")),"target":\#(esc(target?.species.id ?? "")),"gremlets":[\#(gremlets)],"history":[\#(history)],"day":{"focus":\#(day.focusMinutes),"streak":\#(day.streak),"plants":\#(day.plantsToday),"seeds":\#(day.seedsFound),"seedsTotal":\#(day.seedsTotal),"claude":\#(day.claudeToday)}}"#
    }

    /// The chat page (127.0.0.1 only). Portraits are the Gremlets' own first sprite frames.
    private func chatPage() -> String {
        var portraits: [String] = []
        for c in world.creatures {
            guard let sp = species[c.species.id], let f = sp.frames.first,
                  let png = NSBitmapImageRep(cgImage: f).representation(using: .png, properties: [:]) else { continue }
            portraits.append("\"\(c.species.id)\":\"data:image/png;base64,\(png.base64EncodedString())\"")
        }
        return ChatPage.html(portraitsJSON: "{" + portraits.joined(separator: ",") + "}")
    }

    /// The Grove: each plant's level and what it does, how many Claude tasks until the next plot, and the events.
    private func groveMenuItem() -> NSMenuItem {
        let g = world.grove
        let item = NSMenuItem(title: "Grove · \(g.tasks) Claude task\(g.tasks == 1 ? "" : "s")", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        func info(_ t: String, tip: String? = nil) { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; i.toolTip = tip; sub.addItem(i) }
        info("Every Claude task you finish grows every plant here.")
        sub.addItem(.separator())
        for p in g.plants {
            let bar = String(repeating: "■", count: Int((p.levelProgress * 6).rounded())) + String(repeating: "□", count: 6 - Int((p.levelProgress * 6).rounded()))
            info("\(p.kind.name)  Lv \(p.level)  \(p.level < 5 ? bar : "MAX")", tip: p.kind.power.prefix(1).uppercased() + p.kind.power.dropFirst())
        }
        if let next = g.nextUnlock {
            let k = GroveKind.allCases[min(g.plants.count, GroveKind.allCases.count - 1)]
            info("Next plot (\(k.name)) in \(next - g.tasks) more task\(next - g.tasks == 1 ? "" : "s")")
        }
        sub.addItem(.separator())
        func action(_ t: String, _ sel: Selector, tag: Int = 0, tip: String? = nil) {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; i.tag = tag; i.toolTip = tip; sub.addItem(i)
        }
        action("Summon the Stormwyrm", #selector(summonEvent(_:)), tag: 0, tip: "A boss fight! Gremlets throw sunberries, bounce off the bouncecap and the snapjaw bites. Click it to help.")
        action("Start a Meteor Shower", #selector(summonEvent(_:)), tag: 1, tip: "Shooting stars drop star shards. Every shard the Gremlets catch grows the grove.")
        action("Bloom Festival", #selector(summonEvent(_:)), tag: 2)
        let epic = NSMenuItem(title: "Surprise Events", action: #selector(toggleEpic), keyEquivalent: "")
        epic.target = self
        epic.state = epicEvents ? .on : .off
        epic.toolTip = "Bosses show up every so often as Claude tasks pile up, meteor showers on some nights, festivals when a plant maxes out. Never during focus sessions or calls."
        sub.addItem(epic)
        item.submenu = sub
        return item
    }

    @objc private func summonEvent(_ sender: NSMenuItem) {
        let k: SpectacleKind = [.boss, .meteors, .festival][max(0, min(2, sender.tag))]
        world.startEvent(k)
        schedule(rate: 60)
    }

    @objc private func toggleEpic() { epicEvents.toggle(); rebuildMenu() }

    @objc private func clearGarden() {
        overlay.clearKeepsakes()
        rebuildMenu()
    }

    @objc private func toggleIcons() {
        icons.enabled.toggle()
        if icons.enabled { icons.refresh() }
        rebuildMenu()
    }

    @objc private func toggleBuddy() {
        buddy.enabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleReminders() {
        remindersOn.toggle()
        lastReminder = Date()
        rebuildMenu()
    }

    @objc private func copyCLISetup() {
        let repoScript = SpriteLibrary.builtInFolder?.deletingLastPathComponent().appendingPathComponent("scripts/gremlet").path
        let text = """
        # Gremlets terminal command. Paste into your shell config (~/.zshrc):
        gremlet() { curl -s -m 2 -X POST -H 'X-Gremlets: 1' "http://127.0.0.1:\(ControlServer.defaultPort)/$1" >/dev/null; }
        # Then:  npm test && gremlet pass || gremlet fail
        #        gremlet done  (after any long command)
        # Full version with `gremlet run <cmd>` and auto-react to long commands: \(repoScript ?? "scripts/gremlet in the Gremlets repo")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
