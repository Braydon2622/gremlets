import Foundation

/// Gremlets helping each other, and noticing what your Mac is doing.
///
/// - **Boosts:** a window just too high to jump to? A friend walks over to the foot of it, plants its feet, the
///   climber hops onto its head, and the friend heaves it up and over the edge. Each one waves to the other after.
/// - **Your Mac:** start a screenshot and everyone strikes a pose. Battery running low, one holds up a little battery
///   sign (and cheers when you plug in). The internet drops, one holds up a "no signal" sign until it's back.
public struct Boost: Sendable {
    public enum Phase: Sendable { case gather, climb, launch }
    public let helper: Int
    public let target: Surface
    /// Where the helper stands (just outside the window's side edge), where the climber lands, which way it goes.
    public let helperX: Double, landX: Double, dir: Double
    public internal(set) var phase: Phase = .gather
    var started: Double
    var tries = 0
}

public enum HeldSign: String, Sendable { case battery, noSignal }

public enum MachineSignal: Equatable, Sendable {
    /// The screenshot tool is open (the crosshair or the toolbar is showing): time to pose.
    case screenshot
    case batteryLow(percent: Int)
    case pluggedIn
    case offline
    case online
}

public enum TeamEvent: Equatable, Sendable {
    case boostStarted(climber: Int, helper: Int)
    case heave(climber: Int, helper: Int)
    case boostDone(climber: Int, helper: Int)
    case boostFailed(climber: Int)
    case posed([Int])
    case signUp(Int, HeldSign)
    case signDown(Int, HeldSign, cheer: Bool)
}

extension World {
    // MARK: Boosts

    public struct BoostPlan: Sendable {
        public let helper: Int, target: Surface, helperX: Double, landX: Double, dir: Double
    }

    func isFree(_ c: Creature) -> Bool {
        c.job == nil && c.expedition == nil && c.play == nil && c.groveTask == nil && c.stair == nil && c.rail == nil
            && c.building == nil && c.boost == nil && c.helping == nil && c.homeUntil == nil && !c.isAsleep
            && World.carrierID(c.groundOwner) == nil && c.mossTask == nil && c.climb == nil
    }

    /// A window top too high for a jump but not for a boost, with room for a friend at its foot.
    func boostCandidate(for c: Creature, ignoreCooldown: Bool = false) -> BoostPlan? {
        guard ignoreCooldown || clock >= nextBoostAt, isFree(c), c.isGrounded, let s = supportingSurface(for: c),
              [.floor, .windowTop, .plant].contains(s.kind) else { return nil }
        let friends = creatures.filter { $0 !== c && isFree($0) && $0.isGrounded && $0.groundOwner == s.ownerID && abs($0.pos.x - c.pos.x) < 520 }
        guard !friends.isEmpty else { return nil }
        let maxH = maxJumpHeight * c.species.jumpPower
        var best: (BoostPlan, Double)?
        for t in surfaces where [.windowTop, .windowLedge, .plant].contains(t.kind) && t.width >= 60 && t.ownerID != s.ownerID && !World.isStairOwner(t.ownerID) {
            let dy = t.y - s.y
            guard dy > maxH * 0.92, dy < maxH * 1.45 + 40 else { continue }
            for (hx, dir, land) in [(t.minX - 28, 1.0, t.minX + 34), (t.maxX + 28, -1.0, t.maxX - 34)] {
                guard s.supports(x: hx), s.supports(x: hx - dir * 60), abs(hx - c.pos.x) < 520 else { continue }
                // Nothing overhead between the two of them and the edge.
                if surfaces.contains(where: { $0.ownerID != t.ownerID && $0.y > s.y + 10 && $0.y < t.y - 4 && $0.minX < hx + 20 && $0.maxX > hx - 20 }) { continue }
                guard let f = friends.min(by: { abs($0.pos.x - hx) < abs($1.pos.x - hx) }) else { continue }
                let cost = abs(hx - c.pos.x) + abs(f.pos.x - hx)
                if best == nil || cost < best!.1 { best = (BoostPlan(helper: f.id, target: t, helperX: hx, landX: land, dir: dir), cost) }
            }
        }
        return best?.0
    }

