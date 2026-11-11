import Foundation

/// Life around the hanging home (the house under the notch, or on a Mac without one, the nest hut in the top-left
/// corner), busy with or without Claude:
///
/// - **The pantry.** A woven acorn hanging off the porch. Gremlets forage in the moss (seeds, berries, mushrooms)
///   and float home with what they find to stock it, a few at a time.
/// - **Supper.** Come evening, with something in the pantry, a couple of them float up to the porch and eat
///   together under the lantern.
/// - **The house grows** with Claude sessions *and* with the care they put into it (stocking the pantry, filling the
///   window box), so a Mac without Claude still sees it gain a balcony, a loft, a rooftop garden, and lights.
/// - **A bird** drops by now and then: it perches on the roof, a window top or a widget, the Gremlets nearby wave,
///   and sometimes it leaves a seed in the pantry. Bring the pointer near and it flies off.
/// - **Nudge it.** Rest the pointer on the hanging house and it swings on its ropes; anyone inside comes out onto
///   the porch to wave (hovering only: the top corners stay click-through).
public struct Bird: Equatable, Sendable {
    public enum State: Equatable, Sendable { case flyingIn, perched, leaving }
    public let id: Int
    public internal(set) var pos: Vec2
    var vel: Vec2 = .zero
    public internal(set) var state: State = .flyingIn
    /// Where it's landing (global) and what it's standing on (a window id, or one of the hanging places).
    let perch: Vec2
    let perchOwner: Int?
    var until = 0.0
    /// Brings a seed for the pantry (dropped on the roof as it lands at the house).
    let seed: Bool
    public internal(set) var facing: Double
    var greeted = false
    var hopAt = 0.0
    public var flapping: Bool { state != .perched }
}

public enum HomeEvent: Equatable, Sendable {
    /// Picked something up in the moss to take home.
    case foraged(Vec2, by: Int, what: String)
    /// Put it in the pantry.
    case stocked(Vec2, by: Int, what: String)
    case supper(Vec2, by: Int)
    case birdLanded(Vec2)
    case birdLeft(Vec2)
    case birdSeed(Vec2)
    /// The pointer nudged the hanging home (it swings; the renderer does the swaying).
    case nudged(Vec2)
    case cameOut(by: Int)
    /// The rain barrel (Homestead.swift): filled right up; a can drawn from it.
    case barrelFull(Vec2)
    case drewWater(Vec2, by: Int)
    /// The basket lift: waved down, climbed into, and arrived (at the porch, or down at the window top).
    case basketCalled(by: Int)
    case basketAboard(by: Int)
    case basketArrived(Vec2, by: Int, up: Bool)
    /// The vegetable patch (Porch.swift): sown, watered (from the rain barrel or not), ripe, picked.
    case sowed(Vec2, by: Int, what: String)
    case patchWatered(Vec2, by: Int, rain: Bool)
    case patchRipe(Vec2)
    case harvested(Vec2, by: Int, what: String)
    /// A postcard in the mailbox; read.
    case mailArrived(Vec2)
    case mailRead
    /// A lantern set out on the moss; taken in.
    case lanternHung(Vec2, by: Int)
    case lanternTaken(Vec2, by: Int)
    /// The bees brought something extra to a picking (Seasons.swift).
    case beeBonus(Vec2)
    /// The porch swept of leaves (or snow).
    case swept(Vec2, by: Int, snow: Bool)
    /// A firefly into the jar; the jar let go in the morning.
    case jarCaught(Vec2)
    case jarReleased(Vec2, count: Int)
    /// Seeds from a friend's screen for the patch.
    case seedGift(by: Int?, what: String)
}

extension World {
    public static let pantryMax = 6
    static let nestPorchHouse = -2

    public func drainHomeEvents() -> [HomeEvent] { defer { homeEvents = [] }; return homeEvents }

