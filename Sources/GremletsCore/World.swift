import Foundation  // math only (sin); available on Linux and Windows too

/// Things the renderer may want to show (hearts, particles, sounds).
public enum WorldEvent: Equatable, Sendable {
    case poked(Int)
    case petted(Int)
    case fellAsleep(Int)
    case wokeUp(Int)
    case landed(Int, impact: Double)
    case dizzy(Int)
    case alert(Int)
    case special(Int, effect: String)
    case greet(Int, Int)
    case tagged(Int)
    case bump(Int, Int)
    case stacked(rider: Int, carrier: Int)
    case danceBeat(Int)
    case startled(Int)
    case tookOff(Int)
}

/// The simulation: creatures, the surfaces they live on, physics, social behavior and input.
/// Pure Swift with no AppKit, driven by a platform layer that feeds it screens, windows, the cursor and time.
public final class World {
    // Tuning (points, seconds).
    public var gravity: Double = 2200
    public var maxFallSpeed: Double = 2600
    public var maxJumpHeight: Double = 320
    public var maxJumpDistance: Double = 420
    public var energyDrainPerSecond: Double = 0.0045
    /// Landing faster than this (pt/s) leaves a creature seeing stars.
    public var dizzyImpact: Double = 1700
    public var flySpeed: Double = 210
    /// Chance that two creatures walking into each other bonk and bounce (otherwise they squeeze past).
    public var bumpChance: Double = 0.35
    /// Extra sleepiness (e.g. late at night). Multiplies energy drain.
    public var sleepyFactor: Double = 1
    /// Focus mode (see Companion.swift): calm, dozing Gremlets.
    public internal(set) var calm = false
    /// You're at your Mac (recent keyboard/mouse input). Hobbies only start, and only make progress, while you are.
    public var userActive = true
    /// At most this many Gremlets on a hobby at once.
    public var maxHobbies = 2
    var _gardenSpots: [Double] = []
    /// Pending wishes: the next seed planted is epic or better.
    public internal(set) var wishes = 0
    /// Calendar month (1-12) and whether it's night, set by the platform layer (seasonal and night-only plants).
    public var month = 6
    public var isNight = false

    public private(set) var screens: [Rect] = []
    public private(set) var windows: [Int: Rect] = [:]
    /// Window ids, front-most first.
    public private(set) var windowOrder: [Int] = []
    /// Screen floors and window tops (creature heads are added on the fly, see `allSurfaces`).
    public private(set) var surfaces: [Surface] = []
    public private(set) var creatures: [Creature] = []
    public var cursor: Vec2?
    /// Simulation time (seconds), the clock jobs and events are stamped with.
    public var time: Double { clock }
    public var rng: SplitMix64
    public private(set) var events: [WorldEvent] = []

    private var nextID = 1
    private var dragSamples: [(t: Double, p: Vec2)] = []
    var clock: Double = 0
    private var lastCursor: Vec2?
    var cursorSpeed: Double = 0

    public init(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        rng = SplitMix64(seed: seed)
    }

    /// Surface owner ids at or below this value belong to creatures (heads you can stand on).
    static let creatureOwnerBase = -1000
    static func creatureOwner(_ id: Int) -> Int { creatureOwnerBase - id }
    static func carrierID(_ owner: Int?) -> Int? {
        guard let o = owner, o <= creatureOwnerBase, o > shelfOwnerBase else { return nil }
        return creatureOwnerBase - o
    }

    // MARK: Environment

    /// Updates screens and windows. Creatures standing on a window that moved ride along with it;
    /// if their window closed or got covered they'll fall on the next step.
    public func setEnvironment(screens: [Rect], windowsFrontToBack: [WindowInfo]) {
        var newWindows: [Int: Rect] = [:]
        for w in windowsFrontToBack { newWindows[w.id] = w.frame }
        for c in creatures where c.isGrounded {
            guard let owner = windowFor(owner: c.groundOwner), let old = windows[owner], let new = newWindows[owner] else { continue }
            let d = Vec2(new.minX - old.minX, new.maxY - old.maxY)
            c.pos += d
            // Anyone standing on this creature's head comes along for the ride.
            for r in creatures where r.groundOwner == c.carrierOwnerID { r.pos += d }
        }
        self.screens = screens
        self.windows = newWindows
        self.windowOrder = windowsFrontToBack.map(\.id)
        surfaces = SurfaceBuilder.build(screens: screens, windowsFrontToBack: windowsFrontToBack)
    }

