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

    public var name: String {
        switch self {
        case .sunberry: return "Sunberry"
        case .bouncecap: return "Bouncecap"
        case .lanternbloom: return "Lanternbloom"
        case .skyvine: return "Skyvine"
        case .snapjaw: return "Snapjaw"
        case .wishwillow: return "Wishwillow"
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
        }
    }

    /// Bigger plants need more sparks per level.
    public var cost: Double {
        switch self {
        case .sunberry, .bouncecap: return 1
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

    enum CodingKeys: String, CodingKey { case plants, tasks, village, digCharges, gems, todayKey, todayTasks, festivalDone }
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
    }

    public static let maxPlots = 6
    /// Plot unlock schedule: total tasks needed for plot n (the first two are free).
    public static let unlockAt = [0, 0, 4, 10, 18, 30]
    /// Planting order, so every grove grows the same useful mix.
    static let order: [GroveKind] = [.sunberry, .bouncecap, .lanternbloom, .skyvine, .snapjaw, .wishwillow]
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
        }
    }
    static let slots: [Double] = [0.16, 0.30, 0.44, 0.58, 0.72, 0.86]

    public init() {}

    public var unlockedPlots: Int { Grove.unlockAt.filter { tasks >= $0 }.count }
    public var nextUnlock: Int? { Grove.unlockAt.first { $0 > tasks } }

    /// Plants anything newly unlocked. Returns the new plants' indices.
    @discardableResult
    func fillPlots() -> [Int] {
        var added: [Int] = []
        while plants.count < unlockedPlots {
            let k = Grove.order[plants.count]
            plants.append(GrovePlant(kind: k, x: Grove.slots[plants.count]))
            added.append(plants.count - 1)
        }
        return added
    }

    public func plant(of kind: GroveKind) -> Int? { plants.firstIndex { $0.kind == kind } }

    // MARK: Geometry (global points, y-up)

    /// Where a plot sits on the floor of the main screen.
    public func base(_ i: Int, floor: Rect) -> Vec2 {
        Vec2(floor.minX + Grove.offset(plants[i].kind), floor.minY)
    }

    /// Size of the drawn plant (points). The platform layer draws it centered on `base` x, sitting on the floor.
    public func size(_ i: Int) -> Vec2 {
        let p = plants[i], s = p.scale
        switch p.kind {
        case .bouncecap: return Vec2(54 * s, 46 * s)
        case .skyvine: return Vec2(84, 96 + 124 * Double(p.level - 1))
        case .lanternbloom: return Vec2(34 * s, 56 * s)
        case .sunberry: return Vec2(52 * s, 30 * s)
        case .snapjaw: return Vec2(40 * s, 44 * s)
        case .wishwillow: return Vec2(90 * s, 96 * s)
        }
    }

    /// Platforms the grove offers on a screen floor.
    public func ledges(floor: Rect) -> [GroveLedge] {
        var out: [GroveLedge] = []
        for i in plants.indices {
            let b = base(i, floor: floor), sz = size(i), p = plants[i]
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
            case .lanternbloom, .snapjaw:
                break
            }
        }
        // Village roofs (plot = -1 - house index): the ridge, the dome, the terrace, wherever the picture has a spot.
        for (n, h) in village.enumerated() where h.biome != "item:spring" && h.biome != "item:lamps" {
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
        groveLedges = grove.ledges(floor: f)
        groveSurfaces = groveLedges.enumerated().map { n, l in
            Surface(ownerID: World.groveOwner(n), kind: .plant, y: l.y, minX: l.minX, maxX: l.maxX)
        }
        // The grove plants are what the Gremlets go and water.
        gardenSpots = grove.plants.indices.map { grove.base($0, floor: f).x }
    }

    /// Replaces the grove (loaded from disk) and plants anything already unlocked.
    public func loadGrove(_ g: Grove) {
        grove = g
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
        guard let f = groveFloor, let i = grove.plant(of: .snapjaw) else { return }
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
        return true
    }

    /// Wishwillow: one wish a day from level 3. Call once a minute or so.
    public func checkWishwillow(day: Int) {
        guard let i = grove.plant(of: .wishwillow), grove.plants[i].level >= 3, grove.plants[i].lastWishDay != day else { return }
        grove.plants[i].lastWishDay = day
        makeWish()
        groveEvents.append(.wish(i))
    }

    /// Grove choices for the brain: snack on a sunberry, go bounce on the bouncecap, sit by the lantern at night.
    func groveChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard let f = groveFloor, c.job == nil, !grove.plants.isEmpty else { return }
        // Only Gremlets on (or near) the main screen's floor go to the grove.
        guard abs(c.pos.y - f.minY) < 4, c.pos.x >= f.minX, c.pos.x <= f.maxX else { return }
        if let i = grove.plant(of: .sunberry), grove.plants[i].berries > 0, c.energy < 0.8 {
            add("snack", 0.9 * (1.2 - c.energy)) { self.startGroveVisit(c, plot: i, task: .snack) }
        }
        if let i = grove.plant(of: .bouncecap) {
            add("bounce", 0.5 * (0.3 + c.energy)) { self.startGroveVisit(c, plot: i, task: .bounce) }
        }
        // Bedtime (or just tired): walk home to a house in the village and sleep inside.
        if let m = mineIndex, !creatures.contains(where: { $0.mining }) {
            add("dig", grove.digCharges > 0 ? 1.3 : 0.12) { self.startDig(c); _ = m }
        }
        let sleepingIn = creatures.filter { $0.homeHouse != nil }.count
        if !grove.village.isEmpty, isNight || c.energy < 0.35, sleepingIn < grove.village.count * 2 {
            // Its own house if it has one, otherwise any house (not the mine or the village amenities).
            let homes = grove.village.indices.filter { !grove.village[$0].biome.hasPrefix("item:") && grove.village[$0].biome != "mine" }
            if let n = grove.village.firstIndex(where: { $0.owner == c.species.id }) ?? (homes.isEmpty ? nil : homes[Int(rng.next() % UInt64(homes.count))]) {
                add("goHome", isNight ? 1.3 : 0.8) { self.startHomeVisit(c, house: n) }
            }
        }
        if isNight, let i = grove.plant(of: .lanternbloom) {
            add("campfire", 1.1) { self.startGroveVisit(c, plot: i, task: .campfire) }
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
        case .campfire(let i):
            if let f = groveFloor { c.facing = grove.base(i, floor: f).x > c.pos.x ? 1 : -1 }
            c.idleVariant = "idle"
            c.set(.idle, duration: rng.range(8, 16))
            c.campfire = true
        }
    }
}

/// Where a Gremlet is headed in the grove.
enum GroveVisit: Equatable { case snack(Int), campfire(Int), bounce(Int), home(Int), drink(Int), soak(Int) }

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
