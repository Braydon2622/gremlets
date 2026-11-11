import Foundation

/// The Grove: a row of big, useful plants along the bottom of your main screen that grow from *your Claude tasks*.
///
/// Every time Claude finishes a turn, every plant in the grove gets a spark. Sparks level a plant up (1 → 5) and each
/// level makes it visibly bigger and more useful:
///
/// | Plant | What it does |
/// |---|---|
/// | Bouncecap | Its cap is a trampoline. Gremlets bounce sky high off it (and get launched at bosses). |
/// | Skyvine | A beanstalk with leaf platforms that climbs higher up the screen every level. |
/// | Lanternbloom | Glows after dark; Gremlets gather around it like a campfire. |
/// | Sunberry | Grows berries (more each level). Gremlets snack on them for energy and throw them at bosses. |
/// | Snapjaw | A guardian plant that chomps bosses that fly too low, and fireflies at night. |
/// | Wishwillow | Grants a wish a day from level 3 (the next seed anywhere is epic or better). |
///
/// New plots unlock as you finish more Claude tasks, so the grove keeps filling in the more work gets done.
public enum GroveKind: String, CaseIterable, Codable, Sendable {
    case sunberry, bouncecap, lanternbloom, skyvine, snapjaw, wishwillow
    /// Pop-ups: here for a few minutes, then gone. A pile of fallen leaves to dive into, a dandelion clock to blow.
    case leafpile, puffball

    /// Here for a few minutes, not a quarter of an hour.
    public var brief: Bool { self == .leafpile || self == .puffball }

    public var name: String {
        switch self {
        case .sunberry: return "Sunberry"
        case .bouncecap: return "Bouncecap"
        case .lanternbloom: return "Lanternbloom"
        case .skyvine: return "Skyvine"
        case .snapjaw: return "Snapjaw"
        case .wishwillow: return "Wishwillow"
        case .leafpile: return "Leaf pile"
        case .puffball: return "Dandelion clock"
        }
    }

    public var power: String {
        switch self {
        case .sunberry: return "berries that put a spring back in tired Gremlets"
        case .bouncecap: return "a trampoline cap"
        case .lanternbloom: return "a night light Gremlets gather around"
        case .skyvine: return "a beanstalk ladder up the side of the screen"
        case .snapjaw: return "snaps at passers-by, and catches fireflies at night to feed the grove"
        case .wishwillow: return "a wish a day from level 3"
        case .leafpile: return "a pile of leaves to dive into"
        case .puffball: return "a dandelion clock to blow"
        }
    }

    /// Bigger plants need more sparks per level.
    public var cost: Double {
        switch self {
        case .sunberry, .bouncecap, .leafpile, .puffball: return 1
        case .lanternbloom, .snapjaw: return 1.2
        case .skyvine: return 1.4
        case .wishwillow: return 1.6
        }
    }
}

public struct GrovePlant: Codable, Equatable, Sendable {
    public var kind: GroveKind
    /// Horizontal position on the main screen (0 = left edge, 1 = right edge).
    public var x: Double
    /// Claude tasks this plant has soaked up.
    public var sparks: Double = 0
    public var berries = 0
    /// Day number (days since 2001) of the last wish granted.
    public var lastWishDay = -1
    public var golden = false

    public init(kind: GroveKind, x: Double) { self.kind = kind; self.x = x }

    /// Sparks needed to reach levels 2...5 (level 1 = just planted).
    public static let thresholds: [Double] = [2, 5, 10, 18]

    /// 1...5.
    public var level: Int {
        var l = 1
        for t in GrovePlant.thresholds where sparks >= t * kind.cost { l += 1 }
        return l
    }

    /// 0...1 progress toward the next level (1 at max).
    public var levelProgress: Double {
        let l = level
        guard l < 5 else { return 1 }
        let lo = l == 1 ? 0 : GrovePlant.thresholds[l - 2] * kind.cost
        let hi = GrovePlant.thresholds[l - 1] * kind.cost
        return ((sparks - lo) / (hi - lo)).clamped(0, 1)
    }

    /// Visual and physical scale: each level is clearly bigger than the last.
    public var scale: Double { [1.0, 1.0, 1.4, 1.85, 2.35, 2.9][level] }
}

