import Foundation
import Testing
@testable import GremletsCore

/// The Back Office's roof as a place to stand (OfficeRoof.swift).
@Suite struct OfficeRoofTests {
    @Test func theRoofIsASurfaceAndRidersMoveWithIt() {
        let w = World(seed: 3)
        w.setEnvironment(screens: [Rect(x: 0, y: 0, w: 1400, h: 900)], windowsFrontToBack: [])
        let roof = Surface(ownerID: World.officeRoofOwner, kind: .plant, y: 110, minX: 1100, maxX: 1300)
        w.setOfficeRoofs([roof])
        #expect(w.surfaces.contains(roof))
        let c = w.spawn(testSpecies(scale: 10), at: Vec2(1200, 110))
        c.groundOwner = World.officeRoofOwner; c.set(.idle, duration: 5)
        #expect(w.onOffice.map { $0.id } == [c.id])
        // The hover zoom grows it: the rider stays at the same place along the roof, at the new height.
        w.setOfficeRoofs([Surface(ownerID: World.officeRoofOwner, kind: .plant, y: 140, minX: 1050, maxX: 1310)])
        #expect(c.pos.y == 140 && abs(c.pos.x - 1180) < 0.01)
        w.setOfficeRoofs([])
        #expect(!w.surfaces.contains { $0.ownerID == World.officeRoofOwner })
    }
}
