/// Creature-to-creature behaviors: greeting, following, napping together, tag, stacking and dance parties,
/// plus signature moves and peeking around screen edges.
extension World {

    /// Awake friends on roughly the same level and within reach.
    func nearbyFriends(of c: Creature, range: Double = 360) -> [Creature] {
        creatures.filter { o in
            o !== c && o.job == nil && o.homeUntil == nil && o.isGrounded && abs(o.pos.y - c.pos.y) < 40 && abs(o.pos.x - c.pos.x) < range
        }
    }

    func endSocial(_ c: Creature) {
        c.social = .none
        c.friendID = nil
        c.animSpeed = 1
        c.peekX = nil
    }

    // MARK: Starters (called by Brain)

    func startGreet(_ c: Creature, _ f: Creature) {
        c.social = .greet; c.friendID = f.id
        c.lastGreet[f.id] = clock; f.lastGreet[c.id] = clock
        c.set(.follow, duration: 6)
    }

    func startFollow(_ c: Creature, _ f: Creature) {
        c.social = .follow; c.friendID = f.id
        c.set(.follow, duration: rng.range(5, 9))
    }

    func startNap(_ c: Creature, _ f: Creature) {
        c.social = .nap; c.friendID = f.id
        c.set(.follow, duration: 8)
    }

    func startTag(_ c: Creature, _ f: Creature) {
        let length = rng.range(7, 11)
        c.social = .chaser; c.friendID = f.id
        f.social = .runner; f.friendID = c.id
        c.set(.run, duration: length)
        f.set(.run, duration: length)
        f.tagImmunity = 0.8
        emit(.alert(f.id))
    }

    /// Hops onto a friend's head.
    func startStack(_ c: Creature, _ f: Creature) {
        let top = f.pos.y + f.species.headTop
        c.friendID = f.id
        launch(c, velocity: ballistic(from: c.pos, toX: f.pos.x, y: top, apexExtra: 30))
    }

    func startDance(_ c: Creature, duration: Double? = nil, invite: Bool = true) {
        let d = duration ?? rng.range(3, 5)
        c.beatTimer = 0
        c.set(.dance, duration: d)
        guard invite else { return }
        // Dance parties: nearby friends who aren't busy join in.
        for f in nearbyFriends(of: c, range: 420) where [.idle, .walk, .follow].contains(f.activity) && rng.chance(0.6) {
            endSocial(f)
            f.facing = c.pos.x > f.pos.x ? 1 : -1
            startDance(f, duration: d, invite: false)
        }
    }

    func startSpecial(_ c: Creature) {
        c.set(.special, duration: c.animationLength(for: .special))
        emit(.special(c.id, effect: c.species.special))
    }

    /// Walks to the nearest real screen edge to peek around it.
    func startPeek(_ c: Creature) -> Bool {
        guard let owner = c.groundOwner, owner < 0, owner > World.creatureOwnerBase else { return false } // floors only
        let (lo, hi) = horizontalLimits(for: c, atY: c.pos.y + 1, inset: false)
        let toLo = c.pos.x - lo, toHi = hi - c.pos.x
        guard min(toLo, toHi) < 500 else { return false }
        c.peekX = toLo < toHi ? lo + c.size.x * 0.05 : hi - c.size.x * 0.05
        c.facing = toLo < toHi ? -1 : 1
        c.set(.peek, duration: 12)
        return true
    }

    // MARK: Updates

    func updateFollow(_ c: Creature, _ dt: Double, on support: Surface) {
        guard let f = creature(id: c.friendID), abs(f.pos.y - c.pos.y) < 50 else {
            endSocial(c); Brain.decide(c, in: self); return
        }
        let dx = f.pos.x - c.pos.x
        let touch = (c.size.x + f.size.x) * 0.3
        let gap: Double = c.social == .follow ? 80 : touch
        if abs(dx) > gap + 4 {
            c.facing = dx > 0 ? 1 : -1
            move(c, dt, speed: c.species.walkSpeed * (abs(dx) > 200 ? 1.3 : 1), on: support, ledgeTurnChance: 1)
            return
        }
        c.facing = dx > 0 ? 1 : -1
        switch c.social {
        case .greet:
            c.set(.wave, duration: 1.4)
            if [.idle, .walk, .follow, .wave].contains(f.activity) {
                endSocial(f)
                f.facing = -c.facing
                f.set(.wave, duration: 1.4)
            }
            emit(.greet(c.id, f.id))
            endSocial(c)
        case .nap:
            endSocial(c)
            c.set(.yawn, duration: c.animationLength(for: .yawn))
        default:
            break // follow: wait here, facing the friend, until they move on
        }
    }

    func updateTag(_ c: Creature, _ dt: Double, on support: Surface) {
        guard let f = creature(id: c.friendID), abs(f.pos.y - c.pos.y) < 160, [.run, .airborne, .land].contains(f.activity) else {
            endTag(c); return
        }
        let dx = f.pos.x - c.pos.x
        if c.social == .chaser {
            c.facing = dx > 0 ? 1 : -1
            move(c, dt, speed: c.species.walkSpeed * 1.9 + 20, on: support, ledgeTurnChance: 0.3)
            if abs(dx) < (c.size.x + f.size.x) * 0.22 && f.tagImmunity <= 0 && f.isGrounded {
                // Tagged! Swap roles.
                emit(.tagged(f.id))
                c.social = .runner; f.social = .chaser
                c.tagImmunity = 0.9
                c.facing = -c.facing
            }
        } else {
            if abs(dx) < 220 { c.facing = dx > 0 ? -1 : 1 }   // run away from the chaser
            if !move(c, dt, speed: c.species.walkSpeed * 1.7 + 15, on: support, ledgeTurnChance: 0.4) {
                // Cornered at a wall: dodge with a hop over the chaser.
                if abs(dx) < 120 { c.facing = -c.facing; c.groundOwner = nil; c.vel = Vec2(c.facing * 380, 680); c.set(.airborne, duration: 5) }   // leapfrog over the chaser
            }
        }
    }

    func endTag(_ c: Creature) {
        if let f = creature(id: c.friendID), f.friendID == c.id, f.activity == .run {
            endSocial(f)
            f.set(.react, duration: f.animationLength(for: .react))
        }
        endSocial(c)
        if c.isGrounded { c.set(.react, duration: c.animationLength(for: .react)) }
    }

    func updatePeek(_ c: Creature, _ dt: Double) {
        guard let px = c.peekX else { endSocial(c); return }
        let dx = px - c.pos.x
        if abs(dx) > 3 {
            c.facing = dx > 0 ? 1 : -1
            c.pos.x += c.facing * min(abs(dx), c.species.walkSpeed * 0.7 * dt)   // sneaky, slow
            return
        }
        // At the edge, half off-screen: turn around and look back at the desktop.
        c.facing = -c.facing
        endSocial(c)
        c.idleVariant = "look"
        c.set(.idle, duration: 2.6)
    }
}
