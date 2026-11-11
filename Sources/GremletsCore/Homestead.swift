import Foundation

/// Two more things on the hanging home's porch (Hanging.swift has the pantry, supper, the bird and the nudge):
///
/// - **The rain barrel.** A little wooden barrel at the end of the porch fills when it really rains where you are
///   (the weather), and a bit with the morning dew. When the moss could do with it, a Gremlet floats up, fills its
///   can from the barrel and comes back down to water: rainwater does the moss twice the good.
/// - **The basket lift.** A woven basket hangs on a rope under the porch. A Gremlet on the window top below can wave
///   it down and ride it up home (and back down again), instead of floating: the basket lowers, it climbs in, and
///   up it goes, hand over hand. Only to a window top a short way below, so the rope stays up in the corner.
public struct HomeBasket: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Coming down empty for someone waiting below.
        case fetching
        /// Down at the bottom, waiting for them to climb in.
        case waiting
        /// Someone aboard, going up or down.
        case riding
        /// Going back up empty.
        case returning
    }
    public let x: Double
    /// The basket's floor (global).
    public internal(set) var y: Double
    public internal(set) var phase: Phase
    /// Who it's for.
    public internal(set) var rider: Int
    /// Up to the porch (boarding at the bottom), or down from it.
    let up: Bool
    /// Where it stops at the bottom: that window top's id and height.
    let landingOwner: Int
    let landingY: Double
    var waitedSince = 0.0
}

extension World {
    /// How far below the porch the basket goes (keeps the rope up near the top of the screen).
    static let basketReach = 420.0
    static let basketSpeed = 46.0

    /// Where the basket's rope hangs from (under the porch, between the door and the barrel).
    public var basketX: Double? {
        guard let p = homePorch else { return nil }
        return p.minX + min(62, p.width * 0.55)
    }

    /// The basket at rest, just under the porch.
    var basketRestY: Double? { homePorch.map { $0.y - 14 } }

    /// Where the basket is right now (at rest when nobody's using it).
    public var basketPos: Vec2? {
        guard let x = basketX, let rest = basketRestY else { return nil }
        if let b = basket { return Vec2(b.x, b.y) }
        return Vec2(x, rest)
    }

    /// The window top (or floor) right under the basket, if it's near enough for the rope.
    public func basketLanding() -> Surface? {
        guard let x = basketX, let porch = homePorch else { return nil }
        return builtSurfaces.filter { ($0.kind == .windowTop || $0.kind == .floor) && $0.supports(x: x - 12) && $0.supports(x: x + 12)
            && $0.y < porch.y - 60 && porch.y - $0.y <= World.basketReach }
            .max { $0.y < $1.y }
    }

    /// Where the barrel stands on the porch.
    public var barrelSpot: Vec2? {
        guard let p = homePorch else { return nil }
        return Vec2(p.maxX - 30, p.y)
    }

