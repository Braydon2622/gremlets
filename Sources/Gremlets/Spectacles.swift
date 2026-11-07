import AppKit
import GremletsCore

/// Draws the grove and the special events: grove plants (growing, swaying, glowing), the Stormwyrm (body, health
/// bar, lightning), meteor streaks, star shards, thrown berries, the seed in games of catch, petals and banners.
/// All of it lives in the same click-through overlay as the Gremlets.
final class SpectacleRenderer {
    unowned let overlay: OverlayController
    let world: World

    private struct PlantLayer { let layer: CALayer; var glow: CALayer?; var key: String; var si: Int; var size: CGSize }
    private var plants: [Int: PlantLayer] = [:]
    private var snapUntil: [Int: CFTimeInterval] = [:]
    private var squashUntil: [Int: CFTimeInterval] = [:]
    private var boss: [CALayer] = []
    private var bossSI = -1
    private var hpBar: (root: CALayer, fill: CALayer, title: CATextLayer)?
    private var bolts: [CAShapeLayer] = []
    private var houses: [Int: (layer: CALayer, ground: CALayer, key: String)] = [:]
    private var bridgeLayers: [Int: (layer: CALayer, blocks: Int)] = [:]
    private var ropes: [Int: (line: CAShapeLayer, hook: CALayer)] = [:]
    private var nextHouseSmoke: [Int: CFTimeInterval] = [:]
    private var projectiles: [CALayer] = []
    private var balls: [CALayer] = []
    private var shards: [Int: CALayer] = [:]
    private var vignette: CALayer?
    private var emitter: CAEmitterLayer?
    private var headImages: [String: CGImage] = [:]
    private var bodyImages: [String: CGImage] = [:]
    /// Gremlets flung by a friend spin until they land.
    private(set) var spinning: [Int: CFTimeInterval] = [:]

    init(overlay: OverlayController, world: World) { self.overlay = overlay; self.world = world }

    private var screens: [OverlayController.ScreenRef] { overlay.screenRefs }

    private func local(_ p: Vec2) -> (Int, CGPoint)? {
        guard !screens.isEmpty else { return nil }
        let si = overlay.screenIndexFor(p)
        let o = screens[si].frame.origin
        return (si, CGPoint(x: p.x - o.x, y: p.y - o.y))
    }

    private func attach(_ l: CALayer, _ si: Int) {
        guard si < screens.count else { return }
        if l.superlayer !== screens[si].root { l.removeFromSuperlayer(); screens[si].root.addSublayer(l) }
        l.contentsScale = screens[si].scale
    }

