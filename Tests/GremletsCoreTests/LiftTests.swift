import Testing
@testable import GremletsCore

@Suite struct LiftTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func aGremletRidesThePointerUpOntoAWindowAndDropsOff() {
        let w = World(seed: 101)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 700, y: 0, w: 500, h: 600))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 0))
        for _ in 0..<60 { w.step(1.0 / 60) }
        // Hold the keys with the pointer a little above it: it hops on.
        var p = Vec2(360, 200)
        w.setLift(p)
        var riding = false
        for _ in 0..<(60 * 3) where !riding { w.step(1.0 / 60); w.setLift(p); riding = c.groundOwner == World.liftOwner }
        #expect(riding, "hopped onto the cloud (at \(c.pos), \(c.activity))")
        // Carry it over the window, above its top.
        for _ in 0..<90 { p = p + Vec2(6, 6); w.setLift(p); w.step(1.0 / 60) }
        #expect(c.groundOwner == World.liftOwner && abs(c.pos.x - (p.x + 8)) < 2, "rode along")
        // Let go: it drops onto the window top.
        w.setLift(nil)
        for _ in 0..<(60 * 3) { w.step(1.0 / 60) }
        #expect(c.groundOwner == 1 && abs(c.pos.y - 600) < 1, "landed on the window (at \(c.pos))")
        #expect(w.lift == nil && !w.surfaces.contains { $0.ownerID == World.liftOwner })
    }
}
