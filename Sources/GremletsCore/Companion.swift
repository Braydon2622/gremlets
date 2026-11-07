import Foundation  // percent-decoding for speech bubble text
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
    public var focusSessions: Int      // focus sessions it kept you company through

    public init(daysTogether: Int = 0, pets: Int = 0, pokes: Int = 0, hoursTogether: Double = 0, focusSessions: Int = 0) {
        self.daysTogether = daysTogether; self.pets = pets; self.pokes = pokes; self.hoursTogether = hoursTogether
        self.focusSessions = focusSessions
    }

    public static let levelNames = ["New friend", "Pal", "Friend", "Best friend", "Kindred spirit"]
    static let thresholds: [Double] = [0, 4, 15, 40, 90]

    /// Points from everything you've done together. Petting and focusing together count most; being around counts too.
    public var score: Double {
        Double(daysTogether) * 1.5 + Double(pets) * 0.4 + Double(pokes) * 0.1 + hoursTogether * 0.5 + Double(focusSessions) * 1.0
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
                for c in creatures where c.isGrounded && !c.isAsleep && c.activity != .dragged && c.job == nil {
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
            guard let c = getAttention(from: ground) else { return }
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

    /// The Gremlet nearest your cursor stops what it's doing, turns to you and waves. Returns it (nil if none is out).
    @discardableResult
    func getAttention(from candidates: [Creature]? = nil) -> Creature? {
        let pool = candidates ?? creatures.filter { $0.isGrounded }
        // A signal reacts only with Gremlets on the ground; a message falls back to anyone (e.g. one that's flying).
        guard let c = nearestToCursor(pool) ?? (candidates == nil ? nearestToCursor(creatures) : nil) else { return nil }
        endSocial(c)
        if c.isAsleep { emit(.wokeUp(c.id)) }
        if let cur = cursor { c.facing = cur.x > c.pos.x ? 1 : -1 }
        if c.isGrounded { c.set(.wave, duration: 2.0) }
        return c
    }

    /// A Gremlet comes over to tell you something (the platform layer shows `text` in a speech bubble).
    /// Returns the speaker's id, or nil if no Gremlet is out.
    public func say() -> Int? {
        guard let c = getAttention() else { return nil }
        emit(.alert(c.id))
        return c.id
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

/// Text for a speech bubble, from a URL query value: decoded, one line, no control characters, at most 120 characters.
public enum SpeechText {
    public static let maxLength = 120

    public static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let plus = raw.replacingOccurrences(of: "+", with: " ")
        let decoded = plus.removingPercentEncoding ?? plus
        var out = ""
        for ch in decoded {
            let isControl = ch.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format && $0.value != 0x200D }
            out.append(isControl || ch.isWhitespace ? " " : ch)
        }
        let squashed = out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !squashed.isEmpty else { return nil }
        return squashed.count > maxLength ? String(squashed.prefix(maxLength - 1)) + "…" : squashed
    }
}

// MARK: Saying hello (double-click)

extension World {
    /// Where a Gremlet is, in plain words (for its favourite-spot tally): nil while it's in the air or being carried.
    public func placeName(of c: Creature) -> String? {
        if c.homeUntil != nil || World.isHouseOwner(c.groundOwner) { return "the hanging house" }
        guard c.isGrounded, let o = c.groundOwner else { return nil }
        if World.isCornerSpot(o) { return "the corner branches" }
        if World.isBonsaiOwner(o) { return "up in the bonsai" }
        if World.isMossPadOwner(o) || o <= World.mossBridgeOwnerBase && o > World.mossBridgeOwnerBase - 100 { return "the moss bridges" }
        guard let s = supportingSurface(for: c) else { return nil }
        switch s.kind {
        case .windowTop: return creatures.contains { $0.job?.kind == .claude && $0.job?.windowID == o } ? "the top of Claude's window" : "the tops of your windows"
        case .floor: return "the mossy floor"
        case .shelf: return "the shelves"
        default: return "the moss"
        }
    }

    /// Double-clicked: it stops what it's doing (unless it's working for Claude), turns to you and waves.
    public func sayHello(_ c: Creature) {
        guard c.isGrounded, c.activity != .dragged else { return }
        if let cur = cursor { c.facing = cur.x > c.pos.x ? 1 : -1 }
        if c.job != nil && c.activity == .work { emit(.alert(c.id)); return }
        endSocial(c)
        c.set(.wave, duration: 1.6)
        emit(.alert(c.id))
    }
}
