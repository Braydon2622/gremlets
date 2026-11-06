import Testing
@testable import GremletsCore

@Suite struct WorkTests {
    /// A window whose top (y = 650) is far too high to jump to from the floor.
    let tall = WindowInfo(id: 9, frame: Rect(x: 300, y: 100, w: 500, h: 550))

    @Test func climbsALadderToAHighWindowAndWorks() {
        let w = World(seed: 41)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        let id = w.startJob(windowID: 9, craft: .garden)
        #expect(id == c.id)
        var climbed = false
        for _ in 0..<(60 * 30) {
            w.step(1.0 / 60)
            if c.activity == .climb { climbed = true }
        }
        #expect(climbed)
        #expect(c.groundOwner == 9)
        #expect(c.job?.phase == .working)
        #expect(c.activity == .work)
        let lad = w.jobLadder(c.job!)!
        #expect(lad.x < 300 || lad.x > 800)        // leans against the window's side, not over its contents
        let anchor = w.jobAnchor(c.job!)!
        #expect(anchor.y == 650 && anchor.x >= 300 && anchor.x <= 800)
    }

    @Test func creationGrowsButOnlyFinishesWhenClaudeIsDone() {
        let w = World(seed: 42)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .paint)
        settle(w, 30)
        let early = c.job!.progress
        settle(w, 240)
        let later = c.job!.progress
        #expect(early > 0 && later > early && later < 0.95)
        #expect(c.job!.beat > 3)
        w.finishJob(c.id)
        #expect(c.job!.phase == .finished && c.job!.progress == 1)
        settle(w, 10)
        #expect(c.job != nil)                    // stays by its creation until the platform ends the job
        w.endJob(c.id)
        #expect(c.job == nil)
        settle(w, 5)
        #expect(c.activity != .work)
    }

    @Test func flierFliesInsteadOfClimbing() {
        let w = World(seed: 43)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = w.spawn(flyer(), at: Vec2(100, 0))
        settle(w, 1)
        w.startJob(windowID: 9, craft: .build)
        var climbed = false
        for _ in 0..<(60 * 30) { w.step(1.0 / 60); if c.activity == .climb { climbed = true } }
        #expect(!climbed)
        #expect(c.groundOwner == 9 && c.job?.phase == .working)
    }

    @Test func coveredWindowMeansWorkingOnTheFloorBelowIt() {
        let w = World(seed: 44)
        let cover = WindowInfo(id: 1, frame: Rect(x: 250, y: 600, w: 600, h: 100))   // hides the top edge
        w.setEnvironment(screens: [screen], windowsFrontToBack: [cover, tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        settle(w, 30)
        #expect(c.job?.phase == .working)
        #expect(c.pos.y == 0)
        #expect(c.pos.x >= 300 && c.pos.x <= 800)     // right below the window, not off at the end of the floor
    }

    @Test func draggedAwayGoesBackToWork() {
        let w = World(seed: 45)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        let c = grounded(w, [100])[0]
        w.startJob(windowID: 9, craft: .garden)
        settle(w, 30)
        #expect(c.groundOwner == 9)
        w.beginDrag(c, at: c.pos, time: 0)
        w.drag(c, to: Vec2(950, 300), time: 0.2)
        w.endDrag(c, time: 1)
        settle(w, 40)
        #expect(c.groundOwner == 9 && c.job?.phase == .working)
    }

    @Test func workersSkipSocialLifeAndFocusNaps() {
        let w = World(seed: 46)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [400, 450])
        w.startJob(windowID: nil, craft: .build, prefer: cs[0].id)
        settle(w, 2)
        #expect(!w.nearbyFriends(of: cs[1]).contains { $0 === cs[0] })
        w.focusMode = true
        #expect(cs[0].activity != .yawn)
    }

    @Test func noGremletsMeansNoJob() {
        let w = World(seed: 47)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [tall])
        #expect(w.startJob(windowID: 9, craft: .garden) == nil)
    }
}