    /// The hanging home's porch: the house under the notch, or the nest hut in the top-left corner.
    public var homePorch: Surface? {
        if notchHomeShowing, let n = notchHome { return Surface(ownerID: World.notchPorchOwner, kind: .plant, y: n.porch.y, minX: n.porch.minX, maxX: n.porch.maxX) }
        guard !compact else { return nil }
        return topStructures.first { $0.kind == .nestHut }?.surface
    }

    /// Where a Gremlet stands to put something in the pantry (it hangs off the porch's far end).
    public var pantrySpot: Vec2? {
        guard let p = homePorch else { return nil }
        return Vec2(p.maxX - 12, p.y)
    }

    /// The nest hut's door (on its porch).
    var nestDoorX: Double? { topStructures.first { $0.kind == .nestHut }.map { $0.surface.minX + 22 } }

    /// The house grows as the Claude sessions add up, and with the care the Gremlets put into it: a balcony, a loft,
    /// a rooftop garden, and strings of lights.
    public var houseStage: Int {
        let sessions = bonsaiBook.trees.reduce(0) { $0 + $1.sessions }
        let points = Double(sessions) + Double(homeCare) / 3
        return points >= 80 ? 4 : points >= 40 ? 3 : points >= 15 ? 2 : points >= 5 ? 1 : 0
    }

    var localHour: Int { Int(((wallClock + Double(TimeZone.current.secondsFromGMT())).truncatingRemainder(dividingBy: 86_400)) / 3600) }

