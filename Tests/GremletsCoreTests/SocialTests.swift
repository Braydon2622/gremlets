import Testing
@testable import GremletsCore

func flyer() -> SpeciesInfo {
    var s = testSpecies()
    s.flies = true
    return s
}

func grounded(_ w: World, _ xs: [Double]) -> [Creature] {
    let cs = xs.map { w.spawn(testSpecies(), at: Vec2($0, 0)) }
    for _ in 0..<5 { w.step(1.0 / 60) }
    for c in cs { c.set(.idle, duration: 30) }
    return cs
}

@Suite struct SocialTests {
    @Test func riderMovesWithCarrier() {
        let w = World(seed: 21)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [500, 600])
        let (base, rider) = (cs[0], cs[1])
        w.startStack(rider, base)
        for _ in 0..<120 {
            w.step(1.0 / 60)
            if rider.groundOwner == base.carrierOwnerID { break }
        }
        #expect(rider.groundOwner == base.carrierOwnerID)
        #expect(rider.pos.y == base.species.headTop)
        rider.set(.idle, duration: 30)
        base.facing = 1
        base.set(.walk, duration: 30)
        let (bx, rx) = (base.pos.x, rider.pos.x)
        for _ in 0..<30 { w.step(1.0 / 60) }
        #expect(base.pos.x > bx + 10)
        #expect(abs((rider.pos.x - rx) - (base.pos.x - bx)) < 0.001)
    }

    @Test func greetingMakesBothWave() {
        let w = World(seed: 22)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [400, 560])
        w.startGreet(cs[0], cs[1])
        var greeted = false
        for _ in 0..<(60 * 5) {
            w.step(1.0 / 60)
            if w.drainEvents().contains(.greet(cs[0].id, cs[1].id)) { greeted = true; break }
        }
        #expect(greeted)
        #expect(cs[0].activity == .wave && cs[1].activity == .wave)
    }

    @Test func tagSwapsRoles() {
        let w = World(seed: 23)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [300, 420])
        w.startTag(cs[0], cs[1])
        var tags = 0
        for _ in 0..<(60 * 10) {
            w.step(1.0 / 60)
            tags += w.drainEvents().filter { if case .tagged = $0 { return true }; return false }.count
        }
        #expect(tags >= 1)
    }

    @Test func flightLandsOnAWindow() {
        let w = World(seed: 24)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [WindowInfo(id: 5, frame: Rect(x: 300, y: 0, w: 400, h: 450))])
        let c = w.spawn(flyer(), at: Vec2(150, 0))
        for _ in 0..<5 { w.step(1.0 / 60) }
        w.startFlight(c)
        #expect(c.activity == .fly)
        for _ in 0..<(60 * 10) {
            w.step(1.0 / 60)
            if c.isGrounded && c.activity != .fly { break }
        }
        #expect(c.groundOwner == 5)
        #expect(c.pos.y == 450)
    }

    @Test func walkersBumpAndBounce() {
        let w = World(seed: 25)
        w.bumpChance = 1
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let cs = grounded(w, [480, 520])
        cs[0].facing = 1; cs[1].facing = -1
        cs[0].set(.walk, duration: 5); cs[1].set(.walk, duration: 5)
        var bumped = false
        for _ in 0..<60 {
            w.step(1.0 / 60)
            let ev = w.drainEvents()
            if ev.contains(.bump(cs[0].id, cs[1].id)) || ev.contains(.bump(cs[1].id, cs[0].id)) { bumped = true; break }
        }
        #expect(bumped)
        #expect(cs[0].activity == .airborne)
    }
}
