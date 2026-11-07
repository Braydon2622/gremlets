import Foundation

/// Three bits of world to explore, Terraria style:
///
/// - **The mine:** once the grove has a few plots, a little mine opens in the village. Gremlets go in with a pickaxe
///   (you hear the digging: dust puffs from the entrance) and come out with what they found. Every Claude task you
///   finish earns a dig: those trips turn up gems (amber, emerald, sapphire, amethyst, and rarely a starstone).
/// - **The sky ferry:** now and then a little flying boat drifts in, docks beside a high window for a while, and
///   carries any Gremlets who hop aboard over to another window before it sails off.
/// - **The lantern festival:** on evenings after a good day's work, paper lanterns rise from the village, one for each
///   Claude task you finished that day.
public enum GemKind: String, CaseIterable, Codable, Sendable {
    case amber, emerald, sapphire, amethyst, starstone

    public var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum AdventureEvent: Equatable, Sendable {
    case digging(house: Int)
    case gemFound(GemKind, by: Int)
    case pebble(by: Int)
    case ferryArrived
    case ferryLeft
}

/// The sky ferry: a little flying boat with a deck Gremlets can stand on.
public struct Ferry: Sendable {
    public enum Phase: Sendable { case arriving, docked, crossing, leaving }
    public internal(set) var pos: Vec2
    public internal(set) var phase: Phase = .arriving
    public internal(set) var facing = 1.0
    var target: Vec2
    var dockedUntil = 0.0
    var stops = 0
    var prev: Vec2
    public static let deckWidth = 120.0
    /// Deck height above `pos` (pos is the bottom of the hull).
    public static let deckHeight = 26.0
    public var deckY: Double { pos.y + Ferry.deckHeight }
}

extension World {
    static let ferryOwner = -480_000

    // MARK: Mine

    public var mineIndex: Int? { grove.village.firstIndex { $0.biome == "mine" } }

    /// Opens the mine once the grove has at least three plots.
    func openMineIfReady() {
        guard mineIndex == nil, grove.plants.count >= 3 else { return }
        addHouse(biome: "mine", blocks: 1, size: Vec2(120, 66), project: nil, day: nil, builtAt: Date().timeIntervalSince1970)
    }

    func startDig(_ c: Creature) {
        guard let n = mineIndex else { return }
        c.mining = true
        startHomeVisit(c, house: n)
    }

    /// Called when a Gremlet comes back out of the mine.
    func finishDig(_ c: Creature) {
        c.mining = false
        if grove.digCharges > 0 {
            grove.digCharges -= 1
            let roll = rng.range(0, 1)
            let gem: GemKind = roll < 0.03 ? .starstone : roll < 0.15 ? .amethyst : roll < 0.35 ? .sapphire : roll < 0.62 ? .emerald : .amber
            grove.gems[gem.rawValue, default: 0] += 1
            adventureEvents.append(.gemFound(gem, by: c.id))
            c.set(.react, duration: c.animationLength(for: .react) + 0.4)
        } else {
            adventureEvents.append(.pebble(by: c.id))
        }
    }

    // MARK: Sky ferry

    /// Brings the ferry in from off-screen toward a high window.
    @discardableResult
    public func callFerry() -> Bool {
        guard ferry == nil, let f = groveFloor, let dock = ferryDock(excluding: nil) else { return false }
        let fromLeft = rng.chance(0.5)
        let start = Vec2(fromLeft ? f.minX - 160 : f.maxX + 160, dock.y + 120)
        ferry = Ferry(pos: start, facing: fromLeft ? 1 : -1, target: dock, prev: start)
        adventureEvents.append(.ferryArrived)
        return true
    }

    /// A spot to dock: right beside the end of a window top, deck level with it.
    func ferryDock(excluding x: Double?) -> Vec2? {
        guard let f = groveFloor else { return nil }
        let tops = surfaces.filter { $0.kind == .windowTop && $0.y > f.minY + 200 && $0.y < f.maxY - 80 }
        var spots: [Vec2] = []
        for s in tops {
            if s.maxX + Ferry.deckWidth < f.maxX - 10 { spots.append(Vec2(s.maxX + Ferry.deckWidth / 2 + 4, s.y - Ferry.deckHeight)) }
            if s.minX - Ferry.deckWidth > f.minX + 10 { spots.append(Vec2(s.minX - Ferry.deckWidth / 2 - 4, s.y - Ferry.deckHeight)) }
        }
        if let x { spots.removeAll { abs($0.x - x) < 300 } }
        return spots.isEmpty ? nil : spots[Int(rng.next() % UInt64(spots.count))]
    }