    func startBoost(_ c: Creature, _ plan: BoostPlan) {
        guard let f = creature(id: plan.helper) else { return }
        endSocial(c); endSocial(f)
        c.boost = Boost(helper: f.id, target: plan.target, helperX: plan.helperX, landX: plan.landX, dir: plan.dir, started: clock)
        f.helping = c.id
        f.targetX = plan.helperX; f.facing = plan.helperX > f.pos.x ? 1 : -1; f.set(.walk, duration: 30)
        let stand = plan.helperX - plan.dir * 56
        c.targetX = stand; c.facing = stand > c.pos.x ? 1 : -1; c.set(.walk, duration: 30)
        nextBoostAt = clock + rng.range(240, 600)
        teamEvents.append(.boostStarted(climber: c.id, helper: f.id))
    }

    /// `gremlet boost`: any pair that can, does it now.
    @discardableResult
    public func startBoostWithAnyone() -> Bool {
        for c in creatures.shuffled(using: &rng) {
            if let p = boostCandidate(for: c, ignoreCooldown: true) { startBoost(c, p); return true }
        }
        return false
    }

    func endBoost(_ c: Creature, success: Bool) {
        guard let b = c.boost else { return }
        c.boost = nil; c.targetX = nil
        if let f = creature(id: b.helper) {
            f.helping = nil; f.targetX = nil
            if f.isGrounded { f.facing = c.pos.x > f.pos.x ? 1 : -1; f.set(success ? .wave : .idle, duration: success ? 1.6 : 0.5) }
        }
        teamEvents.append(success ? .boostDone(climber: c.id, helper: b.helper) : .boostFailed(climber: c.id))
        if success, c.isGrounded { c.facing = -b.dir; c.set(.wave, duration: 1.6) }
    }

    /// Cancels whatever boost this creature is part of (climber or helper).
    func cancelBoost(_ c: Creature) {
        if c.boost != nil { endBoost(c, success: false) }
        if let id = c.helping, let climber = creature(id: id) { endBoost(climber, success: false) }
        c.helping = nil
    }

    /// Timeouts, a helper that got whisked away, a climber that ended up somewhere else.
    func updateBoosts() {
        for c in creatures where c.boost != nil {
            let b = c.boost!
            guard let f = creature(id: b.helper), f.helping == c.id, f.job == nil else { endBoost(c, success: false); continue }
            if clock - b.started > 30 { endBoost(c, success: false) }
        }
        for f in creatures where f.helping != nil && creature(id: f.helping)?.boost?.helper != f.id { f.helping = nil; f.targetX = nil }
    }

    /// The next step when the current activity ends, for either member of a boost.
    func boostDecide(_ c: Creature) {
        func walkTo(_ x: Double) { c.targetX = x; c.facing = x > c.pos.x ? 1 : -1; c.set(.walk, duration: 30) }
        if let id = c.helping {
            // The helper: get to the foot of the window and brace.
            guard let climber = creature(id: id), let b = climber.boost else { c.helping = nil; c.set(.idle, duration: 0.3); return }
            if abs(c.pos.x - b.helperX) > 5 { walkTo(b.helperX); return }
            c.facing = climber.pos.x > c.pos.x ? 1 : -1
            c.idleVariant = "look"
            c.set(.idle, duration: 0.4)
            return
        }
        guard var b = c.boost, let f = creature(id: b.helper) else { c.set(.idle, duration: 0.3); return }
        let fReady = f.isGrounded && abs(f.pos.x - b.helperX) <= 6 && f.activity == .idle
        switch b.phase {
        case .gather:
            let stand = b.helperX - b.dir * 56
            if abs(c.pos.x - stand) > 6 && c.groundOwner != f.carrierOwnerID { walkTo(stand); return }
            guard fReady else { c.facing = b.dir; c.idleVariant = "look"; c.set(.idle, duration: 0.3); return }
            b.phase = .climb
            c.boost = b
            launch(c, velocity: ballistic(from: c.pos, toX: f.pos.x, y: f.pos.y + f.species.headTop, apexExtra: 30))
        case .climb:
            if c.groundOwner == f.carrierOwnerID {
                // On its friend's head: the heave.
                b.phase = .launch
                c.boost = b
                c.facing = b.dir
                teamEvents.append(.heave(climber: c.id, helper: f.id))
                f.set(.react, duration: f.animationLength(for: .react) + 0.2)
                launch(c, velocity: ballistic(from: c.pos, toX: b.landX, y: b.target.y, apexExtra: 34))
            } else if b.tries < 2 && c.isGrounded {
                b.tries += 1
                b.phase = .gather
                c.boost = b
                c.set(.idle, duration: 0.2)
            } else {
                endBoost(c, success: false)
            }
        case .launch:
            if c.groundOwner == b.target.ownerID && abs(c.pos.y - b.target.y) < 3 { endBoost(c, success: true) }
            else if c.isGrounded { endBoost(c, success: false) }
            else { c.set(.idle, duration: 0.2) }
        }
    }

