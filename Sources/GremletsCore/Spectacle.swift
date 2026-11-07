import Foundation

/// Special events: big, rare moments that take over the main screen for under a minute and pull the whole grove in.
///
/// - **Stormwyrm** (boss): a huge storm-cloud serpent coils across the screen, dives low and calls lightning.
///   Gremlets fight back with sunberries from the grove, bounce off the bouncecap to headbutt it, the snapjaw bites
///   it when it dives, and you can click it too. Win and it bursts into stardust that grows the grove.
/// - **Meteor shower** (at night): shooting stars streak across the screen and drop star shards that Gremlets race
///   to collect. Every shard is a spark for the grove.
/// - **Bloom festival** (when a grove plant reaches level 5): petals, lanterns and a dance party at the grove.
///
/// Everything is visual and playful: nothing blocks your clicks except the boss's own body, and events never start
/// during a focus session or while the Gremlets are hidden for a call.
public enum SpectacleKind: String, CaseIterable, Sendable {
    case boss, meteors, festival

    public var title: String {
        switch self {
        case .boss: return "The Stormwyrm"
        case .meteors: return "Meteor shower"
        case .festival: return "Bloom festival"
        }
    }
}

public enum SpectaclePhase: Sendable { case intro, main, outro }

/// A lightning strike: warned first (a flickering line), then it strikes.
public struct Bolt: Sendable {
    public var x: Double
    public var fromY: Double
    public var toY: Double
    public var age: Double = 0
    public static let warn = 0.9
    public static let strike = 0.3
    public var striking: Bool { age >= Bolt.warn }
    var resolved = false
}

public struct Projectile: Sendable {
    public enum Kind: Sendable { case berry, pebble }
    public var kind: Kind
    public var pos: Vec2
    public var vel: Vec2
    public var from: Int
    public var age: Double = 0
}

public struct Shard: Sendable {
    public var id: Int
    public var pos: Vec2
    public var vel: Vec2
    public var landed = false
    public var landedAt = 0.0
}

public enum SpectacleEvent: Equatable, Sendable {
    case started(SpectacleKind)
    case hit(Vec2, damage: Double, by: Int?)   // by = creature id, nil = you or the snapjaw
    case chomp(plot: Int)
    case boltWarn(x: Double)
    case boltStrike(x: Double, y: Double)
    case throwBerry(Int)
    case shardCollected(Vec2, by: Int)
    case meteor(from: Vec2, to: Vec2)
    case roar
    case ended(SpectacleKind, won: Bool)
}

public final class Spectacle {
    public let kind: SpectacleKind
    public internal(set) var phase: SpectaclePhase = .intro
    public internal(set) var age = 0.0
    public let duration: Double
    // Boss
    public internal(set) var segments: [Vec2] = []
    public internal(set) var hp = 0.0
    public internal(set) var maxHP = 0.0
    public internal(set) var bolts: [Bolt] = []
    public internal(set) var projectiles: [Projectile] = []
    public internal(set) var facing = 1.0
    public internal(set) var won = false
    /// Recent damage (fades), so the renderer can flash the boss.
    public internal(set) var hurt = 0.0
    // Meteors
    public internal(set) var shards: [Shard] = []
    var trail: [Vec2] = []
    var nextBolt = 3.0
    var nextDive = 7.0
    var diveUntil = -1.0
    var nextShard = 0.6
    var shardIDs = 0
    var phaseT = 0.0
    var seed = 0.0
    var bonked: [Int: Double] = [:]
    var lastChomp = -10.0
    var events: [SpectacleEvent] = []

    public static let segmentCount = 16
    public static let segmentSpacing = 34.0
    public static let headRadius = 46.0
    public static func radius(_ i: Int) -> Double { i == 0 ? headRadius : max(16, 38 - Double(i) * 1.4) }

    init(kind: SpectacleKind) {
        self.kind = kind
        switch kind {
        case .boss: duration = 70; maxHP = 100; hp = 100
        case .meteors: duration = 26
        case .festival: duration = 22
        }
    }

    public var isBoss: Bool { kind == .boss }
    public var head: Vec2? { segments.first }
    public var hpFraction: Double { maxHP > 0 ? max(0, hp / maxHP) : 0 }
    public var diving: Bool { age < diveUntil }
}

extension World {

    /// Queues an event (it starts when nothing else is running and the time is right).
    public func requestEvent(_ k: SpectacleKind) {
        if !pendingEvents.contains(k) { pendingEvents.append(k) }
    }

