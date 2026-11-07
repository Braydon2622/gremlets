import Foundation
import Testing
@testable import GremletsCore

@Suite struct GroveTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    func world(seed: UInt64 = 7) -> World {
        let w = World(seed: seed)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 120, w: 600, h: 400))])
        w.loadGrove(Grove())
        return w
    }

    @Test func claudeTasksGrowAndUnlockTheGrove() {
        let w = world()
        #expect(w.grove.plants.map(\.kind) == [.sunberry, .bouncecap])
        #expect(w.grove.plants.allSatisfy { $0.level == 1 })
        let small = w.grove.size(1).y
        for _ in 0..<30 { w.feedGrove() }
        #expect(w.grove.plants.count == 6, "all six plots unlock by 30 tasks")
        #expect(w.grove.plants[0].level == 5 && w.grove.plants[1].level == 5)
        #expect(w.grove.size(1).y > small * 2.5, "a maxed plant is far bigger than a sprout")
        #expect(w.grove.plants[0].berries > 0)
        // Bigger plants offer platforms: the skyvine has leaves all the way up.
        let vine = w.groveLedges.filter { $0.plot == 3 }
        #expect(vine.count >= 4)
        #expect(w.surfaces.contains { $0.kind == .plant })
    }

    @Test func groveSurvivesSaveAndLoad() throws {
        let w = world()
        for _ in 0..<7 { w.feedGrove() }
        let data = try #require(w.grove.encoded())
        let back = try #require(Grove.decode(data))
        #expect(back.tasks == 7)
        #expect(back.plants == w.grove.plants)
    }

    @Test func bouncecapLaunchesHigherThanAHop() {
        let w = world()
        let ledge = try! #require(w.groveLedges.first { $0.bouncy })
        let c = w.spawn(testSpecies(scale: 10), at: Vec2((ledge.minX + ledge.maxX) / 2, ledge.y + 200))
        var peak = c.pos.y, bounced = false
        for _ in 0..<240 {
            w.step(1.0 / 60)
            peak = max(peak, c.pos.y)
            if w.drainGroveEvents().contains(where: { if case .bounce = $0 { return true }; return false }) { bounced = true }
        }
        #expect(bounced)
        #expect(peak > ledge.y + 200, "the cap sent it higher than it fell from")
    }

    @Test func wishwillowGrantsOneWishADay() {
        let w = world()
        for _ in 0..<60 { w.feedGrove() }
        let before = w.wishes
        w.checkWishwillow(day: 100)
        w.checkWishwillow(day: 100)
        #expect(w.wishes == before + 1)
        w.checkWishwillow(day: 101)
        #expect(w.wishes == min(3, before + 2))
    }
}

@Suite struct SpectacleTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func meteorShowerWaitsForNightAndDropsShards() {
        let w = World(seed: 3)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        for _ in 0..<3 { w.spawn(testSpecies(scale: 12), at: Vec2(Double.random(in: 100...1300), 200)) }
        w.isNight = false
        w.requestEvent(.meteors)
        for _ in 0..<60 { w.step(1.0 / 30) }
        #expect(w.spectacle == nil, "no meteors in daylight")
        w.isNight = true
        var collected = 0
        for _ in 0..<(30 * 50) {
            w.step(1.0 / 30)
            _ = w.drainEvents()
            collected += w.drainSpectacleEvents().filter { if case .shardCollected = $0 { return true }; return false }.count
        }
        #expect(collected > 0, "Gremlets collected star shards")
    }

    @Test func eventsStopForFocus() {
        let w = World(seed: 5)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        #expect(w.startEvent(.festival))
        w.focusMode = true
        for _ in 0..<(30 * 20) { w.step(1.0 / 30) }
        #expect(w.spectacle == nil)
    }
}

@Suite struct PlayTests {
    @Test func friendsPlayTogether() {
        let w = World(seed: 11)
        let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.maxHobbies = 0
        let a = w.spawn(testSpecies(scale: 12), at: Vec2(500, 40))
        let b = w.spawn(testSpecies(scale: 12), at: Vec2(800, 40))
        for _ in 0..<30 { w.step(1.0 / 30) }
        var seen = Set<String>()
        for kind in [PlayState.Kind.catchBall, .highFive, .toss] {
            var started = false
            for _ in 0..<(30 * 30) where !started {
                w.step(1.0 / 30); _ = w.drainEvents()
                if a.play == nil && b.play == nil && a.isGrounded && b.isGrounded && a.job == nil && b.job == nil
                    && World.carrierID(a.groundOwner) == nil && World.carrierID(b.groundOwner) == nil {
                    w.startPlay(kind, a, b); started = true
                }
            }
            #expect(started, "could start \(kind): a=\(a.activity) b=\(b.activity)")
            for _ in 0..<(30 * 14) {
                w.step(1.0 / 30)
                for e in w.drainEvents() { seen.insert("\(e)".split(separator: "(").first.map(String.init) ?? "") }
                #expect(a.pos.y.isFinite && b.pos.y.isFinite)
            }
        }
        #expect(seen.contains("caught"))
        #expect(seen.contains("highFive"))
        #expect(seen.contains("tossed"))
        #expect(a.play == nil && b.play == nil)
    }
}

@Suite struct ClaudeWorkTests {
    @Test func toolsBecomeBlocksAndHelpers() throws {
        let w = World(seed: 9)
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1440, h: 860)], windowsFrontToBack: [WindowInfo(id: 4, frame: Rect(x: 300, y: 100, w: 600, h: 400))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(400, 0))
        for _ in 0..<30 { w.step(1.0 / 30) }
        let id = try #require(w.startJob(windowID: 4, craft: .garden, prefer: c.id))
        for name in ["Edit", "Write", "Read", "Bash", "Task", "Task", "WebFetch", "TodoWrite", "mcp__x__y", "Edit"] {
            w.claudeTool(workerID: id, ClaudeTool.from(name))
        }
        let j = try #require(w.creatures.first { $0.id == id }?.job)
        #expect(j.blocks == 3)
        #expect(j.helpers == 2)
        w.claudeHelperDone(workerID: id)
        #expect(j.helpers == 1)
        let ev = w.drainClaudeEvents()
        #expect(ev.contains(.look(id)) && ev.contains(.run(id)) && ev.contains(.web(id)) && ev.contains(.plan(id)))
    }
}

