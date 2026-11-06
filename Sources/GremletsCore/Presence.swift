/// When Gremlets should be on screen, napping, or out of sight. Pure logic; the platform layer feeds it facts
/// (camera/mic in use, seconds since your last input, Low Power Mode, the hide hotkey) once a second.

public struct PresenceInput: Equatable, Sendable {
    public var now: Double
    public var manuallyHidden = false   // boss key / menu
    public var inCall = false           // camera or microphone in use by any app
    public var hideDuringCalls = true
    public var idleSeconds = 0.0        // since the last keyboard/mouse/trackpad input
    public var lowPower = false

    public init(now: Double, manuallyHidden: Bool = false, inCall: Bool = false, hideDuringCalls: Bool = true,
                idleSeconds: Double = 0, lowPower: Bool = false) {
        self.now = now; self.manuallyHidden = manuallyHidden; self.inCall = inCall
        self.hideDuringCalls = hideDuringCalls; self.idleSeconds = idleSeconds; self.lowPower = lowPower
    }
}

public enum HideReason: String, Equatable, Sendable { case manual, call }

public enum PresenceEvent: Equatable, Sendable {
    case hide(HideReason)
    case show
    case away           // you stepped away: everyone settles down for a nap
    case welcomeBack    // you're back after a while: wake up and wave
}

public struct PresenceTracker: Sendable {
    /// Idle time before Gremlets decide you've stepped away.
    public var awayAfter: Double = 5 * 60
    /// Calls often blip the mic on/off; wait this long after a call ends before coming back.
    public var callGrace: Double = 8

    public private(set) var hidden: HideReason?
    public private(set) var isAway = false
    private var callEndedAt: Double?

    public init() {}

    public var isHidden: Bool { hidden != nil }

    /// Highest loop rate worth running (nil = no cap).
    public func maxTickRate(_ input: PresenceInput) -> Double? {
        if isHidden { return 2 }               // nothing to draw; just keep checking
        if isAway { return 12 }
        return input.lowPower ? 30 : nil
    }

    public mutating func update(_ input: PresenceInput) -> [PresenceEvent] {
        var events: [PresenceEvent] = []

        // Hiding: manual wins, then calls (with a grace period so a muted-mic blip doesn't flash them back).
        let callActive: Bool
        if input.hideDuringCalls && input.inCall {
            callActive = true; callEndedAt = nil
        } else if hidden == .call {
            if callEndedAt == nil { callEndedAt = input.now }
            callActive = input.hideDuringCalls && input.now - callEndedAt! < callGrace
        } else {
            callActive = false
        }
        let want: HideReason? = input.manuallyHidden ? .manual : (callActive ? .call : nil)
        if want != hidden {
            if let w = want { events.append(.hide(w)) } else { events.append(.show) }
            hidden = want
            if want == nil { callEndedAt = nil }
        }

        // Away / back (only meaningful while they're visible).
        if !isAway && input.idleSeconds >= awayAfter {
            isAway = true
            if !isHidden { events.append(.away) }
        } else if isAway && input.idleSeconds < 2 {
            isAway = false
            if !isHidden { events.append(.welcomeBack) }
        }
        return events
    }
}

/// Focus minutes per day and the streak of days with at least one finished focus session.
public struct FocusLog: Codable, Equatable, Sendable {
    /// "yyyy-MM-dd" → minutes of finished focus sessions.
    public private(set) var minutesByDay: [String: Double] = [:]
    public private(set) var sessions = 0

    public init() {}

    public mutating func record(minutes: Double, day: String) {
        guard minutes > 0 else { return }
        minutesByDay[day, default: 0] += minutes
        sessions += 1
        // Keep the file small: the last ~60 days are plenty for a streak.
        if minutesByDay.count > 60, let oldest = minutesByDay.keys.min() { minutesByDay[oldest] = nil }
    }

    public func minutes(on day: String) -> Double { minutesByDay[day] ?? 0 }

    /// Consecutive days with focus, ending today (or yesterday, so the streak survives until you focus today).
    /// `previousDay` maps a day key to the day before it (injected so this stays calendar-free and testable).
    public func streak(today: String, previousDay: (String) -> String) -> Int {
        var day = minutesByDay[today] != nil ? today : previousDay(today)
        var n = 0
        while minutesByDay[day] != nil { n += 1; day = previousDay(day) }
        return n
    }
}

/// Which microphone users count as "you're on a call".
public enum CallDetection {
    /// macOS system services that keep the mic open in the background ("Hey Siri", dictation, Voice Control...).
    /// They live under /System/Library or /usr; real apps (including FaceTime in /System/Applications) still count.
    public static func isBackgroundListener(path: String) -> Bool {
        path.hasPrefix("/System/Library/") || path.hasPrefix("/usr/")
    }
}
