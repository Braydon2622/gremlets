import Testing
@testable import GremletsCore

@Suite struct WorkTests {
    /// A window whose top (y = 650) is far too high to jump to from the floor. Room for a shelf on both sides.
    let tall = WindowInfo(id: 9, frame: Rect(x: 300, y: 100, w: 500, h: 550))

    func run(_ w: World, _ seconds: Double, each: (() -> Void)? = nil) {
        for _ in 0..<Int(seconds * 60) { w.step(1.0 / 60); each?() }
    }

    @Test func floatsUpToAShelfOnTheWindowAndWorksThere() {
        let w = World(seed: 41)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        #expect(w.startJob(windowID: 9, craft: .garden) == c.id)
        c.job!.rideUp = .balloon
        var floated = false
        run(w, 30) { if c.activity == .float { floated = true } }
        #expect(floated)
        #expect(c.groundOwner == World.shelfOwner(c.id))
        #expect(c.job?.phase == .working && c.activity == .work)
        let shelf = w.jobShelf(c.job!, workerID: c.id)!
        #expect(shelf.maxX <= 306)                         // left side: closer to where it started
        let a = w.jobAnchor(c.job!, workerID: c.id)!
        #expect(a.x > c.pos.x && a.x < 300)                // creation between the Gremlet and the window
    }

    @Test func staysOnItsShelfWhenAnotherWindowCoversTheTop() {
        let w = World(seed: 42)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        run(w, 30)
        let cover = WindowInfo(id: 1, frame: Rect(x: 0, y: 500, w: 1000, h: 250))
        w.setEnvironment(screens: [screen], windowsFrontToBack: [cover, tall])
        var leftShelf = false
        run(w, 180) { if c.groundOwner != World.shelfOwner(c.id) { leftShelf = true } }
        #expect(!leftShelf)
        #expect(c.job?.phase == .working)
    }

