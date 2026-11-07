import Foundation  // math only (sin); available on Linux and Windows too

/// Things the renderer may want to show (hearts, particles, sounds).
public enum WorldEvent: Equatable, Sendable {
    case poked(Int)
    case petted(Int)
    case fellAsleep(Int)
    case wokeUp(Int)
    case landed(Int, impact: Double)
    case dizzy(Int)
    case alert(Int)
    case special(Int, effect: String)
    case greet(Int, Int)
    case tagged(Int)
    case bump(Int, Int)
    case stacked(rider: Int, carrier: Int)
    case danceBeat(Int)
    case startled(Int)
    case tookOff(Int)
    /// Flung into the air by a friend (a toss).
    case tossed(Int, by: Int)
    case highFive(Int, Int)
    case caught(Int)
}

/// The simulation: creatures, the surfaces they live on, physics, social behavior and input.
/// Pure Swift with no AppKit, driven by a platform layer that feeds it screens, windows, the cursor and time.
public final class World {
    // Tuning (points, seconds).
    public var gravity: Double = 2200
    public var maxFallSpeed: Double = 2600
    public var maxJumpHeight: Double = 320
    public var maxJumpDistance: Double = 420
    public var energyDrainPerSecond: Double = 0.0045
    /// Landing faster than this (pt/s) leaves a creature seeing stars.
    public var dizzyImpact: Double = 1700
    public var flySpeed: Double = 210
    /// Chance that two creatures walking into each other bonk and bounce (otherwise they squeeze past).
    public var bumpChance: Double = 0.35
    /// Extra sleepiness (e.g. late at night). Multiplies energy drain.
    public var sleepyFactor: Double = 1
    /// Focus mode (see Companion.swift): calm, dozing Gremlets.
    public internal(set) var calm = false
    /// You're at your Mac (recent keyboard/mouse input). Hobbies only start, and only make progress, while you are.
    public var userActive = true
    /// At most this many Gremlets on a hobby at once.
    public var maxHobbies = 1
    /// Tops of visible desktop icons (set by the platform layer when icon play is on). Owner ids at or below
    /// `iconOwnerBase`.
    public var iconSurfaces: [Surface] = []
    /// The Grove (big task-powered plants along the main screen's floor) and what it offers to stand on.
    public internal(set) var grove = Grove()
    public internal(set) var groveLedges: [GroveLedge] = []
    var groveSurfaces: [Surface] = []
    var groveEvents: [GroveEvent] = []
    /// Special events (bosses, meteor showers, festivals): the one running now and the ones queued up.
    public internal(set) var spectacle: Spectacle?
    var pendingEvents: [SpectacleKind] = []
    var lastSpectacle: Spectacle?
    var claudeEvents: [ClaudeWorkEvent] = []
    /// Bridges Gremlets have built between windows, and what's happened with them and the village lately.
    public internal(set) var bridges: [Bridge] = []
    var nextBridgeID = 0
    var buildEvents: [BuildEvent] = []
    /// Staircases and minecart rails Gremlets have built (see Terrain.swift).
    public internal(set) var stairs: [Stair] = []
    var nextStairID = 0
    var nextStairAt = 120.0
    public internal(set) var rails: [Rail] = []
    var nextRailID = 0
    var nextRailAt = 300.0
    var terrainEvents: [TerrainEvent] = []
    /// Expeditions: ziplines, chests and summit flags (see Expedition.swift).
    public internal(set) var ziplines: [Zipline] = []
    public internal(set) var chests: [Chest] = []
    public internal(set) var flags: [Flag] = []
    var nextZipID = 0, nextChestID = 0, nextFlagID = 0
    var nextChestAt = 600.0
    var nextSummitAt = 900.0
    var nextExpeditionAt = 0.0
    var expeditionEvents: [ExpeditionEvent] = []
    /// Overgrowth: minutes of Claude work the moss has soaked up. It grows a minute per minute while Claude works,
    /// and slowly recedes (a minute per six) while nothing is running. The platform layer saves it and draws it.
    public var mossMinutes = 0.0
    public static let mossMax = 300.0
    public internal(set) var mossVines: [MossVine] = []
    public internal(set) var mossPads: [MossPad] = []
    public internal(set) var mossPatches: [MossPatch] = []
    var mossPadSurfaces: [Surface] = []
    var mossEvents: [MossEvent] = []
    var nextPadID = 0, nextPatchID = 0
    var nextMossTaskAt = 60.0
    var lastVineBuild = -10.0
    /// When Claude last used a tool in any session (drives the Gremlets' day: garden while Claude works, rest after).
    public internal(set) var lastClaudeWorkAt = -1e9
    /// The Gremlets' day follows Claude (the app turns this on; the engine's other tests run without it).
    public var dayFollowsClaude = false
    /// Claude is working right now (a tool call in the last 90 s).
    public var claudeWorking: Bool { dayFollowsClaude && clock - lastClaudeWorkAt < 90 }
    /// Claude has been quiet for a couple of minutes: time to wind down.
    public var claudeResting: Bool { dayFollowsClaude && clock - lastClaudeWorkAt > 120 }
    /// The app's tidier desktop: no village or road on the floor, no vines up the screen's sides, and one small plant
    /// at a time in the corner (the engine's own tests run with the older, fuller world).
    public var villageOn = true
    /// Minecart rails (the app turns them off: not part of the forest).
    public var railsOn = true
    public var edgeVines = true
    public var rotateGrove = false
    var nextGroveRotation = 0.0
    /// An app is full screen: everything keeps to the bottom corners, and the rest is put away (see Compact.swift).
    public var compact = false { didSet { if compact && !oldValue { enterCompact() } } }
    /// The cloud under the pointer while ⌃⌥ is held (see Lift.swift).
    public internal(set) var lift: CursorLift?
    /// The home under the notch (nil on screens without one); see Notch.swift.
    public var notchHome: NotchHome? { didSet { if notchHome != oldValue { setSurfacesDirty() } } }
    var nextNotchTripAt = 0.0
    /// The Gremlet napping (or about to) in the notch hammock: id, since when, and whether it has dozed off yet.
    var hammockNapper: (Int, Double, Bool)?
    /// Codebase castles by project, where they stand, and what just landed on them (see Castle.swift).
    public internal(set) var castles: [String: Castle] = [:]
    public internal(set) var castlePlacements: [CastlePlacement] = []
    var castleEvents: [CastleEvent] = []
    /// Resting project trees on brackets up the side of the screen (off by default; see rebuildAttached).
    public var showNursery = false
    /// The weather where you are (see Weather.swift).
    var liveWeather: LocalWeather?
    var weatherPreview: LocalWeather?
    var weatherPreviewUntil = -1.0
    /// 0...1: how much snow lies on window tops and the floor.
    public var snowDepth = 0.0
    public internal(set) var snowmen: [Snowman] = []
    var nextSnowmanID = 0
    var nextSnowmanAt = 0.0
    /// Boosts and reactions to the Mac (see Teamwork.swift).
    var teamEvents: [TeamEvent] = []
    var planEvents: [ClaudePlanEvent] = []
    var nextBoostAt = 180.0
    var lastPose = -100.0
    /// The sky ferry (when it's around) and what happened in the mine and the sky lately.
    public internal(set) var ferry: Ferry?
    var nextFerryAt: Double?
    /// The traveling merchant (when it's in the village).
    public internal(set) var merchant: Merchant?
    /// Every project's bonsai, the live Claude sessions growing them, and where the trees and terminal ledges are.
    public internal(set) var bonsaiBook = BonsaiBook()
    var liveBonsai: [String: LiveBonsai] = [:]
    var bonsaiEvents: [BonsaiEvent] = []
    public internal(set) var bonsaiPlacements: [BonsaiPlacement] = []
    public internal(set) var terminalLedges: [TerminalLedge] = []
    var attachedSurfaces: [Surface] = []
    /// Platforms that belong to a window (tree pads, terminal ledges) and ride along with it.
    var attachedOwnerWindow: [Int: Int] = [:]
    var _nurserySide = 1.0
    /// How fast time at work passes (the demo turns it up so the ivy covers a window in a minute).
    public var workClockScale = 1.0
    var nextMerchantAt: Double?
    var merchantEvents: [MerchantEvent] = []
    var adventureEvents: [AdventureEvent] = []
    /// Seeds in flight in games of catch.
    public internal(set) var playBalls: [PlayBall] = []
    public internal(set) var kite: Kite?
    var nextKiteAt = 240.0   // the first kite goes up after a few minutes of life, then every ten to twenty-five
    var pendingThrows: [(at: Double, from: Int, to: Int)] = []
    public var eventsAllowed = true
    var builtSurfaces: [Surface] = []
    public static let iconOwnerBase = -200_000
    var _gardenSpots: [Double] = []
    /// Pending wishes: the next seed planted is epic or better.
    public internal(set) var wishes = 0
    /// A doorway at the edge of the main screen to a linked screen (an iPad, a phone: see the app's ScreenBridge):
    /// +1 = the right edge, -1 = the left. The floor runs `doorDepth` points past that edge so Gremlets can walk out.
    public var door: Double? { didSet { if door != oldValue { for c in creatures { c.doorDecided = false } } } }
    public static let doorDepth = 120.0
    /// Calendar month (1-12) and whether it's night, set by the platform layer (seasonal and night-only plants).
    public var month = 6
    public var isNight = false

