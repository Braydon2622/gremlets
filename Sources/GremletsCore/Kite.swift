import Foundation

/// A kite. Now and then, by day, a Gremlet standing on the floor with nothing to do lets one up: it climbs on the
/// wind, tugs about on its string for half a minute while friends nearby look up, then gets reeled back in.
public struct Kite: Sendable {
    public var flyer: Int
    public var pos: Vec2
    public var vel: Vec2
    public var length: Double
    public var maxLength: Double
    public var age: Double
    public var duration: Double
    public var seed: UInt64
    /// Which way the wind blows it (±1).
    public var dir: Double
}

extension World {
    /// Where the string leaves the flyer's hand.
    public func kiteHand(_ c: Creature) -> Vec2 { c.pos + Vec2(c.facing * c.size.x * 0.45, c.size.y * 0.62) }

    func kiteChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard kite == nil, !isNight, !(weather?.sky.isWet ?? false), maxHobbies > 0, clock >= nextKiteAt, c.job == nil, c.play == nil, c.groveTask == nil, c.isGrounded,
              let g = c.groundOwner, (-100 ... -1).contains(g), c.energy > 0.3,
              let scr = screen(containingX: c.pos.x, y: c.pos.y), scr.maxY - c.pos.y > 320 else { return }
        add("kite", weather?.windy == true ? 1.6 : 0.5) { _ = self.startKite(for: c.id) }
    }

    @discardableResult
    public func startKite(for id: Int) -> Bool {
        guard kite == nil, let c = creature(id: id), c.isGrounded else { return false }
        endSocial(c)
        let dir: Double = c.facing < 0 ? -1 : 1
        let hand = kiteHand(c)
        kite = Kite(flyer: id, pos: hand + Vec2(dir * 10, 20), vel: Vec2(dir * 30, 60), length: 24, maxLength: rng.range(150, 230),
                    age: 0, duration: rng.range(28, 45), seed: rng.next(), dir: dir)
        c.idleVariant = "look"
        c.set(.idle, duration: 9999)
        nextKiteAt = clock + rng.range(600, 1500)
        return true
    }

    /// `gremlet kite`: whoever is free flies one.
    @discardableResult
    public func startKiteWithAnyone() -> Bool {
        let free = creatures.filter { $0.isGrounded && $0.job == nil && $0.play == nil && $0.groveTask == nil && $0.groundOwner.map { (-100 ... -1).contains($0) } == true }
        guard let c = free.randomElement() else { return false }
        return startKite(for: c.id)
    }

    func endKite() {
        if let k = kite, let c = creature(id: k.flyer), c.activity == .idle { c.set(.idle, duration: 1) }
        kite = nil
    }

    func updateKite(_ dt: Double) {
        guard var k = kite else { return }
        // A nudge, a greeting or a few steps don't bring it down; sleep, a jump, a drag, a job or nightfall do.
        guard let c = creature(id: k.flyer), c.isGrounded, c.job == nil, c.play == nil, !isNight,
              [.idle, .walk, .chase, .react, .yawn, .alert, .work].contains(c.activity) else { endKite(); return }
        k.age += dt
        if k.age > k.duration { endKite(); return }
        let hand = kiteHand(c)
        // Pay the string out over the first seconds and reel it in over the last.
        let reel = min(1, k.age / 4) * min(1, max(0, (k.duration - k.age) / 4))
        k.length = 24 + (k.maxLength - 24) * reel
        let t = clock + Double(k.seed % 97)
        let wind = Vec2(k.dir * (70 + 30 * sin(t * 0.6) + 15 * sin(t * 1.7)), 55 + 25 * sin(t * 1.1 + 1))
        k.vel = k.vel + (wind - k.vel * 0.6 + Vec2(0, -40)) * (dt * 2.2)
        k.pos = k.pos + k.vel * dt
        // The string holds it.
        let d = k.pos - hand
        let len = d.length
        if len > k.length, len > 0.001 {
            let n = Vec2(d.x / len, d.y / len)
            k.pos = hand + n * k.length
            let along = k.vel.x * n.x + k.vel.y * n.y
            if along > 0 { k.vel = k.vel - n * along }
        }
        if k.pos.y < hand.y + 12 { k.pos.y = hand.y + 12; k.vel.y = abs(k.vel.y) * 0.3 }
        if c.activity == .idle { c.facing = k.dir }
        // Friends nearby look up at it now and then.
        if Int(clock * 2) != Int((clock - dt) * 2) {
            for o in creatures where o.id != c.id && o.isGrounded && o.activity == .idle && o.job == nil
                && abs(o.pos.x - k.pos.x) < 360 && abs(o.pos.y - c.pos.y) < 200 {
                o.facing = k.pos.x > o.pos.x ? 1 : -1
                if rng.chance(0.08) { o.idleVariant = "look" }
            }
        }
        kite = k
    }
}
