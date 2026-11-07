/// Gremlets change the world around them, Terraria style:
///
/// - **Bridges:** a Gremlet standing at the end of a window sees another window across a gap at about the same height,
///   walks to the edge and builds a plank bridge across it, one block at a time. Everyone can use it afterwards.
///   If either window moves away, the bridge crumbles.
/// - **Grappling hook:** to reach a window too high to jump to, a Gremlet throws a hook and zips up on the rope.
/// - **The village:** when a Claude session ends, the building its Gremlet put up (one block per edit) moves down to
///   the bottom of the screen and stays. Over time your desktop becomes a little town made of your Claude work, and
///   its roofs are more places to stand.
public struct Bridge: Sendable {
    public let id: Int
    public let y: Double
    /// The full span across the gap.
    public let minX: Double, maxX: Double
    /// Built from the left (true) or the right.
    public let fromLeft: Bool
    let leftOwner: Int, rightOwner: Int
    /// How many blocks are down so far.
    public internal(set) var blocks = 0
    public var totalBlocks: Int { max(1, Int(((maxX - minX) / Bridge.blockWidth).rounded(.up))) }
    public var isComplete: Bool { blocks >= totalBlocks }
    public static let blockWidth = 15.0
    /// The built part.
    public var builtSpan: (Double, Double) {
        let len = min(maxX - minX, Double(blocks) * Bridge.blockWidth)
        return fromLeft ? (minX, minX + len) : (maxX - len, maxX)
    }
}

/// A finished Claude building in the village.
public struct House: Codable, Equatable, Sendable {
    public var biome: String
    public var blocks: Int
    /// Position on the main screen's floor (0...1).
    public var x: Double
    /// Drawn size in points.
    public var w: Double, h: Double
    public var project: String?
    /// When it was built (e.g. "Nov 6"), and how many files Claude edited.
    public var day: String?
}

public enum BuildEvent: Equatable, Sendable {
    case bridgeBlock(Vec2, bridge: Int)
    case bridgeDone(Int)
    case bridgeCrumbled(minX: Double, maxX: Double, y: Double)
    case grapple(Int)
    case houseAdded(Int)
}

