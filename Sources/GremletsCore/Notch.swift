import Foundation

/// A home under the MacBook's notch: a little house hanging from the bottom of the menu bar beside the notch, with a
/// porch, and a hammock slung under the notch itself. Its windows glow while Claude works. When Claude is quiet a
/// Gremlet sets out across your windows (the expedition planner finds the way up) and naps in the hammock.
///
/// The notch has no pixels, so nothing is drawn in it: everything hangs just below the menu bar.
public struct NotchHome: Equatable, Sendable {
    /// The notch's left and right edges and the bottom of the menu bar (global points).
    public let minX: Double, maxX: Double, menuBottom: Double
    public init(minX: Double, maxX: Double, menuBottom: Double) { self.minX = minX; self.maxX = maxX; self.menuBottom = menuBottom }

    public var houseWidth: Double { 46 }
    public var houseHeight: Double { 38 }
    /// The house hangs at the notch's left end on ropes, low enough that a Gremlet (about 45 pt tall) can jump up
    /// onto its porch without bumping its head on the menu bar.
    public var houseMinX: Double { minX + 2 }
    public var houseBottom: Double { menuBottom - 92 }
    /// The porch: the house's floor, running out to the right.
    public var porch: (minX: Double, maxX: Double, y: Double) { (houseMinX - 2, houseMinX + houseWidth + 22, houseBottom) }
    /// A plank swing hanging under the porch.
    public var swing: (minX: Double, maxX: Double, y: Double) { (houseMinX + 6, houseMinX + 34, houseBottom - 34) }
    /// The hammock, strung under the middle of the notch.
    public var hammock: (minX: Double, maxX: Double, y: Double) {
        let mid = max((minX + maxX) / 2, houseMinX + houseWidth + 56)
        return (mid - 30, mid + 30, menuBottom - 86)
    }
}

