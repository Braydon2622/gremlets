import Foundation  // exp()

/// Claude buddy: while Claude works on something, a Gremlet goes to that Claude window and works on a little
/// project of its own (a plant, a painting, a block tower) that grows the longer Claude works and is finished when
/// Claude is. The platform layer says which window and when; this file decides how the Gremlet gets there
/// (walk, jump, fly, or climb a ladder) and what it does once it's there. The platform layer draws the props.
public enum Craft: String, CaseIterable, Sendable {
    case garden, paint, build

    public var noun: String {
        switch self { case .garden: return "flower"; case .paint: return "painting"; case .build: return "tower" }
    }
}

public final class Job {
    public enum Phase: Equatable, Sendable { case travel, working, finished }

    public let craft: Craft
    /// The window Claude is running in (nil = no window found; the Gremlet works where it stands).
    public internal(set) var windowID: Int?
    public internal(set) var phase: Phase = .travel
    /// Seconds spent actually working (drives how far along the creation is).
    public internal(set) var workSeconds: Double = 0
    /// Set once Claude is done.
    public internal(set) var finishedAt: Double?
    /// Which side of the Gremlet the creation sits on (+1 right, -1 left).
    public internal(set) var propSide: Double = 1
    /// Where the creation stands. Relative to the window's top-left corner when on a window, else absolute.
    var spot: Vec2?
    var spotOnWindow = false
    /// Ladder from `ladderBaseY` (absolute) up to the window's top edge, `ladderX` relative to the window's left edge.
    public internal(set) var ladderX: Double?
    public internal(set) var ladderBaseY: Double?
    /// A per-job number the platform layer can use to vary the art (which picture gets painted...).
    public let seed: UInt64
    var started: Double
    var poseTimer = 0.0
    var beats = 0

    init(craft: Craft, windowID: Int?, seed: UInt64, now: Double) {
        self.craft = craft; self.windowID = windowID; self.seed = seed; self.started = now
    }

    /// 0...1. Grows quickly at first and then more slowly; never reaches 1 until Claude is done.
    public var progress: Double {
        if phase == .finished { return 1 }
        return 0.9 * (1 - exp(-workSeconds / 75))
    }

    /// Counts up every time the Gremlet does a bit of work (watering, a brush stroke, a block). The platform layer
    /// shows a little effect whenever it changes.
    public var beat: Int { beats }
}

extension World {

    /// Creatures currently on a Claude job.
    public var workers: [Creature] { creatures.filter { $0.job != nil } }

    /// Gives a Gremlet a job at a window. Prefers the given creature, then one that's free and closest to the window.
    /// Returns the worker's id, or nil if no Gremlet is out.
    @discardableResult
    public func startJob(windowID: Int?, craft: Craft, prefer id: Int? = nil) -> Int? {
        let target = windowID.flatMap { windows[$0] }
        let free = creatures.filter { $0.job == nil || $0.job?.phase == .finished }
        let pick = creature(id: id) ?? free.min { a, b in
            guard let t = target else { return a.id < b.id }
            return abs(a.pos.x - t.midX) + abs(a.pos.y - t.maxY) < abs(b.pos.x - t.midX) + abs(b.pos.y - t.maxY)
        } ?? creatures.first
        guard let c = pick else { return nil }
        if let j = c.job, j.phase != .finished, j.windowID == windowID { return c.id }   // already on it
        c.job = Job(craft: craft, windowID: windowID, seed: rng.next(), now: clock)
        endSocial(c)
        if c.isAsleep { emit(.wokeUp(c.id)) }
        if c.isGrounded { c.set(.react, duration: c.animationLength(for: .react)) }   // perks up, then off to work
        emit(.alert(c.id))
        return c.id
    }

    /// Claude finished: the creation completes and the Gremlet shows it off.
    public func finishJob(_ id: Int) {
        guard let c = creature(id: id), let j = c.job, j.phase != .finished else { return }
        if j.phase == .travel, c.isGrounded {
            // Didn't make it there in time: build it right where it stands.
            setSpotHere(c, j)
        }
        j.phase = .finished
        j.finishedAt = clock
        endSocial(c)
        if c.isGrounded { c.facing = j.propSide; startSpecial(c) }
    }

    /// Claude needs you: the Gremlet looks up from its work and waves.
    public func jobNeedsAttention(_ id: Int) {
        guard let c = creature(id: id), c.isGrounded else { return }
        endSocial(c)
        if let cur = cursor { c.facing = cur.x > c.pos.x ? 1 : -1 }
        c.set(.wave, duration: 2.2)
        emit(.alert(c.id))
    }

    /// Ends a job (session closed, or the platform's display time ran out). The Gremlet goes back to normal life.
    public func endJob(_ id: Int) {
        guard let c = creature(id: id), c.job != nil else { return }
        c.job = nil
        if c.activity == .climb { c.set(.airborne) }
        if c.activity == .work { c.set(.idle, duration: 0.5) }
    }

