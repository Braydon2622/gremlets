import Foundation  // exp(), sin()

/// Gremlets have hobbies. While you're at your Mac they now and then settle down to grow a flower, paint a picture,
/// build a block tower or knit a scarf, and doze beside it when you step away. The Claude buddy uses the same
/// machinery: while Claude Code works, a Gremlet floats up on a balloon to a little shelf it puts up on the side of
/// that Claude window and works there until Claude is done.
///
/// This file decides where the work happens and how the Gremlet gets there. The platform layer draws the shelf,
/// balloon and creation.
public enum Craft: String, CaseIterable, Sendable {
    case garden

    public var noun: String { "window box" }
}

/// What a Gremlet's shelf is made of. Some are alive or move: the leaf sways, the cloud bobs, the swing rocks.
public enum ShelfStyle: String, CaseIterable, Sendable {
    case plank, stone, leaf, cloud, mushroom, branch, swing

    /// Relative chance of each.
    var weight: Double {
        switch self { case .plank: return 1.6; case .branch, .leaf: return 1.3; default: return 1.0 }
    }

    /// Up-and-down motion (points) at time t.
    func bob(_ t: Double, _ seed: UInt64) -> Double {
        let phase = Double(seed % 1000) / 159
        switch self {
        case .cloud: return sin(t * 0.9 + phase) * 6
        case .leaf: return sin(t * 1.5 + phase) * 3
        case .swing: return sin(t * 1.2 + phase) * 2.5
        default: return 0
        }
    }
}

/// How a Gremlet gets up to (or down from) its shelf.
public enum Ride: String, CaseIterable, Sendable {
    /// Floating rides (the platform layer draws the prop over its head).
    case balloon, bubble, dandelion, umbrella, leaf
    /// A mushroom pops up from the ground and bounces it up onto the shelf.
    case bounce

    static let up: [Ride] = [.balloon, .bubble, .dandelion, .bounce]
    static let down: [Ride] = [.balloon, .umbrella, .leaf, .dandelion]
}

public final class Job {
    public enum Phase: Equatable, Sendable { case travel, working, finished, leaving }
    public enum Kind: Equatable, Sendable {
        /// Lasts as long as Claude works; the platform layer finishes and ends it.
        case claude
        /// A hobby: finishes on its own once everything in the window box has bloomed.
        case hobby
    }

    public let craft: Craft
    public let kind: Kind
    /// The window the shelf hangs on (nil = working on the floor).
    public internal(set) var windowID: Int?
    /// Which side of the window the shelf sticks out of (+1 right, -1 left); nil = no shelf.
    public internal(set) var shelfSide: Double?
    public internal(set) var shelfStyle: ShelfStyle = .plank
    /// A shelf on the wall (the side edge of a screen) rather than on a window: screen index and height.
    public internal(set) var wall: (screen: Int, y: Double)?
    var rideUp: Ride = .balloon
    /// The bouncy mushroom (where and when), for the platform layer to draw.
    public internal(set) var bounceAt: Double?
    public internal(set) var bounceSpot: Vec2?
    var bounceTries = 0
    public internal(set) var phase: Phase = .travel
    /// Seconds of work done (drives how far along the creation is).
    public internal(set) var workSeconds: Double = 0
    public internal(set) var finishedAt: Double?
    /// Which side of the Gremlet the creation sits on (+1 right, -1 left).
    public internal(set) var propSide: Double = 1
    /// Floor spot (absolute) when there's no shelf.
    var spot: Vec2?
    /// A per-job number the platform layer uses to vary the art (which picture gets painted...).
    public let seed: UInt64
    var started: Double
    var poseTimer = 0.0
    var beats = 0
    /// You poked it while it worked: a little burst of progress.
    /// The window box: three plants.
    public let garden = GardenBox()

    init(craft: Craft, kind: Kind, windowID: Int?, seed: UInt64, now: Double) {
        self.craft = craft; self.kind = kind; self.windowID = windowID; self.seed = seed; self.started = now
    }

    public var isHobby: Bool { if case .hobby = kind { return true }; return false }

