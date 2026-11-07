import Foundation

/// Expeditions: the long way round, Terraria style.
///
/// Now and then a chest turns up somewhere hard to reach (the top of a tall window, a high ledge). A Gremlet that
/// spots it plans a route from where it stands, through every trick it knows, and sets off: walking onto neighbouring
/// platforms, jumping, laying a staircase of blocks it picks back up behind it, bridging a gap with planks, firing
/// the grappling hook, stepping off edges, gliding down on a leaf, or stringing a zipline and sliding down it. It
/// carries the chest home over its head, opens it in the village, and keeps what it finds (a gem for the merchant).
/// Every so often one sets out just to reach the highest point on the desktop and plant its flag there.
///
/// Routes are planned over the same `Surface`s the physics uses (Dijkstra over "legs"), re-planned when a leg goes
/// wrong (a window moved, a landing missed), and abandoned after a few tries. Nothing here is scripted: the route
/// depends on wherever your windows happen to be.
public struct Zipline: Sendable {
    public let id: Int
    /// Cable anchors (the rider hangs `hang` below the cable).
    public let top: Vec2, bottom: Vec2
    let topOwner: Int, bottomOwner: Int
    public let madeAt: Double
    public static let lifetime = 420.0
    public static let hang = 44.0
}

public struct ZipRide: Sendable {
    public let zipline: Int
    public internal(set) var t: Double
}

public struct Chest: Equatable, Sendable {
    public let id: Int
    /// Bottom centre.
    public internal(set) var pos: Vec2
    public internal(set) var windowID: Int?
    var offsetX: Double
    public internal(set) var carriedBy: Int?
    public let golden: Bool
    public let spawnedAt: Double
    public static let lifetime = 2400.0
}

public struct Flag: Equatable, Sendable {
    public let id: Int
    public internal(set) var pos: Vec2
    var windowID: Int?
    var offsetX: Double
    /// Species id of the Gremlet who planted it (its colour).
    public let owner: String
    public let plantedAt: Double
    public static let lifetime = 1800.0
}

public enum ExpeditionGoal: Equatable, Sendable {
    case treasure(Int)
    case summit
}

public enum LegMethod: String, Sendable {
    case walk, jump, drop, glide, climb, grapple, bridge, zip
}

public struct Leg: Sendable {
    public let from: Surface, to: Surface
    public let method: LegMethod
    /// Where on `from` to be before acting, and which way the action goes.
    public let actX: Double
    public let dir: Double
}

public struct Expedition: Sendable {
    public enum Phase: Sendable { case outbound, fetching, homebound, opening }
    public let goal: ExpeditionGoal
    public internal(set) var legs: [Leg]
    public internal(set) var index = 0
    public internal(set) var phase: Phase = .outbound
    var legStarted: Double
    /// 0 = getting to the acting spot, 1 = acted, waiting to arrive.
    var stage = 0
    var replans = 0
    var strayedSince: Double?
    public let startedAt: Double
    public var leg: Leg? { index < legs.count ? legs[index] : nil }
    public var methods: [LegMethod] { legs.map(\.method) }
}

public enum ExpeditionEvent: Equatable, Sendable {
    case started(by: Int, goal: ExpeditionGoal, legs: Int)
    case legDone(by: Int, method: LegMethod)
    case gaveUp(by: Int)
    case chestAppeared(Int)
    case chestTaken(Int, by: Int)
    case chestDropped(Int)
    case chestOpened(Int, by: Int, gem: GemKind)
    case summit(by: Int, flag: Int)
    case flagLost(Int)
    case zipMade(Int)
    case zipped(by: Int, zipline: Int)
    case zipLost(Int)
}

extension World {
    // MARK: Route planning

    /// Places worth standing on while planning a route.
    func routeNodes() -> [Surface] {
        surfaces.filter { s in
            [.floor, .windowTop, .windowLedge, .plant].contains(s.kind) && s.width >= 40
                && !World.isStairOwner(s.ownerID) && !World.isCartOwner(s.ownerID) && !isBouncy(s.ownerID)
        }
    }

    /// The bouncecap's cap launches whoever lands on it: no place to plan through.
    func isBouncy(_ owner: Int) -> Bool {
        guard World.isGroveOwner(owner) else { return false }
        let n = World.groveOwnerBase - owner
        return n < groveLedges.count && groveLedges[n].bouncy
    }