    // MARK: Creatures

    @discardableResult
    public func spawn(_ species: SpeciesInfo, at p: Vec2? = nil) -> Creature {
        let start: Vec2
        if let p { start = p } else if let s = screens.first {
            start = Vec2(rng.range(s.minX + 80, max(s.minX + 81, s.maxX - 80)), s.maxY - species.pointSize.y - 10)
        } else { start = .zero }
        let c = Creature(id: nextID, species: species, pos: start)
        nextID += 1
        c.facing = rng.chance(0.5) ? 1 : -1
        c.prevPos = start
        c.set(.airborne)
        creatures.append(c)
        return c
    }

    public func remove(_ id: Int) {
        creatures.removeAll { $0.id == id }
        for c in creatures where c.friendID == id { c.friendID = nil; c.social = .none }
    }

    /// Top-most creature whose sprite has an opaque pixel at `p`.
    public func creature(at p: Vec2) -> Creature? {
        creatures.last { $0.hitTest(p) }
    }

    func creature(id: Int?) -> Creature? {
        guard let id else { return nil }
        return creatures.first { $0.id == id }
    }

    public func drainEvents() -> [WorldEvent] {
        defer { events.removeAll() }
        return events
    }

    func emit(_ e: WorldEvent) { events.append(e) }

    /// Suggested simulation rate. Lets the platform layer throttle the loop to save CPU when nothing moves.
    public var desiredTickRate: Double {
        if creatures.contains(where: { [.airborne, .dragged, .fly, .run].contains($0.activity) }) { return 60 }
        if creatures.contains(where: { ![.idle, .sleep].contains($0.activity) }) { return 30 }
        return 12
    }

    // MARK: Input

    public func poke(_ c: Creature) {
        guard c.isGrounded else { return }
        if c.isAsleep && calm {
            emit(.poked(c.id))   // focus mode: a sleepy acknowledgement, no wake-up
            return
        }
        if c.isAsleep {
            // Startled awake: jolt, then rub eyes. A bit grumpy, so no energy bonus.
            c.set(.wake, duration: c.animationLength(for: .wake))
            emit(.wokeUp(c.id))
            return
        }
        c.energy = min(1, c.energy + 0.1)
        endSocial(c)
        encourage(c)
        countPokeForMystery(c)
        c.set(.react, duration: c.animationLength(for: .react) + 0.15)
        emit(.poked(c.id))
    }

    /// Call with cursor movement over a creature; enough rubbing counts as petting.
    public func pet(_ c: Creature, distance: Double) {
        guard c.isGrounded, ![.react, .wake, .dizzy, .run].contains(c.activity) else { return }
        c.petAmount += distance
        if c.petAmount > 220 {
            c.petAmount = 0
            if c.activity == .sleep { return } // let sleeping gremlets lie, petting doesn't wake them
            c.energy = min(1, c.energy + 0.05)
            endSocial(c)
            if c.bond >= 0.5 && !calm && rng.chance(0.5) {
                startSpecial(c)        // close friends show off for you
                emit(.petted(c.id))
            } else {
                c.set(.pet, duration: 1.4)
                emit(.petted(c.id))
            }
        }
    }

    public func beginDrag(_ c: Creature, at p: Vec2, time: Double) {
        c.grabOffset = c.pos - p
        c.groundOwner = nil
        c.vel = .zero
        endSocial(c)
        c.set(.dragged)
        dragSamples = [(time, p)]
    }

    public func drag(_ c: Creature, to p: Vec2, time: Double) {
        guard c.activity == .dragged else { return }
        let newPos = p + c.grabOffset
        if newPos.x != c.pos.x { c.facing = newPos.x > c.pos.x ? 1 : -1 }
        c.pos = newPos
        dragSamples.append((time, p))
        dragSamples.removeAll { time - $0.t > 0.1 }
    }

    /// Releases a dragged creature with the cursor's recent velocity, so it can be thrown.
    public func endDrag(_ c: Creature, time: Double) {
        guard c.activity == .dragged else { return }
        var v = Vec2.zero
        if let first = dragSamples.first, let last = dragSamples.last, last.t - first.t > 0.01, time - last.t < 0.08 {
            v = (last.p - first.p) * (1 / (last.t - first.t))
        }
        let len = v.length
        if len > 2400 { v = v * (2400 / len) }
        c.vel = v
        c.set(.airborne)
        dragSamples.removeAll()
    }