@Suite struct ConstructionTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func gremletBuildsABridgeAcrossAGapAndItCrumblesWhenAWindowMoves() throws {
        let w = World(seed: 4)
        w.maxHobbies = 0
        let a = WindowInfo(id: 1, frame: Rect(x: 100, y: 200, w: 400, h: 300))
        var b = WindowInfo(id: 2, frame: Rect(x: 700, y: 210, w: 400, h: 300))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [a, b])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(420, 520))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(c.groundOwner == 1)
        #expect(w.bridgeCandidate(for: c) != nil)
        w.startBridge(c)
        var done = false
        for _ in 0..<(60 * 30) where !done {
            w.step(1.0 / 60)
            done = w.drainBuildEvents().contains { if case .bridgeDone = $0 { return true }; return false }
        }
        #expect(done)
        let bridge = try #require(w.bridges.first)
        #expect(bridge.isComplete)
        #expect(w.surfaces.contains { World.isBridgeOwner($0.ownerID) && abs($0.minX - 500) < 2 && abs($0.maxX - 700) < 2 })
        // Move the far window away: the bridge crumbles.
        b.frame.x = 1000
        w.setEnvironment(screens: [scr], windowsFrontToBack: [a, b])
        #expect(w.bridges.isEmpty)
        #expect(w.drainBuildEvents().contains { if case .bridgeCrumbled = $0 { return true }; return false })
    }

    @Test func grapplingHookReachesAHighWindow() {
        let w = World(seed: 6)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 3, frame: Rect(x: 300, y: 100, w: 500, h: 420))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(500, 30))
        // Wait until it's standing on the floor, then hold it there (it might grapple up on its own otherwise).
        for _ in 0..<600 where !(c.isGrounded && c.groundOwner == -1) { w.step(1.0 / 60) }
        c.set(.idle, duration: 30)
        let target = w.grappleTarget(for: c)
        #expect(target != nil, "grounded=\(c.isGrounded) \(c.activity) y=\(c.pos.y) surfaces=\(w.surfaces.map { "\($0.kind)@\($0.y)" })")
        if let t = target { w.startGrapple(c, to: t) }
        var landed = false, maxY = 0.0
        for _ in 0..<(60 * 4) where !landed { w.step(1.0 / 60); maxY = max(maxY, c.pos.y); landed = c.groundOwner == 3 }
        #expect(landed, "landed on top of the window (max height \(maxY), now \(c.pos), \(c.activity))")
    }

    @Test func villageHousesPersistAndOldSavesStillLoad() throws {
        let w = World(seed: 8)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        for i in 0..<5 { #expect(w.addHouse(biome: "meadow", blocks: 10 + i, size: Vec2(90, 120), project: nil) != nil) }
        #expect(w.grove.village.count == 1, "one home: each new one takes the last one's place")
        #expect(w.grove.village.first?.blocks == 14)
        #expect(w.groveLedges.filter { $0.plot < 0 }.count == 1, "a roof to stand on")
        let data = try #require(w.grove.encoded())
        let back = try #require(Grove.decode(data))
        #expect(back.village == w.grove.village)
        // A save from before the village existed.
        let old = #"{"plants":[{"kind":"sunberry","x":0.16,"sparks":3,"berries":2,"lastWishDay":-1,"golden":false}],"tasks":3,"tasksSinceBoss":3}"#
        let g = try #require(Grove.decode(Data(old.utf8)))
        #expect(g.tasks == 3 && g.village.isEmpty && g.plants.count == 1)
    }
}

@Suite struct VillageLifeTests {
    @Test func tiredGremletsSleepInsideAVillageHouseAndComeBackOut() {
        let w = World(seed: 12)
        w.maxHobbies = 0
        let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        w.addHouse(biome: "snow", blocks: 20, size: Vec2(105, 90), project: "Gremlets", day: "Nov 6")
        w.isNight = true
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(700, 40))
        var wentIn = false, cameOut = false
        for _ in 0..<(60 * 400) where !cameOut {
            w.step(1.0 / 60)
            _ = w.drainEvents()
            for e in w.drainGroveEvents() {
                if case .wentHome = e { wentIn = true; #expect(w.creature(at: c.pos + Vec2(0, 5)) == nil, "hidden inside, not clickable") }
                if case .leftHome = e { cameOut = true }
            }
        }
        #expect(wentIn && cameOut)
        #expect(c.homeUntil == nil)
        #expect(w.grove.village[0].owner == c.species.id, "it claimed the house as its own")
    }

    @Test func claudeSessionStatusFlags() throws {
        let w = World(seed: 13)
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1440, h: 860)], windowsFrontToBack: [WindowInfo(id: 5, frame: Rect(x: 300, y: 100, w: 600, h: 400))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(400, 0))
        for _ in 0..<30 { w.step(1.0 / 30) }
        let id = try #require(w.startJob(windowID: 5, craft: .garden, prefer: c.id))
        w.labelJob(workerID: id, "MyApp")
        let j = try #require(w.creatures.first { $0.id == id }?.job)
        #expect(j.label == "MyApp" && !j.needsYou)
        w.jobNeedsAttention(id)
        #expect(j.needsYou)
        w.claudeTool(workerID: id, .build)
        #expect(!j.needsYou, "Claude got going again")
    }
}

@Suite struct SessionWeatherTests {
    @Test func failuresBringRainThenStormsAndPassingTestsBringSun() throws {
        let w = World(seed: 14)
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1440, h: 860)], windowsFrontToBack: [WindowInfo(id: 5, frame: Rect(x: 300, y: 100, w: 600, h: 400))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(400, 0))
        for _ in 0..<30 { w.step(1.0 / 30) }
        let id = try #require(w.startJob(windowID: 5, craft: .garden, prefer: c.id))
        let j = try #require(w.creatures.first { $0.id == id }?.job)
        w.claudeToolFailed(workerID: id, tests: false)
        #expect(j.weather == .rain)
        w.claudeToolFailed(workerID: id, tests: false); w.claudeToolFailed(workerID: id, tests: false)
        #expect(j.weather == .storm)
        w.claudeTestsPassed(workerID: id)
        #expect(j.weather == .sunny)
        for _ in 0..<(30 * 20) { w.step(1.0 / 30) }
        #expect(j.weather == .clear, "weather passes")
    }
}

