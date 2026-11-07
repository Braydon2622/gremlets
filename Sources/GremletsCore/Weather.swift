import Foundation

/// The weather where you are (fetched by the app; see WeatherService), played out quietly around your windows:
/// rain splashes on window tops and drips off their corners, snow piles up along them and on the floor, wind sends
/// the kites up. Nothing falls across the middle of the screen: weather only shows where it lands, so it never gets
/// between you and your work.
///
/// The Gremlets live in it: in the rain they hold a leaf over their heads, once the snow is deep they roll a little
/// snow-Gremlet together on the floor (it melts when the snow goes), and they keep the kites in when it's wet.
public enum Sky: String, Sendable, CaseIterable {
    case clear, cloudy, fog, drizzle, rain, storm, snow

    /// From a WMO weather code (what Open-Meteo reports).
    public init(wmo code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2, 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57: self = .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .storm
        default: self = .cloudy
        }
    }

    public var isWet: Bool { self == .drizzle || self == .rain || self == .storm }

    /// Splashes a second across the whole screen (a gentle rate even in a storm).
    public var splashRate: Double {
        switch self { case .drizzle: return 3; case .rain: return 8; case .storm: return 15; default: return 0 }
    }

    public var label: String {
        switch self {
        case .clear: return "Clear"; case .cloudy: return "Cloudy"; case .fog: return "Foggy"; case .drizzle: return "Drizzle"
        case .rain: return "Rain"; case .storm: return "Thunderstorm"; case .snow: return "Snow"
        }
    }
}

public struct LocalWeather: Equatable, Sendable {
    public var sky: Sky
    public var windKmh: Double
    public var tempC: Double
    public var place: String
    public init(sky: Sky, windKmh: Double = 0, tempC: Double = 12, place: String = "") {
        self.sky = sky; self.windKmh = windKmh; self.tempC = tempC; self.place = place
    }
    /// Kites go up readily; gusts come more often.
    public var windy: Bool { windKmh >= 22 }
}

/// A little snow-Gremlet rolled on the floor. `built` goes 0 → 1 as Gremlets pat it together; it melts once the snow
/// is gone.
public struct Snowman: Equatable, Sendable {
    public let id: Int
    public let x: Double
    public let floorY: Double
    public internal(set) var built: Double
    public internal(set) var melt = 0.0
    /// 0 base, 1 body, 2 head, 3 face and arms (finished).
    public var stage: Int { built >= 1 ? 3 : built >= 0.66 ? 2 : built >= 0.33 ? 1 : 0 }
}

extension World {
    public static let snowmanLimit = 2

    /// Sets the live weather (nil switches weather off). A preview lasts `previewSeconds`, then the live weather
    /// comes back; a snow preview also lays snow down at once so there's something to see.
    public func setWeather(_ w: LocalWeather?, previewSeconds: Double? = nil) {
        if let s = previewSeconds {
            weatherPreview = w
            weatherPreviewUntil = clock + s
            if w?.sky == .snow { snowDepth = max(snowDepth, 0.75) }
            if w?.windy == true { nextKiteAt = min(nextKiteAt, clock) }
        } else {
            liveWeather = w
        }
    }

    /// What's happening now: a preview if one is running, else the live weather.
    public var weather: LocalWeather? { clock < weatherPreviewUntil ? weatherPreview : liveWeather }

    func updateWeather(_ dt: Double) {
        let w = weather
        // Snow builds up over about twenty minutes and melts over forty (faster once it's above freezing).
        if w?.sky == .snow {
            snowDepth = min(1, snowDepth + dt / 1200)
        } else if snowDepth > 0 {
            snowDepth = max(0, snowDepth - dt / ((w?.tempC ?? 5) > 2 ? 1200 : 2400))
        }
        // Snow-Gremlets melt when the snow is nearly gone.
        for i in snowmen.indices.reversed() {
            if snowDepth < 0.12 { snowmen[i].melt += dt / 300 }
            if snowmen[i].melt >= 1 { snowmen.remove(at: i) }
        }
        // Wind sends a kite up soon.
        if w?.windy == true, !(w?.sky.isWet ?? false), kite == nil, nextKiteAt - clock > 240 { nextKiteAt = clock + rng.range(60, 240) }
    }

