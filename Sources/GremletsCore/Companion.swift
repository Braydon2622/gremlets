/// Companion features: focus mode, celebrations, reactions to your work, and the bond each Gremlet builds with you.
/// Pure engine logic; the platform layer decides when to call these (timers, local commands, saved stats).

/// What the outside world can tell the Gremlets (focus timer, the `gremlet` command, test runners...).
public enum Signal: String, CaseIterable, Sendable {
    case pass       // tests passed / build succeeded → dance party
    case fail       // tests failed / build broke → everyone keels over dizzy
    case done       // a long task finished → one Gremlet pops up and waves
    case dance      // just dance
    case wave       // say hi
    case sleep      // everyone naps
    case wake       // everyone up
    case special    // signature moves all round
    case water      // reminder: drink some water
    case stretch    // reminder: stand up and stretch
}

/// How close a Gremlet is to you. Grows with time together, petting and pokes.
public struct Bond: Equatable, Sendable {
    public var daysTogether: Int
    public var pets: Int
    public var pokes: Int
    public var hoursTogether: Double

    public init(daysTogether: Int = 0, pets: Int = 0, pokes: Int = 0, hoursTogether: Double = 0) {
        self.daysTogether = daysTogether; self.pets = pets; self.pokes = pokes; self.hoursTogether = hoursTogether
    }

    public static let levelNames = ["New friend", "Pal", "Friend", "Best friend", "Kindred spirit"]
    static let thresholds: [Double] = [0, 4, 15, 40, 90]

    /// Points from everything you've done together. Petting counts most; just being around counts too.
    public var score: Double {
        Double(daysTogether) * 1.5 + Double(pets) * 0.4 + Double(pokes) * 0.1 + hoursTogether * 0.5
    }

    /// 0...4
    public var level: Int { Bond.thresholds.lastIndex { score >= $0 } ?? 0 }
    public var name: String { Bond.levelNames[level] }
    /// 0...1, used by the brain.
    public var strength: Double { Double(level) / Double(Bond.levelNames.count - 1) }
    /// Points still needed for the next level (nil at max).
    public var pointsToNext: Double? { level + 1 < Bond.thresholds.count ? Bond.thresholds[level + 1] - score : nil }
}

extension World {

    /// Focus mode: Gremlets settle down, stop zooming around, and doze so they don't distract you.
    public var focusMode: Bool {
        get { calm }
        set {
            guard newValue != calm else { return }
            calm = newValue
            if newValue {
                for c in creatures where c.isGrounded && !c.isAsleep && c.activity != .dragged {
                    endSocial(c)
                    c.set(.yawn, duration: c.animationLength(for: .yawn))
                }
            }
        }
    }

    /// Everyone wakes up and dances.
    public func celebrate(duration: Double = 4.5) {
        for c in creatures where c.isGrounded || c.activity == .sleep {
            if c.isAsleep { emit(.wokeUp(c.id)) }
            endSocial(c)
            startDance(c, duration: duration, invite: false)
        }
    }

    /// Reacts to an outside signal (focus timer, `gremlet` command, test runner).
    public func receive(_ signal: Signal) {
        let ground = creatures.filter { $0.isGrounded }
        switch signal {
        case .pass:
            focusMode = false
            celebrate()
        case .dance:
            celebrate(duration: 3.5)
        case .fail:
            for c in ground {
                endSocial(c)
                c.set(.dizzy, duration: 2.2)
                emit(.dizzy(c.id))
            }
        case .done, .wave, .water, .stretch:
            guard let c = nearestToCursor(ground) else { return }
            endSocial(c)
            if c.isAsleep { emit(.wokeUp(c.id)) }
            if let cur = cursor { c.facing = cur.x > c.pos.x ? 1 : -1 }
            c.set(.wave, duration: 2.0)
            switch signal {
            case .water: emit(.special(c.id, effect: "rain"))
            case .stretch: emit(.special(c.id, effect: "sparkle"))
            default: emit(.alert(c.id))
            }
        case .sleep:
            for c in ground where !c.isAsleep { endSocial(c); c.set(.yawn, duration: c.animationLength(for: .yawn)) }
        case .wake:
            for c in ground where c.isAsleep { c.set(.wake, duration: c.animationLength(for: .wake)); emit(.wokeUp(c.id)) }
        case .special:
            for c in ground where !c.isAsleep { endSocial(c); startSpecial(c) }
        }
    }

    func nearestToCursor(_ cs: [Creature]) -> Creature? {
        guard let cur = cursor else { return cs.first }
        return cs.min { ($0.pos - cur).length < ($1.pos - cur).length }
    }

    /// Sets how close each Gremlet feels to you (0...1). Stronger bonds wave and follow you more,
    /// and show off their signature move when you pet them.
    public func setBond(_ strength: Double, forSpecies id: String) {
        for c in creatures where c.species.id == id { c.bond = strength.clamped(0, 1) }
    }
}

extension World {
    /// A Gremlet waves goodbye (e.g. when a demo session ends). The platform layer removes it afterwards.
    public func sayGoodbye(_ id: Int) {
        guard let c = creature(id: id) else { return }
        endSocial(c)
        if c.isAsleep { emit(.wokeUp(c.id)) }
        if let cur = cursor { c.facing = cur.x > c.pos.x ? 1 : -1 }
        if c.isGrounded { c.set(.wave, duration: 1.6) }
    }
}