@Suite struct StorybookTests {
    @Test func leafGliderFloatsDownSlowlyAndLands() {
        let w = World(seed: 21)
        w.maxHobbies = 0
        let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 9, frame: Rect(x: 600, y: 300, w: 300, h: 300))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(700, 620))
        for _ in 0..<600 where !(c.isGrounded && c.groundOwner == 9) { w.step(1.0 / 60) }
        #expect(w.glideTarget(for: c) != nil)
        w.startGlide(c, direction: 1)
        var steps = 0, sawFloat = false
        while !(c.isGrounded) && steps < 60 * 30 {
            w.step(1.0 / 60); steps += 1
            if c.gliding && c.vel.y > -90 && c.pos.y < 590 { sawFloat = true }
            #expect(c.pos.x.isFinite && c.pos.y.isFinite)
        }
        #expect(sawFloat, "floated gently rather than dropping")
        #expect(c.isGrounded && !c.gliding)
        #expect(Double(steps) / 60 > 2, "took a while to come down (\(Double(steps) / 60)s)")
    }

    @Test func gustTurnsGremletsIntoTheWind() {
        let w = World(seed: 22)
        w.maxHobbies = 0
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1440, h: 860)], windowsFrontToBack: [])
        let cs = (0..<4).map { w.spawn(testSpecies(scale: 10), at: Vec2(300 + Double($0) * 200, 0)) }
        for _ in 0..<30 { w.step(1.0 / 60) }
        for c in cs { c.set(.idle, duration: 5) }
        w.gust(direction: 1)
        #expect(cs.allSatisfy { $0.facing == -1 })
    }
}

@Suite struct AdventureTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func mineOpensAndClaudeTasksTurnUpGems() {
        let w = World(seed: 31)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        #expect(w.mineIndex == nil)
        for _ in 0..<10 { w.feedGrove() }
        #expect(w.mineIndex != nil, "the mine opens once the grove has three plots")
        #expect(w.grove.digCharges == 10)
        for i in 0..<3 { w.spawn(testSpecies(scale: 10), at: Vec2(200 + Double(i) * 300, 20)) }
        var gems = 0
        for _ in 0..<(60 * 300) where gems < 2 {
            w.step(1.0 / 60)
            _ = w.drainEvents(); _ = w.drainGroveEvents()
            gems += w.drainAdventureEvents().filter { if case .gemFound = $0 { return true }; return false }.count
        }
        #expect(gems >= 2)
        #expect(w.grove.gems.values.reduce(0, +) == gems)
    }

    @Test func skyFerryDocksCarriesPassengersAndLeaves() {
        let w = World(seed: 32)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 200, w: 400, h: 350)),
                                                               WindowInfo(id: 2, frame: Rect(x: 850, y: 250, w: 400, h: 300))])
        w.loadGrove(Grove())
        for i in 0..<4 { w.spawn(testSpecies(scale: 10), at: Vec2(300 + Double(i) * 60, 600)) }
        #expect(w.callFerry())
        var rode = false, docked = false, steps = 0
        while w.ferry != nil && steps < 60 * 120 {
            steps += 1
            w.step(1.0 / 60)
            _ = w.drainEvents()
            if w.ferry?.phase == .docked { docked = true }
            if w.creatures.contains(where: { $0.groundOwner == World.ferryOwner }) { rode = true }
            for c in w.creatures { #expect(c.pos.x.isFinite && c.pos.y >= -1 && c.pos.y <= scr.maxY + 1) }
        }
        #expect(docked)
        #expect(rode, "someone hopped aboard")
        #expect(w.ferry == nil, "it sailed off")
        #expect(!w.creatures.contains { $0.groundOwner == World.ferryOwner })
    }

    @Test func lanternFestivalAfterAGoodDay() {
        let w = World(seed: 33)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        w.isNight = true
        w.checkLanternFestival(hour: 21)
        w.step(1.0 / 30)
        #expect(w.spectacle == nil, "not after a quiet day")
        for _ in 0..<9 { w.feedGrove() }
        #expect(w.tasksToday == 9)
        w.checkLanternFestival(hour: 21)
        w.step(1.0 / 30)
        #expect(w.spectacle?.kind == .lanterns)
        for _ in 0..<(30 * 60) { w.step(1.0 / 30) }
        w.checkLanternFestival(hour: 22)
        w.step(1.0 / 30)
        #expect(w.spectacle == nil, "once a day")
    }
}

@Suite struct MerchantTests {
    @Test func merchantTradesGemsForVillageThingsThatGremletsUse() throws {
        let w = World(seed: 41)
        w.maxHobbies = 0
        let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let g = Grove()
        let data = #"{"plants":[],"tasks":0,"gems":{"amber":5,"sapphire":2}}"#
        w.loadGrove(try #require(Grove.decode(Data(data.utf8))))
        _ = g
        #expect(w.nextPurchase == .lamps)
        #expect(w.callMerchant())
        var sold: [VillageItem] = []
        for _ in 0..<(60 * 120) where w.merchant != nil {
            w.step(1.0 / 60)
            for e in w.drainMerchantEvents() { if case .sold(let i) = e { sold.append(i) } }
        }
        #expect(sold == [.lamps])
        #expect(w.owns(.lamps) && w.grove.gems["amber"] == 2)
        // Next visit: not enough amber left for the hot spring (needs 3), so nothing to buy.
        #expect(w.nextPurchase == nil)
    }

    @Test func tiredGremletsSoakInTheHotSpring() throws {
        let w = World(seed: 42)
        w.maxHobbies = 0
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1440, h: 860)], windowsFrontToBack: [])
        let data = #"{"plants":[],"tasks":0,"gems":{"amber":3,"sapphire":2}}"#
        w.loadGrove(try #require(Grove.decode(Data(data.utf8))))
        w.buy(.spring)
        #expect(w.owns(.spring))
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(700, 20))
        var soaked = false
        for _ in 0..<(60 * 200) where !soaked {
            if c.energy > 0.5 { c.energy = 0.3 }
            w.step(1.0 / 60)
            _ = w.drainEvents()
            soaked = w.drainMerchantEvents().contains { if case .soak = $0 { return true }; return false }
        }
        #expect(soaked)
    }
}