    /// Things to do for the home: forage for the pantry, and supper on the porch in the evening.
    func pantryChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !compact, isFree(c), c.isGrounded, !c.isAsleep, let porch = homePorch, let s = supportingSurface(for: c),
              sameScreen(c.pos, Vec2(porch.minX, porch.y)) else { return }
        if pantry < World.pantryMax, s.kind == .windowTop || s.kind == .floor, s.ownerID != porch.ownerID, clock >= nextForageAt {
            let x = (c.pos.x + rng.range(-160, 160)).clamped(s.minX + 14, s.maxX - 14)
            add("forage", ownDay ? 1.3 : 0.5) {
                self.nextForageAt = self.clock + self.rng.range(20, 50)
                self.startMossTask(c, .forage(x: x), walkTo: x)
            }
        }
        let evening = (17...21).contains(localHour)
        if evening, pantry >= 1, clock >= nextSupperAt, suppersTonight < 4,
           creatures.filter({ if case .supper? = $0.mossTask?.kind { return true }; return false }).count < 2 {
            add("supper", 2.4) { self.startSupper(c) }
        }
    }

    /// Both points on the same screen (the hanging home is on the main one; an iPad's Gremlets stay on the iPad).
    func sameScreen(_ a: Vec2, _ b: Vec2) -> Bool {
        guard let i = screens.firstIndex(where: { a.x >= $0.minX && a.x < $0.maxX }) else { return false }
        return b.x >= screens[i].minX && b.x < screens[i].maxX
    }

    func startSupper(_ c: Creature) {
        guard let porch = homePorch, let spot = pantrySpot else { return }
        nextSupperAt = clock + rng.range(40, 120)
        suppersTonight += 1
        let others = creatures.filter { if case .supper? = $0.mossTask?.kind { return true }; return false }.count
        let seat = (spot.x - 26 - Double(others) * 22).clamped(porch.minX + 10, porch.maxX - 10)
        c.mossTask = MossTask(kind: .supper(seat: seat), started: clock)
        if c.groundOwner == porch.ownerID { c.targetX = seat; c.set(.walk, duration: 10) }
        else { startFloat(c, to: Vec2(seat, porch.y), ride: .dandelion) }
    }

    /// Foraging in the moss: a crouch, something found, then home with it under a dandelion.
    func forageDecide(_ c: Creature, _ t: inout MossTask, x: Double, on s: Surface) {
        guard !compact else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
        if !t.acting {
            if abs(c.pos.x - x) > 6, clock - t.started < 15 { c.targetX = x; c.set(.walk, duration: 12); return }
            t.acting = true; c.mossTask = t
            c.workPose = "crouch"; c.set(.work, duration: rng.range(1.8, 2.8))
            return
        }
        guard let spot = pantrySpot, pantry < World.pantryMax else { c.mossTask = nil; c.set(.react, duration: c.animationLength(for: .react)); return }
        let what = s.kind == .floor ? ["acorn", "seeds", "mushroom"].randomElement(using: &rng)! : ["berries", "seeds", "mushroom"].randomElement(using: &rng)!
        homeEvents.append(.foraged(c.pos + Vec2(c.facing * 8, 6), by: c.id, what: what))
        c.carrying = what == "berries" || what == "seeds" ? "berries" : "mushroom"
        c.mossTask = MossTask(kind: .stock(what: what), started: clock)
        startFloat(c, to: spot, ride: .dandelion)
    }

    /// Home with it: into the pantry.
    func stockDecide(_ c: Creature, _ t: inout MossTask, what: String, on s: Surface) {
        guard !compact || s.ownerID == World.notchPorchOwner, let porch = homePorch, let spot = pantrySpot, s.ownerID == porch.ownerID else {
            // Didn't make it home (the house is tucked away): eat it instead.
            c.mossTask = nil; c.energy = min(1, c.energy + 0.15)
            c.set(.react, duration: c.animationLength(for: .react)); return
        }
        if !t.acting {
            if abs(c.pos.x - spot.x) > 6, clock - t.started < 25 { c.targetX = spot.x; c.set(.walk, duration: 10); return }
            t.acting = true; c.mossTask = t
            c.facing = 1
            c.workPose = "crouch"; c.set(.work, duration: 1.3)
            return
        }
        c.mossTask = nil
        c.carrying = nil
        pantry = min(World.pantryMax, pantry + 1)
        homeCare += 1
        homeEvents.append(.stocked(Vec2(spot.x + 8, spot.y - 10), by: c.id, what: what))
        c.set(.react, duration: c.animationLength(for: .react))
        // A rest on the porch, or back down under a leaf.
        c.driftDown = !isNight && rng.chance(0.7)
    }

    /// Supper on the porch: sit, eat, and a happy little moment.
    func supperDecide(_ c: Creature, _ t: inout MossTask, seat: Double, on s: Surface) {
        guard let porch = homePorch, s.ownerID == porch.ownerID else { c.mossTask = nil; c.set(.idle, duration: 0.5); return }
        if !t.acting {
            if abs(c.pos.x - seat) > 5, clock - t.started < 25 { c.targetX = seat; c.set(.walk, duration: 10); return }
            t.acting = true; c.mossTask = t
            c.facing = (pantrySpot?.x ?? seat) > c.pos.x ? 1 : -1
            if pantry > 0 { pantry -= 1 }
            c.carrying = "berries"
            c.workPose = "crouch"; c.set(.work, duration: rng.range(5, 8))
            homeEvents.append(.supper(c.pos, by: c.id))
            return
        }
        c.mossTask = nil
        c.carrying = nil
        c.energy = min(1, c.energy + 0.3)
        c.idleVariant = "look"; c.set(.idle, duration: rng.range(3, 6))
    }

    /// Into the nest hut for a nap (its door's on the porch), like the house under the notch.
    func goInsideNest(_ c: Creature) {
        c.homeHouse = World.nestPorchHouse
        c.homeUntil = clock + rng.range(isNight ? 120 : 40, isNight ? 300 : 120)
        lastHomeArrival = clock
        c.set(.sleep, duration: 9999)
    }

    public var insideNest: [Creature] { creatures.filter { $0.homeHouse == World.nestPorchHouse && $0.homeUntil != nil } }

    func nestChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !notchHomeShowing, let nest = topStructures.first(where: { $0.kind == .nestHut })?.surface, c.groundOwner == nest.ownerID,
              isFree(c), c.isGrounded, insideNest.count < 2, let door = nestDoorX else { return }
        add("goInside", (isNight || c.energy < 0.5) ? 2.0 : 0.6) {
            c.targetX = door; c.facing = door > c.pos.x ? 1 : -1
            c.groveTask = .nestHome
            c.set(.walk, duration: 10)
        }
    }

    // MARK: The pointer

    /// The hanging home's outline (global): resting the pointer here nudges it.
    public var homeRect: Rect? {
        if notchHomeShowing, let n = notchHome { return Rect(x: n.houseMinX - 4, y: n.houseBottom - 4, w: n.houseWidth + 30, h: n.houseHeight + 22) }
        guard !compact, let s = topStructures.first(where: { $0.kind == .nestHut })?.surface else { return nil }
        return Rect(x: s.minX - 8, y: s.y - 6, w: 114, h: 86)
    }

    /// Seconds since the pointer nudged the hanging home / the leaf swing.
    public var homeNudgeAge: Double { clock - homeNudgedAt }
    public var leafNudgeAge: Double { clock - leafNudgedAt }

    /// Hovering: the house swings (and calls whoever's inside out), the leaf swing rocks (and its rider whoops).
    func updateHover() {
        guard let cur = cursor, !compact else { homeHoverSince = nil; return }
        if let r = homeRect, r.contains(cur) {
            if let since = homeHoverSince { if clock - since > 0.45 { nudgeHome() } } else { homeHoverSince = clock }
        } else { homeHoverSince = nil }
        for (s, kind) in topStructures where kind == .leafSwing {
            guard cur.x > s.minX - 6, cur.x < s.maxX + 6, cur.y > s.y - 14, cur.y < s.y + 34, clock - leafNudgedAt > 3 else { continue }
            leafNudgedAt = clock
            homeEvents.append(.nudged(Vec2((s.minX + s.maxX) / 2, s.y)))
            for c in creatures where c.groundOwner == s.ownerID && c.isGrounded && !c.isAsleep && c.mossTask == nil {
                c.set(.react, duration: c.animationLength(for: .react))
            }
        }
    }

    /// The pointer is resting on the hanging home: it swings on its ropes, and anyone inside comes out to say hello.
    @discardableResult
    public func nudgeHome() -> Bool {
        guard clock >= nextNudgeAt, let porch = homePorch else { return false }
        nextNudgeAt = clock + 5
        homeNudgedAt = clock
        homeEvents.append(.nudged(Vec2((porch.minX + porch.maxX) / 2, porch.y)))
        let inside = notchHomeShowing ? insideHangingHome : insideNest
        if let c = inside.first, !calm {
            c.homeUntil = clock   // out it comes (World.update puts it on the porch)
            c.wavesOnWaking = true
            homeEvents.append(.cameOut(by: c.id))
            return true
        }
        // Someone on the porch: whoa! then a wave.
        for c in creatures where c.groundOwner == porch.ownerID && c.isGrounded && !c.isAsleep && c.mossTask == nil {
            c.facing = (cursor?.x ?? c.pos.x) > c.pos.x ? 1 : -1
            c.set(.wave, duration: 1.4)
        }
        return true
    }

    // MARK: The bird

    func updateBirds(_ dt: Double) {
        if birds.isEmpty, crittersOn, !compact, !isNight, clock >= nextBirdAt {
            nextBirdAt = clock + rng.range(ownDay ? 240 : 420, ownDay ? 600 : 1000)
            spawnBird()
        }
        for i in birds.indices {
            var b = birds[i]
            defer { birds[i] = b }
            switch b.state {
            case .flyingIn:
                let d = b.perch - b.pos
                let dist = d.length
                if dist < 4 {
                    b.pos = b.perch; b.vel = .zero; b.state = .perched
                    b.until = clock + rng.range(18, 45)
                    homeEvents.append(.birdLanded(b.pos))
                    if b.seed, let porch = homePorch, abs(b.pos.x - (porch.minX + porch.maxX) / 2) < 120, pantry < World.pantryMax {
                        pantry += 1
                        homeEvents.append(.birdSeed(b.pos))
                    }
                    continue
                }
                // Swooping in: fast across, slowing to land, a bob with each wingbeat.
                let speed = min(220, 40 + dist * 1.6)
                b.vel = d * (speed / dist)
                b.pos = b.pos + b.vel * dt + Vec2(0, sin(clock * 14 + Double(b.id)) * 0.6)
                if abs(b.vel.x) > 5 { b.facing = b.vel.x > 0 ? 1 : -1 }
            case .perched:
                // Its perch went away (a window moved or closed): off it goes.
                if let o = b.perchOwner, o >= 0, windows[o] == nil || !surfaces.contains(where: { $0.ownerID == o && abs($0.y - b.perch.y) < 3 && $0.supports(x: b.perch.x) }) {
                    leaveBird(&b); continue
                }
                if let cur = cursor, (cur - b.pos).length < 60 { leaveBird(&b); continue }
                if clock >= b.until { leaveBird(&b); continue }
                if clock >= b.hopAt {
                    b.hopAt = clock + rng.range(1.5, 4)
                    if rng.chance(0.5) { b.facing = -b.facing }
                }
                // The Gremlets nearby look up and wave, once.
                if !b.greeted {
                    b.greeted = true
                    for c in creatures where (c.pos - b.pos).length < 260 && c.isGrounded && !c.isAsleep && c.job == nil && c.mossTask == nil && c.expedition == nil
                        && [.idle, .walk].contains(c.activity) {
                        c.facing = b.pos.x > c.pos.x ? 1 : -1
                        c.set(.wave, duration: 1.4)
                    }
                }
            case .leaving:
                b.vel = b.vel + Vec2(b.facing * 160, 120) * dt
                b.pos = b.pos + b.vel * dt
            }
        }
        birds.removeAll { b in b.state == .leaving && !screens.contains { $0.contains(b.pos) } && (b.pos.y > (screens.map(\.maxY).max() ?? 0) + 40 || screens.allSatisfy { b.pos.x < $0.minX - 40 || b.pos.x > $0.maxX + 40 }) }
    }

    private func leaveBird(_ b: inout Bird) {
        b.state = .leaving
        b.facing = rng.chance(0.5) ? 1 : -1
        b.vel = Vec2(b.facing * 60, 140)
        homeEvents.append(.birdLeft(b.pos))
    }

    /// `gremlet bird`: one drops by now.
    @discardableResult
    public func spawnBird() -> Bool {
        guard let scr = screens.first, birds.isEmpty else { return false }
        // Somewhere to land: the hanging home's roof above all, the leaf swing, a widget, or a window top's end.
        var perches: [(Vec2, Int?, Double)] = []
        if notchHomeShowing, let n = notchHome { perches.append((Vec2(n.houseMinX + 20, n.houseBottom + n.houseHeight + 6), World.notchPorchOwner, 3)) }
        for (s, kind) in topStructures {
            perches.append((Vec2(kind == .nestHut ? s.minX + 12 : (s.minX + s.maxX) / 2 + 14, kind == .nestHut ? s.y + 72 : s.y), s.ownerID, kind == .nestHut && !notchHomeShowing ? 3 : 1.2))
        }
        for t in surfaces where t.kind == .windowTop && t.ownerID >= 0 && t.width >= 60 && windows[t.ownerID] != nil {
            let wgt = widgetIDs.contains(t.ownerID) ? 1.5 : 0.6
            perches.append((Vec2(rng.chance(0.5) ? t.minX + 14 : t.maxX - 14, t.y), t.ownerID, wgt))
        }
        guard !perches.isEmpty else { return false }
        var roll = rng.range(0, perches.reduce(0) { $0 + $1.2 })
        var pick = perches[0]
        for p in perches { roll -= p.2; if roll <= 0 { pick = p; break } }
        let fromLeft = pick.0.x > scr.midX ? false : true
        let start = Vec2(fromLeft ? scr.minX - 30 : scr.maxX + 30, min(scr.maxY - 40, pick.0.y + rng.range(120, 260)))
        nextBirdID += 1
        birds.append(Bird(id: nextBirdID, pos: start, perch: pick.0, perchOwner: pick.1, seed: rng.chance(0.5), facing: fromLeft ? 1 : -1))
        return true
    }
}