    /// In the rain, a Gremlet out and about holds a big leaf over its head.
    public func holdsLeaf(_ c: Creature) -> Bool {
        guard let w = weather, w.sky.isWet, c.isGrounded, c.sign == nil, c.blocksInHand == 0, c.job == nil,
              c.snowmanTask == nil, c.carrying == nil, [.walk, .idle, .run].contains(c.activity) else { return false }
        return !World.isBonsaiOwner(c.groundOwner)
    }

    // MARK: Snow-Gremlets

    func snowChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard snowDepth >= 0.35, isFree(c), c.isGrounded, c.snowmanTask == nil, let s = supportingSurface(for: c), s.kind == .floor else { return }
        // Help finish one that's under way.
        if let m = snowmen.filter({ $0.built < 1 && $0.melt == 0 && abs($0.floorY - s.y) < 4 }).min(by: { abs($0.x - c.pos.x) < abs($1.x - c.pos.x) }),
           s.supports(x: m.x) {
            add("helpSnowman", 2.0) { self.startSnowman(c, id: m.id) }
            return
        }
        guard clock >= nextSnowmanAt, snowmen.count < World.snowmanLimit else { return }
        let x = (c.pos.x + c.facing * rng.range(40, 120)).clamped(s.minX + 40, s.maxX - 40)
        guard !snowmen.contains(where: { abs($0.x - x) < 70 }) else { return }
        add("buildSnowman", 0.9) {
            self.nextSnowmanID += 1
            self.snowmen.append(Snowman(id: self.nextSnowmanID, x: x, floorY: s.y, built: 0))
            self.nextSnowmanAt = self.clock + self.rng.range(240, 600)
            self.startSnowman(c, id: self.nextSnowmanID)
        }
    }

    func startSnowman(_ c: Creature, id: Int) {
        guard let m = snowmen.first(where: { $0.id == id }) else { return }
        endSocial(c)
        c.snowmanTask = id
        let side: Double = c.pos.x < m.x ? -1 : 1
        c.targetX = m.x + side * 18; c.facing = -side
        c.set(.walk, duration: 25)
    }

    /// `gremlet weather snowman`: someone starts one now (lays snow down if there isn't enough).
    @discardableResult
    public func startSnowmanNow() -> Bool {
        snowDepth = max(snowDepth, 0.5)
        nextSnowmanAt = 0
        for c in creatures.shuffled(using: &rng) where isFree(c) && c.isGrounded && c.snowmanTask == nil {
            var picked: (() -> Void)?
            snowChoices(for: c) { _, _, f in if picked == nil { picked = f } }
            if let f = picked { f(); return true }
        }
        return false
    }

    /// The next step when the current activity ends: walk over, pat it together a few times, admire it.
    func snowmanDecide(_ c: Creature) {
        guard let id = c.snowmanTask, let i = snowmen.firstIndex(where: { $0.id == id }), snowmen[i].melt == 0 else {
            c.snowmanTask = nil; c.set(.idle, duration: 0.3); return
        }
        let m = snowmen[i]
        if m.built >= 1 {
            c.snowmanTask = nil
            c.facing = m.x > c.pos.x ? 1 : -1
            c.set(.react, duration: c.animationLength(for: .react))
            return
        }
        if abs(abs(c.pos.x - m.x) - 18) > 8 || abs(c.pos.y - m.floorY) > 6 {
            guard abs(c.pos.y - m.floorY) < 6 else { c.snowmanTask = nil; c.set(.idle, duration: 0.3); return }
            let side: Double = c.pos.x < m.x ? -1 : 1
            c.targetX = m.x + side * 18; c.set(.walk, duration: 20); return
        }
        // Pat a bit more on.
        if c.activity == .work { snowmen[i].built = min(1, m.built + 0.2) }
        c.facing = m.x > c.pos.x ? 1 : -1
        c.workPose = "crouch"
        c.set(.work, duration: rng.range(1.8, 2.6))
    }
}
