import AppKit
import EventKit
import GremletsCore

// The Focus Garden, daily care and the "real life" reactions (music, meetings, bedtime): the app-side pieces.
// The rules live in GremletsCore (FocusGarden.swift, DailyCare.swift, Teamwork.swift); this file stores them,
// draws the planter and watches the Mac.

/// Saved state plus the session in progress.
final class FocusGardenModel {
    private let gardenKey = "focusGarden.v1", careKey = "dailyCare.v1"
    private(set) var garden = FocusGarden()
    private(set) var care = DailyCare()
    private(set) var run: FocusRun?
    /// True once the current distraction has lasted long enough to count (a quick glance doesn't).
    private(set) var waiting = false
    /// Bumped whenever something visible changes, so the renderer only redraws then.
    private(set) var version = 0

    static let graceSeconds = 8.0

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: gardenKey), let g = try? JSONDecoder().decode(FocusGarden.self, from: data) { garden = g }
        if let data = d.data(forKey: careKey), let c = try? JSONDecoder().decode(DailyCare.self, from: data) { care = c }
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(garden) { d.set(data, forKey: gardenKey) }
        if let data = try? JSONEncoder().encode(care) { d.set(data, forKey: careKey) }
        version += 1
    }

    static var today: String { BondStore.dayKey() }
    static var yesterday: String { BondStore.dayKey(Date().addingTimeInterval(-86_400)) }
    static var hour: Int { Calendar.current.component(.hour, from: Date()) }

    // MARK: Focus sessions

    func begin(minutes: Double) {
        run = FocusRun(minutes: minutes, kind: garden.nextKind(seed: Int(Date().timeIntervalSince1970 / 7)))
        waiting = false
        version += 1
    }

    /// Advances the run. Returns +1 when a distraction starts counting, -1 when you come back, 0 otherwise.
    func advance(_ dt: Double, distracted: Bool) -> Int {
        guard var r = run else { return 0 }
        let stageBefore = r.stage
        _ = r.advance(dt, distracted: distracted)
        run = r
        if r.stage != stageBefore { version += 1 }
        if !waiting, r.currentDistraction >= FocusGardenModel.graceSeconds { waiting = true; version += 1; return 1 }
        if waiting, !r.isDistracted { waiting = false; version += 1; return -1 }
        return 0
    }

    /// The session ended (the break started, or it was stopped). Plants what it grew, if it grew anything.
    @discardableResult
    func finish(minFocusSeconds: Double = 0) -> FocusPlant? {
        defer { run = nil; waiting = false; version += 1 }
        guard let r = run, r.focused >= minFocusSeconds else { return nil }
        let p = r.harvest(day: FocusGardenModel.today)
        garden.add(p)
        save()
        return p
    }

    // MARK: Care

    func water() { garden.lastWatered = FocusGardenModel.today; save() }
    var thirsty: Bool { garden.thirsty(today: FocusGardenModel.today, hour: FocusGardenModel.hour) }
    var hungry: Bool { care.hungry(today: FocusGardenModel.today, hour: FocusGardenModel.hour) }
    var streak: Int { care.streak(today: FocusGardenModel.today, yesterday: FocusGardenModel.yesterday) }

    /// A snack was given. Returns the streak milestone it hit, if any.
    func fed() -> Int? {
        let m = care.feed(today: FocusGardenModel.today, yesterday: FocusGardenModel.yesterday)
        save()
        return m
    }

    static let plantNames = ["daisy", "tulip", "sunflower", "fern", "mushroom", "little pine"]

    var statusJSON: String {
        let plants = garden.plants.map { #"{"kind":"\#(FocusGardenModel.plantNames[$0.kind])","stage":\#($0.stage),"day":"\#($0.day)","minutes":\#($0.minutes)}"# }.joined(separator: ",")
        let r = run.map { #"{"stage":\#($0.stage),"focusedMin":\#(Int($0.focused / 60)),"plannedMin":\#(Int($0.planned / 60)),"waiting":\#(waiting)}"# } ?? "null"
        return #"{"ok":true,"plants":[\#(plants)],"total":\#(garden.total),"thirsty":\#(thirsty),"watered":"\#(garden.lastWatered ?? "")","run":\#(r),"fedToday":\#(care.fedToday(FocusGardenModel.today)),"hungry":\#(hungry),"streak":\#(streak),"best":\#(care.best)}"#
    }
}

// MARK: - Art

enum FocusGardenArt {
    static let slot = 9, pad = 4
    static var width: Int { pad * 2 + slot * FocusGarden.capacity }
    static let height = 19

    /// The planter: finished plants left to right, the growing one (if any) in the next pot.
    static func planter(_ plants: [FocusPlant], growing: (kind: Int, stage: Int, droop: Bool)?, thirsty: Bool) -> CGImage {
        var cv = PixelCanvas(width, height)
        // A wooden box with a light rim, and soil along the top.
        cv.rect(1, 0, width - 2, 4, 0x8A5A35)
        for x in stride(from: 3, to: width - 3, by: 6) { cv.rect(x, 1, 1, 2, 0x7A4C2C) }
        cv.rect(0, 3, width, 1, 0xB07A4A)
        cv.rect(1, 4, width - 2, 1, thirsty ? 0x8A6A4A : 0x5A3A22)
        var shown = plants.suffix(growing == nil ? FocusGarden.capacity : FocusGarden.capacity - 1).map { ($0.kind, $0.stage, thirsty) }
        if let g = growing { shown.append((g.kind, g.stage, g.droop)) }
        for (i, p) in shown.enumerated() {
            plant(&cv, pad + i * slot + slot / 2, 5, kind: p.0, stage: p.1, droop: p.2)
        }
        if let g = growing {   // a little marker under the pot that's growing right now
            let x = pad + (shown.count - 1) * slot + slot / 2
            cv.set(x - 1, 1, 0xF2D27A); cv.set(x, 1, 0xF2D27A); cv.set(x + 1, 1, 0xF2D27A)
            _ = g
        }
        cv.outline(0.6)
        return cv.image
    }

    private static func plant(_ cv: inout PixelCanvas, _ x: Int, _ base: Int, kind: Int, stage: Int, droop: Bool) {
        let green: UInt32 = droop ? 0x8A9A4A : 0x5E9E46, leaf: UInt32 = droop ? 0x9AAA5A : 0x7FCB5A
        if stage <= 0 {   // a seed in the soil
            cv.set(x, base, 0xC9A15A); return
        }
        if kind == 4 {   // mushroom: grows a stalk and a cap instead of leaves
            let h = [0, 1, 2, 3, 4][stage]
            cv.rect(x, base, 1, h, 0xF3E8D2)
            let w = [0, 3, 3, 5, 7][stage], top = base + h - (droop ? 1 : 0)
            cv.rect(x - w / 2, top, w, 2, 0xE0453A); cv.rect(x - w / 2 + 1, top + 2, max(1, w - 2), 1, 0xE0453A)
            if stage >= 3 { cv.set(x - 1, top + 1, 0xFFFFFF); cv.set(x + 1, top + 2, 0xFFFFFF) }
            return
        }
        if kind == 5 {   // little pine: tiers of needles
            cv.rect(x, base, 1, 1 + stage / 2, 0x6B4428)
            for t in 0..<stage {
                let w = max(1, (stage - t) * 2 - 1), y = base + 1 + t * 2
                cv.rect(x - w / 2 + (droop && t == stage - 1 ? 1 : 0), y, w, 2, t % 2 == 0 ? green : leaf)
            }
            return
        }
        let h = [0, 2, 4, 6, kind == 2 ? 9 : 7][stage]
        for y in 0..<h {
            let lean = droop && y > h / 2 ? 1 : 0
            cv.set(x + lean, base + y, green)
        }
        let top = base + h, tx = x + (droop ? 1 : 0), ty = top - (droop ? 1 : 0)
        cv.set(x - 1, base + 1, leaf); cv.set(x + 1, base + min(h - 1, 2), leaf)
        if stage >= 2 { cv.set(x - 1, base + 3, leaf); cv.set(x - 2, base + 3, leaf) }
        if kind == 3 {   // fern: fronds all the way up
            for y in stride(from: base + 2, to: top, by: 2) { cv.set(x - 1, y, leaf); cv.set(x + 1, y + 1, leaf); if stage >= 3 { cv.set(x - 2, y + 1, green); cv.set(x + 2, y, green) } }
            return
        }
        switch stage {
        case 3:   // a bud
            cv.set(tx, ty, [0xF6EFDF, 0xE0453A, 0xF2C230, 0, 0, 0][kind]); cv.set(tx, ty - 1, leaf)
        case 4:
            switch kind {
            case 0:   // daisy
                for (dx, dy) in [(-1, 0), (1, 0), (0, 1), (0, -1)] { cv.set(tx + dx, ty + dy, 0xFFFFFF) }
                cv.set(tx, ty, 0xF2C230)
            case 1:   // tulip
                cv.rect(tx - 1, ty - 1, 3, 2, 0xE0453A); cv.set(tx - 1, ty + 1, 0xE0453A); cv.set(tx + 1, ty + 1, 0xE0453A); cv.set(tx, ty + 1, 0xF27BA0)
            default:  // sunflower
                for dy in -2...2 { for dx in -2...2 where abs(dx) + abs(dy) <= 3 && !(abs(dx) == 2 && abs(dy) == 2) { cv.set(tx + dx, ty + dy, (dx + dy) % 2 == 0 ? 0xF2C230 : 0xF5D36A) } }
                cv.rect(tx - 1, ty - 1, 2, 2, 0x7A4A1A)
            }
        default: break
        }
    }
}

// MARK: - Renderer

/// Draws the planter in the bottom-left corner of the main screen, on the floor moss.
final class FocusGardenRenderer {
    unowned let overlay: OverlayController
    let world: World
    weak var model: FocusGardenModel?
    private var layer: CALayer?
    private var key = ""

    init(overlay: OverlayController, world: World) { self.overlay = overlay; self.world = world }

    func rebuild() { layer?.removeFromSuperlayer(); layer = nil; key = "" }

    /// The planter's middle, in world coordinates (nil when there's nothing to show).
    var anchor: Vec2? {
        guard let m = model, !m.garden.plants.isEmpty || m.run != nil,
              let floor = world.surfaces.first(where: { $0.kind == .floor && $0.ownerID == -1 }) else { return nil }
        let w = Double(FocusGardenArt.width) * artScale
        return Vec2(floor.minX + 18 + w / 2, floor.y)
    }

    func render() {
        let screens = overlay.screenRefs
        guard let m = model, let a = anchor, !screens.isEmpty else { layer?.removeFromSuperlayer(); layer = nil; key = ""; return }
        let si = overlay.screenIndexFor(a)
        let l = layer ?? {
            let l = CALayer()
            l.magnificationFilter = .nearest
            l.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.zPosition = 1.35   // in front of the floor moss (1.3)
            let pop = CAKeyframeAnimation(keyPath: "transform.scale"); pop.values = [0.1, 1.1, 0.96, 1]; pop.duration = 0.6
            l.add(pop, forKey: "pop")
            return l
        }()
        if l.superlayer !== screens[si].root { l.removeFromSuperlayer(); screens[si].root.addSublayer(l) }
        l.contentsScale = screens[si].scale
        layer = l
        let thirsty = m.thirsty
        let k = "\(m.version)-\(thirsty)"
        if k != key {
            let growing = m.run.map { (kind: $0.kind, stage: $0.stage, droop: m.waiting) }
            let img = FocusGardenArt.planter(m.garden.plants, growing: growing, thirsty: thirsty)
            l.contents = img
            l.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            key = k
        }
        let o = screens[si].frame.origin
        l.position = CGPoint(x: (a.x - o.x).rounded(), y: (a.y - o.y).rounded())
    }

    /// A little celebration over the planter (a new plant, a watering).
    func burst(_ images: [CGImage]) {
        guard let a = anchor else { return }
        let screens = overlay.screenRefs
        let si = overlay.screenIndexFor(a), o = screens[si].frame.origin
        overlay.burst(images, si: si, at: CGPoint(x: a.x - o.x, y: a.y - o.y + 30), count: 8, dx: -80...80, dy: 10...60, duration: 1.1)
    }
}

// MARK: - Watching the Mac

enum RealLife {
    /// Music is coming out of a music app (Music, Spotify, TIDAL, Deezer…). No permission needed.
    static let musicApps: Set<String> = ["com.apple.Music", "com.spotify.client", "com.tidal.desktop", "com.deezer.deezer-desktop", "com.amazon.music"]

    static func musicPlaying() -> Bool {
        let running = NSWorkspace.shared.runningApplications.filter { musicApps.contains($0.bundleIdentifier ?? "") }
        guard !running.isEmpty else { return false }
        return running.contains { SystemSignals.isPlayingAudio(pid: $0.processIdentifier) }
    }

    /// The frontmost app and (when Accessibility is allowed) its window's title, for spotting distractions.
    static func frontmost() -> (bundleID: String?, title: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return (nil, nil) }
        var title: String?
        if AXIsProcessTrusted() {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &win) == .success, let w = win {
                var t: CFTypeRef?
                if AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &t) == .success { title = t as? String }
            }
        }
        return (app.bundleIdentifier, title)
    }
}

