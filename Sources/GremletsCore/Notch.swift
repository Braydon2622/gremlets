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
    static func isNotchOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= notchPorchOwner && o >= cornerBranchOwner - 3 }

    /// Full screen: mossy branches out from the screen's top corners, more places to hang out (room for a crowd):
    /// two from the top-left, one from the right edge under the house.
    public var cornerBranches: [Surface] {
        guard compact, let scr = screens.first else { return [] }
        return [Surface(ownerID: World.cornerBranchOwner, kind: .plant, y: scr.maxY - 96, minX: scr.minX, maxX: scr.minX + 140),
                Surface(ownerID: World.cornerBranchOwner - 1, kind: .plant, y: scr.maxY - 176, minX: scr.minX, maxX: scr.minX + 110),
                Surface(ownerID: World.cornerBranchOwner - 2, kind: .plant, y: scr.maxY - 196, minX: scr.maxX - 120, maxX: scr.maxX)]
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
        guard let n = notchHome, notchHomeShowing else { return [] }
        return [Surface(ownerID: World.notchPorchOwner, kind: .plant, y: n.porch.y, minX: n.porch.minX, maxX: n.porch.maxX),
                Surface(ownerID: World.notchHammockOwner, kind: .plant, y: n.hammock.y, minX: n.hammock.minX, maxX: n.hammock.maxX),
                Surface(ownerID: World.notchSwingOwner, kind: .plant, y: n.swing.y, minX: n.swing.minX, maxX: n.swing.maxX)]
            + cornerBranches
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
              !creatures.contains(where: { if case .notch? = $0.expedition?.goal { return true }; return World.isNotchOwner($0.groundOwner) && $0 !== c }) else { return }
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

