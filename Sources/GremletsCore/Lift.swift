import Foundation

/// The cursor elevator: hold ⌃⌥ and a little cloud appears under your pointer. The nearest Gremlet hops up onto it
/// and rides wherever you move the pointer: lift it onto a high window, carry it across the screen. Let go of the
/// keys and it drops off (flung a little the way you were moving), landing on whatever is below.
public struct CursorLift: Sendable {
    /// The pointer's hotspot (global points).
    public var at: Vec2
    var prev: Vec2
    var vel = Vec2.zero
    /// Who it's for (hopping up, or riding).
    public var rider: Int?
    public static let width = 44.0
    /// The cloud sits just under the arrow.
    public static let drop = 30.0
    public var deck: (minX: Double, maxX: Double, y: Double) { (at.x - 14, at.x - 14 + CursorLift.width, at.y - CursorLift.drop) }
}

extension World {
    static let liftOwner = -425_000

    var liftSurface: Surface? {
        guard let l = lift else { return nil }
        return Surface(ownerID: World.liftOwner, kind: .plant, y: l.deck.y, minX: l.deck.minX, maxX: l.deck.maxX)
    }

    /// Called every frame by the app: where the pointer is while ⌃⌥ is held, or nil when it isn't.
    public func setLift(_ p: Vec2?) {
        guard let p else { endLift(); return }
        if var l = lift {
            l.at = p
            lift = l
        } else {
            lift = CursorLift(at: p, prev: p)
            callLiftRider()
        }
    }

    /// The nearest free Gremlet hops up toward the cloud.
    func callLiftRider() {
        guard var l = lift else { return }
        let free = creatures.filter { isFree($0) && $0.groveTask == nil && $0.snowmanTask == nil && $0.activity != .dragged && $0.activity != .float && $0.groundOwner != World.ferryOwner }
        guard let c = free.min(by: { ($0.pos - l.at).length < ($1.pos - l.at).length }), (c.pos - l.at).length < 900 else { return }
        l.rider = c.id
        lift = l
        endSocial(c)
        c.targetX = nil
        c.groundOwner = nil
        let d = l.at - c.pos
        c.vel = Vec2(d.x * 1.6, max(380, d.y * 2.2 + 300))
        c.facing = d.x >= 0 ? 1 : -1
        c.set(.airborne)
        emit(.alert(c.id))
    }

    func endLift() {
        guard let l = lift else { return }
        lift = nil
        if let id = l.rider, let c = creature(id: id), c.groundOwner == World.liftOwner {
            c.groundOwner = nil
            c.vel = Vec2((l.vel.x * 0.6).clamped(-500, 500), max(120, (l.vel.y * 0.4).clamped(-200, 500)))
            c.set(.airborne)
        }
        setSurfacesDirty()
    }

    /// Each frame: the rider homes in on the cloud while hopping up, then rides it.
    func updateLift(_ dt: Double) {
        guard var l = lift else { return }
        let delta = l.at - l.prev
        if dt > 0 { l.vel = l.vel * 0.7 + delta * (0.3 / dt) }
        l.prev = l.at
        lift = l
        guard let id = l.rider, let c = creature(id: id) else { return }
        if c.groundOwner == World.liftOwner {
            c.pos += delta
            c.pos.y = l.deck.y
            return
        }
        guard c.activity == .airborne else {
            // It landed somewhere else on the way up (or got grabbed): try again from there.
            if c.isGrounded && c.activity != .dragged { lift?.rider = nil; callLiftRider() }
            return
        }
        // Steer toward the cloud, and step aboard once close.
        let target = Vec2((l.deck.minX + l.deck.maxX) / 2, l.deck.y)
        let d = target - c.pos
        if d.length < 26 {
            c.pos = target
            c.vel = .zero
            c.groundOwner = World.liftOwner
            c.idleVariant = "look"
            c.set(.idle, duration: 1e6)
            emit(.landed(c.id, impact: 0))
            return
        }
        let want = d * (1 / max(0.12, d.length / 900)) * 0.9
        c.vel = c.vel + (want - c.vel) * min(1, dt * 6)
    }
}