    @Test func shelfAndWorkerRideAlongWhenTheWindowMoves() {
        let w = World(seed: 43)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        c.job!.shelfStyle = .plank
        run(w, 30)
        let before = c.pos
        var moved = tall; moved.frame = Rect(x: 340, y: 60, w: 500, h: 550)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [moved])
        run(w, 1)
        #expect(abs(c.pos.x - (before.x + 40)) < 1 && abs(c.pos.y - (before.y - 40)) < 1)
        #expect(c.groundOwner == World.shelfOwner(c.id))
    }

    @Test func claudeJobGrowsFinishesAndFloatsBackDown() {
        let w = World(seed: 44)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        run(w, 30)
        let early = c.job!.progress
        run(w, 240)
        let later = c.job!.progress
        #expect(early > 0 && later > early && later <= 0.95)
        #expect(c.job!.beat > 3)
        w.finishJob(c.id)
        #expect(c.job!.phase == .finished && c.job!.progress == 1)
        run(w, 10)
        #expect(c.job != nil)                      // admires it until the platform ends the job
        w.endJob(c.id)
        #expect(c.job?.phase == .leaving)
        run(w, 20)
        #expect(c.job == nil && c.pos.y == 0)      // floated down safely, no dizzy fall
    }

    @Test func flierFliesToTheShelf() {
        let w = World(seed: 45)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = w.spawn(flyer(), at: Vec2(100, 0))
        run(w, 1)
        w.startJob(windowID: 9, craft: .garden)
        var floated = false
        run(w, 30) { if c.activity == .float { floated = true } }
        #expect(!floated)
        #expect(c.groundOwner == World.shelfOwner(c.id) && c.job?.phase == .working)
    }

    @Test func noShelfWhereAWindowInFrontWouldBeCovered() {
        let w = World(seed: 53)
        // A window in front sits right where a left-side shelf would go, so the shelf goes on the right.
        let front = WindowInfo(id: 2, frame: Rect(x: 120, y: 450, w: 170, h: 300))
        w.setEnvironment(screens: [screen], windowsFrontToBack: [front, tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        #expect(c.job?.shelfSide == 1)
    }

    @Test func fullWidthWindowMeansWorkingOnTheFloorBelowIt() {
        let w = World(seed: 46)
        let wide = WindowInfo(id: 9, frame: Rect(x: 0, y: 100, w: 1000, h: 600))
        w.setEnvironment(screens: [screen], windowsFrontToBack: [wide])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        run(w, 30)
        #expect(c.job?.phase == .working && c.pos.y == 0)
        #expect(w.jobShelf(c.job!, workerID: c.id) == nil)
    }

    @Test func draggedOffTheShelfGoesBack() {
        let w = World(seed: 47)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        run(w, 30)
        w.beginDrag(c, at: c.pos, time: 0)
        w.drag(c, to: Vec2(950, 300), time: 0.2)
        w.endDrag(c, time: 1)
        run(w, 40)
        #expect(c.groundOwner == World.shelfOwner(c.id) && c.job?.phase == .working)
    }

    @Test func gardenPausesWhileYoureAwayThenBloomsAndEndsOnItsOwn() {
        let w = World(seed: 48)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [500])[0]
        #expect(w.startHobby(c, onWindow: false))
        run(w, 20)
        #expect(c.job?.phase == .working)
        #expect(c.job!.garden.planted.count == 3)       // planted all three spots
        w.userActive = false
        let paused = c.job!.garden.progress
        run(w, 30)
        #expect(c.job!.garden.progress - paused < 0.05)  // barely grows while you're away
        #expect(c.isDozingAtWork)
        w.userActive = true
        run(w, 900)
        #expect(c.job == nil)                            // all bloomed, admired, back to normal life
    }

    @Test func gremletsTakeUpHobbiesOnTheirOwnButNotTooMany() {
        let w = World(seed: 49)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let cs = grounded(w, [100, 200, 900, 950])
        var maxBusy = 0, everBusy = Set<Int>()
        run(w, 900) {
            let busy = cs.filter { $0.job?.isHobby == true }
            maxBusy = max(maxBusy, busy.count)
            for b in busy { everBusy.insert(b.id) }
        }
        #expect(everBusy.count >= 2)
        #expect(maxBusy <= w.maxHobbies)
    }

    @Test func noHobbiesWhileYoureAway() {
        let w = World(seed: 50)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [100, 300, 600])
        w.userActive = false
        var any = false
        run(w, 600) { if cs.contains(where: { $0.job != nil }) { any = true } }
        #expect(!any)
    }

    @Test func workersSkipSocialLifeAndFocusNaps() {
        let w = World(seed: 51)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [400, 450])
        w.startJob(windowID: nil, craft: .garden, prefer: cs[0].id)
        run(w, 2)
        #expect(!w.nearbyFriends(of: cs[1]).contains { $0 === cs[0] })
        w.focusMode = true
        #expect(cs[0].activity != .yawn)
    }

    @Test func noGremletsMeansNoJob() {
        let w = World(seed: 52)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        #expect(w.startJob(windowID: 9, craft: .garden) == nil)
    }

    @Test func floorProjectsKeepAwayFromEdgesAndEachOther() {
        let w = World(seed: 60)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [10, 480, 520])
        cs[0].pos.x = 5          // just peeked around the screen edge
        for c in cs { #expect(w.startHobby(c, onWindow: false)) }
        w.maxHobbies = 3
        run(w, 20)
        let anchors = cs.compactMap { c in c.job.flatMap { w.jobAnchor($0, workerID: c.id) } }
        #expect(anchors.count == 3)
        for a in anchors { #expect(a.x > 40 && a.x < 960) }
        let xs = cs.map(\.pos.x).sorted()
        #expect(xs[1] - xs[0] > 60 && xs[2] - xs[1] > 60)
        #expect(cs[0].pos.x >= 90)
    }

    @Test func clickingTheBoxShoosBugsThenWaters() {
        let w = World(seed: 61)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let a = grounded(w, [300])[0]
        w.startHobby(a, onWindow: false)
        run(w, 15)
        let g = a.job!.garden
        g.plants[1]?.bug = true
        g.plants[2]?.water = 0.05
        w.drainEvents()
        #expect(w.helpGarden(workerID: a.id) == .shoo(1))
        #expect(g.plants[1]?.bug == false)
        #expect(a.activity == .pet && w.drainEvents().contains(.petted(a.id)))
        let before = g.plants[2]!.growth
        #expect(w.helpGarden(workerID: a.id) == .water(2))
        #expect(g.plants[2]!.water == 1 && g.plants[2]!.growth > before)
    }

    @Test func gardenerWatersDryPlantsAndShoosBugsItself() {
        let w = World(seed: 64)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let a = grounded(w, [300])[0]
        w.startHobby(a, onWindow: false)
        run(w, 15)
        let g = a.job!.garden
        g.plants[0]?.water = 0.02
        g.plants[1]?.bug = true
        run(w, 25)
        #expect((g.plants[0]?.water ?? 0) > 0.5)
        #expect(g.plants[1]?.bug == false)
    }

    @Test func onlyOneGremletPerShelf() {
        let w = World(seed: 65)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let cs = grounded(w, [100, 600])
        w.startJob(windowID: 9, craft: .garden, prefer: cs[0].id)
        run(w, 30)
        let shelf = w.jobShelf(cs[0].job!, workerID: cs[0].id)!
        // Drop the other Gremlet right onto the shelf: it falls through instead of landing.
        w.beginDrag(cs[1], at: cs[1].pos, time: 0)
        w.drag(cs[1], to: Vec2(shelf.minX + 20, shelf.y + 40), time: 0.1)
        w.endDrag(cs[1], time: 1)
        run(w, 3)
        #expect(cs[1].groundOwner != World.shelfOwner(cs[0].id))
        #expect(cs[1].pos.y < shelf.y)
    }

    @Test func claudeFinishingMakesEverythingBloom() {
        let w = World(seed: 66)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        run(w, 40)
        #expect(!c.job!.garden.allBloomed)
        w.finishJob(c.id)
        #expect(c.job!.garden.allBloomed && c.job!.garden.bloomed.count == 3)
    }

    @Test func focusMakesThingsGrowFaster() {
        func grown(calm: Bool) -> Double {
            let w = World(seed: 67)
            w.setEnvironment(screens: [screen], windowsFrontToBack: [])
            let c = grounded(w, [300])[0]
            w.startHobby(c, onWindow: false)
            w.focusMode = calm
            run(w, 50)
            return c.job?.garden.progress ?? 1
        }
        #expect(grown(calm: true) > grown(calm: false) * 1.2)
    }

    @Test func seedsFollowTheirRarity() {
        let w = World(seed: 68)
        var tiers = [0, 0, 0, 0, 0]
        for _ in 0..<20000 { tiers[w.pickSeed(boost: false, emptyBox: true).kind.rarity] += 1 }
        #expect(tiers[0] > tiers[1] && tiers[1] > tiers[2] && tiers[2] > tiers[3] && tiers[3] > tiers[4] && tiers[4] > 50)
    }

    @Test func giantsOnlyInAnEmptyBox() {
        let w = World(seed: 69)
        for _ in 0..<20000 { #expect(!w.pickSeed(boost: true, emptyBox: false).kind.isGiant) }
    }

    @Test func seasonalAndNightPlantsOnlyAtTheRightTime() {
        let w = World(seed: 70)
        w.month = 7; w.isNight = false
        var seen = Set<PlantKind>()
        for _ in 0..<30000 { seen.insert(w.pickSeed(boost: true, emptyBox: true).kind) }
        #expect(!seen.contains(.cherryBlossom) && !seen.contains(.frostbell) && !seen.contains(.moonflower))
        w.month = 4; w.isNight = true
        seen = []
        for _ in 0..<30000 { seen.insert(w.pickSeed(boost: true, emptyBox: true).kind) }
        #expect(seen.contains(.cherryBlossom) && seen.contains(.moonflower) && !seen.contains(.frostbell))
    }

    @Test func goldenPlantsAreRare() {
        let w = World(seed: 71)
        let golden = (0..<20000).filter { _ in w.pickSeed(boost: false).golden }.count
        #expect(golden > 300 && golden < 800)            // about 1 in 40
    }

    @Test func aWishMakesTheNextSeedSpecial() {
        let w = World(seed: 72)
        w.makeWish()
        #expect(w.pickSeed(boost: false).kind.rarity >= 3)
        #expect(w.wishes == 0)
    }

    @Test func aGiantFillsTheWholeBoxAndGrowsAsOne() {
        let w = World(seed: 73)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [400])[0]
        w.startHobby(c, onWindow: false)
        run(w, 6)
        let g = c.job!.garden
        g.plants = [nil, Plant(kind: .giantPumpkin), nil]
        #expect(g.planted.count == 1 && g.giant?.kind == .giantPumpkin)
        run(w, 60)
        #expect(g.plants[0] == nil && g.plants[2] == nil)   // nothing planted around it
        #expect(g.progress > 0.05)
        w.finishJob(c.id)
        #expect(g.allBloomed && g.bloomed.count == 1 && g.plants[0] == nil)
    }

    @Test func rainWatersEverything() {
        let w = World(seed: 74)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [400])[0]
        w.startHobby(c, onWindow: false)
        run(w, 15)
        let j = c.job!
        for i in 0..<3 { j.garden.plants[i]?.water = 0.05 }
        w.rainOn(j)
        #expect(j.garden.planted.allSatisfy { $0.water == 1 })
        #expect(j.garden.lastAction == .rain)
    }

    @Test func fivePokesDigUpAMysterySeed() {
        let w = World(seed: 75)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [400])[0]
        w.startHobby(c, onWindow: false)
        run(w, 8)
        for _ in 0..<5 {
            c.set(.work, duration: 9999)
            w.poke(c)
            run(w, 0.2)
        }
        if case .mystery = c.job!.garden.lastAction! {} else { Issue.record("no mystery seed: \(String(describing: c.job!.garden.lastAction))") }
        #expect(c.job!.garden.planted.contains { $0.kind.rarity >= 2 } || w.wishes > 0)
    }


    @Test func gremletsWaterThePlantedGarden() {
        let w = World(seed: 62)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [200, 700])
        w.gardenSpots = [450]
        w.maxHobbies = 0
        var watered = false
        run(w, 600) {
            for e in w.drainEvents() { if case .special(_, "rain") = e { watered = true } }
        }
        #expect(watered)
        #expect(cs.allSatisfy { $0.tendX == nil || $0.activity == .walk || $0.activity == .work || $0.activity == .idle })
    }

    @Test func twoGremletsNeverShareAShelfSpot() {
        let w = World(seed: 63)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let cs = grounded(w, [100, 150, 200])
        w.startJob(windowID: 9, craft: .garden, prefer: cs[0].id)
        w.startJob(windowID: 9, craft: .garden, prefer: cs[1].id)
        #expect(cs[0].job?.shelfSide != nil && cs[1].job?.shelfSide != nil)
        #expect(cs[0].job?.shelfSide != cs[1].job?.shelfSide)
        w.startJob(windowID: 9, craft: .garden, prefer: cs[2].id)
        #expect(cs[2].job?.shelfSide == nil)          // both sides taken: works on the floor below
    }

    @Test func mushroomBounceLaunchesItOntoItsShelf() {
        let w = World(seed: 80)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        c.job!.rideUp = .bounce
        var bounced = false
        run(w, 30) { if c.job?.bounceAt != nil { bounced = true } }
        #expect(bounced)
        #expect(c.groundOwner == World.shelfOwner(c.id) && c.job?.phase == .working)
        #expect(c.activity != .dizzy)
    }

    @Test func staysOnABobbingCloudShelf() {
        let w = World(seed: 81)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        c.job!.shelfStyle = .cloud
        run(w, 30)
        var ys = Set<Int>(), fell = false
        run(w, 60) {
            ys.insert(Int(c.pos.y))
            if c.groundOwner != World.shelfOwner(c.id) { fell = true }
        }
        #expect(!fell)
        #expect(ys.count > 4)                 // it really bobs
    }

    @Test func flytrapSnapsUpItsNeighboursAphids() {
        let w = World(seed: 82)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [400])[0]
        w.startHobby(c, onWindow: false)
        run(w, 10)
        let j = c.job!
        var trap = Plant(kind: .flytrap); trap.growth = 0.8
        j.garden.plants[1] = trap
        j.garden.plants[2]?.bug = true
        #expect(w.doGardenChore(j))
        #expect(j.garden.lastAction == .snap(1, 2) && j.garden.plants[2]?.bug == false)
    }

    @Test func everyStyleAndRideTurnsUp() {
        let w = World(seed: 83)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        var styles = Set<ShelfStyle>(), rides = Set<Ride>()
        for _ in 0..<200 {
            let c = w.spawn(testSpecies(), at: Vec2(100, 0))
            c.set(.idle); c.groundOwner = -1
            w.startJob(windowID: 9, craft: .garden, prefer: c.id)
            if let j = c.job { styles.insert(j.shelfStyle); rides.insert(j.rideUp) }
            w.remove(c.id)
        }
        // The snail is for floor gardens; the hot-air basket and flying carpet are retired.
        #expect(styles == Set(ShelfStyle.allCases.filter { ![.snail, .basket, .carpet].contains($0) }))
        #expect(rides == Set(Ride.up))
        #expect(!rides.contains(.balloon) && !rides.contains(.umbrella), "only rides from nature")
    }

    @Test func noRoomBesideAnyWindowMeansAShelfOnTheWall() {
        let w = World(seed: 84)
        let wide = WindowInfo(id: 9, frame: Rect(x: 0, y: 100, w: 1000, h: 600))
        w.setEnvironment(screens: [screen], windowsFrontToBack: [wide])
        let c = grounded(w, [300])[0]
        #expect(w.startHobby(c, onWindow: true))
        #expect(c.job?.wall != nil && c.job?.shelfSide == 1)      // left wall, sticking out to the right
        c.job!.rideUp = .balloon
        run(w, 40)
        #expect(c.groundOwner == World.shelfOwner(c.id) && c.job?.phase == .working)
        let shelf = w.jobShelf(c.job!, workerID: c.id)!
        #expect(shelf.minX == 0 && shelf.y > 200 && shelf.y < 650)
    }

    @Test func ridesADriftingBalloonBasketWithoutFallingOff() {
        let w = World(seed: 90)
        let small = WindowInfo(id: 9, frame: Rect(x: 380, y: 100, w: 240, h: 450))
        w.setEnvironment(screens: [screen], windowsFrontToBack: [small])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        c.job!.shelfStyle = .basket
        c.job!.rideUp = .balloon
        run(w, 30)
        #expect(c.groundOwner == World.shelfOwner(c.id))
        var xs: [Double] = [], fell = false
        run(w, 90) {
            xs.append(c.pos.x)
            if c.groundOwner != World.shelfOwner(c.id) { fell = true }
        }
        #expect(!fell)
        #expect((xs.max()! - xs.min()!) > 20)           // carried along as the basket drifts
        let s = w.jobShelf(c.job!, workerID: c.id)!
        #expect(s.maxX <= 1000 && s.minX >= 0)
    }

    @Test func aGiantSnailCarriesTheGardenAlongTheFloor() {
        let w = World(seed: 91)
        let wide = Rect(x: 0, y: 0, w: 1600, h: 900)
        w.setEnvironment(screens: [wide], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(), at: Vec2(800, 0))
        run(w, 1)
        var tries = 0
        while c.job?.snail == nil && tries < 200 {
            w.endJob(c.id); c.job = nil; c.hobbyRestUntil = 0; c.set(.idle, duration: 1)
            _ = w.startHobby(c, onWindow: false); tries += 1
        }
        #expect(c.job?.snail != nil)
        c.job!.rideUp = .balloon
        run(w, 40)
        #expect(c.groundOwner == World.shelfOwner(c.id) && c.job?.phase == .working)
        let x0 = c.pos.x
        run(w, 60)
        #expect(abs(c.pos.x - x0) > 5 && c.groundOwner == World.shelfOwner(c.id))
    }

    @Test func browserWindowsHaveALedgeInsideThatCanBeCovered() {
        let browser = WindowInfo(id: 5, frame: Rect(x: 100, y: 100, w: 600, h: 500), ledges: [88])
        var s = SurfaceBuilder.build(screens: [screen], windowsFrontToBack: [browser])
        #expect(s.contains { $0.ownerID == 5 && $0.kind == .windowLedge && $0.y == 512 })
        let front = WindowInfo(id: 6, frame: Rect(x: 50, y: 300, w: 700, h: 300))
        s = SurfaceBuilder.build(screens: [screen], windowsFrontToBack: [front, browser])
        #expect(!s.contains { $0.kind == .windowLedge })
    }

    @Test func gremletsVisitDesktopIconsAndIconsAreNotHeads() {
        let w = World(seed: 92)
        w.iconSurfaces = [Surface(ownerID: World.iconOwnerBase - 3, kind: .icon, y: 700, minX: 880, maxX: 926)]
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [500])[0]
        w.maxHobbies = 0
        let icon = w.iconToVisit(for: c)!
        w.startIconVisit(c, icon)
        var sat = 0.0
        run(w, 40) { if w.iconUnder(c) == 3 { sat += 1.0 / 60; #expect(World.carrierID(c.groundOwner) == nil) } }
        #expect(sat > 6)                          // sat on the icon for a good while
    }
}
