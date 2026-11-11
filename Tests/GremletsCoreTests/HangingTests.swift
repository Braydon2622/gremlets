import Foundation
import Testing
@testable import GremletsCore

@Suite struct HangingTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    /// A Mac without a notch: the nest hut is home.
    func nestWorld(seed: UInt64) -> World {
        let w = World(seed: seed)
        w.maxHobbies = 0
        w.topCornerPerches = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 400, y: 0, w: 600, h: 300))])
        return w
    }

    @Test func foragersStockThePantryAndTheHouseGrowsWithoutClaude() throws {
        let w = nestWorld(seed: 401)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(600, 302))
        settle(w)
        #expect(w.homePorch != nil && w.pantrySpot != nil)
        #expect(w.ideas(for: c).contains(.forage))
        #expect(w.ask(c, .forage))
        var stocked = 0, foraged = 0
        for _ in 0..<(60 * 40) where stocked == 0 {
            w.step(1.0 / 60)
            for e in w.drainHomeEvents() {
                if case .foraged = e { foraged += 1 }
                if case .stocked = e { stocked += 1 }
            }
        }
        #expect(foraged == 1 && stocked == 1, "found something in the moss and floated home with it")
        #expect(w.pantry == 1 && w.homeCare == 1)
        #expect(c.groundOwner == w.homePorch?.ownerID)
        // Care adds up: no Claude sessions at all, and the house still grows.
        #expect(w.houseStage == 0)
        w.homeCare = 15
        #expect(w.houseStage == 1)
        w.homeCare = 300
        #expect(w.houseStage == 4)
    }

    @Test func pointerOnTheHouseCallsSomeoneOutOfTheNest() throws {
        let w = nestWorld(seed: 402)
        let nest = try #require(w.topStructures.first { $0.kind == .nestHut }?.surface)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(nest.minX + 60, nest.y + 2))
        settle(w, 1)
        w.goInsideNest(c)
        #expect(w.insideNest.count == 1)
        settle(w, 1)
        #expect(w.nudgeHome())
        #expect(!w.nudgeHome(), "not again straight away")
        settle(w, 0.5)
        #expect(w.insideNest.isEmpty && c.homeUntil == nil)
        #expect(c.groundOwner == nest.ownerID, "out onto the porch")
        #expect(c.activity == .wave)
    }

    @Test func aBirdDropsByLandsAndFliesOffFromThePointer() {
        let w = nestWorld(seed: 403)
        w.crittersOn = true
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(600, 302))
        settle(w, 1)
        _ = c
        #expect(w.spawnBird())
        var landed = false
        for _ in 0..<(60 * 20) where !landed { w.step(1.0 / 60); landed = w.birds.first?.state == .perched }
        #expect(landed)
        let b = w.birds[0]
        w.cursor = b.pos + Vec2(10, 10)
        w.step(1.0 / 60)
        #expect(w.birds.first?.state == .leaving)
        w.cursor = nil
        for _ in 0..<(60 * 20) { w.step(1.0 / 60) }
        #expect(w.birds.isEmpty, "flew off the screen")
    }

    @Test func askingForStairsSkipsTheWait() throws {
        let w = World(seed: 404)
        w.maxHobbies = 0
        w.maxJumpHeight = 50
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 700, y: 0, w: 500, h: 150))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(420, 2))
        settle(w, 1)
        w.nextStairAt = w.clock + 500
        #expect(w.ideas(for: c).contains(.stairs))
        #expect(w.ask(c, .stairs))
        #expect(c.stair != nil)
        // Asleep: the only thing to ask is to wake up.
        let d = w.spawn(testSpecies(scale: 10), at: Vec2(200, 2))
        settle(w, 1)
        d.set(.sleep, duration: 60)
        #expect(w.ideas(for: d) == [.wakeUp])
        #expect(w.ask(d, .wakeUp) && !d.isAsleep)
        #expect(w.ask(d, .snack))
    }

    @Test func eveningSupperOnThePorchEmptiesThePantry() {
        let w = nestWorld(seed: 405)
        let tz = Double(TimeZone.current.secondsFromGMT())
        w.wallClock = 1_728_000_000.0 - 1_728_000_000.0.truncatingRemainder(dividingBy: 86_400) + 18 * 3600 - tz
        w.pantry = 3
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(600, 302))
        settle(w, 1)
        #expect(w.ideas(for: c).contains(.supper))
        #expect(w.ask(c, .supper))
        var ate = false
        for _ in 0..<(60 * 40) where !ate {
            w.step(1.0 / 60)
            ate = w.drainHomeEvents().contains { if case .supper = $0 { return true }; return false }
        }
        #expect(ate && w.pantry == 2, "up to the porch for supper")
        #expect(c.groundOwner == w.homePorch?.ownerID)
    }

    @Test func widgetsInTheTopLeftSendTheNestHutToTheOtherCorner() throws {
        let w = World(seed: 406)
        w.topCornerPerches = true
        let widget = WindowInfo(id: 9, frame: Rect(x: 8, y: 500, w: 360, h: 300), isWidget: true)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [widget])
        let nest = try #require(w.topStructures.first { $0.kind == .nestHut }?.surface)
        #expect(nest.minX > scr.maxX - 200, "over in the top-right corner, not over the widgets")
        #expect(!w.topStructures.contains { $0.kind == .leafSwing })
        #expect(w.cornerBranches.allSatisfy { $0.minX > scr.midX })
        let right = WindowInfo(id: 10, frame: Rect(x: 1200, y: 600, w: 200, h: 200), isWidget: true)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [widget, right])
        #expect(w.topStructures.isEmpty)
    }
}
