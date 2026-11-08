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
        var slid = false, landed = false
        for _ in 0..<(60 * 20) where !landed {
            w.step(1.0 / 60)
            if c.climb?.sliding == true { slid = true }
            if slid && c.isGrounded && c.pos.y < 100 { landed = true }
        }
        #expect(slid)
        #expect(landed, "landed down below (\(c.pos))")
    }
}

@Suite struct MossBridgeTests {
    @Test func mossWeavesABridgeBetweenWindowsSideBySide() throws {
        let w = World(seed: 141)
        w.maxHobbies = 0
        let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
        let wins = [WindowInfo(id: 1, frame: Rect(x: 100, y: 0, w: 500, h: 400)), WindowInfo(id: 2, frame: Rect(x: 700, y: 0, w: 500, h: 410))]
        w.setEnvironment(screens: [scr], windowsFrontToBack: wins)
        w.mossMinutes = 30
        w.rebuildVines()
        #expect(w.mossBridges.isEmpty, "not yet")
        w.mossMinutes = 90
        w.rebuildVines()
        let b = try #require(w.mossBridges.first)
        #expect(b.minX < 600 && b.maxX > 700)
        // A Gremlet can walk across it from one window to the other.
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(560, 420))
        for _ in 0..<60 { w.step(1.0 / 60) }
        c.facing = 1; c.targetX = 760
        w.startMossTask(c, .water(window: 2, offset: 60), walkTo: 760)
        for _ in 0..<(60 * 15) where c.groundOwner != 2 { w.step(1.0 / 60) }
        #expect(c.groundOwner == 2, "crossed the bridge (at \(c.pos))")
    }
}

@Suite struct SproutTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    func world(seed: UInt64) -> World {
        let w = World(seed: seed)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 0, w: 900, h: 160))])
        w.mossMinutes = 80
        return w
    }

    @Test func thingsComeUpInTheMossAndGrow() {
        let w = world(seed: 161)
        for _ in 0..<(20 * 60 * 6) { w.step(1.0 / 20) }   // six minutes, nobody about
        #expect(!w.sprouts.isEmpty, "something sprouted")
        #expect(w.sprouts.allSatisfy { $0.windowID == 1 || $0.windowID == -1 }, "on the window top or the floor")
        // Floor ones only in the mossy corners, never across the middle of the screen.
        for sp in w.sprouts where sp.windowID < 0 { #expect(sp.offset < 400 || sp.offset > 1040, "\(sp.offset)") }
        #expect(w.sprouts.count <= World.sproutLimit)
        #expect(w.sprouts.contains { $0.growth > 0.3 }, "and grew (\(w.sprouts.map(\.growth)))")
    }

    @Test func gremletsPickEatAndBlowWhatsReady() {
        for kind in MossSprout.Kind.wild {
            let w = world(seed: 162)
            w.nextSproutAt = .infinity
            let a = w.spawn(testSpecies(scale: 10), at: Vec2(500, 160))
            _ = w.spawn(testSpecies(scale: 10), at: Vec2(800, 160))
            for _ in 0..<60 { w.step(1.0 / 60) }
            let patches = w.mossPatches.count
            #expect(w.sproutNow(kind))
            var gone = false
            for _ in 0..<(60 * 90) {
                w.step(1.0 / 60)
                if w.sprouts.isEmpty { gone = true; break }
            }
            #expect(gone, "the \(kind) got seen to")
            if kind == .dandelion {
                for _ in 0..<(60 * 8) { w.step(1.0 / 60) }
                #expect(w.mossPatches.count > patches, "its seeds started new moss")
            }
            _ = a
        }
    }

    @Test func youngSproutsGetWatered() {
        let w = world(seed: 163)
        w.nextSproutAt = .infinity
        _ = w.spawn(testSpecies(scale: 10), at: Vec2(500, 160))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(w.sproutNow(.daisy, ripe: false))
        let id = w.sprouts[0].id
        var watered = false
        for _ in 0..<(60 * 120) {
            w.step(1.0 / 60)
            if w.sproutWatered[id] != nil { watered = true; break }
        }
        #expect(watered)
    }
}

