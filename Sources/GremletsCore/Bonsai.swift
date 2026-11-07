import Foundation

/// Every project you work on with Claude grows a bonsai.
///
/// The tree is rooted on that project's terminal window while a Claude session is running there, and rests on a
/// bracket shelf up the side of the screen (the nursery) in between. It is grown entirely from the work:
///
/// | Claude | The tree |
/// |---|---|
/// | a new session | a new branch (up to seven; after that the tree thickens instead) |
/// | a file edit | a leaf: the foliage pad on that session's branch fills out |
/// | a finished task | a flower on that pad |
/// | tests pass | a golden fruit |
/// | time | the trunk thickens, moss gathers on the pot, lichen on old bark |
///
/// The species and the style (upright, informal, windswept, cascade) come from the project's name, so the same
/// project always grows the same kind of tree, and it changes with the seasons: maples turn red in autumn, cherries
/// blossom in spring, the deciduous ones stand bare under snow in winter.
public enum BonsaiSpecies: String, CaseIterable, Codable, Sendable {
    case pine, maple, cherry, juniper, wisteria, olive

    public var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// Loses its leaves in winter.
    public var deciduous: Bool { [.maple, .cherry, .wisteria].contains(self) }
}

public enum BonsaiForm: String, CaseIterable, Codable, Sendable {
    case upright, informal, windswept, cascade

    public var name: String {
        switch self {
        case .upright: return "formal upright"
        case .informal: return "informal upright"
        case .windswept: return "windswept"
        case .cascade: return "cascade"
        }
    }
}

public struct BonsaiBranch: Codable, Equatable, Sendable {
    /// Which side of the trunk it grows out of (+1 right, -1 left).
    public var side: Double
    public var edits = 0
    public var blooms = 0
    public var fruit = 0
    public init(side: Double) { self.side = side }
}

public struct Bonsai: Codable, Equatable, Sendable {
    public var project: String
    public var seed: UInt64
    public var species: BonsaiSpecies
    public var form: BonsaiForm
    /// Pot style (0...3).
    public var pot: Int
    public var branches: [BonsaiBranch] = []
    public var sessions = 0
    public var minutes = 0.0
    /// Seconds since 1970.
    public var firstSeen: Double
    public var lastSeen: Double
    /// The Claude session growing it right now, and which branch that session is on.
    public var currentSession: String?
    public var currentBranch: Int?

    public static let maxBranches = 12

    enum CodingKeys: String, CodingKey { case project, seed, species, form, pot, branches, sessions, minutes, firstSeen, lastSeen, currentSession, currentBranch, milestones }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        project = try c.decode(String.self, forKey: .project)
        seed = try c.decode(UInt64.self, forKey: .seed)
        species = try c.decode(BonsaiSpecies.self, forKey: .species)
        form = try c.decode(BonsaiForm.self, forKey: .form)
        pot = try c.decode(Int.self, forKey: .pot)
        branches = try c.decodeIfPresent([BonsaiBranch].self, forKey: .branches) ?? []
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        minutes = try c.decodeIfPresent(Double.self, forKey: .minutes) ?? 0
        firstSeen = try c.decodeIfPresent(Double.self, forKey: .firstSeen) ?? 0
        lastSeen = try c.decodeIfPresent(Double.self, forKey: .lastSeen) ?? 0
        currentSession = try c.decodeIfPresent(String.self, forKey: .currentSession)
        currentBranch = try c.decodeIfPresent(Int.self, forKey: .currentBranch)
        milestones = try c.decodeIfPresent([String].self, forKey: .milestones) ?? []
    }

    public init(project: String, now: Double) {
        self.project = project
        seed = Bonsai.hash(project)
        species = BonsaiSpecies.allCases[Int(seed % UInt64(BonsaiSpecies.allCases.count))]
        form = BonsaiForm.allCases[Int((seed >> 8) % UInt64(BonsaiForm.allCases.count))]
        pot = Int((seed >> 16) % 4)
        firstSeen = now
        lastSeen = now
    }

    /// FNV-1a, so the same project name always grows the same tree.
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }

    /// Milestones reached so far (ribbons on the pot): "edits-100", "sessions-10", ...
    public var milestones: [String] = []
    public var edits: Int { branches.reduce(0) { $0 + $1.edits } }
    public var blooms: Int { branches.reduce(0) { $0 + $1.blooms } }
    public var fruit: Int { branches.reduce(0) { $0 + $1.fruit } }
    /// 0 (a seedling) ... 1 (a venerable tree, around 400 edits and a dozen sessions).
    public var stature: Double { min(1, 0.75 * log2(1 + Double(edits)) / 8.6 + 0.25 * Double(min(sessions, 12)) / 12) }
    public func ageDays(now: Double) -> Double { max(0, now - firstSeen) / 86400 }

    /// A Claude session starts (or sends another prompt). A new session sprouts a branch; the same one carries on.
    /// Returns true when a branch sprouted.
    public mutating func startSession(_ key: String, now: Double) -> Bool {
        lastSeen = now
        if currentSession == key, let b = currentBranch, b < branches.count { return false }
        currentSession = key
        sessions += 1
        if branches.count < Bonsai.maxBranches {
            let side: Double
            switch form {
            case .windswept: side = (seed >> 24) % 2 == 0 ? 1 : -1
            default: side = branches.count % 2 == 0 ? 1 : -1
            }
            branches.append(BonsaiBranch(side: side))
            currentBranch = branches.count - 1
            return true
        }
        // Full: the thinnest branch takes the new growth, and the tree gets denser.
        currentBranch = branches.indices.min { branches[$0].edits < branches[$1].edits }
        return false
    }

    public mutating func endSession() { currentSession = nil }

    /// Where new growth goes (the current branch, or the thinnest one).
    var growthBranch: Int? {
        if let b = currentBranch, b < branches.count { return b }
        return branches.indices.min { branches[$0].edits < branches[$1].edits }
    }
}

