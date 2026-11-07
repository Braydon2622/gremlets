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
    private var houses: [Int: (layer: CALayer, ground: CALayer, key: String)] = [:]
    private var bridgeLayers: [Int: (layer: CALayer, blocks: Int)] = [:]
    private var stairLayers: [Int: (layer: CALayer, key: Int)] = [:]
    private var railLayers: [Int: (rail: CALayer, cart: CALayer, px: Int, frame: Int)] = [:]
    private var nextCartSpark: [Int: CFTimeInterval] = [:]
    private var zipLayers: [Int: (line: CAShapeLayer, top: CALayer, bottom: CALayer)] = [:]
    private var doorLayer: (glow: CAGradientLayer, line: CAShapeLayer, side: Double)?
    private var routeLayers: [Int: (line: CAShapeLayer, until: CFTimeInterval)] = [:]
    private var pulleyLayers: [Int: CALayer] = [:]
    private var chestLayers: [Int: (layer: CALayer, key: String)] = [:]
    private var flagLayers: [Int: CALayer] = [:]
    private var stackLayers: [Int: (layer: CALayer, n: Int)] = [:]
    private var signLayers: [Int: (layer: CALayer, sign: HeldSign)] = [:]
    private var mossLayers: [String: (layer: CALayer, key: String)] = [:]
    private var lastMoss: CFTimeInterval = 0
    private var ropes: [Int: (line: CAShapeLayer, hook: CALayer)] = [:]
    private var nextHouseSmoke: [Int: CFTimeInterval] = [:]
    private var pennants: [Int: CALayer] = [:]
    private var balls: [CALayer] = []
    private var shards: [Int: CALayer] = [:]
    private var emitter: CAEmitterLayer?
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
        renderGliders(); renderKite()
        renderSpirits()
        renderWind()
        renderCampfire()
        renderFerry()
        renderMerchant()
        renderVillage()
        renderBridges()
        renderStairs(); renderRails()
        renderExpeditions()
        renderDoor()
        renderMoss()
        renderRoutes()
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
            case .claimed(let n, _):
                guard n < world.grove.village.count else { continue }
                let h = world.grove.village[n]
                if let (si, pt) = local(Vec2(floor.minX + h.x * floor.w, floor.minY + h.h)) {
                    overlay.burst([Effects.heart, Effects.sparkle], si: si, at: pt, count: 6, dx: -30...30, dy: 10...50, duration: 1.2, stagger: 0.05)
                }
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
    private var kiteLayer: CALayer?
    private var kiteString: CAShapeLayer?

    /// The kite on its string, pointing away from the hand that holds it.
    private func renderKite() {
        guard let k = world.kite, let flyer = world.creatures.first(where: { $0.id == k.flyer }),
              let (si, kp) = local(k.pos), let (si2, hp) = local(world.kiteHand(flyer)), si == si2 else {
            if let l = kiteLayer { fade(l, to: 0, remove: true); kiteLayer = nil }
            kiteString?.removeFromSuperlayer(); kiteString = nil
            return
        }
        let l = kiteLayer ?? {
            let l = pixelLayer(); l.contents = StoryArt.kite(seed: k.seed)
            l.bounds = CGRect(x: 0, y: 0, width: 33, height: 66); l.anchorPoint = CGPoint(x: 0.5, y: 0.75); l.zPosition = 26
            popIn(l); return l
        }()
        attach(l, si)
        l.position = CGPoint(x: kp.x.rounded(), y: kp.y.rounded())
        l.transform = CATransform3DMakeRotation(atan2(kp.y - hp.y, kp.x - hp.x) - .pi / 2, 0, 0, 1)
        let s = kiteString ?? {
            let s = CAShapeLayer(); s.strokeColor = NSColor(white: 0.2, alpha: 0.7).cgColor; s.fillColor = nil; s.lineWidth = 1
            s.zPosition = 25; s.actions = ["path": NSNull(), "position": NSNull()]; return s
        }()
        attach(s, si)
        let path = CGMutablePath()
        path.move(to: hp)
        path.addQuadCurve(to: kp, control: CGPoint(x: (hp.x + kp.x) / 2, y: (hp.y + kp.y) / 2 - 16))
        s.path = path
        kiteLayer = l; kiteString = s
    }

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

    private var pathLayer: (layer: CALayer, key: String)?

    private func renderVillage() {
        guard let floor = world.groveFloor else { return }
        // The path runs from the first house to the last.
        let xs = world.grove.village.map { floor.minX + $0.x * floor.w }
        if let lo = xs.min(), let hi = xs.max(), hi - lo > 40, let (si, pt) = local(Vec2(lo - 40, floor.minY)) {
            let px = Int((hi - lo + 80) / artScale / 6) * 6
            let key = "\(px)-\(si)"
            var e = pathLayer ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0, y: 0); l.zPosition = -5.5; return (l, "") }()
            attach(e.layer, si)
            if e.key != key {
                let img = VillageArt.path(widthPx: px)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
                e.key = key
            }
            e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
            pathLayer = e
        } else if let e = pathLayer { e.layer.removeFromSuperlayer(); pathLayer = nil }
        let night = world.isNight
        for (n, h) in world.grove.village.enumerated() {
            guard let (si, pt) = local(Vec2(floor.minX + h.x * floor.w, floor.minY)) else { continue }
            if h.biome == "mine" { renderMine(n, h, si: si, at: pt); continue }
            if h.biome.hasPrefix("item:"), let item = VillageItem(rawValue: String(h.biome.dropFirst(5))) { renderItem(n, item, si: si, at: pt); continue }
            guard let b = Biome(rawValue: h.biome) else { continue }
            let stage = BuildArt.overgrowthStage(hours: h.builtAt.map { (Date().timeIntervalSince1970 - $0) / 3600 } ?? 0)
            // The Gremlets finish what Claude's session started: a house in the village is always complete.
            let blocks = max(h.blocks, BuildArt.cells(b).count)
            let key = "\(h.biome)-\(blocks)-\(night)-\(si)-\(stage)-\(world.month)"
            var entry = houses[n] ?? {
                let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = -4
                // A strip of its biome's ground under it, so each house sits in its own little patch of world.
                let g = pixelLayer(); g.anchorPoint = CGPoint(x: 0.5, y: 1); g.zPosition = -4.1
                popIn(l)
                return (l, g, "")
            }()
            attach(entry.layer, si); attach(entry.ground, si)
            if entry.key != key, let img = BuildArt.image(b, blocks: blocks, night: night, overgrowth: stage, seed: UInt64(n * 31 + 7), month: world.month) {
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
            // Its owner's pennant on the roof.
            if let owner = h.owner {
                let p = pennants[n] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0, y: 0); l.zPosition = -3.9; l.bounds = CGRect(x: 0, y: 0, width: 15, height: 15); popIn(l); return l }()
                attach(p, si)
                p.contents = OwnerArt.pennant(OwnerArt.color(for: owner))
                let f = entry.layer.frame
                p.position = CGPoint(x: f.minX + f.width * 0.25, y: f.maxY - 3)
                pennants[n] = p
            } else if let p = pennants[n] { p.removeFromSuperlayer(); pennants[n] = nil }
            // Someone's home: smoke from the chimney, and the odd "z" drifting out.
            let now = CACurrentMediaTime()
            if world.creatures.contains(where: { $0.homeHouse == n }), now >= (nextHouseSmoke[n] ?? 0) {
                nextHouseSmoke[n] = now + 1.4
                let f = entry.layer.frame, ch = BuildArt.chimney(b)
                overlay.burst([Effects.smoke], si: si, at: CGPoint(x: f.minX + f.width * ch.x, y: f.minY + f.height * ch.y), count: 1, dx: 4...14, dy: 26...44, duration: 2.2)
                if Int(now) % 3 == 0 { overlay.burst([Effects.zzz], si: si, at: CGPoint(x: f.midX, y: f.maxY - 10), count: 1, dx: -10...10, dy: 20...34, duration: 1.8) }
            }
        }
        for n in pennants.keys where n >= world.grove.village.count { pennants[n]?.removeFromSuperlayer(); pennants[n] = nil }
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

    /// Wooden staircases up to windows, block by block.
    private func renderStairs() {
        var alive = Set<Int>()
        for s in world.stairs where s.standing > 0 {
            alive.insert(s.id)
            guard let (si, pt) = local(Vec2(s.minX, s.base.y)) else { continue }
            var e = stairLayers[s.id] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0, y: 0); l.zPosition = -0.3; return (l, -1) }()
            attach(e.layer, si)
            let key = s.built * 1000 + s.first
            if e.key != key {
                let img = TerrainArt.stairs(steps: s.steps, built: s.built, first: s.first, dir: s.dir)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                e.key = key
            }
            e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
            stairLayers[s.id] = e
        }
        for (id, e) in stairLayers where !alive.contains(id) { e.layer.removeFromSuperlayer(); stairLayers[id] = nil }
    }

    /// Rails along wide windows, and the carts rolling on them (sparks when they're going fast).
    private func renderRails() {
        var alive = Set<Int>()
        let now = CACurrentMediaTime()
        for r in world.rails where r.laid > 0 {
            alive.insert(r.id)
            let (lo, hi) = r.laidSpan
            guard let (si, pt) = local(Vec2(lo, r.y)) else { continue }
            var e = railLayers[r.id] ?? {
                let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0, y: 0); l.zPosition = -0.25
                let c = pixelLayer(); c.anchorPoint = CGPoint(x: 0.5, y: 0); c.zPosition = 0.6
                return (l, c, -1, -1)
            }()
            attach(e.rail, si)
            let px = max(2, Int(((hi - lo) / 3).rounded()))
            if e.px != px {
                e.rail.contents = TerrainArt.rail(widthPx: px)
                e.rail.bounds = CGRect(x: 0, y: 0, width: px * 3, height: 9)
                e.px = px
            }
            e.rail.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded() - 3)
            if r.isComplete, let (csi, cpt) = local(Vec2(r.cart.x, r.y)) {
                let fresh = e.frame < 0
                attach(e.cart, csi)
                let frame = abs(r.cart.vel) > 5 ? Int(now * 10) % 2 : 0
                if e.frame != frame {
                    let img = TerrainArt.cart(frame: frame)
                    e.cart.contents = img
                    e.cart.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                    e.frame = frame
                }
                e.cart.position = CGPoint(x: cpt.x.rounded(), y: cpt.y.rounded() + 2)
                if fresh { popIn(e.cart) }
                if abs(r.cart.vel) > 150, now >= (nextCartSpark[r.id] ?? 0) {
                    nextCartSpark[r.id] = now + 0.25
                    let back = r.cart.vel > 0 ? -14.0 : 14.0
                    overlay.burst([Effects.sparkle, Effects.smallStar], si: csi, at: CGPoint(x: cpt.x + back, y: cpt.y + 4), count: 1, dx: (back - 6)...(back + 6), dy: 4...18, duration: 0.3)
                }
            } else {
                e.cart.removeFromSuperlayer()
            }
            railLayers[r.id] = e
        }
        for (id, e) in railLayers where !alive.contains(id) { e.rail.removeFromSuperlayer(); e.cart.removeFromSuperlayer(); railLayers[id] = nil }
    }

    func handle(_ events: [TerrainEvent]) {
        for e in events {
            switch e {
            case .stairBlock(let p, _):
                if let (si, pt) = local(p) { overlay.burst([Effects.dust, Effects.smallStar], si: si, at: pt, count: 2, dx: -10...10, dy: -4...12, duration: 0.4) }
            case .stairBlockTaken(let p, let by):
                guard let (si, pt) = local(p) else { continue }
                // The block hops up out of the staircase and arcs into the climber's arms.
                if let id = by, let c = world.creatures.first(where: { $0.id == id }), let (_, head) = local(c.pos + Vec2(c.facing * 2, c.species.headTop - 2 + Double(max(0, c.blocksInHand - 1)) * 15)) {
                    let img = TerrainArt.blockStack(1)
                    let l = pixelLayer(); l.contents = img
                    l.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                    l.zPosition = 1.2
                    attach(l, si)
                    l.position = pt
                    let path = CGMutablePath()
                    path.move(to: pt)
                    path.addQuadCurve(to: head, control: CGPoint(x: (pt.x + head.x) / 2, y: max(pt.y, head.y) + 34))
                    let fly = CAKeyframeAnimation(keyPath: "position"); fly.path = path
                    let spin = CABasicAnimation(keyPath: "transform.rotation.z"); spin.fromValue = 0; spin.toValue = (head.x > pt.x ? -1 : 1) * Double.pi
                    let g = CAAnimationGroup(); g.animations = [fly, spin]; g.duration = 0.34
                    g.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    l.position = head
                    l.add(g, forKey: "fly")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { l.removeFromSuperlayer() }
                    overlay.burst([Effects.dust], si: si, at: pt, count: 2, dx: -8...8, dy: -4...8, duration: 0.3)
                } else {
                    overlay.burst([Effects.dust, Effects.smallStar], si: si, at: pt, count: 3, dx: -10...10, dy: 6...18, duration: 0.4)
                }
            case .blocksStowed(let by):
                if let c = world.creatures.first(where: { $0.id == by }), let (si, pt) = local(c.pos + Vec2(0, c.size.y)) {
                    overlay.burst([Effects.sparkle], si: si, at: pt, count: 3, dx: -10...10, dy: 4...16, duration: 0.5)
                }
            case .stairsDone(let id):
                if let s = world.stairs.first(where: { $0.id == id }), let (si, pt) = local(Vec2((s.minX + s.maxX) / 2, s.topY)) {
                    overlay.burst([Effects.sparkle, Effects.star], si: si, at: pt, count: 8, dx: -60...60, dy: 0...40, duration: 0.9, stagger: 0.03)
                }
            case .stairsCrumbled(let blocks):
                for p in blocks {
                    if let (si, pt) = local(p) { overlay.burst([WeatherArt.block, Effects.dust], si: si, at: pt, count: 1, dx: -12...12, dy: -170 ... -60, duration: 0.9) }
                }
            case .railDone(let id):
                if let r = world.rails.first(where: { $0.id == id }) {
                    for x in stride(from: r.minX, through: r.maxX, by: 60) {
                        if let (si, pt) = local(Vec2(x, r.y)) { overlay.burst([Effects.sparkle], si: si, at: pt, count: 1, dx: -10...10, dy: 6...24, duration: 0.7, delay: (x - r.minX) / 600) }
                    }
                }
            case .railCrumbled(let lo, let hi, let y):
                for x in stride(from: lo, through: hi, by: 45) {
                    if let (si, pt) = local(Vec2(x, y)) { overlay.burst([Effects.dust, BridgeArt.plank], si: si, at: pt, count: 1, dx: -8...8, dy: -120 ... -40, duration: 0.8) }
                }
            case .cartBounce(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle, Effects.smallStar, Effects.dust], si: si, at: pt, count: 6, dx: -24...24, dy: 6...40, duration: 0.5, stagger: 0.02) }
            case .boarded(_, let by):
                if let c = world.creatures.first(where: { $0.id == by }), let (si, pt) = local(c.pos + Vec2(0, c.size.y)) {
                    overlay.burst([Effects.smallStar], si: si, at: pt, count: 2, dx: -10...10, dy: 10...24, duration: 0.6)
                }
            }
        }
    }

    /// Ziplines (cable, posts, the pulley a rider hangs from), chests, summit flags, and the blocks climbers carry.
    private func renderExpeditions() {
        var alive = Set<Int>()
        for z in world.ziplines {
            alive.insert(z.id)
            guard let (si, top) = local(z.top), let (_, bottom) = local(z.bottom) else { continue }
            var e = zipLayers[z.id] ?? {
                let line = CAShapeLayer()
                line.strokeColor = NSColor(red: 0.55, green: 0.58, blue: 0.64, alpha: 1).cgColor
                line.lineWidth = 2; line.fillColor = nil; line.zPosition = -0.35
                line.actions = ["path": NSNull()]
                let t = pixelLayer(); t.contents = TerrainArt.zipPost; t.bounds = CGRect(x: 0, y: 0, width: 15, height: 30); t.anchorPoint = CGPoint(x: 0.5, y: 0); t.zPosition = -0.34
                let b = pixelLayer(); b.contents = TerrainArt.zipPost; b.bounds = t.bounds; b.anchorPoint = CGPoint(x: 0.5, y: 0); b.zPosition = -0.34
                popIn(t); popIn(b)
                return (line, t, b)
            }()
            attach(e.line, si); attach(e.top, si); attach(e.bottom, si)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: top.x, y: top.y + 2))
            path.addQuadCurve(to: CGPoint(x: bottom.x, y: bottom.y + 2), control: CGPoint(x: (top.x + bottom.x) / 2, y: (top.y + bottom.y) / 2 - 9))
            e.line.path = path
            e.top.position = CGPoint(x: top.x.rounded(), y: (top.y - Zipline.hang).rounded())
            e.bottom.position = CGPoint(x: bottom.x.rounded(), y: (bottom.y - Zipline.hang).rounded())
            zipLayers[z.id] = e
        }
        for (id, e) in zipLayers where !alive.contains(id) { e.line.removeFromSuperlayer(); e.top.removeFromSuperlayer(); e.bottom.removeFromSuperlayer(); zipLayers[id] = nil }
        // Pulleys over riders, block stacks over climbers.
        var riders = Set<Int>(), climbers = Set<Int>()
        for c in world.creatures {
            if c.isZipping, let (si, pt) = local(c.pos + Vec2(0, Zipline.hang)) {
                riders.insert(c.id)
                let l = pulleyLayers[c.id] ?? { let l = pixelLayer(); l.contents = TerrainArt.pulley; l.bounds = CGRect(x: 0, y: 0, width: 21, height: 27); l.anchorPoint = CGPoint(x: 0.5, y: 1); l.zPosition = 1.2; return l }()
                attach(l, si)
                l.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded() + 4)
                pulleyLayers[c.id] = l
            }
            if c.blocksInHand > 0, let (si, pt) = local(c.pos + Vec2(c.facing * 2, c.species.headTop - 2)) {
                climbers.insert(c.id)
                var e = stackLayers[c.id] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = 1.1; popIn(l); return (l, -1) }()
                attach(e.layer, si)
                if e.n != c.blocksInHand {
                    let img = TerrainArt.blockStack(c.blocksInHand)
                    e.layer.contents = img
                    e.layer.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                    e.n = c.blocksInHand
                }
                e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
                stackLayers[c.id] = e
            }
        }
        // Signs held up over heads (battery low, no signal), bobbing a little.
        var holders = Set<Int>()
        for c in world.creatures {
            guard let s = c.sign, let (si, pt) = local(c.pos + Vec2(0, c.species.headTop - 4)) else { continue }
            holders.insert(c.id)
            var e = signLayers[c.id] ?? {
                let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = 1.1
                let img = SignArt.image(s); l.contents = img; l.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                popIn(l)
                return (l, s)
            }()
            if e.sign != s { let img = SignArt.image(s); e.layer.contents = img; e.sign = s }
            attach(e.layer, si)
            e.layer.position = CGPoint(x: pt.x.rounded(), y: (pt.y + sin(CACurrentMediaTime() * 3 + Double(c.id)) * 2).rounded())
            signLayers[c.id] = e
        }
        for (id, e) in signLayers where !holders.contains(id) { fade(e.layer, to: 0, remove: true); signLayers[id] = nil }
        for (id, l) in pulleyLayers where !riders.contains(id) { l.removeFromSuperlayer(); pulleyLayers[id] = nil }
        for (id, e) in stackLayers where !climbers.contains(id) { fade(e.layer, to: 0, remove: true); stackLayers[id] = nil }
        // Chests: on their perch, or over a carrier's head (with a little bob).
        var chestsAlive = Set<Int>()
        let now = CACurrentMediaTime()
        for ch in world.chests {
            chestsAlive.insert(ch.id)
            guard let (si, pt) = local(ch.pos) else { continue }
            var e = chestLayers[ch.id] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.5, y: 0); l.zPosition = ch.carriedBy == nil ? -0.2 : 1.15; popIn(l); return (l, "") }()
            attach(e.layer, si)
            let key = "\(ch.golden)-\(ch.carriedBy != nil)"
            if e.key != key {
                let img = TerrainArt.chest(open: false, golden: ch.golden)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                e.layer.zPosition = ch.carriedBy == nil ? -0.2 : 1.15
                if ch.golden {
                    e.layer.shadowColor = NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1).cgColor
                    e.layer.shadowRadius = 8; e.layer.shadowOpacity = 0.8; e.layer.shadowOffset = .zero
                }
                e.key = key
            }
            let bob = ch.carriedBy == nil ? 0 : sin(now * 5) * 2
            e.layer.position = CGPoint(x: pt.x.rounded(), y: (pt.y + bob).rounded())
            chestLayers[ch.id] = e
        }
        for (id, e) in chestLayers where !chestsAlive.contains(id) { e.layer.removeFromSuperlayer(); chestLayers[id] = nil }
        // Flags.
        var flagsAlive = Set<Int>()
        for f in world.flags {
            flagsAlive.insert(f.id)
            guard let (si, pt) = local(f.pos) else { continue }
            let l = flagLayers[f.id] ?? {
                let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0.15, y: 0); l.zPosition = -0.25
                let img = TerrainArt.summitFlag(OwnerArt.color(for: f.owner))
                l.contents = img; l.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
                let wave = CABasicAnimation(keyPath: "transform.rotation.z")
                wave.fromValue = -0.05; wave.toValue = 0.05; wave.duration = 0.9; wave.autoreverses = true; wave.repeatCount = .infinity
                l.add(wave, forKey: "wave")
                popIn(l)
                return l
            }()
            attach(l, si)
            l.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
            flagLayers[f.id] = l
        }
        for (id, l) in flagLayers where !flagsAlive.contains(id) { fade(l, to: 0, remove: true); flagLayers[id] = nil }
    }

    func handle(_ events: [TeamEvent]) {
        func at(_ id: Int, _ up: Double = 1) -> (Int, CGPoint)? {
            guard let c = world.creatures.first(where: { $0.id == id }) else { return nil }
            return local(c.pos + Vec2(0, c.size.y * up))
        }
        for e in events {
            switch e {
            case .boostStarted(let climber, let helper):
                overlay.showBubble(["Give me a boost?", "Little help?", "Lift me up?"].randomElement()!, on: climber, seconds: 2.2)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.overlay.showBubble(["On it!", "I got you.", "Hop on!"].randomElement()!, on: helper, seconds: 2) }
            case .heave(let climber, let helper):
                overlay.showBubble("Hup!", on: helper, seconds: 1.2)
                if let (si, pt) = at(climber, 0.2) { overlay.burst([Effects.dust, Effects.smallStar], si: si, at: pt, count: 6, dx: -24...24, dy: -6...20, duration: 0.6) }
            case .boostDone(let climber, let helper):
                if let (si, pt) = at(climber) { overlay.burst([Effects.heart, Effects.sparkle], si: si, at: pt, count: 5, dx: -20...20, dy: 10...40, duration: 1.0) }
                overlay.showBubble(["Thanks!", "Made it! Thank you!", "Teamwork!"].randomElement()!, on: climber, seconds: 2.2)
                _ = helper
            case .boostFailed:
                break
            case .posed(let ids):
                for id in ids {
                    if let (si, pt) = at(id, 1.1) { overlay.burst([Effects.sparkle, Effects.smallStar], si: si, at: pt, count: 3, dx: -20...20, dy: 4...24, duration: 0.7) }
                }
                if let first = ids.randomElement() { overlay.showBubble(["Cheese!", "Get my good side!", "📸 ✌️", "Ready!"].randomElement()!, on: first, seconds: 2.2) }
            case .signUp(let id, let s):
                overlay.showBubble(s == .battery ? "Battery's getting low! 🔋" : "No internet… 📡", on: id, seconds: 3)
            case .signDown(let id, let s, let cheer):
                if cheer { overlay.showBubble(s == .battery ? "Ahh, power! ⚡" : "We're back online!", on: id, seconds: 2.4) }
                if cheer, let (si, pt) = at(id) { overlay.burst([Effects.sparkle, Effects.star], si: si, at: pt, count: 6, dx: -24...24, dy: 10...40, duration: 0.9) }
            }
        }
    }

    func handle(_ events: [ExpeditionEvent]) {
        for e in events {
            switch e {
            case .started(let by, let goal, _):
                if case .treasure = goal { overlay.showBubble(["Treasure! Back soon.", "Ooh, a chest. Mine!", "Off to get it!"].randomElement()!, on: by, seconds: 2.5) }
                else { overlay.showBubble(["To the top!", "Summit time.", "Going up!"].randomElement()!, on: by, seconds: 2.5) }
                showRoute(of: by)
            case .legDone:
                break
            case .gaveUp(let by):
                overlay.showBubble("Hmph. Another day.", on: by, seconds: 2)
            case .chestAppeared(let id):
                if let ch = world.chests.first(where: { $0.id == id }), let (si, pt) = local(ch.pos + Vec2(0, 14)) {
                    overlay.burst([Effects.sparkle, Effects.star], si: si, at: pt, count: 8, dx: -30...30, dy: 0...40, duration: 1.2, stagger: 0.05)
                }
            case .chestTaken(_, let by):
                if let c = world.creatures.first(where: { $0.id == by }), let (si, pt) = local(c.pos + Vec2(0, c.size.y)) {
                    overlay.burst([Effects.sparkle, Effects.smallStar], si: si, at: pt, count: 5, dx: -20...20, dy: 10...40, duration: 0.8)
                }
                overlay.showBubble("Got it!", on: by, seconds: 1.8)
            case .chestDropped:
                break
            case .chestOpened(_, let by, let gem):
                if let c = world.creatures.first(where: { $0.id == by }), let (si, pt) = local(c.pos + Vec2(0, c.size.y)) {
                    overlay.burst([AdventureArt.gem(gem), Effects.sparkle, Effects.star], si: si, at: pt, count: 12, dx: -50...50, dy: 10...80, duration: 1.6, stagger: 0.04)
                }
                overlay.showBubble(gem == .starstone ? "A starstone! ✨" : "\(gem.name == "Amber" || gem == .amethyst || gem == .emerald ? "An" : "A") \(gem.name.lowercased())!", on: by, seconds: 3.5)
            case .summit(let by, _):
                if let c = world.creatures.first(where: { $0.id == by }), let (si, pt) = local(c.pos + Vec2(0, c.size.y)) {
                    overlay.burst([Effects.star, Effects.sparkle, Effects.smallStar], si: si, at: pt, count: 14, dx: -60...60, dy: 10...90, duration: 1.6, stagger: 0.04)
                }
                overlay.showBubble(["Made it to the top!", "Highest point. Claimed.", "What a view."].randomElement()!, on: by, seconds: 3.5)
            case .flagLost:
                break
            case .zipMade(let id):
                if let z = world.ziplines.first(where: { $0.id == id }), let (si, pt) = local(z.top) {
                    overlay.burst([Effects.sparkle], si: si, at: pt, count: 3, dx: -10...10, dy: -4...10, duration: 0.4)
                }
            case .zipped(let by, _):
                overlay.showBubble("Wheee!", on: by, seconds: 1.4)
            case .zipLost:
                break
            }
        }
    }

    /// The doorway to a linked screen: a soft glow and a dashed line at the edge of the main screen's floor.
    private func renderDoor() {
        guard let d = world.door, let floor = world.groveFloor, let (si, pt) = local(Vec2(d > 0 ? floor.maxX : floor.minX, floor.minY)) else {
            if let e = doorLayer { e.glow.removeFromSuperlayer(); e.line.removeFromSuperlayer(); doorLayer = nil }
            return
        }
        var e = doorLayer ?? {
            let glow = CAGradientLayer()
            glow.colors = [NSColor(red: 0.66, green: 0.55, blue: 0.92, alpha: 0).cgColor, NSColor(red: 0.66, green: 0.55, blue: 0.92, alpha: 0.5).cgColor]
            glow.startPoint = CGPoint(x: 0.5, y: 1); glow.endPoint = CGPoint(x: 0.5, y: 0)
            glow.bounds = CGRect(x: 0, y: 0, width: 26, height: 150); glow.zPosition = -6
            let line = CAShapeLayer()
            line.strokeColor = NSColor(red: 0.66, green: 0.55, blue: 0.92, alpha: 1).cgColor
            line.lineWidth = 3; line.lineDashPattern = [8, 6]; line.fillColor = nil; line.zPosition = -5.9
            let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: 20)); p.addLine(to: CGPoint(x: 0, y: 150)); line.path = p
            let dash = CABasicAnimation(keyPath: "lineDashPhase"); dash.fromValue = 0; dash.toValue = -14; dash.duration = 0.5; dash.repeatCount = .infinity
            line.add(dash, forKey: "dash")
            return (glow, line, d)
        }()
        attach(e.glow, si); attach(e.line, si)
        e.glow.anchorPoint = CGPoint(x: d > 0 ? 1 : 0, y: 0)
        e.glow.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
        e.line.position = CGPoint(x: (pt.x - d * 3).rounded(), y: pt.y.rounded())
        e.side = d
        doorLayer = e
    }

    /// The plan, drawn for a few seconds when an expedition sets out: a dotted line from the Gremlet through every
    /// leg to the goal, so you can see the route it worked out across your windows before it takes it.
    private func showRoute(of id: Int) {
        guard let c = world.creatures.first(where: { $0.id == id }), let ex = c.expedition, !ex.legs.isEmpty,
              let (si, start) = local(c.pos + Vec2(0, c.size.y * 0.5)) else { return }
        let o = screens[si].frame.origin
        let path = CGMutablePath()
        path.move(to: start)
        var last = c.pos
        for leg in ex.legs {
            let a = Vec2(leg.actX.clamped(leg.from.minX, leg.from.maxX), leg.from.y + 24)
            let tx = leg.method == .walk || leg.method == .drop ? leg.actX : (leg.from.minX + leg.from.maxX) / 2 > (leg.to.minX + leg.to.maxX) / 2 ? leg.to.maxX - 30 : leg.to.minX + 30
            let b = Vec2(tx.clamped(leg.to.minX + 10, leg.to.maxX - 10), leg.to.y + 24)
            path.addLine(to: CGPoint(x: a.x - o.x, y: a.y - o.y))
            // Arcs for the airborne moves, straight runs for the rest.
            switch leg.method {
            case .jump, .grapple, .glide, .zip, .drop:
                let lift: Double = leg.method == .drop || leg.method == .glide || leg.method == .zip ? 20 : max(60, (b.y - a.y) * 0.5 + 40)
                path.addQuadCurve(to: CGPoint(x: b.x - o.x, y: b.y - o.y), control: CGPoint(x: (a.x + b.x) / 2 - o.x, y: max(a.y, b.y) + lift - o.y))
            default:
                path.addLine(to: CGPoint(x: b.x - o.x, y: b.y - o.y))
            }
            last = b
        }
        _ = last
        let l = routeLayers[id]?.line ?? {
            let l = CAShapeLayer()
            l.fillColor = nil; l.lineWidth = 2.5; l.lineCap = .round; l.lineJoin = .round
            l.lineDashPattern = [1, 9]; l.zPosition = 25
            l.actions = ["path": NSNull(), "opacity": NSNull()]
            let flow = CABasicAnimation(keyPath: "lineDashPhase"); flow.fromValue = 0; flow.toValue = -10; flow.duration = 0.6; flow.repeatCount = .infinity
            l.add(flow, forKey: "flow")
            return l
        }()
        l.strokeColor = NSColor(red: 1, green: 0.93, blue: 0.6, alpha: 0.95).cgColor
        l.shadowColor = NSColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1).cgColor; l.shadowRadius = 2; l.shadowOpacity = 0.8; l.shadowOffset = .zero
        l.path = path
        l.opacity = 1
        attach(l, si)
        routeLayers[id] = (l, CACurrentMediaTime() + 4.5)
    }

    private func renderRoutes() {
        let now = CACurrentMediaTime()
        for (id, e) in routeLayers {
            let left = e.until - now
            if left <= 0 { e.line.removeFromSuperlayer(); routeLayers[id] = nil; continue }
            e.line.opacity = Float(min(1, left / 1.2))
        }
    }

    // MARK: Overgrowth

    /// Moss over everything, by how long Claude has been working (`World.mossMinutes`):
    /// from 10 minutes, carpets creep in from the ends of every window top; from 40, strands hang down window sides
    /// and vines climb the screen's side edges; from 90, the carpets meet in the middle and flower; from 150, moss
    /// fringes the bottom of the menu bar and the floor; at 300 everything is covered.
    private func renderMoss() {
        let now = CACurrentMediaTime()
        guard now - lastMoss > 0.12 else { return }   // a few times a second is plenty for moss
        lastMoss = now
        let m = world.mossMinutes
        var alive = Set<String>()
        let night = world.isNight
        func place(_ key: String, _ si: Int, at p: CGPoint, anchor: CGPoint, flip: Bool = false, rotate: Double = 0, imageKey: String, make: () -> CGImage) {
            alive.insert(key)
            var e = mossLayers[key] ?? {
                let l = pixelLayer(); l.zPosition = 1.3
                let grow = CABasicAnimation(keyPath: "opacity"); grow.fromValue = 0; grow.toValue = 1; grow.duration = 1.2
                l.add(grow, forKey: "grow")
                return (l, "")
            }()
            attach(e.layer, si)
            if e.key != imageKey {
                let img = make()
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
                e.key = imageKey
            }
            e.layer.anchorPoint = anchor
            var t = CGAffineTransform(scaleX: flip ? -1 : 1, y: 1)
            if rotate != 0 { t = t.rotated(by: rotate) }
            e.layer.setAffineTransform(t)
            e.layer.position = CGPoint(x: p.x.rounded(), y: p.y.rounded())
            mossLayers[key] = e
        }
        if m >= 10 {
            // Window tops: carpets creeping in from both ends.
            let reach = ((m - 10) / 90).clamped(0, 1)       // fraction of each half covered
            let density = ((m - 10) / 200).clamped(0, 1)
            for s in world.surfaces where s.kind == .windowTop && s.width >= 40 {
                let half = s.width / 2 * max(0.12, reach)
                let px = max(4, Int(half / artScale / 4) * 4)
                let dq = Int(density * 5)
                for (end, x, flip) in [("l", s.minX, false), ("r", s.maxX, true)] {
                    guard let (si, pt) = local(Vec2(x, s.y)) else { continue }
                    let seed = UInt64(abs(s.ownerID) &* 31 &+ (end == "l" ? 1 : 2))
                    place("w\(s.ownerID)-\(Int(s.minX))-\(end)", si, at: CGPoint(x: pt.x, y: pt.y - 3 * artScale), anchor: CGPoint(x: 0, y: 0), flip: flip,
                          imageKey: "\(px)-\(dq)-\(night)") { MossArt.carpet(lengthPx: px, density: density, seed: seed, night: night) }
                }
                // Strands hanging down the window's sides, from the corners that are really the window's corners.
                if m >= 40, let w = world.windows[s.ownerID] {
                    let len = min(w.h * 0.7, (m - 40) * 2.2 + 30)
                    let lpx = max(6, Int(len / artScale / 4) * 4)
                    for (end, x) in [("l", w.minX), ("r", w.maxX)] where abs((end == "l" ? s.minX : s.maxX) - x) < 2 {
                        guard let (si, pt) = local(Vec2(x, s.y)) else { continue }
                        let seed = UInt64(abs(s.ownerID) &* 17 &+ (end == "l" ? 3 : 4))
                        place("s\(s.ownerID)-\(end)", si, at: CGPoint(x: pt.x + (end == "l" ? -2 : 2), y: pt.y + 4), anchor: CGPoint(x: 0.5, y: 1),
                              imageKey: "\(lpx)-\(m >= 90)") { MossArt.strand(lengthPx: lpx, seed: seed, bloom: m >= 90) }
                        // A second, shorter strand a little way in once it's thick.
                        if m >= 120 {
                            let x2 = end == "l" ? x + 26 : x - 26
                            if let (si2, pt2) = local(Vec2(x2, s.y)) {
                                let l2 = max(6, lpx / 2)
                                place("s\(s.ownerID)-\(end)2", si2, at: CGPoint(x: pt2.x, y: pt2.y + 2), anchor: CGPoint(x: 0.5, y: 1),
                                      imageKey: "\(l2)") { MossArt.strand(lengthPx: l2, seed: seed &+ 9, bloom: false) }
                            }
                        }
                    }
                }
            }
        }
        // Screens: vines up the side edges, then the floor and the menu bar's underside.
        for (i, scr) in world.screens.enumerated() where m >= 40 {
            let climb = min(scr.h * 0.9, (m - 40) * 4)
            let cpx = max(8, Int(climb / artScale / 4) * 4)
            for (end, x) in [("l", scr.minX + 2), ("r", scr.maxX - 2)] {
                guard let (si, pt) = local(Vec2(x, scr.minY)) else { continue }
                place("v\(i)-\(end)", si, at: pt, anchor: CGPoint(x: 0, y: 0.5), rotate: end == "l" ? Double.pi / 2 : Double.pi / 2,
                      imageKey: "\(cpx)-\(Int((m / 60).rounded()))") { MossArt.carpet(lengthPx: cpx, density: (m / 300).clamped(0.1, 1), seed: UInt64(i * 7 + (end == "l" ? 1 : 2)), night: night) }
            }
            if m >= 150 {
                let frac = ((m - 150) / 150).clamped(0.15, 1)
                let fpx = max(8, Int(scr.w * frac / artScale / 8) * 8)
                if let (si, pt) = local(Vec2(scr.minX + (scr.w - scr.w * frac) / 2, scr.maxY)) {
                    place("top\(i)", si, at: pt, anchor: CGPoint(x: 0, y: 0), flip: false, rotate: 0,
                          imageKey: "\(fpx)-\(night)") { MossArt.carpet(lengthPx: fpx, density: frac, seed: UInt64(i + 40), night: night) }
                    mossLayers["top\(i)"]?.layer.setAffineTransform(CGAffineTransform(scaleX: 1, y: -1))   // hanging from the menu bar
                }
                if let (si, pt) = local(Vec2(scr.minX, scr.minY)) {
                    let gpx = max(8, Int(scr.w * frac / artScale / 8) * 8)
                    place("floor\(i)", si, at: CGPoint(x: pt.x, y: pt.y - 3 * artScale), anchor: CGPoint(x: 0, y: 0),
                          imageKey: "\(gpx)-\(night)") { MossArt.carpet(lengthPx: gpx, density: frac, seed: UInt64(i + 60), night: night) }
                }
            }
        }
        for (k, e) in mossLayers where !alive.contains(k) { fade(e.layer, to: 0, remove: true); mossLayers[k] = nil }
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
            for (_, l) in shards { l.removeFromSuperlayer() }; shards.removeAll()
            return
        }
        renderShards(s)
    }

    private func renderShards(_ s: Spectacle) {
        var alive = Set<Int>()
        for sh in s.shards {
            alive.insert(sh.id)
            guard let (si, pt) = local(sh.pos + Vec2(0, 10)) else { continue }
            let l = shards[sh.id] ?? {
                let l = pixelLayer()
                l.contents = SkyArt.shard
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
            l.contents = SkyArt.seedBall
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
            case .shardCollected(let p, _):
                if let (si, pt) = local(p + Vec2(0, 14)) {
                    overlay.burst([Effects.sparkle, Effects.star], si: si, at: pt, count: 6, dx: -26...26, dy: 10...50, duration: 0.9)
                    floatText("+✦", si: si, at: CGPoint(x: pt.x, y: pt.y + 26), color: .systemYellow, size: 16, rise: 30, duration: 1)
                }
            case .meteor(let from, let to):
                meteor(from, to)
            case .ended:
                stopEmitter()
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
        if let o = h.owner { parts.insert("\(overlay.species[o]?.info.name ?? "A Gremlet")'s home", at: 0) }
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
