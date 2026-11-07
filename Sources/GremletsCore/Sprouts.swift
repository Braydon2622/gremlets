import Foundation

/// Little things that come up in the moss on window tops: daisies, mushrooms, berry sprigs and dandelions. They
/// sprout, grow over a few minutes (faster while Claude works and while the moss is cared for), and the Gremlets look
/// after them: water the young ones, then pick the daisies and mushrooms (and hand them to a friend), eat the berries,
/// and blow the dandelion clocks, whose seeds drift off and start new moss somewhere else.
///
/// They're tiny and only ever sit on window tops, in the moss, so they never get in the way.
public struct MossSprout: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case daisy, mushroom, berries, dandelion
        /// From a friend's seed: a star flower in their colour (only ever planted by a visit).
        case friendBloom
        /// The kinds that come up on their own.
        static let wild: [Kind] = [.daisy, .mushroom, .berries, .dandelion]
    }
    public let id: Int
    public let kind: Kind
    public let windowID: Int
    /// Distance from the window's left edge.
    public let offset: Double
    /// 0...1; ripe at 1.
    public internal(set) var growth: Double
    /// When it ripened (it doesn't wait forever: flowers wilt, berries drop, dandelions blow away on their own).
    var ripeAt: Double? = nil
    /// A friend's flower: its colour, and the day it was planted (it lasts that day).
    public internal(set) var tint: UInt32? = nil
    var day: Int? = nil
    public var ripe: Bool { growth >= 1 }
    /// 0 a shoot, 1 budding, 2 ready.
    public var stage: Int { growth >= 1 ? 2 : growth >= 0.35 ? 1 : 0 }
}

public enum SproutEvent: Equatable, Sendable {
    case sprouted(Vec2)
    case watered(Vec2, by: Int)
    case picked(MossSprout.Kind, Vec2, by: Int)
    case gave(MossSprout.Kind, from: Int, to: Int)
    case ate(Vec2, by: Int)
    /// Dandelion seeds off on the breeze, drifting this way (+1 right, -1 left). `by` is nil if the wind did it.
    case seedsBlown(Vec2, toward: Double, by: Int?)
    /// A seed came down and started a tuft of moss here.
    case seedLanded(Vec2)
    case wilted(Vec2)
    /// A daisy went into the window box on the hanging house.
    case boxed(Vec2, by: Int)
    /// Caught a firefly (it glows in their hands a moment, then they let it go).
    case caughtFirefly(Vec2, by: Int)
    case missedFirefly(by: Int)
    /// Full screen: popped straight from one place up to a corner perch (leaves where it was, a sparkle where it lands).
    case poofed(from: Vec2, to: Vec2)
}

extension World {
    public static let sproutLimit = 7

    public func drainSproutEvents() -> [SproutEvent] { defer { sproutEvents = [] }; return sproutEvents }

    func sproutX(_ s: MossSprout) -> Double { (bed(s.windowID)?.minX ?? 0) + s.offset }

    /// The visible window top a sprout stands on (nil while it's covered by another window).
    func sproutTop(_ s: MossSprout) -> Surface? {
        bedSurface(s.windowID, at: sproutX(s))
    }

