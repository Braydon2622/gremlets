import Foundation

/// Gems become things for the village. Every so often a traveling merchant (a hooded wanderer with a towering
/// backpack) walks in along the bottom of the screen, stops in the village for a while, and trades the gems your
/// Gremlets dug up for something new. Each piece is useful to the Gremlets, not just decoration:
///
/// | Item | Cost | What it does |
/// |---|---|---|
/// | Lamp posts | 3 amber | light the village after dark |
/// | Stone well | 2 emerald, 2 amber | thirsty Gremlets stop for a drink (energy) |
/// | Hot spring | 2 sapphire, 3 amber | tired Gremlets soak in the steam (lots of energy) |
/// | Windmill | 2 amethyst, 1 emerald | turns in the wind; its roof is a lookout to stand on |
/// | Flower arch | 1 starstone | the village gate, glowing at night |
public enum VillageItem: String, CaseIterable, Sendable {
    case lamps, well, spring, windmill, arch

    public var name: String {
        switch self {
        case .lamps: return "Lamp posts"
        case .well: return "Stone well"
        case .spring: return "Hot spring"
        case .windmill: return "Windmill"
        case .arch: return "Flower arch"
        }
    }

    public var cost: [GemKind: Int] {
        switch self {
        case .lamps: return [.amber: 3]
        case .well: return [.emerald: 2, .amber: 2]
        case .spring: return [.sapphire: 2, .amber: 3]
        case .windmill: return [.amethyst: 2, .emerald: 1]
        case .arch: return [.starstone: 1]
        }
    }

    /// Drawn size in points.
    public var size: Vec2 {
        switch self {
        case .lamps: return Vec2(150, 60)
        case .well: return Vec2(66, 72)
        case .spring: return Vec2(120, 36)
        case .windmill: return Vec2(78, 150)
        case .arch: return Vec2(90, 96)
        }
    }

    public var houseKey: String { "item:" + rawValue }
}

public struct Merchant: Sendable {
    public enum Phase: Sendable { case arriving, trading, leaving }
    public internal(set) var x: Double
    public internal(set) var phase: Phase = .arriving
    public internal(set) var facing: Double
    var target: Double
    var until = 0.0
    public internal(set) var sold: VillageItem?
}

public enum MerchantEvent: Equatable, Sendable {
    case arrived, sold(VillageItem), left
    case drink(Int), soak(Int)
}

extension World {
    public func owns(_ item: VillageItem) -> Bool { grove.village.contains { $0.biome == item.houseKey } }

    public func canAfford(_ item: VillageItem) -> Bool {
        item.cost.allSatisfy { (grove.gems[$0.key.rawValue] ?? 0) >= $0.value }
    }

    /// What the merchant would sell right now (the first thing you don't have and can afford).
    public var nextPurchase: VillageItem? { VillageItem.allCases.first { !owns($0) && canAfford($0) } }

    /// Brings the merchant in (on its own every ~25 minutes once there's something to buy).
    @discardableResult
    public func callMerchant() -> Bool {
        guard merchant == nil, let f = groveFloor else { return false }
        let fromLeft = (Int(clock) / 7) % 2 == 0
        let stop = f.minX + f.w * (fromLeft ? 0.3 : 0.7)
        merchant = Merchant(x: fromLeft ? f.minX - 60 : f.maxX + 60, facing: fromLeft ? 1 : -1, target: stop)
        merchantEvents.append(.arrived)
        return true
    }

    func updateMerchant(_ dt: Double) {
        if merchant == nil {
            if nextMerchantAt == nil { nextMerchantAt = clock + 1500 }
            if let t = nextMerchantAt, clock > t, nextPurchase != nil, eventsAllowed, !calm, userActive, villageOn, !compact {
                nextMerchantAt = clock + 1500
                callMerchant()
            }
        }
        guard var m = merchant, let f = groveFloor else { return }
        switch m.phase {
        case .arriving:
            let d = m.target - m.x
            if abs(d) < 2 {
                m.phase = .trading
                m.until = clock + 35
                // Gremlets nearby come over to see.
                for c in creatures where c.job == nil && c.isGrounded && abs(c.pos.y - f.minY) < 4 && abs(c.pos.x - m.x) < 500 && c.play == nil && c.groveTask == nil {
                    c.facing = m.x > c.pos.x ? 1 : -1
                    c.set(.walk, duration: abs(m.x - c.pos.x) / max(1, c.species.walkSpeed) * 0.7)
                }
            } else {
                m.x += (d > 0 ? 1 : -1) * min(abs(d), 46 * dt)
            }
        case .trading:
            if m.sold == nil && clock > m.until - 25, let item = nextPurchase {
                buy(item)
                m.sold = item
            }
            if clock > m.until {
                m.phase = .leaving
                m.facing = m.x < f.minX + f.w / 2 ? -1 : 1
                m.target = m.facing > 0 ? f.maxX + 80 : f.minX - 80
            }
        case .leaving:
            let d = m.target - m.x
            if abs(d) < 2 { merchant = nil; merchantEvents.append(.left); return }
            m.x += (d > 0 ? 1 : -1) * min(abs(d), 52 * dt)
        }
        merchant = m
    }

    func buy(_ item: VillageItem) {
        for (g, n) in item.cost { grove.gems[g.rawValue, default: 0] -= n }
        addHouse(biome: item.houseKey, blocks: 1, size: item.size, project: nil, day: nil, builtAt: Date().timeIntervalSince1970)
        merchantEvents.append(.sold(item))
    }

    /// Village amenities in the brain: a drink at the well, a soak in the hot spring.
    func villageChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard villageOn, let f = groveFloor, abs(c.pos.y - f.minY) < 4, c.job == nil else { return }
        if let n = grove.village.firstIndex(where: { $0.biome == VillageItem.well.houseKey }), c.energy < 0.85 {
            add("drink", 0.7) { self.startAmenity(c, house: n, kind: .drink) }
        }
        if let n = grove.village.firstIndex(where: { $0.biome == VillageItem.spring.houseKey }), c.energy < 0.6 {
            add("soak", 1.2) { self.startAmenity(c, house: n, kind: .soak) }
        }
    }

    enum Amenity { case drink, soak }

    func startAmenity(_ c: Creature, house n: Int, kind: Amenity) {
        guard let f = groveFloor, n < grove.village.count else { return }
        let h = grove.village[n]
        let cx = f.minX + h.x * f.w
        c.targetX = kind == .soak ? cx + rng.range(-h.w * 0.3, h.w * 0.3) : cx + (c.pos.x < cx ? -1 : 1) * (h.w * 0.5 + 6)
        c.groveTask = kind == .soak ? .soak(n) : .drink(n)
        c.set(.walk, duration: 25)
    }

    func arriveAtAmenity(_ c: Creature, _ v: GroveVisit) {
        switch v {
        case .drink:
            c.energy = min(1, c.energy + 0.25)
            c.set(.react, duration: c.animationLength(for: .react) + 0.4)
            merchantEvents.append(.drink(c.id))
        case .soak:
            c.energy = min(1, c.energy + 0.6)
            c.set(.pet, duration: rng.range(6, 10))   // the blissful wiggle
            merchantEvents.append(.soak(c.id))
        default: break
        }
    }

    public func drainMerchantEvents() -> [MerchantEvent] {
        defer { merchantEvents.removeAll() }
        return merchantEvents
    }
}
