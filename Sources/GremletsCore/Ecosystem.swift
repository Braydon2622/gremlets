import Foundation

/// The desktop as a little living ecosystem, busy whether or not Claude is working:
///
/// - **The Dock.** Its icons are a row of stepping stones along the bottom of the screen. Gremlets hop across them,
///   cheer when you open an app (a Gremlet standing on a bouncing icon gets bounced sky-high), knock on an icon that
///   just got a badge, wave an app goodbye when it quits, and curl up for a nap on the Trash.
/// - **Critters** live in the moss: ladybugs and tiny snails crawl along mossy window tops and widgets, bees drift
///   between them in the daytime. Gremlets crouch to say hello; a ladybug climbs onto a hand for a moment, then flies.
/// - **Widgets** are windows too (the app marks them): moss creeps over them and Gremlets set off to plant it there.
public struct DockIcon: Equatable, Sendable {
    public let app: String
    public let minX: Double, maxX: Double
    /// The top of the icon (global y-up).
    public let top: Double
    public var badge: String?
    public var running: Bool
    public let isTrash: Bool
    public var midX: Double { (minX + maxX) / 2 }
    public init(app: String, minX: Double, maxX: Double, top: Double, badge: String? = nil, running: Bool = false, isTrash: Bool = false) {
        self.app = app; self.minX = minX; self.maxX = maxX; self.top = top; self.badge = badge; self.running = running; self.isTrash = isTrash
    }
}

public enum DockWhy: Equatable, Sendable { case hop(Int), cheer, mail, nap }

public struct Critter: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable { case ladybug, bee, snail }
    public let id: Int
    public let kind: Kind
    /// The window (or widget) it lives on.
    public internal(set) var windowID: Int
    /// From the window's top-left corner: x from its left edge, y above its top.
    var local: Vec2
    var vel: Vec2 = .zero
    public internal(set) var facing: Double = 1
    public let phase: Double
    var homeX: Double
    var pauseUntil = 0.0
    public internal(set) var leaving = false
    var age = 0.0
    /// Sitting on a Gremlet's hand (its id), until a moment later.
    public internal(set) var onHand: Int?
    var handUntil = 0.0
    public var isMoving: Bool { vel.length > 2 }
}

public enum EcoEvent: Equatable, Sendable {
    case dockHop(Vec2, by: Int)
    case dockBounce(Vec2, by: Int, app: String)
    case dockCheer(by: Int, app: String)
    case dockMail(Vec2, by: Int, app: String, badge: String)
    case dockWave(by: Int, app: String)
    case dockNap(by: Int)
    /// Off through the moss tunnel to the linked screen: dived in here, popped out by the hollow log there.
    case tunnelDive(Vec2, by: Int)
    case tunnelPop(Vec2, by: Int)
    case critterHello(Vec2, by: Int, kind: Critter.Kind)
    case critterFlew(Vec2)
}

extension World {
    public static let critterLimit = 6

    public func drainEcoEvents() -> [EcoEvent] { defer { ecoEvents = [] }; return ecoEvents }

    /// Where a critter is now (global points), riding along with its window, or on the Gremlet holding it.
    public func position(of k: Critter) -> Vec2? {
        if let h = k.onHand, let c = creature(id: h) { return c.pos + Vec2(c.facing * c.size.x * 0.22, c.size.y * 0.5) }
        guard let w = windows[k.windowID] else { return nil }
        return Vec2(w.minX + k.local.x, w.maxY + k.local.y)
    }

    /// Whether the Dock's icons are out (not in full screen, and the app told us where they are).
    var dockOut: Bool { !compact && !dockIcons.isEmpty }

    func updateEcosystem(_ dt: Double) {
        if crittersOn || !critters.isEmpty { updateCritters(dt) }
        for (app, until) in dockBouncing where clock > until { dockBouncing[app] = nil }
        if crittersOn || !birds.isEmpty { updateBirds(dt) }
        updateHover()
        updateBarrel(dt)
        updatePatch(dt)
        updateMailHover()
        updateLanterns()
        updateSeasons(dt)
        updateJar()
        if basket != nil { updateBasket(dt) }
        if !(17...21).contains(localHour) { suppersTonight = 0 }
    }

    // MARK: Critters

