/// Utility-style decision making: when a creature finishes what it's doing, every candidate action
/// gets a score from the creature's needs (energy), its species (flies? sleepy? jumpy?) and its
/// surroundings (friends nearby, cursor nearby, windows above, screen edges), then one is picked by
/// weighted random choice. New behaviors are added by appending a `Choice`.
struct Brain {
    struct Choice {
        let name: String
        let weight: Double
        let start: () -> Void
    }

    static func decide(_ c: Creature, in world: World) {
        var choices: [Choice] = []
        let e = c.energy
        func add(_ name: String, _ w: Double, _ f: @escaping () -> Void) { if w > 0 { choices.append(Choice(name: name, weight: w, start: f)) } }

        // Focus mode: only quiet things. Mostly dozing, the odd stretch or slow amble.
        if world.calm {
            add("doze", 3.0) { c.set(.yawn, duration: c.animationLength(for: .yawn)) }
            add("idle", 1.0) { c.idleVariant = "idle"; c.set(.idle, duration: world.rng.range(3, 6)) }
            add("amble", 0.3) { c.facing = world.rng.chance(0.5) ? 1 : -1; c.set(.walk, duration: world.rng.range(1, 2)) }
            if world.canStartHobby(c) {
                add("hobby", 1.5) { if !world.startHobby(c, onWindow: false) { c.set(.idle, duration: 1) } }  // quiet work while you focus
            }
            pickAndStart(choices, world)
            return
        }

        // Sitting on a desktop icon: stay a while (it's tiny, so no wandering), look around, show off, then hop off.
        if world.iconUnder(c) != nil {
            add("sit", 3.0) { c.idleVariant = world.rng.chance(0.5) ? "look" : "idle"; c.set(.idle, duration: world.rng.range(2.5, 5)) }
            add("special", 0.4) { world.startSpecial(c) }
            add("dance", 0.25) { world.startDance(c, invite: false) }
            add("hopOff", 0.35) { world.launch(c, velocity: Vec2(c.facing * 120, 420)) }
            pickAndStart(choices, world)
            return
        }

        c.campfire = false
        // Up in a bonsai: sit and look around, nap in the foliage after dark or when sleepy, or hop down.
        if World.isBonsaiOwner(c.groundOwner) {
            add("sitInTree", 2.0) { c.idleVariant = world.rng.chance(0.5) ? "look" : "idle"; c.set(.idle, duration: world.rng.range(3, 7)) }
            if c.energy < 0.75 || world.isNight {
                add("napInTree", 3.0) { c.set(.sleep, duration: world.rng.range(40, 120)); world.emit(.fellAsleep(c.id)) }
            }
            add("hopDown", 0.4) { world.launch(c, velocity: Vec2(c.facing * 140, 380)) }
            pickAndStart(choices, world)
            return
        }
        world.bonsaiChoices(for: c, add: add)
        // In the middle of a game with a friend: wait for our turn.
        if c.play != nil { c.set(.idle, duration: 0.4); return }
        world.groveChoices(for: c, add: add)
        world.playChoices(for: c, add: add)
        world.ferryChoices(for: c, add: add)
        world.villageChoices(for: c, add: add)
        if world.spectacle == nil, c.job == nil {
            if world.bridgeCandidate(for: c) != nil { add("bridge", 0.7) { world.startBridge(c) } }
            if let a = world.grappleTarget(for: c) { add("grapple", 0.3 * (0.3 + e)) { world.startGrapple(c, to: a) } }
            if let d = world.glideTarget(for: c) { add("glide", 0.45) { world.startGlide(c, direction: d) } }
        }

        // --- Solo
        add("idle", 1.0) {
            c.idleVariant = world.rng.chance(0.35) ? "look" : "idle"
            c.set(.idle, duration: world.rng.range(1.2, 3.5))
        }
        add("walk", 1.3 * (0.4 + e)) {
            c.facing = world.rng.chance(0.5) ? 1 : -1
            c.edgeDecisionMade = false
            c.set(.walk, duration: world.rng.range(1.5, 4.5))
        }
        add("hop", 0.3 * e) {
            let h = world.rng.range(30, 60) * c.species.jumpPower
            world.launch(c, velocity: Vec2(c.facing * world.rng.range(40, 110), (2 * world.gravity * h).squareRoot()))
        }
        if let target = world.jumpTarget(for: c) {
            add("jumpUp", 1.1 * (0.3 + e)) { world.launch(c, velocity: target) }
        }
        if c.species.flies {
            add("fly", 0.8 * (0.3 + e)) { world.startFlight(c) }
        }
        add("special", 0.3 * (0.3 + e)) { world.startSpecial(c) }
        if let icon = world.iconToVisit(for: c) {
            add("icon", 0.25) { world.startIconVisit(c, icon) }
        }
        if let x = world.flowerToTend(for: c) {
            add("tend", 0.3) { world.startTending(c, x: x) }
        }
        if let busy = world.workerToVisit(from: c) {
            add("visit", 0.7) { world.startVisit(c, busy) }
        }
        if world.canStartHobby(c) {
            add("hobby", 0.5) { if !world.startHobby(c) { c.set(.idle, duration: 1) } }
        }
        add("dance", 0.1 * e) { world.startDance(c) }
        if c.energy < 0.55 {
            add("sleep", (0.55 - e) * 6 * c.species.sleepiness) { c.set(.yawn, duration: c.animationLength(for: .yawn)) }
        }
        if let (lo, hi) = Optional(world.horizontalLimits(for: c, atY: c.pos.y + 1, inset: false)),
           min(c.pos.x - lo, hi - c.pos.x) < 500, (c.groundOwner ?? 0) < 0 {
            add("peek", 0.18) { if !world.startPeek(c) { c.set(.idle, duration: 1) } }
        }

        // --- Cursor
        if let cur = world.cursor, abs(cur.y - c.pos.y) < 220 {
            let dx = abs(cur.x - c.pos.x)
            if dx > 40 && dx < 700 {
                add("chase", (0.4 + c.bond * 0.4) * e) {
                    c.targetX = cur.x
                    c.facing = cur.x > c.pos.x ? 1 : -1
                    c.set(.alert, duration: max(0.3, c.animationLength(for: .alert)))
                    world.emit(.alert(c.id))
                }
            }
            if dx < 240 {
                add("waveAtCursor", 0.5 + c.bond * 1.2) {
                    c.facing = cur.x > c.pos.x ? 1 : -1
                    c.set(.wave, duration: 1.3)
                }
            }
        }

        // --- Friends
        let friends = world.nearbyFriends(of: c)
        if !friends.isEmpty {
            let pick = { friends[Int.random(in: 0..<friends.count, using: &world.rng)] }
            let awake = friends.filter { !$0.isAsleep && $0.activity != .dizzy }
            if let dancer = friends.first(where: { $0.activity == .dance }) {
                add("joinDance", 1.4) {
                    c.facing = dancer.pos.x > c.pos.x ? 1 : -1
                    world.startDance(c, duration: max(1.5, dancer.timer), invite: false)
                }
            }
            if let f = awake.first(where: { world.clock - (c.lastGreet[$0.id] ?? -999) > 90 }) {
                add("greet", 1.2) { world.startGreet(c, f) }
            }
            if !awake.isEmpty {
                add("tag", 0.55 * e) {
                    let f = awake[Int.random(in: 0..<awake.count, using: &world.rng)]
                    if [.idle, .walk, .follow, .wave].contains(f.activity) { world.startTag(c, f) } else { world.startFollow(c, f) }
                }
                add("follow", 0.4) { world.startFollow(c, awake[Int.random(in: 0..<awake.count, using: &world.rng)]) }
            }
            if c.energy < 0.75, let sleeper = friends.first(where: { $0.activity == .sleep }) {
                add("napTogether", 1.6) { world.startNap(c, sleeper) }
            }
            // Stand on a friend's head (only on someone who isn't already carrying or riding).
            let canStack = World.carrierID(c.groundOwner) == nil && !world.creatures.contains { $0.groundOwner == c.carrierOwnerID }
            if canStack {
                let bases = friends.filter { f in
                    [.idle, .sleep].contains(f.activity) && World.carrierID(f.groundOwner) == nil
                        && !world.creatures.contains { $0.groundOwner == f.carrierOwnerID } && abs(f.pos.x - c.pos.x) < 260
                }
                if !bases.isEmpty {
                    add("stack", 0.18 * (0.3 + e)) { world.startStack(c, bases[Int.random(in: 0..<bases.count, using: &world.rng)]) }
                }
            }
            _ = pick
        }

        pickAndStart(choices, world)
    }

    static func pickAndStart(_ choices: [Choice], _ world: World) {
        let total = choices.reduce(0) { $0 + $1.weight }
        var roll = world.rng.range(0, total)
        for choice in choices {
            roll -= choice.weight
            if roll <= 0 { choice.start(); return }
        }
        choices.last?.start()
    }
}