    var ferrySurface: Surface? {
        guard let fe = ferry else { return nil }
        return Surface(ownerID: World.ferryOwner, kind: .plant, y: fe.deckY, minX: fe.pos.x - Ferry.deckWidth / 2 + 8, maxX: fe.pos.x + Ferry.deckWidth / 2 - 8)
    }

    func updateFerry(_ dt: Double) {
        // On a schedule (no dice rolls here, so the rest of the world's randomness is undisturbed): every 9-13 minutes.
        if ferry == nil {
            if nextFerryAt == nil { nextFerryAt = clock + 600 }
            if let t = nextFerryAt, clock > t, eventsAllowed, !calm, userActive {
                nextFerryAt = clock + 540 + (sin(clock) + 1) * 120
                callFerry()
            }
        }
        guard var fe = ferry, let f = groveFloor else { return }
        fe.prev = fe.pos
        let bob = sin(clock * 1.6) * 0.6
        switch fe.phase {
        case .arriving, .crossing:
            let d = fe.target - fe.pos
            if d.length < 3 {
                fe.pos = fe.target
                fe.phase = .docked
                fe.dockedUntil = clock + rng.range(9, 14)
                fe.stops += 1
            } else {
                fe.pos += d * (min(d.length, 140 * dt) / d.length)
                if abs(d.x) > 4 { fe.facing = d.x > 0 ? 1 : -1 }
            }
        case .docked:
            fe.pos.y += bob * dt * 4
            if clock > fe.dockedUntil {
                if fe.stops < 2, let next = ferryDock(excluding: fe.pos.x) {
                    fe.target = next; fe.phase = .crossing
                } else {
                    fe.phase = .leaving
                    fe.target = Vec2(fe.facing > 0 ? f.maxX + 220 : f.minX - 220, fe.pos.y + 160)
                    // Passengers hop off before it sails away.
                    for c in creatures where c.groundOwner == World.ferryOwner {
                        c.groundOwner = nil
                        c.vel = Vec2(-fe.facing * 120, 300)
                        c.set(.airborne, duration: 5)
                    }
                }
            }
        case .leaving:
            let d = fe.target - fe.pos
            if d.length < 4 { ferry = nil; adventureEvents.append(.ferryLeft); return }
            fe.pos += d * (min(d.length, 170 * dt) / d.length)
        }
        ferry = fe
        // Passengers ride along.
        let delta = fe.pos - fe.prev
        for c in creatures where c.groundOwner == World.ferryOwner { c.pos += delta }
    }

    /// Hop aboard when it's docked close by, or hop off at the next window.
    func ferryChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard let fe = ferry, fe.phase == .docked, let deck = ferrySurface else { return }
        if c.groundOwner == World.ferryOwner {
            if let s = surfaces.filter({ abs($0.y - deck.y) < 30 && ($0.maxX < deck.minX + 10 || $0.minX > deck.maxX - 10) && min(abs($0.maxX - deck.minX), abs($0.minX - deck.maxX)) < 120 }).first {
                add("disembark", 1.5) { self.launch(c, velocity: self.ballistic(from: c.pos, toX: s.minX + s.width / 2, y: s.y, apexExtra: 40)) }
            }
            add("ride", 1.2) { c.idleVariant = "look"; c.set(.idle, duration: self.rng.range(2, 4)) }
        } else if c.isGrounded && abs(c.pos.y - deck.y) < 60 && abs(c.pos.x - fe.pos.x) < 480 {
            add("board", 4.5) { self.launch(c, velocity: self.ballistic(from: c.pos, toX: fe.pos.x + self.rng.range(-30, 30), y: deck.y, apexExtra: 40)) }
        }
    }

    // MARK: Lantern festival

    /// Claude tasks finished today (the festival sends up one lantern per task).
    public var tasksToday: Int { grove.todayKey == World.dayKey() ? grove.todayTasks : 0 }

    static func dayKey(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    func countTaskToday() {
        let k = World.dayKey()
        if grove.todayKey != k { grove.todayKey = k; grove.todayTasks = 0; grove.festivalDone = false }
        grove.todayTasks += 1
    }

    /// After a good day (8+ Claude tasks), once it's dark: the lantern festival, once per day.
    public func checkLanternFestival(hour: Int) {
        guard isNight, hour >= 19, tasksToday >= 8, !grove.festivalDone, spectacle == nil else { return }
        grove.festivalDone = true
        requestEvent(.lanterns)
    }

    public func drainAdventureEvents() -> [AdventureEvent] {
        defer { adventureEvents.removeAll() }
        return adventureEvents
    }
}
