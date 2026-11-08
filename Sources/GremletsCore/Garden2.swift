import Foundation

/// More of the garden's day around Claude's work and yours:
/// - **Win flags:** each task Claude finishes plants a tiny flag in the moss on its window top; they stay all day.
/// - **Rubber duck:** two failed commands in a row and the Gremlet sits down with a little duck to talk it through;
///   the next thing that works, it cheers.
/// - **Test weather:** a day of passing tests makes the moss lush and flowery; lots of failures and it gets
///   windswept until things pass again (`testMood`, -1...1, easing back to calm over a few hours).
/// - **Picnic** at lunchtime, and a **blanket** brought to you late at night.
/// - **Summary sign:** when Claude finishes, its Gremlet holds up a little sign with the first words of Claude's
///   summary.
/// - **Friend's seed:** visiting Gremlets from a friend's Mac bring a seed that grows a flower only they have.
/// - **Hush:** while you're typing fast, the Gremlets go quiet and tiptoe; when you stop, they stretch and play.
public struct WinFlag: Codable, Equatable, Sendable {
    public let windowID: Int
    public let offset: Double
    public let day: Int
    public let tint: Int
}

public enum GardenEvent: Equatable, Sendable {
    case flagPlanted(Vec2, by: Int)
    case duckOut(by: Int)
    case duckCheer(by: Int)
    case picnicStarted(Vec2)
    case blanketGiven(Vec2, by: Int)
    case friendSeed(by: Int?)
    case stretchBreak([Int])
    /// A Gremlet tapped the quest board and reads out the next step.
    case questNag(by: Int)
    case questStepDone(Int?)
}

extension World {
    /// Days since 1970 on the local wall clock.
    var today: Int { Int((wallClock + Double(TimeZone.current.secondsFromGMT())) / 86_400) }

    public func drainGardenEvents() -> [GardenEvent] { defer { gardenEvents = [] }; return gardenEvents }

    // MARK: Win flags

    /// Claude finished a task: a tiny flag goes into the moss on its window top (today's wins, side by side).
    public func plantWinFlag(workerID: Int) {
        guard let c = creature(id: workerID), let wid = c.job?.windowID ?? c.groundOwner, wid >= 0, let w = windows[wid] else { return }
        let mine = winFlags.filter { $0.windowID == wid && $0.day == today }
        guard mine.count < 12 else { return }
        // In a neat row from where it's working, toward the middle of the window.
        let toward: Double = c.pos.x < w.midX ? 1 : -1
        var x = (c.pos.x + toward * 30).clamped(w.minX + 24, w.maxX - 24)
        while mine.contains(where: { abs(w.minX + $0.offset - x) < 13 }) { x += toward * 13 }
        x = x.clamped(w.minX + 18, w.maxX - 18)
        winFlags.append(WinFlag(windowID: wid, offset: x - w.minX, day: today, tint: Int(rng.next() % 5)))
        gardenEvents.append(.flagPlanted(Vec2(x, w.maxY), by: c.id))
    }

    /// Yesterday's flags come down; flags on windows that closed go with them.
    func tidyWinFlags() {
        let t = today
        let before = winFlags.count
        winFlags.removeAll { $0.day != t || windows[$0.windowID] == nil }
        if winFlags.count != before { winFlagsChanged = true }
    }

    public func loadWinFlags(_ f: [WinFlag]) { winFlags = f }

    // MARK: Rubber duck

    func duckAfterFailure(_ c: Creature, _ j: Job) {
        guard j.failStreak >= 2, !j.duckOut else { return }
        j.duckOut = true
        gardenEvents.append(.duckOut(by: c.id))
    }

    func duckAfterSuccess(_ c: Creature, _ j: Job) {
        guard j.duckOut else { return }
        j.duckOut = false
        gardenEvents.append(.duckCheer(by: c.id))
        if c.isGrounded && !c.isDozingAtWork { c.set(.react, duration: c.animationLength(for: .react)) }
    }

    /// Whether its rubber duck is out (sitting beside it).
    public func duckOut(_ c: Creature) -> Bool { c.job?.duckOut == true && c.job?.phase == .working }

    // MARK: Test weather

    func nudgeTestMood(_ d: Double) { testMood = (testMood + d).clamped(-1, 1) }

    // MARK: Picnic and blanket

    /// Up for a picnic (a game or a little moss chore can wait; Claude's work and a trip can't).
    func canDropEverything(_ c: Creature, evenAsleep: Bool = false) -> Bool {
        c.isGrounded && c.job == nil && c.expedition == nil && c.homeUntil == nil && (evenAsleep || !c.isAsleep) && c.stair == nil && c.rail == nil
            && c.climb == nil && c.building == nil && World.carrierID(c.groundOwner) == nil && c.activity != .dragged
    }