    func boostChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard let p = boostCandidate(for: c) else { return }
        add("boost", 0.9) { self.startBoost(c, p) }
    }

    // MARK: Your Mac

    /// Something happened on the Mac. Gremlets react in small ways: a pose, a sign held up, a cheer.
    public func machineSignal(_ s: MachineSignal) {
        switch s {
        case .screenshot:
            guard clock - lastPose > 6 else { return }
            lastPose = clock
            var posed: [Int] = []
            for c in creatures where c.isGrounded && !c.isAsleep && c.activity != .dragged && c.homeUntil == nil {
                if let cur = cursor { c.facing = cur.x > c.pos.x ? 1 : -1 }
                if c.job != nil || c.boost != nil || c.helping != nil || c.expedition != nil || c.stair != nil { continue }
                endSocial(c)
                // A pose each: a wave, a signature move or a little hop, held while you frame the shot.
                switch posed.count % 3 {
                case 0: c.set(.wave, duration: 2.6)
                case 1: startSpecial(c)
                default: c.idleVariant = "look"; c.set(.idle, duration: 2.6)
                }
                posed.append(c.id)
            }
            if !posed.isEmpty { teamEvents.append(.posed(posed)) }
        case .batteryLow:
            guard !creatures.contains(where: { $0.sign == .battery }), let c = signHolder() else { return }
            raiseSign(c, .battery, for: 14)
        case .pluggedIn:
            for c in creatures where c.sign == .battery { lowerSign(c, cheer: true) }
        case .offline:
            guard !creatures.contains(where: { $0.sign == .noSignal }), let c = signHolder() else { return }
            raiseSign(c, .noSignal, for: 180)
        case .online:
            for c in creatures where c.sign == .noSignal { lowerSign(c, cheer: true) }
        }
    }

    func signHolder() -> Creature? {
        let free = creatures.filter { $0.isGrounded && isFree($0) && $0.sign == nil }
        if let cur = cursor { return free.min { ($0.pos - cur).length < ($1.pos - cur).length } }
        return free.first
    }

    func raiseSign(_ c: Creature, _ s: HeldSign, for seconds: Double) {
        c.sign = s
        c.signUntil = clock + seconds
        endSocial(c)
        if let cur = cursor { c.facing = cur.x > c.pos.x ? 1 : -1 }
        c.idleVariant = "look"
        c.set(.idle, duration: 3)
        teamEvents.append(.signUp(c.id, s))
    }

    func lowerSign(_ c: Creature, cheer: Bool) {
        guard let s = c.sign else { return }
        c.sign = nil
        teamEvents.append(.signDown(c.id, s, cheer: cheer))
        if cheer, c.isGrounded, isFree(c) { startSpecial(c) }
    }

    func updateSigns() {
        for c in creatures where c.sign != nil && (clock > c.signUntil || c.job != nil || c.homeUntil != nil) { lowerSign(c, cheer: false) }
    }

    public func drainTeamEvents() -> [TeamEvent] {
        defer { teamEvents.removeAll() }
        return teamEvents
    }
}
