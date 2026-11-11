import Testing
@testable import GremletsCore

@Suite struct EcosystemTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func sendOneOverWorksEvenForANapperAndCrossesQuickly() {
        let w = World(seed: 301)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 0, w: 600, h: 300))])
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 302))
        settle(w)
        c.set(.sleep, duration: 60)
        w.door = 1
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 0, w: 600, h: 300))])
        #expect(w.sendThroughDoor())
        let events = w.drainEcoEvents()
        #expect(events.contains { if case .tunnelDive = $0 { return true }; return false })
        var crossed = false
        for _ in 0..<(60 * 5) where !crossed { w.step(1.0 / 60); crossed = w.creaturesPastDoor().contains { $0 === c } }
        #expect(crossed, "out through the log within a few seconds (at \(c.pos))")
    }

    @Test func ownDayKeepsThemBusyWithoutClaude() {
        let w = World(seed: 302)
        w.dayFollowsClaude = true
        w.claudeAround = false
        #expect(w.ownDay && w.busyDay && !w.claudeResting)
        w.claudeAround = true
        #expect(w.claudeResting && !w.ownDay)
    }

    @Test func gremletsHopAlongTheDockAndBounceOffAnOpeningApp() {
        let w = World(seed: 303)
        w.maxHobbies = 0
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        w.dockIcons = (0..<6).map { i in DockIcon(app: "App\(i)", minX: 500 + Double(i) * 60, maxX: 552 + Double(i) * 60, top: -4) }
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(400, 2))
        settle(w)
        #expect(w.dockHopNow())
        var hops = 0
        for _ in 0..<(60 * 25) { w.step(1.0 / 60); hops += w.drainEcoEvents().filter { if case .dockHop = $0 { return true }; return false }.count }
        #expect(hops >= 2, "hopped icon to icon (\(hops))")
        // Standing on an icon as its app opens: up it goes.
        let icon = w.dockIcons[2]
        c.pos = Vec2(icon.midX, 0); c.vel = .zero
        settle(w, 1)
        c.pos.x = icon.midX
        w.dockAppOpened("App2")
        #expect(w.drainEcoEvents().contains { if case .dockBounce = $0 { return true }; return false })
        var top = 0.0
        for _ in 0..<60 { w.step(1.0 / 60); top = max(top, c.pos.y) }
        #expect(top > 80, "bounced high (\(top))")
    }

    @Test func crittersLiveInTheMossAndWidgetsGetMoss() {
        let w = World(seed: 304)
        w.maxHobbies = 0
        w.crittersOn = true
        w.mossMinutes = 90
        let widget = WindowInfo(id: 9, frame: Rect(x: 1100, y: 500, w: 160, h: 160), isWidget: true)
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 200, y: 0, w: 600, h: 300)), widget])
        #expect(w.widgetIDs == [9])
        #expect(w.surfaces.contains { $0.ownerID == 9 && $0.kind == .windowTop }, "a widget's top is somewhere to stand and grow moss")
        #expect(w.crittersNow() == 3)
        for _ in 0..<(60 * 20) { w.step(1.0 / 60) }
        #expect(!w.critters.isEmpty)
        for k in w.critters where !k.leaving && k.onHand == nil {
            let p = w.position(of: k)!
            let r = w.windows[k.windowID]!
            #expect(p.x >= r.minX - 1 && p.x <= r.maxX + 1, "stays over its own window or widget")
        }
    }
}
