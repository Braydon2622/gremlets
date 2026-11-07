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
