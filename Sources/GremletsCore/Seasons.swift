import Foundation

/// The hanging home through the year, and a few more small things on its porch:
///
/// - **Bees and a hive.** Once the house has grown a bit, a little hive hangs off the nest hut. Its bees (and the
///   bees out in the moss) visit the vegetable patch in the daytime: it grows faster, and a picking sometimes comes
///   with something extra for the pantry.
/// - **Seasons on the porch.** Autumn leaves pile up on the hut's roof and porch, winter snow settles on them, and a
///   Gremlet floats up now and then to sweep it all off. (Spring blossoms drift from the roof: the renderer's.)
/// - **The firefly jar.** On the rain barrel's lid: fireflies caught at night go into it and light the porch, and at
///   dawn they're let go.
/// - **Seed swap.** A Gremlet back from a friend's screen brings seeds from there, and a friend's Gremlet visiting
///   brings seeds from theirs: strawberries, pumpkins, tomatoes join the patch.
extension World {
    public static let jarMax = 5

    // MARK: Bees

    /// The hive hangs off the nest hut once the house has grown a little.
    public var hasHive: Bool { nestPorch != nil && houseStage >= 2 }

    /// Bees out and about over the patch: daytime, not raining.
    public var beesOut: Bool { hasHive && !isNight && weather?.sky.isWet != true && weather?.sky != .snow }

    /// The patch is being visited by bees (the hive's, or the moss's).
    var pollinating: Bool { beesOut || (!isNight && critters.contains { $0.kind == .bee && !$0.leaving }) }

    /// Where the hive hangs (its top, under the eave on the hut's left side).
    public var hiveSpot: Vec2? {
        guard hasHive, let p = nestPorch else { return nil }
        return Vec2(p.minX - 6, p.y + 40)
    }

    // MARK: Seasons on the porch

    var autumn: Bool { (9...11).contains(month) }
    var winter: Bool { month == 12 || month <= 2 }

    func updateSeasons(_ dt: Double) {
        guard nestPorch != nil else { return }
        let snowing = weather?.sky == .snow
        if autumn { porchLeaves = min(1, porchLeaves + dt / 1500) } else { porchLeaves = max(0, porchLeaves - dt / 3000) }
        if snowing { roofSnow = min(1, roofSnow + dt / 500) }
        else if winter { roofSnow = min(1, roofSnow + dt / 2400) }
        else { roofSnow = max(0, roofSnow - dt / 1200) }
    }

    /// 0...3: how much is piled up (for the picture).
    public var leafLevel: Int { porchLeaves < 0.15 ? 0 : porchLeaves < 0.45 ? 1 : porchLeaves < 0.8 ? 2 : 3 }
    public var snowLevel: Int { roofSnow < 0.15 ? 0 : roofSnow < 0.45 ? 1 : roofSnow < 0.8 ? 2 : 3 }

    func seasonChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !compact, isFree(c), c.isGrounded, !c.isAsleep, c.mossTask == nil, clock >= nextSweepAt, let porch = nestPorch,
              max(porchLeaves, roofSnow) >= 0.45, let s = supportingSurface(for: c), sameScreen(c.pos, Vec2(porch.minX, porch.y)),
              s.ownerID == porch.ownerID || s.kind == .windowTop || s.kind == .floor,
              weather?.sky != .snow,
              !creatures.contains(where: { if case .sweep? = $0.mossTask?.kind { return true }; return false }) else { return }
        add("sweepPorch", 0.8 + max(porchLeaves, roofSnow) + (s.ownerID == porch.ownerID ? 1.5 : 0)) { self.startSweep(c) }
    }

    func startSweep(_ c: Creature) {
        guard let porch = nestPorch else { return }
        nextSweepAt = clock + rng.range(60, 160)
        endSocial(c)
        c.mossTask = MossTask(kind: .sweep, started: clock)
        let x = porch.minX + 70
        if c.groundOwner == porch.ownerID { c.targetX = x; c.facing = x > c.pos.x ? 1 : -1; c.set(.walk, duration: 10) }
        else { startFloat(c, to: Vec2(x, porch.y), ride: .dandelion) }
    }

    func sweepDecide(_ c: Creature, _ t: inout MossTask, on s: Surface) {
        guard let porch = nestPorch, s.ownerID == porch.ownerID else { c.mossTask = nil; c.set(.idle, duration: 0.4); return }
        let x = porch.minX + 70
        if !t.acting {
            if abs(c.pos.x - x) > 6, clock - t.started < 25 { c.targetX = x; c.set(.walk, duration: 10); return }
            t.acting = true; c.mossTask = t
            c.carrying = "broom"
            c.workPose = "crouch"; c.set(.work, duration: 3)
            return
        }
        c.mossTask = nil
        c.carrying = nil
        let snow = roofSnow > porchLeaves
        porchLeaves = 0; roofSnow = 0
        homeCare += 1
        homeEvents.append(.swept(Vec2(porch.minX + 50, porch.y + 10), by: c.id, snow: snow))
        c.set(.react, duration: c.animationLength(for: .react))
        c.driftDown = !isNight && rng.chance(0.6)
    }

    // MARK: The firefly jar

    /// Where the jar stands (on the rain barrel's lid).
    public var jarSpot: Vec2? { barrelSpot.map { Vec2($0.x + 1, $0.y + 22) } }

    /// A firefly caught at night goes into the jar (instead of off into the dark). True if it did.
    func jarFirefly(from p: Vec2) -> Bool {
        guard isNight, fireflyJar < World.jarMax, let j = jarSpot, sameScreen(p, j) else { return false }
        fireflyJar += 1
        homeEvents.append(.jarCaught(j))
        return true
    }

    /// Come morning, they're let go.
    func updateJar() {
        guard fireflyJar > 0, !isNight, (5...11).contains(localHour) || jarSpot == nil else { return }
        if let j = jarSpot { homeEvents.append(.jarReleased(j, count: fireflyJar)) }
        fireflyJar = 0
    }

    // MARK: Seed swap

    /// Seeds from a friend: one of the friend crops, picked by who they're from (so each friend brings their own), or
    /// any one this patch hasn't grown yet.
    public static func friendCrop(for key: String) -> PatchPlot.Crop {
        let h = key.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return PatchPlot.Crop.friends[Int(h % UInt32(PatchPlot.Crop.friends.count))]
    }

    /// Seeds into the tin (the Gremlet `by` brought them). False if they're ones we already have.
    @discardableResult
    public func receiveSeeds(_ crop: PatchPlot.Crop, by: Int?) -> Bool {
        guard !seedTin.contains(crop) else { return false }
        seedTin.append(crop)
        homeEvents.append(.seedGift(by: by, what: crop.rawValue))
        // The next sowing is likely to be the new one: an empty plot gets it.
        if let i = vegPatch.indices.first(where: { vegPatch[$0].crop == nil }) { _ = i; nextPatchAt = min(nextPatchAt, clock + 20) }
        return true
    }

    /// A seed this patch doesn't have yet (for a Gremlet home from a friend's screen), if there's one left.
    public var newFriendCrop: PatchPlot.Crop? { PatchPlot.Crop.friends.first { !seedTin.contains($0) } }

    public var seedTinSaved: String {
        get { seedTin.map(\.rawValue).joined(separator: ",") }
        set {
            let got = newValue.split(separator: ",").compactMap { PatchPlot.Crop(rawValue: String($0)) }
            seedTin = PatchPlot.Crop.home + got.filter { !PatchPlot.Crop.home.contains($0) }
        }
    }
}
