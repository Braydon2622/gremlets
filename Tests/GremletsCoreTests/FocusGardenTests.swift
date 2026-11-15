import Testing
@testable import GremletsCore

@Suite struct FocusGardenTests {
    @Test func plantsGrowWithFocusedTimeNotJustTime() {
        var r = FocusRun(minutes: 20, kind: 0)
        #expect(r.stage == 0)
        _ = r.advance(300, distracted: false)
        #expect(r.stage == 1)
        _ = r.advance(600, distracted: true)
        #expect(r.stage == 1, "time on a distraction doesn't grow the plant")
        #expect(r.isDistracted)
        _ = r.advance(900, distracted: false)
        #expect(r.stage == 4 && !r.isDistracted)
        #expect(abs(r.focusShare - 1200.0 / 1800.0) < 0.001)
    }

    @Test func distractionStartAndEndAreReported() {
        var r = FocusRun(minutes: 25, kind: 0)
        let a = r.advance(5, distracted: false), b = r.advance(1, distracted: true)
        let c = r.advance(1, distracted: true), d = r.advance(1, distracted: false)
        #expect(!a)
        #expect(b, "started")
        #expect(!c)
        #expect(d, "came back")
    }

    @Test func showingUpAlwaysLeavesAtLeastASprout() {
        let r = FocusRun(minutes: 25, kind: 2)
        let p = r.harvest(day: "2026-11-12")
        #expect(p.stage == 1 && p.kind == 2 && p.minutes == 0)
    }

    @Test func gardenKeepsTheLastEightAndCountsThemAll() {
        var g = FocusGarden()
        for i in 0..<11 { g.add(FocusPlant(kind: i % 6, stage: 4, day: "2026-11-12", minutes: 25)) }
        #expect(g.plants.count == FocusGarden.capacity)
        #expect(g.total == 11)
        #expect(g.plants.first?.kind == 3)
        #expect(g.plantsOn("2026-11-12") == 8)
        #expect(g.nextKind(seed: g.plants.last!.kind) != g.plants.last!.kind, "not the same plant twice in a row")
    }

    @Test func gardenGetsThirstyInTheAfternoonUntilWatered() {
        var g = FocusGarden()
        #expect(!g.thirsty(today: "2026-11-12", hour: 15), "an empty planter doesn't need water")
        g.add(FocusPlant(kind: 0, stage: 4, day: "2026-11-12", minutes: 25))
        #expect(!g.thirsty(today: "2026-11-12", hour: 9))
        #expect(g.thirsty(today: "2026-11-12", hour: 15))
        g.lastWatered = "2026-11-12"
        #expect(!g.thirsty(today: "2026-11-12", hour: 15))
        #expect(g.thirsty(today: "2026-11-13", hour: 13))
    }

    @Test func distractionsAreAppsOrSites() {
        #expect(Distraction.isDistracting(bundleID: "com.hnc.Discord", title: nil))
        #expect(Distraction.isDistracting(bundleID: "com.google.Chrome", title: "Funny cats - YouTube"))
        #expect(Distraction.isDistracting(bundleID: "com.apple.Safari", title: "Home / X"))
        #expect(!Distraction.isDistracting(bundleID: "com.google.Chrome", title: "Pull request #42 · GitHub"))
        #expect(!Distraction.isDistracting(bundleID: "com.apple.Terminal", title: nil))
    }
}

@Suite struct DailyCareTests {
    @Test func snacksBuildAStreakAndHitMilestones() {
        var c = DailyCare()
        #expect(c.feed(today: "d1", yesterday: "d0") == nil)
        #expect(c.feed(today: "d1", yesterday: "d0") == nil, "a second snack the same day doesn't count twice")
        #expect(c.snacksToday == 2)
        #expect(c.feed(today: "d2", yesterday: "d1") == nil)
        #expect(c.feed(today: "d3", yesterday: "d2") == 3)
        #expect(c.streak(today: "d3", yesterday: "d2") == 3)
        #expect(c.streak(today: "d4", yesterday: "d3") == 3, "still alive the next morning")
        #expect(c.streak(today: "d5", yesterday: "d4") == 0, "a missed day")
        _ = c.feed(today: "d5", yesterday: "d4")
        #expect(c.streak(today: "d5", yesterday: "d4") == 1)
        #expect(c.best == 3)
    }

    @Test func hungryOnlyInTheAfternoonAndOnlyIfUnfed() {
        var c = DailyCare()
        #expect(!c.hungry(today: "d1", hour: 10))
        #expect(c.hungry(today: "d1", hour: 16))
        c.feed(today: "d1", yesterday: "d0")
        #expect(!c.hungry(today: "d1", hour: 16))
    }
}

@Suite struct RealLifeSignTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func newSignsGoUpAndDown() {
        let w = World(seed: 7)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        _ = w.spawn(testSpecies(scale: 10), at: Vec2(300, 2))
        _ = w.spawn(testSpecies(scale: 10), at: Vec2(700, 2))
        for _ in 0..<60 { w.step(1.0 / 60) }
        _ = w.drainTeamEvents()
        w.machineSignal(.hungry)
        #expect(w.creatures.filter { $0.sign == .hungry }.count == 1)
        w.machineSignal(.hungry)
        #expect(w.creatures.filter { $0.sign == .hungry }.count == 1, "one bowl is enough")
        w.machineSignal(.fed)
        #expect(!w.creatures.contains { $0.sign == .hungry })
        w.machineSignal(.meetingSoon)
        #expect(w.creatures.contains { $0.sign == .meeting })
        w.machineSignal(.distracted)
        w.machineSignal(.focusBack)
        #expect(!w.creatures.contains { $0.sign == .waiting })
        w.machineSignal(.music)
        #expect(w.drainTeamEvents().contains { if case .danced = $0 { return true }; return false })
        w.machineSignal(.music)
        #expect(!w.drainTeamEvents().contains { if case .danced = $0 { return true }; return false }, "not every few seconds")
    }
}