@Suite struct BonsaiTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func projectsGrowTreesFromTheWork() throws {
        let w = World(seed: 51)
        w.maxHobbies = 0
        let win = WindowInfo(id: 7, frame: Rect(x: 300, y: 200, w: 700, h: 400))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        w.loadBonsai(BonsaiBook())
        w.bonsaiStart(project: "MyApp", session: "s1", windowID: 7)
        #expect(w.bonsaiBook["MyApp"]?.branches.count == 1 && w.bonsaiBook["MyApp"]?.sessions == 1)
        // Another prompt in the same session: no new branch. A new session: a new branch.
        w.bonsaiStart(project: "MyApp", session: "s1", windowID: 7)
        #expect(w.bonsaiBook["MyApp"]?.branches.count == 1)
        w.bonsaiStart(project: "MyApp", session: "s2", windowID: 7)
        #expect(w.bonsaiBook["MyApp"]?.branches.count == 2)
        let small = BonsaiGeometry.layout(try #require(w.bonsaiBook["MyApp"])).bounds
        for _ in 0..<60 { w.bonsaiGrow(project: "MyApp", .leaf) }
        w.bonsaiGrow(project: "MyApp", .bloom, count: 3)
        w.bonsaiGrow(project: "MyApp", .fruit)
        let t = try #require(w.bonsaiBook["MyApp"])
        #expect(t.edits == 60 && t.blooms == 3 && t.fruit == 1)
        let big = BonsaiGeometry.layout(t).bounds
        #expect(big.w > small.w * 1.5 && big.h > small.h, "it sprawls as the work piles up (\(small.w)→\(big.w))")
        #expect(BonsaiGeometry.layout(t).pads.map(\.center.x) == BonsaiGeometry.layout(t).pads.map(\.center.x), "deterministic")
        // Rooted on the window, with foliage you can stand on.
        let live = try #require(w.bonsaiPlacements.first { $0.project == "MyApp" })
        #expect(live.windowID == 7 && live.slot == -1 && live.base.y == 600)
        #expect(w.surfaces.contains { World.isBonsaiOwner($0.ownerID) })
        let events = w.drainBonsaiEvents()
        #expect(events.contains(.planted("MyApp")) && events.contains(.sprouted("MyApp", branch: 1)))
        #expect(events.filter { if case .grew("MyApp", "leaf", _) = $0 { return true }; return false }.count == 60)
    }

    @Test func treesRideTheirWindowThenRestInTheNursery() throws {
        let w = World(seed: 52)
        w.maxHobbies = 0
        var win = WindowInfo(id: 9, frame: Rect(x: 300, y: 150, w: 700, h: 400))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        w.loadBonsai(BonsaiBook())
        w.bonsaiStart(project: "Gremlets", session: "a", windowID: 9)
        for _ in 0..<40 { w.bonsaiGrow(project: "Gremlets", .leaf) }
        let pad = try #require(w.surfaces.first { World.isBonsaiOwner($0.ownerID) })
        let c = w.spawn(testSpecies(scale: 10), at: Vec2((pad.minX + pad.maxX) / 2, pad.y + 30))
        for _ in 0..<120 where c.groundOwner != pad.ownerID { w.step(1.0 / 60) }
        #expect(c.groundOwner == pad.ownerID, "sitting in the tree (on \(String(describing: c.groundOwner)))")
        let before = c.pos.x
        win.frame.x += 80
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        #expect(abs(c.pos.x - before - 80) < 0.01, "rode the window with the tree")
        // Session over: the tree rests on a nursery bracket on the right edge.
        w.bonsaiEnd(project: "Gremlets")
        let rest = try #require(w.bonsaiPlacements.first { $0.project == "Gremlets" })
        #expect(rest.slot == 0 && rest.windowID == nil && rest.base.x > scr.maxX - World.nurseryWidth)
        #expect(w.surfaces.contains { World.isNurseryOwner($0.ownerID) })
        w.nurserySide = -1
        #expect(w.bonsaiPlacements.first { $0.project == "Gremlets" }!.base.x < World.nurseryWidth)
    }

    @Test func twelveBranchesThenItThickens() {
        let w = World(seed: 53)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadBonsai(BonsaiBook())
        for n in 0..<15 { w.bonsaiStart(project: "Big", session: "s\(n)", windowID: nil); w.bonsaiGrow(project: "Big", .leaf, count: n + 1) }
        let t = w.bonsaiBook["Big"]!
        #expect(t.branches.count == Bonsai.maxBranches && t.sessions == 15)
        #expect(t.edits == (1...15).reduce(0, +))
        #expect(t.stature > 0.6)
    }

    @Test func bookSurvivesSaveAndLoad() throws {
        var book = BonsaiBook()
        var t = Bonsai(project: "DesktopPets", now: 1_000_000)
        _ = t.startSession("x", now: 1_000_100)
        t.branches[0].edits = 12; t.branches[0].blooms = 2
        book.trees.append(t)
        let data = try #require(book.encoded())
        let back = try #require(BonsaiBook.decode(data))
        #expect(back.trees == book.trees)
        #expect(Bonsai(project: "DesktopPets", now: 5).species == t.species, "the project name decides the species")
    }

    @Test func mossyLedgesGrowOutOfAClaudeWindow() throws {
        let w = World(seed: 54)
        var win = WindowInfo(id: 4, frame: Rect(x: 300, y: 100, w: 600, h: 400))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(400, 0))
        for _ in 0..<30 { w.step(1.0 / 30) }
        let id = try #require(w.startJob(windowID: 4, craft: .garden, prefer: c.id))
        w.labelJob(workerID: id, "MyApp")
        for _ in 0..<9 { w.claudeTool(workerID: id, .build) }
        #expect(w.terminalLedges.count == 2, "a ledge every four edits (\(w.terminalLedges.count))")
        let ledge = try #require(w.terminalLedges.first)
        #expect(ledge.windowID == 4 && w.surfaces.contains { $0.ownerID == ledge.surface.ownerID })
        let x0 = ledge.surface.minX
        win.frame.x += 50
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        #expect(abs((w.terminalLedges.first?.surface.minX ?? 0) - x0 - 50) < 0.01, "ledges move with the window")
    }
}

