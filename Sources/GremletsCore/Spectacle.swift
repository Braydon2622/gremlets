import Foundation

/// Little moments that pass over the grove and the village, quietly and never during a focus session:
///
/// - **Meteor shower** (at night): shooting stars streak across the sky and drop star shards that Gremlets race
///   to collect. Every shard is a spark for the grove.
/// - **Bloom festival** (when a grove plant reaches level 5): petals drift down and everyone dances.
/// - **Lantern festival** (on evenings after a good day's work): paper lanterns rise from the village, one for each
///   Claude task you finished that day.
public enum SpectacleKind: String, CaseIterable, Sendable {
    case meteors, festival, lanterns

    public var title: String {
        switch self {
        case .meteors: return "Meteor shower"
        case .festival: return "Bloom festival"
        case .lanterns: return "Lantern festival"
        }
    }
}

public enum SpectaclePhase: Sendable { case intro, main, outro }

public struct Shard: Sendable {
    public var id: Int
    public var pos: Vec2
    public var vel: Vec2
    public var landed = false
    public var landedAt = 0.0
}

public enum SpectacleEvent: Equatable, Sendable {
    case started(SpectacleKind)
    case shardCollected(Vec2, by: Int)
    case meteor(from: Vec2, to: Vec2)
    case ended(SpectacleKind)
}

public final class Spectacle {
    public let kind: SpectacleKind
    public internal(set) var phase: SpectaclePhase = .intro
    public internal(set) var age = 0.0
    public let duration: Double
    public internal(set) var shards: [Shard] = []
    var nextShard = 0.6
    var shardIDs = 0
    var phaseT = 0.0
    var events: [SpectacleEvent] = []

    init(kind: SpectacleKind) {
        self.kind = kind
        switch kind {
        case .meteors: duration = 26
        case .festival: duration = 22
        case .lanterns: duration = 40
        }
    }
}

extension World {

    /// Queues an event (it starts when nothing else is running and the time is right).
    public func requestEvent(_ k: SpectacleKind) {
        if !pendingEvents.contains(k) { pendingEvents.append(k) }
    }

    /// Starts an event right away (the menu items). Returns false if one is already running.
    @discardableResult
    public func startEvent(_ k: SpectacleKind) -> Bool {
        guard spectacle == nil, groveFloor != nil else { return false }
        let s = Spectacle(kind: k)
        spectacle = s
        s.events.append(.started(k))
        for c in creatures where c.isAsleep && c.homeUntil == nil { c.set(.wake, duration: c.animationLength(for: .wake)) }
        if k == .festival { for c in creatures where c.job == nil && c.isGrounded { startDance(c, duration: rng.range(5, 9), invite: false) } }
        return true
    }

    public func drainSpectacleEvents() -> [SpectacleEvent] {
        guard let s = spectacle ?? lastSpectacle else { return [] }
        defer { s.events.removeAll(); if spectacle == nil { lastSpectacle = nil } }
        return s.events
    }

    func finishSpectacle(_ s: Spectacle) {
        guard s.phase != .outro else { return }
        s.phase = .outro
        s.phaseT = 0
        s.events.append(.ended(s.kind))
    }

    // MARK: Step

    func updateSpectacle(_ dt: Double) {
        if spectacle == nil, eventsAllowed, !calm, let next = pendingEvents.first {
            // Meteor showers wait for dark; everything else starts right away.
            if next != .meteors || isNight {
                pendingEvents.removeFirst()
                startEvent(next)
            }
        }
        guard let s = spectacle, let f = groveFloor else { return }
        if calm || !eventsAllowed { finishSpectacle(s) }
        s.age += dt
        s.phaseT += dt
        switch s.phase {
        case .intro: if s.phaseT > 0.5 { s.phase = .main; s.phaseT = 0 }
        case .main: if s.age > s.duration { finishSpectacle(s) }
        case .outro: break
        }
        switch s.kind {
        case .meteors: updateMeteors(s, dt, f)
        case .festival: updateFestival(s, dt)
        case .lanterns: updateLanterns(s, dt)
        }
        updateShards(s, dt, f)
        if s.phase == .outro && (s.phaseT > 6 && s.shards.isEmpty || s.phaseT > 18) {
            lastSpectacle = s
            spectacle = nil
        }
    }

