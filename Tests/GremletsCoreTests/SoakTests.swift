import Foundation
import Testing
@testable import GremletsCore

@Suite struct SoakTests {
    /// Eight creatures, two windows that move and close, a wandering cursor: ten simulated minutes.
    @Test func tenMinutesOfLife() {
        let w = World(seed: 99)
        let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
        var win1 = WindowInfo(id: 1, frame: Rect(x: 200, y: 100, w: 500, h: 380))
        let win2 = WindowInfo(id: 2, frame: Rect(x: 800, y: 50, w: 450, h: 520))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win1, win2])
        for i in 0..<8 {
            var s = testSpecies(scale: 12)
            s.flies = i % 3 == 0
            w.spawn(s, at: Vec2(150 + Double(i) * 150, 700))
        }
        var counts: [String: Int] = [:]
        let dt = 1.0 / 30
        for frame in 0..<(60 * 10 * 30) {
            let t = Double(frame) * dt
            // Cursor drifts around; window 1 slides back and forth; window 2 closes for a while.
            w.cursor = Vec2(720 + 600 * sin(t * 0.3), 300 + 200 * sin(t * 0.17))
            if frame % 3 == 0 {
                win1.frame.x = 200 + 150 * sin(t * 0.2)
                let closed = Int(t / 40) % 3 == 2
                w.setEnvironment(screens: [scr], windowsFrontToBack: closed ? [win1] : [win1, win2])
            }
            w.step(dt)
            for e in w.drainEvents() {
                let name = "\(e)".split(separator: "(").first.map(String.init) ?? "\(e)"
                counts[name, default: 0] += 1
            }
            for c in w.creatures {
                #expect(c.pos.x.isFinite && c.pos.y.isFinite)
                #expect(c.pos.x >= -1 && c.pos.x <= scr.maxX + 1, "creature \(c.id) left the screen: \(c.pos)")
                #expect(c.pos.y >= -1 && c.pos.y <= scr.maxY + 1)
            }
        }
        print("soak event counts:", counts.sorted { $0.key < $1.key })
        for kind in ["greet", "special", "tookOff", "danceBeat", "fellAsleep", "landed"] {
            #expect((counts[kind] ?? 0) > 0, "never saw \(kind)")
        }
        #expect((counts["tagged"] ?? 0) + (counts["stacked"] ?? 0) + (counts["bump"] ?? 0) > 0)
    }
}