    func sameNode(_ a: Surface, _ b: Surface) -> Bool {
        a.ownerID == b.ownerID && abs(a.y - b.y) < 3 && a.minX <= b.maxX + 1 && a.maxX >= b.minX - 1
    }

    /// Something to land on between two heights at `x` (so a drop wouldn't reach `to`): any platform at all, not just
    /// the ones worth planning through (a narrow roof catches a falling Gremlet just the same).
    func blocked(x: Double, from top: Double, to bottom: Double, nodes: [Surface]) -> Bool {
        surfaces.contains { $0.y < top - 1 && $0.y > bottom + 1 && $0.supports(x: x) && !World.isCartOwner($0.ownerID) }
    }

    /// The nodes to plan over, plus wherever we're standing and wherever the goal is (either may be a perch too
    /// narrow to count as a node, like a roof ridge).
    func planNodes(start: Surface, also: Surface? = nil) -> [Surface] {
        var nodes = routeNodes()
        if !nodes.contains(where: { sameNode($0, start) }) { nodes.append(start) }
        if let a = also, !nodes.contains(where: { sameNode($0, a) }) { nodes.append(a) }
        return nodes
    }

    /// The platform a chest sits on.
    func perch(of ch: Chest) -> Surface? {
        surfaces.first { abs($0.y - ch.pos.y) < 3 && $0.supports(x: ch.pos.x) && !World.isCartOwner($0.ownerID) }
    }

    /// The cheapest way (in seconds) from `a` straight to `b`, if there is one.
    func leg(from a: Surface, to b: Surface, for c: Creature, nodes: [Surface]) -> (Leg, Double)? {
        let dy = b.y - a.y
        let gap = max(0, max(b.minX - a.maxX, a.minX - b.maxX))
        let overlapLo = max(a.minX, b.minX), overlapHi = min(a.maxX, b.maxX)
        let aMid = (a.minX + a.maxX) / 2, bMid = (b.minX + b.maxX) / 2
        var best: (Leg, Double)?
        func consider(_ method: LegMethod, actX: Double, dir: Double, cost: Double) {
            if best == nil || cost < best!.1 { best = (Leg(from: a, to: b, method: method, actX: actX, dir: dir), cost) }
        }
        // Straight across onto a neighbour at about the same height (a small step up or down is taken in stride).
        if abs(dy) <= World.strideStep, gap <= 2 {
            let x = b.minX > a.minX ? b.minX + min(24, b.width / 2) : b.maxX - min(24, b.width / 2)
            consider(.walk, actX: x, dir: x > aMid ? 1 : -1, cost: 0.5 + abs(x - aMid) / c.species.walkSpeed)
        }
        // Jump up.
        let maxH = maxJumpHeight * c.species.jumpPower
        if dy > 25, dy < maxH, gap + 24 < maxJumpDistance {
            let x = overlapHi >= overlapLo ? (overlapLo + overlapHi) / 2 : (b.minX > a.maxX ? a.maxX - 8 : a.minX + 8)
            consider(.jump, actX: x.clamped(a.minX + 6, a.maxX - 6), dir: bMid > x ? 1 : -1, cost: 1.5 + gap / 300)
        }
        if dy < -10 {
            // Step off the end and drop onto it, when nothing is in the way.
            for (edgeX, dir) in [(a.maxX + 14, 1.0), (a.minX - 14, -1.0)] where b.supports(x: edgeX) && !blocked(x: edgeX, from: a.y, to: b.y, nodes: nodes) {
                consider(.drop, actX: edgeX, dir: dir, cost: 1 + (a.y - b.y) / 1200)
                break
            }
            // Glide a long way down and across on a leaf.
            if dy <= -220 {
                let reach = -dy * 2.2
                if b.minX > a.maxX, b.minX - a.maxX < reach { consider(.glide, actX: a.maxX - 4, dir: 1, cost: 2.5) }
                if b.maxX < a.minX, a.minX - b.maxX < reach { consider(.glide, actX: a.minX + 4, dir: -1, cost: 2.5) }
            }
            // Zip down a line.
            if dy <= -120, gap >= 120, gap <= 900, b.width >= 60 {
                let dir: Double = b.minX > a.maxX ? 1 : -1
                consider(.zip, actX: dir > 0 ? a.maxX - 10 : a.minX + 10, dir: dir, cost: 2 + gap / 500)
            }
        }
        // Up: a staircase of blocks (preferred: it's the fun way), or the grappling hook.
        if dy >= 90, dy <= 480, b.kind == .windowTop, let plan = stairPlan(from: a, to: b, nodes: nodes) {
            consider(.climb, actX: plan.standX, dir: plan.dir, cost: 1 + Double(plan.steps) * 0.25)
        }
        if dy > maxH * 0.85, dy < 620, b.width > 60, [.windowTop, .plant, .windowLedge].contains(b.kind) {
            let x = bMid.clamped(a.minX + 6, a.maxX - 6)
            // Dear: the hook is the last resort, stairs and bridges are the show.
            if abs(x - bMid) < 520 { consider(.grapple, actX: x, dir: bMid > x ? 1 : -1, cost: 14 + dy / 50) }
        }
        // A plank bridge across a gap.
        if abs(dy) < 26, gap > 50, gap < 340, [.windowTop, .windowLedge].contains(a.kind), [.windowTop, .windowLedge].contains(b.kind), bridges.count < 4 {
            let dir: Double = b.minX > a.maxX ? 1 : -1
            consider(.bridge, actX: dir > 0 ? a.maxX - 10 : a.minX + 10, dir: dir, cost: 2 + gap / Bridge.blockWidth * 0.38)
        }
        return best
    }