    // MARK: Simulation

    public func step(_ rawDt: Double) {
        let dt = min(max(rawDt, 0), 1.0 / 20)
        clock += dt
        if let cur = cursor {
            if let last = lastCursor, dt > 0 { cursorSpeed = cursorSpeed * 0.5 + (cur - last).length / dt * 0.5 }
            lastCursor = cur
        }
        for c in creatures { c.prevPos = c.pos }
        // Lower creatures first so a carrier has moved before the friend standing on its head.
        for c in creatures.sorted(by: { $0.pos.y < $1.pos.y }) { update(c, dt) }
        resolveBumps()
        checkStartle()
    }

    private func update(_ c: Creature, _ dt: Double) {
        c.animTime += dt * c.animSpeed
        c.bumpCooldown = max(0, c.bumpCooldown - dt)
        c.startleCooldown = max(0, c.startleCooldown - dt)
        c.tagImmunity = max(0, c.tagImmunity - dt)
        if c.activity == .sleep {
            c.energy = min(1, c.energy + dt * 0.06)
        } else if c.activity != .dragged {
            let busy = [.walk, .chase, .run, .fly, .dance].contains(c.activity)
            c.energy = max(0, c.energy - dt * energyDrainPerSecond * sleepyFactor * (busy ? 1.6 : 1))
        }

        switch c.activity {
        case .dragged:
            return
        case .airborne:
            integrateAirborne(c, dt)
            return
        case .fly:
            c.timer -= dt
            updateFlight(c, dt)
            return
        case .float:
            updateFloat(c, dt)
            return
        default:
            break
        }

        // Standing on a friend's head: move with them.
        if let carrier = creature(id: World.carrierID(c.groundOwner)) {
            c.pos += carrier.pos - carrier.prevPos
        }

        // Grounded: make sure something still supports us (windows move, close, or get covered).
        guard let support = supportingSurface(for: c) else {
            let walking = [.walk, .chase, .run, .follow, .peek].contains(c.activity)
            c.groundOwner = nil
            c.vel = Vec2(walking ? c.facing * c.species.walkSpeed * 0.6 : 0, 0)
            if c.isAsleep { emit(.wokeUp(c.id)) }
            endSocial(c)
            c.set(.airborne)
            return
        }
        c.pos.y = support.y
        c.groundOwner = support.ownerID

        c.timer -= dt
        if let job = c.job, updateJob(c, job, dt, on: support) { return }
        if c.visitingID != nil, updateVisit(c, dt, on: support) { return }
        if c.tendX != nil, updateTending(c, dt, on: support) { return }
        switch c.activity {
        case .idle:
            faceCursorIfNear(c)
        case .walk, .chase:
            walk(c, dt, on: support)
        case .follow:
            updateFollow(c, dt, on: support)
        case .run:
            updateTag(c, dt, on: support)
        case .peek:
            updatePeek(c, dt)
        case .dance:
            c.beatTimer -= dt
            if c.beatTimer <= 0 { c.beatTimer = 0.55; emit(.danceBeat(c.id)) }
        case .crouch:
            if c.timer <= 0 {
                c.vel = c.pendingLaunch
                if abs(c.vel.x) > 1 { c.facing = c.vel.x > 0 ? 1 : -1 }
                c.groundOwner = nil
                c.pos.y += 1
                c.set(.airborne)
                return
            }
        case .yawn:
            if c.timer <= 0 {
                c.set(.sleep, duration: rng.range(12, 28) * c.species.sleepiness.clamped(0.6, 1.6))
                emit(.fellAsleep(c.id))
            }
            return
        case .sleep:
            if calm { return }  // focus mode: keep dozing until the break
            if c.timer <= 0 || c.energy >= 1 {
                c.set(.wake, duration: c.animationLength(for: .wake))
                emit(.wokeUp(c.id))
            }
            return
        case .alert:
            if c.timer <= 0 { c.set(.chase, duration: 6) }
            return
        default:
            break
        }
        if c.timer <= 0 && c.activity != .crouch {
            if c.activity == .run { endTag(c) }
            endSocial(c)
            if c.job != nil { c.set(.idle, duration: 0.2) } else { Brain.decide(c, in: self) }
        }
    }

