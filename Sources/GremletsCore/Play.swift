/// Two-Gremlet games, so friends do more together than stand on each other's heads:
///
/// - **Toss:** one hops onto a friend's head, the friend heaves, and it's flung sky high with a flip.
/// - **Catch:** two friends a little apart lob a seed back and forth in big arcs, hopping to catch it.
/// - **High five:** they run at each other, jump, and clap in mid-air (sparkles).
public struct PlayState: Sendable {
    public enum Kind: Sendable { case toss, catchBall, highFive }
    public var kind: Kind
    public var partner: Int
    /// 0 = the one who started it, 1 = the partner.
    public var role: Int
    public var stage = 0
    public var t = 0.0
    public var throwsLeft = 0
}

/// The seed in a game of catch.
public struct PlayBall: Sendable {
    public var pos: Vec2
    public var vel: Vec2
    public var to: Int
    public var from: Int
    public var age = 0.0
    public var flight: Double
}

extension World {

    func playChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard c.job == nil, c.play == nil, spectacle?.isBoss != true else { return }
        let friends = nearbyFriends(of: c, range: 520).filter {
            $0.play == nil && $0.job == nil && [.idle, .walk, .follow].contains($0.activity) && $0.groveTask == nil
        }
        guard !friends.isEmpty else { return }
        let e = c.energy
        let f = friends[Int(rng.next() % UInt64(friends.count))]
        let dx = abs(f.pos.x - c.pos.x)
        if dx < 300 && World.carrierID(f.groundOwner) == nil && World.carrierID(c.groundOwner) == nil {
            add("toss", 0.5 * (0.3 + e)) { self.startPlay(.toss, c, f) }
        }
        if dx > 140 && dx < 520 {
            add("catch", 0.6 * (0.3 + e)) { self.startPlay(.catchBall, c, f) }
        }
        add("highFive", 0.45 * (0.3 + e)) { self.startPlay(.highFive, c, f) }
    }

    func startPlay(_ k: PlayState.Kind, _ a: Creature, _ b: Creature) {
        a.play = PlayState(kind: k, partner: b.id, role: 0)
        b.play = PlayState(kind: k, partner: a.id, role: 1)
        a.facing = b.pos.x > a.pos.x ? 1 : -1
        b.facing = -a.facing
        endSocial(a); endSocial(b)
        switch k {
        case .toss:
            // The partner waits, facing out; the tosser hops on its head.
            b.set(.idle, duration: 8)
            startStack(a, b)
        case .catchBall:
            a.play?.throwsLeft = Int(rng.range(4, 7.99))
            a.set(.idle, duration: 10); b.set(.idle, duration: 10)
            emit(.alert(b.id))
        case .highFive:
            let mid = (a.pos.x + b.pos.x) / 2
            a.targetX = mid - a.facing * 30
            b.targetX = mid - b.facing * 30
            a.set(.walk, duration: 6); b.set(.walk, duration: 6)
        }
    }

    func endPlay(_ c: Creature) {
        if let p = c.play, let o = creature(id: p.partner), o.play?.partner == c.id { o.play = nil; o.targetX = nil }
        c.play = nil
        c.targetX = nil
        playBalls.removeAll { $0.from == c.id || $0.to == c.id }
    }

    func updatePlay(_ dt: Double) {
        for c in creatures {
            guard var p = c.play else { continue }
            guard let o = creature(id: p.partner), o.play?.partner == c.id, c.job == nil, o.job == nil,
                  c.activity != .dragged, o.activity != .dragged else { endPlay(c); continue }
            p.t += dt
            if p.t > 14 { endPlay(c); continue }
            switch p.kind {
            case .toss where p.role == 0:
                // Riding the partner's head? Then the partner heaves and we fly.
                if p.stage == 0 && c.isGrounded && c.groundOwner == o.carrierOwnerID {
                    p.stage = 1; p.t = 0
                    o.set(.special, duration: 0.5)
                } else if p.stage == 0 && c.isGrounded && p.t > 2.5 && World.carrierID(c.groundOwner) == nil {
                    endPlay(c); continue   // missed the jump; no big deal
                } else if p.stage == 1 && p.t > 0.45 {
                    c.groundOwner = nil
                    c.vel = Vec2(rng.range(-180, 180), rng.range(1150, 1450))
                    c.set(.airborne)
                    emit(.tossed(c.id, by: o.id))
                    c.play = nil; o.play = nil
                    o.set(.wave, duration: 1.4)
                    continue
                }
            case .catchBall where p.role == 0:
                // The starter throws first; after that whoever catches throws back.
                if p.stage == 0 && c.isGrounded && o.isGrounded && p.t > 0.6 {
                    p.stage = 1
                    throwBall(from: c, to: o)
                }
            case .highFive where p.role == 0:
                if p.stage == 0, c.isGrounded, o.isGrounded, abs(c.pos.x - o.pos.x) < 96, abs(c.pos.y - o.pos.y) < 8 {
                    p.stage = 1; p.t = 0
                    for (x, y) in [(c, o), (o, c)] {
                        x.targetX = nil
                        x.facing = y.pos.x > x.pos.x ? 1 : -1
                        x.groundOwner = nil
                        x.vel = Vec2(x.facing * 40, (2 * gravity * 70).squareRoot())
                        x.set(.airborne)
                    }
                } else if p.stage == 1 && p.t > 0.17 {
                    p.stage = 2
                    emit(.highFive(c.id, o.id))
                } else if p.stage == 2 && c.isGrounded {
                    c.set(.react, duration: c.animationLength(for: .react))
                    o.set(.react, duration: o.animationLength(for: .react))
                    endPlay(c); continue
                } else if p.stage == 0 && c.activity == .walk && abs(c.pos.x - o.pos.x) < 70 {
                    c.targetX = nil; c.set(.idle, duration: 3)
                }
            default: break
            }
            c.play = p
        }
        updateBalls(dt)
    }

    private func throwBall(from a: Creature, to b: Creature) {
        let start = a.pos + Vec2(a.facing * a.size.x * 0.3, a.size.y * 0.7)
        let end = b.pos + Vec2(0, b.size.y * 0.75)
        let flight = 0.8 + abs(end.x - start.x) / 900
        let vx = (end.x - start.x) / flight
        let vy = (end.y - start.y + 0.5 * gravity * 0.55 * flight * flight) / flight
        playBalls.append(PlayBall(pos: start, vel: Vec2(vx, vy), to: b.id, from: a.id, flight: flight))
        a.set(.special, duration: min(0.6, a.animationLength(for: .special)))
        b.facing = a.pos.x > b.pos.x ? 1 : -1
    }

    private func updateBalls(_ dt: Double) {
        var keep: [PlayBall] = []
        for var ball in playBalls {
            ball.age += dt
            ball.vel.y -= gravity * 0.55 * dt
            ball.pos += ball.vel * dt
            guard let catcher = creature(id: ball.to), let thrower = creature(id: ball.from) else { continue }
            // A little hop to catch it just before it arrives.
            if ball.flight - ball.age < 0.22 && catcher.isGrounded && catcher.activity != .airborne && rng.chance(0.5) {
                catcher.groundOwner = nil
                catcher.vel = Vec2(0, 420)
                catcher.set(.airborne)
            }
            if ball.age >= ball.flight {
                emit(.caught(catcher.id))
                // The starter keeps count; when it's out of throws the game ends with a wave.
                let starter = catcher.play?.role == 0 ? catcher : thrower
                if var sp = starter.play, sp.throwsLeft > 1 {
                    sp.throwsLeft -= 1
                    starter.play = sp
                    pendingThrows.append((at: clock + 0.45, from: catcher.id, to: thrower.id))
                } else {
                    endPlay(starter)
                    catcher.set(.wave, duration: 1.4); thrower.set(.wave, duration: 1.4)
                }
                continue
            }
            keep.append(ball)
        }
        playBalls = keep
        let due = pendingThrows.filter { $0.at <= clock }
        pendingThrows.removeAll { $0.at <= clock }
        for d in due {
            guard let a = creature(id: d.from), let b = creature(id: d.to), a.play != nil, b.play != nil else { continue }
            if a.isGrounded { throwBall(from: a, to: b) } else { pendingThrows.append((at: clock + 0.2, from: d.from, to: d.to)) }
        }
    }
}