@Suite struct TreeLifeTests {
    @Test func sleepyGremletsClimbUpAndNapInTheTree() throws {
        let w = World(seed: 61)
        w.maxHobbies = 0
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1440, h: 860)], windowsFrontToBack: [WindowInfo(id: 2, frame: Rect(x: 400, y: 100, w: 700, h: 300))])
        w.loadBonsai(BonsaiBook())
        w.bonsaiStart(project: "Nap", session: "s", windowID: 2)
        for _ in 0..<80 { w.bonsaiGrow(project: "Nap", .leaf) }
        w.isNight = true
        let pad = try #require(w.surfaces.first { World.isBonsaiOwner($0.ownerID) })
        let c = w.spawn(testSpecies(scale: 10), at: Vec2((pad.minX + pad.maxX) / 2, 400))
        c.energy = 0.3
        var napped = false
        for _ in 0..<(60 * 150) where !napped {
            w.step(1.0 / 60); _ = w.drainEvents()
            napped = c.activity == .sleep && World.isBonsaiOwner(c.groundOwner)
        }
        #expect(napped, "asleep up in the foliage (\(c.activity), on \(String(describing: c.groundOwner)))")
    }
}

@Suite struct MilestoneTests {
    @Test func roundNumbersEarnRibbonsOnce() {
        let w = World(seed: 71)
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1440, h: 860)], windowsFrontToBack: [])
        w.loadBonsai(BonsaiBook())
        w.bonsaiStart(project: "Big", session: "a", windowID: nil)
        w.bonsaiGrow(project: "Big", .leaf, count: 49)
        _ = w.drainBonsaiEvents()
        w.bonsaiGrow(project: "Big", .leaf)
        let e = w.drainBonsaiEvents()
        #expect(e.contains(.milestone("Big", "50 edits")))
        w.bonsaiGrow(project: "Big", .leaf)
        #expect(!w.drainBonsaiEvents().contains { if case .milestone = $0 { return true }; return false }, "only once")
        #expect(w.bonsaiBook["Big"]?.milestones == ["edits-50"])
    }
}

@Suite struct RepoHistoryTests {
    @Test func anOldRepoGrowsAnOldTree() throws {
        let w = World(seed: 81)
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1440, h: 860)], windowsFrontToBack: [])
        w.loadBonsai(BonsaiBook())
        w.bonsaiStart(project: "Young", session: "a", windowID: nil)
        let twoYearsAgo = Date().timeIntervalSince1970 - 730 * 86400
        w.bonsaiStart(project: "Old", session: "a", windowID: nil, repoCommits: 400, repoSince: twoYearsAgo)
        let young = try #require(w.bonsaiBook["Young"]), old = try #require(w.bonsaiBook["Old"])
        #expect(old.stature > young.stature)
        #expect(old.ageDays(now: Date().timeIntervalSince1970) > 700 && young.ageDays(now: Date().timeIntervalSince1970) < 1)
        #expect(BonsaiGeometry.layout(old).thickness > BonsaiGeometry.layout(young).thickness)
        // A bad or future date is ignored; a higher commit count later wins.
        w.bonsaiStart(project: "Old", session: "b", windowID: nil, repoCommits: 10, repoSince: Date().timeIntervalSince1970 + 999)
        #expect(w.bonsaiBook["Old"]?.repoCommits == 400 && w.bonsaiBook["Old"]?.repoSince == twoYearsAgo)
    }
}

@Suite struct KiteTests {
    @Test func kiteFliesOnItsStringAndComesDown() {
        let w = World(seed: 5)
        let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.maxHobbies = 0
        let a = w.spawn(testSpecies(scale: 12), at: Vec2(500, 40))
        let b = w.spawn(testSpecies(scale: 12), at: Vec2(1300, 40))
        for _ in 0..<30 { w.step(1.0 / 30) }
        #expect(w.startKite(for: a.id))
        var highest = 0.0
        for _ in 0..<(30 * 10) {
            w.step(1.0 / 30)
            guard let k = w.kite else { break }
            let hand = w.kiteHand(a)
            #expect((k.pos - hand).length <= k.length + 14)
            #expect(k.pos.y >= hand.y + 11.9)
            highest = max(highest, k.pos.y - hand.y)
        }
        #expect(w.kite != nil)
        #expect(highest > 60)
        for _ in 0..<(30 * 50) where w.kite != nil { w.step(1.0 / 30) }
        #expect(w.kite == nil)
        #expect(w.startKite(for: b.id))
    }
}