    /// Dijkstra over the nodes. `goal` picks the destination; with `summit` the farthest-up node reached wins.
    func route(for c: Creature, from start: Surface, nodes given: [Surface], goal: ExpeditionGoal) -> [Leg]? {
        var nodes = given
        if !nodes.contains(where: { sameNode($0, start) }) { nodes.append(start) }
        if case .treasure(let id) = goal, let ch = chests.first(where: { $0.id == id }), let p = perch(of: ch), !nodes.contains(where: { sameNode($0, p) }) { nodes.append(p) }
        guard let s = nodes.firstIndex(where: { sameNode($0, start) }) else { return nil }
        let n = nodes.count
        var dist = Array(repeating: Double.infinity, count: n)
        var prev = Array<(Int, Leg)?>(repeating: nil, count: n)
        var done = Array(repeating: false, count: n)
        dist[s] = 0
        var target: Int?
        if case .treasure(let id) = goal, let ch = chests.first(where: { $0.id == id }) {
            target = nodes.firstIndex { abs($0.y - ch.pos.y) < 3 && $0.supports(x: ch.pos.x) }
            guard target != nil else { return nil }
        }
        while true {
            var u = -1
            for i in 0..<n where !done[i] && dist[i] < .infinity && (u < 0 || dist[i] < dist[u]) { u = i }
            if u < 0 { break }
            done[u] = true
            if let t = target, u == t { break }
            for v in 0..<n where !done[v] {
                if let (l, cost) = leg(from: nodes[u], to: nodes[v], for: c, nodes: nodes), dist[u] + cost < dist[v] {
                    dist[v] = dist[u] + cost
                    prev[v] = (u, l)
                }
            }
        }
        let end: Int
        if let t = target {
            guard dist[t] < .infinity else { return nil }
            end = t
        } else {
            // The summit: the highest place reached, well above where we started.
            guard let top = (0..<n).filter({ dist[$0] < .infinity && nodes[$0].y >= start.y + 150 && nodes[$0].kind != .floor })
                .max(by: { (nodes[$0].y, -dist[$0]) < (nodes[$1].y, -dist[$1]) }) else { return nil }
            end = top
        }
        var legs: [Leg] = []
        var cur = end
        while cur != s, let (p, l) = prev[cur] { legs.append(l); cur = p }
        return legs.reversed()
    }

    // MARK: Starting out

    /// The main floor, where chests are opened.
    var homeFloor: Surface? { surfaces.first { $0.kind == .floor && $0.ownerID == -1 } }

    /// Where a chest gets opened: by the Gremlet's own house, or in the middle of the village.
    func openingSpot(for c: Creature) -> Double? {
        guard let f = groveFloor else { return nil }
        if let h = grove.village.first(where: { $0.owner == c.species.id }) { return f.minX + h.x * f.w }
        let xs = grove.village.filter { !$0.biome.hasPrefix("item:") && $0.biome != "mine" }.map { f.minX + $0.x * f.w }
        if !xs.isEmpty { return xs.reduce(0, +) / Double(xs.count) }
        return f.maxX - 300
    }

