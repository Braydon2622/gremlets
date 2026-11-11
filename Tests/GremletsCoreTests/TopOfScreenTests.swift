import Testing
@testable import GremletsCore

/// A window filling the screen has its top edge right up under the menu bar: moss still grows along it, and Gremlets
/// walk the stretches where the menu bar above is empty (never in front of the menus, the status icons or the notch).
@Suite struct TopOfScreenTests {
    // A 1470×956 notched laptop: usable area 57...918, a 38-point menu bar, the notch at 646...825.
    let scr = Rect(x: 0, y: 57, w: 1470, h: 861)
    let bar = MenuBar(height: 38, clear: [Span(390, 638), Span(833, 894)])
    let full = WindowInfo(id: 1, frame: Rect(x: 0, y: 57, w: 1470, h: 854))   // top at 911

    @Test func aFullHeightWindowGetsMossAndAWalkUnderTheEmptyMenuBar() {
        let w = World(seed: 501)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [full], menuBars: [bar])
        #expect(w.topEdges.contains { $0.ownerID == 1 && $0.minX == 0 && $0.maxX == 1470 }, "moss grows along the whole top")
        let walk = w.surfaces.filter { $0.ownerID == 1 && $0.kind == .windowTop }
        #expect(walk.count == 2)
        #expect(walk.allSatisfy { s in bar.clear.contains { $0.lo <= s.minX && $0.hi >= s.maxX } }, "only under empty menu bar")

        // Without knowing where the menu bar is empty, nobody walks up there (but the moss is still there).
        let v = World(seed: 502)
        v.setEnvironment(screens: [scr], windowsFrontToBack: [full])
        #expect(!v.surfaces.contains { $0.ownerID == 1 && $0.kind == .windowTop })
        #expect(v.topEdges.contains { $0.ownerID == 1 })
    }

    @Test func aGremletDroppedUpThereStaysAndPottersAbout() {
        let w = World(seed: 503)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [full], menuBars: [bar])
        let c = w.spawn(testSpecies(scale: 24), at: Vec2(500, 940))
        var up = 0, log: [String] = []
        for i in 0..<(60 * 30) {
            w.step(1.0 / 60)
            if c.groundOwner == 1 { up += 1; #expect(c.pos.x >= 380 && c.pos.x <= 650, "stays on its stretch") }
            if i % 60 == 0 { log.append("\(c.activity) \(c.groundOwner ?? 0) \(Int(c.pos.x)),\(Int(c.pos.y))") }
        }
        #expect(up > 60 * 15, "up there a good while (until it floats down on a leaf) (\(log))")
    }

    @Test func aGremletCanJumpUpOntoIt() {
        let w = World(seed: 504)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [full], menuBars: [bar])
        let c = w.spawn(testSpecies(scale: 24), at: Vec2(500, 940))
        settle(w, 1)
        #expect(c.groundOwner == 1)
        // From just below, a hop lands on it rather than bonking on the top of the screen.
        c.pos = Vec2(500, 880); c.groundOwner = nil; c.set(.airborne, duration: 5)
        c.vel = Vec2(0, 520)
        var landed = false
        for _ in 0..<(60 * 3) where !landed { w.step(1.0 / 60); landed = c.groundOwner == 1 }
        #expect(landed)
    }
}
