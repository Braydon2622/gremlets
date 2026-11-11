import Foundation
import Testing
@testable import GremletsCore

/// Bees and the hive, seasons on the porch, the firefly jar and the seed swap (Seasons.swift).
@Suite struct SeasonsTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
    func world(seed: UInt64, hour: Int = 11) -> World {
        let w = World(seed: seed)
        w.maxHobbies = 0
        w.topCornerPerches = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 0, y: 0, w: 600, h: 520))])
        let tz = Double(TimeZone.current.secondsFromGMT())
        w.wallClock = 1_728_000_000.0 - 1_728_000_000.0.truncatingRemainder(dividingBy: 86_400) + Double(hour) * 3600 - tz
        w.liveWeather = LocalWeather(sky: .clear)
        return w
    }
    func steps(_ w: World, _ seconds: Double) { for _ in 0..<Int(seconds * 60) { w.step(1.0 / 60) } }
    func ready(_ w: World, _ c: Creature) {
        for _ in 0..<(60 * 60) where !(c.isGrounded && c.groundOwner == 1 && c.mossTask == nil && c.job == nil) { w.step(1.0 / 60) }
    }

    @Test func theHiveComesWithTheHouseAndItsBeesSpeedThePatch() {
        let plain = world(seed: 801), hived = world(seed: 801)
        hived.homeCare = 60
        #expect(!plain.hasHive && hived.hasHive && hived.beesOut && hived.hiveSpot != nil)
        for w in [plain, hived] { w.nextPatchAt = .infinity; w.patchSaved = "carrot:0.1:1,-,-" }
        steps(plain, 60); steps(hived, 60)
        let a = plain.vegPatch[0].growth - 0.1, b = hived.vegPatch[0].growth - 0.1
        #expect(b > a * 1.25, "the bees help it along")
        hived.liveWeather = LocalWeather(sky: .rain)
        #expect(!hived.beesOut, "in out of the rain")
    }

    @Test func autumnLeavesPileUpAndSomeoneSweepsThemOff() throws {
        let w = world(seed: 802)
        w.month = 10
        w.nextPatchAt = .infinity
        steps(w, 60)
        #expect(w.porchLeaves > 0.03 && w.roofSnow == 0)
        w.porchLeaves = 0.9
        #expect(w.leafLevel == 3)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 522))
        ready(w, c)
        #expect(w.ideas(for: c).contains(.sweep))
        #expect(w.ask(c, .sweep))
        var swept = false
        for _ in 0..<(60 * 40) where !swept { w.step(1.0 / 60); swept = w.drainHomeEvents().contains { if case .swept(_, _, false) = $0 { return true }; return false } }
        #expect(swept && w.porchLeaves < 0.05)
    }

    @Test func winterSnowSettlesAndMeltsInSpring() {
        let w = world(seed: 803)
        w.month = 1
        w.liveWeather = LocalWeather(sky: .snow)
        steps(w, 120)
        #expect(w.roofSnow > 0.2)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 522))
        ready(w, c)
        w.roofSnow = 0.9
        #expect(!w.ideas(for: c).contains(.sweep), "not while it's still snowing")
        w.month = 4
        w.liveWeather = LocalWeather(sky: .clear)
        w.nextSweepAt = .infinity
        let before = w.roofSnow
        steps(w, 60)
        #expect(w.roofSnow < before, "melting")
    }

    @Test func firefliesGoInTheJarAtNightAndAreLetGoAtDawn() throws {
        let w = world(seed: 804, hour: 22)
        w.isNight = true
        steps(w, 0.5)
        let j = try #require(w.jarSpot)
        for _ in 0..<7 { _ = w.jarFirefly(from: j) }
        #expect(w.fireflyJar == World.jarMax)
        w.isNight = false
        let tz = Double(TimeZone.current.secondsFromGMT())
        w.wallClock = 1_728_000_000.0 - 1_728_000_000.0.truncatingRemainder(dividingBy: 86_400) + 6 * 3600 - tz
        _ = w.drainHomeEvents()
        steps(w, 0.2)
        #expect(w.fireflyJar == 0)
        #expect(w.drainHomeEvents().contains { if case .jarReleased(_, 5) = $0 { return true }; return false })
        #expect(!w.jarFirefly(from: j), "only at night")
    }

    @Test func seedsFromAFriendJoinThePatch() {
        let w = world(seed: 805)
        #expect(w.seedTin == PatchPlot.Crop.home)
        #expect(World.friendCrop(for: "abc") == World.friendCrop(for: "abc"))
        #expect(PatchPlot.Crop.friends.contains(World.friendCrop(for: "someone")))
        let crop = World.friendCrop(for: "friend-1")
        #expect(w.receiveSeeds(crop, by: nil))
        #expect(!w.receiveSeeds(crop, by: nil), "already have those")
        #expect(w.seedTin.contains(crop) && w.newFriendCrop != crop)
        let again = world(seed: 806)
        again.seedTinSaved = w.seedTinSaved
        #expect(again.seedTin == w.seedTin)
        again.patchSaved = "pumpkin:1:0,-,-"
        #expect(again.vegPatch[0].ripe && again.vegPatch[0].crop == .pumpkin)
        // Sowing picks from the tin.
        again.seedTinSaved = "strawberry,pumpkin,tomato"
        var seen = Set<PatchPlot.Crop>()
        for _ in 0..<20 { again.patchSaved = "-,-,-"; again.sowPatchNow(ripe: false); for p in again.vegPatch { if let c = p.crop { seen.insert(c) } } }
        #expect(!seen.isDisjoint(with: PatchPlot.Crop.friends))
    }
}
