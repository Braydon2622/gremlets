import Testing
@testable import GremletsCore

/// The rain barrel and the basket lift on the hanging home's porch (Homestead.swift).
@Suite struct HomesteadTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
    /// A Mac without a notch, so the nest hut in the top-left corner is home; a window top a little way under it.
    func world(seed: UInt64) -> World {
        let w = World(seed: seed)
        w.maxHobbies = 0
        w.topCornerPerches = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 0, y: 0, w: 600, h: 520))])
        return w
    }

    @Test func rainFillsTheBarrelAndRainwaterDoesTheMossTwiceTheGood() throws {
        let w = world(seed: 601)
        w.rainBarrel = 0
        w.liveWeather = LocalWeather(sky: .rain)
        for _ in 0..<(60 * 60) { w.step(1.0 / 60) }   // a minute of rain
        #expect(w.rainBarrel > 0.05)
        w.liveWeather = LocalWeather(sky: .clear)
        w.rainBarrel = 0.8
        w.mossMinutes = 40
        w.mossCare = 0.4
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 522))
        for _ in 0..<(60 * 60) where !(c.isGrounded && c.groundOwner == 1 && c.mossTask == nil && c.job == nil) { w.step(1.0 / 60) }
        #expect(w.ideas(for: c).contains(.rainwater))
        #expect(w.ask(c, .rainwater))
        var drew = false
        for _ in 0..<(60 * 40) where !drew {
            w.step(1.0 / 60)
            drew = w.drainHomeEvents().contains { if case .drewWater = $0 { return true }; return false }
        }
        #expect(drew && w.rainBarrel < 0.7 && c.hasRainwater, "up to the barrel for a canful")
        // Back down (basket or leaf) and straight to watering.
        w.mossCare = 0.3
        for _ in 0..<(60 * 60) where c.hasRainwater { w.step(1.0 / 60) }
        #expect(!c.hasRainwater)
        #expect(w.mossCare >= 0.75, "rainwater: twice the good")
    }

    @Test func theBasketCarriesAGremletUpHomeAndBackDown() throws {
        let w = world(seed: 602)
        let porch = try #require(w.homePorch)
        let x = try #require(w.basketX)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(x + 140, 522))
        settle(w, 1)
        #expect(w.basketLanding()?.ownerID == 1)
        #expect(w.ideas(for: c).contains(.basket))
        #expect(w.ask(c, .basket))
        var rode = false, home = false
        for _ in 0..<(60 * 40) where !home {
            w.step(1.0 / 60)
            if c.inBasket { rode = true; #expect(abs(c.pos.x - x) < 1 && c.pos.y >= 519 && c.pos.y <= porch.y) }
            home = w.drainHomeEvents().contains { if case .basketArrived(_, _, true) = $0 { return true }; return false }
        }
        #expect(rode && home)
        settle(w, 0.5)
        #expect(c.groundOwner == porch.ownerID, "stepped out onto the porch")
        for _ in 0..<(60 * 15) where w.basket != nil { w.step(1.0 / 60) }
        #expect(w.basket == nil, "the basket's back up under the porch")
        // And back down again.
        settle(w, 2)
        #expect(w.ask(c, .basket))
        var down = false
        for _ in 0..<(60 * 40) where !down {
            w.step(1.0 / 60)
            down = w.drainHomeEvents().contains { if case .basketArrived(_, _, false) = $0 { return true }; return false }
        }
        #expect(down)
        settle(w, 0.5)
        #expect(c.groundOwner == 1)
    }

    @Test func aWindowClosingMidRideTipsTheRiderOutSafely() throws {
        let w = world(seed: 603)
        let x = try #require(w.basketX)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(x + 60, 522))
        settle(w, 1)
        #expect(w.ask(c, .basket))
        for _ in 0..<(60 * 30) where !c.inBasket { w.step(1.0 / 60) }
        #expect(c.inBasket)
        settle(w, 1)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        settle(w, 6)
        #expect(!c.inBasket && c.isGrounded, "hopped out and landed")
        #expect(w.basket == nil)
    }

    @Test func aRiderCalledAwayToWorkIsntLeftHalfInTheBasket() throws {
        let w = world(seed: 604)
        let x = try #require(w.basketX)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(x + 60, 522))
        settle(w, 1)
        var asked = false
        for _ in 0..<(60 * 5) where !asked { w.step(1.0 / 60); asked = w.ask(c, .basket) }   // (once it's not mid-hop)
        #expect(asked)
        for _ in 0..<(60 * 30) where !c.inBasket { w.step(1.0 / 60) }
        #expect(c.inBasket)
        // A Claude job comes in: it floats off to work, and the basket goes home.
        w.startFloat(c, to: Vec2(900, 302))
        settle(w, 8)
        #expect(!c.inBasket && w.basket == nil)
    }
}
