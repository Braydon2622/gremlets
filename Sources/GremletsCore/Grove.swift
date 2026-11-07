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
/// | Lanternbloom | Glows after dark; Gremlets gather around it like a campfire. Lights up boss fights. |
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
        case .sunberry: return "berries for snacks and boss fights"
        case .bouncecap: return "a trampoline cap"
        case .lanternbloom: return "a night light Gremlets gather around"
        case .skyvine: return "leaf platforms up the screen"
        case .snapjaw: return "chomps bosses that fly too low"
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
    /// Tasks since the last boss (bosses come every so often as work gets done).
    public internal(set) var tasksSinceBoss = 0

    public static let maxPlots = 6
    /// Plot unlock schedule: total tasks needed for plot n (the first two are free).
    public static let unlockAt = [0, 0, 4, 10, 18, 30]
    /// Planting order, so every grove grows the same useful mix.
    static let order: [GroveKind] = [.sunberry, .bouncecap, .lanternbloom, .skyvine, .snapjaw, .wishwillow]
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
        Vec2(floor.minX + plants[i].x * floor.w, floor.minY)
    }

    /// Size of the drawn plant (points). The platform layer draws it centered on `base` x, sitting on the floor.
    public func size(_ i: Int) -> Vec2 {
        let p = plants[i], s = p.scale
        switch p.kind {
        case .bouncecap: return Vec2(54 * s, 46 * s)
        case .skyvine: return Vec2(60 * s, 110 * s)
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
                // Leaves alternate sides every 62pt up the stalk.
                let leaves = max(1, Int((sz.y - 40) / 62))
                for n in 0..<leaves {
                    let y = b.y + 52 + Double(n) * 62
                    let side: Double = n % 2 == 0 ? -1 : 1
                    let cx = b.x + side * 20
                    out.append(GroveLedge(plot: i, y: y, minX: cx - 24, maxX: cx + 24, bouncy: false))
                }
                out.append(GroveLedge(plot: i, y: b.y + sz.y - 6, minX: b.x - 26, maxX: b.x + 26, bouncy: false))
            case .wishwillow:
                out.append(GroveLedge(plot: i, y: b.y + sz.y * 0.55, minX: b.x - sz.x * 0.46, maxX: b.x - sz.x * 0.08, bouncy: false))
                out.append(GroveLedge(plot: i, y: b.y + sz.y * 0.78, minX: b.x + sz.x * 0.06, maxX: b.x + sz.x * 0.42, bouncy: false))
            case .lanternbloom, .snapjaw:
                break
            }
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
    }

    /// Replaces the grove (loaded from disk) and plants anything already unlocked.
    public func loadGrove(_ g: Grove) {
        grove = g
        for i in grove.fillPlots() { groveEvents.append(.planted(i)) }
        rebuildGroveSurfaces()
        setSurfacesDirty()
    }

    /// Claude finished a task: every grove plant soaks up a spark, new plots unlock, berries grow, and every so
    /// often a boss shows up. Returns plants that levelled up.
    @discardableResult
    public func feedGrove(sparks: Double = 1) -> [Int] {
        grove.tasks += 1
        grove.tasksSinceBoss += 1
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
        groveEvents.append(.fed(tasks: grove.tasks))
        rebuildGroveSurfaces()
        setSurfacesDirty()
        if !ups.isEmpty, ups.contains(where: { grove.plants[$0].level == 5 }) { requestEvent(.festival) }
        return ups
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
        if let i = grove.plant(of: .sunberry), grove.plants[i].berries > 0, c.energy < 0.8 || c.heldBerry == false {
            add("snack", 0.9 * (1.2 - c.energy)) { self.startGroveVisit(c, plot: i, task: .snack) }
        }
        if let i = grove.plant(of: .bouncecap) {
            add("bounce", 0.5 * (0.3 + c.energy)) { self.startGroveVisit(c, plot: i, task: .bounce) }
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
            c.heldBerry = true
            c.facing = grove.base(i, floor: groveFloor ?? Rect(x: 0, y: 0, w: 1, h: 1)).x > c.pos.x ? 1 : -1
            c.set(.react, duration: c.animationLength(for: .react) + 0.3)
            groveEvents.append(.berryPicked(i, by: c.id))
        case .bounce(let i):
            startGroveVisit(c, plot: i, task: .bounce)
        case .campfire(let i):
            if let f = groveFloor { c.facing = grove.base(i, floor: f).x > c.pos.x ? 1 : -1 }
            c.idleVariant = "idle"
            c.set(.idle, duration: rng.range(8, 16))
            c.campfire = true
        }
    }
}

/// Where a Gremlet is headed in the grove.
enum GroveVisit: Equatable { case snack(Int), campfire(Int), bounce(Int) }
