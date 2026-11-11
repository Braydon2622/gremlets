import Testing
@testable import GremletsCore

@Suite struct StairStressTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    /// Many builds with things happening mid-climb: whatever happens, the blocks never hang about and nobody gets stuck.
    @Test(arguments: 0..<40) func stairsNeverGetStuck(seed: Int) throws {
        let w = World(seed: UInt64(1000 + seed))
        w.maxHobbies = 0
        w.maxJumpHeight = 50
        var r = SplitMix64(seed: UInt64(seed))
        let h = 100 + Double(r.next() % 300)
        let x = 500 + Double(r.next() % 400)
        let win = WindowInfo(id: 1, frame: Rect(x: x, y: 0, w: 400, h: h))
        var wins = [win]
        if seed % 3 == 0 { wins.append(WindowInfo(id: 2, frame: Rect(x: 60, y: 0, w: 260, h: 60))) }
        w.setEnvironment(screens: [scr], windowsFrontToBack: wins)
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(x - 200, 2))
        let others = (0..<(seed % 3)).map { i in w.spawn(testSpecies(scale: 10), at: Vec2(200 + Double(i) * 90, 2)) }
        settle(w, 1)
        w.nextStairAt = 0
        guard let plan = w.stairCandidate(for: c) else { return }
        w.startStairs(c, plan)
        let disrupt = seed % 8
        let at = 60 * (2 + Int(r.next() % 5))
        var maxBlocksNoStair = 0
        var lastPos = c.pos, stillFor = 0
        for f in 0..<(60 * 60) {
            if f == at {
                switch disrupt {
                case 1: w.poke(c)
                case 2: w.beginDrag(c, at: c.pos, time: w.clock); w.drag(c, to: c.pos + Vec2(-300, 200), time: w.clock + 0.02); w.endDrag(c, time: w.clock + 0.2)
                case 3: _ = w.startJob(windowID: 1, craft: .garden, prefer: c.id)
                case 4: w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 1, frame: Rect(x: x + 300, y: 0, w: 400, h: h))])
                case 5: w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 3, frame: Rect(x: x - 260, y: 0, w: 300, h: 400)), win])
                case 6: w.door = 1; _ = w.sendThroughDoor(preferring: c.id)
                case 7: c.set(.sleep, duration: 10)
                default: break
                }
            }
            w.step(1.0 / 60)
            _ = w.drainTerrainEvents(); _ = w.drainEcoEvents()
            for k in [c] + others where k.stair == nil { maxBlocksNoStair = max(maxBlocksNoStair, k.blocksInHand) }
            if c.stair != nil && c.activity != .dragged {
                if (c.pos - lastPos).length < 0.01 { stillFor += 1 } else { stillFor = 0 }
                #expect(stillFor < 60 * 6, "builder frozen on its stairs at \(c.pos), \(c.activity) (seed \(seed))")
                if stillFor >= 60 * 6 { break }
            }
            lastPos = c.pos
        }
        if disrupt != 3 {
            #expect(w.stairs.isEmpty, "stairs gone after a minute (seed \(seed), disrupt \(disrupt), stair \(String(describing: c.stair)), pos \(c.pos), act \(c.activity))")
        } else {
            #expect(w.stairs.allSatisfy { $0.doneAt != nil } && c.stair == nil, "a Claude job takes it off its stairs, which come down (seed \(seed))")
        }
        #expect(c.blocksInHand == 0 || c.stair != nil, "not carrying blocks around for nothing (seed \(seed)): \(c.blocksInHand)")
        #expect(c.pos.y >= -1 && c.pos.y < 900)
    }
}