    public private(set) var screens: [Rect] = []
    public private(set) var windows: [Int: Rect] = [:]
    /// Window ids, front-most first.
    public private(set) var windowOrder: [Int] = []
    /// Screen floors and window tops (creature heads are added on the fly, see `allSurfaces`).
    public private(set) var surfaces: [Surface] = []
    public private(set) var creatures: [Creature] = []
    public var cursor: Vec2?
    /// Simulation time (seconds), the clock jobs and events are stamped with.
    public var time: Double { clock }
    public var rng: SplitMix64
    public private(set) var events: [WorldEvent] = []

    private var nextID = 1
    private var dragSamples: [(t: Double, p: Vec2)] = []
    var clock: Double = 0
    private var lastCursor: Vec2?
    var cursorSpeed: Double = 0

    public init(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        rng = SplitMix64(seed: seed)
    }

    /// Surface owner ids at or below this value belong to creatures (heads you can stand on).
    static let creatureOwnerBase = -1000
    static func creatureOwner(_ id: Int) -> Int { creatureOwnerBase - id }
    static func carrierID(_ owner: Int?) -> Int? {
        guard let o = owner, o <= creatureOwnerBase, o > iconOwnerBase else { return nil }
        return creatureOwnerBase - o
    }

    // MARK: Environment