/// A platform a grove plant offers (a mushroom cap, a vine leaf, a willow branch, the top of a berry bush).
public struct GroveLedge: Equatable, Sendable {
    public var plot: Int
    public var y: Double
    public var minX: Double
    public var maxX: Double
    public var bouncy: Bool
}

public final class Grove: Codable {
    public internal(set) var plants: [GrovePlant] = []
    /// Claude tasks finished since the grove was planted.
    public internal(set) var tasks = 0
    /// Finished Claude buildings along the bottom of the screen.
    public internal(set) var village: [House] = []
    public static let maxHouses = 14
    /// The mine: digs earned (one per Claude task) and the gems found so far.
    public internal(set) var digCharges = 0
    public internal(set) var gems: [String: Int] = [:]
    /// Today's Claude tasks, for the lantern festival.
    var todayKey: String?
    var todayTasks = 0
    var festivalDone = false
    /// The one plant out at the moment (the app shows a single, smaller plant in the bottom-left corner and swaps it
    /// for another every so often). nil: every plant shows (on its bracket up the left edge).
    /// -1: the corner is empty for a while between plants.
    public internal(set) var featured: Int?
    /// When the corner next changes (seconds since 1970, so restarting the app doesn't reset it).
    public internal(set) var nextCornerChange: Double?