/// Everyone's trees, kept between launches.
public struct BonsaiBook: Codable, Sendable {
    public var trees: [Bonsai] = []
    public init() {}
    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ d: Data) -> BonsaiBook? { try? JSONDecoder().decode(BonsaiBook.self, from: d) }
    public subscript(project: String) -> Bonsai? { trees.first { $0.project == project } }
    public func index(of project: String) -> Int? { trees.firstIndex { $0.project == project } }
}

// MARK: - Shape

/// The tree's shape, in points, with the origin at the middle of the pot's top (soil level), y up. Deterministic
/// from the record, so the same work always grows the same tree, and it only ever adds to what was there.
public struct BonsaiLayout: Sendable {
    public struct Pad: Sendable {
        public var center: Vec2
        public var rx: Double
        public var ry: Double
        /// -1 for the crown, otherwise the branch it belongs to.
        public var branch: Int
        public var blooms: [Vec2]
        public var fruit: [Vec2]
    }
    public var trunk: [Vec2]
    /// Limbs and twigs: polylines from the trunk (or a limb) out to a pad, with the thickness at their root.
    public var limbs: [(points: [Vec2], thickness: Double)]
    /// Surface roots spreading over the soil.
    public var roots: [[Vec2]]
    public var pads: [Pad]
    public var potWidth: Double
    public var potHeight: Double
    /// Trunk thickness at the base, in points.
    public var thickness: Double
    /// Everything, pot included (y from -potHeight).
    public var bounds: Rect
}