    func homesteadChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !compact, isFree(c), c.isGrounded, !c.isAsleep, c.mossTask == nil, let porch = homePorch, let s = supportingSurface(for: c),
              sameScreen(c.pos, Vec2(porch.minX, porch.y)) else { return }
        // The basket: up home from the window top below, or down from the porch.
        if basket == nil, clock >= nextBasketAt, let x = basketX {
            if let landing = basketLanding(), s.ownerID == landing.ownerID, abs(s.y - landing.y) < 1, abs(c.pos.x - x) < 500 {
                add("basketUp", 0.7 + (isNight || c.energy < 0.4 ? 0.8 : 0)) { self.startBasket(c, up: true, landing: landing) }
            }
            if s.ownerID == porch.ownerID, let landing = basketLanding() {
                add("basketDown", 0.8) { self.startBasket(c, up: false, landing: landing) }
            }
        }
        // Rainwater for the moss.
        if rainBarrel >= 0.2, !c.hasRainwater, clock >= nextBarrelAt, mossMinutes >= 10, mossCare < 0.85 || mossThirsty,
           s.ownerID != porch.ownerID, s.kind == .windowTop || s.kind == .floor, let spot = barrelSpot,
           !creatures.contains(where: { if case .fetchWater? = $0.mossTask?.kind { return true }; return false }) {
            add("fetchWater", 0.6 + (mossThirsty ? 2.5 : 0) + (1 - mossCare)) {
                self.nextBarrelAt = self.clock + self.rng.range(60, 150)
                self.endSocial(c)
                c.mossTask = MossTask(kind: .fetchWater, started: self.clock)
                c.carrying = "can"
                self.startFloat(c, to: Vec2(spot.x - 14, porch.y), ride: .dandelion)
            }
        }
    }

    // MARK: The rain barrel

    func updateBarrel(_ dt: Double) {
        let before = rainBarrel
        if weather?.sky.isWet == true { rainBarrel += dt / (weather?.sky == .drizzle ? 1500 : 800) }
        if (5...8).contains(localHour) { rainBarrel += dt / 9000 }   // morning dew
        rainBarrel = min(1, rainBarrel)
        if before < 1, rainBarrel >= 1 { homeEvents.append(.barrelFull(barrelSpot ?? .zero)) }
    }

    func fetchWaterDecide(_ c: Creature, _ t: inout MossTask, on s: Surface) {
        guard let porch = homePorch, let spot = barrelSpot, s.ownerID == porch.ownerID else {
            // Didn't make it up (the house is tucked away): never mind.
            c.mossTask = nil; c.set(.idle, duration: 0.4); return
        }
        if !t.acting {
            let x = spot.x - 14
            if abs(c.pos.x - x) > 5, clock - t.started < 25 { c.targetX = x; c.set(.walk, duration: 10); return }
            t.acting = true; c.mossTask = t
            c.facing = 1
            c.carrying = "can"
            c.workPose = "crouch"; c.set(.work, duration: 1.8)
            return
        }
        c.mossTask = nil
        guard rainBarrel >= 0.1 else { c.set(.react, duration: c.animationLength(for: .react)); return }
        rainBarrel = max(0, rainBarrel - 0.2)
        c.hasRainwater = true
        homeCare += 1
        homeEvents.append(.drewWater(Vec2(spot.x, spot.y + 14), by: c.id))
        // Back down: in the basket if it's free and there's a window top under it, or under a leaf.
        if basket == nil, let landing = basketLanding() { startBasket(c, up: false, landing: landing) }
        else { c.driftDown = true; c.set(.idle, duration: 0.4) }
    }

    // MARK: The basket lift

    func startBasket(_ c: Creature, up: Bool, landing: Surface) {
        guard let x = basketX, let rest = basketRestY else { return }
        nextBasketAt = clock + rng.range(50, 140)
        endSocial(c)
        basket = HomeBasket(x: x, y: rest, phase: up ? .fetching : .riding, rider: c.id, up: up, landingOwner: landing.ownerID, landingY: landing.y)
        if up {
            // Wave it down, then walk over to where it'll land.
            c.targetX = x; c.facing = x > c.pos.x ? 1 : -1
            c.groveTask = .basket
            c.set(.walk, duration: 14)
            homeEvents.append(.basketCalled(by: c.id))
        } else {
            c.targetX = x; c.facing = x > c.pos.x ? 1 : -1
            c.groveTask = .basket
            c.set(.walk, duration: 8)
            basket?.phase = .waiting
            basket?.waitedSince = clock
        }
    }

    /// Walked over to the basket: in it climbs, or (it's still on its way down) waits for it, looking up.
    func reachedBasket(_ c: Creature) {
        guard let b = basket, b.rider == c.id else { c.set(.idle, duration: 0.5); return }
        if b.phase == .waiting { boardBasket(c); return }
        c.groveTask = .basket
        c.facing = 1
        c.idleVariant = "look"; c.set(.idle, duration: 25)
    }

    /// Climbs in (it's walked over to the basket).
    func boardBasket(_ c: Creature) {
        guard var b = basket, b.rider == c.id, b.phase == .waiting else { c.set(.idle, duration: 0.5); return }
        c.basketRide = true
        c.groundOwner = nil
        c.vel = .zero
        c.pos = Vec2(b.x, b.y)
        c.set(.float, duration: 9999)
        b.phase = .riding
        basket = b
        homeEvents.append(.basketAboard(by: c.id))
    }

    func updateBasket(_ dt: Double) {
        guard var b = basket else { return }
        guard let porch = homePorch, let rest = basketRestY, abs(b.x - (basketX ?? .infinity)) < 1 else { dropBasket(); return }
        let rider = creature(id: b.rider)
        // The window it lands on moved or closed: whoever's aboard hops out, and it goes home.
        let landingHere = builtSurfaces.contains { $0.ownerID == b.landingOwner && abs($0.y - b.landingY) < 1 && $0.supports(x: b.x) }
        if !landingHere, b.phase != .returning { dropBasket(); return }
        let bottom = b.landingY
        switch b.phase {
        case .fetching:
            b.y = max(bottom, b.y - dt * World.basketSpeed * 1.5)
            if b.y <= bottom { b.phase = .waiting; b.waitedSince = clock }
        case .waiting:
            // Not coming after all (it got distracted, picked up, called away): back up.
            let stillComing = rider.map { $0.groveTask == .basket && !$0.isAsleep && $0.activity != .dragged } ?? false
            if !stillComing || clock - b.waitedSince > 20 { b.phase = .returning; if rider?.groveTask == .basket { rider?.groveTask = nil } }
            // Waiting right there for it: in it climbs.
            else if let c = rider, c.isGrounded, abs(c.pos.x - b.x) < 10, c.activity != .walk { basket = b; boardBasket(c); return }
        case .riding:
            guard let c = rider, c.basketRide, c.activity == .float else { rider?.basketRide = false; b.phase = .returning; break }
            let target = b.up ? rest : bottom
            let dir = target > b.y ? 1.0 : -1.0
            // Hand over hand: a little pause in each pull.
            let pull = 0.55 + 0.45 * abs(sin(clock * 3.2))
            b.y += dir * dt * World.basketSpeed * pull
            if (dir > 0 && b.y >= target) || (dir < 0 && b.y <= target) {
                b.y = target
                c.basketRide = false
                c.groveTask = nil
                if b.up {
                    c.pos = Vec2(b.x + 10, porch.y); c.groundOwner = porch.ownerID
                } else {
                    c.pos = Vec2(b.x, bottom); c.groundOwner = b.landingOwner
                }
                c.vel = .zero
                c.set(.land, duration: c.animationLength(for: .land))
                homeEvents.append(.basketArrived(Vec2(b.x, b.up ? porch.y : bottom), by: c.id, up: b.up))
                b.phase = .returning
            } else {
                c.pos = Vec2(b.x, b.y)
                c.vel = .zero
            }
        case .returning:
            b.y = min(rest, b.y + dt * World.basketSpeed * 1.6)
            if b.y >= rest { basket = nil; return }
        }
        basket = b
    }

    /// Something went wrong mid-ride (the house was tucked away, a window closed): whoever's aboard hops out.
    func dropBasket() {
        if let b = basket, let c = creature(id: b.rider) {
            if c.basketRide { c.basketRide = false; c.groundOwner = nil; c.vel = Vec2(c.facing * 40, 120); c.set(.airborne) }
            if c.groveTask == .basket { c.groveTask = nil }
        }
        basket = nil
    }
}