/// Opt-in: a heads-up a few minutes before a calendar event starts (reads only start times and titles, on this Mac).
final class MeetingWatcher {
    private let store = EKEventStore()
    private(set) var granted = false
    private var told: Set<String> = []
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "care.meetings") }
        set { UserDefaults.standard.set(newValue, forKey: "care.meetings"); if newValue { requestAccess() } }
    }

    init() { if enabled { requestAccess() } }

    func requestAccess() {
        let done: (Bool, Error?) -> Void = { [weak self] ok, _ in DispatchQueue.main.async { self?.granted = ok } }
        if #available(macOS 14.0, *) { store.requestFullAccessToEvents(completion: done) } else { store.requestAccess(to: .event, completion: done) }
    }

    /// The title of an event starting within `minutes` that hasn't been announced yet.
    func upcoming(minutes: Double = 5) -> String? {
        guard enabled, granted else { return nil }
        let now = Date()
        let pred = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(minutes * 60 + 30), calendars: nil)
        for e in store.events(matching: pred) where !e.isAllDay && e.startDate > now && e.startDate.timeIntervalSince(now) <= minutes * 60 {
            let id = (e.eventIdentifier ?? e.title ?? "") + "\(e.startDate.timeIntervalSince1970)"
            guard !told.contains(id) else { continue }
            told.insert(id)
            let t = (e.title ?? "Meeting").trimmingCharacters(in: .whitespaces)
            return t.count > 28 ? String(t.prefix(27)) + "…" : t
        }
        return nil
    }
}