    func updateSprouts(_ dt: Double) {
        sprouts.removeAll { bed($0.windowID) == nil }
        if wallClock > 0 { rollDaisyDay() }
        guard !compact else { return }
        // Seeds drifting down to start new moss.
        for (i, seed) in pendingSeeds.enumerated().reversed() where clock >= seed.at {
            pendingSeeds.remove(at: i)
            guard let b = bed(seed.window), mossPatches.filter({ $0.windowID == seed.window }).count < 5,
                  !mossPatches.contains(where: { $0.windowID == seed.window && abs($0.offset - seed.offset) < 60 }) else { continue }
            nextPatchID += 1
            mossPatches.append(MossPatch(id: nextPatchID, windowID: seed.window, offset: seed.offset, size: 0.06, lastTended: clock))
            sproutEvents.append(.seedLanded(Vec2(b.minX + seed.offset, b.y)))
        }
        // Growing (not while the moss is parched).
        if !mossThirsty {
            let rate = dt / (claudeWorking ? 70 : 160) * (0.6 + mossCare * 0.6)
            for i in sprouts.indices where sprouts[i].growth < 1 {
                sprouts[i].growth = min(1, sprouts[i].growth + rate)
                if sprouts[i].growth >= 1 { sprouts[i].ripeAt = clock }
            }
        }
        // Left too long: they look after themselves.
        sprouts.removeAll { $0.kind == .friendBloom && $0.day != nil && $0.day != today }
        for (i, s) in sprouts.enumerated().reversed() where s.kind != .friendBloom {
            guard let r = s.ripeAt, clock - r > 480, !creatures.contains(where: { $0.mossTask?.sprout == s.id }) else { continue }
            sprouts.remove(at: i)
            let p = Vec2(sproutX(s), bed(s.windowID)?.y ?? 0)
            if s.kind == .dandelion { blowSeeds(from: s, at: p, by: nil) } else { sproutEvents.append(.wilted(p)) }
        }
        // Something new comes up in the moss now and then (more often while Claude works).
        guard clock >= nextSproutAt, mossMinutes >= 12, !mossThirsty, sprouts.count < min(World.sproutLimit, 2 + Int(mossMinutes / 40)) else { return }
        nextSproutAt = clock + (claudeWorking ? rng.range(15, 35) : rng.range(40, 90))
        // Mostly out of the moss the Gremlets planted; otherwise anywhere along a mossy window top, or in the moss
        // along the bottom of the screen.
        let tops = builtSurfaces.filter { $0.kind == .windowTop && $0.ownerID >= 0 && $0.width >= 100 && windows[$0.ownerID] != nil }
        let floors = screens.indices.flatMap { i in floorMoss(i).map { (id: -(i + 1), lo: $0.lo, hi: $0.hi) } }.filter { $0.hi - $0.lo > 70 }
        var spot: (window: Int, offset: Double)?
        for _ in 0..<6 where spot == nil {
            var wid: Int, x: Double
            if let p = mossPatches.randomElement(using: &rng), rng.chance(0.6), let b = bed(p.windowID) {
                wid = p.windowID; x = b.minX + p.offset + rng.range(-p.width / 2, p.width / 2)
            } else if let f = floors.randomElement(using: &rng), rng.chance(0.3) {
                wid = f.id; x = rng.range(f.lo + 30, f.hi - 30)
            } else if let t = tops.randomElement(using: &rng) {
                wid = t.ownerID; x = rng.range(t.minX + 30, t.maxX - 30)
            } else { break }
            guard let b = bed(wid), bedSurface(wid, at: x - 10) != nil, bedSurface(wid, at: x + 10) != nil,
                  wid < 0 || (x > b.minX + 26 && x < (windows[wid]?.maxX ?? 0) - 26),
                  !sprouts.contains(where: { $0.windowID == wid && abs(sproutX($0) - x) < 40 }) else { continue }
            spot = (wid, x - b.minX)
        }
        guard let s = spot, let b = bed(s.window) else { return }
        let kinds: [(MossSprout.Kind, Double)] = [(.daisy, 1.0), (.mushroom, 0.8), (.berries, 0.8), (.dandelion, 1.0)]
        var r = rng.range(0, kinds.reduce(0) { $0 + $1.1 })
        let kind = kinds.first { r -= $0.1; return r <= 0 }?.0 ?? .daisy
        nextSproutID += 1
        sprouts.append(MossSprout(id: nextSproutID, kind: kind, windowID: s.window, offset: s.offset, growth: 0.02))
        sproutEvents.append(.sprouted(Vec2(b.minX + s.offset, b.y)))
    }

    func blowSeeds(from s: MossSprout, at p: Vec2, by: Int?) {
        let dir: Double = rng.chance(0.5) ? 1 : -1
        sproutEvents.append(.seedsBlown(p, toward: dir, by: by))
        // A seed or two comes down on another window top (or further along this one) and starts a tuft there.
        let tops = builtSurfaces.filter { $0.kind == .windowTop && $0.ownerID >= 0 && $0.width >= 100 }
        for _ in 0..<(rng.chance(0.5) ? 2 : 1) {
            guard let t = tops.randomElement(using: &rng), let w = windows[t.ownerID] else { break }
            let x = rng.range(t.minX + 40, t.maxX - 40)
            pendingSeeds.append((clock + rng.range(3, 6), t.ownerID, x - w.minX))
        }
    }

    // MARK: The Gremlets and the sprouts