    enum CodingKeys: String, CodingKey { case plants, tasks, village, digCharges, gems, todayKey, todayTasks, festivalDone, featured, nextCornerChange }
    public required init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        plants = try c.decodeIfPresent([GrovePlant].self, forKey: .plants) ?? []
        tasks = try c.decodeIfPresent(Int.self, forKey: .tasks) ?? 0
        village = try c.decodeIfPresent([House].self, forKey: .village) ?? []
        digCharges = try c.decodeIfPresent(Int.self, forKey: .digCharges) ?? 0
        gems = try c.decodeIfPresent([String: Int].self, forKey: .gems) ?? [:]
        todayKey = try c.decodeIfPresent(String.self, forKey: .todayKey)
        todayTasks = try c.decodeIfPresent(Int.self, forKey: .todayTasks) ?? 0
        festivalDone = try c.decodeIfPresent(Bool.self, forKey: .festivalDone) ?? false
        featured = try c.decodeIfPresent(Int.self, forKey: .featured)
        nextCornerChange = try c.decodeIfPresent(Double.self, forKey: .nextCornerChange)
    }

    public static let maxPlots = 5
    /// Plot unlock schedule: total tasks needed for plot n (the first two are free).
    public static let unlockAt = [0, 4, 10, 18, 30]
    /// Planting order, so every grove grows the same useful mix. (The sunberry bush is retired: Braydon found the
    /// green clump beside the mushroom odd, and it sat over the bottoms of windows.)
    static let order: [GroveKind] = [.bouncecap, .lanternbloom, .skyvine, .snapjaw, .wishwillow]
    /// The garden is a corner, not a row: it hugs the left edge of the screen and climbs it (the skyvine runs up the
    /// wall, the willow spreads over everything). Offsets in points from the screen's left edge.
    static func offset(_ k: GroveKind) -> Double {
        switch k {
        case .skyvine: return 40
        case .bouncecap: return 112
        case .sunberry: return 204
        case .lanternbloom: return 268
        case .snapjaw: return 322
        case .wishwillow: return 426
        case .leafpile, .puffball: return 112
        }
    }
    static let slots: [Double] = [0.16, 0.30, 0.44, 0.58, 0.72, 0.86]

    /// Plants that live on wooden brackets up the left edge of the screen (off the floor, off the bottoms of windows),
    /// and how high above the floor their shelf is. The skyvine stays rooted on the floor: it's the ladder up the wall
    /// between them.
    static func shelf(_ k: GroveKind) -> Double? {
        switch k {
        case .skyvine, .sunberry, .leafpile, .puffball: return nil
        case .bouncecap: return 150
        case .lanternbloom: return 270
        case .snapjaw: return 390
        case .wishwillow: return 520
        }
    }

    /// How far a plant's bracket reaches out from the wall (points).
    public func bracketReach(_ i: Int) -> Double? {
        guard featured == nil, Grove.shelf(plants[i].kind) != nil else { return nil }
        return 40 + size(i).x + 18
    }

    public init() {}

    public var unlockedPlots: Int { Grove.unlockAt.filter { tasks >= $0 }.count }
    public var nextUnlock: Int? { Grove.unlockAt.first { $0 > tasks } }

    /// Plants anything newly unlocked. Returns the new plants' indices.
    @discardableResult
    func fillPlots() -> [Int] {
        var added: [Int] = []
        // (The corner rotation may already have planted some of them; never plant a kind twice.)
        while plants.count < unlockedPlots, let k = Grove.order.first(where: { k in !plants.contains { $0.kind == k } }) {
            plants.append(GrovePlant(kind: k, x: Grove.slots[min(plants.count, Grove.slots.count - 1)]))
            added.append(plants.count - 1)
        }
        return added
    }

    public func plant(of kind: GroveKind) -> Int? { plants.firstIndex { $0.kind == kind } }

    // MARK: Geometry (global points, y-up)

    /// Where a plot sits: on its bracket up the left edge, or (the skyvine) on the floor.
    public func base(_ i: Int, floor: Rect) -> Vec2 {
        let k = plants[i].kind
        // One plant at a time: on the floor, tucked into the bottom-left corner.
        if featured != nil { return Vec2(floor.minX + (k == .skyvine ? 34 : 24 + size(i).x / 2), floor.minY) }
        if let h = Grove.shelf(k) {
            // Never above the top of a short screen.
            let y = floor.minY + min(h, max(120, floor.h - size(i).y - 80))
            return Vec2(floor.minX + 40 + size(i).x / 2, y)
        }
        return Vec2(floor.minX + Grove.offset(k), floor.minY)
    }

    /// Size of the drawn plant (points). The platform layer draws it centered on `base` x, sitting on the floor.
    public func size(_ i: Int) -> Vec2 {
        let p = plants[i]
        // The corner plant is kept small (and the skyvine short), so it never gets in the way.
        if featured != nil {
            let s = min(1.1, p.scale) * 0.42
            switch p.kind {
            case .skyvine: return Vec2(52, min(150, 80 + 24 * Double(p.level - 1)))
            case .bouncecap: return Vec2(54 * s, 46 * s)
            case .lanternbloom: return Vec2(34 * s, 56 * s)
            case .sunberry: return Vec2(52 * s, 30 * s)
            case .snapjaw: return Vec2(40 * s, 44 * s)
            case .wishwillow: return Vec2(90 * s, 96 * s)
            case .leafpile: return Vec2(60, 24)
            case .puffball: return Vec2(30, 48)
            }
        }
        let s = p.scale
        switch p.kind {
        case .bouncecap: return Vec2(54 * s, 46 * s)
        case .skyvine: return Vec2(84, 96 + 124 * Double(p.level - 1))
        case .lanternbloom: return Vec2(34 * s, 56 * s)
        case .sunberry: return Vec2(52 * s, 30 * s)
        case .snapjaw: return Vec2(40 * s, 44 * s)
        case .wishwillow: return Vec2(90 * s, 96 * s)
        case .leafpile: return Vec2(60, 24)
        case .puffball: return Vec2(30, 48)
        }
    }

    /// Platforms the grove offers on a screen floor.
    public func ledges(floor: Rect, roofs: Bool = true) -> [GroveLedge] {
        var out: [GroveLedge] = []
        for i in plants.indices where featured == nil || featured == i {
            let b = base(i, floor: floor), sz = size(i), p = plants[i]
            // The bracket's plank, either side of the pot.
            if let reach = bracketReach(i) {
                out.append(GroveLedge(plot: i, y: b.y, minX: floor.minX + 6, maxX: floor.minX + reach - 4, bouncy: false))
            }
            switch p.kind {
            case .bouncecap:
                out.append(GroveLedge(plot: i, y: b.y + sz.y * 0.92, minX: b.x - sz.x * 0.38, maxX: b.x + sz.x * 0.38, bouncy: true))
            case .sunberry:
                out.append(GroveLedge(plot: i, y: b.y + sz.y * 0.9, minX: b.x - sz.x * 0.3, maxX: b.x + sz.x * 0.3, bouncy: false))
            case .skyvine:
                // A ladder up the wall: a broad leaf every 64pt, all reaching out from the screen's edge.
                let leaves = max(1, Int((sz.y - 36) / 64))
                for n in 0..<leaves {
                    let y = b.y + 56 + Double(n) * 64
                    out.append(GroveLedge(plot: i, y: y, minX: b.x - 22, maxX: b.x + 34, bouncy: false))
                }
            case .wishwillow:
                out.append(GroveLedge(plot: i, y: b.y + sz.y * 0.55, minX: b.x - sz.x * 0.46, maxX: b.x - sz.x * 0.08, bouncy: false))
                out.append(GroveLedge(plot: i, y: b.y + sz.y * 0.78, minX: b.x + sz.x * 0.06, maxX: b.x + sz.x * 0.42, bouncy: false))
            case .lanternbloom, .snapjaw, .leafpile, .puffball:
                break
            }
        }
        // Village roofs (plot = -1 - house index): the ridge, the dome, the terrace, wherever the picture has a spot.
        for (n, h) in village.enumerated() where roofs && h.biome != "item:spring" && h.biome != "item:lamps" {
            if let ry = h.roofY, ry <= 0 { continue }   // a house with nowhere to stand (a spire)
            let x = floor.minX + h.x * floor.w
            let hw = h.roofHalfW ?? h.w * 0.3
            out.append(GroveLedge(plot: -1 - n, y: floor.minY + (h.roofY ?? (h.h - 4)), minX: x - hw, maxX: x + hw, bouncy: false))
        }
        return out
    }

    // MARK: Persistence

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ d: Data) -> Grove? { try? JSONDecoder().decode(Grove.self, from: d) }
}


