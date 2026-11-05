/// Utility-style decision making: when a creature finishes what it's doing, every candidate action
/// gets a score from the creature's needs and surroundings, and one is picked by weighted random choice.
/// New behaviors are added by appending a `Choice` here, with no state-machine rewiring needed.
struct Brain {
    struct Choice {
        let name: String
        let weight: Double
        let start: () -> Void
    }

    static func decide(_ c: Creature, in world: World) {
        var choices: [Choice] = []

        choices.append(Choice(name: "idle", weight: 1.0) {
            c.idleVariant = world.rng.chance(0.35) ? "look" : "idle"
            c.set(.idle, duration: world.rng.range(1.2, 3.5))
        })

        choices.append(Choice(name: "walk", weight: 1.5 * (0.4 + c.energy)) {
            c.facing = world.rng.chance(0.5) ? 1 : -1
            c.edgeDecisionMade = false
            c.set(.walk, duration: world.rng.range(1.5, 4.5))
        })

        choices.append(Choice(name: "hop", weight: 0.35 * c.energy) {
            let h = world.rng.range(30, 60)
            world.launch(c, velocity: Vec2(c.facing * world.rng.range(40, 110), (2 * world.gravity * h).squareRoot()))
        })

        if let target = world.jumpTarget(for: c) {
            choices.append(Choice(name: "jumpUp", weight: 1.3 * (0.3 + c.energy)) {
                world.launch(c, velocity: target)
            })
        }

        if c.energy < 0.55 {
            choices.append(Choice(name: "sleep", weight: (0.55 - c.energy) * 6 * c.species.sleepiness) {
                c.set(.yawn, duration: c.animationLength(for: .yawn))
            })
        }

        if let cur = world.cursor, abs(cur.y - c.pos.y) < 220, abs(cur.x - c.pos.x) > 40, abs(cur.x - c.pos.x) < 700 {
            choices.append(Choice(name: "chase", weight: 0.45 * c.energy) {
                c.targetX = cur.x
                c.facing = cur.x > c.pos.x ? 1 : -1
                c.set(.alert, duration: max(0.3, c.animationLength(for: .alert)))
                world.emit(.alert(c.id))
            })
        }

        let total = choices.reduce(0) { $0 + $1.weight }
        var roll = world.rng.range(0, total)
        for choice in choices {
            roll -= choice.weight
            if roll <= 0 { choice.start(); return }
        }
        choices.last?.start()
    }
}
