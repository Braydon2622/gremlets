import Testing
@testable import GremletsCore

@Suite struct PodTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)

    @Test func aHutHangsBesideTheTerminalAwayFromItsTreeAndTheBranchIsAPerch() throws {
        let w = World(seed: 81)
        w.maxHobbies = 0
        var win = WindowInfo(id: 9, frame: Rect(x: 200, y: 150, w: 700, h: 400))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        w.loadBonsai(BonsaiBook())
        w.bonsaiStart(project: "Demo", session: "a", windowID: 9)
        let pod = try #require(w.podPlacements.first)
        let tree = try #require(w.bonsaiPlacements.first)
        #expect((tree.base.x < 550) == (pod.side > 0), "at the corner away from the tree")
        #expect(pod.side > 0 ? pod.tie.x > 900 : pod.tie.x < 200, "hanging outside the window, not over it")
        let branch = try #require(w.surfaces.first { World.isPodOwner($0.ownerID) })
        let c = w.spawn(testSpecies(scale: 10), at: Vec2((branch.minX + branch.maxX) / 2, branch.y + 20))
        for _ in 0..<120 where c.groundOwner != branch.ownerID { w.step(1.0 / 60) }
        #expect(c.groundOwner == branch.ownerID, "perched on the branch")
        let x = c.pos.x
        win.frame.x += 40
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        #expect(abs(c.pos.x - x - 40) < 0.01, "rides along with the window")
        // No room beside a window that fills the screen's width: no hut.
        w.setEnvironment(screens: [scr], windowsFrontToBack: [WindowInfo(id: 9, frame: Rect(x: 0, y: 150, w: 1440, h: 400))])
        #expect(w.podPlacements.isEmpty)
        w.bonsaiEnd(project: "Demo")
        #expect(!w.surfaces.contains { World.isPodOwner($0.ownerID) })
    }
}
