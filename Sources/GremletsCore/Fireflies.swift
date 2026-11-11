import Foundation

/// After dark, fireflies come out of the thick moss on window tops and drift about just above it, blinking. Now and
/// then a Gremlet chases one along the window top, jumps for it, and sometimes catches it, holds it a moment and lets
/// it go. They keep low over the moss (never out over the middle of a window) and fade away at dawn.
public struct Firefly: Equatable, Sendable {
    public let id: Int
    public let windowID: Int
    /// Where it lives, from the window's left edge (it drifts around here).
    let homeOffset: Double
    /// Its position relative to the window's top-left corner (x from the left edge, y above the top).
    var local: Vec2
    var vel: Vec2
    /// Its own blink rhythm.
    public let phase: Double
    /// Let go after being caught: it rises and goes.
    var leaving = false
    var age = 0.0
}

extension World {
    public static let fireflyLimit = 6

    /// Where it is now (global points), riding along with its window.
    public func position(of f: Firefly) -> Vec2? {
        guard let w = windows[f.windowID] else { return nil }
        return Vec2(w.minX + f.local.x, w.maxY + f.local.y)
    }

    func updateFireflies(_ dt: Double) {
        fireflies.removeAll { windows[$0.windowID] == nil || ($0.leaving && $0.local.y > 220) }
        if compact { return }
        // Dawn (or the moss thinning out): they drift off one by one.
        let wanted = (isNight && mossMinutes >= 40) || clock < fireflyPreviewUntil ? min(World.fireflyLimit, 1 + mossPatches.count + Int(mossMinutes / 80)) : 0
        if fireflies.count > wanted, let i = fireflies.indices.randomElement(using: &rng), rng.chance(dt * 0.2) { fireflies[i].leaving = true }
        if fireflies.filter({ !$0.leaving }).count < wanted, clock >= nextFireflyAt {
            nextFireflyAt = clock + rng.range(3, 8)
            spawnFirefly()
        }
        for i in fireflies.indices {
            var f = fireflies[i]
            f.age += dt
            guard let w = windows[f.windowID] else { continue }
            if f.leaving {
                f.vel = f.vel * (1 - min(1, dt * 2)) + Vec2(rng.range(-20, 20), 40) * min(1, dt * 2)
            } else {
                // Wander, pulled gently home: a little above the moss near where it came out.
                let home = Vec2(f.homeOffset, 46)
                var acc = Vec2(rng.range(-60, 60), rng.range(-40, 40)) + (home - f.local) * 0.35
                // Shy of a Gremlet chasing it: it darts away and up.
                for c in creatures where c.mossTask?.firefly == f.id {
                    let me = Vec2(w.minX + f.local.x, w.maxY + f.local.y)
                    let d = me - (c.pos + Vec2(0, c.size.y * 0.7))
                    if d.length < 70 { acc = acc + Vec2(d.x >= 0 ? 260 : -260, 140) }
                }
                f.vel = f.vel + acc * dt
                f.vel = f.vel * (1 - min(1, dt * 1.2))
                let speed = f.vel.length
                if speed > 70 { f.vel = f.vel * (70 / speed) }
            }
            f.local = f.local + f.vel * dt
            if !f.leaving {
                // Low over the moss and over its own window top.
                f.local.x = f.local.x.clamped(14, w.w - 14)
                f.local.y = f.local.y.clamped(14, 110)
            }
            fireflies[i] = f
        }
    }

    @discardableResult
    func spawnFirefly() -> Bool {
        // Out of the moss the Gremlets planted, or anywhere along a mossy window top.
        var spot: (Int, Double)?
        if let p = mossPatches.filter({ windows[$0.windowID] != nil }).randomElement(using: &rng) {
            spot = (p.windowID, p.offset + rng.range(-p.width / 2, p.width / 2))
        } else if let t = builtSurfaces.filter({ $0.kind == .windowTop && $0.ownerID >= 0 && $0.width >= 100 }).randomElement(using: &rng),
                  let w = windows[t.ownerID] {
            spot = (t.ownerID, rng.range(t.minX + 20, t.maxX - 20) - w.minX)
        }
        guard let (wid, off) = spot, let w = windows[wid] else { return false }
        let x = off.clamped(20, w.w - 20)
        nextFireflyID += 1
        fireflies.append(Firefly(id: nextFireflyID, windowID: wid, homeOffset: x, local: Vec2(x, 6), vel: Vec2(0, 30), phase: rng.range(0, 6.28)))
        return true
    }