@Suite struct HouseAndNightTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func pickedDaisiesFillTheWindowBoxOnTheHouse() {
        let w = World(seed: 171)
        w.maxHobbies = 0
        w.wallClock = 1_800_000_000
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 0, w: 700, h: 200))])
        w.notchHome = NotchHome(minX: 1100, maxX: 1300, menuBottom: scr.maxY)
        w.mossMinutes = 80
        w.nextSproutAt = .infinity
        _ = w.spawn(testSpecies(scale: 10), at: Vec2(500, 200))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(w.houseDaisies == 0)
        #expect(w.sproutNow(.daisy))
        for _ in 0..<(60 * 120) where w.houseDaisies == 0 { w.step(1.0 / 60) }
        #expect(w.houseDaisies == 1, "one daisy in the box")
        // A new day: the box starts over.
        w.wallClock += 86_400
        w.step(1.0 / 60)
        #expect(w.houseDaisies == 0)
    }

    @Test func firefliesComeOutAtNightAndGetChased() {
        let w = World(seed: 172)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 0, w: 900, h: 200))])
        w.mossMinutes = 120
        w.isNight = true
        let cs = [400.0, 800].map { w.spawn(testSpecies(scale: 10), at: Vec2($0, 200)) }
        var chased = false
        for _ in 0..<(60 * 180) {
            w.step(1.0 / 60)
            if cs.contains(where: { $0.mossTask?.firefly != nil }) { chased = true }
            // Low over the window top, never out over the screen.
            for f in w.fireflies where !f.leaving {
                let p = w.position(of: f)!
                #expect(p.y >= 200 && p.y <= 200 + 112 && p.x >= 200 && p.x <= 1100)
            }
        }
        #expect(!w.fireflies.isEmpty, "out at night")
        #expect(chased, "someone chased one")
        // Morning: they go.
        w.isNight = false
        for _ in 0..<(60 * 120) { w.step(1.0 / 60) }
        #expect(w.fireflies.isEmpty)
    }
}

@Suite struct GardenInMossTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func claudesGardenGrowsOnTheWindowTopNotOnAShelf() throws {
        let w = World(seed: 181)
        w.maxHobbies = 0
        w.gardenInMoss = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 100, w: 800, h: 400))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(700, 0))
        for _ in 0..<60 { w.step(1.0 / 60) }
        let id = try #require(w.startJob(windowID: 1, craft: .garden, prefer: c.id))
        #expect(id == c.id)
        for _ in 0..<(60 * 40) where c.job?.phase != .working { w.step(1.0 / 60) }
        #expect(c.job?.phase == .working, "set up")
        #expect(c.job?.shelfSide == nil && c.groundOwner == 1, "working in the moss on the window top")
        let a = try #require(w.jobAnchor(c.job!, workerID: c.id))
        #expect(abs(a.y - 500) < 1)
        // The window moves: the garden goes with it.
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 150, w: 800, h: 400))])
        for _ in 0..<10 { w.step(1.0 / 60) }
        let b = try #require(w.jobAnchor(c.job!, workerID: c.id))
        #expect(abs(b.y - 550) < 1 && abs(b.x - (a.x - 100)) < 1)
    }

    @Test func outOfFullScreenTheyRestOnTopCornerBranches() {
        let w = World(seed: 182)
        w.maxHobbies = 0
        w.topCornerPerches = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let cs = (0..<4).map { w.spawn(testSpecies(scale: 10), at: Vec2(200 + Double($0) * 300, 0)) }
        #expect(w.topCornerSpots.count == 4, "two branches, the nest hut and the leaf swing")
        var up = false
        for _ in 0..<(60 * 600) {
            w.step(1.0 / 60)
            if cs.contains(where: { $0.isGrounded && World.isCornerSpot($0.groundOwner ?? 0) }) { up = true; break }
        }
        #expect(up, "someone went up to a corner branch")
    }
}

