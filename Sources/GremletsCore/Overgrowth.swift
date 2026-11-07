import Foundation

/// The moss as something the Gremlets live in, not just look at.
///
/// - **Vines** hang from window corners and climb the screen's side edges as the moss grows (`mossMinutes`).
///   Gremlets climb them: up a window's strand onto its top, or up the screen's edge.
/// - **Platforms:** a Gremlet climbs an edge vine, weaves a pad of moss into it, and steps out onto it. Over a long
///   day the edge vines become ladders of mossy platforms.
/// - **Planting and tending:** Gremlets plant tufts of moss along window tops and come back to water them. Tended
///   moss grows faster, and grows faster still while Claude works.
public struct MossVine: Equatable, Sendable {
    public enum Anchor: Equatable, Sendable { case screenEdge(screen: Int, side: Double), windowSide(window: Int, side: Double) }
    public let key: String
    public let anchor: Anchor
    public let x: Double
    /// Vertical extent (global y-up).
    public let bottom: Double, top: Double
    public var length: Double { top - bottom }
}

/// A bridge the moss weaves between two windows whose tops sit close together, side by side.
public struct MossBridge: Equatable, Sendable {
    public let key: String
    public let minX: Double, maxX: Double, y: Double
    public let leftWindow: Int, rightWindow: Int
}

public struct MossPad: Equatable, Sendable {
    public let id: Int
    public let vine: String
    /// Height above the vine's bottom.
    public let height: Double
    public static let width = 58.0
}

public struct MossPatch: Equatable, Sendable {
    public let id: Int
    public let windowID: Int
    /// Distance from the window's left edge.
    public let offset: Double
    /// 0...1: how big it has grown.
    public internal(set) var size: Double
    var lastTended: Double
    /// The drawn width in points.
    public var width: Double { 30 + size * 150 }
}

public enum MossEvent: Equatable, Sendable {
    case planted(Int, by: Int)
    case tended(Int, by: Int)
    case padBuilt(Int, by: Int)
    case padLost(Vec2)
    case climbing(by: Int)
    /// A strand was snipped back at this point (clippings fall); a friend may have held it steady.
    case pruned(Vec2, by: Int)
    /// Whee: sliding down a strand like a fire pole.
    case sliding(by: Int)
    /// Trimmed back where it was getting thick (a puff of clippings at that spot).
    case trimmed(Vec2, by: Int)
    /// Watered a stretch of the moss on a window top.
    case watered(Vec2, by: Int)
}

struct MossTask: Sendable {
    enum Kind: Sendable { case climb(vine: String, to: Double), buildPad(vine: String, height: Double), plant(window: Int, offset: Double), tend(patch: Int), trim(window: Int, offset: Double), water(window: Int, offset: Double), prune(vine: String), slide(vine: String), hold(vine: String) }
    let kind: Kind
    var acting = false
    var actUntil = 0.0
    let started: Double
}

struct VineClimb: Sendable {
    let vine: String
    var target: Double
    var hangUntil: Double?
    var weaving: Double?   // weaving a pad at this height until the given time
    var padHeight: Double?
    /// Pruning: snip at the target, then climb back up onto the window.
    var pruning = false
    /// Sliding down like a fire pole (fast).
    var sliding = false
}