public enum BonsaiGeometry {
    /// A classic bonsai silhouette: a tapering trunk with movement, the lowest branches longest and each one shorter
    /// up the tree, pads of foliage at the end of every limb and twig, a crown on top and surface roots at the base.
    /// A seedling is a short stem with one tuft; a tree with hundreds of edits sprawls three hundred points wide.
    public static func layout(_ b: Bonsai) -> BonsaiLayout {
        var rng = SplitMix64(seed: b.seed &+ 1)
        let s = b.stature
        let H = 48 + 160 * s
        let W = 70 + 250 * s
        let windDir: Double = (b.seed >> 24) % 2 == 0 ? 1 : -1
        let phase = rng.range(0, 6.28)
        let wiggle = (0..<10).map { _ in rng.range(-1, 1) }

        // Trunk.
        var trunk: [Vec2] = [.zero]
        let n = 8
        for k in 1...n {
            let t = Double(k) / Double(n)
            var p: Vec2
            switch b.form {
            case .upright:
                p = Vec2(0.05 * H * t + wiggle[k] * 3 * s, t * H)
            case .informal:
                p = Vec2(sin(t * .pi * 1.7 + phase) * (12 + 18 * s) + wiggle[k] * 2, t * H)
            case .windswept:
                p = Vec2(windDir * (0.08 * H * t + 0.45 * H * t * t), t * H * (1 - 0.28 * t))
            case .cascade:
                if t < 0.3 { p = Vec2(windDir * t * 26, t * H * 0.9) }
                else { p = Vec2(windDir * (8 + (t - 0.3) * H * 0.8), 0.27 * H - (t - 0.3) * H * 0.9) }
            }
            trunk.append(p)
        }
        func along(_ t: Double) -> Vec2 {
            let f = t * Double(n)
            let i = min(n - 1, Int(f)), u = f - Double(i)
            return trunk[i] + (trunk[i + 1] - trunk[i]) * u
        }
        let baseThickness = 5 + 15 * s

        // Surface roots.
        var roots: [[Vec2]] = []
        let rootCount = s < 0.15 ? 0 : 2 + Int(s * 3)
        for r in 0..<rootCount {
            let dir: Double = r % 2 == 0 ? 1 : -1
            let len = (8 + 14 * s) * rng.range(0.7, 1.3)
            roots.append([Vec2(dir * baseThickness * 0.3, 2), Vec2(dir * len * 0.6, 0.5), Vec2(dir * len, -1)])
        }

        // Branches, longest at the bottom, each with its pad and (as it fills out) a twig or two.
        var limbs: [(points: [Vec2], thickness: Double)] = []
        var pads: [BonsaiLayout.Pad] = []
        let count = b.branches.count
        for (i, br) in b.branches.enumerated() {
            var brng = SplitMix64(seed: b.seed ^ (UInt64(i + 1) &* 0x9E3779B97F4A7C15))
            let t = min(0.9, 0.2 + 0.68 * (Double(i) + 0.5) / Double(max(count, 1)))
            let root = along(t)
            let fullness = min(1, log2(1 + Double(br.edits)) / 7)
            let L = W * 0.5 * (1 - 0.55 * t) * (0.45 + 0.55 * fullness)
            let side = b.form == .windswept ? windDir : br.side
            var angle: Double
            switch b.form {
            case .windswept: angle = brng.range(-0.1, 0.25)
            case .cascade: angle = t > 0.45 ? brng.range(-0.55, -0.2) : brng.range(0.05, 0.35)
            default: angle = brng.range(0.08, 0.32) - 0.12 * t   // upper branches flatter
            }
            let droop = s > 0.6 ? -0.08 * fullness : 0   // old branches sag a little at the tip
            let p1 = root + Vec2(side * cos(angle + 0.22) * L * 0.45, sin(angle + 0.22) * L * 0.45)
            let end = p1 + Vec2(side * cos(angle + droop) * L * 0.55, sin(angle + droop) * L * 0.55)
            let thick = baseThickness * (0.55 - 0.3 * t)
            limbs.append((points: [root, p1, end], thickness: thick))
            let rx = (10 + 26 * fullness) * (0.55 + 0.45 * s)
            var padCenters = [end]
            if fullness > 0.35 {
                let q = p1 + Vec2(side * cos(angle + 0.9) * L * 0.32, sin(angle + 0.9) * L * 0.32)
                limbs.append((points: [p1, q], thickness: thick * 0.5))
                padCenters.append(q)
            }
            if fullness > 0.7 {
                let m = p1 + (end - p1) * 0.55
                let q = m + Vec2(side * cos(angle - 0.35) * L * 0.28, sin(angle - 0.35) * L * 0.28 - 4)
                limbs.append((points: [m, q], thickness: thick * 0.45))
                padCenters.append(q)
            }
            // Blooms and fruit spread over this branch's pads.
            var bloomSpots: [[Vec2]] = Array(repeating: [], count: padCenters.count)
            var fruitSpots: [[Vec2]] = Array(repeating: [], count: padCenters.count)
            for (k, c) in padCenters.enumerated() {
                let r = k == 0 ? rx : rx * 0.68
                for _ in 0..<4 { bloomSpots[k].append(c + Vec2(brng.range(-0.8, 0.8) * r, brng.range(-0.1, 0.9) * r * 0.4)) }
                for _ in 0..<3 { fruitSpots[k].append(c + Vec2(brng.range(-0.7, 0.7) * r, -r * 0.4 - 3 - brng.range(0, 5))) }
            }
            var bloomsLeft = min(br.blooms, 4 * padCenters.count), fruitLeft = min(br.fruit, 3 * padCenters.count)
            for (k, c) in padCenters.enumerated() {
                let r = k == 0 ? rx : rx * 0.68
                let nb = min(bloomSpots[k].count, (bloomsLeft + padCenters.count - 1 - k) / padCenters.count)
                let nf = min(fruitSpots[k].count, (fruitLeft + padCenters.count - 1 - k) / padCenters.count)
                bloomsLeft -= nb; fruitLeft -= nf
                pads.append(.init(center: c, rx: r, ry: r * 0.4, branch: i, blooms: Array(bloomSpots[k].prefix(nb)), fruit: Array(fruitSpots[k].prefix(nf))))
            }
        }
        // The crown: a cluster at the top (for a cascade, at the bend).
        let top = b.form == .cascade ? along(0.3) + Vec2(-windDir * 5, 10) : trunk[n] + Vec2(0, 5)
        let crx = (11 + 22 * s), cry = crx * 0.42
        pads.append(.init(center: top, rx: crx, ry: cry, branch: -1, blooms: [], fruit: []))
        if s > 0.4 {
            pads.append(.init(center: top + Vec2(-crx * 0.7, -cry * 0.9), rx: crx * 0.65, ry: cry * 0.7, branch: -1, blooms: [], fruit: []))
            pads.append(.init(center: top + Vec2(crx * 0.75, -cry * 1.1), rx: crx * 0.6, ry: cry * 0.7, branch: -1, blooms: [], fruit: []))
        }

        // Pot, and the bounds of it all.
        let potW = 44 + 56 * s, potH = 15 + 13 * s
        var minX = -potW / 2, maxX = potW / 2, minY = -potH, maxY = 0.0
        for p in trunk { minX = min(minX, p.x - 6); maxX = max(maxX, p.x + 6); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        for r in roots { for p in r { minX = min(minX, p.x - 2); maxX = max(maxX, p.x + 2) } }
        for p in pads {
            minX = min(minX, p.center.x - p.rx - 3); maxX = max(maxX, p.center.x + p.rx + 3)
            minY = min(minY, p.center.y - p.ry - 10); maxY = max(maxY, p.center.y + p.ry + 5)
        }
        return BonsaiLayout(trunk: trunk, limbs: limbs, roots: roots, pads: pads, potWidth: potW, potHeight: potH,
                            thickness: baseThickness,
                            bounds: Rect(x: minX - 4, y: minY - 2, w: maxX - minX + 8, h: maxY - minY + 6))
    }
}

// MARK: - In the world

/// Where a tree is right now.
public struct BonsaiPlacement: Sendable {
    public var project: String
    /// Middle of the pot's top (soil level), global points.
    public var base: Vec2
    public var scale: Double
    /// The terminal window it's rooted on (nil in the nursery).
    public var windowID: Int?
    /// Nursery slot, or -1 while live.
    public var slot: Int
    public var layout: BonsaiLayout
    /// Index into the world's placement list (owner ids are derived from it).
    public var index: Int
}

public enum BonsaiPart: Sendable { case leaf, bloom, fruit }

public enum BonsaiEvent: Equatable, Sendable {
    case planted(String)
    case sprouted(String, branch: Int)
    case grew(String, part: String, branch: Int)
    case moved(String, live: Bool)
    /// A round number reached: edits 50/100/250/500, sessions 5/10/25, tasks 25/100.
    case milestone(String, String)
}

/// A live Claude session: which window the tree is rooted on.
struct LiveBonsai { var windowID: Int?; var floorX: Double? }

extension World {
    static let bonsaiOwnerBase = -495_000
    static let nurseryOwnerBase = -497_000
    static let ledgeOwnerBase = -490_000
    static func isBonsaiOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= bonsaiOwnerBase && o > nurseryOwnerBase }
    static func isNurseryOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= nurseryOwnerBase && o > nurseryOwnerBase - 100 }
    static func isLedgeOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= ledgeOwnerBase && o > bonsaiOwnerBase }

    public static let nurserySlots = 4
    public static let nurseryWidth = 140.0

    // MARK: Growth (called by the Claude buddy)

    public func loadBonsai(_ book: BonsaiBook) {
        bonsaiBook = book
        for i in bonsaiBook.trees.indices { bonsaiBook.trees[i].currentSession = nil }
        rebuildAttached()
    }

    /// A Claude session started (or sent another prompt) in `project`, on `windowID`.
    public func bonsaiStart(project: String, session: String, windowID: Int?, floorX: Double? = nil) {
        let now = Date().timeIntervalSince1970
        if bonsaiBook.index(of: project) == nil {
            bonsaiBook.trees.append(Bonsai(project: project, now: now))
            bonsaiEvents.append(.planted(project))
        }
        guard let i = bonsaiBook.index(of: project) else { return }
        if bonsaiBook.trees[i].startSession(session, now: now), let b = bonsaiBook.trees[i].currentBranch {
            bonsaiEvents.append(.sprouted(project, branch: b))
        }
        checkMilestones(i)
        let wasLive = liveBonsai[project] != nil
        liveBonsai[project] = LiveBonsai(windowID: windowID, floorX: floorX)
        if !wasLive { bonsaiEvents.append(.moved(project, live: true)) }
        rebuildAttached()
    }

    /// Puts a tree in the book as given (the demo plants an established one; the real book is restored after).
    public func seedBonsai(_ t: Bonsai) {
        bonsaiBook.trees.removeAll { $0.project == t.project }
        bonsaiBook.trees.append(t)
        rebuildAttached()
    }

    public func bonsaiEnd(project: String) {
        guard let i = bonsaiBook.index(of: project) else { return }
        bonsaiBook.trees[i].endSession()
        bonsaiBook.trees[i].lastSeen = Date().timeIntervalSince1970
        if liveBonsai.removeValue(forKey: project) != nil { bonsaiEvents.append(.moved(project, live: false)) }
        rebuildAttached()
    }

    /// Claude did something in `project`: the tree grows.
    public func bonsaiGrow(project: String, _ part: BonsaiPart, count: Int = 1) {
        guard count > 0, let i = bonsaiBook.index(of: project), let b = bonsaiBook.trees[i].growthBranch else { return }
        switch part {
        case .leaf: bonsaiBook.trees[i].branches[b].edits += count
        case .bloom: bonsaiBook.trees[i].branches[b].blooms += count
        case .fruit: bonsaiBook.trees[i].branches[b].fruit += count
        }
        bonsaiBook.trees[i].lastSeen = Date().timeIntervalSince1970
        bonsaiEvents.append(.grew(project, part: "\(part)", branch: b))
        checkMilestones(i)
        rebuildAttached()
    }

    /// Round numbers worth a ribbon and a little dance.
    func checkMilestones(_ i: Int) {
        let t = bonsaiBook.trees[i]
        var reached: [(String, String)] = []
        for n in [50, 100, 250, 500, 1000] where t.edits >= n { reached.append(("edits-\(n)", "\(n) edits")) }
        for n in [5, 10, 25, 50] where t.sessions >= n { reached.append(("sessions-\(n)", "\(n) sessions")) }
        for n in [25, 100, 250] where t.blooms >= n { reached.append(("tasks-\(n)", "\(n) tasks finished")) }
        for (key, text) in reached where !t.milestones.contains(key) {
            bonsaiBook.trees[i].milestones.append(key)
            bonsaiEvents.append(.milestone(t.project, text))
            // Everyone nearby celebrates.
            if let p = bonsaiPlacements.first(where: { $0.project == t.project }) {
                for c in creatures where c.job == nil && c.isGrounded && abs(c.pos.x - p.base.x) < 500 && abs(c.pos.y - p.base.y) < 300 {
                    startDance(c, duration: rng.range(3, 5), invite: false)
                }
            }
        }
    }

    public func drainBonsaiEvents() -> [BonsaiEvent] {
        defer { bonsaiEvents.removeAll() }
        return bonsaiEvents
    }

    /// Time at work: the trees of sessions that are being worked on right now age a little.
    func updateBonsai(_ dt: Double) {
        guard !liveBonsai.isEmpty else { return }
        for c in creatures {
            guard let j = c.job, j.kind == .claude, j.phase == .working, let p = j.label, let i = bonsaiBook.index(of: p) else { continue }
            bonsaiBook.trees[i].minutes += dt / 60
        }
    }

    // MARK: Placement

    /// Which side of the main screen the nursery is on (+1 right, -1 left).
    public var nurserySide: Double {
        get { _nurserySide }
        set { _nurserySide = newValue; rebuildAttached() }
    }

    /// Nursery bracket `k` (0 = lowest) on the main screen.
    public func nurseryBracket(_ k: Int) -> Surface? {
        guard let f = groveFloor else { return nil }
        let y = f.minY + 170 + Double(k) * 160
        guard y < f.maxY - 170 else { return nil }
        let lo = nurserySide < 0 ? f.minX + 6 : f.maxX - World.nurseryWidth - 6
        return Surface(ownerID: World.nurseryOwnerBase - k, kind: .shelf, y: y, minX: lo, maxX: lo + World.nurseryWidth)
    }

    /// Trees resting in the nursery, most recently worked on first (the rest wait in the greenhouse, off screen).
    public var restingTrees: [Bonsai] {
        bonsaiBook.trees.filter { liveBonsai[$0.project] == nil }.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Recomputes where every tree and every terminal ledge is, and the platforms they offer.
    func rebuildAttached() {
        guard let f = groveFloor else { return }
        var placements: [BonsaiPlacement] = []
        var surfacesOut: [Surface] = []
        var attached: [Int: Int] = [:]

        // Live trees: on the terminal window's top edge, at the visible end with the most room.
        for tree in bonsaiBook.trees {
            guard let live = liveBonsai[tree.project] else { continue }
            let layout = BonsaiGeometry.layout(tree)
            var placed: BonsaiPlacement?
            if let wid = live.windowID, let w = windows[wid],
               let scr = screens.first(where: { w.midX >= $0.minX && w.midX < $0.maxX }) ?? screens.first {
                let tops = builtSurfaces.filter { $0.ownerID == wid && $0.kind == .windowTop }
                let headroom = scr.maxY - w.maxY - 8
                let scale = min(1, max(0.5, headroom / max(1, layout.bounds.maxY)))
                if headroom > 50, let seg = tops.max(by: { $0.width < $1.width }), seg.width > layout.potWidth * scale + 40 {
                    // The corner nearest the screen edge keeps the tree out of the way of the window's title.
                    let leftRoom = w.minX - scr.minX, rightRoom = scr.maxX - w.maxX
                    let x = leftRoom < rightRoom ? seg.minX + layout.potWidth * scale / 2 + 18 : seg.maxX - layout.potWidth * scale / 2 - 18
                    placed = BonsaiPlacement(project: tree.project, base: Vec2(x, w.maxY), scale: scale, windowID: wid, slot: -1, layout: layout, index: placements.count)
                }
            } else if let fx = live.floorX {
                placed = BonsaiPlacement(project: tree.project, base: Vec2(fx, f.minY), scale: 0.85, windowID: nil, slot: -1, layout: layout, index: placements.count)
            }
            if let p = placed { placements.append(p) }
        }
        // Resting trees on the nursery brackets, and live ones whose window has no room or isn't showing right now.
        var liveProjects = Set(placements.map(\.project))
        let waiting = bonsaiBook.trees.filter { liveBonsai[$0.project] != nil && !liveProjects.contains($0.project) }
        for (k, tree) in (waiting + restingTrees.filter { !liveProjects.contains($0.project) }).prefix(World.nurserySlots).enumerated() {
            guard let br = nurseryBracket(k) else { break }
            liveProjects.insert(tree.project)
            let layout = BonsaiGeometry.layout(tree)
            let scale = min(0.8, 150 / max(1, layout.bounds.maxY))
            placements.append(BonsaiPlacement(project: tree.project, base: Vec2(br.minX + br.width / 2, br.y), scale: scale, windowID: nil, slot: k, layout: layout, index: placements.count))
            surfacesOut.append(br)
        }
        // Foliage pads are platforms.
        for p in placements {
            for (n, pad) in p.layout.pads.enumerated() where pad.rx * p.scale >= 17 && n < 16 {
                let owner = World.bonsaiOwnerBase - (p.index * 16 + n)
                surfacesOut.append(Surface(ownerID: owner, kind: .plant, y: p.base.y + (pad.center.y + pad.ry * 0.8) * p.scale,
                                           minX: p.base.x + (pad.center.x - pad.rx * 0.7) * p.scale, maxX: p.base.x + (pad.center.x + pad.rx * 0.7) * p.scale))
                if let wid = p.windowID { attached[owner] = wid }
            }
        }
        bonsaiPlacements = placements

        // Terminal ledges: mossy shelves that grow out of a Claude window's side as the edits pile up.
        var ledges: [TerminalLedge] = []
        for c in creatures {
            guard let j = c.job, j.kind == .claude, j.phase != .leaving, let wid = j.windowID, let w = windows[wid],
                  let scr = screens.first(where: { w.midX >= $0.minX && w.midX < $0.maxX }) ?? screens.first else { continue }
            let count = min(4, j.blocks / 4)
            guard count > 0 else { continue }
            let side: Double = j.shelfSide.map { -$0 } ?? (scr.maxX - w.maxX > w.minX - scr.minX ? 1 : -1)
            let width = 56.0
            let fits = side > 0 ? w.maxX + width <= scr.maxX : w.minX - width >= scr.minX
            guard fits else { continue }
            for k in 0..<count {
                let y = w.maxY - 70 - Double(k) * 64
                guard y > w.minY + 40 else { break }
                let owner = World.ledgeOwnerBase - (c.id * 8 + k)
                let lo = side > 0 ? w.maxX - 4 : w.minX - width
                let s = Surface(ownerID: owner, kind: .shelf, y: y, minX: lo, maxX: lo + width + 4)
                surfacesOut.append(s)
                attached[owner] = wid
                ledges.append(TerminalLedge(worker: c.id, windowID: wid, side: side, index: k, surface: s))
            }
        }
        terminalLedges = ledges
        attachedSurfaces = surfacesOut
        attachedOwnerWindow = attached
        setSurfacesDirty()
    }

    /// Brain choices around the trees: after dark, or when sleepy, climb up into a foliage pad for a nap.
    func bonsaiChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard c.job == nil, c.isGrounded, isNight || c.energy < 0.5 else { return }
        let pad = attachedSurfaces.filter { p in
            guard World.isBonsaiOwner(p.ownerID) else { return false }
            let dy = p.y - c.pos.y, cx = p.minX + p.width / 2
            return dy > 20 && dy < maxJumpHeight && abs(cx - c.pos.x) < maxJumpDistance * 0.9
        }.min { abs($0.minX + $0.width / 2 - c.pos.x) < abs($1.minX + $1.width / 2 - c.pos.x) }
        guard let s = pad else { return }
        add("climbTree", isNight ? 1.4 : 0.8) {
            let tx = (s.minX + s.width / 2).clamped(s.minX + 8, s.maxX - 8)
            self.launch(c, velocity: self.ballistic(from: c.pos, toX: tx, y: s.y, apexExtra: 40))
        }
    }

    /// The tree under a point, if any (for clicks).
    public func bonsai(at p: Vec2) -> BonsaiPlacement? {
        bonsaiPlacements.last { pl in
            let b = pl.layout.bounds
            return p.x >= pl.base.x + b.minX * pl.scale && p.x <= pl.base.x + b.maxX * pl.scale
                && p.y >= pl.base.y + b.minY * pl.scale && p.y <= pl.base.y + b.maxY * pl.scale
        }
    }
}

/// A mossy ledge growing out of the side of a terminal window Claude is working in.
public struct TerminalLedge: Sendable {
    public var worker: Int
    public var windowID: Int
    public var side: Double
    public var index: Int
    public var surface: Surface
}
