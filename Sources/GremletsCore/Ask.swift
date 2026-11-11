import Foundation

/// Asking a Gremlet to do something (right-click it): the menu offers whatever it could do from where it stands
/// right now, and picking one starts it straight away, skipping the usual waits between outings.
public enum Idea: String, CaseIterable, Sendable {
    case garden, forage, supper, rainwater, basket, patch, lantern, sweep, stairs, rail, nap, play, critters, dock, kite, treasure, visitFriend, snack, wakeUp, cornerPerch, dance

    /// The menu wording.
    public var title: String {
        switch self {
        case .garden: return "Tend the moss"
        case .forage: return "Forage for the pantry"
        case .supper: return "Have supper on the porch"
        case .rainwater: return "Fetch rainwater for the moss"
        case .basket: return "Ride the basket"
        case .patch: return "Tend the vegetable patch"
        case .lantern: return "Set out a lantern"
        case .sweep: return "Sweep the porch"
        case .stairs: return "Build a staircase"
        case .rail: return "Lay a minecart track"
        case .nap: return "Go home for a nap"
        case .play: return "Play with a friend"
        case .critters: return "Say hi to the critters"
        case .dock: return "Hop along the Dock"
        case .kite: return "Fly a kite"
        case .treasure: return "Go on an adventure"
        case .visitFriend: return "Visit your friend's screen"
        case .snack: return "Give a berry"
        case .wakeUp: return "Wake up"
        case .cornerPerch: return "Climb up to a corner"
        case .dance: return "Dance"
        }
    }

    /// The brain's names for the choices this covers.
    var choices: Set<String> {
        switch self {
        case .garden: return ["plantMoss", "plantFar", "widgetMoss", "tendMoss", "waterMoss", "trimMoss", "pruneMoss", "mowMoss", "tendTree", "buildPad", "climbVine", "waterSprout", "tend"]
        case .forage: return ["forage"]
        case .supper: return ["supper"]
        case .rainwater: return ["fetchWater"]
        case .basket: return ["basketUp", "basketDown"]
        case .patch: return ["tendPatch"]
        case .lantern: return ["hangLantern"]
        case .sweep: return ["sweepPorch"]
        case .stairs: return ["stairs"]
        case .rail: return ["rail"]
        case .nap: return ["notchNap", "goHome", "goInside", "cornerNap", "dockNap", "napInTree", "nap"]
        case .play: return ["tag", "greet", "highFive", "toss", "follow", "stack", "joinDance"]
        case .critters: return ["meetCritter", "chaseFirefly"]
        case .dock: return ["dockHop"]
        case .kite: return ["kite"]
        case .treasure: return ["treasure", "summit"]
        case .cornerPerch: return ["cornerPerch"]
        case .dance: return ["dance", "joinDance"]
        case .visitFriend, .snack, .wakeUp: return []
        }
    }
}

extension World {
    /// The waits between outings: a request skips them (they're put back if nothing comes of it).
    private static let askCooldowns: [ReferenceWritableKeyPath<World, Double>] = [
        \.nextStairAt, \.nextRailAt, \.nextNotchTripAt, \.nextMossTaskAt, \.nextDockPlayAt, \.nextKiteAt, \.nextExpeditionAt,
        \.nextCornerTripAt, \.nextForageAt, \.nextSupperAt, \.nextBasketAt, \.nextBarrelAt, \.nextPatchAt, \.nextLanternAt, \.nextSweepAt, \.nextSummitAt, \.nextChestAt, \.nextFireflyAt,
    ]

    /// Whether it's in a state to be asked anything (not mid-air, not being carried, not busy for Claude).
    func askable(_ c: Creature) -> Bool {
        c.isGrounded && c.activity != .dragged && c.job?.kind != .claude && c.homeUntil == nil && c.climb == nil && World.carrierID(c.groundOwner) == nil
    }

    private func askChoices(_ c: Creature) -> [Brain.Choice] {
        let saved = World.askCooldowns.map { self[keyPath: $0] }
        for k in World.askCooldowns { self[keyPath: k] = 0 }
        let sup = suppersTonight; suppersTonight = 0
        defer { for (k, v) in zip(World.askCooldowns, saved) { self[keyPath: k] = v }; suppersTonight = sup }
        // What it's in the middle of doesn't count against it: it would drop that for you.
        let task = c.mossTask, grove = c.groveTask, play = c.play, social = c.social
        c.mossTask = nil; c.groveTask = nil
        if play == nil { c.social = .none }
        defer { c.mossTask = task; c.groveTask = grove; c.social = social }
        return Brain.general(c, self)
    }

    /// What this Gremlet could do for you right now (for the right-click menu).
    public func ideas(for c: Creature) -> [Idea] {
        if c.homeUntil != nil || c.isAsleep { return calm ? [] : [.wakeUp] }
        guard askable(c) else { return [] }
        let names = Set(askChoices(c).map(\.name))
        var out = Idea.allCases.filter { !$0.choices.isDisjoint(with: names) }
        if door != nil, canUseDoor(c) || c.isGrounded { out.append(.visitFriend) }
        out.append(.snack)
        return out
    }

    /// Asks it to do one of them now. False if it can't after all.
    @discardableResult
    public func ask(_ c: Creature, _ idea: Idea) -> Bool {
        switch idea {
        case .wakeUp:
            guard c.isAsleep || c.homeUntil != nil else { return false }
            if c.homeUntil != nil { c.homeUntil = clock; c.wavesOnWaking = true; return true }
            c.set(.wake, duration: c.animationLength(for: .wake)); emit(.wokeUp(c.id))
            return true
        case .snack:
            guard c.isGrounded, c.activity != .dragged else { return false }
            endSocial(c)
            c.energy = min(1, c.energy + 0.25)
            c.bond = min(1, c.bond + 0.02)
            c.carrying = "berries"
            homeEvents.append(.supper(c.pos, by: c.id))
            c.workPose = "crouch"; c.set(.work, duration: 2.2)
            c.mossTask = MossTask(kind: .gift(to: -1, what: .berries), started: clock)
            return true
        case .visitFriend:
            return sendThroughDoor(preferring: c.id)
        default:
            break
        }
        guard askable(c) else { return false }
        let picks = askChoices(c).filter { idea.choices.contains($0.name) }
        guard !picks.isEmpty else { return false }
        // Drop whatever it was doing.
        if c.stair != nil { abandonStairs(c) }
        if basket?.rider == c.id { dropBasket() }
        if c.expedition != nil { giveUp(c) }
        endSocial(c)
        c.mossTask = nil; c.groveTask = nil; c.carrying = nil; c.targetX = nil
        if c.job?.kind == .hobby { c.job = nil }
        let saved = World.askCooldowns.map { self[keyPath: $0] }
        for k in World.askCooldowns { self[keyPath: k] = 0 }
        Brain.pickAndStart(picks, self)
        // Whatever it started has set its own wait; everything else goes back as it was.
        for (k, v) in zip(World.askCooldowns, saved) where self[keyPath: k] == 0 { self[keyPath: k] = v }
        emit(.alert(c.id))
        return true
    }
}