    /// Updates screens and windows. Creatures standing on a window that moved ride along with it;
    /// if their window closed or got covered they'll fall on the next step.
    public func setEnvironment(screens: [Rect], windowsFrontToBack: [WindowInfo]) {
        var newWindows: [Int: Rect] = [:]
        for w in windowsFrontToBack { newWindows[w.id] = w.frame }
        for c in creatures where c.isGrounded {
            // Window tops, and the platforms attached to windows (tree pads, terminal ledges); shelves carry their
            // own riders (carryRiders).
            guard let owner = c.groundOwner, owner >= 0 || attachedOwnerWindow[owner] != nil,
                  let wid = owner >= 0 ? owner : attachedOwnerWindow[owner], let old = windows[wid], let new = newWindows[wid] else { continue }
            let d = Vec2(new.minX - old.minX, new.maxY - old.maxY)
            c.pos += d
            // Anyone standing on this creature's head comes along for the ride.
            for r in creatures where r.groundOwner == c.carrierOwnerID { r.pos += d }
        }
        self.screens = screens
        self.windows = newWindows
        self.windowOrder = windowsFrontToBack.map(\.id)
        builtSurfaces = SurfaceBuilder.build(screens: screens, windowsFrontToBack: windowsFrontToBack)
        if let d = door, let main = screens.first, let i = builtSurfaces.firstIndex(where: { $0.kind == .floor && $0.ownerID == -1 }) {
            if d > 0 { builtSurfaces[i].maxX = main.maxX + World.doorDepth } else { builtSurfaces[i].minX = main.minX - World.doorDepth }
        }
        validateBridges()
        validateStairs()
        validateRails()
        rebuildGroveSurfaces()
        rebuildAttached()
        setSurfacesDirty()
        validateZips()
        validateChests()
        validateFlags()
        rebuildVines()
    }

    func setSurfacesDirty() { surfaces = builtSurfaces + iconSurfaces + groveSurfaces + bridgeSurfaces + stairSurfaces + attachedSurfaces + mossPadSurfaces + notchSurfaces }

    // MARK: Creatures

    @discardableResult
    public func spawn(_ species: SpeciesInfo, at p: Vec2? = nil) -> Creature {
        let start: Vec2
        if let p { start = p } else if let s = screens.first {
            start = Vec2(rng.range(s.minX + 80, max(s.minX + 81, s.maxX - 80)), s.maxY - species.pointSize.y - 10)
        } else { start = .zero }
        let c = Creature(id: nextID, species: species, pos: start)
        nextID += 1
        c.facing = rng.chance(0.5) ? 1 : -1
        c.prevPos = start
        c.set(.airborne)
        creatures.append(c)
        return c
    }

    public func remove(_ id: Int) {
        creatures.removeAll { $0.id == id }
        for c in creatures where c.friendID == id { c.friendID = nil; c.social = .none }
    }

    /// Top-most creature whose sprite has an opaque pixel at `p`.
    public func creature(at p: Vec2) -> Creature? {
        creatures.last { $0.homeUntil == nil && $0.hitTest(p) }
    }

    func creature(id: Int?) -> Creature? {
        guard let id else { return nil }
        return creatures.first { $0.id == id }
    }

    public func drainEvents() -> [WorldEvent] {
        defer { events.removeAll() }
        return events
    }

    func emit(_ e: WorldEvent) { events.append(e) }

    /// Suggested simulation rate. Lets the platform layer throttle the loop to save CPU when nothing moves.
    public var desiredTickRate: Double {
        if creatures.contains(where: { [.airborne, .dragged, .fly, .run].contains($0.activity) }) { return 60 }
        if creatures.contains(where: { ![.idle, .sleep].contains($0.activity) }) { return 30 }
        return 12
    }

    // MARK: Input

    public func poke(_ c: Creature) {
        guard c.isGrounded else { return }
        if c.isAsleep && calm {
            emit(.poked(c.id))   // focus mode: a sleepy acknowledgement, no wake-up
            return
        }
        if c.isAsleep {
            // Startled awake: jolt, then rub eyes. A bit grumpy, so no energy bonus.
            c.set(.wake, duration: c.animationLength(for: .wake))
            emit(.wokeUp(c.id))
            return
        }
        c.energy = min(1, c.energy + 0.1)
        endSocial(c)
        encourage(c)
        countPokeForMystery(c)
        c.set(.react, duration: c.animationLength(for: .react) + 0.15)
        emit(.poked(c.id))
    }

    /// Call with cursor movement over a creature; enough rubbing counts as petting.
    public func pet(_ c: Creature, distance: Double) {
        guard c.isGrounded, ![.react, .wake, .dizzy, .run].contains(c.activity) else { return }
        c.petAmount += distance
        if c.petAmount > 220 {
            c.petAmount = 0
            if c.activity == .sleep { return } // let sleeping gremlets lie, petting doesn't wake them
            c.energy = min(1, c.energy + 0.05)
            endSocial(c)
            if c.bond >= 0.5 && !calm && rng.chance(0.5) {
                startSpecial(c)        // close friends show off for you
                emit(.petted(c.id))
            } else {
                c.set(.pet, duration: 1.4)
                emit(.petted(c.id))
            }
        }
    }

    public func beginDrag(_ c: Creature, at p: Vec2, time: Double) {
        c.grabOffset = c.pos - p
        c.groundOwner = nil
        c.vel = .zero
        endSocial(c)
        c.set(.dragged)
        dragSamples = [(time, p)]
    }

    public func drag(_ c: Creature, to p: Vec2, time: Double) {
        guard c.activity == .dragged else { return }
        let newPos = p + c.grabOffset
        if newPos.x != c.pos.x { c.facing = newPos.x > c.pos.x ? 1 : -1 }
        c.pos = newPos
        dragSamples.append((time, p))
        dragSamples.removeAll { time - $0.t > 0.1 }
    }

