/// Window-box gardening. Each gardening job has a planter with three spots. The Gremlet plants seeds, waters
/// whatever is getting dry, shoos off bugs and pulls weeds; plants grow through five stages while it tends them
/// (faster during a focus session, barely at all while you're away) and are harvested once they've all bloomed.
///
/// There's more to find than tulips: five rarity tiers, seasonal and night-only plants, legendary giants that fill the
/// whole box, golden plants, rain showers, helpful ladybugs, wishes on shooting stars and a mystery seed or two.
public enum PlantKind: String, CaseIterable, Codable, Sendable {
    // Common
    case tulip, daisy, carrot, lavender
    // Uncommon
    case strawberry, tomato, cactus, bluebell
    // Rare (cherry blossom in spring, frostbell in winter)
    case sunflower, mushroom, cherryBlossom, frostbell
    // Epic (moonflower only at night)
    case moonflower, crystalRose
    // Legendary giants: fill the whole window box
    case giantPumpkin, wishingTree

    public var name: String {
        switch self {
        case .cherryBlossom: return "Cherry blossom"
        case .crystalRose: return "Crystal rose"
        case .giantPumpkin: return "Giant pumpkin"
        case .wishingTree: return "Wishing tree"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// 0 common, 1 uncommon, 2 rare, 3 epic, 4 legendary.
    public var rarity: Int {
        switch self {
        case .tulip, .daisy, .carrot, .lavender: return 0
        case .strawberry, .tomato, .cactus, .bluebell: return 1
        case .sunflower, .mushroom, .cherryBlossom, .frostbell: return 2
        case .moonflower, .crystalRose: return 3
        case .giantPumpkin, .wishingTree: return 4
        }
    }

    public static let rarityNames = ["common", "uncommon", "rare", "epic", "legendary"]
    public var rarityName: String { PlantKind.rarityNames[rarity] }

    /// Takes up all three spots in the window box.
    public var isGiant: Bool { rarity == 4 }

    /// Seconds of tending (well watered, no bugs, you at your Mac) from seed to bloom.
    public var growTime: Double { [150.0, 200.0, 280.0, 340.0, 420.0][rarity] }

    /// Vegetables and fruit get picked; flowers are cut for the garden.
    public var isProduce: Bool { [.strawberry, .carrot, .tomato, .giantPumpkin].contains(self) }

    /// Months (1-12) it can be planted, or nil for all year.
    public var season: Set<Int>? {
        switch self {
        case .cherryBlossom: return [3, 4, 5]
        case .frostbell: return [12, 1, 2]
        default: return nil
        }
    }

    public var seasonName: String? {
        switch self {
        case .cherryBlossom: return "spring"
        case .frostbell: return "winter"
        case .moonflower: return "night"
        default: return nil
        }
    }

    /// Only planted after dark.
    public var nightOnly: Bool { self == .moonflower }
}

public struct Plant: Equatable, Sendable {
    public var kind: PlantKind
    /// 0 = just planted ... 1 = in bloom / ripe.
    public var growth: Double = 0
    /// 1 = just watered ... 0 = bone dry.
    public var water: Double = 0.6
    /// A little aphid nibbling on it (slows growth until shooed).
    public var bug = false
    /// A rare golden plant: same kind, all gold, sparkles.
    public var golden = false
    var bugSince = 0.0

    public init(kind: PlantKind, golden: Bool = false) { self.kind = kind; self.golden = golden }

    /// 0 seed, 1 sprout, 2 young plant, 3 bud, 4 bloom.
    public var stage: Int { growth >= 1 ? 4 : growth >= 0.6 ? 3 : growth >= 0.33 ? 2 : growth >= 0.1 ? 1 : 0 }
    public var isThirsty: Bool { water < 0.2 }
    public var isSpecial: Bool { golden || kind.rarity >= 3 }
}

/// What just happened in a window box, for the platform layer's little effects.
public enum GardenAction: Equatable, Sendable {
    case plant(Int), water(Int), shoo(Int), weed(Int), bloom(Int), harvest
    /// A passing rain cloud watered everything.
    case rain
    /// A ladybug flew in and ate the aphid.
    case ladybug(Int)
    /// The gardener found a mystery seed and planted it.
    case mystery(Int)
}

public final class GardenBox {
    public static let slots = 3
    public internal(set) var plants: [Plant?] = Array(repeating: nil, count: GardenBox.slots)
    public internal(set) var lastAction: GardenAction?
    /// Plants that bloomed in this box (in order), for the seed book and the keepsake garden.
    public internal(set) var bloomed: [Plant] = []
    /// One legendary plant filling the whole box (kept in the middle spot).
    public var giant: Plant? { plants[1].flatMap { $0.kind.isGiant ? $0 : nil } }

    public var planted: [Plant] { giant.map { [$0] } ?? plants.compactMap { $0 } }
    public var allBloomed: Bool { giant.map { $0.growth >= 1 } ?? plants.allSatisfy { ($0?.growth ?? 0) >= 1 } }
    /// How far along the box is (0...1).
    public var progress: Double {
        if let g = giant { return min(1, g.growth) }
        return plants.reduce(0) { $0 + min(1, $1?.growth ?? 0) } / Double(GardenBox.slots)
    }
    /// Spots the gardener works on: just the middle one for a giant.
    var activeSlots: [Int] { giant != nil ? [1] : Array(plants.indices) }
}

extension World {

    /// Picks a seed by rarity: mostly common, sometimes uncommon, now and then rare, rarely epic, very rarely a
    /// legendary giant (only for an empty box). Focus sessions and Claude jobs tilt the odds; a wish (shooting star,
    /// mystery seed) guarantees epic or better. Seasonal and night-only plants only turn up at the right time.
    func pickSeed(boost: Bool, emptyBox: Bool = false) -> Plant {
        var tier: Int
        if wishes > 0 {
            wishes -= 1
            tier = emptyBox && rng.chance(0.45) ? 4 : 3
        } else {
            let roll = rng.range(0, 1)
            let odds: [Double] = boost ? [0.03, 0.06, 0.16, 0.36] : [0.012, 0.03, 0.09, 0.30]   // legendary, epic, rare, uncommon
            tier = roll < odds[0] ? 4 : roll < odds[0] + odds[1] ? 3 : roll < odds[0] + odds[1] + odds[2] ? 2
                : roll < odds[0] + odds[1] + odds[2] + odds[3] ? 1 : 0
            if tier == 4 && !emptyBox { tier = 3 }
        }
        var options = PlantKind.allCases.filter { k in
            k.rarity == tier && (k.season?.contains(month) ?? true) && (!k.nightOnly || isNight)
        }
        if options.isEmpty { options = PlantKind.allCases.filter { $0.rarity == tier && $0.season == nil && !$0.nightOnly } }
        var kind = options[Int(rng.next() % UInt64(options.count))]
        // Pumpkin season.
        if tier == 4 && [9, 10, 11].contains(month) && rng.chance(0.6) { kind = .giantPumpkin }
        let golden = rng.chance(boost ? 1.0 / 25 : 1.0 / 40)
        return Plant(kind: kind, golden: golden)
    }

    /// Grows the plants a little (called every tick while the Gremlet is working, or dozing beside its box).
    func growGarden(_ j: Job, _ dt: Double, tending: Bool) {
        let g = j.garden
        let claude = j.kind == .claude
        let pace = (userActive || claude ? 1.0 : 0.12) * (calm ? 1.6 : 1.0) * (tending ? 1.0 : 0.5)
        for i in g.activeSlots {
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
                g.bloomed.append(p)
                g.lastAction = .bloom(i)
                j.beats += 1
            }
            g.plants[i] = p
        }
        // Now and then a little rain cloud drifts over a box while you're working.
        if userActive && rng.chance(dt / 700) && !g.planted.isEmpty && !g.allBloomed {
            rainOn(j)
        }
    }

    /// A passing shower: everything watered, everything a little further along.
    func rainOn(_ j: Job) {
        let g = j.garden
        for i in g.activeSlots where g.plants[i] != nil {
            g.plants[i]?.water = 1
            if (g.plants[i]?.growth ?? 1) < 0.95 { g.plants[i]?.growth += 0.03 }
        }
        g.lastAction = .rain
        j.beats += 1
    }

    /// The gardener's next chore: plant an empty spot, shoo a bug (after giving you a few seconds to do it, and
    /// sometimes a ladybug beats it to it), water the driest plant, or pull a weed. Returns false when there's nothing to do.
    @discardableResult
    func doGardenChore(_ j: Job) -> Bool {
        let g = j.garden
        let boost = calm || j.kind == .claude
        if g.giant == nil, let empty = g.plants.firstIndex(where: { $0 == nil }) {
            let seed = pickSeed(boost: boost, emptyBox: g.plants.allSatisfy { $0 == nil })
            if seed.kind.isGiant {
                g.plants = [nil, seed, nil]
                g.lastAction = .plant(1)
            } else {
                g.plants[empty] = seed
                g.lastAction = .plant(empty)
            }
        } else if let b = g.activeSlots.first(where: { g.plants[$0]?.bug == true && clock - (g.plants[$0]?.bugSince ?? 0) > 6 }) {
            g.plants[b]?.bug = false
            g.lastAction = rng.chance(0.3) ? .ladybug(b) : .shoo(b)
        } else if let dry = g.activeSlots.filter({ (g.plants[$0]?.water ?? 1) < 0.45 && (g.plants[$0]?.growth ?? 1) < 1 })
                    .min(by: { (g.plants[$0]?.water ?? 1) < (g.plants[$1]?.water ?? 1) }) {
            g.plants[dry]?.water = 1
            g.lastAction = .water(dry)
        } else if let growing = g.activeSlots.filter({ (g.plants[$0]?.growth ?? 1) < 1 }).randomElement(using: &rng), rng.chance(0.5) {
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
        if let b = g.activeSlots.first(where: { g.plants[$0]?.bug == true }) {
            g.plants[b]?.bug = false; did = .shoo(b)
        } else if let dry = g.activeSlots.filter({ g.plants[$0] != nil && (g.plants[$0]?.growth ?? 1) < 1 })
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

    /// A wish (a shooting star, or `gremlet wish`): the next seed planted anywhere is epic or better.
    public func makeWish() { wishes = min(3, wishes + 1) }

    /// Easter egg: poke a gardening Gremlet five times in a row and it digs up a mystery seed, swapping it in for its
    /// least-grown seedling (or saving the luck for the next box if everything's already well along).
    func countPokeForMystery(_ c: Creature) {
        guard let j = c.job, j.phase == .working else { c.pokeStreak = 0; return }
        if clock - c.lastPoke > 1.2 { c.pokeStreak = 0 }
        c.lastPoke = clock
        c.pokeStreak += 1
        guard c.pokeStreak >= 5 else { return }
        c.pokeStreak = 0
        let g = j.garden
        if g.giant == nil, let i = g.plants.indices.filter({ (g.plants[$0]?.growth ?? 0) < 0.3 })
            .min(by: { (g.plants[$0]?.growth ?? 0) < (g.plants[$1]?.growth ?? 0) }) {
            wishes += 1
            var seed = pickSeed(boost: true)
            if seed.kind.isGiant { seed = Plant(kind: .crystalRose, golden: seed.golden) }
            g.plants[i] = seed
            g.lastAction = .mystery(i)
        } else {
            makeWish()
            g.lastAction = .mystery(1)
        }
        j.beats += 1
        c.set(.react, duration: c.animationLength(for: .react) + 0.2)
        emit(.alert(c.id))
    }
}
