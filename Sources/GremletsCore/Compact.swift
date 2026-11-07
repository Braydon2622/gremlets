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

    /// How close the pointer gets before a Gremlet in full screen gets out of the way, and how far clear of it the
    /// spot it goes to must be (so the button under it is free to click).
    static let shyReach = 48.0, shyClear = 140.0

    /// Full screen: they're shy of the pointer. Bring it near one up in a corner and it leaps off at once (no wind-up)
    /// to a spot well clear of the pointer: another perch, or, with nowhere up top, the stump in the bottom corner on its
    /// side. Gremlets on their way to somewhere near the pointer turn aside.
    func shyFromCursor() {
        guard let cur = cursor else { return }
        for (id, _) in dropTarget where creature(id: id).map({ $0.activity != .airborne }) ?? true { dropTarget[id] = nil }
        // (Out of full screen, only up in the top corners and at the hanging house, where they'd sit over buttons.)
        for c in creatures where c.activity != .dragged && c.homeUntil == nil && dropTarget[c.id] == nil
            && (compact || World.isNotchOwner(c.groundOwner) || (c.activity == .float && c.floatTarget.map { t in compactPerches.contains { abs($0.y - t.y) < 4 } } ?? false)) {
            if c.activity == .float, let t = c.floatTarget, (t + Vec2(0, c.size.y / 2) - cur).length < World.shyClear {
                if let (p, x) = shySpot(for: c, from: cur) { c.floatTarget = Vec2(x, p.y) }
                continue
            }
            let b = c.bounds
            let dx = max(b.minX - cur.x, 0, cur.x - b.maxX), dy = max(b.minY - cur.y, 0, cur.y - b.maxY)
            guard (dx * dx + dy * dy).squareRoot() < World.shyReach, c.isGrounded else { continue }
            if let t = spookedAt[c.id], clock - t < 0.25 { continue }
            spookedAt[c.id] = clock
            endSocial(c)
            c.targetX = nil
            emit(.alert(c.id))
            if let (p, x) = shySpot(for: c, from: cur) {
                leap(c, toX: x, y: p.y, landingOn: p.ownerID)
            } else {
                // Nowhere up top is clear: the stumps come out and it drops straight down the side of the screen.
                compactOverflowUntil = clock + 120
                setSurfacesDirty()
                if let stump = cornerStumps.min(by: { abs(($0.minX + $0.maxX) / 2 - c.pos.x) < abs(($1.minX + $1.maxX) / 2 - c.pos.x) }) {
                    leap(c, toX: (stump.minX + stump.maxX) / 2, y: stump.y, landingOn: stump.ownerID)
                } else {
                    c.groundOwner = nil; c.vel = Vec2((c.pos.x < cur.x ? -1 : 1) * 200, 200); c.pos.y += 1; c.set(.airborne)
                }
            }
        }
    }

    /// The nearest spot on a perch with room, on the same side of the screen, well clear of the pointer.
    func shySpot(for c: Creature, from cur: Vec2) -> (Surface, Double)? {
        var best: (Surface, Double, Double)?
        for p in compactPerches {
            let others = creatures.filter { $0 !== c && ($0.groundOwner == p.ownerID || ($0.floatTarget.map { abs($0.y - p.y) < 4 && p.supports(x: $0.x) } ?? false)) }
            guard Double(others.count + 1) <= max(1, p.width / 34) + 1 else { continue }
            for x in stride(from: p.minX + 12, through: max(p.minX + 12, p.maxX - 12), by: 10) {
                // Same side of the screen (no leaping across the middle of it).
                guard abs(x - c.pos.x) < 420, (Vec2(x, p.y + c.size.y / 2) - cur).length >= World.shyClear,
                      !others.contains(where: { abs($0.pos.x - x) < 22 && abs($0.pos.y - p.y) < 6 }) else { continue }
                let d = (Vec2(x, p.y) - c.pos).length
                if best == nil || d < best!.2 { best = (p, x, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Straight off (no crouch first), landing only on that perch: it passes through anything else on the way.
    func leap(_ c: Creature, toX x: Double, y: Double, landingOn owner: Int) {
        let v = ballistic(from: c.pos, toX: x, y: y, apexExtra: y > c.pos.y ? 14 : 8)
        c.groundOwner = nil
        c.vel = v
        c.pos.y += 1
        c.facing = v.x >= 0 ? 1 : -1
        c.set(.airborne)
        dropTarget[c.id] = owner
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
                guard let cur = world.cursor else { return 0 }
                let near = Vec2(cur.x.clamped(p.minX, p.maxX), p.y + 20)
                return (near - cur).length < World.shyClear ? 5 : 0
            }
            let p = perches.min { crowd($0) + shy($0) < crowd($1) + shy($1) }!
            let x = (p.minX + p.width * world.rng.range(0.2, 0.8))
            world.startFloat(c, to: Vec2(x, p.y), ride: .dandelion)
            return
        }
        add("idle", 2.0) { c.idleVariant = world.rng.chance(0.5) ? "look" : "idle"; c.set(.idle, duration: world.rng.range(4, 10)) }
        add("potter", 0.6) {
            c.targetX = world.rng.range(here.minX + 8, here.maxX - 8)
            // Not over toward the pointer.
            if let cur = world.cursor, (Vec2(c.targetX!, here.y + 20) - cur).length < World.shyClear { c.targetX = c.pos.x }
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
            let pointerNear = world.cursor.map { (Vec2($0.x.clamped(p.minX, p.maxX), p.y + 20) - $0).length < World.shyClear } ?? false
            if abs(mid - c.pos.x) < 170 && abs(p.y - c.pos.y) < 90 && Double(there + 1) <= max(1, p.width / 34) && !pointerNear {
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