    /// Moves a grounded creature horizontally, handling screen walls and ledges. Returns false if it turned.
    @discardableResult
    func move(_ c: Creature, _ dt: Double, speed: Double, on support: Surface, ledgeTurnChance: Double = 0.65) -> Bool {
        let nx = c.pos.x + c.facing * speed * dt
        let (lo, hi) = horizontalLimits(for: c, atY: c.pos.y + 1)
        if nx < lo || nx > hi {
            c.facing *= -1
            return false
        }
        if !support.supports(x: nx) && !c.edgeDecisionMade {
            c.edgeDecisionMade = true
            if rng.chance(ledgeTurnChance) {
                c.facing *= -1
                return false
            }
        }
        if support.supports(x: nx) { c.edgeDecisionMade = false }
        c.pos.x = nx
        return true
    }

    private func walk(_ c: Creature, _ dt: Double, on support: Surface) {
        if c.activity == .chase {
            if let cur = cursor, abs(cur.y - c.pos.y) < 260 { c.targetX = cur.x }
            if let tx = c.targetX {
                if abs(tx - c.pos.x) < 14 {
                    c.set(.react, duration: c.animationLength(for: .react) + 0.15)
                    emit(.poked(c.id))
                    return
                }
                c.facing = tx > c.pos.x ? 1 : -1
            }
        }
        let speed = c.species.walkSpeed * (c.activity == .chase ? 1.6 : 1)
        if !move(c, dt, speed: speed, on: support, ledgeTurnChance: c.activity == .chase ? 1 : 0.65), c.activity == .chase {
            c.set(.idle, duration: 1)
        }
    }

    private func faceCursorIfNear(_ c: Creature) {
        guard let cur = cursor else { return }
        let dx = cur.x - c.pos.x
        if abs(dx) > 14 && abs(dx) < 260 && abs(cur.y - (c.pos.y + c.size.y / 2)) < 180 { c.facing = dx > 0 ? 1 : -1 }
    }

    private func integrateAirborne(_ c: Creature, _ dt: Double) {
        let prev = c.pos
        c.vel.y = max(c.vel.y - gravity * dt, -maxFallSpeed)
        var next = prev + c.vel * dt

        // Walls and ceiling of the screen we're on (crossing onto another monitor is allowed).
        let (lo, hi) = horizontalLimits(for: c, atY: next.y)
        if next.x < lo || next.x > hi {
            next.x = next.x.clamped(lo, hi)
            c.vel.x = -c.vel.x * 0.45
            c.facing = c.vel.x >= 0 ? 1 : -1
        }
        if let scr = screen(containingX: next.x, y: prev.y), next.y + c.size.y > scr.maxY {
            next.y = scr.maxY - c.size.y
            c.vel.y = min(c.vel.y, 0) * 0.3
        }

        // Land on the highest one-way platform crossed while falling (including friends' heads).
        if c.vel.y <= 0 {
            let landing = allSurfaces(excluding: c)
                .filter { prev.y >= $0.y - 0.5 && next.y <= $0.y && $0.supports(x: next.x) }
                .max { $0.y < $1.y }
            if let s = landing {
                let impact = -c.vel.y
                next.y = s.y
                c.pos = next
                c.vel = .zero
                c.groundOwner = s.ownerID
                c.edgeDecisionMade = false
                emit(.landed(c.id, impact: impact))
                if let carrier = World.carrierID(s.ownerID) {
                    emit(.stacked(rider: c.id, carrier: carrier))
                    c.set(.react, duration: c.animationLength(for: .react) + 0.1)
                } else if impact > dizzyImpact {
                    c.set(.dizzy, duration: 1.9)
                    emit(.dizzy(c.id))
                } else {
                    c.set(.land, duration: impact > 900 ? max(0.3, c.animationLength(for: .land)) : 0.14)
                }
                return
            }
        }
        c.pos = next

        // Safety net: fell out of every screen (e.g. monitor unplugged). Respawn at the top of the main screen.
        if let lowest = screens.map(\.minY).min(), c.pos.y < lowest - 200, let main = screens.first {
            c.pos = Vec2(main.minX + main.w / 2, main.maxY - c.size.y - 10)
            c.vel = .zero
        }
    }