    /// Starts an event right away (the menu's "Summon" items). Returns false if one is already running.
    @discardableResult
    public func startEvent(_ k: SpectacleKind) -> Bool {
        guard spectacle == nil, let f = groveFloor else { return false }
        let s = Spectacle(kind: k)
        s.seed = rng.range(0, 6.28)
        if k == .boss {
            // Comes in from off-screen on one side, coiled up.
            let fromLeft = rng.chance(0.5)
            s.facing = fromLeft ? 1 : -1
            let start = Vec2(fromLeft ? f.minX - 200 : f.maxX + 200, f.minY + f.h * 0.7)
            s.segments = (0..<Spectacle.segmentCount).map { i in start - Vec2(s.facing * Double(i) * Spectacle.segmentSpacing, 0) }
            s.trail = s.segments
            // A stronger grove makes for a tougher boss (and better loot).
            let strength = grove.plants.reduce(0) { $0 + $1.level }
            s.maxHP = 80 + Double(strength) * 4
            s.hp = s.maxHP
            grove.tasksSinceBoss = 0
        }
        spectacle = s
        s.events.append(.started(k))
        for c in creatures where c.activity == .sleep || c.isAsleep { c.set(.wake, duration: c.animationLength(for: .wake)) }
        if k == .festival { for c in creatures where c.job == nil && c.isGrounded { startDance(c, duration: rng.range(5, 9), invite: false) } }
        return true
    }

    public func drainSpectacleEvents() -> [SpectacleEvent] {
        guard let s = spectacle ?? lastSpectacle else { return [] }
        defer { s.events.removeAll(); if spectacle == nil { lastSpectacle = nil } }
        return s.events
    }

    /// You clicked the boss. Returns true if it was hit.
    @discardableResult
    public func hitBoss(at p: Vec2) -> Bool {
        guard let s = spectacle, s.isBoss, s.phase == .main, bossSegment(at: p, s) != nil else { return false }
        damageBoss(s, 3, at: p, by: nil)
        return true
    }

    /// Whether a point is on the boss's body (for click-through).
    public func bossContains(_ p: Vec2) -> Bool {
        guard let s = spectacle, s.isBoss, s.phase != .outro else { return false }
        return bossSegment(at: p, s) != nil
    }

    func bossSegment(at p: Vec2, _ s: Spectacle, pad: Double = 0) -> Int? {
        s.segments.indices.first { (s.segments[$0] - p).length < Spectacle.radius($0) + pad }
    }

    func damageBoss(_ s: Spectacle, _ amount: Double, at p: Vec2, by: Int?) {
        guard s.phase == .main else { return }
        s.hp -= amount
        s.hurt = 1
        s.events.append(.hit(p, damage: amount, by: by))
        if s.hp <= 0 { finishSpectacle(s, won: true) }
    }

    func finishSpectacle(_ s: Spectacle, won: Bool) {
        guard s.phase != .outro else { return }
        s.phase = .outro
        s.phaseT = 0
        s.won = won
        s.bolts.removeAll()
        if s.kind == .boss && won {
            // Victory: stardust shards rain down from where it burst, a wish, and the grove grows.
            makeWish()
            for i in grove.plants.indices { grove.plants[i].sparks += 2 }
            rebuildGroveSurfaces(); setSurfacesDirty()
            for seg in s.segments.prefix(10) {
                s.shardIDs += 1
                s.shards.append(Shard(id: s.shardIDs, pos: seg, vel: Vec2(rng.range(-220, 220), rng.range(100, 420))))
            }
            for c in creatures where c.job == nil && c.isGrounded { startDance(c, duration: rng.range(3, 6), invite: false) }
        }
        s.events.append(.ended(s.kind, won: won))
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
        if calm || !eventsAllowed { finishSpectacle(s, won: false) }
        s.age += dt
        s.phaseT += dt
        s.hurt = max(0, s.hurt - dt * 3)
        switch s.phase {
        case .intro: if s.phaseT > (s.isBoss ? 2.2 : 0.5) { s.phase = .main; s.phaseT = 0; if s.isBoss { s.events.append(.roar) } }
        case .main: if s.age > s.duration { finishSpectacle(s, won: false) }
        case .outro: break
        }
        switch s.kind {
        case .boss: updateBoss(s, dt, f)
        case .meteors: updateMeteors(s, dt, f)
        case .festival: updateFestival(s, dt, f)
        }
        updateShards(s, dt, f)
        let outroLength = s.kind == .boss ? (s.won ? 9.0 : 4.0) : 6.0
        if s.phase == .outro && s.phaseT > outroLength && s.shards.isEmpty || s.phase == .outro && s.phaseT > outroLength + 12 {
            lastSpectacle = s
            spectacle = nil
            for c in creatures { if c.groveTask != nil { c.groveTask = nil } }
        }
    }

