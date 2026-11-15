import Foundation

/// The Focus Garden: every focus session grows a plant. While you focus, a seedling grows in the next free pot of a
/// little planter in the bottom-left corner; drift off to something distracting and it droops and waits for you; finish
/// the session and the plant stays in the garden. The planter keeps the last eight, so a good week fills it up.
public struct FocusPlant: Codable, Equatable, Sendable {
    /// Which plant (FocusGarden.kinds), how big it got (1...4) and when (yyyy-MM-dd).
    public var kind: Int
    public var stage: Int
    public var day: String
    public var minutes: Int

    public init(kind: Int, stage: Int, day: String, minutes: Int) {
        self.kind = kind; self.stage = stage; self.day = day; self.minutes = minutes
    }
}

/// One focus session in progress.
public struct FocusRun: Equatable, Sendable {
    public let planned: Double          // seconds
    public let kind: Int
    public private(set) var elapsed = 0.0
    public private(set) var distractedFor = 0.0
    /// Seconds spent on something distracting in the current stretch (resets when you come back).
    public private(set) var currentDistraction = 0.0

    public init(minutes: Double, kind: Int) { planned = max(60, minutes * 60); self.kind = kind }

    public var focused: Double { max(0, elapsed - distractedFor) }
    public var isDistracted: Bool { currentDistraction > 0 }

    /// 0...4: a seed, a sprout, leaves, a bud, in flower. Growth follows focused time, not just time.
    public var stage: Int { min(4, Int((focused / planned) * 4.0 + 0.0001)) }
    /// How much of the time so far was spent focused (1 before anything has happened).
    public var focusShare: Double { elapsed <= 0 ? 1 : focused / elapsed }

    /// Advances the run; returns whether the distraction state changed (started or ended).
    public mutating func advance(_ dt: Double, distracted: Bool) -> Bool {
        let was = isDistracted
        elapsed += dt
        if distracted { distractedFor += dt; currentDistraction += dt } else { currentDistraction = 0 }
        return was != isDistracted
    }

    /// The plant this run leaves behind: at least a sprout, so showing up always counts for something.
    public func harvest(day: String) -> FocusPlant {
        FocusPlant(kind: kind, stage: max(1, stage), day: day, minutes: Int((focused / 60).rounded()))
    }
}

public struct FocusGarden: Codable, Equatable, Sendable {
    /// daisy, tulip, sunflower, fern, mushroom, little pine.
    public static let kinds = 6
    public static let capacity = 8

    public private(set) var plants: [FocusPlant] = []
    public private(set) var total = 0
    /// The last day it was watered (yyyy-MM-dd).
    public var lastWatered: String?

    public init() {}

    public mutating func add(_ p: FocusPlant) {
        plants.append(p)
        if plants.count > FocusGarden.capacity { plants.removeFirst(plants.count - FocusGarden.capacity) }
        total += 1
    }

    /// A plant for the next session: not the same as the last one.
    public func nextKind(seed: Int) -> Int {
        let last = plants.last?.kind ?? -1
        var k = abs(seed) % FocusGarden.kinds
        if k == last { k = (k + 1) % FocusGarden.kinds }
        return k
    }

    /// Thirsty from noon if nobody has watered it today. It never dies; it just looks a bit sad.
    public func thirsty(today: String, hour: Int) -> Bool { !plants.isEmpty && lastWatered != today && hour >= 12 }

    public func plantsOn(_ day: String) -> Int { plants.filter { $0.day == day }.count }
}

/// What counts as a distraction while focusing: the app in front, or (when the window's title is readable) the site.
public enum Distraction {
    public static let apps: Set<String> = [
        "com.hnc.Discord", "com.apple.MobileSMS", "com.apple.TV", "com.netflix.Netflix", "tv.twitch.studio",
        "com.valvesoftware.steam", "com.facebook.Messenger", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram",
        "com.reddit.Reddit", "com.apple.news", "com.burbn.instagram", "com.zhiliaoapp.musically",
    ]
    static let sites = ["youtube", "instagram", "tiktok", "reddit", "facebook", "netflix", "twitch", "hulu", "disney+",
                        "prime video", "pinterest", "snapchat", "tumblr", "9gag", "/ x", "twitter"]

    public static func isDistracting(bundleID: String?, title: String?) -> Bool {
        if let b = bundleID, apps.contains(b) { return true }
        guard let t = title?.lowercased(), !t.isEmpty else { return false }
        return sites.contains { t.contains($0) }
    }
}