    // MARK: Flight

    /// Takes off toward a random surface (window top or floor) within reach.
    func startFlight(_ c: Creature, awayFrom: Vec2? = nil) {
        let options = surfaces.filter { s in
            guard s.width >= 40 else { return false }
            let x = c.pos.x.clamped(s.minX + 20, s.maxX - 20)
            if let a = awayFrom, (x - a.x) * (c.pos.x - a.x) < 0 { return false }
            return abs(x - c.pos.x) < 800 && abs(s.y - c.pos.y) > 20
        }
        guard let s = options.isEmpty ? nil : options[Int.random(in: 0..<options.count, using: &rng)] else {
            launch(c, velocity: Vec2(c.facing * 80, 500)); return
        }
        let inset = min(40, s.width / 2 - 1)
        var tx = rng.range(s.minX + inset, s.maxX - inset)
        if abs(tx - c.pos.x) > 800 { tx = c.pos.x.clamped(s.minX + inset, s.maxX - inset) }
        c.flyTarget = Vec2(tx, s.y)
        c.groundOwner = nil
        c.vel = Vec2(c.facing * 40, 220)
        c.facing = tx > c.pos.x ? 1 : -1
        endSocial(c)
        c.set(.fly, duration: 7)
        emit(.tookOff(c.id))
    }

    private func updateFlight(_ c: Creature, _ dt: Double) {
        guard let target = c.flyTarget else { c.set(.airborne); return }
        let aim = target + Vec2(0, 34)       // arrive from just above, then drop on
        let to = aim - c.pos
        let dist = to.length
        let speed = min(flySpeed, dist * 2.5 + 30)
        var desired = dist > 0.1 ? to * (speed / dist) : .zero
        desired.y += sin(clock * 7 + Double(c.id)) * 45  // fluttery bob
        let k = min(1, 3.2 * dt)
        c.vel = c.vel + (desired - c.vel) * k
        var next = c.pos + c.vel * dt
        let (lo, hi) = horizontalLimits(for: c, atY: next.y)
        next.x = next.x.clamped(lo, hi)
        if let scr = screen(containingX: next.x, y: next.y), next.y + c.size.y > scr.maxY { next.y = scr.maxY - c.size.y }
        c.pos = next
        if abs(c.vel.x) > 12 { c.facing = c.vel.x > 0 ? 1 : -1 }
        if dist < 16 || c.timer <= 0 {
            c.flyTarget = nil
            c.vel = Vec2(c.vel.x * 0.25, -60)
            c.set(.airborne)
        }
    }

    // MARK: Cursor startle & bumps

    private func checkStartle() {
        guard let cur = cursor, cursorSpeed > 2800 else { return }
        for c in creatures where c.isGrounded && !c.isAsleep && c.startleCooldown <= 0 && c.activity != .dizzy {
            let center = c.pos + Vec2(0, c.size.y * 0.4)
            guard (cur - center).length < 90 else { continue }
            c.startleCooldown = 6
            emit(.startled(c.id))
            endSocial(c)
            let away: Double = cur.x < c.pos.x ? 1 : -1
            if c.species.flies {
                c.facing = away
                startFlight(c, awayFrom: cur)
            } else {
                c.facing = away
                c.groundOwner = nil
                c.vel = Vec2(away * 200, 460)
                c.set(.airborne)
            }
        }
    }

    /// Two creatures walking into each other bounce apart.
    private func resolveBumps() {
        let movers = creatures.filter { [.walk, .run, .chase, .follow, .peek].contains($0.activity) && $0.isGrounded && $0.bumpCooldown <= 0 }
        guard movers.count > 1 else { return }
        for i in 0..<movers.count { for j in (i + 1)..<movers.count {
            let a = movers[i], b = movers[j]
            guard abs(a.pos.y - b.pos.y) < 3 else { continue }
            let dx = b.pos.x - a.pos.x
            guard abs(dx) < (a.size.x + b.size.x) * 0.2 else { continue }
            guard a.facing * dx > 0 && b.facing * -dx > 0 else { continue }  // heading toward each other
            if (a.social == .chaser && a.friendID == b.id) || (b.social == .chaser && b.friendID == a.id) { continue }
            // Most of the time they just squeeze past each other; sometimes they bonk.
            a.bumpCooldown = 2; b.bumpCooldown = 2
            guard rng.chance(bumpChance) else { continue }
            for (c, dir) in [(a, dx > 0 ? -1.0 : 1.0), (b, dx > 0 ? 1.0 : -1.0)] {
                endSocial(c)
                c.bumpCooldown = 4
                c.groundOwner = nil
                c.vel = Vec2(dir * 150, 340)
                c.set(.airborne)
            }
            emit(.bump(a.id, b.id))
        }}
    }

