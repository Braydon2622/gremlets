/// Things the renderer may want to show (hearts, sleep bubbles, sounds).
public enum WorldEvent: Equatable, Sendable {
    case poked(Int)
    case petted(Int)
    case fellAsleep(Int)
    case wokeUp(Int)
    case landed(Int, impact: Double)
    case dizzy(Int)
    case alert(Int)
}

/// The simulation: creatures, the surfaces they live on, physics and input.
/// Pure Swift with no AppKit, driven by a platform layer that feeds it screens, windows, the cursor and time.
public final class World {
    // Tuning (points, seconds).
    public var gravity: Double = 2200
    public var maxFallSpeed: Double = 2600
    public var maxJumpHeight: Double = 320
    public var maxJumpDistance: Double = 420
    public var energyDrainPerSecond: Double = 0.006
    /// Landing faster than this (pt/s) leaves a creature seeing stars.
    public var dizzyImpact: Double = 1700

    public private(set) var screens: [Rect] = []
    public private(set) var windows: [Int: Rect] = [:]
    public private(set) var surfaces: [Surface] = []
    public private(set) var creatures: [Creature] = []
    public var cursor: Vec2?
    public var rng: SplitMix64
    public private(set) var events: [WorldEvent] = []

    private var nextID = 1
    private var dragSamples: [(t: Double, p: Vec2)] = []
    private var clock: Double = 0

    public init(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        rng = SplitMix64(seed: seed)
    }

    // MARK: Environment

    /// Updates screens and windows. Creatures standing on a window that moved ride along with it;
    /// if their window closed or got covered they'll fall on the next step.
    public func setEnvironment(screens: [Rect], windowsFrontToBack: [WindowInfo]) {
        var newWindows: [Int: Rect] = [:]
        for w in windowsFrontToBack { newWindows[w.id] = w.frame }
        for c in creatures where c.isGrounded {
            guard let owner = c.groundOwner, owner >= 0, let old = windows[owner], let new = newWindows[owner] else { continue }
            c.pos.x += new.minX - old.minX
            c.pos.y += new.maxY - old.maxY
        }
        self.screens = screens
        self.windows = newWindows
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
        c.set(.airborne)
        creatures.append(c)
        return c
    }

    public func remove(_ id: Int) { creatures.removeAll { $0.id == id } }

    /// Top-most creature whose sprite has an opaque pixel at `p`.
    public func creature(at p: Vec2) -> Creature? {
        creatures.last { $0.hitTest(p) }
    }

    public func drainEvents() -> [WorldEvent] {
        defer { events.removeAll() }
        return events
    }

    func emit(_ e: WorldEvent) { events.append(e) }

    /// Suggested simulation rate. Lets the platform layer throttle the loop to save CPU when nothing moves.
    public var desiredTickRate: Double {
        if creatures.contains(where: { $0.activity == .airborne || $0.activity == .dragged }) { return 60 }
        if creatures.contains(where: { ![.idle, .sleep].contains($0.activity) }) { return 30 }
        return 12
    }

    // MARK: Input

    public func poke(_ c: Creature) {
        guard c.isGrounded else { return }
        if c.activity == .sleep || c.activity == .yawn {
            // Startled awake: jolt, then rub eyes. A bit grumpy, so no energy bonus.
            c.set(.wake, duration: c.animationLength(for: .wake))
            emit(.wokeUp(c.id))
            return
        }
        c.energy = min(1, c.energy + 0.1)
        c.set(.react, duration: c.animationLength(for: .react) + 0.15)
        emit(.poked(c.id))
    }

    /// Call with cursor movement over a creature; enough rubbing counts as petting.
    public func pet(_ c: Creature, distance: Double) {
        guard c.isGrounded, ![.react, .wake, .dizzy].contains(c.activity) else { return }
        c.petAmount += distance
        if c.petAmount > 220 {
            c.petAmount = 0
            if c.activity == .sleep { return } // let sleeping gremlets lie, petting doesn't wake them
            c.energy = min(1, c.energy + 0.05)
            c.set(.pet, duration: 1.4)
            emit(.petted(c.id))
        }
    }