    /// Where the creation stands right now, in global points (feet of the prop), or nil if not placed yet.
    public func jobAnchor(_ j: Job) -> Vec2? {
        guard let s = j.spot else { return nil }
        if j.spotOnWindow {
            guard let id = j.windowID, let w = windows[id] else { return nil }
            return Vec2(w.minX + s.x, w.maxY)
        }
        return s
    }

    /// The ladder's foot and top, in global points, while one is up.
    public func jobLadder(_ j: Job) -> (x: Double, bottom: Double, top: Double)? {
        guard let lx = j.ladderX, let by = j.ladderBaseY, let id = j.windowID, let w = windows[id] else { return nil }
        return (w.minX + lx, by, w.maxY)
    }

    // MARK: Simulation (called from `update` while a creature has a job)

    /// Surface the Gremlet should work on: the widest visible stretch of the window's top edge, else the floor below
    /// the window (a maximised or covered window), else nil.
    func workSurface(_ j: Job) -> Surface? {
        guard let id = j.windowID, let w = windows[id] else { return nil }
        if let top = surfaces.filter({ $0.ownerID == id && $0.width >= 90 }).max(by: { $0.width < $1.width }) { return top }
        return surfaces.filter { $0.kind == .floor && $0.supports(x: w.midX.clamped($0.minX, $0.maxX)) && $0.y <= w.maxY }
            .max { $0.y < $1.y }
    }

    private func setSpotHere(_ c: Creature, _ j: Job) {
        let propX = c.pos.x + j.propSide * c.size.x * 0.55
        if let owner = c.groundOwner, owner >= 0, owner == j.windowID, let w = windows[owner] {
            j.spot = Vec2(propX - w.minX, 0); j.spotOnWindow = true
        } else {
            j.spot = Vec2(propX, c.pos.y); j.spotOnWindow = false
        }
    }

    /// Climbing a ladder: straight up, ignoring platforms until the top.
    func updateClimb(_ c: Creature, _ dt: Double) {
        guard let j = c.job, let lad = jobLadder(j) else { c.set(.airborne); return }
        c.pos.x = lad.x
        c.pos.y += 120 * dt
        if c.pos.y >= lad.top {
            c.pos.y = lad.top
            // Step off the ladder onto the window's top edge.
            if let t = workSurface(j), t.kind == .windowTop { c.pos.x = lad.x.clamped(t.minX + 14, t.maxX - 14) }
            c.groundOwner = j.windowID
            c.set(.land, duration: 0.14)
            emit(.landed(c.id, impact: 200))
        }
    }

    /// Returns true when the job handled this tick (otherwise the normal activity rules run).
    func updateJob(_ c: Creature, _ j: Job, _ dt: Double, on support: Surface) -> Bool {
        guard [.idle, .walk, .work].contains(c.activity) else { return false }
        switch j.phase {
        case .finished:
            // Hang around next to the creation, admiring it, until the platform ends the job.
            if c.activity != .idle || c.timer <= 0 {
                c.idleVariant = rng.chance(0.4) ? "look" : "idle"
                c.facing = rng.chance(0.7) ? j.propSide : -j.propSide
                c.set(.idle, duration: rng.range(1.5, 3.5))
            }
            return true
        case .working:
            // Carried or knocked away from the creation: head back to the window.
            if let a = jobAnchor(j) {
                let standX = a.x - j.propSide * c.size.x * 0.55
                if abs(standX - c.pos.x) > 40 || abs(a.y - c.pos.y) > 4 {
                    j.phase = .travel; j.started = clock; j.spot = nil
                    return travel(c, j, dt, on: support)
                }
            }
            j.workSeconds += dt
            c.facing = j.propSide
            j.poseTimer -= dt
            if c.activity != .work || j.poseTimer <= 0 {
                let r = rng.next() % 10
                c.workPose = r < 5 ? "crouch" : (r < 8 ? "idle" : "pet")
                if c.workPose == "idle" { c.idleVariant = "look" }
                j.poseTimer = rng.range(1.6, 3.0)
                c.set(.work, duration: 9999)
                if c.workPose == "crouch" { j.beats += 1 }
            }
            return true
        case .travel:
            return travel(c, j, dt, on: support)
        }
    }