    func updateCritters(_ dt: Double) {
        critters.removeAll { k in (k.onHand == nil && windows[k.windowID] == nil) || (k.leaving && k.local.y > 260) || (k.onHand != nil && creature(id: k.onHand!) == nil) }
        if compact { for i in critters.indices { critters[i].leaving = true; critters[i].onHand = nil } ; return }
        let day = !isNight
        let wanted = crittersOn && day && mossMinutes >= 14 && !mossThirsty ? min(World.critterLimit, 2 + Int(mossMinutes / 60) + (ownDay ? 1 : 0)) : 0
        if critters.filter({ !$0.leaving }).count > wanted, let i = critters.indices.randomElement(using: &rng), rng.chance(dt * 0.05) {
            critters[i].leaving = true; critters[i].onHand = nil
        }
        if critters.filter({ !$0.leaving }).count < wanted, clock >= nextCritterAt {
            nextCritterAt = clock + rng.range(ownDay ? 6 : 12, ownDay ? 18 : 35)
            spawnCritter()
        }
        for i in critters.indices {
            var k = critters[i]
            k.age += dt
            defer { critters[i] = k }
            if let h = k.onHand {
                if clock >= k.handUntil {
                    // Off it flies, from the hand it was sitting on.
                    if let c = creature(id: h), let w = windows[k.windowID] {
                        let p = c.pos + Vec2(c.facing * c.size.x * 0.22, c.size.y * 0.5)
                        k.local = Vec2(p.x - w.minX, p.y - w.maxY)
                        ecoEvents.append(.critterFlew(p))
                    }
                    k.onHand = nil; k.leaving = true; k.vel = Vec2(rng.range(-30, 30), 50)
                }
                continue
            }
            guard let w = windows[k.windowID] else { continue }
            if k.leaving {
                k.vel = k.vel * (1 - min(1, dt * 1.5)) + Vec2(rng.range(-30, 30) + k.facing * 30, 70) * min(1, dt * 1.5)
                k.local = k.local + k.vel * dt
                continue
            }
            switch k.kind {
            case .ladybug, .snail:
                // Crawling along the top of the window, stopping now and then to look about.
                let speed = k.kind == .snail ? 4.5 : 16.0
                if clock < k.pauseUntil { k.vel = .zero; continue }
                if rng.chance(dt * (k.kind == .snail ? 0.08 : 0.35)) { k.pauseUntil = clock + rng.range(1.2, k.kind == .snail ? 7 : 3.5); continue }
                if rng.chance(dt * 0.12) { k.facing = -k.facing }
                // Drawn back towards home, so it doesn't wander off the moss.
                if abs(k.local.x - k.homeX) > 90 { k.facing = k.local.x < k.homeX ? 1 : -1 }
                var nx = k.local.x + k.facing * speed * dt
                let gx = w.minX + nx
                // Only on the visible stretch of its window's top (a window over it: turn round).
                if !surfaces.contains(where: { $0.ownerID == k.windowID && $0.kind == .windowTop && $0.supports(x: gx) }) || nx < 8 || nx > w.w - 8 {
                    k.facing = -k.facing; nx = k.local.x
                    if !surfaces.contains(where: { $0.ownerID == k.windowID && $0.kind == .windowTop && $0.supports(x: w.minX + nx) }) {
                        if k.kind == .ladybug { k.leaving = true; k.vel = Vec2(0, 40) } else { k.local.x = -9999 }   // a snail just vanishes into the moss
                        continue
                    }
                }
                k.vel = Vec2(k.facing * speed, 0)
                k.local = Vec2(nx, 0)
                // A ladybug sometimes opens its wings and flies off to somewhere new.
                if k.kind == .ladybug, k.age > 40, rng.chance(dt * 0.01) { k.leaving = true; k.vel = Vec2(k.facing * 20, 40) }
            case .bee:
                // Drifting low over the moss, visiting the sprouts and the flowers, bobbing.
                var target = Vec2(k.homeX, 30 + sin(clock * 0.7 + k.phase) * 12)
                if let sp = sprouts.first(where: { $0.windowID == k.windowID }), let ww = windows[sp.windowID] {
                    _ = ww
                    if sin(clock * 0.21 + k.phase) > 0.3 { target = Vec2(sp.offset, 16) }
                }
                if rng.chance(dt * 0.15) { k.homeX = (k.homeX + rng.range(-120, 120)).clamped(16, max(17, w.w - 16)) }
                var acc = (target - k.local) * 0.9 + Vec2(rng.range(-80, 80), rng.range(-60, 60))
                for c in creatures where c.mossTask.map({ if case .critter(let id) = $0.kind { return id == k.id }; return false }) ?? false {
                    let d = Vec2(w.minX + k.local.x, w.maxY + k.local.y) - (c.pos + Vec2(0, c.size.y * 0.7))
                    if d.length < 50 { acc = acc + Vec2(0, 120) }
                }
                k.vel = (k.vel + acc * dt) * (1 - min(1, dt * 1.6))
                let sp = k.vel.length
                if sp > 60 { k.vel = k.vel * (60 / sp) }
                if abs(k.vel.x) > 4 { k.facing = k.vel.x > 0 ? 1 : -1 }
                k.local = k.local + k.vel * dt
                k.local.x = k.local.x.clamped(10, max(11, w.w - 10))
                k.local.y = k.local.y.clamped(8, 90)
                if k.age > 150, rng.chance(dt * 0.02) { k.leaving = true }
            }
        }
        critters.removeAll { $0.local.x < -9000 }
    }

