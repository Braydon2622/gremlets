import Testing
@testable import GremletsCore

/// The app's tidy desktop: one small plant at a time in the corner, no village, and in full screen everyone keeps
/// to the bottom corners.
@Suite struct TidyTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 900)

    @Test func oneSmallPlantAtATimeInTheCornerAndItChanges() throws {
        let w = World(seed: 111)
        w.rotateGrove = true; w.villageOn = false
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        w.step(1.0 / 60)
        let first = try #require(w.grove.featured)
        let f = try #require(w.groveFloor)
        let b = w.grove.base(first, floor: f)
        #expect(b.y == f.minY && b.x < f.minX + 120, "on the floor, in the bottom-left corner")
        #expect(w.grove.size(first).y < 60 || w.grove.plants[first].kind == .skyvine, "small")
        #expect(w.groveLedges.allSatisfy { $0.plot == first }, "only the corner plant offers platforms")
        let kind = w.grove.plants[first].kind
        w.rotateGroveNow()
        let second = try #require(w.grove.featured)
        #expect(w.grove.plants[second].kind != kind, "a different plant")
        // Nothing grows in the village.
        for _ in 0..<5 { w.feedGrove() }
        #expect(w.mineIndex == nil)
    }

    @Test func fullScreenSendsEveryoneToTheBottomCornersAndKeepsThemThere() {
        let w = World(seed: 112)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let cs = [300.0, 700, 1000].map { w.spawn(testSpecies(scale: 10), at: Vec2($0, 0)) }
        for _ in 0..<60 { w.step(1.0 / 60) }
        w.compact = true
        for _ in 0..<(60 * 30) { w.step(1.0 / 60) }
        for c in cs { #expect(w.inCorner(c), "\(c.pos.x) in a corner") }
        // And they stay there.
        for _ in 0..<(60 * 120) {
            w.step(1.0 / 60)
            for c in cs where c.isGrounded { #expect(c.pos.x < World.cornerZone + 3 || c.pos.x > scr.maxX - World.cornerZone - 3) }
        }
        #expect(w.kite == nil && w.ferry == nil && w.chests.isEmpty)
    }
}