extension World {
    static let mossPadOwnerBase = -462_000
    public static func isMossPadOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= mossPadOwnerBase && o > mossPadOwnerBase - 2_900 }

    // MARK: Vines (derived from the moss and the windows)

    func rebuildVines() {
        let m = mossMinutes
        var out: [MossVine] = []
        if m >= 40 && edgeVines {
            for (i, scr) in screens.enumerated() {
                let h = min(scr.h * 0.9, (m - 40) * 4)
                for side in [-1.0, 1.0] {
                    out.append(MossVine(key: "e\(i)\(side < 0 ? "l" : "r")", anchor: .screenEdge(screen: i, side: side),
                                        x: side < 0 ? scr.minX + 8 : scr.maxX - 8, bottom: scr.minY, top: scr.minY + h))
                }
            }
        }
        // Moss trickling down the sides of windows: from 20 minutes, each corner grows a strand (and a shorter one
        // beside it) that keeps lengthening until a Gremlet prunes it back.
        if m >= 20 {
            for s in builtSurfaces where s.kind == .windowTop && s.ownerID >= 0 {
                guard let w = windows[s.ownerID] else { continue }
                for (side, x) in [(-1.0, w.minX), (1.0, w.maxX)] where abs((side < 0 ? s.minX : s.maxX) - x) < 2 {
                    let key = "w\(s.ownerID)\(side < 0 ? "l" : "r")"
                    // Each strand keeps its own length: it starts at the moss's level and grows until pruned.
                    if strandGrowth[key] == nil { strandGrowth[key] = (m - 20) * 0.9 }
                    let len = min(w.h * 0.85, 24 + strandGrowth[key]!)
                    out.append(MossVine(key: key, anchor: .windowSide(window: s.ownerID, side: side), x: x + side * 2, bottom: s.y - len, top: s.y))
                    let short = len * 0.55
                    if short > 26 {
                        out.append(MossVine(key: key + "2", anchor: .windowSide(window: s.ownerID, side: side), x: x - side * 7, bottom: s.y - short, top: s.y))
                    }
                }
            }
        }
        mossVines = out
        // Moss bridges: from an hour of moss, between window tops 24 to 200 points apart at about the same height.
        var bridges: [MossBridge] = []
        if m >= 60 {
            let tops = builtSurfaces.filter { $0.kind == .windowTop && $0.ownerID >= 0 && $0.width >= 40 }
            for a in tops { for b in tops where a.ownerID != b.ownerID && b.minX > a.maxX {
                let gap = b.minX - a.maxX
                guard gap >= 24, gap <= 200, abs(a.y - b.y) < 22,
                      // Nothing else in the way.
                      !tops.contains(where: { $0.ownerID != a.ownerID && $0.ownerID != b.ownerID && $0.minX < b.minX && $0.maxX > a.maxX && abs($0.y - a.y) < 60 }),
                      !bridges.contains(where: { $0.leftWindow == a.ownerID || $0.rightWindow == b.ownerID }) else { continue }
                bridges.append(MossBridge(key: "\(a.ownerID)-\(b.ownerID)", minX: a.maxX - 6, maxX: b.minX + 6, y: min(a.y, b.y), leftWindow: a.ownerID, rightWindow: b.ownerID))
            } }
        }
        if bridges.count > 3 { bridges = Array(bridges.prefix(3)) }
        if bridges != mossBridges { mossBridges = bridges; rebuildMossSurfaces() }
        // Pads only stay where their vine still reaches.
        let before = mossPads.count
        mossPads.removeAll { p in
            guard let v = mossVines.first(where: { $0.key == p.vine }), p.height + 10 < v.length else {
                if let v = mossVines.first(where: { $0.key == p.vine }) ?? lastVine(p.vine) { mossEvents.append(.padLost(Vec2(v.x, v.bottom + p.height))) }
                return true
            }
            return false
        }
        // Patches only live on windows that are still there.
        mossPatches.removeAll { windows[$0.windowID] == nil }
        if mossPads.count != before || mossPadSurfaces.count != mossPads.count + mossBridges.count { rebuildMossSurfaces() }
    }

    private func lastVine(_ key: String) -> MossVine? { mossVines.first { $0.key == key } }

    func rebuildMossSurfaces() {
        mossPadSurfaces = mossPads.compactMap { p in
            guard let v = mossVines.first(where: { $0.key == p.vine }), case .screenEdge(_, let side) = v.anchor else { return nil }
            let y = v.bottom + p.height
            let lo = side < 0 ? v.x - 8 : v.x + 8 - MossPad.width
            return Surface(ownerID: World.mossPadOwnerBase - p.id, kind: .plant, y: y, minX: lo, maxX: lo + MossPad.width)
        } + mossBridges.enumerated().map { n, b in
            Surface(ownerID: World.mossPadOwnerBase - 2800 - n, kind: .plant, y: b.y, minX: b.minX, maxX: b.maxX)
        }
        setSurfacesDirty()
    }

    func updateOvergrowth(_ dt: Double) {
        // Strands lengthen while the moss is cared for (about a window's height in an hour or two).
        if !mossThirsty && mossMinutes >= 20 {
            for v in mossVines where !v.key.hasSuffix("2") { if case .windowSide = v.anchor { strandGrowth[v.key, default: 0] += dt * (0.05 + 0.1 * mossCare) } }
        }
        if clock - lastVineBuild > 1 { lastVineBuild = clock; rebuildVines() }
        // Patches grow on their own, faster when tended and while Claude works.
        let boost = 1 + mossMinutes / 100
        for i in mossPatches.indices {
            let tended = clock - mossPatches[i].lastTended < 120 ? 2.5 : 1
            mossPatches[i].size = min(1, mossPatches[i].size + dt * 0.0012 * boost * tended)
        }
    }

    // MARK: Choosing moss things to do

    func mossChoices(for c: Creature, add: (String, Double, @escaping () -> Void) -> Void) {
        guard isFree(c), c.isGrounded, c.mossTask == nil, clock >= nextMossTaskAt, let s = supportingSurface(for: c) else { return }
        // Tend a patch nearby on this window that hasn't been watered lately.
        if s.ownerID >= 0, let p = mossPatches.filter({ $0.windowID == s.ownerID && $0.size < 1 && clock - $0.lastTended > 60 })
            .min(by: { abs(patchX($0) - c.pos.x) < abs(patchX($1) - c.pos.x) }), s.supports(x: patchX(p)) {
            add("tendMoss", 0.8) { self.startMossTask(c, .tend(patch: p.id), walkTo: self.patchX(p)) }
        }
        // A strand hanging more than half-way down its window needs pruning: climb down from the top and snip it.
        if s.kind == .windowTop, let w = windows[s.ownerID] {
            for v in mossVines where !v.key.hasSuffix("2") {
                guard case .windowSide(let wid, _) = v.anchor, wid == s.ownerID, abs(v.top - s.y) < 3 else { continue }
                let corner = v.x - inward(v) * 14   // on the window top, just in from the strand
                guard s.supports(x: corner), !creatures.contains(where: { if case .prune(let k)? = $0.mossTask?.kind { return k == v.key }; return false }) else { continue }
                if v.length > w.h * 0.5 {
                    add("pruneMoss", 1.2 + (v.length / w.h - 0.5) * 6) { self.startMossTask(c, .prune(vine: v.key), walkTo: corner) }
                }
                // Or just slide down it, for the fun of it.
                if v.length > 70 && abs(corner - c.pos.x) < 300 {
                    add("slideDown", 0.35) { self.startMossTask(c, .slide(vine: v.key), walkTo: corner) }
                }
            }
        }
        // Water the moss on this window top (they notice when it's getting dry, and go to it far more often).
        if mossMinutes >= 10, s.kind == .windowTop, let w = windows[s.ownerID] {
            let x = (c.pos.x + c.facing * rng.range(20, 90)).clamped(s.minX + 16, s.maxX - 16)
            add("waterMoss", 0.4 + (1 - mossCare) * 4) { self.startMossTask(c, .water(window: s.ownerID, offset: x - w.minX), walkTo: x) }
        }
        // Keep it tidy: once the moss is thick, trim the carpet back near an end of this window top.
        if mossMinutes > 170, s.kind == .windowTop, let w = windows[s.ownerID] {
            let x = (c.pos.x < s.minX + s.width / 2 ? s.minX + 26 : s.maxX - 26).clamped(s.minX + 10, s.maxX - 10)
            add("trimMoss", 0.35 + (mossMinutes - 170) / 120) { self.startMossTask(c, .trim(window: s.ownerID, offset: x - w.minX), walkTo: x) }
        }
        // Plant a new tuft on this window top.
        if s.kind == .windowTop, let w = windows[s.ownerID], mossPatches.filter({ $0.windowID == s.ownerID }).count < 4 {
            let spots = stride(from: s.minX + 40, through: s.maxX - 40, by: 30).filter { x in
                !mossPatches.contains { $0.windowID == s.ownerID && abs(patchX($0) - x) < 90 }
            }
            if let x = spots.min(by: { abs($0 - c.pos.x) < abs($1 - c.pos.x) }) {
                add("plantMoss", 0.45) { self.startMossTask(c, .plant(window: s.ownerID, offset: x - w.minX), walkTo: x) }
            }
        }
        // Climb a vine, or build a platform on one.
        guard let v = mossVines.filter({ canGrab($0, from: s, at: c.pos.x) }).min(by: { abs($0.x - c.pos.x) < abs($1.x - c.pos.x) }),
              abs(v.x - c.pos.x) < 420 else { return }
        let standX = v.x + (inward(v) * 14)
        switch v.anchor {
        case .windowSide:
            add("climbVine", 0.9) { self.startMossTask(c, .climb(vine: v.key, to: v.top), walkTo: standX) }
        case .screenEdge:
            let pads = mossPads.filter { $0.vine == v.key }.map(\.height).sorted()
            let next = (pads.last ?? 0) + 110
            if next + 30 < v.length && !creatures.contains(where: { if case .buildPad(let k, _)? = $0.mossTask?.kind { return k == v.key }; return false }) {
                add("buildPad", 0.7) { self.startMossTask(c, .buildPad(vine: v.key, height: next), walkTo: standX) }
            }
            let to = pads.last.map { $0 } ?? min(v.length - 10, 160)
            add("climbVine", 0.5) { self.startMossTask(c, .climb(vine: v.key, to: v.bottom + to), walkTo: standX) }
        }
    }

    func inward(_ v: MossVine) -> Double {
        switch v.anchor { case .screenEdge(_, let side): return -side; case .windowSide(_, let side): return side }
    }

    /// Can a creature standing on `s` reach the bottom of this vine (walk under it and grab it)?
    func canGrab(_ v: MossVine, from s: Surface, at x: Double) -> Bool {
        let gx = v.x + inward(v) * 14
        guard s.supports(x: gx), v.length > 60 else { return false }
        return s.y >= v.bottom - 70 && s.y < v.top - 40
    }

    func patchX(_ p: MossPatch) -> Double { (windows[p.windowID]?.minX ?? 0) + p.offset }

    func startMossTask(_ c: Creature, _ kind: MossTask.Kind, walkTo x: Double) {
        endSocial(c)
        c.mossTask = MossTask(kind: kind, started: clock)
        switch kind {
        case .plant: c.carrying = "sprout"
        case .water, .tend: c.carrying = "can"
        default: c.carrying = nil
        }
        c.targetX = x; c.facing = x > c.pos.x ? 1 : -1
        c.set(.walk, duration: 30)
        // While Claude works they're busy gardeners: the next moss job comes round quickly.
        nextMossTaskAt = clock + (claudeWorking ? rng.range(2, 5) : rng.range(8, 20))
    }

    /// `gremlet moss climb|pad|plant`: someone does it now, if anyone can.
    @discardableResult
    public func startMossActivity(_ what: String) -> Bool {
        nextMossTaskAt = 0
        for c in creatures.shuffled(using: &rng) where isFree(c) && c.isGrounded && c.mossTask == nil {
            var picked: (() -> Void)?
            mossChoices(for: c) { name, _, f in
                if (what == "climb" && name == "climbVine") || (what == "pad" && name == "buildPad") || (what == "plant" && (name == "plantMoss" || name == "tendMoss")) {
                    if picked == nil { picked = f }
                }
            }
            if let f = picked { f(); return true }
        }
        return false
    }

    /// The next step of a moss task when the current activity ends.
    func mossDecide(_ c: Creature) {
        defer { if c.mossTask == nil { c.carrying = nil } }
        guard var t = c.mossTask, let s = supportingSurface(for: c) else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
        if clock - t.started > 60 { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
        switch t.kind {
        case .plant(let wid, let offset):
            guard let w = windows[wid], s.ownerID == wid else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
            let x = w.minX + offset
            if !t.acting {
                if abs(c.pos.x - x) > 6 { c.targetX = x; c.set(.walk, duration: 20); return }
                t.acting = true; c.mossTask = t; c.carrying = nil
                c.workPose = "crouch"; c.set(.work, duration: 2.4)
                return
            }
            nextPatchID += 1
            mossPatches.append(MossPatch(id: nextPatchID, windowID: wid, offset: offset, size: 0.08, lastTended: clock))
            mossEvents.append(.planted(nextPatchID, by: c.id))
            c.mossTask = nil
            c.set(.react, duration: c.animationLength(for: .react))
        case .tend(let pid):
            guard let i = mossPatches.firstIndex(where: { $0.id == pid }) else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
            let x = patchX(mossPatches[i])
            if !t.acting {
                if abs(c.pos.x - x) > 8 { c.targetX = x; c.set(.walk, duration: 20); return }
                t.acting = true; c.mossTask = t
                c.workPose = "crouch"; c.set(.work, duration: 2.2)
                mossEvents.append(.tended(pid, by: c.id))
                return
            }
            mossPatches[i].size = min(1, mossPatches[i].size + 0.2)
            mossPatches[i].lastTended = clock
            mossCare = min(1, mossCare + 0.1)
            c.mossTask = nil
            c.set(.idle, duration: 0.6)
        case .prune(let key), .slide(let key):
            guard let v = mossVines.first(where: { $0.key == key }), abs(s.y - v.top) < 3 else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
            let corner = v.x - inward(v) * 14   // on the window top, just in from the strand
            if abs(c.pos.x - corner) > 6 { c.targetX = corner; c.set(.walk, duration: 20); return }
            let pruning: Bool = { if case .prune = t.kind { return true }; return false }()
            c.mossTask = nil
            if pruning {
                // A friend on the same window comes to hold the strand steady.
                // (Dropping a little moss chore of its own to help.)
                if let f = creatures.filter({ $0 !== c && $0.job == nil && $0.expedition == nil && $0.play == nil && !$0.isAsleep && $0.climb == nil
                    && $0.isGrounded && $0.groundOwner == s.ownerID && abs($0.pos.x - corner) < 700 })
                    .min(by: { abs($0.pos.x - corner) < abs($1.pos.x - corner) }) {
                    startMossTask(f, .hold(vine: key), walkTo: (corner - inward(v) * 26).clamped(s.minX + 6, s.maxX - 6))
                }
            }
            endSocial(c)
            c.climb = VineClimb(vine: v.key, target: pruning ? v.top - v.length * 0.5 : v.bottom, hangUntil: nil, weaving: nil, padHeight: nil, pruning: pruning, sliding: !pruning)
            c.groundOwner = nil
            c.vel = .zero
            c.pos = Vec2(v.x, v.top - 4)
            c.facing = inward(v)
            c.set(.float, duration: 60)
            mossEvents.append(pruning ? .climbing(by: c.id) : .sliding(by: c.id))
        case .hold(let key):
            guard let v = mossVines.first(where: { $0.key == key }) else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
            let spot = v.x - inward(v) * 40
            if !t.acting {
                if abs(c.pos.x - spot) > 8, s.supports(x: spot) { c.targetX = spot; c.set(.walk, duration: 15); return }
                t.acting = true; c.mossTask = t
                c.facing = inward(v); c.workPose = "crouch"; c.set(.work, duration: 5)
                return
            }
            c.mossTask = nil
            c.set(.react, duration: c.animationLength(for: .react))
        case .water(let wid, let offset):
            guard let w = windows[wid], s.ownerID == wid else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
            let x = w.minX + offset
            if !t.acting {
                if abs(c.pos.x - x) > 6 { c.targetX = x; c.set(.walk, duration: 20); return }
                t.acting = true; c.mossTask = t
                c.workPose = "crouch"; c.set(.work, duration: 2.2)
                mossEvents.append(.watered(Vec2(x, s.y), by: c.id))
                return
            }
            mossCare = min(1, mossCare + 0.2)
            c.mossTask = nil
            c.set(.idle, duration: 0.5)
        case .trim(let wid, let offset):
            guard let w = windows[wid], s.ownerID == wid else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
            let x = w.minX + offset
            if !t.acting {
                if abs(c.pos.x - x) > 6 { c.targetX = x; c.set(.walk, duration: 20); return }
                t.acting = true; c.mossTask = t
                c.workPose = "crouch"; c.set(.work, duration: 2.6)
                return
            }
            mossMinutes = max(0, mossMinutes - 8)
            mossCare = min(1, mossCare + 0.06)
            mossEvents.append(.trimmed(Vec2(x, s.y), by: c.id))
            c.mossTask = nil
            c.set(.idle, duration: 0.6)
        case .climb(let key, let to):
            guard let v = mossVines.first(where: { $0.key == key }) else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
            let gx = v.x + inward(v) * 14
            if abs(c.pos.x - gx) > 6 { c.targetX = gx; c.set(.walk, duration: 20); return }
            c.mossTask = nil
            startClimb(c, v, to: to, pad: nil)
        case .buildPad(let key, let height):
            guard let v = mossVines.first(where: { $0.key == key }), height + 20 < v.length else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
            let gx = v.x + inward(v) * 14
            if abs(c.pos.x - gx) > 6 { c.targetX = gx; c.set(.walk, duration: 20); return }
            c.mossTask = nil
            startClimb(c, v, to: v.bottom + height, pad: height)
        }
    }

    // MARK: Climbing

    func startClimb(_ c: Creature, _ v: MossVine, to: Double, pad: Double?) {
        endSocial(c)
        c.climb = VineClimb(vine: v.key, target: min(to, v.top), hangUntil: nil, weaving: nil, padHeight: pad)
        c.groundOwner = nil
        c.vel = .zero
        c.pos.x = v.x
        c.facing = inward(v)
        c.set(.float, duration: 60)
        mossEvents.append(.climbing(by: c.id))
    }

    func updateClimb(_ c: Creature, _ dt: Double) {
        guard var cl = c.climb, let v = mossVines.first(where: { $0.key == cl.vine }) else {
            c.climb = nil; c.set(.airborne); return
        }
        c.pos.x = v.x
        c.vel = .zero
        // Weaving a pad: hold on, then step out onto it.
        if let until = cl.weaving {
            if clock >= until, let h = cl.padHeight {
                nextPadID += 1
                mossPads.append(MossPad(id: nextPadID, vine: v.key, height: h))
                rebuildMossSurfaces()
                mossEvents.append(.padBuilt(nextPadID, by: c.id))
                c.climb = nil
                c.pos = Vec2(v.x + inward(v) * 26, v.bottom + h + 2)
                c.vel = Vec2(inward(v) * 40, 120)
                c.set(.airborne)
            }
            return
        }
        if let until = cl.hangUntil {
            if clock >= until {
                cl.hangUntil = nil
                if cl.pruning {
                    // Snip: the strand's cut back to about half the window's height, and up we go again.
                    if case .windowSide(let wid, _) = v.anchor, let w = windows[wid] {
                        strandGrowth[v.key] = max(0, w.h * 0.35 - 24)
                    }
                    mossCare = min(1, mossCare + 0.05)
                    mossEvents.append(.pruned(Vec2(v.x, c.pos.y - 10), by: c.id))
                    cl.pruning = false
                    cl.target = v.top
                } else {
                    cl.target = v.bottom
                }
                c.climb = cl
            }
            return
        }
        let dy = cl.target - c.pos.y
        let speed = cl.sliding ? 380.0 : (dy < 0 ? 140.0 : 62.0)
        if abs(dy) > 2 {
            c.pos.y += max(-speed * dt, min(speed * dt, dy))
            c.climb = cl
            return
        }
        // Arrived.
        if cl.pruning {
            // Hold on and snip for a moment.
            cl.hangUntil = clock + 2.4
            c.climb = cl
            return
        }
        if cl.padHeight != nil {
            cl.weaving = clock + 2.8
            c.climb = cl
            return
        }
        if abs(cl.target - v.top) < 3, case .windowSide(let wid, _) = v.anchor, let top = surfaces.first(where: { $0.ownerID == wid && $0.kind == .windowTop && abs($0.y - v.top) < 3 }) {
            // Over the edge onto the window's top.
            c.climb = nil
            c.pos = Vec2((v.x + inward(v) * 16).clamped(top.minX + 4, top.maxX - 4), top.y + 2)
            c.vel = Vec2(inward(v) * 30, 80)
            c.set(.airborne)
            return
        }
        if let pad = mossPadSurfaces.first(where: { abs($0.y - cl.target) < 3 && ($0.supports(x: v.x - 8) || $0.supports(x: v.x + 8)) }) {
            c.climb = nil
            c.pos = Vec2((pad.minX + pad.maxX) / 2, pad.y + 2)
            c.vel = Vec2(inward(v) * 20, 60)
            c.set(.airborne)
            return
        }
        if abs(cl.target - v.bottom) < 3 {
            c.climb = nil
            // Off the end of a slide with a little hop outward.
            if cl.sliding { c.vel = Vec2(-inward(v) * 90, 160) }
            c.set(.airborne)
            return
        }
        // Nowhere to step off: look around a while, then slide back down.
        cl.hangUntil = clock + rng.range(1.5, 3)
        c.climb = cl
    }

    public func drainMossEvents() -> [MossEvent] {
        defer { mossEvents.removeAll() }
        return mossEvents
    }
}