    /// Releases a dragged creature with the cursor's recent velocity, so it can be thrown.
    public func endDrag(_ c: Creature, time: Double) {
        guard c.activity == .dragged else { return }
        var v = Vec2.zero
        if let first = dragSamples.first, let last = dragSamples.last, last.t - first.t > 0.01, time - last.t < 0.08 {
            v = (last.p - first.p) * (1 / (last.t - first.t))
        }
        let len = v.length
        if len > 2400 { v = v * (2400 / len) }
        c.vel = v
        c.set(.airborne)
        dragSamples.removeAll()
    }

    // MARK: Simulation

    public func step(_ rawDt: Double) {
        let dt = min(max(rawDt, 0), 1.0 / 20)
        clock += dt
        if let cur = cursor {
            if let last = lastCursor, dt > 0 { cursorSpeed = cursorSpeed * 0.5 + (cur - last).length / dt * 0.5 }
            lastCursor = cur
        }
        for c in creatures { c.prevPos = c.pos }
        carryRiders()
        updateRails(dt)
        updateStairs(dt)
        updateChests(dt)
        updateFlags()
        updateExpeditions(dt)
        updateBoosts()
        updateSigns()
        updateOvergrowth(dt)
        updateWeather(dt)
        checkHammock()
        let working = creatures.contains { $0.job?.kind == .claude && $0.job?.phase == .working && clock - ($0.job?.lastToolTime ?? -999) < 90 }
        if let t = creatures.compactMap({ $0.job?.kind == .claude ? $0.job?.lastToolTime : nil }).max(), t > lastClaudeWorkAt { lastClaudeWorkAt = t }
        // Moss keeps growing: a minute a minute while Claude works, slowly otherwise. The Gremlets trim it back where
        // it gets thick, so it settles into a lush but tidy cover rather than taking everything over.
        mossMinutes = (mossMinutes + (working ? dt * workClockScale / 60 : dt / 300)).clamped(0, World.mossMax)
        updateFerry(dt)
        updateLift(dt)
        updateMerchant(dt)
        updateBonsai(dt)
        updateGrove(dt)
        // Lower creatures first so a carrier has moved before the friend standing on its head.
        for c in creatures.sorted(by: { $0.pos.y < $1.pos.y }) { update(c, dt) }
        resolveBumps()
        checkStartle()
        updatePlay(dt); updateKite(dt)
        updateSpectacle(dt)
        updateSessionWeather()
    }

    private func update(_ c: Creature, _ dt: Double) {
        c.animTime += dt * c.animSpeed
        if c.gliding && c.activity != .airborne { c.gliding = false }
        // Asleep inside a village house: rest up, and come back out when it's time (or when there's work to do).
        if let until = c.homeUntil {
            if c.job != nil || clock >= until || spectacle != nil {
                c.homeUntil = nil
                if let n = c.homeHouse, n >= 0 { groveEvents.append(.leftHome(n, by: c.id)) }
                c.homeHouse = nil
                if c.mining { finishDig(c) }
                c.set(.wake, duration: c.animationLength(for: .wake))
                emit(.wokeUp(c.id))
            } else {
                c.energy = min(1, c.energy + dt * 0.08)
                return
            }
        }
        c.bumpCooldown = max(0, c.bumpCooldown - dt)
        c.startleCooldown = max(0, c.startleCooldown - dt)
        c.tagImmunity = max(0, c.tagImmunity - dt)
        if c.activity == .sleep {
            c.energy = min(1, c.energy + dt * 0.06)
        } else if c.activity != .dragged {
            let busy = [.walk, .chase, .run, .fly, .dance].contains(c.activity)
            c.energy = max(0, c.energy - dt * energyDrainPerSecond * sleepyFactor * (busy ? 1.6 : 1))
        }

        switch c.activity {
        case .dragged:
            return
        case .airborne:
            integrateAirborne(c, dt)
            return
        case .fly:
            c.timer -= dt
            updateFlight(c, dt)
            return
        case .float:
            if c.zip != nil { updateZip(c, dt) } else if c.climb != nil { updateClimb(c, dt) } else { updateFloat(c, dt) }
            return
        default:
            break
        }

        // Standing on a friend's head: move with them.
        if let carrier = creature(id: World.carrierID(c.groundOwner)) {
            c.pos += carrier.pos - carrier.prevPos
            // Never get carried past a screen edge (the carrier's own walls are a little wider than ours).
            let (lo, hi) = horizontalLimits(for: c, atY: c.pos.y + 1)
            if c.pos.x < lo || c.pos.x > hi {
                c.pos.x = c.pos.x.clamped(lo, hi)
                c.groundOwner = nil
                c.vel = Vec2((c.pos.x < carrier.pos.x ? -1 : 1) * 80, 260)
                c.set(.airborne, duration: 5)
            }
        }

        // Grounded: make sure something still supports us (windows move, close, or get covered).
        guard let support = supportingSurface(for: c) else {
            let walking = [.walk, .chase, .run, .follow, .peek].contains(c.activity)
            c.groundOwner = nil
            c.vel = Vec2(walking ? c.facing * c.species.walkSpeed * 0.6 : 0, 0)
            if c.isAsleep { emit(.wokeUp(c.id)) }
            endSocial(c)
            c.set(.airborne)
            return
        }
        c.pos.y = support.y
        c.groundOwner = support.ownerID

        c.timer -= dt
        if let job = c.job, !compact, updateJob(c, job, dt, on: support) { return }
        if c.building != nil, c.job == nil, updateBuilding(c, dt, on: support) { return }
        if c.stair != nil, c.job == nil, updateStairBuilding(c, dt, on: support) { return }
        if c.rail != nil, c.job == nil, updateRailLaying(c, dt, on: support) { return }
        if c.visitingID != nil, updateVisit(c, dt, on: support) { return }
        if c.tendX != nil, updateTending(c, dt, on: support) { return }
        switch c.activity {
        case .idle:
            faceCursorIfNear(c)
        case .walk, .chase:
            walk(c, dt, on: support)
        case .follow:
            updateFollow(c, dt, on: support)
        case .run:
            updateTag(c, dt, on: support)
        case .peek:
            updatePeek(c, dt)
        case .dance:
            c.beatTimer -= dt
            if c.beatTimer <= 0 { c.beatTimer = 0.55; emit(.danceBeat(c.id)) }
        case .crouch:
            if c.timer <= 0 {
                c.vel = c.pendingLaunch
                if abs(c.vel.x) > 1 { c.facing = c.vel.x > 0 ? 1 : -1 }
                c.groundOwner = nil
                c.pos.y += 1
                c.set(.airborne)
                return
            }
        case .yawn:
            if c.timer <= 0 {
                c.set(.sleep, duration: rng.range(12, 28) * c.species.sleepiness.clamped(0.6, 1.6))
                emit(.fellAsleep(c.id))
            }
            return
        case .sleep:
            if calm { return }  // focus mode: keep dozing until the break
            if c.timer <= 0 || c.energy >= 1 {
                c.set(.wake, duration: c.animationLength(for: .wake))
                emit(.wokeUp(c.id))
            }
            return
        case .alert:
            if c.timer <= 0 { c.set(.chase, duration: 6) }
            return
        default:
            break
        }
        if c.timer <= 0 && c.activity != .crouch {
            // A runner landing from a dodge hop keeps the game of tag going.
            if c.activity == .land, c.social == .runner || c.social == .chaser,
               let f = creature(id: c.friendID), f.friendID == c.id, f.activity == .run {
                c.set(.run, duration: max(2, f.timer)); return
            }
            if c.activity == .run { endTag(c) }
            endSocial(c)
            // A grove errand that ran out of time (or got interrupted) is over: never leave it hanging.
            if c.groveTask != nil { c.groveTask = nil; c.targetX = nil }
            if compact { Brain.decideCompact(c, in: self) }
            else if c.job != nil { c.set(.idle, duration: 0.2) } else if c.expedition != nil { expeditionDecide(c) }
            else if c.boost != nil || c.helping != nil { boostDecide(c) } else if c.mossTask != nil { mossDecide(c) }
            else if c.snowmanTask != nil { snowmanDecide(c) }
            else if ridingThroughDoor(c) { c.idleVariant = "look"; c.facing = door ?? c.facing; c.set(.idle, duration: rng.range(2, 4)) }
            else { Brain.decide(c, in: self) }
        }
    }

