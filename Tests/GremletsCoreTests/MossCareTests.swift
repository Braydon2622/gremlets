import Testing
@testable import GremletsCore

@Suite struct MossCareTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func mossNobodyTendsDriesOutAndShrinks() {
        let w = World(seed: 121)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.mossMinutes = 120
        for _ in 0..<(20 * 60 * 60 * 2) { w.step(1.0 / 20) }   // two hours, nobody about
        #expect(w.mossThirsty)
        #expect(w.mossMinutes < 120, "neglected moss shrinks back (\(w.mossMinutes))")
    }

    @Test func gremletsWaterTheMossAndItThrives() {
        let w = World(seed: 122)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 0, w: 900, h: 120))])
        w.mossMinutes = 120
        w.mossCare = 0.2
        for x in [400.0, 700] { w.spawn(testSpecies(scale: 10), at: Vec2(x, 140)) }
        for _ in 0..<(20 * 60 * 60) { w.step(1.0 / 20) }   // an hour
        #expect(!w.mossThirsty, "kept watered (care \(w.mossCare))")
        #expect(w.mossMinutes > 120, "and still growing (\(w.mossMinutes))")
    }
}

@Suite struct StrandTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    func world() -> World {
        let w = World(seed: 131)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 100, w: 700, h: 400))])
        w.mossMinutes = 120
        for _ in 0..<70 { w.step(1.0 / 60) }
        return w
    }

    @Test func aLongStrandGetsPrunedWithAFriendHoldingIt() throws {
        let w = world()
        w.strandGrowth["w1r"] = 400
        w.rebuildVines()
        let v = try #require(w.mossVines.first { $0.key == "w1r" })
        #expect(v.length > 200, "hanging well down the window")
        #expect(w.mossVines.contains { $0.key == "w1r2" }, "with a shorter strand beside it")
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(900, 520))
        let f = w.spawn(testSpecies(scale: 10), at: Vec2(700, 520))
        for _ in 0..<60 { w.step(1.0 / 60) }
        w.startMossTask(c, .prune(vine: "w1r"), walkTo: v.x - 16)
        var held = false, pruned = false
        for _ in 0..<(60 * 40) where !pruned {
            w.step(1.0 / 60)
            if case .hold? = f.mossTask?.kind { held = true }
            pruned = w.drainMossEvents().contains { if case .pruned = $0 { return true }; return false }
        }
        #expect(pruned)
        #expect(held, "the friend came to hold it")
        w.rebuildVines()
        #expect(try #require(w.mossVines.first { $0.key == "w1r" }).length < v.length * 0.6)
        // And the pruner climbs back up onto the window.
        for _ in 0..<(60 * 10) where c.groundOwner != 1 { w.step(1.0 / 60) }
        #expect(c.groundOwner == 1)
    }

    @Test func slidingDownAStrandEndsOnTheFloor() throws {
        let w = world()
        let v = try #require(w.mossVines.first { $0.key == "w1l" })
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(400, 520))
        for _ in 0..<60 { w.step(1.0 / 60) }
        w.startMossTask(c, .slide(vine: v.key), walkTo: v.x + 16)
        var slid = false
        for _ in 0..<(60 * 20) { w.step(1.0 / 60); if c.climb?.sliding == true { slid = true } }
        #expect(slid)
        #expect(c.isGrounded && c.pos.y < 100, "landed down below (\(c.pos))")
    }
}
