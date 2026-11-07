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

    /// A full boss fight with the whole grove out and a busy click-happy user: it always ends, nothing escapes the
    /// screen, the Gremlets fight back, and a win grows the grove.
    @Test func bossFightPlaysOutAndCanBeWon() {
        let w = World(seed: 42)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 100, w: 500, h: 380))])
        w.loadGrove(Grove())
        for _ in 0..<30 { w.feedGrove() }
        for i in 0..<6 { var s = testSpecies(scale: 12); s.flies = i == 0; w.spawn(s, at: Vec2(200 + Double(i) * 180, 300)) }
        let sparksBefore = w.grove.plants[0].sparks
        #expect(w.startEvent(.boss))
        var seen: [String: Int] = [:]
        var frames = 0
        while w.spectacle != nil && frames < 60 * 120 {
            frames += 1
            // You click the boss's head every half second.
            if frames % 30 == 0, let h = w.spectacle?.head { w.hitBoss(at: h) }
            w.step(1.0 / 60)
            _ = w.drainEvents()
            for e in w.drainSpectacleEvents() { seen["\(e)".split(separator: "(").first.map(String.init) ?? "", default: 0] += 1 }
            for c in w.creatures {
                #expect(c.pos.x.isFinite && c.pos.y.isFinite)
                #expect(c.pos.x >= -1 && c.pos.x <= scr.maxX + 1 && c.pos.y >= -1 && c.pos.y <= scr.maxY + 1)
            }
            for s in w.spectacle?.segments ?? [] { #expect(s.x.isFinite && s.y.isFinite) }
        }
        print("boss events:", seen.sorted { $0.key < $1.key })
        #expect(w.spectacle == nil, "the fight ended")
        #expect(seen["roar", default: 0] > 0 && seen["boltStrike", default: 0] > 0)
        #expect(seen["throwBerry", default: 0] + seen["chomp", default: 0] > 0, "the grove joined the fight")
        #expect(w.grove.plants[0].sparks > sparksBefore, "victory (and stardust) grew the grove")
    }

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
        #expect(w.startEvent(.boss))
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
        #expect(w.grove.village.count == 5)
        #expect(w.groveLedges.filter { $0.plot < 0 }.count == 5, "roofs to stand on")
        let data = try #require(w.grove.encoded())
        let back = try #require(Grove.decode(data))
        #expect(back.village == w.grove.village)
        // A save from before the village existed.
        let old = #"{"plants":[{"kind":"sunberry","x":0.16,"sparks":3,"berries":2,"lastWishDay":-1,"golden":false}],"tasks":3,"tasksSinceBoss":3}"#
        let g = try #require(Grove.decode(Data(old.utf8)))
        #expect(g.tasks == 3 && g.village.isEmpty && g.plants.count == 1)
    }
}
