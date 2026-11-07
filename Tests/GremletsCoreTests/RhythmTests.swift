import Testing
@testable import GremletsCore

/// The Gremlets' day follows Claude: gardening while it works, winding down on platforms and at home once it's quiet.
@Suite struct RhythmTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    func counts(working: Bool, seed: UInt64) -> (garden: Int, lively: Int, restful: Int) {
        let w = World(seed: seed)
        w.dayFollowsClaude = true
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: 300, y: 0, w: 700, h: 420))])
        w.loadGrove(Grove())
        let cs = (0..<4).map { w.spawn(testSpecies(scale: 10), at: Vec2(380 + Double($0) * 120, 500)) }
        for _ in 0..<60 { w.step(1.0 / 60) }
        var g = 0, l = 0, r = 0
        for _ in 0..<(60 * 180) {
            if working { w.lastClaudeWorkAt = w.clock }
            w.step(1.0 / 60)
            for c in cs {
                if c.mossTask != nil { g += 1 }
                if [.walk, .run, .dance, .fly, .airborne].contains(c.activity) && c.mossTask == nil { l += 1 }
                if [.idle, .sleep].contains(c.activity) || c.homeUntil != nil { r += 1 }
            }
        }
        return (g, l, r)
    }

    @Test func gremletsGardenWhileClaudeWorksAndRestWhenItsQuiet() {
        let busy = counts(working: true, seed: 71)
        let quiet = counts(working: false, seed: 71)
        #expect(busy.garden > quiet.garden * 2 + 100, "busy \(busy) quiet \(quiet)")
        #expect(quiet.restful > busy.restful, "busy \(busy) quiet \(quiet)")
        #expect(quiet.lively < busy.lively, "busy \(busy) quiet \(quiet)")
    }
}