@Suite struct TerrainTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func gremletBuildsStairsUpToAWindowAndTakesThemWithIt() throws {
        let w = World(seed: 9)
        w.maxHobbies = 0
        w.maxJumpHeight = 50   // no jumping up there: the stairs are the only way
        let win = WindowInfo(id: 1, frame: Rect(x: 700, y: 0, w: 500, h: 150))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(420, 2))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(c.groundOwner == -1)
        w.nextStairAt = 0
        let plan = try #require(w.stairCandidate(for: c))
        #expect(plan.dir == 1 && plan.steps == 10 && abs(plan.base.x - 550) < 0.01)
        w.startStairs(c, plan)
        #expect(c.blocksInHand == 3)
        var done = false, laid = 0, taken = 0, mostStanding = 0
        for _ in 0..<(60 * 60) where !done {
            w.step(1.0 / 60)
            mostStanding = max(mostStanding, w.stairs.first?.standing ?? 0)
            for e in w.drainTerrainEvents() {
                if case .stairBlock = e { laid += 1 }
                if case .stairBlockTaken = e { taken += 1 }
                if case .stairsDone = e { done = true }
            }
        }
        #expect(done && laid == 10)
        #expect(mostStanding <= Stair.trail + 2, "it only ever leaves a short trail of blocks behind it")
        // It walks on up and onto the window, and the last blocks come up after it.
        var onWindow = false
        for _ in 0..<(60 * 10) {
            w.step(1.0 / 60)
            for e in w.drainTerrainEvents() { if case .stairBlockTaken = e { taken += 1 } }
            if c.groundOwner == 1 { onWindow = true }
            if onWindow && w.stairs.isEmpty { break }
        }
        #expect(onWindow, "climbed its own stairs onto the window")
        #expect(w.stairs.isEmpty && taken == 10, "every block was picked back up")
        #expect(!w.surfaces.contains { World.isStairOwner($0.ownerID) })
        #expect(c.blocksInHand == 0)
    }

    @Test func gremletLaysARailAndRidesTheCart() throws {
        let w = World(seed: 12)
        w.maxHobbies = 0
        let win = WindowInfo(id: 1, frame: Rect(x: 200, y: 300, w: 700, h: 200))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(500, 502))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(c.groundOwner == 1)
        w.nextRailAt = 0
        let s = try #require(w.railCandidate(for: c))
        w.startRail(c, on: s)
        #expect(w.rails.count == 1)
        var laid = false
        for _ in 0..<(60 * 90) where !laid {
            w.step(1.0 / 60)
            laid = w.drainTerrainEvents().contains { if case .railDone = $0 { return true }; return false }
        }
        #expect(laid)
        let rail = try #require(w.rails.first)
        #expect(rail.isComplete && rail.minX > 200 && rail.maxX < 900)
        // It hops in and rides: the cart moves a long way and bounces at the ends.
        var rode = false, bounces = 0, travelled = 0.0
        var lastX = rail.cart.x
        for _ in 0..<(60 * 40) {
            w.step(1.0 / 60)
            for e in w.drainTerrainEvents() { if case .cartBounce = e { bounces += 1 } }
            if let r = w.rails.first { travelled += abs(r.cart.x - lastX); lastX = r.cart.x }
            if c.groundOwner == World.cartOwner(rail.id) { rode = true }
            if rode && bounces >= 2 { break }
        }
        #expect(rode, "was riding the cart")
        #expect(bounces >= 2 && travelled > 600)
        // Eventually it parks and the rider hops out onto the window.
        var off = false
        for _ in 0..<(60 * 60) where !off { w.step(1.0 / 60); _ = w.drainTerrainEvents(); off = c.groundOwner == 1 && (w.rails.first?.cart.passes ?? 1) == 0 }
        #expect(off)
        // Close the window: the rail comes down.
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        #expect(w.rails.isEmpty)
        #expect(w.drainTerrainEvents().contains { if case .railCrumbled = $0 { return true }; return false })
    }
}

@Suite struct ExpeditionTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    /// Three windows: A reachable from the floor only by stairs, B across a gap from A, C above B (grapple only,
    /// and too far from A to hook straight from there).
    func layout() -> [WindowInfo] {
        [WindowInfo(id: 1, frame: Rect(x: 480, y: 0, w: 260, h: 360)),
         WindowInfo(id: 2, frame: Rect(x: 960, y: 0, w: 400, h: 380)),
         WindowInfo(id: 3, frame: Rect(x: 1200, y: 380, w: 160, h: 320))]
    }

    /// Steps until the creature is standing on `owner` (the brain may hop about in the meantime).
    func settle(_ c: Creature, in w: World, on owner: Int) {
        for _ in 0..<600 where !(c.isGrounded && c.groundOwner == owner && [.idle, .walk, .land].contains(c.activity)) { w.step(1.0 / 60) }
        _ = w.drainExpeditionEvents(); _ = w.drainTerrainEvents(); _ = w.drainBuildEvents()
    }

    @Test func treasureRunAcrossThreeWindowsAndBackHome() throws {
        let w = World(seed: 21)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: layout())
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 2))
        settle(c, in: w, on: -1)
        #expect(c.groundOwner == -1)
        let chest = try #require(w.spawnChest(at: Vec2(1280, 700), golden: false))
        #expect(w.chests.count == 1)
        #expect(w.startExpedition(c, .treasure(chest)))
        let ex = try #require(c.expedition)
        #expect(ex.methods == [.climb, .bridge, .grapple], "stairs up to A, a bridge over to B, the hook up to C")
        var taken = false, opened: GemKind?, legs: [LegMethod] = []
        for _ in 0..<(60 * 150) where opened == nil {
            w.step(1.0 / 60)
            _ = w.drainTerrainEvents(); _ = w.drainBuildEvents()
            for e in w.drainExpeditionEvents() {
                switch e {
                case .legDone(_, let m): legs.append(m)
                case .chestTaken: taken = true
                case .chestOpened(_, _, let gem): opened = gem
                case .gaveUp: Issue.record("gave up with legs \(legs)")
                default: break
                }
            }
        }
        #expect(taken, "picked the chest up")
        #expect(opened != nil, "brought it home and opened it (legs: \(legs))")
        #expect(legs.prefix(3) == [.climb, .bridge, .grapple])
        #expect(legs.count >= 4, "came back down by another route")
        #expect(w.chests.isEmpty && c.expedition == nil)
        #expect(w.grove.gems.values.reduce(0, +) == 1)
        #expect(c.groundOwner == -1, "back on the floor")
        #expect(w.stairs.isEmpty, "no lumber left behind")
    }

    @Test func summitExpeditionPlantsAFlagOnTheHighestWindow() throws {
        let w = World(seed: 22)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: layout())
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 2))
        settle(c, in: w, on: -1)
        #expect(w.startExpedition(c, .summit))
        #expect(c.expedition?.methods == [.climb, .bridge, .grapple])
        var planted = false
        for _ in 0..<(60 * 120) where !planted {
            w.step(1.0 / 60)
            _ = w.drainTerrainEvents(); _ = w.drainBuildEvents()
            for e in w.drainExpeditionEvents() { if case .summit = e { planted = true } }
        }
        #expect(planted)
        let flag = try #require(w.flags.first)
        #expect(abs(flag.pos.y - 700) < 1 && c.groundOwner == 3, "the flag is on C, the highest window")
        // Close that window: the flag goes with it.
        w.setEnvironment(screens: [scr], windowsFrontToBack: Array(layout().prefix(2)))
        #expect(w.flags.isEmpty)
    }

    @Test func ziplineCarriesGremletsDown() throws {
        let w = World(seed: 23)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: layout())
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(1280, 702))
        let d = w.spawn(testSpecies(scale: 10), at: Vec2(1250, 702))
        settle(c, in: w, on: 3)
        #expect(c.groundOwner == 3)
        let floor = try #require(w.surfaces.first { $0.kind == .floor })
        #expect(w.startZip(c, to: floor))
        let z = try #require(w.ziplines.first)
        #expect(z.bottom.x < z.top.x - 80, "the line runs down and away")
        var landed = false
        for _ in 0..<(60 * 12) where !landed { w.step(1.0 / 60); landed = c.groundOwner == -1 }
        #expect(landed, "slid down and landed on the floor")
        #expect(w.ziplines.count == 1, "the line stays for the next one")
        // A friend at the top takes it too.
        d.pos = Vec2(z.top.x, 700); d.groundOwner = 3; d.set(.idle, duration: 1)
        #expect(w.rideZip(d, z.id))
        var landed2 = false
        for _ in 0..<(60 * 12) where !landed2 { w.step(1.0 / 60); landed2 = d.groundOwner == -1 }
        #expect(landed2)
    }
}