    /// Not on the moss-chore timer: something ready in the moss is always worth a look.
    func sproutChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !sprouts.isEmpty, !compact, isFree(c), c.isGrounded, c.mossTask == nil, let s = supportingSurface(for: c), s.kind == .windowTop || s.kind == .floor else { return }
        for sp in sprouts where sp.windowID == s.ownerID && !creatures.contains(where: { $0.mossTask?.sprout == sp.id }) {
            let x = sproutX(sp)
            guard s.supports(x: x), abs(x - c.pos.x) < 700 else { continue }
            let near = abs(x - c.pos.x) < 250 ? 1.0 : 0.6
            if sp.ripe && sp.kind == .friendBloom {
                if clock - (sproutWatered[sp.id] ?? -999) > 90 {
                    add("admireFriendBloom", 0.8 * near) { self.startMossTask(c, .sprout(sp.id), walkTo: x - c.facing * 10) }
                }
            } else if sp.ripe {
                let w: Double = sp.kind == .dandelion ? 3.2 : sp.kind == .berries ? 2.6 : 2.8
                add("sprout-\(sp.kind.rawValue)", w * near) { self.startMossTask(c, .sprout(sp.id), walkTo: x - c.facing * 10) }
            } else if sp.growth > 0.08, clock - (sproutWatered[sp.id] ?? -999) > 40 {
                add("waterSprout", 1.0 * near) {
                    self.startMossTask(c, .sprout(sp.id), walkTo: x - c.facing * 10)
                    c.carrying = "can"
                }
            }
        }
    }

    /// The next step of a sprout task: walk over, then water it, or pick / eat / blow it.
    func sproutDecide(_ c: Creature, _ t: inout MossTask, id: Int, on s: Surface) {
        guard let i = sprouts.firstIndex(where: { $0.id == id }), s.ownerID == sprouts[i].windowID else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
        let sp = sprouts[i]
        let x = sproutX(sp)
        let p = Vec2(x, s.y)
        if !t.acting {
            let stand = x + (c.pos.x < x ? -12 : 12)
            if abs(c.pos.x - stand) > 6 { c.targetX = stand; c.set(.walk, duration: 20); return }
            t.acting = true; c.mossTask = t
            c.facing = x > c.pos.x ? 1 : -1
            c.workPose = "crouch"
            c.set(.work, duration: sp.ripe ? (sp.kind == .berries ? 2.2 : 1.4) : 2.0)
            if !sp.ripe { c.carrying = "can"; sproutEvents.append(.watered(p, by: c.id)) }
            return
        }
        c.mossTask = nil
        if sp.ripe && sp.kind == .friendBloom {
            // Not for picking: a sniff and a smile.
            sproutWatered[sp.id] = clock
            c.set(.react, duration: c.animationLength(for: .react))
            return
        }
        guard sp.ripe else {
            sprouts[i].growth = min(1, sp.growth + 0.2)
            if sprouts[i].growth >= 1 { sprouts[i].ripeAt = clock }
            sproutWatered[sp.id] = clock
            mossCare = min(1, mossCare + 0.05)
            c.carrying = nil
            c.idleVariant = "look"; c.set(.idle, duration: 1.2)
            return
        }
        sprouts.remove(at: i)
        switch sp.kind {
        case .berries:
            c.energy = min(1, c.energy + 0.25)
            sproutEvents.append(.ate(p, by: c.id))
            c.set(.react, duration: c.animationLength(for: .react))
        case .dandelion:
            blowSeeds(from: sp, at: p, by: c.id)
            c.set(.react, duration: c.animationLength(for: .react))
        case .daisy where notchHomeShowing && houseDaisies < 6 && (houseDaisies < 2 || rng.chance(0.6)):
            // Home with it for the window box, on a dandelion.
            sproutEvents.append(.picked(sp.kind, p, by: c.id))
            c.carrying = sp.kind.rawValue
            c.mossTask = MossTask(kind: .flowerBox, started: clock)
            startFloat(c, to: flowerBoxSpot, ride: .dandelion)
        case .friendBloom:
            break
        case .daisy, .mushroom:
            sproutEvents.append(.picked(sp.kind, p, by: c.id))
            // Off to give it to a friend on this window, if there's one about; otherwise, a happy little hop.
            if let f = creatures.filter({ $0 !== c && $0.isGrounded && $0.groundOwner == s.ownerID && !$0.isAsleep && $0.homeUntil == nil
                                          && abs($0.pos.x - c.pos.x) < 500 && s.supports(x: $0.pos.x) }).min(by: { abs($0.pos.x - c.pos.x) < abs($1.pos.x - c.pos.x) }) {
                c.mossTask = MossTask(kind: .gift(to: f.id, what: sp.kind), started: clock)
                c.carrying = sp.kind.rawValue
                c.targetX = f.pos.x + (c.pos.x < f.pos.x ? -22 : 22)
                c.set(.walk, duration: 15)
            } else {
                c.carrying = sp.kind.rawValue
                c.mossTask = MossTask(kind: .gift(to: -1, what: sp.kind), started: clock)
                c.set(.react, duration: c.animationLength(for: .react))
            }
        }
    }

    /// Carrying a daisy or mushroom over to a friend (or, with nobody about, just admiring it).
    func giftDecide(_ c: Creature, to: Int, what: MossSprout.Kind, started: Double, on s: Surface) {
        c.mossTask = nil
        guard to >= 0, let f = creature(id: to), f.groundOwner == s.ownerID, s.supports(x: f.pos.x) else {
            c.idleVariant = "look"; c.set(.idle, duration: 1.0)
            return
        }
        let stand = f.pos.x + (c.pos.x < f.pos.x ? -22 : 22)
        if abs(c.pos.x - stand) > 10, clock - started < 20 {
            c.mossTask = MossTask(kind: .gift(to: to, what: what), started: started)
            c.targetX = stand; c.set(.walk, duration: 10)
            return
        }
        c.facing = f.pos.x > c.pos.x ? 1 : -1
        sproutEvents.append(.gave(what, from: c.id, to: f.id))
        c.set(.wave, duration: 1.2)
        if f.job == nil, f.mossTask == nil, f.expedition == nil, f.isGrounded {
            endSocial(f)
            f.facing = -c.facing
            f.set(.react, duration: f.animationLength(for: .react))
        }
    }

    /// Where a Gremlet stands on the porch to put a daisy in the window box (just in front of it).
    var flowerBoxSpot: Vec2 {
        guard let n = notchHome else { return .zero }
        return Vec2(n.houseMinX + 14, n.porch.y)
    }

    func flowerBoxDecide(_ c: Creature, _ t: inout MossTask, on s: Surface) {
        guard s.ownerID == World.notchPorchOwner, notchHomeShowing else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
        if !t.acting {
            let x = flowerBoxSpot.x
            if abs(c.pos.x - x) > 6 { c.targetX = x; c.set(.walk, duration: 10); return }
            t.acting = true; c.mossTask = t
            c.facing = 1
            c.workPose = "crouch"; c.set(.work, duration: 1.6)
            return
        }
        c.mossTask = nil
        rollDaisyDay()
        houseDaisies = min(6, houseDaisies + 1)
        sproutEvents.append(.boxed(flowerBoxSpot + Vec2(0, 14), by: c.id))
        c.set(.react, duration: c.animationLength(for: .react))
    }

    /// The window box starts each day fresh.
    func rollDaisyDay() {
        let day = Int((wallClock + Double(TimeZone.current.secondsFromGMT())) / 86_400)
        if day != houseDaisiesDay { houseDaisiesDay = day; houseDaisies = 0 }
    }

    /// `gremlet sprout [kind]`: something comes up now, already grown (to try it out).
    @discardableResult
    public func sproutNow(_ kind: MossSprout.Kind? = nil, ripe: Bool = true) -> Bool {
        let tops = surfaces.filter { $0.kind == .windowTop && $0.ownerID >= 0 && $0.width >= 100 && windows[$0.ownerID] != nil }
        guard let t = tops.randomElement(using: &rng), let w = windows[t.ownerID] else { return false }
        let x = rng.range(t.minX + 30, t.maxX - 30)
        nextSproutID += 1
        sprouts.append(MossSprout(id: nextSproutID, kind: kind ?? MossSprout.Kind.wild.randomElement(using: &rng)!, windowID: t.ownerID,
                                  offset: x - w.minX, growth: ripe ? 1 : 0.1, ripeAt: ripe ? clock : nil))
        sproutEvents.append(.sprouted(Vec2(x, w.maxY)))
        nextMossTaskAt = min(nextMossTaskAt, clock)
        return true
    }
}

extension MossTask {
    /// The sprout this task is about, if any.
    var sprout: Int? { if case .sprout(let id) = kind { return id }; return nil }
}