    // MARK: Boss

    private func updateBoss(_ s: Spectacle, _ dt: Double, _ f: Rect) {
        guard !s.segments.isEmpty else { return }
        var head = s.segments[0]
        let t = s.age + s.seed
        let target: Vec2
        switch s.phase {
        case .intro, .main:
            if s.phase == .main && s.age > s.nextDive && s.diveUntil < s.age {
                s.diveUntil = s.age + 3.2
                s.nextDive = s.age + rng.range(7, 10)
                s.events.append(.roar)
            }
            if s.diving {
                // Swoop low across the grove: this is the moment to hit it.
                let k = (s.diveUntil - s.age) / 3.2
                target = Vec2(f.minX + f.w * (s.facing > 0 ? 1 - k : k), f.minY + 150 + sin(t * 3) * 30)
            } else {
                target = Vec2(f.midX + sin(t * 0.42) * f.w * 0.38, f.minY + f.h * (0.62 + 0.18 * sin(t * 0.77)))
            }
        case .outro:
            // Lost: it flies off the top. Won: it's gone (shards and stardust take over).
            target = s.won ? head : Vec2(head.x + s.facing * 400, f.maxY + 400)
        }
        let speed = s.diving ? 720.0 : 340.0
        let d = target - head
        if d.length > 1 {
            let step = min(d.length, speed * dt)
            head += d * (step / d.length)
            if abs(d.x) > 20 { s.facing = d.x > 0 ? 1 : -1 }
        }
        // Body follows the head's trail, evenly spaced.
        s.trail.insert(head, at: 0)
        var segs = [head]
        var need = Spectacle.segmentSpacing, acc = 0.0
        for i in 1..<s.trail.count where segs.count < Spectacle.segmentCount {
            let a = s.trail[i - 1], b = s.trail[i]
            let l = (a - b).length
            acc += l
            while acc >= need && segs.count < Spectacle.segmentCount {
                let over = acc - need
                let u = l > 0 ? over / l : 0
                segs.append(b + (a - b) * u)
                need += Spectacle.segmentSpacing
            }
        }
        while segs.count < Spectacle.segmentCount { segs.append(segs.last ?? head) }
        if s.trail.count > 600 { s.trail.removeLast(s.trail.count - 600) }
        s.segments = segs
        if s.phase == .outro && s.won { s.segments = [] }

        guard s.phase == .main else { s.bolts.removeAll(); updateProjectiles(s, dt, f); return }

        // Lightning: aim at a Gremlet now and then, otherwise somewhere along the floor.
        if s.age > s.nextBolt && !s.diving {
            s.nextBolt = s.age + rng.range(2.6, 4.2) * (s.hpFraction < 0.4 ? 0.65 : 1)
            let victims = creatures.filter { $0.isGrounded && $0.job == nil && abs($0.pos.x - head.x) < f.w * 0.5 }
            let x = victims.isEmpty || rng.chance(0.3) ? rng.range(f.minX + 60, f.maxX - 60)
                : victims[Int(rng.next() % UInt64(victims.count))].pos.x + rng.range(-40, 40)
            let ground = surfaces.filter { $0.supports(x: x) && $0.y < head.y }.map(\.y).max() ?? f.minY
            s.bolts.append(Bolt(x: x, fromY: head.y, toY: ground))
            s.events.append(.boltWarn(x: x))
        }
        for i in s.bolts.indices {
            s.bolts[i].age += dt
            if s.bolts[i].striking && !s.bolts[i].resolved {
                s.bolts[i].resolved = true
                let b = s.bolts[i]
                s.events.append(.boltStrike(x: b.x, y: b.toY))
                // Zapped Gremlets get knocked away, seeing stars (never hurt).
                for c in creatures where c.isGrounded && c.job == nil && abs(c.pos.x - b.x) < 56 && abs(c.pos.y - b.toY) < 6 {
                    c.groundOwner = nil
                    c.vel = Vec2((c.pos.x < b.x ? -1 : 1) * rng.range(260, 420), rng.range(620, 860))
                    c.set(.airborne)
                    emit(.startled(c.id))
                }
            }
        }
        s.bolts.removeAll { $0.age > Bolt.warn + Bolt.strike }

        // The snapjaw bites when the boss dives over it.
        if let i = grove.plant(of: .snapjaw), s.age - s.lastChomp > 1.4 {
            let b = grove.base(i, floor: f), sz = grove.size(i)
            if let n = s.segments.indices.first(where: { abs(s.segments[$0].x - b.x) < sz.x * 0.8 && s.segments[$0].y - (b.y + sz.y) < 70 }) {
                s.lastChomp = s.age
                s.events.append(.chomp(plot: i))
                damageBoss(s, 4 + Double(grove.plants[i].level) * 1.5, at: s.segments[n], by: nil)
            }
        }

        // Gremlets in the air (bouncecap launches, jumps) headbutt it.
        for c in creatures where [.airborne, .fly].contains(c.activity) && (s.bonked[c.id] ?? -9) < s.age - 0.8 {
            let mid = c.pos + Vec2(0, c.size.y * 0.5)
            if let n = bossSegment(at: mid, s, pad: c.size.x * 0.3) {
                s.bonked[c.id] = s.age
                damageBoss(s, 6, at: s.segments[n], by: c.id)
                c.vel = Vec2(c.vel.x * -0.4, max(200, -c.vel.y * 0.3))
                emit(.special(c.id, effect: "bonk"))
            }
        }
        updateProjectiles(s, dt, f)
        guard s.phase == .main else { return }

        // Gremlets join in: berry holders throw, others fetch berries or jump at it when it dives low.
        for c in creatures where c.job == nil && c.isGrounded && [Activity.idle, .walk, .wave].contains(c.activity)
            && c.groveTask == nil && c.play == nil && rng.chance(dt * 0.9) {
            let dx = head.x - c.pos.x
            if c.heldBerry && abs(dx) < 900 {
                throwAtBoss(c, s, kind: .berry)
            } else if s.diving, let seg = s.segments.min(by: { abs($0.x - c.pos.x) < abs($1.x - c.pos.x) }),
                      abs(seg.x - c.pos.x) < 260, seg.y - c.pos.y < maxJumpHeight + 40, seg.y > c.pos.y {
                c.facing = seg.x > c.pos.x ? 1 : -1
                launch(c, velocity: ballistic(from: c.pos, toX: seg.x, y: seg.y, apexExtra: 30))
            } else if let i = grove.plant(of: .sunberry), grove.plants[i].berries > 0, abs(c.pos.y - f.minY) < 4, rng.chance(0.5) {
                startGroveVisit(c, plot: i, task: .snack)
            } else if rng.chance(0.35) && abs(dx) < 900 {
                throwAtBoss(c, s, kind: .pebble)
            } else {
                c.facing = dx > 0 ? 1 : -1
            }
        }
    }