    /// Moves a grounded creature horizontally, handling screen walls and ledges. Returns false if it turned.
    @discardableResult
    func move(_ c: Creature, _ dt: Double, speed: Double, on support: Surface, ledgeTurnChance: Double = 0.65) -> Bool {
        let nx = c.pos.x + c.facing * speed * dt
        doorDecision(c)
        let (lo, hi) = horizontalLimits(for: c, atY: c.pos.y + 1)
        // The screen's edges are walls (only ever outward: something arriving through the doorway walks on in).
        if (nx < lo && nx < c.pos.x) || (nx > hi && nx > c.pos.x) {
            c.facing *= -1
            return false
        }
        // Stairs are taken in stride (a block up or down), and so is a neighbouring platform at the same height.
        if let s = stepAcross(c, from: support, toX: nx) {
            c.pos.x = nx; c.pos.y = s.y; c.groundOwner = s.ownerID
            c.edgeDecisionMade = false
            return true
        }
        if !support.supports(x: nx) && !c.edgeDecisionMade {
            c.edgeDecisionMade = true
            if rng.chance(ledgeTurnChance) {
                c.facing *= -1
                return false
            }
        }
        if support.supports(x: nx) { c.edgeDecisionMade = false }
        c.pos.x = nx
        return true
    }

    private func walk(_ c: Creature, _ dt: Double, on support: Surface) {
        if c.activity == .chase {
            if let cur = cursor, abs(cur.y - c.pos.y) < 260 { c.targetX = cur.x }
            if let tx = c.targetX {
                if abs(tx - c.pos.x) < 14 {
                    c.set(.react, duration: c.animationLength(for: .react) + 0.15)
                    emit(.poked(c.id))
                    return
                }
                c.facing = tx > c.pos.x ? 1 : -1
            }
        }
        if c.activity == .walk, let tx = c.targetX, c.expedition != nil || c.boost != nil || c.helping != nil || c.mossTask != nil || c.snowmanTask != nil || (compact && c.groveTask == nil) {
            // On an expedition: straight to the spot (off the edge, if that's where it is), no dithering at ledges.
            if abs(tx - c.pos.x) < 5 { c.targetX = nil; c.set(.idle, duration: 0.05); return }
            c.facing = tx > c.pos.x ? 1 : -1
            if !move(c, dt, speed: c.species.walkSpeed * 1.15, on: support, ledgeTurnChance: 0) { c.targetX = nil; c.set(.idle, duration: 0.3) }
            return
        }
        if c.activity == .walk, let tx = c.targetX, c.groveTask != nil || c.play != nil {
            if abs(tx - c.pos.x) < 8 {
                c.targetX = nil
                if c.groveTask != nil { arriveAtGrove(c) } else { c.set(.idle, duration: 4) }
                return
            }
            c.facing = tx > c.pos.x ? 1 : -1
            if !move(c, dt, speed: c.species.walkSpeed * 1.2, on: support, ledgeTurnChance: 1) { c.groveTask = nil; c.targetX = nil; c.set(.idle, duration: 1) }
            return
        }
        let speed = c.species.walkSpeed * (c.activity == .chase ? 1.6 : 1)
        if !move(c, dt, speed: speed, on: support, ledgeTurnChance: c.activity == .chase ? 1 : 0.65), c.activity == .chase {
            c.set(.idle, duration: 1)
        }
    }