    // MARK: Queries

    /// Static surfaces plus the tops of other creatures' heads (so friends can stand on each other).
    func allSurfaces(excluding c: Creature) -> [Surface] {
        // A shelf only holds the Gremlet who put it up.
        var out = surfaces + shelfSurfaces.filter { $0.ownerID == World.shelfOwner(c.id) }
        for o in creatures where o !== c && o.groundOwner != c.carrierOwnerID
            && World.carrierID(o.groundOwner) == nil && ![.airborne, .fly, .dragged].contains(o.activity) {
            let half = o.size.x * 0.17
            out.append(Surface(ownerID: o.carrierOwnerID, kind: .creature, y: o.pos.y + o.species.headTop,
                               minX: o.pos.x - half, maxX: o.pos.x + half))
        }
        return out
    }

    func supportingSurface(for c: Creature) -> Surface? {
        let candidates = allSurfaces(excluding: c).filter { abs($0.y - c.pos.y) <= 2 && $0.supports(x: c.pos.x) }
        return candidates.first { $0.ownerID == c.groundOwner } ?? candidates.max { $0.y < $1.y }
    }

    func screen(containingX x: Double, y: Double) -> Rect? {
        screens.first { x >= $0.minX && x < $0.maxX && y >= $0.minY - 2 && y < $0.maxY }
            ?? screens.first { x >= $0.minX && x < $0.maxX }
    }

    /// Horizontal range a creature can move in at height y: its screen, extended across touching monitors.
    func horizontalLimits(for c: Creature, atY y: Double, inset: Bool = true) -> (Double, Double) {
        let half = inset ? c.size.x * 0.3 : 0
        guard let scr = screen(containingX: c.pos.x, y: y) ?? screens.first else { return (-.infinity, .infinity) }
        var lo = scr.minX, hi = scr.maxX
        var changed = true
        while changed {
            changed = false
            for s in screens where y >= s.minY - 2 && y < s.maxY {
                if abs(s.maxX - lo) < 1 && s.minX < lo { lo = s.minX; changed = true }
                if abs(s.minX - hi) < 1 && s.maxX > hi { hi = s.maxX; changed = true }
            }
        }
        return (lo + half, hi - half)
    }

    /// Launch velocity to land on `s` near x, arcing `apexExtra` above it.
    func ballistic(from p: Vec2, toX tx: Double, y: Double, apexExtra: Double = 40) -> Vec2 {
        let dh = y - p.y
        let apex = max(dh, 0) + apexExtra
        let vy = (2 * gravity * apex).squareRoot()
        let t = (vy + max(0, vy * vy - 2 * gravity * dh).squareRoot()) / gravity
        return Vec2((tx - p.x) / t, vy)
    }

    /// Picks a surface above the creature it can jump onto and returns the launch velocity, if any.
    func jumpTarget(for c: Creature) -> Vec2? {
        let maxH = maxJumpHeight * c.species.jumpPower
        let options = surfaces.filter { s in
            let dh = s.y - c.pos.y
            guard dh > 25, dh < maxH, s.width >= 40 else { return false }
            let tx = c.pos.x.clamped(s.minX + 16, s.maxX - 16)
            return abs(tx - c.pos.x) < maxJumpDistance
        }
        guard !options.isEmpty else { return nil }
        let s = options[Int.random(in: 0..<options.count, using: &rng)]
        let inset = min(60, s.width / 2 - 1)
        var tx = c.pos.x.clamped(s.minX + inset, s.maxX - inset)
        tx += rng.range(-20, 20)
        tx = tx.clamped(s.minX + 12, s.maxX - 12)
        return ballistic(from: c.pos, toX: tx, y: s.y)
    }

    /// Starts a jump with a short crouch for anticipation.
    func launch(_ c: Creature, velocity: Vec2) {
        c.pendingLaunch = velocity
        c.set(.crouch, duration: 0.16)
    }
}
