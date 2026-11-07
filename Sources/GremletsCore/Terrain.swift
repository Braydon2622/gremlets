import Foundation

/// More ways Gremlets reshape the desktop, Terraria style:
///
/// - **Staircases:** a window too high to jump onto, with room beside it? A Gremlet lays wooden blocks in a diagonal
///   from where it stands up to the window's edge, climbing each one as it goes and picking the blocks up again
///   behind it (it only ever carries a few), so the staircase travels up with the climber and is gone once it's on
///   the window. Gremlets step up and down the blocks in stride while they stand.
/// - **Minecarts:** on a wide window a Gremlet lays a stretch of rail along the top edge, a cart rolls up, and it
///   rides back and forth with sparks flying at the ends. The rail stays as long as the window does, and others
///   take turns in the cart.
public struct Stair: Sendable {
    public let id: Int
    /// Ground point at the near edge of the first block, and the direction the stairs climb (+1 = up to the right).
    public let base: Vec2
    public let dir: Double
    public let steps: Int
    public internal(set) var built = 0
    /// The lowest block still standing: the climber takes the ones behind it as it goes up.
    public internal(set) var first = 0
    public let builtAt: Double
    public let climber: Int
    /// Set once the climber is done with it: the remaining blocks get picked up one by one.
    var doneAt: Double?
    var nextTake = 0.0
    let fromOwner: Int, toOwner: Int
    /// One block: 5 art pixels.
    public static let rise = 15.0, run = 15.0
    /// Blocks left standing behind the one the climber is on.
    public static let trail = 2
    public var isComplete: Bool { built >= steps }
    /// Blocks standing right now.
    public var standing: Int { max(0, built - first) }
    /// The top of block `k` (0-based).
    public func step(_ k: Int) -> (y: Double, minX: Double, maxX: Double) {
        let a = base.x + dir * Double(k) * Stair.run, b = base.x + dir * Double(k + 1) * Stair.run
        return (base.y + Double(k + 1) * Stair.rise, min(a, b), max(a, b))
    }
    public var minX: Double { min(base.x, base.x + dir * Double(steps) * Stair.run) }
    public var maxX: Double { max(base.x, base.x + dir * Double(steps) * Stair.run) }
    public var topY: Double { base.y + Double(steps) * Stair.rise }
}

public struct Cart: Sendable {
    public internal(set) var x: Double
    public internal(set) var vel = 0.0
    public internal(set) var dir = 1.0
    /// Lengths of track left to ride before it rolls to a stop (0 = parked or parking).
    public internal(set) var passes = 0
    public static let width = 36.0
    /// The cart's floor above the rail: where a rider's feet are.
    public static let floorHeight = 6.0
    public static let speed = 240.0
}

public struct Rail: Sendable {
    public let id: Int
    public let windowID: Int
    public internal(set) var y: Double, minX: Double, maxX: Double
    /// Laid from the left end (true) or the right.
    public let fromLeft: Bool
    /// 0...1 laid so far.
    public internal(set) var laid = 0.0
    public internal(set) var laidAt: Double
    public internal(set) var cart: Cart
    public static let lifetime = 720.0
    public static let minWindowWidth = 420.0
    public var isComplete: Bool { laid >= 1 }
    public var span: Double { maxX - minX }
    /// The built part.
    public var laidSpan: (Double, Double) {
        let len = span * min(1, laid)
        return fromLeft ? (minX, minX + len) : (maxX - len, maxX)
    }
}

public enum TerrainEvent: Equatable, Sendable {
    case stairBlock(Vec2, stair: Int)
    /// The climber picked a block back up (its centre).
    case stairBlockTaken(Vec2)
    case stairsDone(Int)
    /// The blocks that fell (their centres), for the crumble effect.
    case stairsCrumbled(blocks: [Vec2])
    case railDone(Int)
    case railCrumbled(minX: Double, maxX: Double, y: Double)
    /// Sparks as the cart hits the end of the line.
    case cartBounce(Vec2)
    case boarded(rail: Int, by: Int)
}