    private func faceCursorIfNear(_ c: Creature) {
        guard let cur = cursor else { return }
        let dx = cur.x - c.pos.x
        if abs(dx) > 14 && abs(dx) < 260 && abs(cur.y - (c.pos.y + c.size.y / 2)) < 180 { c.facing = dx > 0 ? 1 : -1 }
    }

    private func integrateAirborne(_ c: Creature, _ dt: Double) {
        if updateGrapple(c, dt) { return }
        let prev = c.pos
        if c.gliding {
            // Floating on a leaf: gentle sink, a little sway, steady drift.
            c.vel.y = max(c.vel.y - gravity * 0.1 * dt, -60 + sin(clock * 3 + Double(c.id)) * 25)
            c.vel.x = c.facing * 150
        } else {
            c.vel.y = max(c.vel.y - gravity * dt, -maxFallSpeed)
        }
        var next = prev + c.vel * dt

        // Walls and ceiling of the screen we're on (crossing onto another monitor is allowed).
        let (lo, hi) = horizontalLimits(for: c, atY: next.y)
        if next.x < lo || next.x > hi {
            next.x = next.x.clamped(lo, hi)
            c.vel.x = -c.vel.x * 0.45
            c.facing = c.vel.x >= 0 ? 1 : -1
        }
        if let scr = screen(containingX: next.x, y: prev.y), next.y + c.size.y > scr.maxY {
            next.y = scr.maxY - c.size.y
            c.vel.y = min(c.vel.y, 0) * 0.3
        }

        // Land on the highest one-way platform crossed while falling (including friends' heads).
        if c.vel.y <= 0 {
            let landing = allSurfaces(excluding: c)
                .filter { prev.y >= $0.y - 0.5 && next.y <= $0.y && $0.supports(x: next.x) }
                .max { $0.y < $1.y }
            if let s = landing {
                let impact = -c.vel.y
                c.gliding = false
                if groveBounce(c, on: s, impact: impact) { return }
                next.y = s.y
                c.pos = next
                c.vel = .zero
                c.groundOwner = s.ownerID
                c.edgeDecisionMade = false
                emit(.landed(c.id, impact: impact))
                if let carrier = World.carrierID(s.ownerID) {
                    emit(.stacked(rider: c.id, carrier: carrier))
                    c.set(.react, duration: c.animationLength(for: .react) + 0.1)
                } else if impact > dizzyImpact {
                    c.set(.dizzy, duration: 1.9)
                    emit(.dizzy(c.id))
                } else {
                    c.set(.land, duration: impact > 900 ? max(0.3, c.animationLength(for: .land)) : 0.14)
                }
                return
            }
        }
        c.pos = next

        // Safety net: fell out of every screen (e.g. monitor unplugged). Respawn at the top of the main screen.
        if let lowest = screens.map(\.minY).min(), c.pos.y < lowest - 200, let main = screens.first {
            c.pos = Vec2(main.minX + main.w / 2, main.maxY - c.size.y - 10)
            c.vel = .zero
        }
    }

    // MARK: Flight

    /// Takes off toward a random surface (window top or floor) within reach.
    func startFlight(_ c: Creature, awayFrom: Vec2? = nil) {
        let options = surfaces.filter { s in
            guard s.width >= 40 else { return false }
            let x = c.pos.x.clamped(s.minX + 20, s.maxX - 20)
            if let a = awayFrom, (x - a.x) * (c.pos.x - a.x) < 0 { return false }
            return abs(x - c.pos.x) < 800 && abs(s.y - c.pos.y) > 20
        }
        guard let s = options.isEmpty ? nil : options[Int.random(in: 0..<options.count, using: &rng)] else {
            launch(c, velocity: Vec2(c.facing * 80, 500)); return
        }
        let inset = min(40, s.width / 2 - 1)
        var tx = rng.range(s.minX + inset, s.maxX - inset)
        if abs(tx - c.pos.x) > 800 { tx = c.pos.x.clamped(s.minX + inset, s.maxX - inset) }
        c.flyTarget = Vec2(tx, s.y)
        c.groundOwner = nil
        c.vel = Vec2(c.facing * 40, 220)
        c.facing = tx > c.pos.x ? 1 : -1
        endSocial(c)
        c.set(.fly, duration: 7)
        emit(.tookOff(c.id))
    }

    private func updateFlight(_ c: Creature, _ dt: Double) {
        guard let target = c.flyTarget else { c.set(.airborne); return }
        let aim = target + Vec2(0, 34)       // arrive from just above, then drop on
        let to = aim - c.pos
        let dist = to.length
        let speed = min(flySpeed, dist * 2.5 + 30)
        var desired = dist > 0.1 ? to * (speed / dist) : .zero
        desired.y += sin(clock * 7 + Double(c.id)) * 45  // fluttery bob
        let k = min(1, 3.2 * dt)
        c.vel = c.vel + (desired - c.vel) * k
        var next = c.pos + c.vel * dt
        let (lo, hi) = horizontalLimits(for: c, atY: next.y)
        next.x = next.x.clamped(lo, hi)
        if let scr = screen(containingX: next.x, y: next.y), next.y + c.size.y > scr.maxY { next.y = scr.maxY - c.size.y }
        c.pos = next
        if abs(c.vel.x) > 12 { c.facing = c.vel.x > 0 ? 1 : -1 }
        if dist < 16 || c.timer <= 0 {
            c.flyTarget = nil
            c.vel = Vec2(c.vel.x * 0.25, -60)
            c.set(.airborne)
        }
    }

