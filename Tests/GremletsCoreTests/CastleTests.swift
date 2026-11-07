import Testing
@testable import GremletsCore

@Suite struct CastleTests {
    let scr = Rect(x: 0, y: 0, w: 1440, h: 860)
    let paths = ["README.md", "Package.swift", "Sources/App/main.swift", "Sources/App/View.swift", "Sources/Core/World.swift",
                 "Tests/WorldTests.swift", "web/index.html", "web/js/app.js", "web/js/engine.js", "web/css/site.css",
                 "docs/GUIDE.md", ".github/workflows/ci.yml", "scripts/build.sh"]

    @Test func foldersBecomeTowersAndRootFilesTheKeep() throws {
        let c = Castle.from(project: "Demo", paths: paths)
        let keep = try #require(c.towers.first { $0.isKeep })
        #expect(keep.files == 2 && keep.mix["docs"] == 1 && keep.mix["swift"] == 1)
        #expect(!c.towers.contains { $0.name.hasPrefix(".") }, "hidden folders stay out")
        let web = try #require(c.towers.first { $0.name == "web" })
        #expect(web.files == 4 && web.mainLanguage == "js")
        #expect(c.towers.count == 4, "the keep plus the three biggest folders")
        // The biggest folders stand beside the keep.
        let k = try #require(c.towers.firstIndex { $0.isKeep })
        #expect([c.towers[k - 1].name, c.towers[k + 1].name].contains("web"))
        // More files, taller tower.
        let src = try #require(c.towers.firstIndex { $0.name == "Sources" })
        let keepIndex = try #require(c.towers.firstIndex { $0.isKeep })
        #expect(c.height(src) > c.height(keepIndex) - 10, "a busy folder's tower stands tall")
    }

    @Test func theCastleStandsOnTheTerminalAndEditsAddBlocks() throws {
        let w = World(seed: 81)
        w.maxHobbies = 0
        var win = WindowInfo(id: 9, frame: Rect(x: 200, y: 150, w: 900, h: 400))
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        w.loadBonsai(BonsaiBook())
        w.bonsaiStart(project: "Demo", session: "a", windowID: 9)
        w.setCastle(Castle.from(project: "Demo", paths: paths))
        let place = try #require(w.castlePlacements.first)
        #expect(place.windowID == 9 && abs(place.origin.y - 550) < 0.01)
        let tree = try #require(w.bonsaiPlacements.first)
        #expect(abs(place.origin.x - tree.base.x) > 60, "at the other end from the tree")
        let tops = w.surfaces.filter { World.isCastleOwner($0.ownerID) }
        #expect(tops.count == 1 && tops.allSatisfy { $0.y > 550 }, "the keep's lookout")
        // A Gremlet can stand on a tower, and rides along when the window moves.
        let t = try #require(tops.max { $0.y < $1.y })
        let c = w.spawn(testSpecies(scale: 10), at: Vec2((t.minX + t.maxX) / 2, t.y + 20))
        for _ in 0..<120 where c.groundOwner != t.ownerID { w.step(1.0 / 60) }
        #expect(c.groundOwner == t.ownerID)
        let x = c.pos.x
        win.frame.x += 50
        w.setEnvironment(screens: [scr], windowsFrontToBack: [win])
        #expect(abs(c.pos.x - x - 50) < 0.01)
        // An edit in web/ lands a block on that tower.
        let i = try #require(w.castles["Demo"]?.towers.firstIndex { $0.name == "web" })
        let before = try #require(w.castles["Demo"]).height(i)
        w.castleEdit(project: "Demo", area: "web")
        #expect(w.drainCastleEvents() == [.block(project: "Demo", tower: i)])
        #expect(try #require(w.castles["Demo"]).height(i) > before)
        // Rereading the file list keeps the edits.
        w.setCastle(Castle.from(project: "Demo", paths: paths + ["web/js/new.js"]))
        #expect(w.castles["Demo"]?.towers[i].edits == 1)
        // Session over: no castle.
        w.bonsaiEnd(project: "Demo")
        #expect(w.castlePlacements.isEmpty && !w.surfaces.contains { World.isCastleOwner($0.ownerID) })
    }
}