    @discardableResult
    public func startExpedition(_ c: Creature, _ goal: ExpeditionGoal) -> Bool {
        guard c.expedition == nil, c.job == nil, c.isGrounded, let support = supportingSurface(for: c) else { return false }
        let nodes = planNodes(start: support)
        var legs: [Leg] = []
        var phase = Expedition.Phase.outbound
        switch goal {
        case .treasure(let id):
            guard let ch = chests.first(where: { $0.id == id }), ch.carriedBy == nil else { return false }
            if abs(ch.pos.y - support.y) < 3 && support.supports(x: ch.pos.x) {
                phase = .fetching
            } else {
                guard let r = route(for: c, from: support, nodes: nodes, goal: goal), !r.isEmpty else { return false }
                legs = r
            }
        case .summit:
            guard let r = route(for: c, from: support, nodes: nodes, goal: goal), !r.isEmpty else { return false }
            legs = r
            nextSummitAt = clock + rng.range(1500, 2700)
        }
        endSocial(c)
        c.visitingID = nil; c.tendX = nil; c.targetX = nil
        c.expedition = Expedition(goal: goal, legs: legs, phase: phase, legStarted: clock, startedAt: clock)
        nextExpeditionAt = clock + 90
        expeditionEvents.append(.started(by: c.id, goal: goal, legs: legs.count))
        c.set(.react, duration: min(0.5, c.animationLength(for: .react)))
        emit(.alert(c.id))
        return true
    }

    /// `gremlet expedition`: someone sets out for the highest point. `gremlet chest`: a chest appears and someone
    /// goes for it.
    @discardableResult
    public func startExpeditionWithAnyone(_ goal: ExpeditionGoal) -> Bool {
        nextExpeditionAt = 0
        let free = creatures.filter { $0.expedition == nil && $0.job == nil && $0.play == nil && $0.isGrounded && $0.homeUntil == nil }
        for c in free.shuffled(using: &rng) where startExpedition(c, goal) { return true }
        return false
    }