@Suite struct ClaudeMoodTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func thinkingBetweenToolsAndALanternWhileItWaitsForYou() throws {
        let w = World(seed: 191)
        w.maxHobbies = 0
        w.gardenInMoss = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 100, w: 800, h: 400))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(700, 0))
        for _ in 0..<60 { w.step(1.0 / 60) }
        _ = try #require(w.startJob(windowID: 1, craft: .garden, prefer: c.id))
        for _ in 0..<(60 * 40) where c.job?.phase != .working { w.step(1.0 / 60) }
        w.claudeTool(workerID: c.id, .build)
        w.step(1.0 / 60)
        #expect(w.claudeMood(c) == nil, "busy with a tool")
        for _ in 0..<(60 * 6) { w.step(1.0 / 60) }
        #expect(w.claudeMood(c) == .thinking, "quiet for a bit: thinking")
        w.jobNeedsAttention(c.id)
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(w.claudeMood(c) == .waiting)
        // You answer: a new prompt in the same session.
        _ = w.startJob(windowID: 1, craft: .garden, prefer: c.id)
        #expect(w.claudeMood(c) == nil)
        #expect(w.placeName(of: c) == "the top of Claude's window")
    }
}

@Suite struct ClaudeActingTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    func working() throws -> (World, Creature) {
        let w = World(seed: 201)
        w.maxHobbies = 0
        w.gardenInMoss = true
        w.topCornerPerches = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 100, w: 800, h: 400))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(700, 0))
        for _ in 0..<60 { w.step(1.0 / 60) }
        _ = try #require(w.startJob(windowID: 1, craft: .garden, prefer: c.id))
        for _ in 0..<(60 * 40) where c.job?.phase != .working { w.step(1.0 / 60) }
        return (w, c)
    }

    @Test func itHoldsUpWhatClaudeIsUsing() throws {
        let (w, c) = try working()
        for (tool, prop) in [("Read", "book"), ("Grep", "magnifier"), ("WebSearch", "telescope"), ("Edit", "trowel"), ("Test", "clover"), ("TodoWrite", "list")] {
            w.claudeTool(workerID: c.id, ClaudeTool.from(tool == "Test" ? "Bash" : tool), name: tool)
            w.step(1.0 / 60)
            #expect(w.heldProp(c) == prop, "\(tool)")
        }
        for _ in 0..<(60 * 5) { w.step(1.0 / 60) }
        #expect(w.heldProp(c) == nil, "put away after a few seconds")
    }

    @Test func compactingEmptiesThePack() throws {
        let (w, c) = try working()
        w.claudeContext(workerID: c.id, pct: 90)
        #expect(c.job?.contextPct == 90)
        _ = w.drainPlanEvents()
        w.claudeCompact(workerID: c.id)
        #expect((c.job?.contextPct ?? 99) <= 8)
        #expect(w.drainPlanEvents().contains(.unpacked(worker: c.id)))
    }

    @Test func aGentleKnockAfterThreeMinutesWaiting() throws {
        let (w, c) = try working()
        w.jobNeedsAttention(c.id)
        _ = w.drainPlanEvents()
        var knocks = 0
        for _ in 0..<(20 * 60 * 8) {
            w.step(1.0 / 20)
            knocks += w.drainPlanEvents().filter { $0 == .knocked(worker: c.id) }.count
        }
        #expect(knocks == 2, "at three minutes and seven, not more (\(knocks))")
    }

    @Test func atTheEndItWavesAndCarriesALanternHome() throws {
        let (w, c) = try working()
        w.endJob(c.id)
        w.claudeGoodbye(workerID: c.id)
        #expect(c.carrying == "lantern")
        var home = false
        for _ in 0..<(60 * 80) {
            w.step(1.0 / 60)
            if c.isGrounded, let o = c.groundOwner, World.isCornerSpot(o) || World.isHouseOwner(o) { home = true; break }
        }
        #expect(home, "made it to the nest hut (\(c.pos))")
        for _ in 0..<5 { w.step(1.0 / 60) }
        #expect(c.carrying == nil, "lantern put away at home")
    }
}