extension World {
    static let stairOwnerBase = -465_000
    static let cartOwnerBase = -485_000
    static func stairOwner(_ id: Int) -> Int { stairOwnerBase - id }
    static func cartOwner(_ id: Int) -> Int { cartOwnerBase - id }
    public static func isStairOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= stairOwnerBase && o > stairOwnerBase - 5_000 }
    public static func isCartOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= cartOwnerBase && o > cartOwnerBase - 5_000 }

    var stairSurfaces: [Surface] {
        var out: [Surface] = []
        for s in stairs where s.built > s.first {
            for k in s.first..<s.built {
                let t = s.step(k)
                out.append(Surface(ownerID: World.stairOwner(s.id), kind: .plant, y: t.y, minX: t.minX, maxX: t.maxX))
            }
        }
        return out
    }

    /// Cart floors: moving platforms, so they're added to `allSurfaces` on the fly.
    var cartSurfaces: [Surface] {
        rails.filter { $0.isComplete }.map {
            Surface(ownerID: World.cartOwner($0.id), kind: .plant, y: $0.y + Cart.floorHeight,
                    minX: $0.cart.x - Cart.width / 2 + 4, maxX: $0.cart.x + Cart.width / 2 - 4)
        }
    }

    // MARK: Walking on stairs

    /// A platform to step onto in stride when the ground runs out at `nx`, or a stair block right ahead: another
    /// surface at the same height, or a stair block within one block's height up or down.
    /// How big a step (points) a walker takes in stride when its ground runs out and another platform is right there.
    static let strideStep = 26.0

    func stepAcross(_ c: Creature, from support: Surface, toX nx: Double) -> Surface? {
        // A block straight ahead, entered from its side: up we go.
        if let up = surfaces.first(where: { World.isStairOwner($0.ownerID) && $0.y > c.pos.y + 4 && $0.y <= c.pos.y + Stair.rise + 1.5
                                                && $0.supports(x: nx) && !$0.supports(x: c.pos.x) }) { return up }
        guard !support.supports(x: nx) else { return nil }
        // The ground ran out: the nearest platform within a small step up or down, if one is right there.
        return surfaces.filter { $0.ownerID != support.ownerID && abs($0.y - c.pos.y) <= World.strideStep && $0.supports(x: nx) }
            .min { abs($0.y - c.pos.y) < abs($1.y - c.pos.y) }
    }

    // MARK: Staircases

    public struct StairPlan: Sendable {
        public let from: Surface, to: Surface, dir: Double, base: Vec2, steps: Int
        /// Where the builder stands to lay the first block.
        public var standX: Double { base.x - dir * 24 }
    }

    /// How to build from `s` up to the edge of window top `t`, if there's room (either direction; the one with its
    /// foot nearer `nearX` wins).
    func stairPlan(from s: Surface, to t: Surface, nodes: [Surface]? = nil, nearX: Double? = nil) -> StairPlan? {
        guard t.kind == .windowTop, t.ownerID != s.ownerID, t.width >= 120, s.kind == .floor || s.kind == .windowTop else { return nil }
        let dy = t.y - s.y
        guard dy >= 90, dy <= 480 else { return nil }
        let steps = Int(dy / Stair.rise)
        let runW = Double(steps) * Stair.run
        var plans: [StairPlan] = []
        for dir in [1.0, -1.0] {
            let topEdge = dir > 0 ? t.minX : t.maxX
            let baseX = topEdge - dir * runW
            let standX = baseX - dir * 24
            guard s.supports(x: baseX), s.supports(x: standX), s.supports(x: standX - dir * 20) else { continue }
            let lo = min(baseX, topEdge), hi = max(baseX, topEdge)
            // Nothing in the way: no other window edge crossing the stairs, no stairs already there.
            if builtSurfaces.contains(where: { $0.ownerID != t.ownerID && $0.ownerID != s.ownerID && $0.y > s.y + 10 && $0.y < t.y + 40 && $0.maxX > lo - 10 && $0.minX < hi + 10 }) { continue }
            if stairs.contains(where: { $0.maxX > lo - 80 && $0.minX < hi + 80 }) { continue }
            if let scr = screen(containingX: baseX, y: s.y), lo < scr.minX + 10 || hi > scr.maxX - 10 { continue }
            plans.append(StairPlan(from: s, to: t, dir: dir, base: Vec2(baseX, s.y), steps: steps))
        }
        guard let x = nearX else { return plans.first }
        return plans.min { abs($0.standX - x) < abs($1.standX - x) }
    }

    /// A window above, too high to jump onto, with room to build up to its edge from where this creature stands.
    func stairCandidate(for c: Creature) -> StairPlan? {
        guard clock >= nextStairAt, stairs.count < 2, c.job == nil, c.play == nil, c.groveTask == nil, c.isGrounded,
              let s = supportingSurface(for: c), s.kind == .floor || s.kind == .windowTop else { return nil }
        let plans = builtSurfaces.compactMap { t in stairPlan(from: s, to: t, nearX: c.pos.x) }.filter { abs($0.standX - c.pos.x) < 560 }
        return plans.min { abs($0.standX - c.pos.x) < abs($1.standX - c.pos.x) }
    }

    func startStairs(_ c: Creature, _ plan: StairPlan) {
        if c.stair != nil { abandonStairs(c) }
        nextStairID += 1
        stairs.append(Stair(id: nextStairID, base: plan.base, dir: plan.dir, steps: plan.steps, builtAt: clock, climber: c.id, fromOwner: plan.from.ownerID, toOwner: plan.to.ownerID))
        endSocial(c)
        c.stair = nextStairID
        c.blocksInHand = 3
        c.targetX = plan.standX
        c.facing = plan.standX > c.pos.x ? 1 : -1
        c.set(.walk, duration: 40)
        nextStairAt = clock + rng.range(240, 600)
    }

    /// `gremlet stairs`: whoever has a window to climb to builds a staircase now.
    @discardableResult
    public func startStairsWithAnyone() -> Bool {
        nextStairAt = 0
        for c in creatures.shuffled(using: &rng) where c.job == nil && c.isGrounded {
            if let plan = stairCandidate(for: c) { startStairs(c, plan); return true }
        }
        return false
    }

    /// Builder update: get to the foot of the next block, lay it, climb it, repeat. Returns true if it handled this tick.
    func updateStairBuilding(_ c: Creature, _ dt: Double, on support: Surface) -> Bool {
        guard let id = c.stair, let i = stairs.firstIndex(where: { $0.id == id }) else { c.stair = nil; c.targetX = nil; return false }
        var st = stairs[i]
        if st.isComplete {
            c.stair = nil; c.targetX = nil
            st.doneAt = clock; st.nextTake = clock + 0.5
            stairs[i] = st
            terrainEvents.append(.stairsDone(st.id))
            // On up the last blocks and onto the window; the blocks come up behind it.
            c.facing = st.dir
            c.edgeDecisionMade = true
            c.set(.walk, duration: Double(Stair.trail + 2) * Stair.run / c.species.walkSpeed + 1.5)
            return true
        }
        let k = st.built
        let standY = st.base.y + Double(k) * Stair.rise
        let standX = st.base.x + st.dir * Double(k) * Stair.run - st.dir * 9
        if abs(c.pos.x - standX) > 5 || abs(c.pos.y - standY) > 2 {
            // Walk there; the blocks already laid carry it up. Lost (fell off, or walled in)? Pick up and give up.
            if c.pos.y > standY + 2 || c.pos.y < st.base.y - 2 || c.pos.x < st.minX - 400 || c.pos.x > st.maxX + 400 {
                abandonStairs(c)
                return false
            }
            c.facing = standX > c.pos.x ? 1 : -1
            if c.activity != .walk { c.set(.walk, duration: 30) }
            if !move(c, dt, speed: c.species.walkSpeed, on: support, ledgeTurnChance: 0) { abandonStairs(c) }
            return true
        }
        // Standing on block k-1: the blocks more than a trail behind come up into its hands.
        let keepFrom = max(0, k - 1 - Stair.trail)
        if st.first < keepFrom {
            while st.first < keepFrom {
                let t = st.step(st.first)
                terrainEvents.append(.stairBlockTaken(Vec2((t.minX + t.maxX) / 2, t.y - Stair.rise / 2)))
                st.first += 1
            }
            stairs[i] = st
            setSurfacesDirty()
        }
        c.facing = st.dir
        c.buildTimer -= dt
        if c.buildTimer <= 0 {
            c.buildTimer = 0.42
            st.built += 1
            stairs[i] = st
            setSurfacesDirty()
            let top = st.step(k)
            terrainEvents.append(.stairBlock(Vec2((top.minX + top.maxX) / 2, top.y), stair: st.id))
            c.set(.special, duration: min(0.32, c.animationLength(for: .special)))
        } else if c.activity != .special {
            c.set(.idle, duration: 1)
        }
        return true
    }

    /// The climber stops: whatever is standing gets picked up over the next moments.
    func abandonStairs(_ c: Creature) {
        guard let id = c.stair else { return }
        c.stair = nil; c.targetX = nil
        if let i = stairs.firstIndex(where: { $0.id == id }) {
            if stairs[i].standing == 0 { stairs.remove(at: i); c.blocksInHand = 0 }
            else { stairs[i].doneAt = clock; stairs[i].nextTake = clock + 0.3 }
        } else {
            c.blocksInHand = 0
        }
    }

    /// Finished (or abandoned) staircases come up block by block, from the bottom, once the climber is off them.
    func updateStairs(_ dt: Double) {
        guard !stairs.isEmpty else { return }
        var changed = false
        var i = 0
        while i < stairs.count {
            var s = stairs[i]
            if let done = s.doneAt, clock >= s.nextTake {
                let climber = creature(id: s.climber)
                let off = climber.map { $0.groundOwner != World.stairOwner(s.id) } ?? true
                if off || clock - done > 4 {
                    s.nextTake = clock + 0.12
                    if s.first < s.built {
                        let t = s.step(s.first)
                        terrainEvents.append(.stairBlockTaken(Vec2((t.minX + t.maxX) / 2, t.y - Stair.rise / 2)))
                        s.first += 1
                        changed = true
                    }
                    if s.first >= s.built {
                        climber?.blocksInHand = 0
                        stairs.remove(at: i)
                        continue
                    }
                }
            }
            stairs[i] = s
            i += 1
        }
        if changed { setSurfacesDirty() }
    }

    /// After the windows change: stairs whose window moved away come down.
    func validateStairs() {
        guard !stairs.isEmpty else { return }
        var keep: [Stair] = []
        for s in stairs {
            let topEdgeX = s.base.x + s.dir * Double(s.steps) * Stair.run
            let toOK = builtSurfaces.contains { $0.ownerID == s.toOwner && $0.kind == .windowTop && abs($0.y - s.topY) < Stair.rise + 2
                && abs((s.dir > 0 ? $0.minX : $0.maxX) - topEdgeX) < 14 }
            let fromOK = builtSurfaces.contains { $0.ownerID == s.fromOwner && abs($0.y - s.base.y) < 2 && $0.supports(x: s.base.x) }
            if (toOK && fromOK) || s.doneAt != nil { keep.append(s); continue }
            if s.standing > 0 { terrainEvents.append(.stairsCrumbled(blocks: (s.first..<s.built).map { let t = s.step($0); return Vec2((t.minX + t.maxX) / 2, t.y - Stair.rise / 2) })) }
            for c in creatures where c.stair == s.id { c.stair = nil; c.targetX = nil; c.blocksInHand = 0 }
        }
        if keep.count != stairs.count { stairs = keep; setSurfacesDirty() }
    }

    // MARK: Rails and carts

    /// The wide window top this creature stands on, if it has no rail yet.
    func railCandidate(for c: Creature) -> Surface? {
        guard clock >= nextRailAt, rails.count < 2, c.job == nil, c.play == nil, c.groveTask == nil, c.isGrounded,
              let s = supportingSurface(for: c), s.kind == .windowTop, s.ownerID >= 0, s.width >= Rail.minWindowWidth,
              !rails.contains(where: { $0.windowID == s.ownerID }) else { return nil }
        return s
    }

    func startRail(_ c: Creature, on s: Surface) {
        nextRailID += 1
        let fromLeft = c.pos.x - s.minX < s.maxX - c.pos.x
        let minX = s.minX + 8, maxX = s.maxX - 8
        let cart = Cart(x: fromLeft ? maxX - Cart.width / 2 : minX + Cart.width / 2)
        rails.append(Rail(id: nextRailID, windowID: s.ownerID, y: s.y, minX: minX, maxX: maxX, fromLeft: fromLeft, laidAt: clock, cart: cart))
        endSocial(c)
        c.rail = nextRailID
        c.targetX = fromLeft ? minX + 4 : maxX - 4
        c.facing = c.targetX! > c.pos.x ? 1 : -1
        c.set(.walk, duration: 40)
        nextRailAt = clock + rng.range(420, 900)
    }

    /// `gremlet cart`: a Gremlet on a wide window lays a rail now (one on the floor climbs up first if it can).
    @discardableResult
    public func startRailWithAnyone() -> Bool {
        nextRailAt = 0
        for c in creatures.shuffled(using: &rng) where c.job == nil && c.isGrounded {
            if let s = railCandidate(for: c) { startRail(c, on: s); return true }
        }
        // Nobody up there: send the nearest free Gremlet to the widest window top; it lays the rail on arrival.
        let railed = Set(rails.map(\.windowID))
        let wide = builtSurfaces.filter { s in s.kind == .windowTop && s.ownerID >= 0 && s.width >= Rail.minWindowWidth && !railed.contains(s.ownerID) }
        guard let s = wide.max(by: { $0.width < $1.width }) else { return false }
        let mid = s.minX + s.width / 2
        let free = creatures.filter { $0.job == nil && $0.isGrounded }
        guard let c = free.min(by: { abs($0.pos.x - mid) < abs($1.pos.x - mid) }) else { return false }
        startGrapple(c, to: Vec2(c.pos.x.clamped(s.minX + 40, s.maxX - 40), s.y))
        return true
    }

    /// Layer update: walk to the near end, then along the window laying track; when it's all down the cart rolls up
    /// and the layer hops in for a ride.
    func updateRailLaying(_ c: Creature, _ dt: Double, on support: Surface) -> Bool {
        guard let id = c.rail, let i = rails.firstIndex(where: { $0.id == id }) else { c.rail = nil; c.targetX = nil; return false }
        var r = rails[i]
        guard support.ownerID == r.windowID || World.isCartOwner(support.ownerID) else {
            // Fell off (or the window moved): what's laid stays, the job is dropped.
            c.rail = nil; c.targetX = nil
            if r.laid <= 0 { rails.remove(at: i) }
            return false
        }
        if r.isComplete {
            c.rail = nil; c.targetX = nil
            terrainEvents.append(.railDone(r.id))
            board(c, rail: i, passes: 3)
            return true
        }
        let startX = r.fromLeft ? r.minX + 4 : r.maxX - 4
        if r.laid <= 0, abs(c.pos.x - startX) > 6 {
            c.facing = startX > c.pos.x ? 1 : -1
            if c.activity != .walk { c.set(.walk, duration: 30) }
            if !move(c, dt, speed: c.species.walkSpeed, on: support, ledgeTurnChance: 0) { c.rail = nil; c.targetX = nil; rails.remove(at: i) }
            return true
        }
        // Laying: a steady walk along the edge, track appearing behind it.
        let dir: Double = r.fromLeft ? 1 : -1
        c.facing = dir
        c.workPose = "crouch"
        if c.activity != .work { c.set(.work, duration: 60) }
        c.pos.x += dir * c.species.walkSpeed * 0.55 * dt
        let covered = r.fromLeft ? c.pos.x - r.minX : r.maxX - c.pos.x
        r.laid = max(r.laid, min(1, (covered + 6) / r.span))
        if (r.fromLeft && c.pos.x >= r.maxX - 4) || (!r.fromLeft && c.pos.x <= r.minX + 4) {
            c.pos.x = r.fromLeft ? r.maxX - 4 : r.minX + 4
            r.laid = 1
        }
        rails[i] = r
        return true
    }

    /// Hops into the cart (a little jump) and sets it rolling.
    func board(_ c: Creature, rail i: Int, passes: Int) {
        let r = rails[i]
        rails[i].cart.passes = max(rails[i].cart.passes, passes)
        rails[i].cart.dir = r.cart.x > (r.minX + r.maxX) / 2 ? -1 : 1
        terrainEvents.append(.boarded(rail: r.id, by: c.id))
        launch(c, velocity: ballistic(from: c.pos, toX: r.cart.x, y: r.y + Cart.floorHeight, apexExtra: 36))
    }

    /// Carts roll, bounce at the ends and carry their riders; old rails come down.
    func updateRails(_ dt: Double) {
        guard !rails.isEmpty else { return }
        var crumbled: [Int] = []
        for i in rails.indices {
            var r = rails[i]
            if r.isComplete && clock - r.laidAt > Rail.lifetime && !creatures.contains(where: { $0.groundOwner == World.cartOwner(r.id) }) { crumbled.append(i); continue }
            guard r.isComplete else { continue }
            var cart = r.cart
            let before = cart.x
            let riders = creatures.filter { $0.groundOwner == World.cartOwner(r.id) }
            if cart.passes > 0 && !riders.isEmpty {
                let target = cart.dir * Cart.speed
                cart.vel += (target - cart.vel).clamped(-520 * dt, 520 * dt)
            } else {
                // Rolling to a stop.
                let brake = 300 * dt
                cart.vel = abs(cart.vel) <= brake ? 0 : cart.vel - brake * (cart.vel > 0 ? 1 : -1)
                if cart.passes > 0 && riders.isEmpty && abs(cart.vel) < 1 { cart.passes = 0 }
            }
            cart.x += cart.vel * dt
            let lo = r.minX + Cart.width / 2, hi = r.maxX - Cart.width / 2
            if cart.x <= lo || cart.x >= hi {
                cart.x = cart.x.clamped(lo, hi)
                if abs(cart.vel) > 40 { terrainEvents.append(.cartBounce(Vec2(cart.x + (cart.x <= lo ? -Cart.width / 2 : Cart.width / 2), r.y))) }
                cart.dir = cart.x <= lo ? 1 : -1
                cart.vel = -cart.vel * 0.25
                if cart.passes > 0 { cart.passes -= 1 }
            }
            r.cart = cart
            rails[i] = r
            let dx = cart.x - before
            for c in riders {
                c.pos.x += dx
                if abs(cart.vel) > 20 { c.facing = cart.vel > 0 ? 1 : -1 }
            }
        }
        for i in crumbled.reversed() {
            let r = rails[i]
            terrainEvents.append(.railCrumbled(minX: r.minX, maxX: r.maxX, y: r.y))
            for c in creatures where c.rail == r.id { c.rail = nil; c.targetX = nil }
            rails.remove(at: i)
        }
    }

    /// After the windows change: a rail follows its window, and comes down if the window went away or got narrow.
    func validateRails() {
        guard !rails.isEmpty else { return }
        var keep: [Rail] = []
        for var r in rails {
            guard let top = builtSurfaces.filter({ $0.ownerID == r.windowID && $0.kind == .windowTop }).max(by: { $0.width < $1.width }),
                  top.width >= Rail.minWindowWidth * 0.7 else {
                terrainEvents.append(.railCrumbled(minX: r.minX, maxX: r.maxX, y: r.y))
                for c in creatures where c.rail == r.id { c.rail = nil; c.targetX = nil }
                continue
            }
            let newMinX = top.minX + 8, newMaxX = top.maxX - 8
            let dx = (r.fromLeft ? newMinX - r.minX : newMaxX - r.maxX), dy = top.y - r.y
            if dx != 0 || dy != 0 {
                r.cart.x = (r.cart.x + dx).clamped(newMinX + Cart.width / 2, newMaxX - Cart.width / 2)
                for c in creatures where c.groundOwner == World.cartOwner(r.id) { c.pos += Vec2(dx, dy) }
            }
            r.minX = newMinX; r.maxX = newMaxX; r.y = top.y
            keep.append(r)
        }
        rails = keep
    }

    /// Riding: stay in the cart while it rolls, hop out when it's parked (or send it off again); anyone on the window
    /// near a parked cart may climb in.
    func cartChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        if World.isCartOwner(c.groundOwner), let i = rails.firstIndex(where: { World.cartOwner($0.id) == c.groundOwner }) {
            let r = rails[i]
            if r.cart.passes > 0 || abs(r.cart.vel) > 10 {
                add("ride", 4) { c.idleVariant = "look"; c.set(.idle, duration: self.rng.range(1, 2)) }
            } else {
                add("hopOut", 2) {
                    let side: Double = r.cart.x - r.minX < r.maxX - r.cart.x ? 1 : -1
                    self.launch(c, velocity: Vec2(side * 110, 330))
                }
                add("rideAgain", 0.5) { self.rails[i].cart.passes = 2; self.rails[i].cart.dir = r.cart.x > (r.minX + r.maxX) / 2 ? -1 : 1 }
            }
            return
        }
        guard c.job == nil, c.play == nil, c.isGrounded, let s = supportingSurface(for: c), s.kind == .windowTop,
              let i = rails.firstIndex(where: { $0.windowID == s.ownerID && $0.isComplete && $0.cart.passes == 0 && abs($0.cart.vel) < 5 }) else { return }
        let r = rails[i]
        guard abs(r.cart.x - c.pos.x) < 320, !creatures.contains(where: { $0.groundOwner == World.cartOwner(r.id) }) else { return }
        add("board", 1.4) { self.board(c, rail: i, passes: 2 + Int(self.rng.next() % 2)) }
    }

    public func drainTerrainEvents() -> [TerrainEvent] {
        defer { terrainEvents.removeAll() }
        return terrainEvents
    }
}