extension World {
    static let bridgeOwnerBase = -470_000
    static func isBridgeOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= bridgeOwnerBase && o > bridgeOwnerBase - 10_000 }

    var bridgeSurfaces: [Surface] {
        bridges.compactMap { b in
            guard b.blocks > 0 else { return nil }
            let (lo, hi) = b.builtSpan
            return Surface(ownerID: World.bridgeOwnerBase - b.id, kind: .plant, y: b.y, minX: lo, maxX: hi)
        }
    }

    // MARK: Bridges

    /// A gap worth bridging that starts at the end of the window this creature stands on.
    func bridgeCandidate(for c: Creature) -> (from: Surface, to: Surface, fromLeft: Bool)? {
        guard let s = supportingSurface(for: c), s.kind == .windowTop || s.kind == .windowLedge, bridges.count < 4 else { return nil }
        let tops = builtSurfaces.filter { ($0.kind == .windowTop || $0.kind == .windowLedge) && $0.ownerID != s.ownerID && abs($0.y - s.y) < 26 }
        // Gap to the right of this surface, or to the left.
        if let r = tops.filter({ $0.minX - s.maxX > 50 && $0.minX - s.maxX < 340 }).min(by: { $0.minX < $1.minX }),
           !bridges.contains(where: { abs($0.y - s.y) < 30 && $0.minX < r.minX && $0.maxX > s.maxX }) {
            return (s, r, true)
        }
        if let l = tops.filter({ s.minX - $0.maxX > 50 && s.minX - $0.maxX < 340 }).max(by: { $0.maxX < $1.maxX }),
           !bridges.contains(where: { abs($0.y - s.y) < 30 && $0.minX < s.minX && $0.maxX > l.maxX }) {
            return (s, l, false)
        }
        return nil
    }

    func startBridge(_ c: Creature) {
        guard let (from, to, fromLeft) = bridgeCandidate(for: c) else { return }
        nextBridgeID += 1
        let b = Bridge(id: nextBridgeID, y: from.y, minX: fromLeft ? from.maxX : to.maxX, maxX: fromLeft ? to.minX : from.minX,
                       fromLeft: fromLeft, leftOwner: fromLeft ? from.ownerID : to.ownerID, rightOwner: fromLeft ? to.ownerID : from.ownerID)
        bridges.append(b)
        c.building = b.id
        c.targetX = fromLeft ? from.maxX - 10 : from.minX + 10
        c.set(.walk, duration: 20)
    }

    /// Builder update: walk to the edge, then lay a block every so often. Returns true if it handled this tick.
    func updateBuilding(_ c: Creature, _ dt: Double, on support: Surface) -> Bool {
        guard let id = c.building, let i = bridges.firstIndex(where: { $0.id == id }) else { c.building = nil; return false }
        var b = bridges[i]
        if b.isComplete {
            c.building = nil; c.targetX = nil
            buildEvents.append(.bridgeDone(b.id))
            // Proudly walk across.
            c.facing = b.fromLeft ? 1 : -1
            c.set(.walk, duration: (b.maxX - b.minX) / c.species.walkSpeed + 1.5)
            return true
        }
        // The edge we build from is the end of what's built so far.
        let (lo, hi) = b.builtSpan
        let edge = b.blocks == 0 ? (b.fromLeft ? b.minX - 8 : b.maxX + 8) : (b.fromLeft ? hi - 6 : lo + 6)
        if abs(c.pos.x - edge) > 6 {
            c.facing = edge > c.pos.x ? 1 : -1
            if c.activity != .walk { c.set(.walk, duration: 20) }
            // Walk along the window and out onto the planks already laid (they're all at the same height).
            let nx = c.pos.x + c.facing * c.species.walkSpeed * dt
            let deck = bridgeSurfaces.first { World.bridgeOwnerBase - $0.ownerID == b.id && $0.supports(x: nx) }
            if support.supports(x: nx) || deck != nil {
                c.pos.x = nx
                if let d = deck, !support.supports(x: nx) { c.groundOwner = d.ownerID; c.pos.y = d.y }
            } else {
                // Can't get there (the window moved): give up and let the bridge crumble.
                c.building = nil
                if b.blocks == 0 { bridges.remove(at: i) }
            }
            return true
        }
        c.facing = b.fromLeft ? 1 : -1
        c.buildTimer -= dt
        if c.buildTimer <= 0 {
            c.buildTimer = 0.38
            b.blocks += 1
            bridges[i] = b
            setSurfacesDirty()
            let (l2, h2) = b.builtSpan
            buildEvents.append(.bridgeBlock(Vec2(b.fromLeft ? h2 - Bridge.blockWidth / 2 : l2 + Bridge.blockWidth / 2, b.y), bridge: b.id))
            c.set(.special, duration: min(0.32, c.animationLength(for: .special)))
        } else if c.activity != .special {
            c.set(.idle, duration: 1)
        }
        return true
    }

    /// After the windows change: bridges whose ends no longer line up crumble (anyone on them falls).
    func validateBridges() {
        guard !bridges.isEmpty else { return }
        var keep: [Bridge] = []
        for b in bridges {
            let leftOK = builtSurfaces.contains { $0.ownerID == b.leftOwner && abs($0.maxX - b.minX) < 14 && abs($0.y - b.y) < 30 }
            let rightOK = builtSurfaces.contains { $0.ownerID == b.rightOwner && abs($0.minX - b.maxX) < 14 && abs($0.y - b.y) < 30 }
            if leftOK && rightOK { keep.append(b); continue }
            if b.blocks > 0 { let (lo, hi) = b.builtSpan; buildEvents.append(.bridgeCrumbled(minX: lo, maxX: hi, y: b.y)) }
            for c in creatures where c.building == b.id { c.building = nil; c.targetX = nil }
        }
        bridges = keep
    }

    // MARK: Grappling hook

    /// A window top too high to jump to, but close enough to hook.
    func grappleTarget(for c: Creature) -> Vec2? {
        guard c.isGrounded, c.job == nil else { return nil }
        let options = surfaces.filter { s in
            let dy = s.y - c.pos.y
            let cx = s.minX + s.width / 2
            return dy > maxJumpHeight * 0.85 && dy < 620 && abs(cx - c.pos.x) < 520 && s.width > 60
                && (s.kind == .windowTop || s.kind == .plant || s.kind == .windowLedge)
        }
        guard !options.isEmpty else { return nil }
        let s = options[Int(rng.next() % UInt64(options.count))]
        let x = (c.pos.x).clamped(s.minX + 24, s.maxX - 24)
        return Vec2(x, s.y)
    }

    func startGrapple(_ c: Creature, to anchor: Vec2) {
        c.grapple = anchor
        c.grappleTime = 0
        c.groundOwner = nil
        c.facing = anchor.x > c.pos.x ? 1 : -1
        c.vel = Vec2(0, 300)
        c.set(.airborne, duration: 5)
        buildEvents.append(.grapple(c.id))
    }

    /// Reel in: pulled toward the hook, then a little hop over the edge to land on top.
    func updateGrapple(_ c: Creature, _ dt: Double) -> Bool {
        guard let a = c.grapple else { return false }
        c.grappleTime += dt
        let target = a + Vec2(0, 26)
        let d = target - c.pos
        if d.length < 22 || c.grappleTime > 2.5 {
            c.grapple = nil
            c.vel = Vec2(c.facing * 90, 360)
            return false
        }
        let speed = min(1100, 300 + c.grappleTime * 1400)
        c.vel = d * (speed / d.length)
        c.pos += c.vel * dt
        return true
    }

    // MARK: Village

    /// A Claude building moves to the village. Finds a free spot along the bottom of the main screen, away from the
    /// grove plants and the other houses; the oldest house makes way when there's no room.
    @discardableResult
    public func addHouse(biome: String, blocks: Int, size: Vec2, project: String?, day: String? = nil) -> Int? {
        guard let f = groveFloor, blocks > 0 else { return nil }
        func free(_ x: Double) -> Bool {
            let px = f.minX + x * f.w
            for i in grove.plants.indices {
                let b = grove.base(i, floor: f), sz = grove.size(i)
                if abs(px - b.x) < sz.x / 2 + size.x / 2 + 16 { return false }
            }
            for h in grove.village where abs(px - (f.minX + h.x * f.w)) < (h.w + size.x) / 2 + 20 { return false }
            return true
        }
        // Spots from the edges inward, so the village grows out from both sides.
        var spots: [Double] = []
        for k in 0..<40 { let u = 0.03 + Double(k / 2) * 0.024; spots.append(k % 2 == 0 ? u : 1 - u) }
        if grove.village.count >= Grove.maxHouses { grove.village.removeFirst() }
        guard let x = spots.first(where: free) else { return nil }
        grove.village.append(House(biome: biome, blocks: blocks, x: x, w: size.x, h: size.y, project: project, day: day))
        for o in creatures where o.homeHouse != nil { o.homeUntil = clock }   // house numbers may shift: everyone wakes
        rebuildGroveSurfaces(); setSurfacesDirty()
        groveEvents.append(.houseAdded(grove.village.count - 1))
        return grove.village.count - 1
    }

    public func drainBuildEvents() -> [BuildEvent] {
        defer { buildEvents.removeAll() }
        return buildEvents
    }
}