    private func throwAtBoss(_ c: Creature, _ s: Spectacle, kind: Projectile.Kind) {
        guard let head = s.head else { return }
        if kind == .berry { c.heldBerry = false }
        let from = c.pos + Vec2(0, c.size.y * 0.7)
        // Lead the target a little, and aim for a high arc that drops onto it.
        let aim = head + Vec2(s.facing * 60, 0)
        let dx = aim.x - from.x, dy = aim.y - from.y
        let apex = max(dy, 0) + 140
        let vy = (2 * gravity * apex).squareRoot()
        let tUp = vy / gravity
        let tDown = ((2 * max(1, apex - dy)) / gravity).squareRoot()
        let vx = dx / (tUp + tDown)
        s.projectiles.append(Projectile(kind: kind, pos: from, vel: Vec2(vx, vy), from: c.id))
        c.facing = dx > 0 ? 1 : -1
        c.set(.special, duration: c.animationLength(for: .special))
        s.events.append(.throwBerry(c.id))
    }

    private func updateProjectiles(_ s: Spectacle, _ dt: Double, _ f: Rect) {
        for i in s.projectiles.indices {
            s.projectiles[i].age += dt
            s.projectiles[i].vel.y -= gravity * dt
            s.projectiles[i].pos += s.projectiles[i].vel * dt
        }
        var keep: [Projectile] = []
        for p in s.projectiles {
            if s.phase == .main, let n = bossSegment(at: p.pos, s, pad: 10) {
                damageBoss(s, p.kind == .berry ? 5 : 2, at: s.segments[n], by: p.from)
                continue
            }
            if p.pos.y > f.minY - 40 && p.age < 4 { keep.append(p) }
        }
        s.projectiles = keep
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

    // MARK: Festival

    private func updateFestival(_ s: Spectacle, _ dt: Double, _ f: Rect) {
        guard s.phase == .main else { return }
        for c in creatures where c.job == nil && c.isGrounded && c.activity == .idle && rng.chance(dt * 0.5) {
            startDance(c, duration: rng.range(3, 6), invite: true)
        }
    }

    // MARK: Shards (meteor showers and a defeated boss)

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

