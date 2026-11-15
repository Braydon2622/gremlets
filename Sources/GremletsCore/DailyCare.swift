import Foundation

/// Light pet care: once a day your Gremlets would love a snack (right-click one → Give a berry, or the menu), and the
/// Focus Garden would like some water. Feeding them on consecutive days builds a streak. Nothing bad ever happens:
/// a missed day only means a slightly hungry Gremlet holding up an empty bowl in the afternoon, and the streak
/// starting over.
public struct DailyCare: Codable, Equatable, Sendable {
    public static let milestones = [3, 7, 14, 30, 50, 100, 200, 365]
    /// From this hour, an unfed household starts (gently) asking.
    public static let hungryHour = 15

    public private(set) var lastFed: String?
    public private(set) var streakCount = 0
    public private(set) var best = 0
    public private(set) var snacksToday = 0

    public init() {}

    public func fedToday(_ today: String) -> Bool { lastFed == today }

    /// The streak as it stands today: still alive if they were fed today or yesterday.
    public func streak(today: String, yesterday: String) -> Int {
        lastFed == today || lastFed == yesterday ? streakCount : 0
    }

    public func hungry(today: String, hour: Int) -> Bool { !fedToday(today) && hour >= DailyCare.hungryHour }

    /// A snack. Returns the milestone reached, if this was the day's first snack and it hit one.
    @discardableResult
    public mutating func feed(today: String, yesterday: String) -> Int? {
        if lastFed == today { snacksToday += 1; return nil }
        streakCount = lastFed == yesterday ? streakCount + 1 : 1
        best = max(best, streakCount)
        lastFed = today
        snacksToday = 1
        return DailyCare.milestones.contains(streakCount) ? streakCount : nil
    }
}