@Suite struct GardenDayTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    func working(_ seed: UInt64) throws -> (World, Creature) {
        let w = World(seed: seed)
        w.maxHobbies = 0
        w.gardenInMoss = true
        w.wallClock = 1_800_000_000
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 100, w: 800, h: 400))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(700, 0))
        for _ in 0..<60 { w.step(1.0 / 60) }
        _ = try #require(w.startJob(windowID: 1, craft: .garden, prefer: c.id))
        for _ in 0..<(60 * 40) where c.job?.phase != .working { w.step(1.0 / 60) }
        return (w, c)
    }

    @Test func winFlagsLineUpForTheDayAndComeDownTomorrow() throws {
        let (w, c) = try working(211)
        for _ in 0..<4 { w.plantWinFlag(workerID: c.id) }
        #expect(w.winFlags.count == 4)
        let xs = w.winFlags.map(\.offset).sorted()
        for (a, b) in zip(xs, xs.dropFirst()) { #expect(b - a >= 12, "side by side") }
        w.wallClock += 86_400
        for _ in 0..<(60 * 31) { w.step(1.0 / 60) }
        #expect(w.winFlags.isEmpty)
    }

    @Test func theDuckComesOutAfterTwoFailuresAndCheersWhenItWorks() throws {
        let (w, c) = try working(212)
        w.claudeToolFailed(workerID: c.id, tests: false)
        #expect(!w.duckOut(c))
        w.claudeToolFailed(workerID: c.id, tests: false)
        #expect(w.duckOut(c))
        w.claudeTool(workerID: c.id, .run, name: "Bash")
        #expect(!w.duckOut(c))
        #expect(w.drainGardenEvents().contains(.duckCheer(by: c.id)))
    }

    @Test func testsSwayTheMossMoodAndItCalmsDown() throws {
        let (w, c) = try working(213)
        for _ in 0..<3 { w.claudeTestsPassed(workerID: c.id) }
        #expect(w.testMood > 0.5)
        for _ in 0..<(20 * 60 * 60 * 3) { w.step(1.0 / 20) }
        #expect(w.testMood < 0.25, "easing back to calm")
    }

    @Test func picnicBlanketFriendSeedAndHush() {
        let w = World(seed: 214)
        w.maxHobbies = 0
        w.wallClock = 1_800_000_000
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 100, w: 800, h: 300))])
        let cs = [200.0, 260, 900].map { w.spawn(testSpecies(scale: 10), at: Vec2($0, 0)) }
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(w.startPicnic())
        for _ in 0..<(60 * 20) { w.step(1.0 / 60) }
        let seated = cs.filter { if case .picnic? = $0.mossTask?.kind { return true }; return false }
        #expect(seated.count >= 2, "friends came to the picnic")
        for _ in 0..<(60 * 160) { w.step(1.0 / 60) }
        #expect(w.picnic == nil, "and it's packed up after a while")
        #expect(w.bringBlanket(towardX: 1300))
        for _ in 0..<(60 * 30) where w.blanket == nil { w.step(1.0 / 60) }
        #expect(w.blanket != nil && abs(w.blanket!.x - 1300) < 60, "a blanket left by you")
        #expect(w.friendSeed(tint: 0x8FD3FF))
        #expect(w.sprouts.contains { $0.kind == .friendBloom && $0.tint == 0x8FD3FF })
        // Tiptoeing while you type.
        let c = cs[2]
        w.hushed = true
        let x0 = c.pos.x
        c.facing = 1; c.targetX = nil
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(abs(c.pos.x - x0) < c.species.walkSpeed * 0.7, "slow and quiet")
    }
}

@Suite struct QuestTests {
    @Test func aGremletWalksToTheBoardAndReadsItOut() {
        let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
        let w = World(seed: 231)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 500, y: 100, w: 600, h: 300))])
        let cs = [300.0, 900].map { w.spawn(testSpecies(scale: 10), at: Vec2($0, 0)) }
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(!w.startQuestNag(), "no board, no nag")
        w.questBoard = QuestBoard(next: "Record the clip", done: 1, total: 9, staleDays: 3)
        #expect(w.questBoardSpot != nil)
        #expect(w.startQuestNag())
        var read = false
        for _ in 0..<(60 * 40) {
            w.step(1.0 / 60)
            if w.drainGardenEvents().contains(where: { if case .questNag = $0 { return true }; return false }) { read = true; break }
        }
        #expect(read, "someone read it out")
        let messenger = cs.min { abs($0.pos.x - 64) < abs($1.pos.x - 64) }!
        #expect(abs(messenger.pos.x - (64 + 36)) < 20, "standing by the board")
        w.compact = true
        #expect(w.questBoardSpot == nil, "hidden in full screen")
    }
}
