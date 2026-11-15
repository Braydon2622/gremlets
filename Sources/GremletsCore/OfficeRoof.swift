import Foundation

/// The Back Office building as somewhere to be: its mossy roof (and the notice board's little roof) are surfaces the
/// Gremlets can jump up onto, wander, sit on to watch the racetrack, and cheer from when good news comes in.
extension World {
    public static let officeRoofOwner = -490_001, officeBoardOwner = -490_002

    /// The app tells the world where the roofs are (global, y-up). When the building grows or shrinks (the hover
    /// zoom), whoever's standing on a roof moves with it.
    public func setOfficeRoofs(_ roofs: [Surface]) {
        let old = Dictionary(uniqueKeysWithValues: officeRoofs.map { ($0.ownerID, $0) })
        for r in roofs {
            guard let o = old[r.ownerID], o != r else { continue }
            for c in creatures where c.isGrounded && c.groundOwner == r.ownerID {
                // Keep each rider at the same place along the roof.
                let u = o.width > 0 ? (c.pos.x - o.minX) / o.width : 0.5
                c.pos = Vec2(r.minX + u * r.width, r.y)
            }
        }
        officeRoofs = roofs
        setSurfacesDirty()
    }

    /// Who's up on the office right now.
    public var onOffice: [Creature] {
        creatures.filter { $0.isGrounded && ($0.groundOwner == World.officeRoofOwner || $0.groundOwner == World.officeBoardOwner) }
    }

    /// Good news in the office: everyone on the roof cheers (a little dance), the rest who are close look over.
    public func officeCheer() {
        for c in onOffice where !c.isAsleep && c.job == nil && !c.onMail { c.set(.dance, duration: 1.6) }
    }

    /// On the roof: mostly sitting and watching (the track, the pigeons), now and then a stroll or a hop down.
    func officeRoofChoices(_ c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard let s = supportingSurface(for: c), s.ownerID == World.officeRoofOwner || s.ownerID == World.officeBoardOwner else { return }
        add("watchTheTrack", 2.4) {
            c.idleVariant = self.rng.chance(0.6) ? "look" : "idle"
            c.facing = self.rng.chance(0.5) ? 1 : -1
            c.set(.idle, duration: self.rng.range(3, 7))
        }
        add("roofStroll", 0.9) {
            c.facing = self.rng.chance(0.5) ? 1 : -1
            c.set(.walk, duration: self.rng.range(1, 2.5))
        }
        add("roofNap", 0.5) { c.set(.yawn, duration: c.animationLength(for: .yawn)) }
    }

    /// From anywhere (a window, a corner): float over to the office roof on a leaf. Nil if nobody can.
    @discardableResult
    public func floatToOffice(_ who: Creature? = nil) -> Int? {
        guard let roof = officeRoofs.first(where: { $0.ownerID == World.officeRoofOwner }) else { return nil }
        guard let c = who ?? creatures.filter({ isFree($0) && $0.isGrounded && !$0.onMail && $0.groundOwner != World.officeRoofOwner })
            .min(by: { abs($0.pos.x - roof.center) < abs($1.pos.x - roof.center) }) else { return nil }
        let t = Vec2(rng.range(roof.minX + 20, roof.maxX - 20), roof.y)
        startFloat(c, to: t, ride: .leaf)
        return c.id
    }

    /// Now and then someone who isn't on the floor drifts over to the office (if nobody's up there yet).
    func officeFloatChoice(_ c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !officeRoofs.isEmpty, onOffice.isEmpty, c.groundOwner != World.officeRoofOwner, c.groundOwner != World.officeBoardOwner,
              let s = supportingSurface(for: c), s.kind != .floor else { return }
        add("floatToOffice", 0.12) { _ = self.floatToOffice(c) }
    }

    /// On the floor near the building: now and then, up onto the roof.
    func officeVisit(_ c: Creature) -> Vec2? {
        guard let roof = officeRoofs.first(where: { $0.ownerID == World.officeRoofOwner }), c.isGrounded,
              let s = supportingSurface(for: c), s.kind == .floor else { return nil }
        let dh = roof.y - c.pos.y
        guard dh > 20, dh < maxJumpHeight * c.species.jumpPower * 1.1, abs(c.pos.x - roof.center) < 420 else { return nil }
        let tx = c.pos.x.clamped(roof.minX + 14, roof.maxX - 14)
        guard abs(tx - c.pos.x) < maxJumpDistance else { return nil }
        return ballistic(from: c.pos, toX: tx, y: roof.y)
    }
}

extension Surface {
    var center: Double { (minX + maxX) / 2 }
}