    // MARK: Meteors

    private func updateMeteors(_ s: Spectacle, _ dt: Double, _ f: Rect) {
        guard s.phase == .main else { return }
        s.nextShard -= dt
        if s.nextShard <= 0 {
            s.nextShard = rng.range(0.25, 0.7)
            let from = Vec2(rng.range(f.minX, f.maxX + f.w * 0.3), f.maxY + 40)
            let to = from + Vec2(-rng.range(400, 900), -rng.range(500, 900))
            s.events.append(.meteor(from: from, to: to))
            // About one in three leaves a star shard behind.
            if rng.chance(0.38) && s.shards.count < 14 {
                s.shardIDs += 1
                let x = rng.range(f.minX + 40, f.maxX - 40)
                s.shards.append(Shard(id: s.shardIDs, pos: Vec2(x, f.maxY - 20), vel: Vec2(rng.range(-80, 80), -300)))
            }
        }
    }

    // MARK: Festivals

    private func updateFestival(_ s: Spectacle, _ dt: Double) {
        guard s.phase == .main else { return }
        for c in creatures where c.job == nil && c.isGrounded && c.activity == .idle && rng.chance(dt * 0.5) {
            startDance(c, duration: rng.range(3, 6), invite: true)
        }
    }

    private func updateLanterns(_ s: Spectacle, _ dt: Double) {
        guard s.phase == .main else { return }
        // Everyone on the floor stops to watch the lanterns go up.
        for c in creatures where c.job == nil && c.isGrounded && c.activity == .idle && rng.chance(dt * 0.6) {
            c.idleVariant = "look"
            c.set(.idle, duration: rng.range(3, 6))
        }
    }

    // MARK: Star shards

    private func updateShards(_ s: Spectacle, _ dt: Double, _ f: Rect) {
        for i in s.shards.indices where !s.shards[i].landed {
            var sh = s.shards[i]
            let prev = sh.pos
            sh.vel.y = max(sh.vel.y - gravity * 0.5 * dt, -900)
            sh.pos += sh.vel * dt
            sh.pos.x = sh.pos.x.clamped(f.minX + 20, f.maxX - 20)
            if sh.vel.y <= 0, let land = surfaces.filter({ prev.y >= $0.y - 0.5 && sh.pos.y <= $0.y && $0.supports(x: sh.pos.x) }).max(by: { $0.y < $1.y }) {
                sh.pos.y = land.y
                sh.landed = true
                sh.landedAt = s.age
            }
            if sh.pos.y < f.minY - 50 { sh.pos.y = f.minY; sh.landed = true; sh.landedAt = s.age }
            s.shards[i] = sh
        }
        // Gremlets race for landed shards on their own level.
        var taken = Set<Int>()
        for c in creatures where c.job == nil && c.isGrounded && c.play == nil {
            guard let sh = s.shards.filter({ $0.landed && !taken.contains($0.id) && abs($0.pos.y - c.pos.y) < 6 })
                .min(by: { abs($0.pos.x - c.pos.x) < abs($1.pos.x - c.pos.x) }) else { continue }
            taken.insert(sh.id)
            if abs(sh.pos.x - c.pos.x) < 18 {
                s.shards.removeAll { $0.id == sh.id }
                s.events.append(.shardCollected(sh.pos, by: c.id))
                for i in grove.plants.indices { grove.plants[i].sparks += 0.34 }
                rebuildGroveSurfaces(); setSurfacesDirty()
                c.set(.react, duration: c.animationLength(for: .react) + 0.1)
                emit(.poked(c.id))
            } else if [Activity.idle, .walk].contains(c.activity) && abs(sh.pos.x - c.pos.x) < 700 {
                c.facing = sh.pos.x > c.pos.x ? 1 : -1
                if c.activity != .walk { c.set(.walk, duration: 3) }
            }
        }
        // Uncollected shards fade after a while.
        s.shards.removeAll { $0.landed && s.age - $0.landedAt > 16 }
    }
}