/// What just happened in the grove, for the platform layer's effects.
public enum GroveEvent: Equatable, Sendable {
    case fed(tasks: Int)
    case planted(Int)
    case levelUp(Int, level: Int)
    case berryPicked(Int, by: Int)
    case wish(Int)
    case bounce(Int, by: Int)
    case chomp(Int)
    case houseAdded(Int)
    /// The corner plant went away for a while.
    case cornerCleared
    /// A Gremlet dove into the leaf pile / blew the dandelion clock.
    case played(Int, by: Int)
    case wentHome(Int, by: Int)
    case claimed(Int, by: Int)
    case leftHome(Int, by: Int)
}

extension World {
    public static let groveOwnerBase = -450_000
    static func groveOwner(_ ledge: Int) -> Int { groveOwnerBase - ledge }
    static func isGroveOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= groveOwnerBase && o > groveOwnerBase - 10_000 }

    /// The main screen's floor rect (the grove lives here).
    public var groveFloor: Rect? { screens.first }

    /// Grove platforms as surfaces (recomputed whenever the grove or screens change).
    func rebuildGroveSurfaces() {
        guard let f = groveFloor else { groveSurfaces = []; groveLedges = []; return }
        groveLedges = grove.ledges(floor: f, roofs: villageOn)
        groveSurfaces = groveLedges.enumerated().map { n, l in
            Surface(ownerID: World.groveOwner(n), kind: .plant, y: l.y, minX: l.minX, maxX: l.maxX)
        }
        // The grove plants are what the Gremlets go and water.
        gardenSpots = grove.plants.indices.filter { grove.featured == nil || grove.featured == $0 }.map { grove.base($0, floor: f).x }
    }

    /// Replaces the grove (loaded from disk) and plants anything already unlocked.
    public func loadGrove(_ g: Grove) {
        grove = g
        if let f = grove.featured, grove.plants.indices.contains(f), grove.plants[f].kind == .sunberry { grove.featured = nil }
        let featuredKind = grove.featured.flatMap { grove.plants.indices.contains($0) ? grove.plants[$0].kind : nil }
        grove.plants.removeAll { $0.kind == .sunberry }
        // (-1, an empty corner, survives a restart too: only a real plant needs re-finding by its kind.)
        if grove.featured != -1 { grove.featured = featuredKind.flatMap { grove.plant(of: $0) } }
        // Older villages grew in from the left corner, where the garden lives now: move those houses to the right.
        let displaced = grove.village.filter { $0.x < 0.36 }
        if !displaced.isEmpty {
            grove.village.removeAll { $0.x < 0.36 }
            for var h in displaced { if let x = villageSpot(forWidth: h.w) { h.x = x; grove.village.append(h) } }
        }
        // One home: keep only the newest session house.
        if let keep = grove.village.lastIndex(where: { World.isSessionHouse($0.biome) }) {
            let newest = grove.village[keep]
            grove.village.removeAll { World.isSessionHouse($0.biome) }
            grove.village.append(newest)
        }
        for i in grove.fillPlots() { groveEvents.append(.planted(i)) }
        rebuildGroveSurfaces()
        setSurfacesDirty()
        openMineIfReady()
    }

    /// Claude finished a task: every grove plant soaks up a spark, new plots unlock and berries grow. Returns plants
    /// that levelled up.
    @discardableResult
    public func feedGrove(sparks: Double = 1) -> [Int] {
        grove.tasks += 1
        var ups: [Int] = []
        for i in grove.plants.indices {
            let before = grove.plants[i].level
            grove.plants[i].sparks += sparks
            if grove.plants[i].kind == .sunberry {
                grove.plants[i].berries = min(2 + grove.plants[i].level * 2, grove.plants[i].berries + 1)
            }
            let after = grove.plants[i].level
            if after > before { ups.append(i); groveEvents.append(.levelUp(i, level: after)) }
        }
        for i in grove.fillPlots() { groveEvents.append(.planted(i)) }
        grove.digCharges = min(20, grove.digCharges + 1)
        countTaskToday()
        groveEvents.append(.fed(tasks: grove.tasks))
        rebuildGroveSurfaces()
        setSurfacesDirty()
        openMineIfReady()
        if !ups.isEmpty, ups.contains(where: { grove.plants[$0].level == 5 }) { requestEvent(.festival) }
        return ups
    }

    /// The snapjaw at work, and the garden spots the Gremlets water. Called every tick.
    func updateGrove(_ dt: Double) {
        if rotateGrove { rotateGroveIfDue() }
        guard let f = groveFloor, let i = shownPlant(.snapjaw) else { return }
        let b = grove.base(i, floor: f), sz = grove.size(i)
        // Fireflies after dark: each one it catches is a spark for the whole grove.
        if isNight && rng.chance(dt / 40) {
            for k in grove.plants.indices { grove.plants[k].sparks += 0.12 }
            groveEvents.append(.chomp(i))
            rebuildGroveSurfaces()
        }
        // Gremlets love to dare it: walk past the mouth and it snaps, and they jump.
        for c in creatures where c.job == nil && c.isGrounded && abs(c.pos.y - f.minY) < 4 && c.activity == .walk
            && abs(c.pos.x - b.x) < sz.x * 0.55 && clock - c.lastSnap > 25 {
            c.lastSnap = clock
            groveEvents.append(.chomp(i))
            c.groundOwner = nil
            c.vel = Vec2((c.pos.x < b.x ? -1 : 1) * 160, 420)
            c.set(.airborne, duration: 5)
            emit(.startled(c.id))
        }
    }

    /// A gentle boost from the window-box gardens (a harvest is worth half a task).
    public func groveHarvestBonus() {
        for i in grove.plants.indices { grove.plants[i].sparks += 0.5 }
        rebuildGroveSurfaces()
    }

    public func drainGroveEvents() -> [GroveEvent] {
        defer { groveEvents.removeAll() }
        return groveEvents
    }

    /// Ledge index the creature is standing on, if it's a grove ledge.
    func groveLedge(under c: Creature) -> GroveLedge? {
        guard World.isGroveOwner(c.groundOwner), let o = c.groundOwner else { return nil }
        let n = World.groveOwnerBase - o
        return n < groveLedges.count ? groveLedges[n] : nil
    }

    /// Bouncecap: landing on the cap launches you higher than you fell (capped), with a little spin of luck.
    func groveBounce(_ c: Creature, on s: Surface, impact: Double) -> Bool {
        guard World.isGroveOwner(s.ownerID) else { return false }
        let n = World.groveOwnerBase - s.ownerID
        guard n < groveLedges.count, groveLedges[n].bouncy else { return false }
        let level = grove.plants[groveLedges[n].plot].level
        let up = min(900 + Double(level) * 230, max(1050, impact * 1.05 + 240))
        c.vel = Vec2(rng.range(-160, 160), up)
        c.pos.y = s.y + 1
        c.groundOwner = nil
        c.set(.airborne)
        groveEvents.append(.bounce(groveLedges[n].plot, by: c.id))
        lastCornerUse = now
        return true
    }

    /// Wishwillow: one wish a day from level 3. Call once a minute or so.
    public func checkWishwillow(day: Int) {
        guard let i = shownPlant(.wishwillow), grove.plants[i].level >= 3, grove.plants[i].lastWishDay != day else { return }
        grove.plants[i].lastWishDay = day
        makeWish()
        groveEvents.append(.wish(i))
    }

    /// Grove choices for the brain: snack on a sunberry, go bounce on the bouncecap, sit by the lantern at night.
    func groveChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard let f = groveFloor, c.job == nil, !grove.plants.isEmpty else { return }
        // Only Gremlets on (or near) the main screen's floor go to the grove.
        guard abs(c.pos.y - f.minY) < 4, c.pos.x >= f.minX, c.pos.x <= f.maxX else { return }
        if let i = shownPlant(.sunberry), grove.plants[i].berries > 0, c.energy < 0.8 {
            add("snack", 0.9 * (1.2 - c.energy)) { self.startGroveVisit(c, plot: i, task: .snack) }
        }
        if let i = shownPlant(.bouncecap) {
            add("bounce", 0.5 * (0.3 + c.energy)) { self.startGroveVisit(c, plot: i, task: .bounce) }
        }
        // Dare the snapjaw: stroll right past its mouth (it snaps, they leap).
        if let i = shownPlant(.snapjaw), let f = groveFloor {
            let b = grove.base(i, floor: f), sz = grove.size(i)
            add("dare", 0.45) {
                let side: Double = c.pos.x < b.x ? 1 : -1
                c.targetX = (b.x + side * (sz.x * 0.8 + 16)).clamped(f.minX + 14, f.maxX - 14)
                c.groveTask = .dare(i)
                c.set(.walk, duration: 14)
            }
        }
        // Pop-ups: everyone wants a go before they're gone.
        for k in [GroveKind.leafpile, .puffball] {
            guard let i = shownPlant(k), let f = groveFloor else { continue }
            let b = grove.base(i, floor: f)
            add(k == .leafpile ? "diveInLeaves" : "blowPuff", 1.8) {
                let side: Double = c.pos.x < b.x ? -1 : 1
                c.targetX = (b.x + side * (k == .leafpile ? 44 : 22)).clamped(f.minX + 14, f.maxX - 14)
                c.groveTask = .pop(i)
                c.set(.walk, duration: 14)
            }
        }
        // Climb the skyvine's leaves, or sit up in the willow's branches.
        for k in [GroveKind.skyvine, .wishwillow] {
            guard let i = shownPlant(k), let leaf = groveLedges.enumerated().filter({ $0.element.plot == i }).min(by: { $0.element.y < $1.element.y }) else { continue }
            let l = leaf.element, mid = (l.minX + l.maxX) / 2
            guard l.y - c.pos.y < maxJumpHeight * c.species.jumpPower * 0.9, abs(mid - c.pos.x) < 360 else { continue }
            add(k == .skyvine ? "climbSkyvine" : "sitInWillow", 0.6) { self.lastCornerUse = self.now; self.launch(c, velocity: self.ballistic(from: c.pos, toX: mid, y: l.y, apexExtra: 30)) }
        }
        // Bedtime (or just tired): walk home to a house in the village and sleep inside.
        if villageOn, let m = mineIndex, !creatures.contains(where: { $0.mining }) {
            add("dig", grove.digCharges > 0 ? 1.3 : 0.12) { self.startDig(c); _ = m }
        }
        let sleepingIn = creatures.filter { $0.homeHouse != nil }.count
        if villageOn, !grove.village.isEmpty, isNight || c.energy < 0.35 || claudeResting, sleepingIn < grove.village.count * 2 {
            // Its own house if it has one, otherwise any house (not the mine or the village amenities).
            let homes = grove.village.indices.filter { !grove.village[$0].biome.hasPrefix("item:") && grove.village[$0].biome != "mine" }
            if let n = grove.village.firstIndex(where: { $0.owner == c.species.id }) ?? (homes.isEmpty ? nil : homes[Int(rng.next() % UInt64(homes.count))]) {
                add("goHome", isNight ? 1.3 : 0.8) { self.startHomeVisit(c, house: n) }
            }
        }
        if let i = shownPlant(.lanternbloom) {
            // Warm up by the lantern flower (a proper campfire after dark).
            add("campfire", isNight ? 1.1 : 0.4) { self.startGroveVisit(c, plot: i, task: .campfire) }
        }
    }

    enum GroveTask { case snack, bounce, campfire }

    func startGroveVisit(_ c: Creature, plot: Int, task: GroveTask) {
        guard let f = groveFloor, plot < grove.plants.count else { return }
        let b = grove.base(plot, floor: f), sz = grove.size(plot)
        switch task {
        case .snack, .campfire:
            let side: Double = c.pos.x < b.x ? -1 : 1
            c.targetX = b.x + side * (sz.x / 2 + 14 + rng.range(0, 30))
            c.groveTask = task == .snack ? .snack(plot) : .campfire(plot)
            c.set(.walk, duration: 12)
        case .bounce:
            // Jump straight onto the cap from wherever we are (if it's in reach), otherwise walk closer first.
            let capY = b.y + sz.y * 0.92
            if abs(c.pos.x - b.x) < maxJumpDistance * 0.8 && capY - c.pos.y < maxJumpHeight {
                launch(c, velocity: ballistic(from: c.pos, toX: b.x + rng.range(-8, 8), y: capY, apexExtra: 60))
            } else {
                c.targetX = b.x + (c.pos.x < b.x ? -1 : 1) * (sz.x / 2 + 40)
                c.groveTask = .bounce(plot)
                c.set(.walk, duration: 10)
            }
        }
    }

    /// Called from the walk update: arrived at the grove plant we were heading to.
    func arriveAtGrove(_ c: Creature) {
        guard let t = c.groveTask else { return }
        c.groveTask = nil
        switch t { case .bounce, .campfire, .dare, .pop, .snack: lastCornerUse = now; default: break }   // playing with the corner plant
        switch t {
        case .snack(let i):
            guard i < grove.plants.count, grove.plants[i].berries > 0 else { return }
            grove.plants[i].berries -= 1
            c.energy = min(1, c.energy + 0.35)
            c.facing = grove.base(i, floor: groveFloor ?? Rect(x: 0, y: 0, w: 1, h: 1)).x > c.pos.x ? 1 : -1
            c.set(.react, duration: c.animationLength(for: .react) + 0.3)
            groveEvents.append(.berryPicked(i, by: c.id))
        case .bounce(let i):
            startGroveVisit(c, plot: i, task: .bounce)
        case .drink, .soak:
            arriveAtAmenity(c, t)
        case .home(let n):
            guard n < grove.village.count else { c.mining = false; return }
            // A Gremlet without a home claims the first free house it sleeps in.
            if !c.mining, grove.village[n].owner == nil, !grove.village[n].biome.hasPrefix("item:"), grove.village[n].biome != "mine",
               !grove.village.contains(where: { $0.owner == c.species.id }) {
                grove.village[n].owner = c.species.id
                groveEvents.append(.claimed(n, by: c.id))
            }
            c.homeUntil = c.mining ? clock + rng.range(6, 12) : clock + rng.range(isNight ? 60 : 25, isNight ? 180 : 70)
            if c.mining { adventureEvents.append(.digging(house: n)) }
            c.homeHouse = n
            c.set(.sleep, duration: 9999)
            groveEvents.append(.wentHome(n, by: c.id))
        case .dare(let i):
            // Made it past (or got snapped at on the way): a little cheer.
            if let f = groveFloor, grove.plants.indices.contains(i) { c.facing = grove.base(i, floor: f).x > c.pos.x ? 1 : -1 }
            c.set(.react, duration: c.animationLength(for: .react))
        case .hangingHome:
            goInsideHangingHome(c)
        case .nestHome:
            goInsideNest(c)
        case .basket:
            reachedBasket(c)
        case .pop(let i):
            guard grove.featured == i, grove.plants.indices.contains(i), let f = groveFloor else { return }
            let b = grove.base(i, floor: f)
            c.facing = b.x > c.pos.x ? 1 : -1
            groveEvents.append(.played(i, by: c.id))
            if grove.plants[i].kind == .leafpile {
                // A run and a dive into the leaves; after a few dives they're scattered.
                launch(c, velocity: ballistic(from: c.pos, toX: b.x, y: f.minY, apexExtra: 50))
                if rng.chance(0.3) { useUpCorner() }
            } else {
                // A big breath: the seeds float away.
                c.set(.special, duration: c.animationLength(for: .special))
                useUpCorner()
            }
        case .campfire(let i):
            if let f = groveFloor { c.facing = grove.base(i, floor: f).x > c.pos.x ? 1 : -1 }
            c.idleVariant = "idle"
            c.set(.idle, duration: rng.range(8, 16))
            c.campfire = true
        }
    }
}