    private func travel(_ c: Creature, _ j: Job, _ dt: Double, on support: Surface) -> Bool {
        // Taking too long (odd window layout): set up shop right here.
        if clock - j.started > 45 || j.windowID.flatMap({ windows[$0] }) == nil {
            beginWork(c, j); return true
        }
        guard let target = workSurface(j) else { beginWork(c, j); return true }

        // The stretch to work in: the window's top edge, or the part of the floor right below the window.
        var spanLo = target.minX, spanHi = target.maxX
        if target.kind == .floor, let w = j.windowID.flatMap({ windows[$0] }) {
            spanLo = max(spanLo, w.minX); spanHi = min(spanHi, w.maxX)
            if spanLo >= spanHi { spanLo = target.minX; spanHi = target.maxX }
        }
        if support.ownerID == target.ownerID {
            // On the right surface: walk to a spot near the right end (away from the window's buttons).
            let want = (spanHi - 80).clamped(spanLo + 40, max(spanLo + 40, spanHi - 40))
            if abs(want - c.pos.x) < 8 || !target.supports(x: want) { beginWork(c, j); return true }
            c.facing = want > c.pos.x ? 1 : -1
            if !move(c, dt, speed: c.species.walkSpeed * 1.3, on: support, ledgeTurnChance: 1) { beginWork(c, j) }
            else if c.activity != .walk { c.set(.walk, duration: 9999) }
            return true
        }

        let dh = target.y - support.y
        // Fliers just fly up.
        if c.species.flies && abs(dh) > 20 {
            let tx = (spanHi - 80).clamped(spanLo + 30, max(spanLo + 30, spanHi - 30))
            c.flyTarget = Vec2(tx, target.y)
            c.groundOwner = nil
            c.vel = Vec2(0, 200)
            c.facing = tx > c.pos.x ? 1 : -1
            c.set(.fly, duration: 8)
            emit(.tookOff(c.id))
            return true
        }
        // A short hop up: jump.
        let reachX = c.pos.x.clamped(target.minX + 30, target.maxX - 30)
        if dh > 25, dh < maxJumpHeight * c.species.jumpPower * 0.9, abs(reachX - c.pos.x) < maxJumpDistance * 0.8 {
            launch(c, velocity: ballistic(from: c.pos, toX: reachX, y: target.y))
            return true
        }
        // Higher up: put up a ladder where this surface and the target overlap, walk to it, climb.
        if dh > 0 {
            let lo = max(support.minX, target.minX) + 20, hi = min(support.maxX, target.maxX) - 20
            if let w = j.windowID.flatMap({ windows[$0] }), j.ladderX != nil && j.ladderBaseY == support.y || ladderSpot(c, w, target, support, lo, hi) != nil {
                if j.ladderX == nil || j.ladderBaseY != support.y, let lx = ladderSpot(c, w, target, support, lo, hi) {
                    j.ladderX = lx - w.minX; j.ladderBaseY = support.y
                }
                let ladderAbs = w.minX + (j.ladderX ?? 0)
                if abs(ladderAbs - c.pos.x) < 6 {
                    c.pos.x = ladderAbs
                    c.groundOwner = nil
                    c.set(.climb, duration: 9999)
                    return true
                }
                c.facing = ladderAbs > c.pos.x ? 1 : -1
                move(c, dt, speed: c.species.walkSpeed * 1.3, on: support, ledgeTurnChance: 1)
                if c.activity != .walk { c.set(.walk, duration: 9999) }
                return true
            }
        }
        // Wrong level with no overlap (or the target is below): walk off the nearer end and drop down.
        let goal = target.minX + target.width / 2
        let dir: Double = support.kind == .floor ? (goal > c.pos.x ? 1 : -1)
            : (c.pos.x - support.minX < support.maxX - c.pos.x ? -1 : 1)
        c.facing = dir
        move(c, dt, speed: c.species.walkSpeed * 1.3, on: support, ledgeTurnChance: 0)
        if c.activity != .walk { c.set(.walk, duration: 9999) }
        return true
    }

    /// Where to stand the ladder: leaning against the window's left or right side (so it never covers what's in the
    /// window), whichever is closer and has the top edge showing there; otherwise inside the overlap of the two surfaces.
    private func ladderSpot(_ c: Creature, _ w: Rect, _ target: Surface, _ support: Surface, _ lo: Double, _ hi: Double) -> Double? {
        let gap = 16.0
        var sides: [Double] = []
        if target.minX <= w.minX + 1 { sides.append(w.minX - gap) }
        if target.maxX >= w.maxX - 1 { sides.append(w.maxX + gap) }
        let (screenLo, screenHi) = horizontalLimits(for: c, atY: support.y + 1)
        let ok = sides.filter { support.supports(x: $0) && $0 > screenLo && $0 < screenHi }
        if let best = ok.min(by: { abs($0 - c.pos.x) < abs($1 - c.pos.x) }) { return best }
        return lo < hi ? c.pos.x.clamped(lo, hi) : nil
    }

    private func beginWork(_ c: Creature, _ j: Job) {
        // Face whichever side has room for the creation.
        if let s = supportingSurface(for: c) {
            j.propSide = (s.maxX - c.pos.x) >= (c.pos.x - s.minX) ? 1 : -1
            if min(s.maxX - c.pos.x, c.pos.x - s.minX) > 70 { j.propSide = rng.chance(0.5) ? 1 : -1 }
        }
        setSpotHere(c, j)
        j.phase = .working
        j.poseTimer = 0
        c.set(.work, duration: 9999)
    }
}

extension Rect {
    var midX: Double { x + w / 2 }
}