    /// Lunchtime: a picnic blanket goes down where someone is, and a couple of friends join for a bite.
    @discardableResult
    public func startPicnic() -> Bool {
        guard picnic == nil, !compact else { return false }
        let free = creatures.filter { canDropEverything($0) }
        guard let host = free.first(where: { supportingSurface(for: $0)?.kind == .floor }) ?? free.first,
              let s = supportingSurface(for: host) else { return false }
        let x = host.pos.x.clamped(s.minX + 50, s.maxX - 50)
        picnic = (s.ownerID, x, s.y, clock + 150)
        gardenEvents.append(.picnicStarted(Vec2(x, s.y)))
        let guests = [host] + free.filter { $0 !== host && supportingSurface(for: $0)?.ownerID == s.ownerID }
            .sorted { abs($0.pos.x - x) < abs($1.pos.x - x) }.prefix(2)
        for (k, g) in guests.enumerated() {
            g.mossTask = nil; g.groveTask = nil; g.snowmanTask = nil
            let seat = x + [-22.0, 22, 44][k]
            startMossTask(g, .picnic(seat: seat.clamped(s.minX + 8, s.maxX - 8)), walkTo: seat.clamped(s.minX + 8, s.maxX - 8))
        }
        return true
    }

    func picnicDecide(_ c: Creature, _ t: inout MossTask, seat: Double) {
        guard let p = picnic, clock < p.until else {
            c.mossTask = nil
            c.set(.react, duration: c.animationLength(for: .react))
            return
        }
        if abs(c.pos.x - seat) > 6 { c.targetX = seat; c.set(.walk, duration: 10); return }
        c.facing = p.x > c.pos.x ? 1 : -1
        if rng.chance(0.3) { c.set(.react, duration: c.animationLength(for: .react)) }   // a bite
        else { c.idleVariant = rng.chance(0.5) ? "look" : "idle"; c.set(.idle, duration: rng.range(3, 6)) }
    }

    /// Late at night: one of them brings a tiny blanket over to where you are, sets it down and yawns.
    @discardableResult
    public func bringBlanket(towardX x: Double) -> Bool {
        // (Even one that's dozing gets up for this.)
        guard !compact, let c = creatures.filter({ canDropEverything($0, evenAsleep: true) })
            .min(by: { abs($0.pos.x - x) < abs($1.pos.x - x) }), let s = supportingSurface(for: c) else { return false }
        let spot = x.clamped(s.minX + 20, s.maxX - 20)
        c.mossTask = nil; c.groveTask = nil; c.snowmanTask = nil
        startMossTask(c, .blanket(x: spot), walkTo: spot)
        c.carrying = "blanket"
        return true
    }

    func blanketDecide(_ c: Creature, _ t: inout MossTask, x: Double, on s: Surface) {
        if abs(c.pos.x - x) > 8, s.supports(x: x) { c.targetX = x; c.carrying = "blanket"; c.set(.walk, duration: 15); return }
        c.mossTask = nil
        c.carrying = nil
        blanket = (s.ownerID, c.pos.x + c.facing * 16, s.y, clock + 90)
        gardenEvents.append(.blanketGiven(Vec2(c.pos.x, s.y), by: c.id))
        c.set(.yawn, duration: c.animationLength(for: .yawn))
    }

    // MARK: Summary sign

    /// Claude finished: its Gremlet holds up a little sign with the first words of what Claude said.
    public func claudeSummary(workerID: Int, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let c = creature(id: workerID) else { return }
        summarySigns[c.id] = (String(t.prefix(64)), clock + 14)
    }

    public func summarySign(_ c: Creature) -> String? {
        guard let s = summarySigns[c.id], clock < s.until, c.homeUntil == nil else { return nil }
        return s.text
    }

    // MARK: A friend's seed

    /// A friend's Gremlets came to visit and brought a seed: a flower in their own colour comes up in the moss, the
    /// only one like it. It lasts the day.
    @discardableResult
    public func friendSeed(tint: UInt32, by guest: Int? = nil) -> Bool {
        let tops = surfaces.filter { $0.kind == .windowTop && $0.ownerID >= 0 && $0.width >= 100 }
        let host = guest.flatMap { creature(id: $0) }
        let t = host.flatMap { h in tops.min { abs(($0.minX + $0.maxX) / 2 - h.pos.x) < abs(($1.minX + $1.maxX) / 2 - h.pos.x) } } ?? tops.randomElement(using: &rng)
        guard let top = t, let b = bed(top.ownerID) else { return false }
        let x = (host?.pos.x ?? rng.range(top.minX + 30, top.maxX - 30)).clamped(top.minX + 26, top.maxX - 26)
        nextSproutID += 1
        sprouts.append(MossSprout(id: nextSproutID, kind: .friendBloom, windowID: top.ownerID, offset: x - b.minX, growth: 0.3, tint: tint, day: today))
        sproutEvents.append(.sprouted(Vec2(x, b.y)))
        gardenEvents.append(.friendSeed(by: guest))
        return true
    }

    // MARK: Hush

    /// You've stopped typing after a long stretch: a few of them stretch, and one starts a little dance.
    public func stretchBreak() {
        let free = creatures.filter { isFree($0) && $0.isGrounded && $0.mossTask == nil }.shuffled(using: &rng).prefix(3)
        for c in free { endSocial(c); c.set(.react, duration: c.animationLength(for: .react) + 0.3) }
        if let d = free.first { startDance(d, duration: 4, invite: true) }
        gardenEvents.append(.stretchBreak(free.map(\.id)))
    }

    func updateGarden2(_ dt: Double) {
        testMood *= exp(-dt / 7200)
        if let p = picnic, clock > p.until + 5 { picnic = nil }
        if let b = blanket, clock > b.until { blanket = nil }
        for (id, s) in summarySigns where clock > s.until { summarySigns[id] = nil }
        if Int(clock) % 30 == 0 { tidyWinFlags() }
    }
}
