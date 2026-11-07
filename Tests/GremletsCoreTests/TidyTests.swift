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

    @Test func fullScreenSendsEveryoneUpToTheTopCornersAndBackDownAfter() {
        let w = World(seed: 112)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let cs = [300.0, 700, 1000].map { w.spawn(testSpecies(scale: 10), at: Vec2($0, 0)) }
        for _ in 0..<60 { w.step(1.0 / 60) }
        w.compact = true
        // The house hangs in the top-right corner, a branch grows from the top-left.
        w.notchHome = NotchHome(minX: scr.maxX - 206, maxX: scr.maxX - 12, menuBottom: scr.maxY)
        #expect(w.cornerBranch != nil && w.notchHomeShowing)
        var upThere = 0
        for _ in 0..<(60 * 60) {
            w.step(1.0 / 60)
            upThere = cs.filter { World.isNotchOwner($0.groundOwner) || $0.homeUntil != nil }.count
            if upThere == cs.count { break }
        }
        #expect(upThere == cs.count, "all up in the corners")
        for _ in 0..<(60 * 120) {
            w.step(1.0 / 60)
            for c in cs where c.isGrounded { #expect(c.pos.y > scr.maxY - 200, "stays up top (\(c.pos))") }
        }
        #expect(w.kite == nil && w.ferry == nil && w.chests.isEmpty)
        // Back to normal: they drift down.
        w.compact = false
        w.notchHome = nil
        for _ in 0..<(60 * 90) { w.step(1.0 / 60) }
        // Back down by the floor (any of them may be mid-hop by now).
        #expect(cs.filter { $0.homeUntil == nil }.allSatisfy { $0.pos.y < 160 }, "\(cs.map(\.pos))")
    }

    @Test func inFullScreenTheyKeepOutOfThePointersWay() {
        for seed in [115, 116, 117] as [UInt64] {
            let w = World(seed: seed)
            w.maxHobbies = 0
            w.setEnvironment(screens: [scr], windowsFrontToBack: [])
            let cs = (0..<6).map { w.spawn(testSpecies(scale: 10), at: Vec2(200 + Double($0) * 180, 0)) }
            w.compact = true
            w.notchHome = NotchHome(minX: scr.maxX - 206, maxX: scr.maxX - 12, menuBottom: scr.maxY)
            for _ in 0..<(60 * 60) {
                w.step(1.0 / 60)
                if cs.allSatisfy({ World.isNotchOwner($0.groundOwner) || $0.homeUntil != nil }) { break }
            }
            for _ in 0..<(60 * 5) { w.step(1.0 / 60) }
            // Point right at each one in turn (its middle, where a button behind it would be).
            for c in cs where c.isGrounded && World.isNotchOwner(c.groundOwner) && c.homeUntil == nil {
                let cur = Vec2(c.pos.x, c.pos.y + c.size.y / 2)
                w.cursor = cur
                for _ in 0..<60 { w.step(1.0 / 60) }   // a second
                #expect((Vec2(c.pos.x, c.pos.y + c.size.y / 2) - cur).length > 100, "well clear (\(c.pos) vs \(cur), \(c.activity))")
                // And the button stays clear while the pointer rests there (nobody wanders back under it).
                for _ in 0..<(60 * 4) {
                    w.step(1.0 / 60)
                    for o in w.creatures where o.homeUntil == nil && o.isGrounded && o.activity != .land {
                        #expect(!o.bounds.contains(cur), "\(o.id) back under the pointer at \(o.pos)")
                    }
                }
            }
            w.cursor = nil
        }
    }

    @Test func rotationNeverPlantsAKindTwice() {
        let w = World(seed: 113)
        w.rotateGrove = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        for _ in 0..<6 { w.rotateGroveNow(); w.step(1.0 / 60) }
        for _ in 0..<40 { w.feedGrove() }
        let kinds = w.grove.plants.map(\.kind)
        #expect(Set(kinds).count == kinds.count, "\(kinds)")
    }

    @Test func fullScreenNeverLeavesAGroveTaskStuck() {
        let w = World(seed: 114)
        w.maxHobbies = 0
        w.rotateGrove = true; w.villageOn = false
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.loadGrove(Grove())
        let cs = [60.0, 120, 1300].map { w.spawn(testSpecies(scale: 10), at: Vec2($0, 0)) }
        w.compact = true
        for _ in 0..<(60 * 240) {
            w.step(1.0 / 60)
            // Anyone with a grove errand is on its way to it (not standing about with it forever).
            for c in cs where c.groveTask != nil { #expect([.walk, .airborne, .crouch, .land].contains(c.activity), "\(c.activity)") }
        }
    }
}


@Suite struct BusyTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 900)

    @Test func eightGremletsAllFindAPerchInFullScreen() {
        let w = World(seed: 151)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let cs = (0..<8).map { w.spawn(testSpecies(scale: 10), at: Vec2(150 + Double($0) * 150, 0)) }
        for _ in 0..<60 { w.step(1.0 / 60) }
        w.notchHome = NotchHome(minX: scr.maxX - 206, maxX: scr.maxX - 12, menuBottom: scr.maxY)
        w.compact = true
        var up = 0
        for _ in 0..<(60 * 90) {
            w.step(1.0 / 60)
            up = cs.filter { World.isNotchOwner($0.groundOwner) || $0.homeUntil != nil }.count
            if up == cs.count { break }
        }
        #expect(up == 8, "all eight up in the corners (\(up))")
        // Spread out: no perch holds more than it has room for.
        for p in w.compactPerches {
            let n = cs.filter { $0.groundOwner == p.ownerID }.count
            #expect(Double(n) <= max(1, p.width / 34) + 1, "\(n) on a \(Int(p.width)) pt perch")
        }
        #expect(w.cornerBranches.count > 1, "a crowd gets more branches")
    }

    @Test func fullScreenSpotsGrowOnlyWithTheCrowd() {
        let w = World(seed: 153)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let two = (0..<2).map { w.spawn(testSpecies(scale: 10), at: Vec2(300 + Double($0) * 300, 0)) }
        w.notchHome = NotchHome(minX: scr.maxX - 206, maxX: scr.maxX - 12, menuBottom: scr.maxY)
        w.compact = true
        for _ in 0..<(60 * 20) { w.step(1.0 / 60) }
        #expect(w.cornerBranches.count == 1 && w.cornerStumps.isEmpty, "two Gremlets: just the house and one branch")
        // A crowd arrives: more branches come out, and once those are full, the stumps in the bottom corners too.
        for i in 0..<18 { _ = w.spawn(testSpecies(scale: 10), at: Vec2(200 + Double(i) * 100, 0)) }
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(w.cornerBranches.count == 5 && w.cornerStumps.count == 2, "\(w.cornerBranches.count) branches")
        _ = two
    }

    @Test func withNowhereLeftUpTopAShyGremletHopsDownToAStump() {
        let w = World(seed: 154)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 0))
        w.notchHome = NotchHome(minX: scr.maxX - 206, maxX: scr.maxX - 12, menuBottom: scr.maxY)
        w.compact = true
        for _ in 0..<(60 * 60) where !(c.isGrounded && c.groundOwner == World.cornerBranchOwner) {
            w.step(1.0 / 60)
            // Steer it to the top-left branch (the only perch on that side while it's alone).
            if c.isGrounded && c.groundOwner != World.cornerBranchOwner && c.activity != .float && World.isNotchOwner(c.groundOwner) {
                w.startFloat(c, to: Vec2(scr.minX + 70, scr.maxY - 96))
            }
        }
        guard c.groundOwner == World.cornerBranchOwner else { Issue.record("never reached the branch"); return }
        // The pointer sits over the whole branch: nowhere up there is clear, so down it goes.
        w.cursor = Vec2(scr.minX + 70, scr.maxY - 80)
        var landed = false
        for _ in 0..<(60 * 6) {
            w.step(1.0 / 60)
            if c.isGrounded && c.groundOwner == World.cornerStumpOwner { landed = true; break }
        }
        #expect(landed, "on the bottom-left stump (\(c.pos), \(c.groundOwner ?? 0))")
    }

    @Test func aGremletTravelsToABareWindowAndPlantsMossThere() throws {
        let w = World(seed: 152)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 100, y: 0, w: 400, h: 200)),
                                                               WindowInfo(id: 2, frame: Rect(x: 600, y: 0, w: 400, h: 320))])
        w.mossMinutes = 60
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 220))
        for _ in 0..<60 { w.step(1.0 / 60) }
        #expect(w.startExpedition(c, .plant(2)))
        for _ in 0..<(60 * 60) where !w.mossPatches.contains(where: { $0.windowID == 2 }) { w.step(1.0 / 60) }
        #expect(w.mossPatches.contains { $0.windowID == 2 }, "planted on the other window")
    }

    @Test func mowingRunsAlongAWindowTopAndTidiesTheMoss() {
        let w = World(seed: 153)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 100, y: 0, w: 600, h: 200))])
        w.mossMinutes = 80
        w.mossCare = 0.5
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(150, 220))
        for _ in 0..<60 { w.step(1.0 / 60) }
        w.startMossTask(c, .mow(window: 1, to: 560), walkTo: c.pos.x)
        var mowed = false, sawMowing = false
        for _ in 0..<(60 * 20) where !mowed {
            w.step(1.0 / 60)
            if c.mowing { sawMowing = true }
            mowed = w.drainMossEvents().contains { if case .trimmed = $0 { return true }; return false }
        }
        #expect(sawMowing && mowed)
        #expect(c.pos.x > 500, "all the way along (\(c.pos.x))")
        #expect(w.mossCare > 0.5 && w.mossMinutes >= 79)
    }
}