    // MARK: Cursor startle & bumps

    private func checkStartle() {
        guard let cur = cursor, cursorSpeed > 2800 else { return }
        for c in creatures where c.isGrounded && !c.isAsleep && c.startleCooldown <= 0 && c.activity != .dizzy {
            let center = c.pos + Vec2(0, c.size.y * 0.4)
            guard (cur - center).length < 90 else { continue }
            c.startleCooldown = 6
            emit(.startled(c.id))
            endSocial(c)
            let away: Double = cur.x < c.pos.x ? 1 : -1
            if c.species.flies {
                c.facing = away
                startFlight(c, awayFrom: cur)
            } else {
                c.facing = away
                c.groundOwner = nil
                c.vel = Vec2(away * 200, 460)
                c.set(.airborne)
            }
        }
    }

    /// Two creatures walking into each other bounce apart.
    private func resolveBumps() {
        let movers = creatures.filter { [.walk, .run, .chase, .follow, .peek].contains($0.activity) && $0.isGrounded && $0.bumpCooldown <= 0 }
        guard movers.count > 1 else { return }
        for i in 0..<movers.count { for j in (i + 1)..<movers.count {
            let a = movers[i], b = movers[j]
            guard abs(a.pos.y - b.pos.y) < 3 else { continue }
            let dx = b.pos.x - a.pos.x
            guard abs(dx) < (a.size.x + b.size.x) * 0.2 else { continue }
            guard a.facing * dx > 0 && b.facing * -dx > 0 else { continue }  // heading toward each other
            if (a.social == .chaser && a.friendID == b.id) || (b.social == .chaser && b.friendID == a.id) { continue }
            // Most of the time they just squeeze past each other; sometimes they bonk.
            a.bumpCooldown = 2; b.bumpCooldown = 2
            guard rng.chance(bumpChance) else { continue }
            for (c, dir) in [(a, dx > 0 ? -1.0 : 1.0), (b, dx > 0 ? 1.0 : -1.0)] {
                endSocial(c)
                c.bumpCooldown = 4
                c.groundOwner = nil
                c.vel = Vec2(dir * 150, 340)
                c.set(.airborne)
            }
            emit(.bump(a.id, b.id))
        }}
    }

    // MARK: Queries

    /// Static surfaces plus the tops of other creatures' heads (so friends can stand on each other).
    func allSurfaces(excluding c: Creature) -> [Surface] {
        // A shelf only holds the Gremlet who put it up.
        var out = surfaces + shelfSurfaces.filter { $0.ownerID == World.shelfOwner(c.id) }
        if let deck = ferrySurface { out.append(deck) }
        if let cloud = liftSurface { out.append(cloud) }
        if !rails.isEmpty { out += cartSurfaces }
        // Mid-game of tag, runners leapfrog over heads instead of landing on them.
        let tagging = c.social == .runner || c.social == .chaser
        for o in creatures where !tagging && o !== c && o.groundOwner != c.carrierOwnerID
            && World.carrierID(o.groundOwner) == nil && ![.airborne, .fly, .dragged].contains(o.activity) {
            let half = o.size.x * 0.17
            out.append(Surface(ownerID: o.carrierOwnerID, kind: .creature, y: o.pos.y + o.species.headTop,
                               minX: o.pos.x - half, maxX: o.pos.x + half))
        }
        return out
    }

    func supportingSurface(for c: Creature) -> Surface? {
        let candidates = allSurfaces(excluding: c).filter { abs($0.y - c.pos.y) <= 2 && $0.supports(x: c.pos.x) }
        return candidates.first { $0.ownerID == c.groundOwner } ?? candidates.max { $0.y < $1.y }
    }

    func screen(containingX x: Double, y: Double) -> Rect? {
        screens.first { x >= $0.minX && x < $0.maxX && y >= $0.minY - 2 && y < $0.maxY }
            ?? screens.first { x >= $0.minX && x < $0.maxX }
    }

    /// Horizontal range a creature can move in at height y: its screen, extended across touching monitors.
    func horizontalLimits(for c: Creature, atY y: Double, inset: Bool = true) -> (Double, Double) {
        let half = inset ? c.size.x * 0.3 : 0
        guard let scr = screen(containingX: c.pos.x, y: y) ?? screens.first else { return (-.infinity, .infinity) }
        var lo = scr.minX, hi = scr.maxX
        var changed = true
        while changed {
            changed = false
            for s in screens where y >= s.minY - 2 && y < s.maxY {
                if abs(s.maxX - lo) < 1 && s.minX < lo { lo = s.minX; changed = true }
                if abs(s.minX - hi) < 1 && s.maxX > hi { hi = s.maxX; changed = true }
            }
        }
        // Full screen: a Gremlet in a bottom corner stays in it.
        if compact, let scr = screen(containingX: c.pos.x, y: y), abs(y - scr.minY) < 4 {
            if c.pos.x <= scr.minX + World.cornerZone + 1 { hi = min(hi, scr.minX + World.cornerZone) }
            else if c.pos.x >= scr.maxX - World.cornerZone - 1 { lo = max(lo, scr.maxX - World.cornerZone) }
        }
        // The doorway to the other screen, for a Gremlet that has decided to go through.
        if let d = door, let main = screens.first, y < main.maxY, c.doorChoice {
            if d > 0, abs(hi - main.maxX) < 1 { hi += World.doorDepth } else if d < 0, abs(lo - main.minX) < 1 { lo -= World.doorDepth }
        }
        return (lo + half, hi - half)
    }