    @discardableResult
    func spawnCritter(kind want: Critter.Kind? = nil) -> Bool {
        // Mossy window tops, widgets above all (they're little gardens of their own).
        let tops = surfaces.filter { $0.kind == .windowTop && $0.ownerID >= 0 && $0.width >= 70 }
        guard !tops.isEmpty else { return false }
        let weights = tops.map { t -> Double in
            (widgetIDs.contains(t.ownerID) ? 3.0 : 1.0) + Double(mossPatches.filter { $0.windowID == t.ownerID }.count) * 0.6
        }
        var roll = rng.range(0, weights.reduce(0, +))
        var pick = tops[0]
        for (t, wt) in zip(tops, weights) { roll -= wt; if roll <= 0 { pick = t; break } }
        guard let w = windows[pick.ownerID] else { return false }
        let kind: Critter.Kind = want ?? {
            let r = rng.range(0, 1)
            return r < 0.45 ? .ladybug : r < 0.8 ? .bee : .snail
        }()
        let x = rng.range(pick.minX + 10, max(pick.minX + 11, pick.maxX - 10)) - w.minX
        nextCritterID += 1
        var k = Critter(id: nextCritterID, kind: kind, windowID: pick.ownerID, local: Vec2(x, kind == .bee ? 60 : 0), phase: rng.range(0, 6.28), homeX: x)
        k.facing = rng.chance(0.5) ? 1 : -1
        if kind != .snail { k.local.y = kind == .bee ? 70 : 40; k.vel = Vec2(0, -30) }
        critters.append(k)
        // A ladybug lands from the air; snails come up out of the moss.
        if kind == .ladybug { critters[critters.count - 1].local.y = 0 }
        return true
    }

    /// `gremlet critters`: a few come out now, to try them out.
    @discardableResult
    public func crittersNow() -> Int {
        var n = 0
        for kind in Critter.Kind.allCases where spawnCritter(kind: kind) { n += 1 }
        return n
    }

    func critterDecide(_ c: Creature, _ t: inout MossTask, id: Int, on s: Surface) {
        guard let i = critters.firstIndex(where: { $0.id == id }), !critters[i].leaving, critters[i].onHand == nil,
              let p = position(of: critters[i]), clock - t.started < 25 else {
            c.mossTask = nil; c.idleVariant = "look"; c.set(.idle, duration: 0.8); return
        }
        let k = critters[i]
        let stand = p.x - (p.x > c.pos.x ? 18 : -18)
        if !t.acting {
            if abs(c.pos.x - stand) > 8, s.supports(x: stand) {
                c.targetX = stand; c.facing = stand > c.pos.x ? 1 : -1
                c.set(.walk, duration: 8); return
            }
            t.acting = true; c.mossTask = t
            c.facing = p.x >= c.pos.x ? 1 : -1
            if k.kind == .bee { c.set(.wave, duration: 1.8) }
            else { c.workPose = "crouch"; c.set(.work, duration: k.kind == .snail ? 2.6 : 1.6) }
            critters[i].pauseUntil = clock + 4
            return
        }
        c.mossTask = nil
        ecoEvents.append(.critterHello(p, by: c.id, kind: k.kind))
        if k.kind == .ladybug {
            // It climbs onto the offered hand, sits a moment, and flies off.
            critters[i].onHand = c.id
            critters[i].handUntil = clock + 3.2
            c.idleVariant = "look"; c.set(.idle, duration: 3.2)
        } else {
            c.set(.react, duration: c.animationLength(for: .react))
        }
    }

