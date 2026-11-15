import Foundation

/// The mail carrier (Back Office): when a letter comes in, a Gremlet walks over to the building to collect it, then
/// carries it along the floor to the far corner of the screen and waits there with it: waving if it's for you
/// (a mention or a DM), napping on it if it can wait. Clicking the carrier opens the letter (the app does that).
extension World {
    /// Someone free and on the floor sets off for the building. Nil if nobody can go.
    public func startMailRun(pickupX: Double) -> Int? {
        let free = creatures.filter { isFree($0) && $0.isGrounded && !$0.isAsleep && $0.mossTask == nil && $0.job == nil }
        // Someone on the floor if possible (it walks right up to the building), else whoever's nearest, along what it's
        // standing on (the top edge, a window): it goes as close as it can, then on to the far corner.
        let onFloor = free.filter { supportingSurface(for: $0).map { $0.kind == .floor && $0.ownerID == -1 } ?? false }
        guard let c = (onFloor.isEmpty ? free : onFloor).min(by: { abs($0.pos.x - pickupX) < abs($1.pos.x - pickupX) }) else { return nil }
        endSocial(c)
        guard mailWalk(c.id, to: pickupX) else { return nil }
        c.onMail = true
        return c.id
    }

    /// The run's over (delivered, clicked, or it gave up): back to its own day.
    public func endMailRun(_ id: Int) {
        guard let c = creatures.first(where: { $0.id == id }) else { return }
        c.onMail = false
        if c.activity == .wave || c.activity == .idle { c.set(.idle, duration: 0.5) }
    }

    /// Walks along the floor toward x (kept on its own screen). False if it can't.
    @discardableResult
    public func mailWalk(_ id: Int, to x: Double) -> Bool {
        guard let c = creatures.first(where: { $0.id == id }), c.isGrounded, let s = supportingSurface(for: c) else { return false }
        let tx = min(max(x, s.minX + 14), s.maxX - 14)
        if abs(tx - c.pos.x) < 6 { return true }   // as close as its surface goes
        c.targetX = tx
        c.facing = tx > c.pos.x ? 1 : -1
        c.set(.walk, duration: 30)
        return true
    }

    /// How far it still has to go to x (nil if it's gone, been picked up or fallen asleep elsewhere).
    public func mailDistance(_ id: Int, to x: Double) -> Double? {
        guard let c = creatures.first(where: { $0.id == id }), c.activity != .dragged, c.activity != .airborne else { return nil }
        return abs(c.pos.x - x)
    }

    /// At the corner: a wave (for you) or a nap (it can wait).
    public func mailWait(_ id: Int, urgent: Bool, toward x: Double?) {
        guard let c = creatures.first(where: { $0.id == id }), c.isGrounded else { return }
        if let x { c.facing = x > c.pos.x ? 1 : -1 }
        if urgent { c.set(.wave, duration: 1.4) } else if c.activity != .sleep { c.set(.sleep, duration: 90) }
    }
}
