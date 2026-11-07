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
    /// The hammock, strung under the middle of the notch.
    public var hammock: (minX: Double, maxX: Double, y: Double) {
        let mid = max((minX + maxX) / 2, houseMinX + houseWidth + 56)
        return (mid - 30, mid + 30, menuBottom - 86)
    }
}

extension World {
    static let notchPorchOwner = -430_001, notchHammockOwner = -430_002
    static func isNotchOwner(_ o: Int?) -> Bool { o == notchPorchOwner || o == notchHammockOwner }

    /// The home only shows (and can be reached) while no window is in the space under the notch: it never sits over
    /// a toolbar or a title bar.
    public var notchHomeShowing: Bool {
        guard let n = notchHome else { return false }
        let lo = n.houseMinX - 8, hi = n.hammock.maxX + 10, bottom = n.menuBottom - 104
        return !windows.values.contains { $0.minX < hi && $0.maxX > lo && $0.maxY > bottom }
    }

    var notchSurfaces: [Surface] {
        guard let n = notchHome, notchHomeShowing else { return [] }
        return [Surface(ownerID: World.notchPorchOwner, kind: .plant, y: n.porch.y, minX: n.porch.minX, maxX: n.porch.maxX),
                Surface(ownerID: World.notchHammockOwner, kind: .plant, y: n.hammock.y, minX: n.hammock.minX, maxX: n.hammock.maxX)]
    }

    /// Who's napping in the hammock.
    public var hammockSleeper: Creature? {
        creatures.first { $0.groundOwner == World.notchHammockOwner && $0.isAsleep }
    }

    /// Once Claude has gone quiet, now and then someone heads up to the hammock for a nap.
    func notchChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard notchHomeShowing, claudeResting, clock >= nextNotchTripAt, c.expedition == nil, c.job == nil, c.isGrounded,
              !creatures.contains(where: { if case .notch? = $0.expedition?.goal { return true }; return World.isNotchOwner($0.groundOwner) && $0 !== c }) else { return }
        if World.isNotchOwner(c.groundOwner) { return }
        add("notchNap", 1.4) { if !self.startExpedition(c, .notch) { self.nextNotchTripAt = self.clock + 120 } }
    }

    /// Arrived under the notch: into the hammock for a long nap (hopping across from the porch if it landed there).
    func settleInHammock(_ c: Creature) {
        guard let n = notchHome else { return }
        nextNotchTripAt = clock + rng.range(600, 1200)
        hammockNapper = (c.id, clock, false)
        if c.groundOwner != World.notchHammockOwner {
            launch(c, velocity: ballistic(from: c.pos, toX: (n.hammock.minX + n.hammock.maxX) / 2, y: n.hammock.y, apexExtra: 24))
        }
    }

    /// `gremlet notch`: someone goes up for a nap now.
    @discardableResult
    public func startNotchTrip() -> Bool {
        guard notchHomeShowing else { return false }
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
}