extension World {
    static let notchPorchOwner = -430_001, notchHammockOwner = -430_002, notchSwingOwner = -430_003, cornerBranchOwner = -430_004
    static let cornerStumpOwner = -430_010
    public static func isNotchOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= notchPorchOwner && o >= cornerStumpOwner - 1 }
    /// The house itself: porch, hammock and swing.
    public static func isHouseOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= notchPorchOwner && o >= notchSwingOwner }
    public static func isCornerSpot(_ o: Int) -> Bool { o <= cornerBranchOwner && o >= cornerStumpOwner - 1 }

    /// Full screen: mossy branches out from the screen's top corners, added a few at a time as more Gremlets need
    /// room (two Gremlets only get one; a crowd gets five), fewest first.
    func compactBranchTiers() -> [Surface] {
        guard let scr = screens.first else { return [] }
        let o = World.cornerBranchOwner
        return [Surface(ownerID: o, kind: .plant, y: scr.maxY - 96, minX: scr.minX, maxX: scr.minX + 140),
                Surface(ownerID: o - 2, kind: .plant, y: scr.maxY - 196, minX: scr.maxX - 120, maxX: scr.maxX),
                Surface(ownerID: o - 1, kind: .plant, y: scr.maxY - 176, minX: scr.minX, maxX: scr.minX + 110),
                Surface(ownerID: o - 3, kind: .plant, y: scr.maxY - 256, minX: scr.minX, maxX: scr.minX + 96),
                Surface(ownerID: o - 4, kind: .plant, y: scr.maxY - 276, minX: scr.maxX - 100, maxX: scr.maxX)]
    }

    public var cornerBranches: [Surface] {
        if compact { return Array(compactBranchTiers().prefix(compactTiers)) }
        guard topCornerPerches, let scr = screens.first else { return [] }
        // Out of full screen: mossy branches in both top corners to hang out on (two on the left, one on the right),
        // a little lower than in full screen so they sit below a browser's tabs and toolbar.
        let o = World.cornerBranchOwner
        return [Surface(ownerID: o, kind: .plant, y: scr.maxY - 120, minX: scr.minX, maxX: scr.minX + 130),
                Surface(ownerID: o - 2, kind: .plant, y: scr.maxY - 130, minX: scr.maxX - 124, maxX: scr.maxX),
                Surface(ownerID: o - 1, kind: .plant, y: scr.maxY - 205, minX: scr.minX, maxX: scr.minX + 100)]
    }

    /// Out of full screen: up to a corner branch for a rest now and then (more often while Claude is quiet), and back
    /// down on a leaf after a while.
    func cornerChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !compact, topCornerPerches, isFree(c), c.isGrounded, c.mossTask == nil, c.expedition == nil else { return }
        if let o = c.groundOwner, World.isCornerSpot(o) {
            add("cornerRest", 2.0) { c.idleVariant = self.rng.chance(0.5) ? "look" : "idle"; c.set(.idle, duration: self.rng.range(4, 9)) }
            if c.energy < 0.6 { add("cornerNap", 1.0) { c.set(.yawn, duration: c.animationLength(for: .yawn)) } }
            add("cornerDown", claudeResting ? 0.35 : 0.9) {
                guard let f = self.floorBelow(c.pos.x) else { return }
                let x = (c.pos.x + (c.pos.x < (f.minX + f.maxX) / 2 ? 1 : -1) * self.rng.range(60, 200)).clamped(f.minX + 30, f.maxX - 30)
                self.startFloat(c, to: Vec2(x, f.y), ride: .leaf)
            }
            return
        }
        guard clock >= nextCornerTripAt else { return }
        let free = cornerBranches.filter { p in creatures.filter { $0.groundOwner == p.ownerID || ($0.floatTarget.map { abs($0.y - p.y) < 4 && p.supports(x: $0.x) } ?? false) }.count < max(1, Int(p.width / 34)) }
        guard let p = free.min(by: { abs(($0.minX + $0.maxX) / 2 - c.pos.x) < abs(($1.minX + $1.maxX) / 2 - c.pos.x) }) else { return }
        add("cornerPerch", claudeResting ? 1.0 : 0.3) {
            self.nextCornerTripAt = self.clock + self.rng.range(20, 60)
            self.startFloat(c, to: Vec2(self.rng.range(p.minX + 20, p.maxX - 20), p.y), ride: .dandelion)
        }
    }

    /// Full screen, when the top corners are full (or someone had nowhere up there to skitter to): a mossy stump in
    /// each bottom corner.
    public var cornerStumps: [Surface] {
        guard compact, compactTiers > 5 || clock < compactOverflowUntil, let scr = screens.first else { return [] }
        let y = scr.minY + World.stumpTop
        return [Surface(ownerID: World.cornerStumpOwner, kind: .plant, y: y, minX: scr.minX + 14, maxX: scr.minX + 74),
                Surface(ownerID: World.cornerStumpOwner - 1, kind: .plant, y: y, minX: scr.maxX - 74, maxX: scr.maxX - 14)]
    }
    public static let stumpTop = 36.0

    /// How many Gremlets the full-screen spots can hold (about one per 34 points of perch).
    func compactRoom(_ ss: [Surface]) -> Int { ss.reduce(0) { $0 + max(1, Int($1.width / 34)) } }

    /// Grows (or, once nobody's using them, shrinks) the full-screen spots to fit everyone out and about, with one
    /// spare place so there's always somewhere to skitter to.
    func updateCompactRoom() {
        guard compact, notchHomeShowing else { return }
        let n = creatures.filter { $0.homeUntil == nil }.count
        let tiers = compactBranchTiers()
        let house = notchSurfaces.filter { !World.isCornerSpot($0.ownerID) }
        var want = 1
        while want <= tiers.count, compactRoom(house + tiers.prefix(want)) < n + 1 { want += 1 }
        let old = compactTiers
        if want > compactTiers {
            compactTiers = want
        } else if want < compactTiers {
            // Only put a spot away once it's empty and nobody's on the way to it.
            let last = compactTiers > tiers.count ? cornerStumps : [tiers[compactTiers - 1]]
            let used = creatures.contains { c in
                last.contains { s in c.groundOwner == s.ownerID || (c.floatTarget.map { abs($0.y - s.y) < 4 && s.supports(x: $0.x) } ?? false) }
            }
            if !used && clock >= compactOverflowUntil { compactTiers -= 1 }
        }
        if compactTiers != old { setSurfacesDirty() }
    }

    public var cornerBranch: Surface? { cornerBranches.first }

    /// The home only shows (and can be reached) while no window is in the space under the notch: it never sits over
    /// a toolbar or a title bar.
    public var notchHomeShowing: Bool {
        guard let n = notchHome else { return false }
        // Full screen: the house hangs in the top-right corner over the app on purpose (it's where they live then).
        if compact { return true }
        let lo = n.houseMinX - 8, hi = n.hammock.maxX + 10, bottom = n.menuBottom - 104
        return !windows.values.contains { $0.minX < hi && $0.maxX > lo && $0.maxY > bottom }
    }

    var notchSurfaces: [Surface] {
        guard let n = notchHome, notchHomeShowing else { return cornerBranches + cornerStumps }
        return [Surface(ownerID: World.notchPorchOwner, kind: .plant, y: n.porch.y, minX: n.porch.minX, maxX: n.porch.maxX),
                Surface(ownerID: World.notchHammockOwner, kind: .plant, y: n.hammock.y, minX: n.hammock.minX, maxX: n.hammock.maxX),
                Surface(ownerID: World.notchSwingOwner, kind: .plant, y: n.swing.y, minX: n.swing.minX, maxX: n.swing.maxX)]
            + cornerBranches + cornerStumps
    }

    /// Who's napping in the hammock.
    public var hammockSleeper: Creature? {
        creatures.first { $0.groundOwner == World.notchHammockOwner && $0.isAsleep }
    }

    /// Where the door is (on the porch).
    public var notchDoorX: Double? { notchHome.map { $0.houseMinX + 33 } }

    /// Who's inside the hanging house.
    public var insideHangingHome: [Creature] { creatures.filter { $0.homeHouse == -1 && $0.homeUntil != nil } }

    /// Home time (Claude has gone quiet, it's late, or it's tired): someone heads up to the hanging house, to nap
    /// in the hammock or curl up inside.
    func notchChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard notchHomeShowing, claudeResting || isNight || c.energy < 0.35, !compact, clock >= nextNotchTripAt, c.expedition == nil, c.job == nil, c.isGrounded,
              !creatures.contains(where: { if case .notch? = $0.expedition?.goal { return true }; return World.isHouseOwner($0.groundOwner) && $0 !== c }) else { return }
        if World.isNotchOwner(c.groundOwner) { return }
        add("notchNap", isNight ? 4 : 1.4) { if !self.startExpedition(c, .notch) { self.nextNotchTripAt = self.clock + 120 } }
    }

    /// Arrived at the hanging house: into the hammock if it's free (and it fancies it), otherwise in through the door.
    func settleInHammock(_ c: Creature) {
        guard let n = notchHome else { return }
        // Whoever gets home first takes in the post.
        if mailWaiting { mailWaiting = false; mailEvents += 1 }
        nextNotchTripAt = clock + rng.range(300, 700)
        let hammockFree = hammockNapper == nil && hammockSleeper == nil
        if !hammockFree || rng.chance(0.45), let door = notchDoorX, c.groundOwner == World.notchPorchOwner {
            c.targetX = door; c.facing = door > c.pos.x ? 1 : -1
            c.groveTask = .hangingHome
            c.set(.walk, duration: 10)
            return
        }
        hammockNapper = (c.id, clock, false)
        if c.groundOwner != World.notchHammockOwner {
            launch(c, velocity: ballistic(from: c.pos, toX: (n.hammock.minX + n.hammock.maxX) / 2, y: n.hammock.y, apexExtra: 24))
        }
    }

    /// `gremlet notch`: someone goes up for a nap now.
    @discardableResult
    public func startNotchTrip() -> Bool {
        guard notchHomeShowing, !compact else { return false }
        nextNotchTripAt = 0
        for c in creatures.shuffled(using: &rng) where c.expedition == nil && c.job == nil && c.isGrounded && !World.isNotchOwner(c.groundOwner) {
            if startExpedition(c, .notch) { return true }
        }
        return false
    }

    /// Tucks the napper in once it's lying in the hammock (whatever it was finishing first), and lets go of it once
    /// it has slept and climbed out.
    func checkHammock() {
        guard let (id, since, asleep) = hammockNapper else { return }
        guard let c = creature(id: id) else { hammockNapper = nil; return }
        let inHammock = c.groundOwner == World.notchHammockOwner && c.isGrounded
        if inHammock && !asleep && [.idle, .walk, .land, .react].contains(c.activity) {
            c.set(.sleep, duration: rng.range(90, 240))
            emit(.fellAsleep(c.id))
            hammockNapper = (id, since, true)
        } else if (asleep && !c.isAsleep) || (!inHammock && c.isGrounded && clock - since > 8) {
            hammockNapper = nil
        }
    }

    /// In through the door: out of sight for a while (smoke curls from the chimney), then back out onto the porch.
    func goInsideHangingHome(_ c: Creature) {
        guard notchHomeShowing else { return }
        lastHomeArrival = clock
        c.homeHouse = -1
        c.homeUntil = clock + rng.range(isNight ? 120 : 50, isNight ? 300 : 150)
        c.set(.sleep, duration: 9999)
    }

    // MARK: Growing with you, the night, and the vine to the hut

    /// The house grows as the Claude sessions add up: a balcony (5), a loft (15), a rooftop garden (40).
    public var houseStage: Int {
        let sessions = bonsaiBook.trees.reduce(0) { $0 + $1.sessions }
        return sessions >= 40 ? 3 : sessions >= 15 ? 2 : sessions >= 5 ? 1 : 0
    }

    /// The lights: on while Claude works; after dark, on while anyone's up, and out a few minutes after the last
    /// one has gone in to sleep.
    public var houseLightsOn: Bool {
        if claudeWorking { return true }
        guard isNight else { return false }
        return insideHangingHome.isEmpty || clock - lastHomeArrival < 240
    }

    /// Keeps the vine between the hanging house and the terminal's hut in place (only when the hut hangs below the
    /// house and not too far across).
    func updateHomeLine() {
        // Never pulled away from under someone riding it: it settles once they're off.
        if let h = homeLine, creatures.contains(where: { $0.zip?.zipline == h.id }) { return }
        guard let n = notchHome, notchHomeShowing, !compact, let pod = podPlacements.first else { homeLine = nil; return }
        let top = Vec2(n.porch.maxX - 6, n.porch.y + Zipline.hang)
        let bottom = Vec2(pod.side > 0 ? pod.branch.maxX - 10 : pod.branch.minX + 10, pod.branch.y + Zipline.hang)
        let d = bottom - top
        guard d.y < -120, d.y > -720, abs(d.x) < 760 else { homeLine = nil; return }
        if let h = homeLine, (h.top - top).length < 2, (h.bottom - bottom).length < 2 { return }
        homeLine = Zipline(id: 900_000, top: top, bottom: bottom, topOwner: World.notchPorchOwner, bottomOwner: pod.branch.ownerID, madeAt: clock)
    }
}

