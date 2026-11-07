import Testing
@testable import GremletsCore

@Suite struct NotchTests {
    // A 13" MacBook-ish screen: the notch spans 640...830 at the top, the menu bar ends at 924.
    let scr = Rect(x: 0, y: 0, w: 1470, h: 924)

    @Test func aGremletClimbsUpToTheHammockUnderTheNotchForANap() throws {
        let w = World(seed: 91)
        w.maxHobbies = 0
        w.dayFollowsClaude = true
        // Windows stacked like stairs toward the top of the screen.
        w.setEnvironment(screens: [scr], windowsFrontToBack: [
            WindowInfo(id: 1, frame: Rect(x: 200, y: 0, w: 500, h: 330)),
            WindowInfo(id: 2, frame: Rect(x: 420, y: 0, w: 520, h: 560)),
            WindowInfo(id: 3, frame: Rect(x: 760, y: 0, w: 480, h: 780)),
        ])
        w.notchHome = NotchHome(minX: 640, maxX: 830, menuBottom: 924)
        #expect(w.surfaces.contains { $0.ownerID == World.notchHammockOwner })
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 400))
        for _ in 0..<120 { w.step(1.0 / 60) }
        #expect(w.startNotchTrip(), "found a way up")
        var napped = false
        for _ in 0..<(60 * 150) where !napped {
            w.step(1.0 / 60)
            // In the hammock, or curled up inside the house.
            napped = (c.groundOwner == World.notchHammockOwner && c.activity == .sleep) || (c.homeHouse == -1 && c.homeUntil != nil)
        }
        #expect(napped, "asleep in the hammock (at \(c.pos), \(c.activity), on \(String(describing: c.groundOwner)))")
    }

    @Test func theHomeTucksAwayWhenAWindowIsUnderTheNotch() {
        let w = World(seed: 93)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 100, y: 0, w: 1200, h: 920))])
        w.notchHome = NotchHome(minX: 640, maxX: 830, menuBottom: 924)
        #expect(!w.notchHomeShowing && !w.surfaces.contains { World.isNotchOwner($0.ownerID) })
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 100, y: 0, w: 1200, h: 700))])
        #expect(w.notchHomeShowing && w.surfaces.contains { World.isNotchOwner($0.ownerID) })
    }

    @Test func noNotchNoHome() {
        let w = World(seed: 92)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        #expect(!w.startNotchTrip())
        #expect(!w.surfaces.contains { World.isNotchOwner($0.ownerID) })
    }
}