    // MARK: Chasing them

    func fireflyChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !fireflies.isEmpty, !compact, isFree(c), c.isGrounded, c.mossTask == nil, !c.isAsleep,
              let s = supportingSurface(for: c), s.kind == .windowTop else { return }
        for f in fireflies where f.windowID == s.ownerID && !f.leaving && !creatures.contains(where: { $0.mossTask?.firefly == f.id }) {
            guard let p = position(of: f), s.supports(x: p.x), abs(p.x - c.pos.x) < 500 else { continue }
            add("chaseFirefly", 1.4) {
                self.endSocial(c)
                c.mossTask = MossTask(kind: .firefly(f.id), started: self.clock)
                c.targetX = p.x.clamped(s.minX + 8, s.maxX - 8)
                c.facing = p.x > c.pos.x ? 1 : -1
                c.set(.walk, duration: 10)
            }
        }
    }

    /// Run under it, jump for it; after a few tries (or a catch) it's done.
    func fireflyDecide(_ c: Creature, _ t: inout MossTask, id: Int, on s: Surface) {
        guard let i = fireflies.firstIndex(where: { $0.id == id }), let p = position(of: fireflies[i]), !fireflies[i].leaving,
              clock - t.started < 16 else {
            c.mossTask = nil
            c.idleVariant = "look"; c.set(.idle, duration: 1)
            return
        }
        if t.acting {
            // Just landed from a jump at it.
            t.acting = false
            let close = (p - (c.pos + Vec2(0, c.size.y))).length < 60
            if close && rng.chance(0.6) {
                c.mossTask = nil
                if jarFirefly(from: c.pos) {
                    // Into the jar on the porch with it.
                    fireflies.remove(at: i)
                    sproutEvents.append(.caughtFirefly(c.pos + Vec2(0, c.size.y), by: c.id))
                    c.set(.react, duration: c.animationLength(for: .react) + 0.6)
                    return
                }
                fireflies[i].leaving = true
                fireflies[i].local.y = max(fireflies[i].local.y, c.size.y + 6)
                fireflies[i].local.x = c.pos.x - (windows[s.ownerID]?.minX ?? 0)
                fireflies[i].vel = Vec2(0, 20)
                sproutEvents.append(.caughtFirefly(c.pos + Vec2(0, c.size.y), by: c.id))
                c.set(.react, duration: c.animationLength(for: .react) + 0.6)
                return
            }
            c.mossTask = t
            sproutEvents.append(.missedFirefly(by: c.id))
        }
        let dx = p.x - c.pos.x
        if abs(dx) > 16 {
            c.targetX = p.x.clamped(s.minX + 8, s.maxX - 8)
            c.facing = dx > 0 ? 1 : -1
            if abs(c.targetX! - c.pos.x) < 6 { c.idleVariant = "look"; c.set(.idle, duration: 0.6); return }
            c.set(.walk, duration: 6)
            return
        }
        // Underneath it: jump!
        t.acting = true
        c.mossTask = t
        c.facing = dx >= 0 ? 1 : -1
        let reach = (p.y - c.pos.y - c.size.y * 0.6).clamped(30, 120)
        launch(c, velocity: Vec2(dx * 1.5, (2 * gravity * reach).squareRoot()))
    }

    /// `gremlet fireflies`: a few come out now (night or not), to try them out.
    @discardableResult
    public func firefliesNow() -> Bool {
        var any = false
        fireflyPreviewUntil = clock + 120
        for _ in 0..<3 { if spawnFirefly() { any = true } }
        if any { nextMossTaskAt = min(nextMossTaskAt, clock) }
        return any
    }
}

extension MossTask {
    var firefly: Int? { if case .firefly(let id) = kind { return id }; return nil }
}
