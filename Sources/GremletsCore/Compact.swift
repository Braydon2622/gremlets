import Foundation

/// Full screen (a browser or any app filling the whole screen): the Gremlets keep to the two bottom corners and
/// everything else is put away until you leave full screen. No kites, ferries, expeditions, shelves or village
/// visitors; jobs pause (the Claude helper waits in a corner); flying ones come down.
extension World {
    public static let cornerZone = 180.0

    /// Puts away whatever was going on in the middle of the screen.
    func enterCompact() {
        kite = nil
        merchant = nil
        if let fe = ferry {
            for c in creatures where c.groundOwner == World.ferryOwner { c.groundOwner = nil; c.set(.airborne) }
            _ = fe; ferry = nil
        }
        for c in creatures {
            if c.job?.isHobby == true { endJob(c.id) }
            if c.expedition != nil { giveUp(c) }
            if c.boost != nil || c.helping != nil { cancelBoost(c) }
            if c.stair != nil { abandonStairs(c) }
            c.mossTask = nil; c.snowmanTask = nil; c.groveTask = nil; c.targetX = nil
            if c.climb != nil { c.climb = nil; if c.activity == .float { c.set(.airborne) } }
            if c.activity == .fly || c.activity == .float { c.set(.airborne) }
            endSocial(c)
        }
        setSurfacesDirty()
    }

    /// The bottom corner a Gremlet belongs to (the nearer one), as an x range on its screen's floor.
    func corner(for c: Creature) -> (lo: Double, hi: Double, floorY: Double)? {
        guard let scr = screen(containingX: c.pos.x, y: c.pos.y) ?? screens.first else { return nil }
        let left = c.pos.x - scr.minX < scr.maxX - c.pos.x
        return left ? (scr.minX + 14, scr.minX + World.cornerZone, scr.minY) : (scr.maxX - World.cornerZone, scr.maxX - 14, scr.minY)
    }

    public func inCorner(_ c: Creature) -> Bool {
        guard let k = corner(for: c) else { return true }
        return c.pos.x >= k.lo - 2 && c.pos.x <= k.hi + 2
    }
}

extension Brain {
    /// Full screen: head for the nearest bottom corner, then keep to small, quiet things there.
    static func decideCompact(_ c: Creature, in world: World) {
        var choices: [Choice] = []
        func add(_ name: String, _ w: Double, _ f: @escaping () -> Void) { if w > 0 { choices.append(Choice(name: name, weight: w, start: f)) } }
        guard let k = world.corner(for: c) else { c.set(.idle, duration: 2); return }
        if c.isAsleep { c.set(.sleep, duration: world.rng.range(20, 60)); return }
        if !world.inCorner(c) {
            // Off to the corner (from wherever it was when the app went full screen).
            c.targetX = c.pos.x < k.lo ? k.lo + 20 : k.hi - 20
            c.facing = c.targetX! > c.pos.x ? 1 : -1
            c.set(.walk, duration: 40)
            return
        }
        c.targetX = nil
        add("idle", 2.0) { c.idleVariant = world.rng.chance(0.4) ? "look" : "idle"; c.set(.idle, duration: world.rng.range(3, 9)) }
        add("potter", 0.9) {
            c.targetX = world.rng.range(k.lo + 10, k.hi - 10)
            c.facing = c.targetX! > c.pos.x ? 1 : -1
            c.set(.walk, duration: 8)
        }
        if c.energy < 0.6 { add("sleep", 2.0) { c.set(.yawn, duration: c.animationLength(for: .yawn)) } }
        add("special", 0.25) { world.startSpecial(c) }
        if let cur = world.cursor, abs(cur.x - c.pos.x) < 220, abs(cur.y - c.pos.y) < 200 {
            add("wave", 1.2) { c.facing = cur.x > c.pos.x ? 1 : -1; c.set(.wave, duration: 1.3) }
        }
        // The corner plant is in the bottom-left corner.
        world.groveChoices(for: c) { name, w, f in if name != "goHome" && name != "dig" { add(name, w, f) } }
        let friends = world.nearbyFriends(of: c, range: World.cornerZone)
        if c.energy < 0.75, let sleeper = friends.first(where: { $0.activity == .sleep }) {
            add("napTogether", 1.2) { world.startNap(c, sleeper) }
        }
        pickAndStart(choices, world)
    }
}
