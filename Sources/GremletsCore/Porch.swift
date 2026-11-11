import Foundation

/// Three more bits of life around the hanging home (Hanging.swift, Homestead.swift):
///
/// - **The vegetable patch.** A little bed along the front of the nest hut: carrots, radishes and peas. Gremlets
///   float up to sow it, water it (from the rain barrel when there's some), and pick what's ripe for the pantry.
///   Rain waters it too; left dry, it stops growing until someone comes.
/// - **The mailbox.** It hangs under the porch. A Claude session that finishes while you're away leaves a postcard
///   in it (what got done), and its little flag goes up. Rest the pointer on the mailbox to read them.
/// - **Lanterns on the moss.** Come dusk, Gremlets set tiny lanterns along the mossy window tops; they glow all
///   night, go out at dawn, and get taken in again in the morning.
public struct PatchPlot: Equatable, Sendable, Codable {
    public enum Crop: String, CaseIterable, Sendable, Codable {
        case carrot, radish, peas
        /// Only from a friend's seeds (a Gremlet back from their screen, or one of theirs visiting): Seasons.swift.
        case strawberry, pumpkin, tomato
        public static let home: [Crop] = [.carrot, .radish, .peas]
        public static let friends: [Crop] = [.strawberry, .pumpkin, .tomato]
    }
    public internal(set) var crop: Crop?
    /// 0...1 (ripe at 1).
    public internal(set) var growth = 0.0
    /// How wet the soil is, 0...1: it only grows while there's some.
    public internal(set) var water = 0.0
    public init(crop: Crop? = nil, growth: Double = 0, water: Double = 0) { self.crop = crop; self.growth = growth; self.water = water }
    public var ripe: Bool { crop != nil && growth >= 1 }
    public var dry: Bool { crop != nil && !ripe && water < 0.25 }
}

public struct Postcard: Equatable, Sendable, Codable {
    public let project: String
    public let text: String
    /// When it came (wall clock).
    public let at: Double
    public internal(set) var read = false
    public init(project: String, text: String, at: Double, read: Bool = false) { self.project = project; self.text = text; self.at = at; self.read = read }
}

public struct MossLantern: Equatable, Sendable {
    public let id: Int
    public let windowID: Int
    /// From the window's left edge.
    public let offset: Double
    public internal(set) var lit = true
}

extension World {
    static let patchPlots = 3
    static let mailboxMax = 6
    static let lanternMax = 5
    /// Seconds from sowing to ripe (while watered), and how long a watering lasts.
    static let patchGrowSeconds = 2400.0
    static let patchDrySeconds = 1800.0

    // MARK: The vegetable patch

    /// The nest hut's porch (the patch is in front of the hut, whichever home is showing).
    var nestPorch: Surface? {
        guard !compact else { return nil }
        return topStructures.first { $0.kind == .nestHut }?.surface
    }

    /// Where each plot is (its middle, on the porch).
    public func patchSpot(_ i: Int) -> Vec2? {
        guard let p = nestPorch else { return nil }
        return Vec2(p.minX + 36 + Double(i) * 9, p.y)
    }

    func updatePatch(_ dt: Double) {
        let wet = weather?.sky.isWet == true
        for i in vegPatch.indices where vegPatch[i].crop != nil {
            if wet { vegPatch[i].water = 1 }
            vegPatch[i].water = max(0, vegPatch[i].water - dt / World.patchDrySeconds)
            guard vegPatch[i].water > 0, vegPatch[i].growth < 1 else { continue }
            vegPatch[i].growth = min(1, vegPatch[i].growth + dt / World.patchGrowSeconds * (isNight ? 0.5 : 1) * (pollinating ? 1.3 : 1))
            if vegPatch[i].growth >= 1, let p = patchSpot(i) { homeEvents.append(.patchRipe(p)) }
        }
    }

    /// What needs doing in the patch most: something ripe, then something dry, then an empty plot to sow.
    func patchJob() -> (plot: Int, weight: Double)? {
        if let i = vegPatch.indices.first(where: { vegPatch[$0].ripe }) { return (i, 2.2) }
        if let i = vegPatch.indices.first(where: { vegPatch[$0].dry }) { return (i, 1.8) }
        if !isNight, let i = vegPatch.indices.first(where: { vegPatch[$0].crop == nil }) { return (i, 0.9) }
        return nil
    }