    /// 0...1. Claude jobs grow quickly and then more slowly and never reach 1 until Claude is done; hobbies grow
    /// steadily until they're finished.
    public var progress: Double {
        if phase == .finished || phase == .leaving { return 1 }
        switch kind {
        case .claude, .hobby: return garden.progress
        }
    }

    /// Counts up each time the Gremlet does a bit of work (watering, a brush stroke, a block, a row of stitches).
    public var beat: Int { beats }
}

extension World {
    /// Surface owner ids at or below this belong to the shelves Gremlets put up.
    static let shelfOwnerBase = -500_000
    static func shelfOwner(_ creatureID: Int) -> Int { shelfOwnerBase - creatureID }

    public static let shelfWidth: Double = 176
    /// How far below the window's top edge the shelf hangs.
    static let shelfDrop: Double = 36

    /// Whether this Gremlet could take up a hobby now: you're at the Mac, it's rested, and not too many are busy.
    func canStartHobby(_ c: Creature) -> Bool {
        userActive && c.job == nil && c.energy > 0.3 && c.isGrounded && clock >= c.hobbyRestUntil
            && creatures.filter({ $0.job?.isHobby == true }).count < maxHobbies
    }

    /// Creatures with a job (hobby or Claude).
    public var workers: [Creature] { creatures.filter { $0.job != nil } }

    // MARK: Starting and stopping

    /// Claude buddy: gives a Gremlet a job at a Claude window. Prefers the given creature, then a free one closest to
    /// the window (one on a hobby is happy to drop it). Returns the worker's id, or nil if no Gremlet is out.
    @discardableResult
    public func startJob(windowID: Int?, craft: Craft, prefer id: Int? = nil) -> Int? {
        let target = windowID.flatMap { windows[$0] }
        let free = creatures.filter { $0.job == nil || $0.job!.isHobby || $0.job!.phase == .finished }
        let pick = creature(id: id) ?? free.min { a, b in
            guard let t = target else { return a.id < b.id }
            return abs(a.pos.x - t.midX) + abs(a.pos.y - t.maxY) < abs(b.pos.x - t.midX) + abs(b.pos.y - t.maxY)
        } ?? creatures.first
        guard let c = pick else { return nil }
        if let j = c.job, j.kind == .claude, j.phase == .travel || j.phase == .working, j.windowID == windowID { return c.id }
        assign(c, Job(craft: craft, kind: .claude, windowID: windowID, seed: rng.next(), now: clock))
        if c.isGrounded { c.set(.react, duration: c.animationLength(for: .react)) }   // perks up, then off to work
        emit(.alert(c.id))
        return c.id
    }

    /// Starts a hobby: right here on the floor, or now and then on a shelf on a nearby window.
    @discardableResult
    public func startHobby(_ c: Creature, craft: Craft? = nil, onWindow: Bool? = nil) -> Bool {
        guard c.job == nil, c.isGrounded, let support = supportingSurface(for: c) else { return false }
        let craft = craft ?? Craft.allCases[Int(rng.next() % UInt64(Craft.allCases.count))]
        var windowID: Int?
        let wantsShelf = onWindow ?? (support.kind == .windowTop || rng.chance(0.75))
        if wantsShelf {
            if support.kind == .windowTop, shelfSideFor(window: support.ownerID, near: c.pos.x, for: c.id) != nil {
                windowID = support.ownerID
            } else {
                windowID = windows.keys.filter { id in
                    guard let w = windows[id], abs(w.midX - c.pos.x) < 700 else { return false }
                    return shelfSideFor(window: id, near: c.pos.x, for: c.id) != nil
                }.min { abs(windows[$0]!.midX - c.pos.x) < abs(windows[$1]!.midX - c.pos.x) }
            }
        }
        // No window with room for a shelf? Put one up on the wall: the side edge of the screen, at a cozy height.
        var wall: (Int, Double, Double)?
        if wantsShelf && windowID == nil, let si = screens.firstIndex(where: { c.pos.x >= $0.minX && c.pos.x < $0.maxX }) ?? screens.indices.first {
            let scr = screens[si]
            let taken = creatures.compactMap { $0.job?.wall }.filter { $0.screen == si }.map(\.y)
            let side: Double = c.pos.x - scr.minX < scr.maxX - c.pos.x ? 1 : -1
            for _ in 0..<6 {
                let y = scr.minY + scr.h * rng.range(0.32, 0.72)
                if !taken.contains(where: { abs($0 - y) < 160 }) { wall = (si, side, y); break }
            }
        }
        guard windowID != nil || wall != nil || support.kind == .floor else { return false }
        let job = Job(craft: craft, kind: .hobby, windowID: windowID, seed: rng.next(), now: clock)
        assign(c, job)
        if let (si, side, y) = wall {
            job.wall = (si, y)
            job.shelfSide = side
        }
        c.set(.idle, duration: 0.3)
        return true
    }