    public func beginDrag(_ c: Creature, at p: Vec2, time: Double) {
        c.grabOffset = c.pos - p
        c.groundOwner = nil
        c.vel = .zero
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
        for c in creatures { update(c, dt) }
    }

    private func update(_ c: Creature, _ dt: Double) {
        c.animTime += dt
        if c.activity == .sleep {
            c.energy = min(1, c.energy + dt * 0.06)
        } else if c.activity != .dragged {
            c.energy = max(0, c.energy - dt * energyDrainPerSecond * (c.activity == .walk || c.activity == .chase ? 1.5 : 1))
        }

        switch c.activity {
        case .dragged:
            return
        case .airborne:
            integrateAirborne(c, dt)
            return
        default:
            break
        }

        // Grounded: make sure something still supports us (windows move, close, or get covered).
        guard let support = supportingSurface(for: c) else {
            c.groundOwner = nil
            c.vel = Vec2(c.activity == .walk || c.activity == .chase ? c.facing * c.species.walkSpeed * 0.6 : 0, 0)
            if c.activity == .sleep || c.activity == .yawn { emit(.wokeUp(c.id)) }
            c.set(.airborne)
            return
        }
        c.pos.y = support.y
        c.groundOwner = support.ownerID

        c.timer -= dt
        switch c.activity {
        case .walk, .chase:
            walk(c, dt, on: support)
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
        if c.timer <= 0 && c.activity != .crouch { Brain.decide(c, in: self) }
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
        let nx = c.pos.x + c.facing * speed * dt

        // Screen walls: turn around.
        let (lo, hi) = horizontalLimits(for: c, atY: c.pos.y + 1)
        if nx < lo || nx > hi {
            c.facing *= -1
            if c.activity == .chase { c.set(.idle, duration: 1) }
            return
        }
        // Ledge: usually turn back, sometimes walk off and tumble down.
        if !support.supports(x: nx) && !c.edgeDecisionMade {
            c.edgeDecisionMade = true
            if rng.chance(0.65) || c.activity == .chase {
                c.facing *= -1
                return
            }
        }
        if support.supports(x: nx) { c.edgeDecisionMade = false }
        c.pos.x = nx
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

        // Land on the highest one-way platform crossed while falling.
        if c.vel.y <= 0 {
            let landing = surfaces
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
                if impact > dizzyImpact {
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

    // MARK: Queries

    func supportingSurface(for c: Creature) -> Surface? {
        let candidates = surfaces.filter { abs($0.y - c.pos.y) <= 2 && $0.supports(x: c.pos.x) }
        return candidates.first { $0.ownerID == c.groundOwner } ?? candidates.max { $0.y < $1.y }
    }

    func screen(containingX x: Double, y: Double) -> Rect? {
        screens.first { x >= $0.minX && x < $0.maxX && y >= $0.minY - 2 && y < $0.maxY }
            ?? screens.first { x >= $0.minX && x < $0.maxX }
    }

    /// Horizontal range a creature can move in at height y: its screen, extended across touching monitors.
    func horizontalLimits(for c: Creature, atY y: Double) -> (Double, Double) {
        let half = c.size.x * 0.3
        guard let scr = screen(containingX: c.pos.x, y: y) ?? screens.first else { return (-.infinity, .infinity) }
        var lo = scr.minX, hi = scr.maxX
        // Extend through neighbouring screens at this height.
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
        let dh = s.y - c.pos.y
        let apex = dh + 40
        let vy = (2 * gravity * apex).squareRoot()
        // Time until we come back down to the target height.
        let t = (vy + (vy * vy - 2 * gravity * dh).squareRoot()) / gravity
        return Vec2((tx - c.pos.x) / t, vy)
    }

    /// Starts a jump with a short crouch for anticipation.
    func launch(_ c: Creature, velocity: Vec2) {
        c.pendingLaunch = velocity
        c.set(.crouch, duration: 0.16)
    }
}
