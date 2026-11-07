import Foundation

/// Full screen (a browser or any app filling the whole screen): the corner plant and everything else is put away,
/// the hanging house hangs in the top-right corner and a mossy branch grows from the top-left, and the Gremlets float
/// up to them on dandelions and spend the time there: napping, swinging, going inside, hopping between perches.
/// No kites, ferries, expeditions or shelves; jobs pause.
extension World {
    public static let cornerZone = 180.0

    /// Puts away whatever was going on in the middle of the screen.
    func enterCompact() {
        if kite != nil { endKite() }
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
            c.driftDown = false
            if World.isNotchOwner(c.groundOwner) {
                // On the porch, swing or hammock as the house moves to the corner: float over to it.
                c.groundOwner = nil
                Brain.decideCompact(c, in: self)
            } else if c.isGrounded && !c.isAsleep {
                // Off up to the corners in a little while (one after another).
                c.set(.idle, duration: rng.range(0.3, 3))
            }
        }
        compactTiers = 1
        compactOverflowUntil = 0
        updateCompactRoom()
        setSurfacesDirty()
    }

    /// Out of full screen: everyone up in the corners drifts back down under a leaf.
    func leaveCompact() {
        guard let scr = screens.first else { return }
        for c in creatures where World.isNotchOwner(c.groundOwner) || (c.activity == .float && c.floatTarget != nil) {
            if c.homeUntil != nil { continue }   // still asleep inside: it'll come out on the porch
            c.driftDown = false
            startFloat(c, to: Vec2((c.pos.x + rng.range(-80, 80)).clamped(scr.minX + 40, scr.maxX - 40), scr.minY), ride: .leaf)
        }
    }

    /// Full screen: they're shy of the pointer. Bring it near one up in a corner and it skitters off (to another perch
    /// on that side, the far end of its own, or down out of the way), so they never sit on a button you're reaching for.
    func shyFromCursor() {
        guard let cur = cursor else { return }
        let perches = compactPerches
        for (id, _) in dropTarget where creature(id: id).map({ $0.activity != .airborne && $0.activity != .crouch }) ?? true { dropTarget[id] = nil }
        for c in creatures where c.activity != .dragged && c.homeUntil == nil && dropTarget[c.id] == nil {
            let center = Vec2(c.pos.x, c.pos.y + c.size.y / 2)
            guard abs(cur.x - center.x) < 34 + c.size.x / 2, abs(cur.y - center.y) < 30 + c.size.y / 2 else { continue }
            if let t = spookedAt[c.id], clock - t < 0.7 { continue }
            if c.activity == .float, let t = c.floatTarget, abs(t.x - cur.x) < 90, abs(t.y - cur.y) < 90 {
                // On its way to right where the pointer is: pick somewhere else.
                spookedAt[c.id] = clock
                if let p = perches.filter({ abs(($0.minX + $0.maxX) / 2 - cur.x) > 120 || abs($0.y - cur.y) > 90 })
                    .min(by: { abs(($0.minX + $0.maxX) / 2 - c.pos.x) < abs(($1.minX + $1.maxX) / 2 - c.pos.x) }) {
                    c.floatTarget = Vec2((p.minX + p.maxX) / 2, p.y)
                }
                continue
            }
            guard c.isGrounded, let here = perches.first(where: { $0.ownerID == c.groundOwner }) else { continue }
            spookedAt[c.id] = clock
            endSocial(c)
            c.targetX = nil
            emit(.alert(c.id))
            // The spot on a perch farthest from the pointer.
            func far(_ p: Surface) -> Double { abs(p.minX + 10 - cur.x) > abs(p.maxX - 10 - cur.x) ? p.minX + 10 : p.maxX - 10 }
            func clear(_ p: Surface) -> Bool { abs(far(p) - cur.x) > 80 || abs(p.y - cur.y) > 70 }
            if let p = perches.filter({ $0.ownerID != here.ownerID && clear($0) && abs(far($0) - c.pos.x) < 380 && abs($0.y - c.pos.y) < 170 })
                .min(by: { abs(far($0) - c.pos.x) < abs(far($1) - c.pos.x) }) {
                launch(c, velocity: ballistic(from: c.pos, toX: far(p), y: p.y, apexExtra: 22))
            } else if abs(far(here) - cur.x) > 60 {
                launch(c, velocity: ballistic(from: c.pos, toX: far(here), y: here.y, apexExtra: 14))
            } else {
                // Nowhere up top to go: the stump in the bottom corner on its side comes out, and it hops down to it.
                compactOverflowUntil = clock + 120
                setSurfacesDirty()
                if let stump = cornerStumps.min(by: { abs(($0.minX + $0.maxX) / 2 - c.pos.x) < abs(($1.minX + $1.maxX) / 2 - c.pos.x) }) {
                    // Off the perch and straight down the side of the screen onto the stump.
                    launch(c, velocity: ballistic(from: c.pos, toX: (stump.minX + stump.maxX) / 2, y: stump.y, apexExtra: 12))
                    dropTarget[c.id] = stump.ownerID
                } else {
                    let away: Double = c.pos.x < cur.x ? -1 : 1
                    launch(c, velocity: Vec2(away * 160, 220))
                }
            }
            c.facing = cur.x > c.pos.x ? -1 : 1
        }
    }

    /// The places they hang out in full screen: the porch, hammock and swing, and the top-left branch.
    var compactPerches: [Surface] { notchSurfaces }

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
    /// Full screen: up to the top corners, then small things on the perches there.
    static func decideCompact(_ c: Creature, in world: World) {
        var choices: [Choice] = []
        func add(_ name: String, _ w: Double, _ f: @escaping () -> Void) { if w > 0 { choices.append(Choice(name: name, weight: w, start: f)) } }
        let perches = world.compactPerches
        guard !perches.isEmpty else { c.idleVariant = "look"; c.set(.idle, duration: 3); return }
        if c.isAsleep { c.set(.sleep, duration: world.rng.range(20, 60)); return }
        guard let here = perches.first(where: { $0.ownerID == c.groundOwner }) else {
            // Float up to the least crowded perch (counting those already on their way to it).
            // How full a perch is, for its size (a Gremlet needs about 34 points).
            func crowd(_ p: Surface) -> Double {
                let n = world.creatures.filter { o in o !== c && (o.groundOwner == p.ownerID || (o.floatTarget.map { abs($0.y - p.y) < 4 && p.supports(x: $0.x) } ?? false)) }.count
                return Double(n) / max(1, p.width / 34)
            }
            // ...and keeping away from wherever the pointer is.
            func shy(_ p: Surface) -> Double {
                guard let cur = world.cursor, cur.x > p.minX - 60, cur.x < p.maxX + 60, abs(cur.y - p.y) < 90 else { return 0 }
                return 5
            }
            let p = perches.min { crowd($0) + shy($0) < crowd($1) + shy($1) }!
            let x = (p.minX + p.width * world.rng.range(0.2, 0.8))
            world.startFloat(c, to: Vec2(x, p.y), ride: .dandelion)
            return
        }
        add("idle", 2.0) { c.idleVariant = world.rng.chance(0.5) ? "look" : "idle"; c.set(.idle, duration: world.rng.range(4, 10)) }
        add("potter", 0.6) {
            c.targetX = world.rng.range(here.minX + 8, here.maxX - 8)
            c.facing = c.targetX! > c.pos.x ? 1 : -1
            c.set(.walk, duration: 5)
        }
        if here.ownerID == World.notchHammockOwner || c.energy < 0.6 { add("nap", here.ownerID == World.notchHammockOwner ? 2.5 : 1.5) { c.set(.yawn, duration: c.animationLength(for: .yawn)) } }
        if here.ownerID == World.notchPorchOwner, world.insideHangingHome.count < 2 { add("goInside", 0.7) { world.goInsideHangingHome(c) } }
        if here.ownerID == World.notchSwingOwner { add("swing", 1.5) { c.set(.special, duration: c.animationLength(for: .special)) } }
        add("special", 0.25) { world.startSpecial(c) }
        // Hop over to a nearby perch (the swing, the hammock, the porch).
        for p in perches where p.ownerID != here.ownerID {
            let mid = (p.minX + p.maxX) / 2
            let there = world.creatures.filter { $0.groundOwner == p.ownerID || ($0.floatTarget.map { abs($0.y - p.y) < 4 && p.supports(x: $0.x) } ?? false) }.count
            if abs(mid - c.pos.x) < 170 && abs(p.y - c.pos.y) < 90 && Double(there + 1) <= max(1, p.width / 34) {
                add("hop", 0.5) { world.launch(c, velocity: world.ballistic(from: c.pos, toX: mid, y: p.y, apexExtra: 26)) }
            }
        }
        if let cur = world.cursor, abs(cur.x - c.pos.x) < 220, abs(cur.y - c.pos.y) < 200, (cur - c.pos).length > 110 {
            add("wave", 1.2) { c.facing = cur.x > c.pos.x ? 1 : -1; c.set(.wave, duration: 1.3) }
        }
        let friends = world.nearbyFriends(of: c, range: 120)
        if c.energy < 0.75, let sleeper = friends.first(where: { $0.activity == .sleep }) {
            add("napTogether", 1.2) { world.startNap(c, sleeper) }
        }
        pickAndStart(choices, world)
    }
}
