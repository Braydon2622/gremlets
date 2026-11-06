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
        w.startJob(windowID: 9, craft: .paint)
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
        w.startJob(windowID: 9, craft: .build)
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
        w.startJob(windowID: 9, craft: .knit)
        run(w, 30)
        let early = c.job!.progress
        run(w, 240)
        let later = c.job!.progress
        #expect(early > 0 && later > early && later <= 0.9)
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
        w.startJob(windowID: 9, craft: .build)
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

    @Test func hobbyPausesWhileYoureAwayThenFinishesOnItsOwn() {
        let w = World(seed: 48)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [500])[0]
        #expect(w.startHobby(c, craft: .garden, length: 60, onWindow: false))
        run(w, 20)
        #expect(c.job?.phase == .working)
        w.userActive = false
        let paused = c.job!.workSeconds
        run(w, 30)
        #expect(c.job!.workSeconds == paused)
        #expect(c.isDozingAtWork)
        w.userActive = true
        run(w, 60)
        #expect(c.job == nil || c.job?.phase == .finished)
        run(w, 30)
        #expect(c.job == nil)                      // admired it, then back to normal life
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
        w.startJob(windowID: nil, craft: .build, prefer: cs[0].id)
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
        for c in cs { #expect(w.startHobby(c, craft: .knit, length: 300, onWindow: false)) }
        w.maxHobbies = 3
        run(w, 20)
        let anchors = cs.compactMap { c in c.job.flatMap { w.jobAnchor($0, workerID: c.id) } }
        #expect(anchors.count == 3)
        for a in anchors { #expect(a.x > 40 && a.x < 960) }
        let xs = cs.map(\.pos.x).sorted()
        #expect(xs[1] - xs[0] > 60 && xs[2] - xs[1] > 60)
        #expect(cs[0].pos.x >= 90)
    }

    @Test func helpingWithTheCreationSpeedsItUp() {
        let w = World(seed: 61)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let a = grounded(w, [300])[0]
        w.startHobby(a, craft: .garden, length: 200, onWindow: false)
        run(w, 10)
        let before = a.job!.progress
        w.drainEvents()
        w.tendCreation(workerID: a.id)
        #expect(a.job!.progress > before + 0.03)
        #expect(a.activity == .pet)
        #expect(w.drainEvents().contains(.petted(a.id)))
        run(w, 3)
        #expect(a.activity == .work)                  // back to it
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
}