    func patchChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !compact, isFree(c), c.isGrounded, !c.isAsleep, c.mossTask == nil, clock >= nextPatchAt, let porch = nestPorch,
              let s = supportingSurface(for: c), sameScreen(c.pos, Vec2(porch.minX, porch.y)), let job = patchJob(),
              s.ownerID == porch.ownerID || s.kind == .windowTop || s.kind == .floor,
              !creatures.contains(where: { if case .tendPatch? = $0.mossTask?.kind { return true }; return false }) else { return }
        add("tendPatch", job.weight + (s.ownerID == porch.ownerID ? 1.5 : 0)) { self.startPatch(c) }
    }

    func startPatch(_ c: Creature) {
        guard let porch = nestPorch, let job = patchJob(), let spot = patchSpot(job.plot) else { return }
        nextPatchAt = clock + rng.range(40, 110)
        endSocial(c)
        c.mossTask = MossTask(kind: .tendPatch(done: 0), started: clock)
        if c.groundOwner == porch.ownerID { c.targetX = spot.x; c.facing = spot.x > c.pos.x ? 1 : -1; c.set(.walk, duration: 10) }
        else { startFloat(c, to: spot, ride: .dandelion) }
    }

    func tendPatchDecide(_ c: Creature, _ t: inout MossTask, done: Int, on s: Surface) {
        guard let porch = nestPorch, s.ownerID == porch.ownerID, let job = patchJob(), let spot = patchSpot(job.plot) else {
            // Didn't make it up, or nothing left to do.
            c.mossTask = nil; c.carrying = nil
            c.idleVariant = "look"; c.set(.idle, duration: rng.range(1, 2.5))
            if s.ownerID == nestPorch?.ownerID, done > 0 { c.driftDown = !isNight && rng.chance(0.6) }
            return
        }
        let p = vegPatch[job.plot]
        if !t.acting {
            if abs(c.pos.x - spot.x) > 6, clock - t.started < 25 { c.targetX = spot.x; c.set(.walk, duration: 10); return }
            t.acting = true; c.mossTask = t
            c.facing = 1
            c.carrying = p.dry ? "can" : nil
            c.workPose = "crouch"; c.set(.work, duration: p.ripe ? 1.6 : 2.2)
            return
        }
        if p.ripe, let crop = p.crop {
            vegPatch[job.plot] = PatchPlot()
            homeCare += 1
            homeEvents.append(.harvested(spot + Vec2(0, 10), by: c.id, what: crop.rawValue))
            c.carrying = crop.rawValue
            // The bees have been at it: sometimes there's extra, straight into the pantry.
            if hasHive, pantry < World.pantryMax - 1, rng.chance(0.35) { pantry += 1; homeEvents.append(.beeBonus(spot + Vec2(0, 18))) }
            if pantry < World.pantryMax, let pantrySpot = pantrySpot, let home = homePorch {
                // Into the pantry with it: along the porch, or up to the house under the notch.
                c.mossTask = MossTask(kind: .stock(what: crop.rawValue), started: clock)
                if home.ownerID == porch.ownerID { c.targetX = pantrySpot.x; c.set(.walk, duration: 10) }
                else { startFloat(c, to: pantrySpot, ride: .dandelion) }
            } else {
                // The pantry's full: a snack, then.
                c.mossTask = nil
                c.energy = min(1, c.energy + 0.2)
                c.set(.react, duration: c.animationLength(for: .react))
            }
            return
        }
        if p.dry {
            let rain = rainBarrel >= 0.05
            if rain { rainBarrel -= 0.05 }
            vegPatch[job.plot].water = 1
            homeEvents.append(.patchWatered(spot + Vec2(0, 8), by: c.id, rain: rain))
        } else if p.crop == nil {
            let crop = seedTin.randomElement(using: &rng) ?? .carrot
            vegPatch[job.plot] = PatchPlot(crop: crop, growth: 0.02, water: max(p.water, 0.7))
            homeEvents.append(.sowed(spot + Vec2(0, 6), by: c.id, what: crop.rawValue))
        }
        c.carrying = nil
        // Anything else wanting doing? (A few jobs in one go, then off.)
        if done < 2, patchJob() != nil {
            c.mossTask = MossTask(kind: .tendPatch(done: done + 1), started: clock)
            c.set(.idle, duration: 0.4)
        } else {
            c.mossTask = nil
            c.set(.react, duration: c.animationLength(for: .react))
            c.driftDown = !isNight && rng.chance(0.6)
        }
    }

    /// `gremlet patch [ripe]`: sow every empty plot now (ripe: ready to pick), to try it out.
    @discardableResult
    public func sowPatchNow(ripe: Bool) -> Bool {
        guard nestPorch != nil else { return false }
        for i in vegPatch.indices where vegPatch[i].crop == nil || ripe {
            vegPatch[i] = PatchPlot(crop: vegPatch[i].crop ?? seedTin.randomElement(using: &rng) ?? .carrot, growth: ripe ? 1 : 0.3, water: 0.8)
        }
        nextPatchAt = 0
        return true
    }

    /// The patch as a string to save (and back): "carrot:0.42:0.9,-,peas:1:0".
    public var patchSaved: String {
        get { vegPatch.map { p in p.crop.map { "\($0.rawValue):\((p.growth * 1000).rounded() / 1000):\((p.water * 1000).rounded() / 1000)" } ?? "-" }.joined(separator: ",") }
        set {
            let parts = newValue.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            for i in vegPatch.indices {
                guard i < parts.count else { vegPatch[i] = PatchPlot(); continue }
                let f = parts[i].split(separator: ":").map(String.init)
                if f.count == 3, let crop = PatchPlot.Crop(rawValue: f[0]), let g = Double(f[1]), let w = Double(f[2]) {
                    vegPatch[i] = PatchPlot(crop: crop, growth: g.clamped(0, 1), water: w.clamped(0, 1))
                } else { vegPatch[i] = PatchPlot() }
            }
        }
    }

    // MARK: The mailbox

    /// Where the mailbox hangs (from the underside of the porch, near the house).
    public var mailboxSpot: Vec2? {
        guard let p = homePorch else { return nil }
        return Vec2(p.minX + 8, p.y)
    }

    /// The mailbox's outline: resting the pointer here opens the postcards.
    public var mailboxRect: Rect? { mailboxSpot.map { Rect(x: $0.x - 14, y: $0.y - 42, w: 28, h: 42) } }

    public var unreadMail: Int { mailbox.filter { !$0.read }.count }

    /// A postcard for the mailbox (a Claude session finished while you were away).
    public func post(_ card: Postcard) {
        mailbox.append(card)
        if mailbox.count > World.mailboxMax { mailbox.removeFirst(mailbox.count - World.mailboxMax) }
        if let m = mailboxSpot { homeEvents.append(.mailArrived(m)) }
        // Someone awake nearby looks up at the flag going up.
        if let m = mailboxSpot, let c = creatures.first(where: { ($0.pos - m).length < 260 && $0.isGrounded && !$0.isAsleep && isFree($0) && $0.mossTask == nil }) {
            c.facing = m.x > c.pos.x ? 1 : -1
            c.set(.wave, duration: 1.4)
        }
    }

    /// Hovering the mailbox: open it after a moment; the postcards count as read once they've been up a little while.
    func updateMailHover() {
        guard let cur = cursor, let r = mailboxRect, !mailbox.isEmpty, r.contains(cur) else {
            mailHoverSince = nil
            if mailOpen, clock - mailLastHover > 0.8 { mailOpen = false }
            return
        }
        mailLastHover = clock
        if let since = mailHoverSince {
            if clock - since > 0.35 { mailOpen = true }
            if clock - since > 2.5, unreadMail > 0 {
                for i in mailbox.indices { mailbox[i].read = true }
                homeEvents.append(.mailRead)
            }
        } else { mailHoverSince = clock }
    }

    // MARK: Lanterns on the moss

    /// Lantern time: the evening, once it's dark (not the small hours).
    var lanternEvening: Bool { isNight && (17...23).contains(localHour) }

    /// Where a lantern stands (global), and whether its bit of window top is showing.
    public func lanternSpot(_ l: MossLantern) -> (pos: Vec2, visible: Bool)? {
        guard let w = windows[l.windowID] else { return nil }
        let p = Vec2(w.minX + l.offset, w.maxY)
        return (p, topEdges.contains { $0.ownerID == l.windowID && abs($0.y - p.y) < 1 && $0.supports(x: p.x) })
    }

    func lanternChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !compact, isFree(c), c.isGrounded, !c.isAsleep, c.mossTask == nil, let s = supportingSurface(for: c),
              s.kind == .windowTop, s.ownerID >= 0, windows[s.ownerID] != nil else { return }
        if lanternEvening, mossMinutes >= 5, clock >= nextLanternAt, mossLanterns.count < World.lanternMax,
           !creatures.contains(where: { if case .lantern? = $0.mossTask?.kind { return true }; return false }),
           let x = lanternPlace(on: s, near: c.pos.x), let w = windows[s.ownerID] {
            add("hangLantern", 1.4 + (mossLanterns.isEmpty ? 1.2 : 0)) {
                self.nextLanternAt = self.clock + self.rng.range(25, 70)
                self.startMossTask(c, .lantern(window: s.ownerID, offset: x - w.minX), walkTo: x)
                c.carrying = "lantern"
            }
        }
        if !isNight, (6...11).contains(localHour), let l = mossLanterns.first(where: { $0.windowID == s.ownerID }),
           let spot = lanternSpot(l), s.supports(x: spot.pos.x),
           !creatures.contains(where: { if case .unlantern(l.id)? = $0.mossTask?.kind { return true }; return false }) {
            add("takeLantern", 1.6) { self.startMossTask(c, .unlantern(l.id), walkTo: spot.pos.x - 10) }
        }
    }

    /// A spot along this window top for a lantern: near the Gremlet, clear of the ends and the other lanterns.
    func lanternPlace(on s: Surface, near x: Double) -> Double? {
        guard s.width >= 80 else { return nil }
        let others = mossLanterns.compactMap { lanternSpot($0)?.pos }.filter { abs($0.y - s.y) < 2 }
        let tries = (0..<8).map { _ in (x + rng.range(-180, 180)).clamped(s.minX + 24, s.maxX - 24) }
        return tries.first { t in others.allSatisfy { abs($0.x - t) >= 110 } }
    }

    func lanternDecide(_ c: Creature, _ t: inout MossTask, window: Int, offset: Double, on s: Surface) {
        guard let w = windows[window], s.ownerID == window else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
        let x = w.minX + offset
        if !t.acting {
            if abs(c.pos.x - (x - 10)) > 6, clock - t.started < 20 { c.targetX = x - 10; c.set(.walk, duration: 12); return }
            t.acting = true; c.mossTask = t
            c.facing = 1
            c.workPose = "crouch"; c.set(.work, duration: 1.8)
            return
        }
        c.mossTask = nil
        guard mossLanterns.count < World.lanternMax, s.supports(x: x) else { c.set(.idle, duration: 0.4); return }
        nextLanternID += 1
        mossLanterns.append(MossLantern(id: nextLanternID, windowID: window, offset: offset))
        homeEvents.append(.lanternHung(Vec2(x, w.maxY + 14), by: c.id))
        c.idleVariant = "look"; c.set(.idle, duration: rng.range(2, 4))
    }

    func unlanternDecide(_ c: Creature, _ t: inout MossTask, id: Int, on s: Surface) {
        guard let l = mossLanterns.first(where: { $0.id == id }), let spot = lanternSpot(l), s.ownerID == l.windowID else {
            c.mossTask = nil; c.set(.idle, duration: 0.3); return
        }
        if !t.acting {
            if abs(c.pos.x - (spot.pos.x - 10)) > 6, clock - t.started < 20 { c.targetX = spot.pos.x - 10; c.set(.walk, duration: 12); return }
            t.acting = true; c.mossTask = t
            c.facing = 1
            c.workPose = "crouch"; c.set(.work, duration: 1.4)
            return
        }
        c.mossTask = nil
        mossLanterns.removeAll { $0.id == id }
        homeEvents.append(.lanternTaken(spot.pos + Vec2(0, 10), by: c.id))
        c.carrying = "lantern"
        c.set(.react, duration: c.animationLength(for: .react))
    }

    func updateLanterns() {
        // Their window closed: gone with it.
        mossLanterns.removeAll { windows[$0.windowID] == nil }
        let night = isNight
        for i in mossLanterns.indices where mossLanterns[i].lit != night {
            mossLanterns[i].lit = night
        }
        // Any still out by late morning fade away by themselves.
        if !night, localHour >= 12, !mossLanterns.isEmpty { mossLanterns.removeAll() }
        // Carried in: put away after a moment.
        for c in creatures where c.carrying == "lantern" && c.mossTask == nil && c.lanternUntil == nil && c.activity != .walk && c.activity != .react {
            c.carrying = nil
        }
    }

    /// `gremlet lanterns`: whoever's free sets one out now (any time of day, to try it out).
    @discardableResult
    public func hangLanternNow() -> Bool {
        for c in creatures.shuffled(using: &rng) where isFree(c) && c.isGrounded && c.mossTask == nil {
            guard let s = supportingSurface(for: c), s.kind == .windowTop, s.ownerID >= 0, let w = windows[s.ownerID],
                  let x = lanternPlace(on: s, near: c.pos.x) else { continue }
            startMossTask(c, .lantern(window: s.ownerID, offset: x - w.minX), walkTo: x)
            c.carrying = "lantern"
            return true
        }
        return false
    }
}
