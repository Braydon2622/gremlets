import Testing
@testable import GremletsCore

@Suite struct CompanionTests {
    @Test func focusModeMakesEveryoneDozeAndStayAsleep() {
        let w = World(seed: 31)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [200, 400, 600])
        w.focusMode = true
        for _ in 0..<(60 * 120) {               // two simulated minutes
            w.step(1.0 / 60)
            for c in cs {
                #expect(![.fly, .dance, .run, .special, .chase].contains(c.activity), "\(c.activity) during focus")
            }
        }
        #expect(cs.allSatisfy { $0.activity == .sleep })
    }

    @Test func passEndsFocusWithADanceParty() {
        let w = World(seed: 32)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [200, 400])
        w.focusMode = true
        for _ in 0..<(60 * 10) { w.step(1.0 / 60) }
        w.receive(.pass)
        #expect(!w.focusMode)
        #expect(cs.allSatisfy { $0.activity == .dance })
    }

    @Test func failKnocksEveryoneDizzy() {
        let w = World(seed: 33)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [200, 400])
        w.drainEvents()
        w.receive(.fail)
        #expect(cs.allSatisfy { $0.activity == .dizzy })
        #expect(w.drainEvents().filter { if case .dizzy = $0 { return true }; return false }.count == 2)
    }

    @Test func doneMakesTheNearestGremletWave() {
        let w = World(seed: 34)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [200, 800])
        w.cursor = Vec2(780, 50)
        w.receive(.done)
        #expect(cs[1].activity == .wave)
        #expect(cs[0].activity != .wave)
    }

    @Test func sayPicksTheNearestGremletAndAlerts() {
        let w = World(seed: 36)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [200, 800])
        w.cursor = Vec2(220, 50)
        w.drainEvents()
        let id = w.say()
        #expect(id == cs[0].id)
        #expect(cs[0].activity == .wave)
        #expect(w.drainEvents().contains(.alert(cs[0].id)))
    }

    @Test func sayWithNoGremletsReturnsNil() {
        let w = World(seed: 37)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        #expect(w.say() == nil)
    }

    @Test func speechTextIsCleanedAndCapped() {
        #expect(SpeechText.clean("SalesCheatCodeLive%3A+Claude+is+done+%E2%9C%93") == "SalesCheatCodeLive: Claude is done ✓")
        #expect(SpeechText.clean("line1%0Aline2%09tab") == "line1 line2 tab")
        #expect(SpeechText.clean("  %20 ") == nil)
        #expect(SpeechText.clean(nil) == nil)
        #expect(SpeechText.clean("100%") == "100%")              // bad percent-encoding is kept as typed
        let long = SpeechText.clean(String(repeating: "a", count: 500))!
        #expect(long.count == SpeechText.maxLength && long.hasSuffix("…"))
    }

    @Test func bondLevelsGrow() {
        #expect(Bond().level == 0)
        #expect(Bond().name == "New friend")
        #expect(Bond(daysTogether: 3).level == 1)          // 4.5 pts
        #expect(Bond(daysTogether: 5, pets: 20).level == 2) // 15.5 pts
        #expect(Bond(daysTogether: 20, pets: 30).level == 3) // 42 pts
        #expect(Bond(daysTogether: 40, pets: 80, hoursTogether: 20).level == 4)
        #expect(Bond(daysTogether: 40, pets: 80, hoursTogether: 20).pointsToNext == nil)
        #expect(Bond(daysTogether: 1).strength == 0)
    }

    @Test func closeFriendsWaveAtYouMore() {
        func waves(bond: Double) -> Int {
            let w = World(seed: 35)
            w.setEnvironment(screens: [screen], windowsFrontToBack: [])
            let c = grounded(w, [500])[0]
            w.setBond(bond, forSpecies: c.species.id)
            w.cursor = Vec2(560, 20)
            var n = 0
            for _ in 0..<400 { Brain.decide(c, in: w); if c.activity == .wave { n += 1 } }
            return n
        }
        #expect(waves(bond: 1.0) > waves(bond: 0.0) + 40)
    }
}