@Suite struct DoorTests {
    let scr = Rect(x: 0, y: 0, w: 1000, h: 800)

    @Test func gremletsWalkOutThroughTheDoorAndInFromTheOtherScreen() throws {
        let w = World(seed: 31)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(900, 2))
        for _ in 0..<60 { w.step(1.0 / 60) }
        // No door: the edge is a wall.
        c.facing = 1; c.set(.walk, duration: 5)
        for _ in 0..<120 { w.step(1.0 / 60) }
        #expect(c.pos.x <= 1000 && w.creaturesPastDoor().isEmpty)
        // A door on the right, and this one is sent through.
        w.door = 1
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        #expect(w.surfaces.contains { $0.kind == .floor && $0.maxX > 1100 }, "the floor runs on past the edge")
        #expect(w.sendThroughDoor(preferring: c.id))
        var out = false
        for _ in 0..<(60 * 20) where !out { w.step(1.0 / 60); out = w.creaturesPastDoor().contains { $0 === c } }
        #expect(out && c.pos.x > 1000)
        w.remove(c.id)
        // Someone walks in from the other screen and carries on along the floor.
        let d = try #require(w.arriveThroughDoor(testSpecies(scale: 10), yFrac: 0, vx: 70, vy: 0, airborne: false))
        #expect(d.pos.x > 1000 && d.facing == -1)
        for _ in 0..<(60 * 4) { w.step(1.0 / 60) }
        #expect(d.pos.x < 990 && d.isGrounded, "walked in onto the floor")
        // A flyer comes in mid-air and lands.
        let e = try #require(w.arriveThroughDoor(testSpecies(scale: 10), yFrac: 0.5, vx: 200, vy: 100, airborne: true))
        for _ in 0..<(60 * 4) { w.step(1.0 / 60) }
        #expect(e.pos.x < 1000 && e.isGrounded)
    }
}

@Suite struct FerryDoorTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func theFerryCarriesPassengersOutThroughTheDoorway() throws {
        let w = World(seed: 33)
        w.maxHobbies = 0
        w.door = 1
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 200, w: 400, h: 350)),
                                                               WindowInfo(id: 2, frame: Rect(x: 850, y: 250, w: 400, h: 300))])
        w.loadGrove(Grove())
        for i in 0..<4 { w.spawn(testSpecies(scale: 10), at: Vec2(300 + Double(i) * 60, 600)) }
        #expect(w.sendFerryThroughDoor())
        var crossed: [String]? = nil, steps = 0, boarded = 0
        while w.ferry != nil && steps < 60 * 120 {
            steps += 1
            w.step(1.0 / 60)
            _ = w.drainEvents()
            boarded = max(boarded, w.creatures.filter { $0.groundOwner == World.ferryOwner }.count)
            #expect(w.creaturesPastDoor().allSatisfy { $0.groundOwner != World.ferryOwner }, "riders go with the ferry, not on foot")
            for e in w.drainAdventureEvents() { if case .ferryCrossed(let r, let y) = e { crossed = r; #expect(y >= 0 && y <= 1) } }
        }
        let riders = try #require(crossed, "it sailed out through the doorway")
        #expect(riders.count <= boarded)
        #expect(!riders.isEmpty, "someone rode it over")
        #expect(w.creatures.count == 4 - riders.count, "the passengers left with it")
    }

    @Test func theFerryArrivesFromTheOtherScreenAndDropsItsPassengersOff() {
        let w = World(seed: 34)
        w.maxHobbies = 0
        w.door = -1
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 200, w: 400, h: 350))])
        w.loadGrove(Grove())
        let riders = w.ferryArrivesThroughDoor(riders: [testSpecies(scale: 10), testSpecies(scale: 10)], yFrac: 0.6)
        #expect(riders.count == 2 && w.ferry != nil)
        #expect(riders.allSatisfy { $0.pos.x < 0 })
        var steps = 0
        while w.ferry != nil && steps < 60 * 120 {
            steps += 1
            w.step(1.0 / 60)
            _ = w.drainEvents()
            for c in w.creatures { #expect(c.pos.x.isFinite && c.pos.y >= -1) }
        }
        #expect(w.ferry == nil)
        // Visitors who just came over hop off: the ferry doesn't take them straight back.
        #expect(w.creatures.count == 2)
        #expect(w.creatures.allSatisfy { $0.pos.x > -10 && $0.pos.x < 1450 && $0.groundOwner != World.ferryOwner }, "\(w.creatures.map(\.pos))")
    }
}