    // MARK: The Dock

    /// The main screen's floor (where the Dock's icons sit just below).
    private var dockFloor: Surface? { builtSurfaces.first { $0.kind == .floor && $0.ownerID == -1 } }

    private func onDockFloor(_ c: Creature) -> Bool {
        guard let f = dockFloor else { return false }
        return c.groundOwner == f.ownerID && abs(c.pos.y - f.y) < 3
    }

    func ecoChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard !compact, isFree(c), c.isGrounded, !c.isAsleep, let s = supportingSurface(for: c) else { return }
        // Say hello to a critter on the same window top.
        if s.kind == .windowTop {
            for k in critters where k.windowID == s.ownerID && !k.leaving && k.onHand == nil
                && !creatures.contains(where: { $0.mossTask.map { if case .critter(let id) = $0.kind { return id == k.id }; return false } ?? false }) {
                guard let p = position(of: k), s.supports(x: p.x), abs(p.x - c.pos.x) < 420 else { continue }
                add("meetCritter", ownDay ? 1.4 : 0.9) { self.startMossTask(c, .critter(k.id), walkTo: p.x) }
            }
        }
        // Hop along the Dock's icons like stepping stones, or curl up for a nap on the Trash.
        if dockOut, onDockFloor(c), let floor = dockFloor {
            let near = dockIcons.filter { abs($0.midX - c.pos.x) < 520 && floor.supports(x: $0.midX) }
            if clock >= nextDockPlayAt, let first = near.randomElement(using: &rng) {
                add("dockHop", ownDay ? 1.6 : 0.9) {
                    self.nextDockPlayAt = self.clock + self.rng.range(25, 70)
                    self.startMossTask(c, .dock(app: first.app, why: .hop(Int(self.rng.range(2, 6)))), walkTo: first.midX)
                }
            }
            if let trash = dockIcons.first(where: \.isTrash), floor.supports(x: trash.midX), c.energy < 0.5 || isNight,
               !creatures.contains(where: { $0 !== c && abs($0.pos.x - trash.midX) < 20 && $0.isAsleep }) {
                add("dockNap", 1.2) { self.startMossTask(c, .dock(app: trash.app, why: .nap), walkTo: trash.midX) }
            }
        }
    }

    func dockDecide(_ c: Creature, _ t: inout MossTask, app: String, why: DockWhy, on s: Surface) {
        guard dockOut, s.kind == .floor, let icon = dockIcons.first(where: { $0.app == app }), s.supports(x: icon.midX) else {
            c.mossTask = nil; c.set(.idle, duration: 0.4); return
        }
        let x = icon.midX
        if !t.acting {
            if abs(c.pos.x - x) > 10, clock - t.started < 35 {
                c.targetX = x; c.facing = x > c.pos.x ? 1 : -1
                c.set(.walk, duration: 14); return
            }
            if abs(c.pos.x - x) > 10 { c.mossTask = nil; c.set(.idle, duration: 0.4); return }
        }
        switch why {
        case .hop(let n):
            ecoEvents.append(.dockHop(Vec2(x, icon.top), by: c.id))
            // On to the next icon along, in the direction it's facing (turning round at the end of the Dock).
            let sorted = dockIcons.sorted { $0.midX < $1.midX }
            if n > 1, let idx = sorted.firstIndex(where: { $0.app == app }) {
                var j = idx + (c.facing >= 0 ? 1 : -1)
                if j < 0 || j >= sorted.count { j = idx + (c.facing >= 0 ? -1 : 1) }
                if j >= 0, j < sorted.count, s.supports(x: sorted[j].midX) {
                    let next = sorted[j]
                    c.facing = next.midX > c.pos.x ? 1 : -1
                    c.mossTask = MossTask(kind: .dock(app: next.app, why: .hop(n - 1)), started: t.started)
                    launch(c, velocity: ballistic(from: c.pos, toX: next.midX, y: s.y, apexExtra: 22 + rng.range(0, 14)))
                    return
                }
            }
            c.mossTask = nil
            launch(c, velocity: Vec2(0, (2 * gravity * 40).squareRoot()))
        case .cheer:
            c.mossTask = nil
            if (dockBouncing[app] ?? 0) > clock {
                ecoEvents.append(.dockBounce(Vec2(x, icon.top), by: c.id, app: app))
                launch(c, velocity: Vec2(rng.range(-40, 40), (2 * gravity * 150).squareRoot()))
            } else {
                ecoEvents.append(.dockCheer(by: c.id, app: app))
                c.set(.react, duration: c.animationLength(for: .react) + 0.3)
            }
        case .mail:
            if !t.acting {
                t.acting = true; c.mossTask = t
                c.workPose = "crouch"; c.set(.work, duration: 1.3)   // knock knock
                return
            }
            c.mossTask = nil
            ecoEvents.append(.dockMail(Vec2(x, icon.top), by: c.id, app: app, badge: icon.badge ?? ""))
            c.set(.wave, duration: 1.8)
        case .nap:
            c.mossTask = nil
            ecoEvents.append(.dockNap(by: c.id))
            c.set(.yawn, duration: c.animationLength(for: .yawn))
        }
    }

    /// Nearest Gremlet that can drop what it's doing and is down on the main screen's floor.
    private func dockRunner(near x: Double, within: Double = 900) -> Creature? {
        creatures.filter { canDropEverything($0) && onDockFloor($0) && abs($0.pos.x - x) < within && $0.mossTask == nil }
            .min { abs($0.pos.x - x) < abs($1.pos.x - x) }
    }

    /// You opened an app: its icon bounces, and anyone standing on it goes flying; otherwise someone runs over to cheer.
    public func dockAppOpened(_ app: String) {
        guard dockOut, let icon = dockIcons.first(where: { $0.app == app }) else { return }
        dockBouncing[app] = clock + 2.2
        let riders = creatures.filter { onDockFloor($0) && abs($0.pos.x - icon.midX) < max(18, (icon.maxX - icon.minX) / 2) && $0.activity != .dragged && $0.job == nil }
        for c in riders {
            endSocial(c); c.mossTask = nil
            ecoEvents.append(.dockBounce(Vec2(icon.midX, icon.top), by: c.id, app: app))
            launch(c, velocity: Vec2(rng.range(-60, 60), (2 * gravity * rng.range(130, 190)).squareRoot()))
        }
        if riders.isEmpty, rng.chance(0.6), let c = dockRunner(near: icon.midX, within: 600) {
            startMossTask(c, .dock(app: app, why: .cheer), walkTo: icon.midX)
        }
    }

    /// An app on the Dock got a badge (or more on it): someone goes and knocks on it.
    public func dockBadgeAppeared(_ app: String) {
        guard dockOut, let icon = dockIcons.first(where: { $0.app == app }), let c = dockRunner(near: icon.midX) else { return }
        startMossTask(c, .dock(app: app, why: .mail), walkTo: icon.midX)
    }

    /// An app quit: a Gremlet nearby waves it goodbye.
    public func dockAppQuit(_ app: String) {
        guard dockOut, let icon = dockIcons.first(where: { $0.app == app }),
              let c = dockRunner(near: icon.midX, within: 260) else { return }
        endSocial(c)
        c.facing = icon.midX > c.pos.x ? 1 : -1
        c.set(.wave, duration: 1.8)
        ecoEvents.append(.dockWave(by: c.id, app: app))
    }

    /// `gremlet dock`: someone hops along the Dock now.
    @discardableResult
    public func dockHopNow() -> Bool {
        guard dockOut, let floor = dockFloor else { return false }
        let pool = creatures.filter { canDropEverything($0) }
        guard let c = pool.first(where: { onDockFloor($0) }) ?? pool.first,
              let icon = dockIcons.filter({ floor.supports(x: $0.midX) }).min(by: { abs($0.midX - c.pos.x) < abs($1.midX - c.pos.x) }) else { return false }
        c.mossTask = nil; c.groveTask = nil
        if !onDockFloor(c) {
            startFloat(c, to: Vec2(icon.midX, floor.y), ride: .leaf)
            c.mossTask = MossTask(kind: .dock(app: icon.app, why: .hop(5)), started: clock)
            return true
        }
        startMossTask(c, .dock(app: icon.app, why: .hop(5)), walkTo: icon.midX)
        return true
    }
}
