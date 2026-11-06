/// Window-box gardening. Each gardening job has a planter with three spots. The Gremlet plants seeds, waters
/// whatever is getting dry, shoos off bugs and pulls weeds; plants grow through five stages while it tends them
/// (faster during a focus session, barely at all while you're away) and are harvested once they've all bloomed.
public enum PlantKind: String, CaseIterable, Codable, Sendable {
    case tulip, daisy, strawberry, carrot, tomato, cactus, sunflower, mushroom

    public var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// 0 common, 1 uncommon, 2 rare.
    public var rarity: Int {
        switch self {
        case .tulip, .daisy, .carrot: return 0
        case .strawberry, .tomato, .cactus: return 1
        case .sunflower, .mushroom: return 2
        }
    }

    public var rarityName: String { ["common", "uncommon", "rare"][rarity] }

    /// Seconds of tending (well watered, no bugs, you at your Mac) from seed to bloom.
    public var growTime: Double { [150.0, 200.0, 280.0][rarity] }

    /// Vegetables and fruit get picked; flowers are cut for the garden.
    public var isProduce: Bool { [.strawberry, .carrot, .tomato].contains(self) }
}

public struct Plant: Equatable, Sendable {
    public var kind: PlantKind
    /// 0 = just planted ... 1 = in bloom / ripe.
    public var growth: Double = 0
    /// 1 = just watered ... 0 = bone dry.
    public var water: Double = 0.6
    /// A little aphid nibbling on it (slows growth until shooed).
    public var bug = false
    var bugSince = 0.0

    /// 0 seed, 1 sprout, 2 young plant, 3 bud, 4 bloom.
    public var stage: Int { growth >= 1 ? 4 : growth >= 0.6 ? 3 : growth >= 0.33 ? 2 : growth >= 0.1 ? 1 : 0 }
    public var isThirsty: Bool { water < 0.2 }
}

/// What the gardener just did, for the platform layer's little effects.
public enum GardenAction: Equatable, Sendable {
    case plant(Int), water(Int), shoo(Int), weed(Int), bloom(Int), harvest
}

public final class GardenBox {
    public static let slots = 3
    public internal(set) var plants: [Plant?] = Array(repeating: nil, count: GardenBox.slots)
    public internal(set) var lastAction: GardenAction?
    /// Kinds that bloomed in this box (in order), for the seed book and the keepsake garden.
    public internal(set) var bloomed: [PlantKind] = []

    public var planted: [Plant] { plants.compactMap { $0 } }
    public var allBloomed: Bool { plants.allSatisfy { ($0?.growth ?? 0) >= 1 } }
    /// Average growth of all three spots.
    public var progress: Double { plants.reduce(0) { $0 + min(1, $1?.growth ?? 0) } / Double(GardenBox.slots) }
}

extension World {

    /// Picks a seed: mostly common, sometimes uncommon, now and then rare. Focus sessions and Claude jobs make rare
    /// seeds a little more likely.
    func pickSeed(boost: Bool) -> PlantKind {
        let roll = rng.range(0, 1)
        let rare = boost ? 0.16 : 0.08, uncommon = boost ? 0.36 : 0.30
        let tier = roll < rare ? 2 : roll < rare + uncommon ? 1 : 0
        let options = PlantKind.allCases.filter { $0.rarity == tier }
        return options[Int(rng.next() % UInt64(options.count))]
    }

    /// Grows the plants a little (called every tick while the Gremlet is working, or dozing beside its box).
    func growGarden(_ j: Job, _ dt: Double, tending: Bool) {
        let g = j.garden
        let claude = j.kind == .claude
        let pace = (userActive || claude ? 1.0 : 0.12) * (calm ? 1.6 : 1.0) * (tending ? 1.0 : 0.5)
        for i in g.plants.indices {
            guard var p = g.plants[i] else { continue }
            let before = p.stage
            p.water = max(0, p.water - dt / (userActive ? 80 : 400))
            if p.growth < 1 {
                let thirst = p.water > 0.12 ? 1.0 : 0.25
                let bugged = p.bug ? 0.4 : 1.0
                p.growth += dt / p.kind.growTime * pace * thirst * bugged
                // Claude jobs bloom when Claude is done, not before.
                p.growth = min(claude && j.phase != .finished ? 0.95 : 1, p.growth)
            }
            if !p.bug && p.growth > 0.25 && p.growth < 1 && userActive && rng.chance(dt * 0.006) {
                p.bug = true; p.bugSince = clock
            }
            if p.stage == 4 && before < 4 {
                g.bloomed.append(p.kind)
                g.lastAction = .bloom(i)
                j.beats += 1
            }
            g.plants[i] = p
        }
    }

    /// The gardener's next chore: plant an empty spot, shoo a bug (after giving you a few seconds to do it),
    /// water the driest plant, or pull a weed. Returns false when there's nothing to do.
    @discardableResult
    func doGardenChore(_ j: Job) -> Bool {
        let g = j.garden
        if let empty = g.plants.firstIndex(where: { $0 == nil }) {
            g.plants[empty] = Plant(kind: pickSeed(boost: calm || j.kind == .claude))
            g.lastAction = .plant(empty)
        } else if let b = g.plants.indices.first(where: { g.plants[$0]?.bug == true && clock - (g.plants[$0]?.bugSince ?? 0) > 6 }) {
            g.plants[b]?.bug = false
            g.lastAction = .shoo(b)
        } else if let dry = g.plants.indices.filter({ (g.plants[$0]?.water ?? 1) < 0.45 && (g.plants[$0]?.growth ?? 1) < 1 })
                    .min(by: { (g.plants[$0]?.water ?? 1) < (g.plants[$1]?.water ?? 1) }) {
            g.plants[dry]?.water = 1
            g.lastAction = .water(dry)
        } else if let growing = g.plants.indices.filter({ (g.plants[$0]?.growth ?? 1) < 1 }).randomElement(using: &rng), rng.chance(0.5) {
            g.plants[growing]?.growth += 0.02
            g.lastAction = .weed(growing)
        } else {
            return false
        }
        j.beats += 1
        return true
    }

    /// You clicked the window box: shoo a bug if there is one, otherwise water the driest plant.
    /// Returns what happened (nil if there was nothing to do).
    @discardableResult
    public func helpGarden(workerID: Int) -> GardenAction? {
        guard let c = creature(id: workerID), let j = c.job, j.phase == .working else { return nil }
        let g = j.garden
        var did: GardenAction?
        if let b = g.plants.indices.first(where: { g.plants[$0]?.bug == true }) {
            g.plants[b]?.bug = false; did = .shoo(b)
        } else if let dry = g.plants.indices.filter({ g.plants[$0] != nil && (g.plants[$0]?.growth ?? 1) < 1 })
                    .min(by: { (g.plants[$0]?.water ?? 1) < (g.plants[$1]?.water ?? 1) }) {
            g.plants[dry]?.water = 1
            g.plants[dry]?.growth += 0.04
            did = .water(dry)
        }
        guard let did else { return nil }
        g.lastAction = did
        j.beats += 1
        if c.isGrounded && !c.isDozingAtWork { c.set(.pet, duration: 1.2); emit(.petted(c.id)) }
        return did
    }
}