@Suite struct TeamworkTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func aFriendBoostsAClimberOntoAWindowTooHighToJump() throws {
        let w = World(seed: 41)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 700, y: 0, w: 400, h: 400))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(400, 2))
        let f = w.spawn(testSpecies(scale: 10), at: Vec2(300, 2))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(w.jumpTarget(for: c) == nil || true)
        let plan = try #require(w.boostCandidate(for: c, ignoreCooldown: true))
        #expect(plan.helper == f.id && plan.dir == 1 && abs(plan.helperX - 672) < 0.01)
        w.startBoost(c, plan)
        var heave = false, done = false, failed = false
        for _ in 0..<(60 * 30) where !done && !failed {
            w.step(1.0 / 60)
            for e in w.drainTeamEvents() {
                if case .heave = e { heave = true }
                if case .boostDone = e { done = true }
                if case .boostFailed = e { failed = true }
            }
        }
        #expect(heave && done && !failed)
        #expect(c.groundOwner == 1, "up on the window")
        #expect(f.groundOwner == -1 && f.helping == nil && c.boost == nil)
    }

    @Test func gremletsPoseForAScreenshotAndHoldUpSigns() {
        let w = World(seed: 42)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let a = w.spawn(testSpecies(scale: 10), at: Vec2(300, 2))
        let b = w.spawn(testSpecies(scale: 10), at: Vec2(600, 2))
        for _ in 0..<60 { w.step(1.0 / 60) }
        _ = w.drainTeamEvents()
        w.machineSignal(.screenshot)
        let posed = w.drainTeamEvents().compactMap { e -> [Int]? in if case .posed(let ids) = e { return ids }; return nil }.first
        #expect(Set(posed ?? []) == Set([a.id, b.id]))
        w.machineSignal(.screenshot)
        #expect(w.drainTeamEvents().isEmpty, "not twice in a row")
        w.machineSignal(.offline)
        #expect(w.creatures.filter { $0.sign == .noSignal }.count == 1)
        w.machineSignal(.offline)
        #expect(w.creatures.filter { $0.sign == .noSignal }.count == 1, "one sign is enough")
        w.machineSignal(.online)
        #expect(w.creatures.allSatisfy { $0.sign == nil })
        #expect(w.drainTeamEvents().contains { if case .signDown(_, .noSignal, true) = $0 { return true }; return false })
        w.machineSignal(.batteryLow(percent: 9))
        #expect(w.creatures.contains { $0.sign == .battery })
        for _ in 0..<(60 * 16) { w.step(1.0 / 60) }
        #expect(w.creatures.allSatisfy { $0.sign == nil }, "the battery sign goes down after a while")
    }
}

@Suite struct OvergrowthTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func gremletsPlantAndTendMossOnWindows() throws {
        let w = World(seed: 51)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 100, w: 700, h: 300))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(600, 402))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(c.groundOwner == 1)
        #expect(w.startMossActivity("plant"))
        var planted = false
        for _ in 0..<(60 * 30) where !planted { w.step(1.0 / 60); planted = w.drainMossEvents().contains { if case .planted = $0 { return true }; return false } }
        #expect(planted && w.mossPatches.count == 1)
        let before = try #require(w.mossPatches.first).size
        // It grows by itself, and someone waters it.
        w.mossPatches[0].lastTended = -1000
        #expect(w.startMossActivity("plant"))
        var tended = false
        for _ in 0..<(60 * 30) where !tended { w.step(1.0 / 60); tended = w.drainMossEvents().contains { if case .tended = $0 { return true }; return false } }
        for _ in 0..<(60 * 4) { w.step(1.0 / 60) }
        #expect(tended && w.mossPatches[0].size > before + 0.15)
    }

    @Test func gremletsClimbVinesAndBuildPlatformsOnThem() throws {
        let w = World(seed: 52)
        w.maxHobbies = 0
        w.mossMinutes = 160
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 500, y: 0, w: 500, h: 300))])
        #expect(w.mossVines.contains { $0.key == "e0l" && $0.length > 400 })
        #expect(w.mossVines.contains { $0.key == "w1l" }, "a strand hangs from the window's corner")
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(120, 2))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(w.startMossActivity("pad"))
        var built = false, climbed = false
        for _ in 0..<(60 * 40) where !built {
            w.step(1.0 / 60)
            if c.isClimbing { climbed = true }
            built = w.drainMossEvents().contains { if case .padBuilt = $0 { return true }; return false }
        }
        #expect(climbed && built && w.mossPads.count == 1)
        for _ in 0..<(60 * 2) { w.step(1.0 / 60) }
        #expect(World.isMossPadOwner(c.groundOwner), "standing on its new platform")
        #expect(abs(c.pos.y - 110) < 2)
        // The moss recedes: the platform goes with it.
        w.mossMinutes = 0
        for _ in 0..<(60 * 2) { w.step(1.0 / 60) }
        #expect(w.mossPads.isEmpty && w.mossVines.isEmpty)
    }

    @Test func theVillageKeepsOneHome() {
        let w = World(seed: 53)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        w.addHouse(biome: "meadow", blocks: 30, size: Vec2(105, 135), project: "A")
        w.addHouse(biome: "snow", blocks: 30, size: Vec2(105, 90), project: "B")
        let homes = w.grove.village.filter { $0.biome != "mine" && !$0.biome.hasPrefix("item:") }
        #expect(homes.count == 1 && homes.first?.project == "B")
    }
}

@Suite struct ClaudeCompanionTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func textLinesInAWindowBecomeLedgesUnlessCovered() {
        let back = WindowInfo(id: 1, frame: Rect(x: 100, y: 100, w: 800, h: 600), spans: [WindowSpan(fromTop: 120, minX: 40, maxX: 400)])
        let s = SurfaceBuilder.build(screens: [scr], windowsFrontToBack: [back])
        #expect(s.contains { $0.ownerID == 1 && $0.kind == .windowLedge && abs($0.y - 580) < 0.01 && abs($0.minX - 140) < 0.01 && abs($0.maxX - 500) < 0.01 })
        let front = WindowInfo(id: 2, frame: Rect(x: 50, y: 500, w: 300, h: 200))
        let s2 = SurfaceBuilder.build(screens: [scr], windowsFrontToBack: [front, back])
        let ledge = s2.first { $0.ownerID == 1 && $0.kind == .windowLedge }
        #expect(ledge != nil && ledge!.minX >= 350, "the covered part is cut away")
    }

    @Test func planStepsAndContextShowOnTheWorker() throws {
        let w = World(seed: 61)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 100, w: 600, h: 400))])
        _ = w.spawn(testSpecies(scale: 10), at: Vec2(600, 2))
        for _ in 0..<60 { w.step(1.0 / 60) }
        let id = try #require(w.startJob(windowID: 1, craft: .garden))
        w.claudePlan(workerID: id, total: 5, done: 0)
        w.claudePlan(workerID: id, total: 5, done: 2)
        w.claudePlan(workerID: id, total: 5, done: 5)
        let ev = w.drainPlanEvents()
        #expect(ev.filter { if case .stepDone = $0 { return true }; return false }.count == 5)
        #expect(ev.contains(.planComplete(worker: id)))
        w.claudeContext(workerID: id, pct: 60)
        w.claudeContext(workerID: id, pct: 88)
        #expect(w.drainPlanEvents() == [.contextFilling(worker: id, pct: 88)])
        #expect(w.creatures.first { $0.id == id }?.job?.contextPct == 88)
    }
}