    func expeditionChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard c.expedition == nil, c.job == nil, c.play == nil, c.groveTask == nil, c.isGrounded, !calm, clock >= nextExpeditionAt,
              c.energy > 0.35, c.homeUntil == nil else { return }
        if let chest = chests.first(where: { ch in ch.carriedBy == nil && !creatures.contains { $0.expedition?.goal == .treasure(ch.id) } }) {
            add("treasure", 1.8) { if !self.startExpedition(c, .treasure(chest.id)) { c.set(.idle, duration: 1) } }
        }
        if clock >= nextSummitAt, userActive {
            add("summit", 0.5) { if !self.startExpedition(c, .summit) { self.nextSummitAt = self.clock + 600; c.set(.idle, duration: 1) } }
        }
    }

    // MARK: Underway

    static let legTimeout: [LegMethod: Double] = [.walk: 25, .jump: 12, .drop: 14, .glide: 16, .climb: 75, .grapple: 14, .bridge: 70, .zip: 16]

    /// Bookkeeping every tick: arrivals, strays, timeouts, fetching and opening.
    func updateExpeditions(_ dt: Double) {
        for c in creatures {
            guard var ex = c.expedition else { continue }
            if clock - ex.startedAt > 360 { giveUp(c); continue }
            guard c.isGrounded, let s = supportingSurface(for: c) else { continue }
            switch ex.phase {
            case .fetching:
                guard let i = chests.firstIndex(where: { $0.id == goalChest(ex) }), chests[i].carriedBy == nil else { giveUp(c); continue }
                let ch = chests[i]
                guard abs(ch.pos.y - s.y) < 3, s.supports(x: ch.pos.x) else { replan(c, &ex, from: s); continue }
                if abs(c.pos.x - ch.pos.x) < 16 {
                    chests[i].carriedBy = c.id
                    expeditionEvents.append(.chestTaken(ch.id, by: c.id))
                    c.set(.react, duration: c.animationLength(for: .react) + 0.2)
                    c.targetX = nil
                    // Home: down to the main floor, then over to the opening spot.
                    if let home = homeFloor, !sameNode(s, home) {
                        guard let r = routeHome(for: c, from: s), !r.isEmpty else { c.expedition = ex; giveUp(c); continue }
                        ex.legs = r; ex.index = 0; ex.stage = 0; ex.phase = .homebound; ex.legStarted = clock; ex.strayedSince = nil
                    } else {
                        ex.phase = .opening; ex.legStarted = clock; ex.legs = []; ex.index = 0
                    }
                    c.expedition = ex
                } else if clock - ex.legStarted > 40 {
                    giveUp(c)
                }
            case .opening:
                guard let spot = openingSpot(for: c) else { giveUp(c); continue }
                if abs(c.pos.x - spot) < 16 || clock - ex.legStarted > 60 { openChest(c) }
            case .outbound, .homebound:
                guard let leg = ex.leg else {
                    reachedEnd(c, &ex, on: s)
                    continue
                }
                if sameNode(s, leg.to) {
                    ex.index += 1; ex.stage = 0; ex.legStarted = clock; ex.strayedSince = nil
                    expeditionEvents.append(.legDone(by: c.id, method: leg.method))
                    c.targetX = nil
                    if ex.leg == nil { reachedEnd(c, &ex, on: s) } else { c.expedition = ex }
                    continue
                }
                if sameNode(s, leg.from) || World.isStairOwner(s.ownerID) || World.isBridgeOwner(s.ownerID) {
                    ex.strayedSince = nil   // on the way: on its own blocks, or crossing a bridge
                } else if c.stair == nil && c.building == nil {
                    // Landed somewhere else: give it a moment (a hop in progress), then plan again from here.
                    if ex.strayedSince == nil { ex.strayedSince = clock }
                    if clock - ex.strayedSince! > 0.6 { replan(c, &ex, from: s); continue }
                }
                if clock - ex.legStarted > (World.legTimeout[leg.method] ?? 20) { replan(c, &ex, from: s); continue }
                c.expedition = ex
            }
        }
    }

    func goalChest(_ ex: Expedition) -> Int? { if case .treasure(let id) = ex.goal { return id }; return nil }

    func routeHome(for c: Creature, from s: Surface) -> [Leg]? {
        guard let home = homeFloor else { return nil }
        let nodes = planNodes(start: s)
        guard let hi = nodes.firstIndex(where: { sameNode($0, home) }) else { return nil }
        return routeTo(nodeIndex: hi, for: c, from: s, nodes: nodes)
    }

    func routeTo(nodeIndex t: Int, for c: Creature, from start: Surface, nodes: [Surface]) -> [Leg]? {
        guard let s = nodes.firstIndex(where: { sameNode($0, start) }) else { return nil }
        let n = nodes.count
        var dist = Array(repeating: Double.infinity, count: n)
        var prev = Array<(Int, Leg)?>(repeating: nil, count: n)
        var done = Array(repeating: false, count: n)
        dist[s] = 0
        while true {
            var u = -1
            for i in 0..<n where !done[i] && dist[i] < .infinity && (u < 0 || dist[i] < dist[u]) { u = i }
            if u < 0 || u == t { break }
            done[u] = true
            for v in 0..<n where !done[v] {
                if let (l, cost) = leg(from: nodes[u], to: nodes[v], for: c, nodes: nodes), dist[u] + cost < dist[v] {
                    dist[v] = dist[u] + cost
                    prev[v] = (u, l)
                }
            }
        }
        guard dist[t] < .infinity else { return nil }
        var legs: [Leg] = []
        var cur = t
        while cur != s, let (p, l) = prev[cur] { legs.append(l); cur = p }
        return legs.reversed()
    }

    func replan(_ c: Creature, _ ex: inout Expedition, from s: Surface) {
        ex.replans += 1
        guard ex.replans <= 3 else { giveUp(c); return }
        let nodes = planNodes(start: s)
        let r: [Leg]?
        switch ex.phase {
        case .homebound: r = routeHome(for: c, from: s)
        default:
            if case .treasure(let id) = ex.goal, let ch = chests.first(where: { $0.id == id }), abs(ch.pos.y - s.y) < 3, s.supports(x: ch.pos.x) {
                ex.phase = .fetching; ex.legs = []; ex.index = 0; ex.legStarted = clock
                c.targetX = nil
                c.expedition = ex
                return
            }
            r = route(for: c, from: s, nodes: nodes, goal: ex.goal)
        }
        guard let legs = r, !legs.isEmpty else { giveUp(c); return }
        ex.legs = legs; ex.index = 0; ex.stage = 0; ex.legStarted = clock; ex.strayedSince = nil
        c.targetX = nil
        if c.stair != nil { abandonStairs(c) }
        c.expedition = ex
    }

    func reachedEnd(_ c: Creature, _ ex: inout Expedition, on s: Surface) {
        switch ex.phase {
        case .outbound:
            switch ex.goal {
            case .treasure:
                ex.phase = .fetching; ex.legStarted = clock
                c.expedition = ex
            case .summit:
                plantFlag(c, on: s)
            }
        case .homebound:
            ex.phase = .opening; ex.legStarted = clock
            c.expedition = ex
        default:
            c.expedition = ex
        }
    }

    func giveUp(_ c: Creature) {
        dropChest(c)
        if c.stair != nil { abandonStairs(c) }
        c.expedition = nil
        c.targetX = nil
        expeditionEvents.append(.gaveUp(by: c.id))
        if c.isGrounded { c.set(.idle, duration: 1) }
    }

    /// The next move when the current activity runs out (instead of the brain's usual pick).
    func expeditionDecide(_ c: Creature) {
        func walkTo(_ x: Double) { c.targetX = x; c.facing = x > c.pos.x ? 1 : -1; c.set(.walk, duration: 30) }
        guard var ex = c.expedition, let support = supportingSurface(for: c) else { c.idleVariant = "look"; c.set(.idle, duration: 0.4); return }
        switch ex.phase {
        case .fetching:
            if let ch = chests.first(where: { $0.id == goalChest(ex) }), abs(ch.pos.x - c.pos.x) >= 14 { walkTo(ch.pos.x) } else { c.set(.idle, duration: 0.1) }
            return
        case .opening:
            if let spot = openingSpot(for: c), abs(spot - c.pos.x) >= 14 { walkTo(spot) } else { c.set(.idle, duration: 0.1) }
            return
        case .outbound, .homebound:
            break
        }
        guard let leg = ex.leg else { c.set(.idle, duration: 0.2); return }
        if ex.stage == 0 {
            let onFrom = sameNode(support, leg.from)
            if leg.method != .walk && onFrom && abs(c.pos.x - leg.actX) > 6 {
                c.targetX = leg.actX; c.facing = leg.actX > c.pos.x ? 1 : -1
                c.set(.walk, duration: 30)
                return
            }
            ex.stage = 1; ex.legStarted = clock
            c.expedition = ex
            act(c, leg, on: support)
            return
        }
        c.idleVariant = "look"
        c.set(.idle, duration: 0.6)
    }

    private func act(_ c: Creature, _ leg: Leg, on support: Surface) {
        c.facing = leg.dir
        switch leg.method {
        case .walk, .drop:
            c.targetX = leg.actX
            c.set(.walk, duration: 20)
        case .jump:
            let inset = min(16, leg.to.width / 2 - 1)
            let tx = c.pos.x.clamped(leg.to.minX + inset, leg.to.maxX - inset)
            launch(c, velocity: ballistic(from: c.pos, toX: tx, y: leg.to.y, apexExtra: 40))
        case .glide:
            startGlide(c, direction: leg.dir)
        case .climb:
            if let plan = stairPlan(from: support, to: leg.to, nodes: nil) { startStairs(c, plan) }
            else if var ex = c.expedition { ex.legStarted = -1000; c.expedition = ex; c.set(.idle, duration: 0.2) }
        case .grapple:
            let anchor = Vec2(c.pos.x.clamped(leg.to.minX + 40, leg.to.maxX - 40), leg.to.y)
            startGrapple(c, to: anchor)
        case .bridge:
            startBridge(c)
            if c.building == nil, var ex = c.expedition { ex.legStarted = -1000; c.expedition = ex; c.set(.idle, duration: 0.2) }
        case .zip:
            if !startZip(c, to: leg.to), var ex = c.expedition { ex.legStarted = -1000; c.expedition = ex; c.set(.idle, duration: 0.2) }
        }
    }

    // MARK: Chests

    /// A chest appears somewhere high up (or exactly `at`, for tests and demos). Returns its id.
    @discardableResult
    public func spawnChest(at: Vec2? = nil, golden: Bool? = nil) -> Int? {
        guard let f = groveFloor else { return nil }
        var pos: Vec2
        var owner: Int?
        if let at {
            pos = at
            owner = surfaces.first { abs($0.y - at.y) < 3 && $0.supports(x: at.x) && $0.ownerID >= 0 }?.ownerID
        } else {
            let spots = routeNodes().filter { [.windowTop, .windowLedge, .plant].contains($0.kind) && $0.y >= f.minY + 220 && $0.width >= 60 }
                .sorted { $0.y > $1.y }
            guard !spots.isEmpty else { return nil }
            let s = spots[Int(rng.next() % UInt64(min(3, spots.count)))]
            pos = Vec2(rng.range(s.minX + 30, s.maxX - 30), s.y)
            owner = s.ownerID >= 0 ? s.ownerID : nil
        }
        nextChestID += 1
        let gold = golden ?? rng.chance(0.15)
        chests.append(Chest(id: nextChestID, pos: pos, windowID: owner, offsetX: owner.flatMap { windows[$0] }.map { pos.x - $0.minX } ?? 0,
                            carriedBy: nil, golden: gold, spawnedAt: clock))
        expeditionEvents.append(.chestAppeared(nextChestID))
        nextChestAt = clock + rng.range(1200, 2400)
        return nextChestID
    }

    func updateChests(_ dt: Double) {
        if chests.isEmpty, clock >= nextChestAt, userActive, eventsAllowed, !calm, spectacle == nil { spawnChest() }
        guard !chests.isEmpty else { return }
        var i = 0
        while i < chests.count {
            if let by = chests[i].carriedBy, let c = creature(id: by) {
                chests[i].pos = c.pos + Vec2(0, c.size.y - 2)
            } else if clock - chests[i].spawnedAt > Chest.lifetime {
                chests.remove(at: i); continue
            }
            i += 1
        }
    }

    func dropChest(_ c: Creature) {
        guard let i = chests.firstIndex(where: { $0.carriedBy == c.id }) else { return }
        chests[i].carriedBy = nil
        chests[i].pos = Vec2(c.pos.x, c.pos.y)
        chests[i].windowID = (c.groundOwner ?? -1) >= 0 ? c.groundOwner : nil
        chests[i].offsetX = chests[i].windowID.flatMap { windows[$0] }.map { c.pos.x - $0.minX } ?? 0
        expeditionEvents.append(.chestDropped(chests[i].id))
    }

    func openChest(_ c: Creature) {
        guard let i = chests.firstIndex(where: { $0.carriedBy == c.id }) else { c.expedition = nil; return }
        let ch = chests.remove(at: i)
        let roll = rng.range(0, 1)
        let gem: GemKind = ch.golden
            ? (roll < 0.2 ? .starstone : roll < 0.55 ? .amethyst : .sapphire)
            : (roll < 0.04 ? .starstone : roll < 0.18 ? .amethyst : roll < 0.4 ? .sapphire : roll < 0.68 ? .emerald : .amber)
        grove.gems[gem.rawValue, default: 0] += 1
        expeditionEvents.append(.chestOpened(ch.id, by: c.id, gem: gem))
        c.expedition = nil
        c.targetX = nil
        c.set(.react, duration: c.animationLength(for: .react) + 0.6)
        emit(.special(c.id, effect: "sparkle"))
    }

    /// After the windows change: chests on a window move with it, or fall to the floor if it went away.
    func validateChests() {
        guard !chests.isEmpty, let f = groveFloor else { return }
        for i in chests.indices where chests[i].carriedBy == nil {
            guard let wid = chests[i].windowID else { continue }
            if let w = windows[wid], let top = builtSurfaces.first(where: { $0.ownerID == wid && $0.kind == .windowTop && $0.supports(x: w.minX + chests[i].offsetX) }) {
                chests[i].pos = Vec2(w.minX + chests[i].offsetX, top.y)
            } else {
                chests[i].windowID = nil
                chests[i].pos = Vec2(chests[i].pos.x.clamped(f.minX + 20, f.maxX - 20), f.minY)
            }
        }
    }

    // MARK: Flags

    func plantFlag(_ c: Creature, on s: Surface) {
        nextFlagID += 1
        let wid: Int? = s.ownerID >= 0 ? s.ownerID : nil
        flags.append(Flag(id: nextFlagID, pos: Vec2(c.pos.x + c.facing * 14, s.y), windowID: wid,
                          offsetX: wid.flatMap { windows[$0] }.map { c.pos.x + c.facing * 14 - $0.minX } ?? 0, owner: c.species.id, plantedAt: clock))
        if flags.count > 6 { flags.removeFirst() }
        expeditionEvents.append(.summit(by: c.id, flag: nextFlagID))
        c.expedition = nil
        c.targetX = nil
        c.set(.wave, duration: 2.2)
        emit(.special(c.id, effect: "sparkle"))
    }

    func validateFlags() {
        guard !flags.isEmpty else { return }
        var keep: [Flag] = []
        for var fl in flags {
            if let wid = fl.windowID {
                guard let w = windows[wid], builtSurfaces.contains(where: { $0.ownerID == wid && $0.kind == .windowTop && $0.supports(x: w.minX + fl.offsetX) }) else {
                    expeditionEvents.append(.flagLost(fl.id)); continue
                }
                fl.pos = Vec2(w.minX + fl.offsetX, w.maxY)
            }
            keep.append(fl)
        }
        flags = keep
    }

    func updateFlags() {
        let old = flags.filter { clock - $0.plantedAt > Flag.lifetime }
        guard !old.isEmpty else { return }
        for f in old { expeditionEvents.append(.flagLost(f.id)) }
        flags.removeAll { clock - $0.plantedAt > Flag.lifetime }
    }

    // MARK: Ziplines

    /// Strings a line from here down to `target` and rides it.
    @discardableResult
    func startZip(_ c: Creature, to target: Surface) -> Bool {
        guard c.isGrounded, let support = supportingSurface(for: c), target.y < c.pos.y - 60 else { return false }
        let contains = target.supports(x: c.pos.x)
        let dir: Double = contains ? (target.maxX - c.pos.x > c.pos.x - target.minX ? 1 : -1) : ((target.minX + target.maxX) / 2 > c.pos.x ? 1 : -1)
        let gap = max(0, max(target.minX - c.pos.x, c.pos.x - target.maxX))
        let landX = (c.pos.x + dir * max(140, gap + 70)).clamped(target.minX + 20, target.maxX - 20)
        guard abs(landX - c.pos.x) >= 80 else { return false }
        nextZipID += 1
        ziplines.append(Zipline(id: nextZipID, top: Vec2(c.pos.x, c.pos.y + Zipline.hang), bottom: Vec2(landX, target.y + Zipline.hang),
                                topOwner: support.ownerID, bottomOwner: target.ownerID, madeAt: clock))
        if ziplines.count > 4 { let gone = ziplines.removeFirst(); expeditionEvents.append(.zipLost(gone.id)) }
        expeditionEvents.append(.zipMade(nextZipID))
        return rideZip(c, nextZipID)
    }

    @discardableResult
    func rideZip(_ c: Creature, _ id: Int) -> Bool {
        guard let z = ziplines.first(where: { $0.id == id }) else { return false }
        endSocial(c)
        c.zip = ZipRide(zipline: id, t: 0)
        c.groundOwner = nil
        c.facing = z.bottom.x > z.top.x ? 1 : -1
        c.pos = z.top - Vec2(0, Zipline.hang)
        c.set(.float, duration: 30)
        expeditionEvents.append(.zipped(by: c.id, zipline: id))
        emit(.tookOff(c.id))
        return true
    }

    func updateZip(_ c: Creature, _ dt: Double) {
        guard var ride = c.zip, let z = ziplines.first(where: { $0.id == ride.zipline }) else {
            c.zip = nil; c.set(.airborne); return
        }
        let span = z.bottom - z.top
        let length = max(1, span.length)
        let speed = min(440, 150 + 560 * ride.t)
        ride.t = min(1, ride.t + speed / length * dt)
        let sag = sin(ride.t * .pi) * 7
        c.pos = z.top + span * ride.t - Vec2(0, Zipline.hang + sag)
        c.vel = span * (speed / length)
        c.zip = ride
        if ride.t >= 1 {
            c.zip = nil
            c.vel = Vec2(c.facing * 50, 90)
            c.set(.airborne)
        }
    }

    /// Someone standing by the top of a line may take it down.
    func zipChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard c.job == nil, c.play == nil, c.expedition == nil, c.isGrounded else { return }
        for z in ziplines where abs(z.top.x - c.pos.x) < 50 && abs(z.top.y - Zipline.hang - c.pos.y) < 4 {
            add("zip", 1.1) { self.rideZip(c, z.id) }
            return
        }
    }

    func validateZips() {
        guard !ziplines.isEmpty else { return }
        var keep: [Zipline] = []
        for z in ziplines {
            let topOK = surfaces.contains { $0.ownerID == z.topOwner && abs($0.y - (z.top.y - Zipline.hang)) < 4 && $0.supports(x: z.top.x) }
            let bottomOK = surfaces.contains { $0.ownerID == z.bottomOwner && abs($0.y - (z.bottom.y - Zipline.hang)) < 4 && $0.supports(x: z.bottom.x) }
            if topOK && bottomOK && clock - z.madeAt < Zipline.lifetime { keep.append(z); continue }
            expeditionEvents.append(.zipLost(z.id))
            for c in creatures where c.zip?.zipline == z.id { c.zip = nil; c.set(.airborne) }
        }
        ziplines = keep
    }

    public func drainExpeditionEvents() -> [ExpeditionEvent] {
        defer { expeditionEvents.removeAll() }
        return expeditionEvents
    }
}