    /// The `gremlet hobby` command: the free Gremlet nearest the cursor starts a hobby now.
    @discardableResult
    public func startHobbyNearCursor(craft: Craft? = nil, onWindow: Bool? = nil) -> Bool {
        let free = creatures.filter { $0.job == nil && $0.isGrounded }
        guard let c = nearestToCursor(free) else { return false }
        return startHobby(c, craft: craft, onWindow: onWindow) || startHobby(c, craft: craft, onWindow: !(onWindow ?? true))
    }

    private func assign(_ c: Creature, _ j: Job) {
        endSocial(c)
        c.visitingID = nil
        c.tendX = nil
        if c.isAsleep { emit(.wokeUp(c.id)) }
        c.job = j
        if let id = j.windowID { j.shelfSide = shelfSideFor(window: id, near: c.pos.x, for: c.id) }
        // Every shelf is a little different, and so is the way up.
        let total = ShelfStyle.allCases.reduce(0) { $0 + $1.weight }
        var roll = rng.range(0, total)
        j.shelfStyle = ShelfStyle.allCases.first { roll -= $0.weight; return roll <= 0 } ?? .plank
        j.rideUp = Ride.up[Int(rng.next() % UInt64(Ride.up.count))]
    }

    /// Finishes the creation now (Claude is done); the Gremlet shows it off.
    public func finishJob(_ id: Int) {
        guard let c = creature(id: id), let j = c.job, j.phase == .travel || j.phase == .working else { return }
        if j.phase == .travel {
            // Didn't make it there in time: it finishes up right where it is.
            if c.isGrounded { beginWork(c, j) }
        }
        // Everything in the box bursts into bloom (Claude jobs finish this way; hobbies already have).
        let g = j.garden
        if g.giant == nil {
            for i in g.plants.indices where g.plants[i] == nil {
                var seed = pickSeed(boost: true)
                if seed.kind.isGiant { seed = Plant(kind: .sunflower, golden: seed.golden) }
                g.plants[i] = seed
            }
        }
        for i in g.activeSlots {
            if (g.plants[i]?.growth ?? 0) < 1, var p = g.plants[i] {
                p.growth = 1
                g.plants[i] = p
                g.bloomed.append(p)
            }
            g.plants[i]?.bug = false
        }
        j.garden.lastAction = .harvest
        j.beats += 1
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

    /// Ends a job. A Gremlet up on its shelf floats back down on its balloon first; the shelf comes down after it.
    public func endJob(_ id: Int) {
        guard let c = creature(id: id), let j = c.job else { return }
        if c.groundOwner == World.shelfOwner(c.id), let floor = floorBelow(c.pos.x) {
            j.phase = .leaving
            if j.finishedAt == nil { j.finishedAt = clock }
            startFloat(c, to: Vec2(c.pos.x + (j.shelfSide ?? 1) * 40, floor.y), ride: Ride.down[Int(rng.next() % UInt64(Ride.down.count))])
            return
        }
        if j.isHobby { c.hobbyRestUntil = clock + rng.range(150, 420) }
        c.job = nil
        if c.activity == .float { c.floatTarget = nil; c.set(.airborne) }
        if c.activity == .work { c.set(.idle, duration: 0.5) }
    }

    /// You clicked a Gremlet's creation (watering the plant, adding a brush stroke...): it does a happy wiggle and
    /// the work jumps ahead a little.
    public func tendCreation(workerID: Int) {
        guard let c = creature(id: workerID), let j = c.job, j.phase == .working else { return }
        encourage(c)
        if c.isGrounded && !c.isDozingAtWork {
            c.set(.pet, duration: 1.2)
            emit(.petted(c.id))
        }
    }

    /// You clicked a busy Gremlet: it shows you what it's making and gets a burst of motivation.
    func encourage(_ c: Creature) {
        guard let j = c.job, j.phase == .working else { return }
        // A pat on the head: it gets a little burst of energy for whatever is growing.
        if let i = j.garden.activeSlots.first(where: { (j.garden.plants[$0]?.growth ?? 1) < 1 }) {
            j.garden.plants[i]?.growth += 0.03
            j.garden.lastAction = .weed(i)
        }
        j.beats += 1
    }

    // MARK: Geometry (public so the platform layer can draw it)

    /// The shelf for this job, if any: a plank sticking out of the window's side just below its top edge.
    public func jobShelf(_ j: Job, workerID: Int) -> Surface? {
        if let wall = j.wall, let side = j.shelfSide, wall.screen < screens.count {
            // On the wall: the shelf sticks out from the screen's edge into the screen.
            let scr = screens[wall.screen]
            let edge = side > 0 ? scr.minX : scr.maxX
            let y = wall.y + j.shelfStyle.bob(clock, j.seed)
            let lo = side > 0 ? edge : edge - World.shelfWidth
            let hi = side > 0 ? edge + World.shelfWidth : edge
            return Surface(ownerID: World.shelfOwner(workerID), kind: .shelf, y: y, minX: lo, maxX: hi)
        }
        guard var side = j.shelfSide, let id = j.windowID, let w = windows[id],
              let scr = screens.first(where: { w.midX >= $0.minX && w.midX < $0.maxX }) ?? screens.first
        else { return nil }
        // The window moved and the shelf no longer fits on this side: move it to the other side, or take it down.
        let fits = side > 0 ? w.maxX + World.shelfWidth <= scr.maxX : w.minX - World.shelfWidth >= scr.minX
        if !fits {
            guard let other = shelfSideFor(window: id, near: side > 0 ? w.minX : w.maxX, for: workerID) else { j.shelfSide = nil; return nil }
            side = other; j.shelfSide = other
        }
        let y = min(w.maxY - World.shelfDrop, scr.maxY - 130).clamped(scr.minY + 40, scr.maxY - 60) + j.shelfStyle.bob(clock, j.seed)
        let edge = side > 0 ? w.maxX : w.minX
        let lo = side > 0 ? edge - 6 : edge - World.shelfWidth
        let hi = side > 0 ? edge + World.shelfWidth : edge + 6
        return Surface(ownerID: World.shelfOwner(workerID), kind: .shelf, y: y, minX: lo, maxX: hi)
    }

    /// Where the creation stands (feet of the prop), in global points, once the Gremlet has started.
    public func jobAnchor(_ j: Job, workerID: Int) -> Vec2? {
        if j.shelfSide != nil, let s = jobShelf(j, workerID: workerID), let side = j.shelfSide {
            guard j.phase != .travel else { return nil }
            let edge = side > 0 ? s.minX + 6 : s.maxX - 6
            return Vec2(edge + side * 60, s.y)
        }
        return j.spot
    }

    /// Where the Gremlet stands while working on a shelf: out past the creation, facing the window.
    func standPoint(_ j: Job, workerID: Int) -> Vec2? {
        guard let side = j.shelfSide, let s = jobShelf(j, workerID: workerID) else { return nil }
        let edge = side > 0 ? s.minX + 6 : s.maxX - 6
        return Vec2(edge + side * 146, s.y)
    }

    /// Which side of a window has room for a shelf (closest to `x` first), or nil if neither does.
    func shelfSideFor(window id: Int, near x: Double, for workerID: Int) -> Double? {
        guard let w = windows[id], let scr = screens.first(where: { w.midX >= $0.minX && w.midX < $0.maxX }) ?? screens.first
        else { return nil }
        guard w.maxY - World.shelfDrop > scr.minY + 60 else { return nil }
        let need = World.shelfWidth + 12
        let y = w.maxY - World.shelfDrop
        // Only on a side you can actually see: that end of the window's top edge isn't covered, and no window in
        // front of this one sits where the shelf would go.
        let tops = surfaces.filter { $0.ownerID == id }
        let front = windowOrder.prefix { $0 != id }.compactMap { windows[$0] }
        func clear(_ side: Double) -> Bool {
            let lo = side > 0 ? w.maxX : w.minX - World.shelfWidth, hi = side > 0 ? w.maxX + World.shelfWidth : w.minX
            let cornerShowing = tops.contains { side > 0 ? $0.maxX >= w.maxX - 1 : $0.minX <= w.minX + 1 }
            let blocked = front.contains { $0.minX < hi && $0.maxX > lo && $0.minY < y + 110 && $0.maxY > y - 30 }
            let taken = creatures.contains { $0.id != workerID && $0.job?.windowID == id && $0.job?.shelfSide == side }
            return cornerShowing && !blocked && !taken
        }
        var sides: [Double] = []
        if scr.maxX - w.maxX >= need && clear(1) { sides.append(1) }
        if w.minX - scr.minX >= need && clear(-1) { sides.append(-1) }
        return sides.min { abs((($0 > 0) ? w.maxX : w.minX) - x) < abs((($1 > 0) ? w.maxX : w.minX) - x) }
    }

    /// Shelves currently up (they're surfaces anyone can stand on).
    var shelfSurfaces: [Surface] {
        creatures.compactMap { c in c.job.flatMap { jobShelf($0, workerID: c.id) } }
    }

    /// The window a surface owner moves with (a window's own top edge, or a shelf hanging on it).
    func windowFor(owner: Int?) -> Int? {
        guard let o = owner else { return nil }
        if o >= 0 { return o }
        if o <= World.shelfOwnerBase, let c = creature(id: World.shelfOwnerBase - o) { return c.job?.windowID }
        return nil
    }

    func floorBelow(_ x: Double) -> Surface? {
        surfaces.filter { $0.kind == .floor && $0.supports(x: x) }.min { $0.y < $1.y }
            ?? surfaces.filter { $0.kind == .floor }.min { abs($0.minX + $0.width / 2 - x) < abs($1.minX + $1.width / 2 - x) }
    }

    // MARK: Tending the garden

    /// Where the keepsake garden's flowers are (global x on the main screen's floor). Set by the platform layer.
    public var gardenSpots: [Double] {
        get { _gardenSpots }
        set { _gardenSpots = newValue }
    }

    /// A planted flower on this Gremlet's floor that it could go and water.
    func flowerToTend(for c: Creature) -> Double? {
        guard c.job == nil, c.isGrounded, let s = supportingSurface(for: c), s.kind == .floor else { return nil }
        let near = gardenSpots.filter { s.supports(x: $0) && abs($0 - c.pos.x) < 700 }
        guard !near.isEmpty else { return nil }
        return near[Int(rng.next() % UInt64(near.count))]
    }

    func startTending(_ c: Creature, x: Double) {
        endSocial(c)
        c.tendX = x
        c.visitUntil = clock + 25
        c.set(.walk, duration: 9999)
    }

    /// Walks over to a planted flower, waters it (a little rain from above), admires it, and wanders off.
    func updateTending(_ c: Creature, _ dt: Double, on support: Surface) -> Bool {
        guard [.idle, .walk, .work].contains(c.activity), let x = c.tendX else { return false }
        let stand = x - 34 * (x >= c.pos.x ? 1 : -1)
        if clock > c.visitUntil || support.kind != .floor { c.tendX = nil; c.set(.idle, duration: 0.5); return true }
        if c.activity == .walk {
            if abs(stand - c.pos.x) > 6 {
                c.facing = stand > c.pos.x ? 1 : -1
                if !move(c, dt, speed: c.species.walkSpeed, on: support, ledgeTurnChance: 1) { c.tendX = nil; c.set(.idle, duration: 1) }
                return true
            }
            c.facing = x > c.pos.x ? 1 : -1
            c.workPose = "crouch"
            c.set(.work, duration: 2.4)
            emit(.special(c.id, effect: "rain"))
            return true
        }
        if c.timer <= 0 {
            if c.activity == .work {
                c.idleVariant = "look"
                c.set(.idle, duration: 2.0)
            } else {
                c.tendX = nil
                c.set(.idle, duration: 0.3)
            }
        }
        return true
    }

    // MARK: Friends come to watch

    /// A busy friend on the same floor or window edge, within walking distance.
    func workerToVisit(from c: Creature) -> Creature? {
        guard c.job == nil, c.isGrounded else { return nil }
        return creatures.first { o in
            guard o !== c, let j = o.job, j.phase == .working, o.groundOwner == c.groundOwner,
                  abs(o.pos.x - c.pos.x) < 600 else { return false }
            return !creatures.contains { $0.visitingID == o.id }
        }
    }

    func startVisit(_ c: Creature, _ friend: Creature) {
        endSocial(c)
        c.visitingID = friend.id
        c.visitUntil = clock + rng.range(14, 26)
        c.set(.walk, duration: 9999)
    }

    /// Walks over to stand on the far side of the friend's creation, watches, and claps now and then.
    func updateVisit(_ c: Creature, _ dt: Double, on support: Surface) -> Bool {
        guard [.idle, .walk, .pet].contains(c.activity) else { return false }
        guard let f = creature(id: c.visitingID), let j = f.job, j.phase == .working || j.phase == .finished,
              f.groundOwner == c.groundOwner, clock < c.visitUntil, let a = jobAnchor(j, workerID: f.id) else {
            c.visitingID = nil
            c.set(.idle, duration: 0.5)
            return true
        }
        let want = (a.x + j.propSide * 82).clamped(support.minX + 20, support.maxX - 20)
        if abs(want - c.pos.x) > 8 && c.activity != .pet {
            c.facing = want > c.pos.x ? 1 : -1
            if !move(c, dt, speed: c.species.walkSpeed, on: support, ledgeTurnChance: 1) { c.visitingID = nil; c.set(.idle, duration: 1) }
            else if c.activity != .walk { c.set(.walk, duration: 9999) }
            return true
        }
        c.facing = a.x > c.pos.x ? 1 : -1
        if c.activity == .walk || c.timer <= 0 {
            if rng.chance(0.3) {
                c.set(.pet, duration: 1.2)        // happy wiggle: a little clap
                emit(.greet(c.id, f.id))
            } else {
                c.idleVariant = rng.chance(0.5) ? "look" : "idle"
                c.set(.idle, duration: rng.range(1.5, 3))
            }
        }
        return true
    }

    // MARK: Simulation

    /// Balloon ride: rises a little, drifts over, then settles down onto the target. Ignores platforms on the way.
    func startFloat(_ c: Creature, to target: Vec2, ride: Ride = .balloon) {
        endSocial(c)
        c.ride = ride
        c.floatTarget = target
        c.groundOwner = nil
        c.vel = Vec2(0, 60)
        c.facing = target.x > c.pos.x ? 1 : -1
        c.set(.float, duration: 30)
        emit(.tookOff(c.id))
    }

    func updateFloat(_ c: Creature, _ dt: Double) {
        // Follow the shelf if its window moved during the ride.
        if let j = c.job, j.phase == .travel, let sp = standPoint(j, workerID: c.id) { c.floatTarget = sp }
        guard var target = c.floatTarget else { c.set(.airborne); return }
        c.timer -= dt
        let above = target + Vec2(0, 30)
        // Rise (or hold height) while drifting across, then settle straight down.
        let aim = abs(c.pos.x - target.x) > 8 ? Vec2(target.x, max(c.pos.y, above.y)) : target
        let to = aim - c.pos
        let dist = to.length
        let speed = (aim == target ? 55 : 120.0)
        var v = dist > 0.5 ? to * (min(speed, dist * 3 + 10) / dist) : .zero
        v.y += sin(clock * 3.2 + Double(c.id)) * 14 * min(1, (c.pos - target).length / 80)   // gentle bob, calm on landing
        c.vel = c.vel + (v - c.vel) * min(1, 4 * dt)
        c.pos = c.pos + c.vel * dt
        let (lo, hi) = horizontalLimits(for: c, atY: c.pos.y)
        c.pos.x = c.pos.x.clamped(lo, hi)
        if let scr = screen(containingX: c.pos.x, y: c.pos.y), c.pos.y + c.size.y > scr.maxY { c.pos.y = scr.maxY - c.size.y }
        if abs(c.vel.x) > 10 { c.facing = c.vel.x > 0 ? 1 : -1 }
        target = c.floatTarget ?? target
        if (abs(c.pos.x - target.x) < 6 && c.pos.y <= target.y + 6) || c.timer <= 0 {
            c.pos = target
            c.vel = .zero
            c.floatTarget = nil
            let landing = allSurfaces(excluding: c).filter { abs($0.y - target.y) <= 2 && $0.supports(x: target.x) }
            if let s = landing.first(where: { $0.ownerID == World.shelfOwner(c.id) }) ?? landing.max(by: { $0.y < $1.y }) {
                c.groundOwner = s.ownerID
                c.set(.land, duration: 0.14)
                emit(.landed(c.id, impact: 120))
            } else {
                c.set(.airborne)
            }
            if let j = c.job, j.phase == .leaving {
                if j.isHobby { c.hobbyRestUntil = clock + rng.range(150, 420) }
                c.job = nil
            }
        }
    }

    /// Returns true when the job handled this tick (otherwise the normal activity rules run).
    func updateJob(_ c: Creature, _ j: Job, _ dt: Double, on support: Surface) -> Bool {
        guard [.idle, .walk, .work].contains(c.activity) else { return false }
        switch j.phase {
        case .leaving:
            endJob(c.id); return true
        case .finished:
            // Admire the creation for a while. Hobbies end themselves; Claude jobs are ended by the platform.
            if case .hobby = j.kind, let f = j.finishedAt, clock - f > 25 { endJob(c.id); return true }
            if c.activity != .idle || c.timer <= 0 {
                c.idleVariant = rng.chance(0.4) ? "look" : "idle"
                c.facing = rng.chance(0.7) ? j.propSide : -j.propSide
                c.set(.idle, duration: rng.range(1.5, 3.5))
            }
            return true
        case .working:
            if strayed(c, j) {
                j.phase = .travel; j.started = clock; j.spot = nil
                return travel(c, j, dt, on: support)
            }
            let resting = j.isHobby && !userActive
            if !resting { j.workSeconds += dt }
            growGarden(j, dt, tending: !resting)
            if j.isHobby && j.garden.allBloomed {
                finishJob(c.id); return true
            }
            c.facing = j.propSide
            j.poseTimer -= dt
            if c.activity != .work || j.poseTimer <= 0 || (resting != (c.workPose == "sleep")) {
                if resting {
                    c.workPose = "sleep"
                    j.poseTimer = 5
                } else {
                    // Every couple of seconds: a chore (planting, watering, shooing a bug, weeding), or a moment
                    // to admire the plants.
                    if doGardenChore(j) {
                        c.workPose = "crouch"
                    } else {
                        c.workPose = rng.chance(0.6) ? "look" : "pet"
                    }
                    j.poseTimer = rng.range(1.8, 3.2)
                }
                c.set(.work, duration: 9999)
            }
            return true
        case .travel:
            return travel(c, j, dt, on: support)
        }
    }

    /// Knocked, dragged or dropped away from its spot.
    private func strayed(_ c: Creature, _ j: Job) -> Bool {
        if j.shelfSide != nil {
            guard let sp = standPoint(j, workerID: c.id) else { return true }
            return c.groundOwner != World.shelfOwner(c.id) || abs(sp.x - c.pos.x) > 30
        }
        guard let a = j.spot else { return true }
        return abs(a.x - j.propSide * c.size.x * 0.85 - c.pos.x) > 40 || abs(a.y - c.pos.y) > 4
    }

    private func travel(_ c: Creature, _ j: Job, _ dt: Double, on support: Surface) -> Bool {
        // The window went away (closed, minimised) or this is taking too long: set up shop right here.
        if j.windowID != nil && j.windowID.flatMap({ windows[$0] }) == nil { j.windowID = nil; j.shelfSide = nil }
        if clock - j.started > 60 { j.shelfSide = nil }

        if j.shelfSide != nil, let sp = standPoint(j, workerID: c.id) {
            if support.ownerID == World.shelfOwner(c.id) {
                if abs(sp.x - c.pos.x) < 6 { beginWork(c, j); return true }
                c.facing = sp.x > c.pos.x ? 1 : -1
                move(c, dt, speed: c.species.walkSpeed, on: support, ledgeTurnChance: 1)
                if c.activity != .walk { c.set(.walk, duration: 9999) }
                return true
            }
            if !c.species.flies && j.rideUp == .bounce && j.bounceTries < 2 && support.kind != .shelf {
                // Bouncy mushroom: walk under the shelf, then boing.
                let launchX = sp.x.clamped(support.minX + 30, support.maxX - 30)
                if abs(launchX - c.pos.x) > 8 {
                    c.facing = launchX > c.pos.x ? 1 : -1
                    if !move(c, dt, speed: c.species.walkSpeed * 1.3, on: support, ledgeTurnChance: 1) { j.rideUp = .balloon }
                    else if c.activity != .walk { c.set(.walk, duration: 9999) }
                    return true
                }
                j.bounceTries += 1
                j.bounceAt = clock
                j.bounceSpot = Vec2(c.pos.x, support.y)
                c.groundOwner = nil
                c.vel = ballistic(from: c.pos, toX: sp.x, y: sp.y, apexExtra: 45)
                c.facing = sp.x >= c.pos.x ? 1 : -1
                c.set(.airborne)
                c.pos.y += 1
                emit(.tookOff(c.id))
                return true
            }
            if c.species.flies {
                c.flyTarget = sp
                c.groundOwner = nil
                c.vel = Vec2(0, 200)
                c.facing = sp.x > c.pos.x ? 1 : -1
                c.set(.fly, duration: 10)
                emit(.tookOff(c.id))
            } else {
                startFloat(c, to: sp, ride: j.rideUp == .bounce ? .balloon : j.rideUp)
            }
            return true
        }

        // No shelf: work on the floor (under the Claude window if there is one).
        if support.kind != .floor, let floor = floorBelow(c.pos.x) {
            startFloat(c, to: Vec2(c.pos.x, floor.y))
            return true
        }
        var want = c.pos.x.clamped(support.minX + 100, max(support.minX + 100, support.maxX - 100))
        if let id = j.windowID, let w = windows[id] {
            want = (w.maxX - 80).clamped(max(support.minX + 100, w.minX + 30), min(support.maxX - 100, max(w.minX + 31, w.maxX - 30)))
        }
        // Give other Gremlets' projects some elbow room.
        for o in creatures where o !== c {
            guard let oj = o.job, let a = jobAnchor(oj, workerID: o.id), abs(a.y - support.y) < 2, abs(a.x - want) < 130 else { continue }
            let pushed = a.x + (want >= a.x ? 130 : -130)
            if pushed > support.minX + 100 && pushed < support.maxX - 100 { want = pushed }
        }
        if j.spot == nil && abs(want - c.pos.x) >= 8 && clock - j.started > 20 { want = c.pos.x }  // don't wander forever
        // Peeking around a screen edge can leave a Gremlet past where it may walk: step back in first.
        let (lo, hi) = horizontalLimits(for: c, atY: c.pos.y + 1)
        c.pos.x = c.pos.x.clamped(lo, hi)
        if abs(want - c.pos.x) < 8 { beginWork(c, j); return true }
        c.facing = want > c.pos.x ? 1 : -1
        if !move(c, dt, speed: c.species.walkSpeed * 1.3, on: support, ledgeTurnChance: 1) { beginWork(c, j) }
        else if c.activity != .walk { c.set(.walk, duration: 9999) }
        return true
    }

    private func beginWork(_ c: Creature, _ j: Job) {
        if let side = j.shelfSide, c.groundOwner == World.shelfOwner(c.id) {
            j.propSide = -side                       // face back toward the window, creation in between
        } else {
            j.shelfSide = nil
            if let s = supportingSurface(for: c) {
                j.propSide = (s.maxX - c.pos.x) >= (c.pos.x - s.minX) ? 1 : -1
                if min(s.maxX - c.pos.x, c.pos.x - s.minX) > 80 { j.propSide = rng.chance(0.5) ? 1 : -1 }
            }
            j.spot = Vec2(c.pos.x + j.propSide * c.size.x * 0.85, c.pos.y)
        }
        j.phase = .working
        j.poseTimer = 0
        c.set(.work, duration: 9999)
    }
}

extension Rect {
    var midX: Double { x + w / 2 }
}