    // MARK: The doorway to another screen

    /// Nearing the doorway, a Gremlet decides once whether to go through (most think twice, so a screen doesn't
    /// empty itself; just-arrived ones turn back).
    func doorDecision(_ c: Creature) {
        guard let d = door, let main = screens.first else { return }
        let dist = d > 0 ? main.maxX - c.pos.x : c.pos.x - main.minX
        if dist > 160 { if !c.doorForced { c.doorDecided = false }; return }
        guard c.facing * d > 0, dist < 80, !c.doorDecided else { return }
        c.doorDecided = true
        c.doorChoice = canUseDoor(c) && clock - c.arrivedAt > 10 && rng.chance(0.3)
    }

    func canUseDoor(_ c: Creature) -> Bool {
        c.job == nil && c.expedition == nil && c.stair == nil && c.rail == nil && c.building == nil && c.play == nil
            && c.groveTask == nil && c.homeUntil == nil && !c.isAsleep && c.boost == nil && c.helping == nil
    }

    /// Gremlets that have walked (or flown) out through the doorway; the platform layer hands them to the other screen.
    public func creaturesPastDoor() -> [Creature] {
        guard let d = door, let main = screens.first else { return [] }
        return creatures.filter { c in
            let out = d > 0 ? c.pos.x - main.maxX : main.minX - c.pos.x
            // Heading out, not just arrived from there (arrivals start a little outside the edge, walking in).
            let outward = c.isGrounded || c.activity == .crouch ? c.facing * d > 0 : c.vel.x * d > 0
            return out > c.size.x * 0.35 && outward && c.activity != .dragged && clock - c.arrivedAt > 1.5
                && c.groundOwner != World.ferryOwner
        }
    }

    /// A Gremlet arriving from the other screen through the doorway: walking in along the floor, or mid-air at
    /// `yFrac` of the screen's height with the speed it left at.
    @discardableResult
    public func arriveThroughDoor(_ sp: SpeciesInfo, yFrac: Double, vx: Double, vy: Double, airborne: Bool) -> Creature? {
        guard let main = screens.first else { return nil }
        let d = door ?? 1
        let x = d > 0 ? main.maxX + sp.pointSize.x * 0.4 : main.minX - sp.pointSize.x * 0.4
        let y = airborne ? main.minY + yFrac.clamped(0, 1) * max(1, main.h - 80) : main.minY
        let c = spawn(sp, at: Vec2(x, y))
        c.facing = -d
        c.arrivedAt = clock
        c.doorDecided = true; c.doorChoice = false; c.doorForced = false
        if airborne {
            c.vel = Vec2(max(160, abs(vx)) * -d, vy)
            c.set(.airborne)
        } else {
            c.groundOwner = -1
            c.vel = .zero
            c.set(.walk, duration: 2.5 + rng.range(0, 1))
        }
        return c
    }

    /// `gremlet cross`: a free Gremlet (the nearest to the door, or `id`) heads out through the doorway.
    @discardableResult
    public func sendThroughDoor(preferring id: Int? = nil) -> Bool {
        guard let d = door, let main = screens.first else { return false }
        let edge = d > 0 ? main.maxX : main.minX
        let free = creatures.filter { canUseDoor($0) && $0.isGrounded }
        let preferred = creature(id: id).flatMap { p in free.contains(where: { $0 === p }) ? p : nil }
        guard let c = preferred ?? free.min(by: { abs($0.pos.x - edge) < abs($1.pos.x - edge) }) else { return false }
        endSocial(c)
        c.visitingID = nil; c.tendX = nil; c.targetX = nil
        c.doorDecided = true; c.doorChoice = true; c.doorForced = true
        c.facing = d
        c.edgeDecisionMade = false
        c.set(.walk, duration: 60)
        return true
    }

    /// Launch velocity to land on `s` near x, arcing `apexExtra` above it.
    func ballistic(from p: Vec2, toX tx: Double, y: Double, apexExtra: Double = 40) -> Vec2 {
        let dh = y - p.y
        let apex = max(dh, 0) + apexExtra
        let vy = (2 * gravity * apex).squareRoot()
        let t = (vy + max(0, vy * vy - 2 * gravity * dh).squareRoot()) / gravity
        return Vec2((tx - p.x) / t, vy)
    }

    /// Picks a surface above the creature it can jump onto and returns the launch velocity, if any.
    func jumpTarget(for c: Creature) -> Vec2? {
        let maxH = maxJumpHeight * c.species.jumpPower
        let options = surfaces.filter { s in
            let dh = s.y - c.pos.y
            guard dh > 25, dh < maxH, s.width >= 40 else { return false }
            let tx = c.pos.x.clamped(s.minX + 16, s.maxX - 16)
            return abs(tx - c.pos.x) < maxJumpDistance
        }
        guard !options.isEmpty else { return nil }
        let s = options[Int.random(in: 0..<options.count, using: &rng)]
        let inset = min(60, s.width / 2 - 1)
        var tx = c.pos.x.clamped(s.minX + inset, s.maxX - inset)
        tx += rng.range(-20, 20)
        tx = tx.clamped(s.minX + 12, s.maxX - 12)
        return ballistic(from: c.pos, toX: tx, y: s.y)
    }

    /// Starts a jump with a short crouch for anticipation.
    func launch(_ c: Creature, velocity: Vec2) {
        c.pendingLaunch = velocity
        c.set(.crouch, duration: 0.16)
    }
}