    private func pixelLayer() -> CALayer {
        let l = CALayer()
        l.magnificationFilter = .nearest
        l.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "transform": NSNull(), "opacity": NSNull(), "hidden": NSNull()]
        return l
    }

    func rebuild() {
        for p in plants.values { p.layer.removeFromSuperlayer(); p.glow?.removeFromSuperlayer() }
        plants.removeAll()
    }

    // MARK: Frame

    private var gliders: [Int: CALayer] = [:]
    private var spirits: [(layer: CALayer, home: CGPoint, si: Int, born: CFTimeInterval, phase: Double)] = []
    private var nextSpirit = 0.0
    private var nextGust = CACurrentMediaTime() + Double.random(in: 120...240)
    private var pot: CALayer?

    func render() {
        renderGrove()
        renderGliders()
        renderSpirits()
        renderWind()
        renderCampfire()
        renderFerry()
        renderMerchant()
        renderVillage()
        renderBridges()
        renderRopes()
        renderSpectacle()
        renderBalls()
        let now = CACurrentMediaTime()
        for (id, _) in spinning where world.creatures.first(where: { $0.id == id })?.activity != .airborne || now - spinning[id]! > 3 {
            spinning[id] = nil
        }
    }

    // MARK: Grove

    private func renderGrove() {
        guard let floor = world.groveFloor else { return }
        let now = CACurrentMediaTime()
        for i in world.grove.plants.indices {
            let p = world.grove.plants[i]
            let base = world.grove.base(i, floor: floor), sz = world.grove.size(i)
            guard let (si, pt) = local(base) else { continue }
            let variant = p.kind == .snapjaw ? ((snapUntil[i] ?? 0) > now ? 1 : 0)
                : p.kind == .bouncecap ? ((squashUntil[i] ?? 0) > now ? 1 : 0) : 0
            let night = world.isNight
            let key = "\(p.kind.rawValue)-\(p.level)-\(p.berries)-\(variant)-\(night)-\(p.golden)"
            var pl = plants[i] ?? {
                let l = pixelLayer()
                l.anchorPoint = CGPoint(x: 0.5, y: 0)
                l.zPosition = -5
                // A gentle breeze: every plant sways a little, out of step with its neighbours.
                let sway = CABasicAnimation(keyPath: "transform.rotation.z")
                sway.fromValue = -0.018; sway.toValue = 0.018
                sway.duration = 2.6 + Double(i) * 0.37
                sway.autoreverses = true; sway.repeatCount = .infinity
                sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                if ![.skyvine, .wishwillow].contains(p.kind) { l.add(sway, forKey: "sway") }
                popIn(l)
                return PlantLayer(layer: l, glow: nil, key: "", si: -1, size: .zero)
            }()
            if pl.si != si { attach(pl.layer, si); pl.si = si; pl.glow.map { attach($0, si) } }
            if pl.key != key {
                pl.layer.contents = GroveArt.image(p, size: sz, variant: variant, night: night)
                pl.key = key
            }
            let size = CGSize(width: sz.x, height: sz.y)
            if pl.size != size { pl.layer.bounds = CGRect(origin: .zero, size: size); pl.size = size }
            pl.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y)
            // The lanternbloom lights up the dark.
            if p.kind == .lanternbloom {
                if night || world.spectacle != nil {
                    let g = pl.glow ?? {
                        let g = CALayer()
                        g.zPosition = -6
                        g.contents = GroveArt.glow(NSColor(red: 1, green: 0.8, blue: 0.35, alpha: 1), radius: 80)
                        let pulse = CABasicAnimation(keyPath: "opacity")
                        pulse.fromValue = 0.7; pulse.toValue = 1; pulse.duration = 1.8
                        pulse.autoreverses = true; pulse.repeatCount = .infinity
                        g.add(pulse, forKey: "pulse")
                        attach(g, si)
                        return g
                    }()
                    let r = sz.y * 1.3
                    g.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
                    g.position = CGPoint(x: pt.x + sz.x * 0.1, y: pt.y + sz.y * 0.74)
                    pl.glow = g
                } else if let g = pl.glow { g.removeFromSuperlayer(); pl.glow = nil }
            }
            plants[i] = pl
        }
        for i in plants.keys where i >= world.grove.plants.count {
            plants[i]?.layer.removeFromSuperlayer(); plants[i]?.glow?.removeFromSuperlayer(); plants[i] = nil
        }
    }

    func handle(_ events: [GroveEvent]) {
        guard let floor = world.groveFloor else { return }
        for e in events {
            switch e {
            case .fed:
                // A little shower of sparks over the whole grove: Claude's work feeding it.
                for i in world.grove.plants.indices {
                    let sz = world.grove.size(i)
                    if let (si, pt) = local(world.grove.base(i, floor: floor) + Vec2(0, sz.y * 0.6)) {
                        overlay.burst([Effects.sparkle, Effects.smallStar], si: si, at: pt, count: 3, dx: -30...30, dy: 10...50, duration: 1.2, stagger: 0.1)
                    }
                }
            case .planted(let i):
                if let l = plants[i]?.layer { boing(l, amount: 0.2) }
            case .levelUp(let i, let level):
                let p = world.grove.plants[i], sz = world.grove.size(i)
                if let (si, pt) = local(world.grove.base(i, floor: floor) + Vec2(0, sz.y * 0.5)) {
                    overlay.burst([Effects.sparkle, Effects.star, Effects.leaf, Effects.petal], si: si, at: pt, count: 16,
                                  dx: -sz.x...sz.x, dy: 20...(sz.y + 60), duration: 1.8, stagger: 0.04)
                }
                _ = (p, level)
                if let l = plants[i]?.layer { boing(l, amount: 0.25) }
            case .berryPicked(let i, _):
                if let l = plants[i]?.layer { boing(l, amount: 0.08) }
            case .bounce(let i, _):
                squashUntil[i] = CACurrentMediaTime() + 0.18
                if let l = plants[i]?.layer { boing(l, amount: 0.18) }
            case .wish(let i):
                if let (si, pt) = local(world.grove.base(i, floor: floor) + Vec2(0, world.grove.size(i).y)) {
                    overlay.burst([Effects.star, Effects.sparkle], si: si, at: pt, count: 10, dx: -60...60, dy: 20...120, duration: 2, stagger: 0.08)
                }
            case .chomp(let i):
                snapUntil[i] = CACurrentMediaTime() + 0.35
            case .wentHome(let n, _), .leftHome(let n, _):
                guard n < world.grove.village.count else { continue }
                let h = world.grove.village[n]
                if let (si, pt) = local(Vec2(floor.minX + h.x * floor.w, floor.minY + 8)) {
                    overlay.burst([Effects.dust, Effects.smallStar], si: si, at: pt, count: 3, dx: -16...16, dy: 0...18, duration: 0.5)
                }
                if let l = houses[n]?.layer { boing(l, amount: 0.05) }
            case .houseAdded(let n):
                guard n < world.grove.village.count else { continue }
                let h = world.grove.village[n]
                if let (si, pt) = local(Vec2(floor.minX + h.x * floor.w, floor.minY + h.h * 0.5)) {
                    overlay.burst([Effects.sparkle, Effects.star, Effects.dust], si: si, at: pt, count: 12, dx: -h.w * 0.6...h.w * 0.6, dy: -10...h.h * 0.7, duration: 1.2, stagger: 0.04)
                }
            }
        }
    }

    /// A floating caption over a grove plant.
    private func label(_ text: String, at i: Int, color: NSColor) {
        guard let floor = world.groveFloor, i < world.grove.plants.count else { return }
        let top = world.grove.base(i, floor: floor) + Vec2(0, world.grove.size(i).y + 24)
        guard let (si, pt) = local(top) else { return }
        floatText(text, si: si, at: pt, color: color, size: 15, rise: 50, duration: 3.2)
    }

    func floatText(_ text: String, si: Int, at pt: CGPoint, color: NSColor, size: CGFloat, rise: CGFloat, duration: Double) {
        guard si < screens.count else { return }
        let t = CATextLayer()
        t.string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .heavy),
            .foregroundColor: NSColor.white,
            .strokeColor: color.blended(withFraction: 0.5, of: .black) ?? .black,
            .strokeWidth: -3.5,
        ])
        t.contentsScale = screens[si].scale
        t.alignmentMode = .center
        let w = CGFloat(text.count) * size * 0.62 + 24
        t.bounds = CGRect(x: 0, y: 0, width: w, height: size * 1.5)
        t.position = pt
        t.zPosition = 90
        t.shadowOpacity = 0.6; t.shadowRadius = 3; t.shadowOffset = .zero; t.shadowColor = color.cgColor
        screens[si].root.addSublayer(t)
        let move = CABasicAnimation(keyPath: "position.y"); move.byValue = rise
        let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.1, 0.75, 1]
        let pop = CAKeyframeAnimation(keyPath: "transform.scale"); pop.values = [0.4, 1.15, 1]; pop.keyTimes = [0, 0.12, 0.2]
        let g = CAAnimationGroup(); g.animations = [move, fade, pop]; g.duration = duration
        g.isRemovedOnCompletion = false; g.fillMode = .forwards
        CATransaction.begin()
        CATransaction.setCompletionBlock { t.removeFromSuperlayer() }
        t.add(g, forKey: "float")
        CATransaction.commit()
    }

    private func boing(_ l: CALayer, amount: Double) {
        let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
        a.values = [1, 1 - amount, 1 + amount * 0.6, 1 - amount * 0.25, 1]
        a.duration = 0.45
        l.add(a, forKey: "boing")
    }

    private func popIn(_ l: CALayer) {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [0.1, 1.15, 0.95, 1]; a.duration = 0.6
        l.add(a, forKey: "pop")
    }

    // MARK: Storybook touches

    /// A big leaf held overhead while gliding.
    private func renderGliders() {
        var alive = Set<Int>()
        for c in world.creatures where c.gliding {
            guard let (si, pt) = local(c.pos + Vec2(0, c.size.y + 4)) else { continue }
            alive.insert(c.id)
            let l = gliders[c.id] ?? { let l = pixelLayer(); l.contents = StoryArt.gliderLeaf; l.bounds = CGRect(x: 0, y: 0, width: 48, height: 21); l.zPosition = 25; popIn(l); return l }()
            attach(l, si)
            l.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
            l.transform = CATransform3DMakeRotation(CGFloat(sin(CACurrentMediaTime() * 3 + Double(c.id)) * 0.12), 0, 0, 1)
            gliders[c.id] = l
        }
        for (id, l) in gliders where !alive.contains(id) { l.removeFromSuperlayer(); gliders[id] = nil }
    }

    /// Shy little night spirits drift around the grove and the village after dark, and hide when a Gremlet comes close.
    private func renderSpirits() {
        let now = CACurrentMediaTime()
        guard let floor = world.groveFloor else { return }
        if world.isNight && spirits.count < 6 && now >= nextSpirit {
            nextSpirit = now + Double.random(in: 4...10)
            var spots: [Vec2] = world.grove.plants.indices.map { world.grove.base($0, floor: floor) + Vec2(0, world.grove.size($0).y * 0.5) }
            spots += world.grove.village.map { Vec2(floor.minX + $0.x * floor.w, floor.minY + $0.h * 0.6) }
            if let home = spots.randomElement(), let (si, pt) = local(home + Vec2(Double.random(in: -60...60), Double.random(in: 0...50))) {
                let l = pixelLayer()
                l.contents = StoryArt.spirit(frame: 0)
                l.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
                l.zPosition = 22
                l.shadowColor = NSColor(red: 0.8, green: 1, blue: 0.7, alpha: 1).cgColor; l.shadowRadius = 6; l.shadowOpacity = 0.9; l.shadowOffset = .zero
                l.opacity = 0
                attach(l, si)
                spirits.append((l, pt, si, now, Double.random(in: 0...6)))
            }
        }
        var keep: [(layer: CALayer, home: CGPoint, si: Int, born: CFTimeInterval, phase: Double)] = []
        for s in spirits {
            let age = now - s.born
            let o = screens.indices.contains(s.si) ? screens[s.si].frame.origin : .zero
            let p = CGPoint(x: s.home.x + CGFloat(sin(age * 0.7 + s.phase) * 24), y: s.home.y + CGFloat(sin(age * 1.3 + s.phase) * 10))
            let world0 = Vec2(Double(p.x + o.x), Double(p.y + o.y))
            let shy = world.creatures.contains { $0.homeUntil == nil && ($0.pos + Vec2(0, $0.size.y / 2) - world0).length < 90 }
            let life = 18.0
            var alpha = min(1, age / 1.5) * min(1, (life - age) / 1.5)
            if shy || !world.isNight { alpha = 0 }
            s.layer.opacity = Float(max(0, alpha)) * 0.95
            s.layer.position = p
            s.layer.contents = StoryArt.spirit(frame: Int(age * 3) % 2)
            if age < life && !(shy && age > 2) { keep.append(s) } else { s.layer.removeFromSuperlayer() }
        }
        spirits = keep
    }

    /// Every few minutes a gentle gust of wind sweeps along the bottom of the screen.
    private func renderWind() {
        let now = CACurrentMediaTime()
        guard now >= nextGust, let floor = world.groveFloor, let (si, _) = local(Vec2(floor.minX + 10, floor.minY + 10)) else { return }
        nextGust = now + Double.random(in: 180...420)
        let dir: Double = Bool.random() ? 1 : -1
        world.gust(direction: dir)
        let size = screens[si].frame.size
        let images = world.month >= 9 && world.month <= 11 ? [Effects.leaf, Effects.leaf2] : [Effects.leaf, Effects.petal, Effects.leaf2]
        for i in 0..<22 {
            let l = CALayer()
            l.contents = images[i % images.count]
            l.magnificationFilter = .nearest
            l.bounds = CGRect(x: 0, y: 0, width: 15, height: 15)
            l.zPosition = 24
            attach(l, si)
            let y = CGFloat.random(in: 20...260) + (floor.minY - screens[si].frame.minY)
            let x0: CGFloat = dir > 0 ? -30 : size.width + 30, x1: CGFloat = dir > 0 ? size.width + 30 : -30
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = (0...6).map { k in
                let t = CGFloat(k) / 6
                let wob: CGFloat = CGFloat(sin(Double(t) * 9.0 + Double(i)) * 26.0)
                return NSValue(point: CGPoint(x: x0 + (x1 - x0) * t, y: y + wob))
            }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z"); spin.toValue = Double.random(in: 4...9) * dir
            let g = CAAnimationGroup(); g.animations = [move, spin]
            g.duration = Double.random(in: 3.2...4.6)
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.09
            g.fillMode = .both; g.isRemovedOnCompletion = false
            CATransaction.begin(); CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
            l.add(g, forKey: "gust")
            CATransaction.commit()
        }
        // The plants lean into it.
        for (_, p) in plants {
            let lean = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            lean.values = [0, -0.12 * dir, -0.05 * dir, -0.1 * dir, 0]
            lean.duration = 3
            p.layer.add(lean, forKey: "lean")
        }
    }

    /// A pot bubbling by the lanternbloom while Gremlets sit around the campfire.
    private func renderCampfire() {
        guard let floor = world.groveFloor, let i = world.grove.plant(of: .lanternbloom),
              world.creatures.contains(where: { $0.campfire }) else {
            if let p = pot { p.removeFromSuperlayer(); pot = nil }
            return
        }
        let b = world.grove.base(i, floor: floor), sz = world.grove.size(i)
        guard let (si, pt) = local(b + Vec2(sz.x * 0.8, 0)) else { return }
        let p = pot ?? { let l = pixelLayer(); l.contents = StoryArt.pot; l.anchorPoint = CGPoint(x: 0.5, y: 0); l.bounds = CGRect(x: 0, y: 0, width: 21, height: 18); l.zPosition = -1; popIn(l); return l }()
        attach(p, si)
        p.position = pt
        pot = p
        if Int(CACurrentMediaTime() * 10) % 9 == 0 {
            overlay.burst([Effects.steam], si: si, at: CGPoint(x: pt.x, y: pt.y + 18), count: 1, dx: -6...6, dy: 20...40, duration: 1.6)
        }
    }

    // MARK: Village, bridges, ropes

    private func renderVillage() {
        guard let floor = world.groveFloor else { return }
        let night = world.isNight
        for (n, h) in world.grove.village.enumerated() {
            guard let (si, pt) = local(Vec2(floor.minX + h.x * floor.w, floor.minY)) else { continue }
            if h.biome == "mine" { renderMine(n, h, si: si, at: pt); continue }
            if h.biome.hasPrefix("item:"), let item = VillageItem(rawValue: String(h.biome.dropFirst(5))) { renderItem(n, item, si: si, at: pt); continue }
            guard let b = Biome(rawValue: h.biome) else { continue }
            let stage = BuildArt.overgrowthStage(hours: h.builtAt.map { (Date().timeIntervalSince1970 - $0) / 3600 } ?? 0)
            let key = "\(h.biome)-\(h.blocks)-\(night)-\(si)-\(stage)"
            var entry = houses[n] ?? {
                let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = -4
                // A strip of its biome's ground under it, so each house sits in its own little patch of world.
                let g = pixelLayer(); g.anchorPoint = CGPoint(x: 0.5, y: 1); g.zPosition = -4.1
                popIn(l)
                return (l, g, "")
            }()
            attach(entry.layer, si); attach(entry.ground, si)
            if entry.key != key, let img = BuildArt.image(b, blocks: h.blocks, night: night, overgrowth: stage, seed: UInt64(n * 31 + 7)) {
                entry.layer.contents = img
                entry.layer.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                let gw = Int(h.w / 3) + 8
                let ground = IslandArt.body(b, widthPx: gw, seed: UInt64(n * 13 + 1))
                entry.ground.contents = ground
                entry.ground.bounds = CGRect(x: 0, y: 0, width: ground.width * 3, height: 6)   // only the top soil shows
                entry.ground.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 2.0 / Double(ground.height))
                entry.key = key
            }
            entry.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y)
            entry.ground.position = CGPoint(x: pt.x.rounded(), y: pt.y + 6)
            houses[n] = entry
            // Someone's home: smoke from the chimney, and the odd "z" drifting out.
            let now = CACurrentMediaTime()
            if world.creatures.contains(where: { $0.homeHouse == n }), now >= (nextHouseSmoke[n] ?? 0) {
                nextHouseSmoke[n] = now + 1.4
                let f = entry.layer.frame
                overlay.burst([Effects.smoke], si: si, at: CGPoint(x: f.minX + f.width * 0.55, y: f.maxY), count: 1, dx: 4...14, dy: 26...44, duration: 2.2)
                if Int(now) % 3 == 0 { overlay.burst([Effects.zzz], si: si, at: CGPoint(x: f.midX, y: f.maxY - 10), count: 1, dx: -10...10, dy: 20...34, duration: 1.8) }
            }
        }
        for n in houses.keys where n >= world.grove.village.count {
            houses[n]?.layer.removeFromSuperlayer(); houses[n]?.ground.removeFromSuperlayer(); houses[n] = nil
        }
    }

    private func renderMine(_ n: Int, _ h: House, si: Int, at pt: CGPoint) {
        let night = world.isNight
        let key = "mine-\(night)-\(si)"
        var entry = houses[n] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = -4; popIn(l); return (l, CALayer(), "") }()
        attach(entry.layer, si)
        if entry.key != key {
            let img = AdventureArt.mine(night: night)
            entry.layer.contents = img
            entry.layer.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
            entry.key = key
        }
        entry.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y)
        houses[n] = entry
        // Digging inside: puffs of dust and the odd spark from the entrance.
        let now = CACurrentMediaTime()
        if world.creatures.contains(where: { $0.homeHouse == n && $0.mining }), now >= (nextHouseSmoke[n] ?? 0) {
            nextHouseSmoke[n] = now + Double.random(in: 0.5...0.9)
            let door = CGPoint(x: pt.x - 0, y: pt.y + 12)
            overlay.burst([Effects.dust, Effects.smallStar], si: si, at: door, count: 1, dx: -20...20, dy: 4...20, duration: 0.6)
        }
    }

    private func renderItem(_ n: Int, _ item: VillageItem, si: Int, at pt: CGPoint) {
        let night = world.isNight
        let frame = item == .windmill ? Int(CACurrentMediaTime() * 2.5) % 2 : 0
        let key = "\(item.rawValue)-\(night)-\(frame)-\(si)"
        var entry = houses[n] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = -4.5; popIn(l); return (l, CALayer(), "") }()
        attach(entry.layer, si)
        if entry.key != key {
            let img = VillageArt.item(item, night: night, frame: frame)
            entry.layer.contents = img
            entry.layer.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
            entry.key = key
            if item == .lamps || item == .arch {
                entry.layer.shadowColor = NSColor(red: 1, green: 0.85, blue: 0.5, alpha: 1).cgColor
                entry.layer.shadowRadius = night ? 8 : 0; entry.layer.shadowOpacity = night ? 0.8 : 0; entry.layer.shadowOffset = .zero
            }
        }
        entry.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y)
        houses[n] = entry
        // The hot spring steams.
        let now = CACurrentMediaTime()
        if item == .spring, now >= (nextHouseSmoke[n] ?? 0) {
            nextHouseSmoke[n] = now + Double.random(in: 0.6...1.2)
            overlay.burst([Effects.steam], si: si, at: CGPoint(x: pt.x + .random(in: -40...40), y: pt.y + 14), count: 1, dx: -8...8, dy: 24...44, duration: 1.8)
        }
    }

    private var merchantLayer: CALayer?

    private func renderMerchant() {
        guard let m = world.merchant, let floor = world.groveFloor, let (si, pt) = local(Vec2(m.x, floor.minY)) else {
            if let l = merchantLayer { fade(l, to: 0, remove: true); merchantLayer = nil }
            return
        }
        let l = merchantLayer ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = 5; l.bounds = CGRect(x: 0, y: 0, width: 54, height: 78); popIn(l); return l }()
        attach(l, si)
        let walking = m.phase != .trading
        l.contents = VillageArt.merchant(frame: walking ? Int(CACurrentMediaTime() * 4) % 2 : 0)
        l.position = CGPoint(x: pt.x.rounded(), y: pt.y)
        l.transform = CATransform3DMakeScale(m.facing < 0 ? -1 : 1, 1, 1)
        merchantLayer = l
    }

    func handle(_ events: [MerchantEvent]) {
        for e in events {
            switch e {
            case .sold(let item):
                // A little shower of the gems it cost, over the merchant, then the new thing pops up with sparkles.
                if let m = world.merchant, let floor = world.groveFloor, let (si, pt) = local(Vec2(m.x, floor.minY + 80)) {
                    let gems = item.cost.flatMap { Array(repeating: AdventureArt.gem($0.key), count: $0.value) }
                    overlay.burst(gems, si: si, at: pt, count: gems.count, dx: -30...30, dy: 10...50, duration: 1.2, stagger: 0.08)
                }
                if let n = world.grove.village.lastIndex(where: { $0.biome == item.houseKey }), let floor = world.groveFloor {
                    let h = world.grove.village[n]
                    if let (si, pt) = local(Vec2(floor.minX + h.x * floor.w, floor.minY + h.h * 0.5)) {
                        overlay.burst([Effects.sparkle, Effects.star], si: si, at: pt, count: 10, dx: -h.w * 0.6...h.w * 0.6, dy: 0...h.h * 0.8, duration: 1.2, stagger: 0.04)
                    }
                }
            case .drink(let id):
                if let c = world.creatures.first(where: { $0.id == id }), let (si, pt) = local(c.pos + Vec2(0, c.size.y * 0.8)) {
                    overlay.burst([Effects.bubble, Effects.heart], si: si, at: pt, count: 2, dx: -10...10, dy: 14...30, duration: 1)
                }
            case .soak(let id):
                if let c = world.creatures.first(where: { $0.id == id }), let (si, pt) = local(c.pos + Vec2(0, c.size.y * 0.5)) {
                    overlay.burst([Effects.steam, Effects.heart, Effects.steam], si: si, at: pt, count: 6, dx: -24...24, dy: 20...60, duration: 2, stagger: 0.6)
                }
            case .arrived, .left:
                break
            }
        }
    }

    private var ferryLayer: CALayer?

    private func renderFerry() {
        guard let fe = world.ferry, let (si, pt) = local(fe.pos) else {
            if let l = ferryLayer { fade(l, to: 0, remove: true); ferryLayer = nil }
            return
        }
        let l = ferryLayer ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = 12; l.bounds = CGRect(x: 0, y: 0, width: 132, height: 102); popIn(l); return l }()
        attach(l, si)
        l.contents = AdventureArt.ferry(frame: Int(CACurrentMediaTime() * 10) % 2)
        // The deck (art row 9) lines up with the ferry's walkable surface.
        l.position = CGPoint(x: pt.x.rounded(), y: (pt.y + Ferry.deckHeight - 27).rounded())
        l.transform = CATransform3DMakeScale(fe.facing < 0 ? -1 : 1, 1, 1)
        ferryLayer = l
    }

    func handle(_ events: [AdventureEvent]) {
        for e in events {
            switch e {
            case .gemFound(let g, let id):
                if let c = world.creatures.first(where: { $0.id == id }), let (si, pt) = local(c.pos + Vec2(0, c.size.y + 6)) {
                    overlay.burst([AdventureArt.gem(g)], si: si, at: pt, count: 1, dx: 0...0, dy: 30...40, duration: 1.8)
                    overlay.burst([Effects.sparkle, Effects.smallStar], si: si, at: pt, count: g == .starstone ? 10 : 4, dx: -24...24, dy: 0...40, duration: 0.9)
                }
            case .pebble(let id):
                if let c = world.creatures.first(where: { $0.id == id }), let (si, pt) = local(c.pos + Vec2(0, c.size.y + 6)) {
                    overlay.burst([AdventureArt.pebble], si: si, at: pt, count: 1, dx: 0...0, dy: 20...26, duration: 1.2)
                }
            case .digging, .ferryArrived, .ferryLeft:
                break
            }
        }
    }

    /// Lanterns rising from the village and the grove, one per Claude task finished today.
    private func releaseLanterns() {
        guard let floor = world.groveFloor, let (si, _) = local(Vec2(floor.minX + 10, floor.minY + 10)) else { return }
        let count = max(8, min(40, world.tasksToday))
        var spots: [Double] = world.grove.village.map { floor.minX + $0.x * floor.w }
        spots += world.grove.plants.indices.map { world.grove.base($0, floor: floor).x }
        if spots.isEmpty { spots = [floor.minX + floor.w / 2] }
        let o = screens[si].frame.origin
        for i in 0..<count {
            let x0 = spots[i % spots.count] + Double.random(in: -40...40)
            let start = CGPoint(x: x0 - o.x, y: floor.minY - o.y + 30)
            let l = CALayer()
            l.contents = AdventureArt.lantern
            l.magnificationFilter = .nearest
            l.bounds = CGRect(x: 0, y: 0, width: 21, height: 27)
            l.zPosition = 20
            l.shadowColor = NSColor(red: 1, green: 0.7, blue: 0.3, alpha: 1).cgColor; l.shadowRadius = 10; l.shadowOpacity = 0.9; l.shadowOffset = .zero
            attach(l, si)
            let rise = CAKeyframeAnimation(keyPath: "position")
            let h = CGFloat(Double.random(in: 0.55...0.9)) * screens[si].frame.height
            rise.values = (0...8).map { k -> NSValue in
                let t = CGFloat(k) / 8
                let sway = CGFloat(sin(Double(t) * 7 + Double(i))) * 22
                return NSValue(point: CGPoint(x: start.x + sway + t * 40, y: start.y + h * t))
            }
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.1, 0.7, 1]
            let g = CAAnimationGroup(); g.animations = [rise, fade]
            g.duration = Double.random(in: 14...22)
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.6
            g.fillMode = .both; g.isRemovedOnCompletion = false
            CATransaction.begin(); CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
            l.add(g, forKey: "rise")
            CATransaction.commit()
        }
    }

    private func renderBridges() {
        var alive = Set<Int>()
        for b in world.bridges where b.blocks > 0 {
            alive.insert(b.id)
            let (lo, hi) = b.builtSpan
            guard let (si, pt) = local(Vec2(lo, b.y)) else { continue }
            var e = bridgeLayers[b.id] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0, y: 1); l.zPosition = -0.3; return (l, -1) }()
            attach(e.layer, si)
            if e.blocks != b.blocks {
                let img = BridgeArt.image(blocks: b.blocks, fromLeft: b.fromLeft, total: b.totalBlocks)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                e.blocks = b.blocks
            }
            e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y + 9)   // rails stick up above the deck
            _ = hi
            bridgeLayers[b.id] = e
        }
        for (id, e) in bridgeLayers where !alive.contains(id) { e.layer.removeFromSuperlayer(); bridgeLayers[id] = nil }
    }

    private func renderRopes() {
        var alive = Set<Int>()
        for c in world.creatures {
            guard let a = c.grapple, let (si, hand) = local(c.pos + Vec2(c.facing * c.size.x * 0.15, c.size.y * 0.6)) else { continue }
            alive.insert(c.id)
            let o = screens[si].frame.origin
            let anchor = CGPoint(x: a.x - o.x, y: a.y - o.y)
            let r = ropes[c.id] ?? {
                let line = CAShapeLayer()
                line.strokeColor = NSColor(red: 0.85, green: 0.72, blue: 0.5, alpha: 1).cgColor
                line.lineWidth = 2; line.fillColor = nil; line.zPosition = 20
                line.actions = ["path": NSNull()]
                let hook = pixelLayer(); hook.contents = BridgeArt.hook; hook.bounds = CGRect(x: 0, y: 0, width: 15, height: 12)
                hook.anchorPoint = CGPoint(x: 0.5, y: 0); hook.zPosition = 21
                return (line, hook)
            }()
            attach(r.line, si); attach(r.hook, si)
            let path = CGMutablePath()
            path.move(to: hand)
            // A little sag in the rope.
            let mid = CGPoint(x: (hand.x + anchor.x) / 2, y: (hand.y + anchor.y) / 2 - 10)
            path.addQuadCurve(to: anchor, control: mid)
            r.line.path = path
            r.hook.position = anchor
            ropes[c.id] = r
        }
        for (id, r) in ropes where !alive.contains(id) { r.line.removeFromSuperlayer(); r.hook.removeFromSuperlayer(); ropes[id] = nil }
    }

    func handle(_ events: [BuildEvent]) {
        for e in events {
            switch e {
            case .bridgeBlock(let p, _):
                if let (si, pt) = local(p) { overlay.burst([Effects.dust, Effects.smallStar], si: si, at: pt, count: 2, dx: -10...10, dy: -6...10, duration: 0.4) }
            case .bridgeDone(let id):
                if let b = world.bridges.first(where: { $0.id == id }), let (si, pt) = local(Vec2((b.minX + b.maxX) / 2, b.y + 10)) {
                    overlay.burst([Effects.sparkle, Effects.star], si: si, at: pt, count: 8, dx: -60...60, dy: 0...40, duration: 0.9, stagger: 0.03)
                }
            case .bridgeCrumbled(let lo, let hi, let y):
                var x = lo
                while x < hi {
                    if let (si, pt) = local(Vec2(x, y)) {
                        overlay.burst([BridgeArt.plank, Effects.dust], si: si, at: pt, count: 1, dx: -10...10, dy: -160 ... -60, duration: 0.9)
                    }
                    x += Bridge.blockWidth
                }
            case .grapple:
                break
            case .houseAdded:
                break
            }
        }
    }

    // MARK: Spectacles

    private func renderSpectacle() {
        guard let s = world.spectacle else {
            if !boss.isEmpty { boss.forEach { $0.removeFromSuperlayer() }; boss.removeAll() }
            bolts.forEach { $0.removeFromSuperlayer() }; bolts.removeAll()
            projectiles.forEach { $0.isHidden = true }
            for (_, l) in shards { l.removeFromSuperlayer() }; shards.removeAll()
            hideHP()
            if let v = vignette { fade(v, to: 0, remove: true); vignette = nil }
            return
        }
        if s.isBoss { renderBoss(s) }
        renderProjectiles(s)
        renderShards(s)
    }

    private func renderBoss(_ s: Spectacle) {
        let segs = s.segments
        if segs.isEmpty {
            boss.forEach { $0.removeFromSuperlayer() }; boss.removeAll()
        } else {
            while boss.count < segs.count {
                let l = pixelLayer()
                l.zPosition = 60 - Double(boss.count) * 0.1
                // An electric glow around the whole body.
                l.shadowColor = NSColor(red: 0.55, green: 0.9, blue: 1, alpha: 1).cgColor
                l.shadowRadius = 9; l.shadowOpacity = 0.75; l.shadowOffset = .zero
                boss.append(l)
            }
            let hurt = s.hurt > 0.55
            let open = s.diving || !s.bolts.isEmpty
            for (i, p) in segs.enumerated().reversed() {
                guard let (si, pt) = local(p) else { continue }
                let l = boss[i]
                attach(l, si)
                let img: CGImage
                if i == 0 {
                    let k = "\(open)-\(hurt)"
                    img = headImages[k] ?? { let im = BossArt.head(open: open, hurt: hurt); headImages[k] = im; return im }()
                } else {
                    let k = "\(i)-\(hurt)"
                    img = bodyImages[k] ?? { let im = BossArt.body(i, hurt: hurt); bodyImages[k] = im; return im }()
                }
                if l.contents == nil || (l.contents as! CGImage) !== img { l.contents = img }
                let w = Double(img.width) * artScale, h = Double(img.height) * artScale
                l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                // Bob each segment a little out of phase, so the body ripples.
                let bob = sin(s.age * 3.2 - Double(i) * 0.7) * (i == 0 ? 3 : 9)
                l.position = CGPoint(x: pt.x.rounded(), y: (pt.y + bob).rounded())
                var t = CATransform3DIdentity
                if i == 0 {
                    t = CATransform3DScale(t, s.facing < 0 ? -1 : 1, 1, 1)
                    if i + 1 < segs.count {
                        let d = segs[0] - segs[1]
                        let ang = atan2(d.y, abs(d.x)) * 0.5
                        t = CATransform3DRotate(t, s.facing < 0 ? -ang : ang, 0, 0, 1)
                    }
                }
                l.transform = t
                l.opacity = s.phase == .intro ? Float(min(1, s.age / 1.2)) : 1
            }
        }
        // Dark edges for drama while it's here.
        if vignette == nil, let floor = world.groveFloor, let (si, _) = local(Vec2(floor.x + floor.w / 2, floor.y + floor.h / 2)) {
            let v = CAGradientLayer()
            v.type = .radial
            v.colors = [NSColor.clear.cgColor, NSColor(red: 0.04, green: 0.06, blue: 0.16, alpha: 0.72).cgColor]
            v.startPoint = CGPoint(x: 0.5, y: 0.5); v.endPoint = CGPoint(x: 1.05, y: 1.05)
            v.frame = CGRect(origin: .zero, size: screens[si].frame.size)
            v.zPosition = -20
            v.opacity = 0
            attach(v, si)
            fade(v, to: 1, remove: false)
            vignette = v
        }
        renderBolts(s)
        renderHP(s)
    }

    private func renderBolts(_ s: Spectacle) {
        while bolts.count < s.bolts.count {
            let l = CAShapeLayer()
            l.fillColor = nil
            l.lineCap = .round; l.lineJoin = .round
            l.zPosition = 55
            l.shadowColor = NSColor(red: 0.6, green: 0.95, blue: 1, alpha: 1).cgColor
            l.shadowRadius = 8; l.shadowOpacity = 1; l.shadowOffset = .zero
            l.actions = ["path": NSNull(), "lineWidth": NSNull(), "opacity": NSNull(), "strokeColor": NSNull()]
            bolts.append(l)
        }
        for (i, l) in bolts.enumerated() {
            guard i < s.bolts.count, let (si, top) = local(Vec2(s.bolts[i].x, s.bolts[i].fromY)) else { l.removeFromSuperlayer(); continue }
            let b = s.bolts[i]
            attach(l, si)
            let bottom = top.y - (b.fromY - b.toY)
            let path = CGMutablePath()
            path.move(to: top)
            // Jagged zig-zag, re-rolled every frame so it crackles.
            let steps = 9
            for n in 1...steps {
                let t = CGFloat(n) / CGFloat(steps)
                let jitter = n == steps ? 0 : CGFloat.random(in: -22...22) * (b.striking ? 1 : 0.4)
                path.addLine(to: CGPoint(x: top.x + jitter, y: top.y + (bottom - top.y) * t))
            }
            l.path = path
            if b.striking {
                l.strokeColor = NSColor.white.cgColor
                l.lineWidth = 6
                l.opacity = Float.random(in: 0.75...1)
                l.lineDashPattern = nil
            } else {
                l.strokeColor = NSColor(red: 0.6, green: 0.95, blue: 1, alpha: 1).cgColor
                l.lineWidth = 2
                l.lineDashPattern = [6, 10]
                l.opacity = Float(0.25 + 0.5 * abs(sin(b.age * 18)))
            }
        }
        if bolts.count > s.bolts.count {
            for l in bolts[s.bolts.count...] { l.removeFromSuperlayer() }
            bolts.removeLast(bolts.count - s.bolts.count)
        }
    }

    private func renderHP(_ s: Spectacle) {
        guard let floor = world.groveFloor, let (si, _) = local(Vec2(floor.x + floor.w / 2, floor.maxY - 10)) else { return }
        let width: CGFloat = min(520, screens[si].frame.width * 0.45)
        let bar = hpBar ?? {
            let root = CALayer()
            root.bounds = CGRect(x: 0, y: 0, width: width, height: 20)
            root.backgroundColor = NSColor(red: 0.08, green: 0.1, blue: 0.2, alpha: 0.85).cgColor
            root.cornerRadius = 10
            root.borderColor = NSColor(red: 0.6, green: 0.95, blue: 1, alpha: 0.9).cgColor
            root.borderWidth = 2
            root.zPosition = 95
            let fill = CALayer()
            fill.anchorPoint = .zero
            fill.frame = CGRect(x: 3, y: 3, width: width - 6, height: 14)
            fill.cornerRadius = 7
            fill.backgroundColor = NSColor(red: 0.55, green: 0.85, blue: 1, alpha: 1).cgColor
            root.addSublayer(fill)
            let title = CATextLayer()
            title.string = NSAttributedString(string: "THE STORMWYRM", attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .black), .foregroundColor: NSColor.white,
                .strokeColor: NSColor(red: 0.1, green: 0.15, blue: 0.35, alpha: 1), .strokeWidth: -4, .kern: 3])
            title.alignmentMode = .center
            title.bounds = CGRect(x: 0, y: 0, width: width, height: 24)
            title.position = CGPoint(x: width / 2, y: 36)
            title.contentsScale = screens[si].scale
            root.addSublayer(title)
            root.opacity = 0
            attach(root, si)
            fade(root, to: 1, remove: false)
            return (root, fill, title)
        }()
        hpBar = bar
        let topInset: CGFloat = screens[si].frame.height - CGFloat(floor.maxY - Double(screens[si].frame.minY))
        bar.root.position = CGPoint(x: screens[si].frame.width / 2, y: screens[si].frame.height - topInset - 70)
        CATransaction.begin(); CATransaction.setDisableActions(false); CATransaction.setAnimationDuration(0.25)
        bar.fill.bounds.size.width = max(0, (width - 6) * s.hpFraction)
        CATransaction.commit()
        if s.phase == .outro { hideHP() }
    }

    private func hideHP() {
        if let b = hpBar { fade(b.root, to: 0, remove: true); hpBar = nil }
    }

    private func renderProjectiles(_ s: Spectacle) {
        while projectiles.count < s.projectiles.count { projectiles.append(pixelLayer()) }
        for (i, l) in projectiles.enumerated() {
            guard i < s.projectiles.count, let (si, pt) = local(s.projectiles[i].pos) else { l.isHidden = true; continue }
            attach(l, si)
            let img = s.projectiles[i].kind == .berry ? BossArt.berry : BossArt.pebble
            l.contents = img
            l.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            l.position = pt
            l.zPosition = 70
            l.transform = CATransform3DMakeRotation(CGFloat(s.projectiles[i].age * 12), 0, 0, 1)
            l.isHidden = false
        }
    }

    private func renderShards(_ s: Spectacle) {
        var alive = Set<Int>()
        for sh in s.shards {
            alive.insert(sh.id)
            guard let (si, pt) = local(sh.pos + Vec2(0, 10)) else { continue }
            let l = shards[sh.id] ?? {
                let l = pixelLayer()
                l.contents = BossArt.shard
                l.bounds = CGRect(x: 0, y: 0, width: 15, height: 15)
                l.zPosition = 40
                l.shadowColor = NSColor.yellow.cgColor; l.shadowRadius = 6; l.shadowOpacity = 0.9; l.shadowOffset = .zero
                let tw = CABasicAnimation(keyPath: "transform.scale")
                tw.fromValue = 0.8; tw.toValue = 1.25; tw.duration = 0.5; tw.autoreverses = true; tw.repeatCount = .infinity
                l.add(tw, forKey: "twinkle")
                shards[sh.id] = l
                return l
            }()
            attach(l, si)
            l.position = pt
        }
        for (id, l) in shards where !alive.contains(id) { l.removeFromSuperlayer(); shards[id] = nil }
    }

    private func renderBalls() {
        while balls.count < world.playBalls.count { balls.append(pixelLayer()) }
        for (i, l) in balls.enumerated() {
            guard i < world.playBalls.count, let (si, pt) = local(world.playBalls[i].pos) else { l.isHidden = true; continue }
            attach(l, si)
            l.contents = BossArt.seedBall
            l.bounds = CGRect(x: 0, y: 0, width: 15, height: 15)
            l.position = pt
            l.zPosition = 30
            l.transform = CATransform3DMakeRotation(CGFloat(world.playBalls[i].age * 9), 0, 0, 1)
            l.isHidden = false
        }
    }

    func handle(_ events: [SpectacleEvent]) {
        for e in events {
            switch e {
            case .started(let k):
                if k == .festival { startEmitter(petals: true) }
                if k == .lanterns { releaseLanterns() }
            case .roar:
                if let h = world.spectacle?.head, let (si, pt) = local(h) {
                    overlay.burst([Effects.cloud, Effects.smallStar], si: si, at: pt, count: 6, dx: -90...90, dy: -40...60, duration: 0.9)
                }
            case .hit(let p, let dmg, _):
                if let (si, pt) = local(p) {
                    overlay.burst([Effects.star, Effects.smallStar, Effects.sparkle], si: si, at: pt, count: Int(dmg) + 2, dx: -50...50, dy: -30...50, duration: 0.7)
                    floatText("-\(Int(dmg))", si: si, at: CGPoint(x: pt.x + .random(in: -20...20), y: pt.y + 30), color: .systemOrange, size: 18, rise: 40, duration: 0.9)
                }
            case .chomp(let i):
                snapUntil[i] = CACurrentMediaTime() + 0.4
                if let floor = world.groveFloor, i < world.grove.plants.count {
                    let top = world.grove.base(i, floor: floor) + Vec2(0, world.grove.size(i).y)
                    if let (si, pt) = local(top) { floatText("CHOMP!", si: si, at: pt, color: .systemGreen, size: 20, rise: 36, duration: 1.1) }
                }
            case .boltWarn:
                break
            case .boltStrike(let x, let y):
                if let (si, pt) = local(Vec2(x, y)) {
                    flash(si)
                    overlay.burst([Effects.sparkle, Effects.smallStar, Effects.dust], si: si, at: pt, count: 10, dx: -70...70, dy: 0...60, duration: 0.7)
                }
            case .throwBerry:
                break
            case .shardCollected(let p, _):
                if let (si, pt) = local(p + Vec2(0, 14)) {
                    overlay.burst([Effects.sparkle, Effects.star], si: si, at: pt, count: 6, dx: -26...26, dy: 10...50, duration: 0.9)
                    floatText("+✦", si: si, at: CGPoint(x: pt.x, y: pt.y + 26), color: .systemYellow, size: 16, rise: 30, duration: 1)
                }
            case .meteor(let from, let to):
                meteor(from, to)
            case .ended(let k, let won):
                stopEmitter()
                _ = (k, won)
            }
        }
    }

    func handleWorld(_ e: WorldEvent) {
        switch e {
        case .tossed(let id, _):
            spinning[id] = CACurrentMediaTime()
        case .highFive(let a, let b):
            guard let ca = world.creatures.first(where: { $0.id == a }), let cb = world.creatures.first(where: { $0.id == b }) else { return }
            let mid = (ca.pos + cb.pos) * 0.5 + Vec2(0, ca.size.y * 0.7)
            if let (si, pt) = local(mid) {
                overlay.burst([Effects.sparkle, Effects.star, Effects.smallStar], si: si, at: pt, count: 10, dx: -50...50, dy: -10...60, duration: 0.8)
                floatText("✋", si: si, at: CGPoint(x: pt.x, y: pt.y + 10), color: .systemPink, size: 22, rise: 24, duration: 0.8)
            }
        case .caught(let id):
            if let c = world.creatures.first(where: { $0.id == id }), let (si, pt) = local(c.pos + Vec2(0, c.size.y * 0.8)) {
                overlay.burst([Effects.smallStar], si: si, at: pt, count: 2, dx: -16...16, dy: 6...20, duration: 0.5)
            }
        default: break
        }
    }

    // MARK: Effects

    private func banner(_ k: SpectacleKind) {
        switch k {
        case .boss: banner(text: "THE STORMWYRM", sub: "Throw berries! Bounce! Click it!", color: NSColor(red: 0.55, green: 0.85, blue: 1, alpha: 1))
        case .meteors: banner(text: "METEOR SHOWER", sub: "Catch the falling star shards", color: .systemYellow)
        case .festival: banner(text: "BLOOM FESTIVAL", sub: "A grove plant reached full bloom!", color: .systemPink)
        case .lanterns: break
        }
    }

    private func banner(text: String, sub: String, color: NSColor) {
        guard let floor = world.groveFloor, let (si, _) = local(Vec2(floor.x + floor.w / 2, floor.y + floor.h / 2)) else { return }
        let size = screens[si].frame.size
        floatText(text, si: si, at: CGPoint(x: size.width / 2, y: size.height * 0.62), color: color, size: 54, rise: 18, duration: 3.4)
        floatText(sub, si: si, at: CGPoint(x: size.width / 2, y: size.height * 0.62 - 52), color: color, size: 20, rise: 18, duration: 3.4)
    }

    private func flash(_ si: Int) {
        guard si < screens.count else { return }
        let l = CALayer()
        l.frame = CGRect(origin: .zero, size: screens[si].frame.size)
        l.backgroundColor = NSColor(red: 0.85, green: 0.97, blue: 1, alpha: 1).cgColor
        l.zPosition = 80
        l.opacity = 0
        screens[si].root.addSublayer(l)
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, 0.22, 0.05, 0.14, 0]; a.duration = 0.35
        a.isRemovedOnCompletion = false; a.fillMode = .forwards
        CATransaction.begin(); CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(a, forKey: "flash")
        CATransaction.commit()
    }

    private func meteor(_ from: Vec2, _ to: Vec2) {
        guard let (si, a) = local(from) else { return }
        let o = screens[si].frame.origin
        let b = CGPoint(x: to.x - o.x, y: to.y - o.y)
        let l = CAGradientLayer()
        l.colors = [NSColor.white.cgColor, NSColor(red: 1, green: 0.9, blue: 0.5, alpha: 0.6).cgColor, NSColor.clear.cgColor]
        l.startPoint = CGPoint(x: 0, y: 0.5); l.endPoint = CGPoint(x: 1, y: 0.5)
        l.bounds = CGRect(x: 0, y: 0, width: 140, height: 4)
        l.cornerRadius = 2
        l.anchorPoint = CGPoint(x: 0, y: 0.5)
        l.zPosition = -10
        l.transform = CATransform3DMakeRotation(atan2(a.y - b.y, a.x - b.x), 0, 0, 1)
        l.shadowColor = NSColor.yellow.cgColor; l.shadowRadius = 5; l.shadowOpacity = 1; l.shadowOffset = .zero
        screens[si].root.addSublayer(l)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: a); move.toValue = NSValue(point: b)
        let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.1, 0.7, 1]
        let g = CAAnimationGroup(); g.animations = [move, fade]; g.duration = Double.random(in: 0.6...1.0)
        g.isRemovedOnCompletion = false; g.fillMode = .forwards
        CATransaction.begin(); CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(g, forKey: "meteor")
        CATransaction.commit()
    }

    private func startEmitter(petals: Bool) {
        stopEmitter()
        guard let floor = world.groveFloor, let (si, _) = local(Vec2(floor.x + floor.w / 2, floor.y + floor.h / 2)) else { return }
        let size = screens[si].frame.size
        let e = CAEmitterLayer()
        // Only over the grove, low down: a gentle drift, not a takeover.
        e.emitterPosition = CGPoint(x: size.width / 2, y: 260)
        e.emitterSize = CGSize(width: size.width * 0.75, height: 1)
        e.emitterShape = .line
        e.zPosition = 85
        let images = petals ? [Effects.petal, Effects.leaf, Effects.sparkle] : [Effects.star, Effects.sparkle, Effects.smallStar]
        e.emitterCells = images.map { img in
            let c = CAEmitterCell()
            c.contents = img
            c.birthRate = petals ? 1.2 : 3
            c.lifetime = 7
            c.velocity = 25; c.velocityRange = 15
            c.emissionLongitude = -.pi / 2; c.emissionRange = 0.5
            c.yAcceleration = -30
            c.spin = 1.2; c.spinRange = 2.5
            c.scale = 3; c.scaleRange = 1
            c.magnificationFilter = CALayerContentsFilter.nearest.rawValue
            return c
        }
        attach(e, si)
        emitter = e
    }

    private func stopEmitter() {
        guard let e = emitter else { return }
        e.birthRate = 0
        emitter = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { e.removeFromSuperlayer() }
    }

    private func fade(_ l: CALayer, to: Float, remove: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.6)
        if remove { CATransaction.setCompletionBlock { l.removeFromSuperlayer() } }
        l.opacity = to
        CATransaction.commit()
    }

    // MARK: Hit testing (for click-through)

    /// The village house under a point, if any.
    func house(at p: Vec2) -> Int? {
        guard let floor = world.groveFloor else { return nil }
        return world.grove.village.indices.last { n in
            let h = world.grove.village[n]
            return abs(p.x - (floor.minX + h.x * floor.w)) < h.w * 0.45 && p.y >= floor.minY && p.y < floor.minY + h.h
        }
    }

    /// Clicking a village house: the work it remembers.
    func describeHouse(_ n: Int) {
        guard let floor = world.groveFloor, n < world.grove.village.count else { return }
        let h = world.grove.village[n]
        var parts = ["Built while Claude worked on \(h.project ?? "a project")", "\(h.blocks) edits"]
        if let d = h.day { parts.append(d) }
        if world.creatures.contains(where: { $0.homeHouse == n }) { parts.append("someone's asleep inside") }
        if let (si, pt) = local(Vec2(floor.minX + h.x * floor.w, floor.minY + h.h + 24)) {
            floatText(parts.joined(separator: " · "), si: si, at: pt, color: .systemBrown, size: 14, rise: 40, duration: 3.6)
        }
        if let l = houses[n]?.layer { boing(l, amount: 0.08) }
    }

    /// The grove plant under a point, if any.
    func plant(at p: Vec2) -> Int? {
        guard let floor = world.groveFloor else { return nil }
        return world.grove.plants.indices.first { i in
            let b = world.grove.base(i, floor: floor), sz = world.grove.size(i)
            return abs(p.x - b.x) < sz.x * 0.42 && p.y >= b.y && p.y < b.y + sz.y * 0.95
        }
    }

    /// Clicking a grove plant: what it is, its level, and how many Claude tasks until it grows.
    func describePlant(_ i: Int) {
        let p = world.grove.plants[i]
        var text = "\(p.kind.name) · Lv \(p.level) · \(p.kind.power)"
        if p.kind == .sunberry { text += " · \(p.berries) berries" }
        if p.level < 5 {
            let need = GrovePlant.thresholds[p.level - 1] * p.kind.cost - p.sparks
            text += " · \(Int(need.rounded(.up))) more Claude tasks to Lv \(p.level + 1)"
        }
        label(text, at: i, color: .systemGreen)
        if let l = plants[i]?.layer { boing(l, amount: 0.12) }
    }

}
