import Testing
@testable import GremletsCore

/// 4x4 test species: fully opaque except the top-left pixel.
func testSpecies(scale: Double = 10) -> SpeciesInfo {
    var mask = Array(repeating: true, count: 16)
    mask[0] = false
    return SpeciesInfo(id: "t", name: "T", element: "", frameWidth: 4, frameHeight: 4, scale: scale,
                       animations: ["idle": .init(frames: [0], durations: [1])], masks: [mask])
}

let screen = Rect(x: 0, y: 0, w: 1000, h: 800)

func settle(_ w: World, _ seconds: Double = 2) {
    for _ in 0..<Int(seconds * 60) { w.step(1.0 / 60) }
}

@Suite struct SurfaceTests {
    @Test func floorAndWindowTop() {
        let s = SurfaceBuilder.build(screens: [screen], windowsFrontToBack: [WindowInfo(id: 7, frame: Rect(x: 100, y: 200, w: 300, h: 200))])
        #expect(s.contains(Surface(ownerID: -1, kind: .floor, y: 0, minX: 0, maxX: 1000)))
        #expect(s.contains(Surface(ownerID: 7, kind: .windowTop, y: 400, minX: 100, maxX: 400)))
    }

    @Test func occludedEdgeIsSplit() {
        // Front window covers the middle of the back window's top edge.
        let front = WindowInfo(id: 1, frame: Rect(x: 200, y: 300, w: 100, h: 300))
        let back = WindowInfo(id: 2, frame: Rect(x: 100, y: 200, w: 400, h: 200))
        let tops = SurfaceBuilder.build(screens: [screen], windowsFrontToBack: [front, back]).filter { $0.ownerID == 2 }
        #expect(tops.map { [$0.minX, $0.maxX] } == [[100, 200], [300, 500]])
    }

    @Test func edgeTooCloseToScreenTopIsSkipped() {
        let s = SurfaceBuilder.build(screens: [screen], windowsFrontToBack: [WindowInfo(id: 3, frame: Rect(x: 0, y: 0, w: 500, h: 790))])
        #expect(!s.contains { $0.ownerID == 3 })
    }

    @Test func spanSubtract() {
        #expect(Span.subtract([Span(0, 10)], Span(3, 5)) == [Span(0, 3), Span(5, 10)])
        #expect(Span.subtract([Span(0, 10)], Span(-5, 20)).isEmpty)
        #expect(Span.subtract([Span(0, 10)], Span(10, 20)) == [Span(0, 10)])
    }
}

@Suite struct PhysicsTests {
    @Test func fallsAndLandsOnFloor() {
        let w = World(seed: 1)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(), at: Vec2(500, 600))
        settle(w, 1.5)
        #expect(c.pos.y == 0)
        #expect(c.groundOwner == -1)
    }

    @Test func landsOnWindowTop() {
        let w = World(seed: 2)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [WindowInfo(id: 9, frame: Rect(x: 300, y: 100, w: 400, h: 300))])
        let c = w.spawn(testSpecies(), at: Vec2(500, 700))
        // Long enough to land; short enough that it hasn't wandered off.
        for _ in 0..<40 { w.step(1.0 / 60) }
        #expect(c.pos.y == 400)
        #expect(c.groundOwner == 9)
    }

    @Test func ridesMovingWindowAndFallsWhenItCloses() {
        let w = World(seed: 3)
        let win = WindowInfo(id: 9, frame: Rect(x: 300, y: 100, w: 400, h: 300))
        w.setEnvironment(screens: [screen], windowsFrontToBack: [win])
        let c = w.spawn(testSpecies(), at: Vec2(500, 700))
        for _ in 0..<40 { w.step(1.0 / 60) }
        let x0 = c.pos.x

        var moved = win
        moved.frame.x += 50; moved.frame.y += 80
        w.setEnvironment(screens: [screen], windowsFrontToBack: [moved])
        #expect(c.pos.y == 480)
        #expect(c.pos.x == x0 + 50)

        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        settle(w, 1.5)
        #expect(c.pos.y == 0)
    }

    @Test func throwBouncesOffWall() {
        let w = World(seed: 4)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(), at: Vec2(500, 300))
        w.beginDrag(c, at: Vec2(500, 300), time: 0)
        w.drag(c, to: Vec2(560, 310), time: 0.05)
        w.endDrag(c, time: 0.06)
        #expect(c.vel.x > 1000)
        settle(w, 3)
        #expect(c.pos.x <= 1000 - c.size.x * 0.3 + 0.001)
        #expect(c.pos.y == 0)
    }

    @Test func jumpTargetReachesSurfaceAbove() {
        let w = World(seed: 5)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [WindowInfo(id: 4, frame: Rect(x: 550, y: 0, w: 300, h: 200))])
        let c = w.spawn(testSpecies(), at: Vec2(400, 0))
        settle(w, 0.2)
        let v = try! #require(w.jumpTarget(for: c))
        w.launch(c, velocity: v)
        // Run until it lands somewhere.
        for _ in 0..<240 {
            w.step(1.0 / 60)
            if c.activity == .land { break }
        }
        #expect(c.groundOwner == 4)
        #expect(c.pos.y == 200)
    }

    @Test func multiMonitorWalkThrough() {
        let w = World(seed: 6)
        let right = Rect(x: 1000, y: 0, w: 800, h: 800)
        w.setEnvironment(screens: [screen, right], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(), at: Vec2(990, 0))
        let (lo, hi) = w.horizontalLimits(for: c, atY: 1)
        #expect(lo < 50 && hi > 1700)
    }
}

@Suite struct InteractionTests {
    @Test func perPixelHitTest() {
        let w = World(seed: 7)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(100, 0))
        settle(w, 0.5)
        // Sprite spans x 80..120, y 0..40. The 1px slack means a 3x3 block must be clear to miss,
        // so check a point well inside and one outside the bounds.
        #expect(w.creature(at: Vec2(105, 15)) === c)
        #expect(w.creature(at: Vec2(150, 15)) == nil)
    }

    @Test func pokeWakesAndReacts() {
        let w = World(seed: 8)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(), at: Vec2(500, 0))
        settle(w, 0.3)
        c.set(.sleep, duration: 10)
        w.poke(c)
        #expect(c.activity == .react)
        #expect(w.drainEvents().contains(.wokeUp(c.id)))
    }

    @Test func sleepsWhenTired() {
        let w = World(seed: 9)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(), at: Vec2(500, 0))
        c.energy = 0.05
        var slept = false
        for _ in 0..<(60 * 60) {
            w.step(1.0 / 60)
            if c.activity == .sleep { slept = true; break }
        }
        #expect(slept)
    }

    @Test func idleWorldThrottles() {
        let w = World(seed: 10)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(), at: Vec2(500, 0))
        settle(w, 0.3)
        c.set(.sleep, duration: 10)
        #expect(w.desiredTickRate == 8)
    }
}
