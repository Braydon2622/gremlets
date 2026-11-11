import Foundation
import Testing
@testable import GremletsCore

/// The vegetable patch, the mailbox and the lanterns on the moss (Porch.swift).
@Suite struct PorchTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
    /// A Mac without a notch, so the nest hut in the top-left corner is home; a window top a little way under it.
    func world(seed: UInt64) -> World {
        let w = World(seed: seed)
        w.maxHobbies = 0
        w.topCornerPerches = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 0, y: 0, w: 600, h: 520))])
        return w
    }

    func at(hour: Int, _ w: World) {
        let tz = Double(TimeZone.current.secondsFromGMT())
        w.wallClock = 1_728_000_000.0 - 1_728_000_000.0.truncatingRemainder(dividingBy: 86_400) + Double(hour) * 3600 - tz
    }

    /// Steps until it's standing about on the window top, free to be asked.
    /// (They're a lively lot: ask the moment it's landed on the window top, before it's off doing something else.)
    func ready(_ w: World, _ c: Creature, owner: Int? = 1) {
        for _ in 0..<(60 * 60) where !(c.isGrounded && (owner == nil || c.groundOwner == owner) && c.mossTask == nil && c.job == nil) { w.step(1.0 / 60) }
    }

    func run(_ w: World, seconds: Double, until done: ([HomeEvent]) -> Bool) -> Bool {
        for _ in 0..<Int(seconds * 60) {
            w.step(1.0 / 60)
            if done(w.drainHomeEvents()) { return true }
        }
        return false
    }

    @Test func theyFloatUpToSowWaterAndPickThePatchForThePantry() throws {
        let w = world(seed: 701)
        at(hour: 11, w)
        w.liveWeather = LocalWeather(sky: .clear)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 522))
        ready(w, c)
        #expect(w.vegPatch.allSatisfy { $0.crop == nil })
        #expect(w.ideas(for: c).contains(.patch))
        #expect(w.ask(c, .patch))
        var sown = 0
        _ = run(w, seconds: 60) { ev in sown += ev.filter { if case .sowed = $0 { return true }; return false }.count; return sown == 3 }
        #expect(sown == 3, "up to the porch and all three plots sown")
        #expect(w.vegPatch.allSatisfy { $0.crop != nil && $0.water > 0.5 })
        // (Nobody else comes to tend it for now.)
        for _ in 0..<(60 * 30) where c.mossTask != nil { w.step(1.0 / 60) }
        w.nextPatchAt = .infinity
        // Dry soil: it stops growing.
        w.patchSaved = "carrot:0.5:0,radish:0.5:0,peas:0.98:0.9"
        _ = run(w, seconds: 2) { _ in false }
        #expect(w.vegPatch[0].growth == 0.5 && w.vegPatch[0].dry)
        // Rain waters it.
        w.liveWeather = LocalWeather(sky: .rain)
        _ = run(w, seconds: 1) { _ in false }
        #expect(w.vegPatch.allSatisfy { $0.water > 0.9 })
        w.liveWeather = LocalWeather(sky: .clear)
        // The peas ripen; picked, and into the pantry.
        #expect(run(w, seconds: 60) { $0.contains { if case .patchRipe = $0 { return true }; return false } })
        w.pantry = 0
        ready(w, c, owner: nil)
        #expect(w.ask(c, .patch))
        #expect(run(w, seconds: 40) { $0.contains { if case .stocked(_, _, "peas") = $0 { return true }; return false } }, "picked and stocked")
        #expect(w.pantry == 1 && w.vegPatch[2].crop == nil)
    }

    @Test func thePatchIsSavedAndRestored() {
        let w = world(seed: 702)
        w.patchSaved = "carrot:0.25:0.5,-,peas:1:0"
        #expect(w.vegPatch[0] == PatchPlot(crop: .carrot, growth: 0.25, water: 0.5))
        #expect(w.vegPatch[1].crop == nil && w.vegPatch[2].ripe)
        let again = world(seed: 703)
        again.patchSaved = w.patchSaved
        #expect(again.vegPatch == w.vegPatch)
        again.patchSaved = "junk"
        #expect(again.vegPatch.allSatisfy { $0.crop == nil })
    }

    @Test func aPostcardRaisesTheFlagAndThePointerReadsIt() throws {
        let w = world(seed: 704)
        settle(w, 0.5)
        let r = try #require(w.mailboxRect)
        w.post(Postcard(project: "Gremlets", text: "48 min · 31 edits · tests passing", at: w.wallClock))
        #expect(w.unreadMail == 1 && !w.mailOpen)
        #expect(w.drainHomeEvents().contains { if case .mailArrived = $0 { return true }; return false })
        for n in 0..<8 { w.post(Postcard(project: "p\(n)", text: "", at: w.wallClock)) }
        #expect(w.mailbox.count == 6, "keeps the last few")
        w.cursor = Vec2(r.x + r.w / 2, r.y + r.h / 2)
        settle(w, 1)
        #expect(w.mailOpen && w.unreadMail > 0)
        settle(w, 2)
        #expect(w.unreadMail == 0, "read")
        w.cursor = Vec2(700, 300)
        settle(w, 1.5)
        #expect(!w.mailOpen)
    }

    @Test func lanternsGoOutAlongTheMossAtDuskAndComeInInTheMorning() throws {
        let w = world(seed: 705)
        at(hour: 20, w)
        w.isNight = true
        w.mossMinutes = 30
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 522))
        ready(w, c)
        #expect(w.ideas(for: c).contains(.lantern))
        #expect(w.ask(c, .lantern))
        #expect(run(w, seconds: 30) { $0.contains { if case .lanternHung = $0 { return true }; return false } })
        let l = try #require(w.mossLanterns.first)
        #expect(l.lit && w.lanternSpot(l)?.visible == true)
        #expect(abs((w.lanternSpot(l)?.pos.y ?? 0) - 520) < 1, "on the window top")
        // Morning: out they go, and someone takes it in.
        at(hour: 8, w)
        w.isNight = false
        settle(w, 0.5)
        #expect(w.mossLanterns.first?.lit == false)
        let d = w.spawn(testSpecies(scale: 10), at: Vec2(300, 522))
        ready(w, d)
        var take: (() -> Void)?
        w.lanternChoices(for: d) { name, _, f in if name == "takeLantern" { take = f } }
        try #require(take != nil)
        take?()
        #expect(run(w, seconds: 30) { $0.contains { if case .lanternTaken = $0 { return true }; return false } })
        #expect(w.mossLanterns.isEmpty)
    }

    @Test func aLanternGoesWithItsWindow() throws {
        let w = world(seed: 706)
        at(hour: 21, w)
        w.isNight = true
        w.mossMinutes = 30
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(300, 522))
        ready(w, c)
        _ = c
        #expect(w.hangLanternNow())
        #expect(run(w, seconds: 30) { $0.contains { if case .lanternHung = $0 { return true }; return false } })
        w.setEnvironment(screens: [scr], windowsFrontToBack: [])
        settle(w, 0.2)
        #expect(w.mossLanterns.isEmpty)
    }
}