/// Where a Gremlet is headed in the grove.
enum GroveVisit: Equatable { case snack(Int), campfire(Int), bounce(Int), home(Int), drink(Int), soak(Int), dare(Int), hangingHome, nestHome, pop(Int), basket }

extension World {
    /// A plant of this kind that's out right now (with one plant at a time, only the featured one is).
    func shownPlant(_ k: GroveKind) -> Int? {
        if let f = grove.featured { return grove.plants.indices.contains(f) && grove.plants[f].kind == k ? f : nil }
        return grove.plant(of: k)
    }

    /// The corner's day: a plant stays 8 to 15 minutes (a pop-up only 3 or 4), then the corner rests empty for a few
    /// minutes, then something else turns up. Timed on the wall clock (`now`), so restarting doesn't freeze it.
    func rotateGroveIfDue() {
        let t = now
        // The corner mode never shows every plant at once: no plant chosen means an empty corner.
        if grove.featured == nil { grove.featured = -1; rebuildGroveSurfaces(); setSurfacesDirty() }
        if cornerShownAt == 0 { cornerShownAt = t }   // (just started: give whatever's there its full four minutes)
        // A plant nobody has played with for four minutes doesn't wait out its time: it goes.
        if let f = grove.featured, f >= 0, !grove.plants[f].kind.brief, t - max(lastCornerUse, cornerShownAt) > 240 {
            grove.nextCornerChange = t
        }
        if let due = grove.nextCornerChange, t < due { return }
        if grove.featured == nil || grove.nextCornerChange == nil || grove.featured! >= 0 {
            if grove.featured != nil && grove.nextCornerChange != nil {
                // Time's up for this one: the corner rests.
                grove.featured = -1
                grove.nextCornerChange = t + rng.range(180, 480)
                rebuildGroveSurfaces(); setSurfacesDirty()
                groveEvents.append(.cornerCleared)
                return
            }
        }
        // Something new: a plant most of the time, now and then a quick pop-up.
        let current = lastCornerKind
        let plantsPool: [GroveKind] = [.bouncecap, .lanternbloom, .skyvine, .snapjaw, .wishwillow]
        let pool = rng.chance(0.35) ? [GroveKind.leafpile, .puffball] : plantsPool
        let options = pool.filter { $0 != current }
        let k = options[Int(rng.next() % UInt64(options.count))]
        let i: Int
        if let found = grove.plant(of: k) { i = found } else { grove.plants.append(GrovePlant(kind: k, x: 0.16)); i = grove.plants.count - 1 }
        grove.featured = i
        lastCornerKind = k
        cornerShownAt = t
        grove.nextCornerChange = t + (k.brief ? rng.range(180, 260) : rng.range(480, 900))
        rebuildGroveSurfaces()
        setSurfacesDirty()
        groveEvents.append(.planted(i))
    }

    /// A pop-up was played with and is used up (the leaves scattered, the seeds blown away): the corner rests.
    func useUpCorner() {
        grove.featured = -1
        grove.nextCornerChange = now + rng.range(180, 420)
        rebuildGroveSurfaces(); setSurfacesDirty()
    }

    /// `gremlet plant`: swap the corner plant now.
    public func rotateGroveNow() {
        // Straight to something new (skipping the empty spell).
        grove.featured = -1
        grove.nextCornerChange = nil
        rotateGroveIfDue()
    }
}

extension World {
    func startHomeVisit(_ c: Creature, house n: Int) {
        guard let f = groveFloor, n < grove.village.count else { return }
        let h = grove.village[n]
        // The door is at the middle of the house.
        c.targetX = (f.minX + h.x * f.w).clamped(f.minX + 20, f.maxX - 20)
        c.groveTask = .home(n)
        c.set(.walk, duration: 25)
    }
}
