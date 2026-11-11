import AppKit
import GremletsCore

/// Draws the living bits of the desktop ecosystem (Ecosystem.swift): the hollow log that's the doorway to a linked
/// screen, the critters in the moss (ladybugs, bees, little snails), and the puffs and words for the Dock games.
final class EcoRenderer {
    unowned let overlay: OverlayController
    let world: World

    private var critterLayers: [Int: (layer: CALayer, key: String)] = [:]
    private var logLayer: (layer: CALayer, glow: CALayer, side: Double, key: String)?
    private var birdLayers: [Int: (layer: CALayer, key: String)] = [:]
    private var pantryLayer: (layer: CALayer, rope: CAShapeLayer, key: String)?
    private var barrelLayer: (layer: CALayer, key: String)?
    private var basketLayer: (layer: CALayer, rope: CAShapeLayer)?
    private var nextBarrelDrip = 0.0
    private var patchLayer: (layer: CALayer, key: String)?
    private var mailLayer: (layer: CALayer, rope: CAShapeLayer, key: String)?
    private var mailPanel: (layer: CALayer, key: String)?
    private var lanternLayers: [Int: (layer: CALayer, glow: CAGradientLayer, lit: Bool?)] = [:]
    private var hiveLayer: CALayer?
    private var beeLayers: [CALayer] = []
    private var seasonLayer: (layer: CALayer, key: String)?
    private var jarLayer: (layer: CALayer, glow: CAGradientLayer, key: String)?
    private var nextPetal = 0.0

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
        l.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "transform": NSNull(), "opacity": NSNull(), "hidden": NSNull(), "anchorPoint": NSNull()]
        return l
    }

    private func popIn(_ l: CALayer) {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [0.1, 1.12, 0.96, 1]; a.duration = 0.6
        l.add(a, forKey: "pop")
    }

    private func fadeOut(_ l: CALayer) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = l.opacity; fade.toValue = 0; fade.duration = 0.5
        fade.isRemovedOnCompletion = false; fade.fillMode = .forwards
        l.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    func rebuild() {
        for e in critterLayers.values { e.layer.removeFromSuperlayer() }
        critterLayers.removeAll()
        if let l = logLayer { l.layer.removeFromSuperlayer(); l.glow.removeFromSuperlayer(); logLayer = nil }
        for e in birdLayers.values { e.layer.removeFromSuperlayer() }
        birdLayers.removeAll()
        if let p = pantryLayer { p.layer.removeFromSuperlayer(); p.rope.removeFromSuperlayer(); pantryLayer = nil }
        if let b = barrelLayer { b.layer.removeFromSuperlayer(); barrelLayer = nil }
        if let b = basketLayer { b.layer.removeFromSuperlayer(); b.rope.removeFromSuperlayer(); basketLayer = nil }
        if let p = patchLayer { p.layer.removeFromSuperlayer(); patchLayer = nil }
        if let m = mailLayer { m.layer.removeFromSuperlayer(); m.rope.removeFromSuperlayer(); mailLayer = nil }
        if let m = mailPanel { m.layer.removeFromSuperlayer(); mailPanel = nil }
        for e in lanternLayers.values { e.layer.removeFromSuperlayer(); e.glow.removeFromSuperlayer() }
        lanternLayers.removeAll()
        hiveLayer?.removeFromSuperlayer(); hiveLayer = nil
        for b in beeLayers { b.removeFromSuperlayer() }
        beeLayers.removeAll()
        seasonLayer?.layer.removeFromSuperlayer(); seasonLayer = nil
        if let j = jarLayer { j.layer.removeFromSuperlayer(); j.glow.removeFromSuperlayer(); jarLayer = nil }
    }

    func render(peerOnline: Bool) {
        renderLog(peerOnline: peerOnline)
        renderCritters()
        renderBirds()
        renderPantry()
        renderBarrel()
        renderBasket()
        renderPatch()
        renderMailbox()
        renderMailPanel()
        renderLanterns()
        renderHive()
        renderSeason()
        renderJar()
    }

    // MARK: The hive, the seasons, the firefly jar (Seasons.swift)

    private func renderHive() {
        guard let top = world.hiveSpot, let (si, pt) = local(top) else {
            if let h = hiveLayer { fadeOut(h); hiveLayer = nil }
            for b in beeLayers { b.removeFromSuperlayer() }
            beeLayers.removeAll()
            return
        }
        let h = hiveLayer ?? {
            let l = pixelLayer(); l.zPosition = 1.17
            l.anchorPoint = CGPoint(x: 0.5, y: 1)
            l.contents = PorchArt.hive
            l.bounds = CGRect(x: 0, y: 0, width: Double(PorchArt.hive.width) * artScale, height: Double(PorchArt.hive.height) * artScale)
            popIn(l)
            return l
        }()
        attach(h, si)
        let t = CACurrentMediaTime()
        h.position = CGPoint(x: (pt.x + nestSway).rounded(), y: pt.y.rounded())
        hiveLayer = h
        // Its bees: out over the patch in the daytime, a loop there and back.
        let want = world.beesOut ? 3 : 0
        while beeLayers.count > want { beeLayers.removeLast().removeFromSuperlayer() }
        while beeLayers.count < want {
            let l = pixelLayer(); l.zPosition = 1.36; l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            beeLayers.append(l)
        }
        guard let patch = world.patchSpot(1), let (_, pp) = local(patch) else { return }
        let door = CGPoint(x: pt.x + nestSway, y: pt.y - 16)
        for (i, l) in beeLayers.enumerated() {
            attach(l, si)
            let img = EcoArt.critter(.bee, frame: Int(t * 14 + Double(i)) % 2)
            l.contents = img
            l.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * 2, height: Double(img.height) * 2)
            let phase = t * 0.16 + Double(i) / 3
            let u = 0.5 - 0.5 * cos(phase * 2 * .pi)   // out to the patch and back home
            let x = door.x + (pp.x - door.x) * u + sin(t * 2.1 + Double(i) * 2) * 9
            let y = door.y + (pp.y + 14 - door.y) * u + sin(t * 3.3 + Double(i)) * 6 + sin(u * .pi) * 18
            let goingOut = sin(phase * 2 * .pi) > 0
            l.setAffineTransform(CGAffineTransform(scaleX: (goingOut == (pp.x > door.x)) ? 1 : -1, y: 1))
            l.position = CGPoint(x: x.rounded(), y: y.rounded())
        }
    }

    /// Autumn leaves / winter snow on the nest hut, and blossoms drifting off its roof in spring.
    private func renderSeason() {
        guard let nest = world.topStructures.first(where: { $0.kind == .nestHut })?.surface, let (si, pt) = local(Vec2(nest.minX, nest.y)) else {
            if let s = seasonLayer { fadeOut(s.layer); seasonLayer = nil }
            return
        }
        let k = CGFloat(artScale)
        let origin = CGPoint(x: (pt.x - 2 * k + nestSway).rounded(), y: (pt.y - 2 * k).rounded())
        if (3...5).contains(world.month), !world.isNight, CACurrentMediaTime() >= nextPetal {
            nextPetal = CACurrentMediaTime() + .random(in: 2.5...5)
            overlay.burst([Effects.petal], si: si, at: CGPoint(x: origin.x + .random(in: 6...60), y: origin.y + 70), count: 1, dx: -30...20, dy: -60 ... -30, duration: 3.2)
        }
        let key = "\(world.leafLevel)\(world.snowLevel)"
        guard let img = PorchArt.season(leaves: world.leafLevel, snow: world.snowLevel) else {
            if let s = seasonLayer { fadeOut(s.layer); seasonLayer = nil }
            return
        }
        var e = seasonLayer ?? {
            let l = pixelLayer(); l.zPosition = 1.165; l.anchorPoint = .zero
            return (l, "")
        }()
        attach(e.layer, si)
        if e.key != key {
            e.layer.contents = img
            e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            e.key = key
        }
        e.layer.position = origin
        seasonLayer = e
    }

    /// The firefly jar on the rain barrel's lid, glowing at night while there are fireflies in it.
    private func renderJar() {
        guard world.fireflyJar > 0, let spot = world.jarSpot, let (si, pt) = local(spot) else {
            if let j = jarLayer { fadeOut(j.layer); fadeOut(j.glow); jarLayer = nil }
            return
        }
        let t = CACurrentMediaTime()
        var e = jarLayer ?? {
            let l = pixelLayer(); l.zPosition = 1.17; l.anchorPoint = CGPoint(x: 0.5, y: 0)
            popIn(l)
            let glow = CAGradientLayer(); glow.type = .radial; glow.zPosition = 1.11
            glow.colors = [NSColor(red: 0.85, green: 1, blue: 0.45, alpha: 0.4).cgColor, NSColor(red: 0.8, green: 1, blue: 0.4, alpha: 0).cgColor]
            glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
            glow.bounds = CGRect(x: 0, y: 0, width: 70, height: 70)
            glow.actions = ["position": NSNull(), "opacity": NSNull(), "hidden": NSNull()]
            return (l, glow, "")
        }()
        attach(e.layer, si); attach(e.glow, si)
        let frame = Int(t * 2.5) % 3
        let key = "\(world.fireflyJar)\(frame)\(world.isNight)"
        if e.key != key {
            let img = PorchArt.jar(count: world.fireflyJar, frame: frame, night: world.isNight)
            e.layer.contents = img
            e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            e.key = key
        }
        e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
        e.glow.isHidden = !world.isNight
        e.glow.position = CGPoint(x: pt.x, y: pt.y + 8)
        e.glow.opacity = Float(0.55 + 0.1 * Double(world.fireflyJar) / 5 + 0.15 * sin(t * 2.2))
        jarLayer = e
    }

    // MARK: The vegetable patch, the mailbox and the lanterns (Porch.swift)

    /// The nest hut's little swing after a nudge (the patch sits on its porch, so it swings with it).
    private var nestSway: CGFloat {
        let age = world.homeNudgeAge
        return age < 3.5 && !world.notchHomeShowing ? CGFloat(4 * exp(-1.2 * age) * sin(age * 7)) : 0
    }

    private func renderPatch() {
        guard let mid = world.patchSpot(1), let (si, pt) = local(mid) else {
            if let p = patchLayer { fadeOut(p.layer); patchLayer = nil }
            return
        }
        var e = patchLayer ?? {
            let l = pixelLayer(); l.zPosition = 1.17
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            popIn(l)
            return (l, "")
        }()
        attach(e.layer, si)
        let img = PorchArt.bed(world.vegPatch)
        let key = "\(ObjectIdentifier(img as AnyObject))"
        if e.key != key {
            e.layer.contents = img
            e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            e.key = key
        }
        e.layer.position = CGPoint(x: (pt.x + nestSway).rounded(), y: pt.y.rounded() - 2)
        patchLayer = e
    }

    /// The mailbox hanging under the porch, its flag up while there's unread post.
    private func renderMailbox() {
        guard let spot = world.mailboxSpot, let (si, pt) = local(spot) else {
            if let m = mailLayer { fadeOut(m.layer); m.rope.removeFromSuperlayer(); mailLayer = nil }
            return
        }
        var e = mailLayer ?? {
            let l = pixelLayer(); l.zPosition = 1.15
            l.anchorPoint = CGPoint(x: 0.5, y: 1)
            let rope = CAShapeLayer(); rope.strokeColor = NSColor(red: 0.54, green: 0.42, blue: 0.29, alpha: 0.95).cgColor
            rope.lineWidth = 1.5; rope.fillColor = nil; rope.zPosition = 1.14; rope.actions = ["path": NSNull()]
            popIn(l)
            return (l, rope, "")
        }()
        attach(e.layer, si); attach(e.rope, si)
        let unread = world.unreadMail > 0
        let key = "mail\(unread)"
        if e.key != key {
            let img = PorchArt.mailbox(flag: unread, card: unread)
            e.layer.contents = img
            e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            e.key = key
        }
        let since = world.homeNudgeAge
        let sway = sin(CACurrentMediaTime() * 1.1 + 1) * 1.0 + (since < 3 ? 4 * exp(-1.4 * since) * sin(since * 8 + 1) : 0)
        let hangTop = pt.y - 3
        let top = CGPoint(x: pt.x.rounded() + sway, y: hangTop - 7)
        e.layer.position = top
        let path = CGMutablePath()
        path.move(to: CGPoint(x: pt.x.rounded(), y: hangTop)); path.addLine(to: CGPoint(x: top.x, y: top.y - 1))
        e.rope.path = path
        mailLayer = e
    }

    /// Resting the pointer on the mailbox: the postcards, on a little paper card beside it (towards the screen's middle,
    /// staying up in the corner).
    private func renderMailPanel() {
        guard world.mailOpen, let spot = world.mailboxSpot, let (si, pt) = local(spot), si < screens.count else {
            if let m = mailPanel { fadeOut(m.layer); mailPanel = nil }
            return
        }
        let scale = screens[si].scale
        let now = Date().timeIntervalSince1970
        let key = world.mailbox.map { "\($0.at)\($0.read)" }.joined() + "\(Int(now / 60))"
        var e = mailPanel ?? {
            let l = CALayer(); l.zPosition = 1.6
            l.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
            l.shadowColor = NSColor.black.cgColor; l.shadowOpacity = 0.18; l.shadowRadius = 5; l.shadowOffset = CGSize(width: 0, height: -2)
            let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 0; a.toValue = 1; a.duration = 0.2
            l.add(a, forKey: "in")
            return (l, "")
        }()
        attach(e.layer, si)
        if e.key != key, let img = PorchArt.postcards(world.mailbox, now: now, scale: scale) {
            e.layer.contents = img
            e.layer.bounds = CGRect(x: 0, y: 0, width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
            e.key = key
        }
        let size = e.layer.bounds.size
        let frame = screens[si].frame
        let leftSide = pt.x < frame.width / 2
        let x = leftSide ? pt.x + 18 : pt.x - 18 - size.width
        let y = pt.y - 10 - size.height
        e.layer.anchorPoint = .zero
        e.layer.position = CGPoint(x: min(max(8, x), frame.width - size.width - 8).rounded(), y: max(8, y).rounded())
        mailPanel = e
    }

    /// The lanterns set out along the moss: glowing all night, dark by day until they're taken in.
    private func renderLanterns() {
        var alive = Set<Int>()
        let t = CACurrentMediaTime()
        for l in world.mossLanterns {
            guard let spot = world.lanternSpot(l), let (si, pt) = local(spot.pos) else { continue }
            alive.insert(l.id)
            var e = lanternLayers[l.id] ?? {
                let layer = pixelLayer(); layer.zPosition = 1.12
                layer.anchorPoint = CGPoint(x: 1.5 / 7, y: 0)
                popIn(layer)
                let glow = CAGradientLayer(); glow.type = .radial; glow.zPosition = 1.11
                glow.colors = [NSColor(red: 1, green: 0.82, blue: 0.42, alpha: 0.42).cgColor, NSColor(red: 1, green: 0.75, blue: 0.3, alpha: 0).cgColor]
                glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
                glow.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
                glow.actions = ["position": NSNull(), "opacity": NSNull(), "hidden": NSNull()]
                return (layer, glow, nil)
            }()
            attach(e.layer, si); attach(e.glow, si)
            if e.lit != l.lit {
                let img = PorchArt.lantern(lit: l.lit)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * 2, height: Double(img.height) * 2)
                e.lit = l.lit
            }
            e.layer.isHidden = !spot.visible
            e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
            e.glow.isHidden = !spot.visible || !l.lit
            e.glow.position = CGPoint(x: pt.x + 8, y: pt.y + 13)
            e.glow.opacity = Float(0.8 + 0.12 * sin(t * 6.3 + Double(l.id) * 1.7) + 0.08 * sin(t * 17 + Double(l.id)))
            lanternLayers[l.id] = e
        }
        for (id, e) in lanternLayers where !alive.contains(id) { fadeOut(e.layer); fadeOut(e.glow); lanternLayers[id] = nil }
    }

    // MARK: The rain barrel and the basket lift (Homestead.swift)

    private func renderBarrel() {
        guard let spot = world.barrelSpot, let (si, pt) = local(spot) else {
            if let b = barrelLayer { fadeOut(b.layer); barrelLayer = nil }
            return
        }
        var e = barrelLayer ?? {
            let l = pixelLayer(); l.zPosition = 1.16
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            popIn(l)
            return (l, "")
        }()
        attach(e.layer, si)
        let level = world.rainBarrel >= 0.98 ? 3 : world.rainBarrel >= 0.5 ? 2 : world.rainBarrel >= 0.15 ? 1 : 0
        let key = "barrel\(level)-\(world.isNight)"
        if e.key != key {
            let img = EcoArt.barrel(level: level, night: world.isNight)
            e.layer.contents = img
            e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            e.key = key
        }
        e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded() - 1)
        barrelLayer = e
        // Raining: now and then a drop plinks in.
        let now = CACurrentMediaTime()
        if world.weather?.sky.isWet == true, now >= nextBarrelDrip {
            nextBarrelDrip = now + .random(in: 0.8...2.2)
            overlay.burst([ClimateArt.splash], si: si, at: CGPoint(x: pt.x, y: pt.y + 22), count: 1, dx: -4...4, dy: 0...3, duration: 0.35)
        }
    }

    private func renderBasket() {
        guard let p = world.basketPos, let porch = world.homePorch, let (si, pt) = local(p), let (_, top) = local(Vec2(p.x, porch.y)) else {
            if let b = basketLayer { fadeOut(b.layer); b.rope.removeFromSuperlayer(); basketLayer = nil }
            return
        }
        let e = basketLayer ?? {
            let l = pixelLayer(); l.zPosition = 1.2   // in front of whoever's riding: they peek over the rim
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.contents = EcoArt.basket
            l.bounds = CGRect(x: 0, y: 0, width: Double(EcoArt.basket.width) * artScale, height: Double(EcoArt.basket.height) * artScale)
            let rope = CAShapeLayer(); rope.strokeColor = NSColor(red: 0.54, green: 0.42, blue: 0.29, alpha: 0.95).cgColor
            rope.lineWidth = 1.5; rope.fillColor = nil; rope.zPosition = 1.14; rope.actions = ["path": NSNull()]
            popIn(l)
            return (l, rope)
        }()
        attach(e.layer, si); attach(e.rope, si)
        // A little swing on the rope: more on the way, and after a nudge.
        let t = CACurrentMediaTime()
        let since = world.homeNudgeAge
        let moving = world.basket.map { $0.phase != .waiting } ?? false
        let sway = sin(t * 1.6) * (moving ? 1.6 : 0.6) + (since < 3 ? 4 * exp(-1.4 * since) * sin(since * 8) : 0)
        let base = CGPoint(x: pt.x.rounded() + sway, y: pt.y.rounded() - 4)
        e.layer.position = base
        let h = Double(EcoArt.basket.height) * artScale
        let path = CGMutablePath()
        let anchor = CGPoint(x: top.x.rounded(), y: top.y - 2)
        let rim = CGPoint(x: base.x, y: base.y + h + 4)
        path.move(to: anchor); path.addLine(to: rim)
        // The two short cords down to the handles.
        path.move(to: rim); path.addLine(to: CGPoint(x: base.x - 12, y: base.y + h - 2))
        path.move(to: rim); path.addLine(to: CGPoint(x: base.x + 12, y: base.y + h - 2))
        e.rope.path = path
        basketLayer = e
    }

    // MARK: The bird and the pantry (Hanging.swift)

    private func renderBirds() {
        var alive = Set<Int>()
        let t = CACurrentMediaTime()
        for b in world.birds {
            guard let (si, pt) = local(b.pos) else { continue }
            alive.insert(b.id)
            // Wings beating in flight; perched, now and then a peck or a look about.
            let frame = b.flapping ? Int(t * 12 + Double(b.id)) % 2 : (sin(t * 0.9 + Double(b.id) * 2) > 0.75 ? 3 : 2)
            let key = "bird\(frame)"
            var e = birdLayers[b.id] ?? {
                let l = pixelLayer(); l.zPosition = 1.37
                l.anchorPoint = CGPoint(x: 0.5, y: 0)
                return (l, "")
            }()
            attach(e.layer, si)
            if e.key != key {
                let img = EcoArt.bird(frame: frame)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * 2, height: Double(img.height) * 2)
                e.key = key
            }
            e.layer.setAffineTransform(CGAffineTransform(scaleX: b.facing >= 0 ? 1 : -1, y: 1))
            e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded() - (b.flapping ? 0 : 1))
            birdLayers[b.id] = e
        }
        for (id, e) in birdLayers where !alive.contains(id) { e.layer.removeFromSuperlayer(); birdLayers[id] = nil }
    }

    /// The pantry: a woven acorn hanging off the end of the hanging home's porch, filling up with what they forage.
    private func renderPantry() {
        guard let porch = world.homePorch, let (si, pt) = local(Vec2(porch.maxX - 10, porch.y)) else {
            if let p = pantryLayer { fadeOut(p.layer); p.rope.removeFromSuperlayer(); pantryLayer = nil }
            return
        }
        var e = pantryLayer ?? {
            let l = pixelLayer(); l.zPosition = 1.15
            l.anchorPoint = CGPoint(x: 0.5, y: 1)
            let rope = CAShapeLayer(); rope.strokeColor = NSColor(red: 0.54, green: 0.42, blue: 0.29, alpha: 0.95).cgColor
            rope.lineWidth = 1.5; rope.fillColor = nil; rope.zPosition = 1.14; rope.actions = ["path": NSNull()]
            popIn(l)
            return (l, rope, "")
        }()
        attach(e.layer, si); attach(e.rope, si)
        let key = "pantry\(world.pantry)"
        if e.key != key {
            let img = EcoArt.pantry(fill: world.pantry)
            e.layer.contents = img
            e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            e.key = key
        }
        // Swinging a little on its rope, more so after a nudge.
        let since = world.homeNudgeAge
        let sway = sin(CACurrentMediaTime() * 1.3) * 1.2 + (since < 3 ? 5 * exp(-1.4 * since) * sin(since * 8) : 0)
        let hangTop = pt.y - 3
        let top = CGPoint(x: pt.x.rounded() + sway, y: hangTop - 10)
        e.layer.position = top
        let path = CGMutablePath()
        path.move(to: CGPoint(x: pt.x.rounded(), y: hangTop)); path.addLine(to: CGPoint(x: top.x, y: top.y - 2))
        e.rope.path = path
        pantryLayer = e
    }

    func handle(_ events: [HomeEvent]) {
        for e in events {
            switch e {
            case .foraged(let p, let by, let what):
                if let (si, pt) = local(p) { overlay.burst([Effects.leaf, Effects.leaf2], si: si, at: pt, count: 3, dx: -14...14, dy: 4...20, duration: 0.7) }
                if Int.random(in: 0..<3) == 0 {
                    let line = ["acorn": "An acorn!", "seeds": "Seeds for later!", "mushroom": "Ooh, a mushroom!", "berries": "Berries! 🫐"][what] ?? "Found one!"
                    overlay.showBubble(line, on: by, seconds: 1.5)
                }
            case .stocked(let p, let by, _):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle, Effects.smallStar], si: si, at: pt, count: 3, dx: -10...10, dy: 6...22, duration: 0.8) }
                if world.pantry >= World.pantryMax { overlay.showBubble("The pantry's full!", on: by, seconds: 1.8) }
                else if Int.random(in: 0..<4) == 0 { overlay.showBubble("For the pantry.", on: by, seconds: 1.4) }
            case .supper(let p, let by):
                if let (si, pt) = local(p) { overlay.burst([Effects.smallHeart], si: si, at: CGPoint(x: pt.x, y: pt.y + 30), count: 2, dx: -10...10, dy: 10...26, duration: 1.0, delay: 0.8, stagger: 0.4) }
                if Int.random(in: 0..<2) == 0 { overlay.showBubble(["Mmm, supper.", "Yum!", "Nom nom.", "Berries! 🫐"].randomElement()!, on: by, seconds: 1.6) }
            case .birdLanded(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.dust], si: si, at: pt, count: 1, dx: -6...6, dy: 0...4, duration: 0.4) }
            case .birdLeft(let p):
                if let (si, pt) = local(p) { overlay.burst([EcoArt.feather], si: si, at: CGPoint(x: pt.x, y: pt.y + 6), count: 1, dx: -10...10, dy: -20 ... -6, duration: 1.4) }
            case .birdSeed(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle], si: si, at: CGPoint(x: pt.x, y: pt.y + 4), count: 2, dx: -8...8, dy: 4...16, duration: 0.7) }
            case .nudged:
                break   // the house and the swing sway by themselves (see homeNudgedAt)
            case .cameOut(let by):
                overlay.showBubble(["Hi! 👋", "Who's there?", "Oh, hello!", "Coming!"].randomElement()!, on: by, seconds: 1.6)
            case .barrelFull(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle], si: si, at: CGPoint(x: pt.x, y: pt.y + 24), count: 3, dx: -10...10, dy: 4...16, duration: 0.8) }
            case .drewWater(let p, let by):
                if let (si, pt) = local(p) { overlay.burst([ClimateArt.splash], si: si, at: pt, count: 3, dx: -8...8, dy: 2...14, duration: 0.5, stagger: 0.12) }
                if Int.random(in: 0..<2) == 0 { overlay.showBubble(["Rainwater! 💧", "For the moss.", "Fresh from the sky."].randomElement()!, on: by, seconds: 1.5) }
            case .basketCalled(let by):
                if Int.random(in: 0..<2) == 0 { overlay.showBubble(["Basket, please!", "Going up!", "Lift! 👋"].randomElement()!, on: by, seconds: 1.5) }
            case .basketAboard:
                break
            case .basketArrived(let p, let by, let up):
                if let (si, pt) = local(p) { overlay.burst([Effects.dust], si: si, at: pt, count: 2, dx: -10...10, dy: 0...6, duration: 0.4) }
                if up, Int.random(in: 0..<3) == 0 { overlay.showBubble(["Home!", "Made it!", "Wheee."].randomElement()!, on: by, seconds: 1.4) }
            case .sowed(let p, let by, let what):
                if let (si, pt) = local(p) { overlay.burst([Effects.dust], si: si, at: pt, count: 2, dx: -6...6, dy: 0...6, duration: 0.5) }
                if Int.random(in: 0..<3) == 0 {
                    let line = ["carrot": "Carrots, please.", "radish": "Grow, little radish!", "peas": "Peas! Lots of peas.", "strawberry": "Strawberries soon!", "pumpkin": "Grow big, pumpkin."][what] ?? "In you go."
                    overlay.showBubble(line, on: by, seconds: 1.5)
                }
            case .patchWatered(let p, let by, let rain):
                if let (si, pt) = local(p) { overlay.burst([ClimateArt.splash], si: si, at: pt, count: 3, dx: -6...6, dy: 0...10, duration: 0.5, stagger: 0.12) }
                if rain, Int.random(in: 0..<3) == 0 { overlay.showBubble("Rainwater 💧", on: by, seconds: 1.4) }
            case .patchRipe(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle], si: si, at: CGPoint(x: pt.x, y: pt.y + 16), count: 2, dx: -6...6, dy: 2...12, duration: 0.8, stagger: 0.2) }
            case .harvested(let p, let by, let what):
                if let (si, pt) = local(p) { overlay.burst([Effects.leaf, Effects.leaf2], si: si, at: pt, count: 3, dx: -10...10, dy: 4...18, duration: 0.7) }
                if Int.random(in: 0..<2) == 0 {
                    let line = ["carrot": "A carrot! 🥕", "radish": "Radish!", "peas": "Peas! 🫛", "strawberry": "Strawberry! 🍓", "pumpkin": "A pumpkin! 🎃", "tomato": "Tomato! 🍅"][what] ?? "Ripe!"
                    overlay.showBubble(line, on: by, seconds: 1.5)
                }
            case .mailArrived(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle], si: si, at: CGPoint(x: pt.x, y: pt.y - 14), count: 2, dx: -8...8, dy: 0...10, duration: 0.8, stagger: 0.2) }
            case .mailRead:
                break
            case .lanternHung(let p, let by):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle], si: si, at: pt, count: 1, dx: -4...4, dy: 0...8, duration: 0.7) }
                if Int.random(in: 0..<4) == 0 { overlay.showBubble(["There. Cozy.", "Light for the moss.", "Night night, moss."].randomElement()!, on: by, seconds: 1.5) }
            case .lanternTaken:
                break
            case .beeBonus(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.smallHeart, Effects.sparkle], si: si, at: pt, count: 2, dx: -8...8, dy: 4...16, duration: 0.9, stagger: 0.2) }
            case .swept(let p, let by, let snow):
                if let (si, pt) = local(p) {
                    overlay.burst(snow ? [Effects.snow] : [Effects.leaf, Effects.leaf2], si: si, at: pt, count: 8, dx: -50...50, dy: -40 ... 10, duration: 1.6, stagger: 0.08)
                }
                if Int.random(in: 0..<2) == 0 { overlay.showBubble(snow ? ["Brr! All clear.", "Shoo, snow!"].randomElement()! : ["Tidy!", "Swish swish.", "All swept."].randomElement()!, on: by, seconds: 1.5) }
            case .jarCaught(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle], si: si, at: CGPoint(x: pt.x, y: pt.y + 12), count: 2, dx: -6...6, dy: 0...10, duration: 0.7) }
            case .jarReleased(let p, let count):
                if let (si, pt) = local(p) { overlay.burst([Effects.sparkle, Effects.smallStar], si: si, at: CGPoint(x: pt.x, y: pt.y + 16), count: count * 2, dx: -40...40, dy: 30...90, duration: 2.2, stagger: 0.15) }
            case .seedGift(let by, let what):
                if let by {
                    let name = ["strawberry": "strawberry", "pumpkin": "pumpkin", "tomato": "tomato"][what] ?? what
                    let emoji = ["strawberry": " 🍓", "pumpkin": " 🎃", "tomato": " 🍅"][what] ?? ""
                    overlay.showBubble("I brought \(name) seeds!\(emoji)", on: by, seconds: 2.6)
                }
            }
        }
    }

    // MARK: The hollow log (doorway to the other screen)

    private func renderLog(peerOnline: Bool) {
        guard let d = world.door, let main = world.screens.first, !world.compact,
              let (si, pt) = local(Vec2(d > 0 ? main.maxX : main.minX, main.minY)) else {
            if let l = logLayer { fadeOut(l.layer); fadeOut(l.glow); logLayer = nil }
            return
        }
        let key = "\(d)-\(peerOnline)-\(world.month)"
        var e = logLayer ?? {
            let l = pixelLayer(); l.zPosition = 0.9
            l.anchorPoint = CGPoint(x: 1, y: 0)
            let glow = CALayer()
            glow.bounds = CGRect(x: 0, y: 0, width: 12, height: 18)
            glow.cornerRadius = 6
            glow.backgroundColor = NSColor(red: 1, green: 0.82, blue: 0.45, alpha: 0.55).cgColor
            glow.shadowColor = NSColor(red: 1, green: 0.8, blue: 0.4, alpha: 1).cgColor
            glow.shadowOpacity = 1; glow.shadowRadius = 12; glow.shadowOffset = .zero
            glow.zPosition = 0.91
            glow.actions = ["position": NSNull(), "opacity": NSNull()]
            let pulse = CABasicAnimation(keyPath: "shadowRadius"); pulse.fromValue = 6; pulse.toValue = 16
            pulse.duration = 1.6; pulse.autoreverses = true; pulse.repeatCount = .infinity
            glow.add(pulse, forKey: "pulse")
            popIn(l)
            return (l, glow, d, "")
        }()
        attach(e.glow, si); attach(e.layer, si)
        if e.key != key {
            let img = EcoArt.log(month: world.month)
            e.layer.contents = img
            e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
            e.glow.opacity = peerOnline ? 1 : 0.15
            e.key = key
        }
        // The open end faces into the screen; the rest of the log runs off the edge, onto the other screen.
        e.layer.setAffineTransform(CGAffineTransform(scaleX: d > 0 ? 1 : -1, y: 1))
        e.layer.anchorPoint = CGPoint(x: d > 0 ? 0 : 0, y: 0)
        let w = e.layer.bounds.width
        e.layer.position = CGPoint(x: (d > 0 ? pt.x - w * 0.62 : pt.x + w * 0.62).rounded(), y: pt.y.rounded())
        // Warm light at the far end of the hollow while the other screen is open.
        e.glow.position = CGPoint(x: (d > 0 ? pt.x - w * 0.62 + 5 * artScale : pt.x + w * 0.62 - 5 * artScale).rounded(), y: (pt.y + 7.5 * artScale).rounded())
        e.side = d
        logLayer = e
    }

    // MARK: Critters

    private func renderCritters() {
        var alive = Set<Int>()
        let t = CACurrentMediaTime()
        for k in world.critters {
            guard let p = world.position(of: k), let (si, pt) = local(p) else { continue }
            // Hidden while a window is over it (crawlers walk along the top, so check just above it).
            if k.onHand == nil, !k.leaving, let w = world.windows[k.windowID], isCovered(Vec2(p.x, p.y + 2), owner: k.windowID, top: w.maxY) { continue }
            alive.insert(k.id)
            let frame: Int
            switch k.kind {
            case .bee: frame = Int(t * 14 + k.phase) % 2
            case .ladybug: frame = k.leaving ? 2 + Int(t * 16) % 2 : (k.isMoving ? Int(t * 8 + k.phase) % 2 : 0)
            case .snail: frame = k.isMoving ? Int(t * 2.5 + k.phase) % 4 : 4 + (Int(t * 0.8 + k.phase) % 2)
            }
            let key = "\(k.kind.rawValue)\(frame)"
            var e = critterLayers[k.id] ?? {
                let l = pixelLayer(); l.zPosition = 1.36
                l.anchorPoint = CGPoint(x: 0.5, y: 0)
                popIn(l)
                return (l, "")
            }()
            attach(e.layer, si)
            if e.key != key {
                let img = EcoArt.critter(k.kind, frame: frame)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * 2, height: Double(img.height) * 2)
                e.key = key
            }
            e.layer.setAffineTransform(CGAffineTransform(scaleX: k.facing >= 0 ? 1 : -1, y: 1))
            let bob = k.kind == .bee ? sin(t * 5 + k.phase) * 1.5 : 0
            e.layer.position = CGPoint(x: pt.x.rounded(), y: (pt.y + bob).rounded())
            critterLayers[k.id] = e
        }
        for (id, e) in critterLayers where !alive.contains(id) { fadeOut(e.layer); critterLayers[id] = nil }
    }

    /// A window in front of `owner` covers this point.
    private func isCovered(_ p: Vec2, owner: Int, top: Double) -> Bool {
        for id in world.windowOrder {
            if id == owner { return false }
            if let r = world.windows[id], p.x >= r.minX, p.x <= r.maxX, p.y >= r.minY, p.y <= r.maxY { return true }
        }
        return false
    }

    // MARK: Events

    func handle(_ events: [EcoEvent]) {
        for e in events {
            switch e {
            case .tunnelDive(let p, let by):
                if let (si, pt) = local(p) {
                    overlay.burst([Effects.leaf, Effects.leaf2, Effects.dust], si: si, at: pt, count: 7, dx: -40...40, dy: 6...46, duration: 0.9, stagger: 0.02)
                }
                overlay.showBubble(["Through the moss tunnel!", "Off to visit! 🌿", "Wheee, tunnel!"].randomElement()!, on: by, seconds: 1.8)
            case .tunnelPop(let p, _):
                if let (si, pt) = local(p) {
                    overlay.burst([Effects.leaf, Effects.leaf2, Effects.sparkle], si: si, at: CGPoint(x: pt.x, y: pt.y + 8), count: 6, dx: -30...30, dy: 10...50, duration: 0.9, delay: 0.1, stagger: 0.03)
                }
            case .dockHop(let p, _):
                if let (si, pt) = local(p) {
                    overlay.burst([Effects.dust], si: si, at: CGPoint(x: pt.x, y: pt.y + 2), count: 2, dx: -16...16, dy: 0...6, duration: 0.5)
                }
            case .dockBounce(let p, let by, _):
                if let (si, pt) = local(p) {
                    overlay.burst([Effects.star, Effects.smallStar, Effects.sparkle], si: si, at: CGPoint(x: pt.x, y: pt.y + 6), count: 6, dx: -30...30, dy: 10...60, duration: 0.9, stagger: 0.03)
                }
                overlay.showBubble(["Wheee!", "Boing!", "Whoa, it bounced!"].randomElement()!, on: by, seconds: 1.4)
            case .dockCheer(let by, let app):
                overlay.showBubble(["Ooh, \(app)!", "Hi, \(app)!", "\(app) time!"].randomElement()!, on: by, seconds: 1.6)
            case .dockMail(let p, let by, let app, let badge):
                if let (si, pt) = local(p) {
                    overlay.burst([Effects.sparkle], si: si, at: CGPoint(x: pt.x, y: pt.y + 4), count: 3, dx: -14...14, dy: 8...26, duration: 0.7)
                }
                overlay.showBubble(badge.isEmpty || badge.count > 3 ? "Something new in \(app)!" : "\(badge) new in \(app)!", on: by, seconds: 2.0)
            case .dockWave(let by, let app):
                overlay.showBubble("Bye, \(app)!", on: by, seconds: 1.4)
            case .dockNap(let by):
                if Int.random(in: 0..<3) == 0 { overlay.showBubble("Comfy up here…", on: by, seconds: 1.6) }
            case .critterHello(let p, let by, let kind):
                if let (si, pt) = local(p) {
                    overlay.burst([Effects.smallHeart], si: si, at: CGPoint(x: pt.x, y: pt.y + 8), count: 2, dx: -10...10, dy: 10...26, duration: 0.9)
                }
                if Int.random(in: 0..<2) == 0 {
                    let line: String
                    switch kind {
                    case .ladybug: line = ["Hi, little one!", "A ladybug! 🐞", "Hop on!"].randomElement()!
                    case .bee: line = ["Hello, bee!", "Busy busy!", "Bzz to you too."].randomElement()!
                    case .snail: line = ["Take your time.", "Hi, snail!", "Slow and steady."].randomElement()!
                    }
                    overlay.showBubble(line, on: by, seconds: 1.6)
                }
            case .critterFlew(let p):
                if let (si, pt) = local(p) { overlay.burst([Effects.smallStar], si: si, at: pt, count: 2, dx: -12...12, dy: 6...20, duration: 0.6) }
            }
        }
    }
}

/// Pixel art for the ecosystem: critters and the hollow log.
enum EcoArt {
    private static var cache: [String: CGImage] = [:]

    /// A little brown bird with a robin's breast (facing right): 0/1 wings up/down in flight, 2 perched, 3 pecking.
    static func bird(frame: Int) -> CGImage {
        let key = "bird\(frame)"
        if let c = cache[key] { return c }
        let rows: [[String]] = [
            ["...BB......",
             "...BBB.bbb.",
             "bb..BBbbkbo",
             ".bbbbbbrrr.",
             "...bbbrrr..",
             "...........",
             "..........."],
            ["...........",
             ".......bbb.",
             "bb..bbbbkbo",
             ".bbbbbbrrr.",
             "...BBBrrr..",
             "...BBB.....",
             "....B......"],
            ["......bbb..",
             ".....bbkbbo",
             "bb..bbbbbb.",
             ".bbbbbbrrr.",
             "..bBBBbrrr.",
             "...bBBrrr..",
             "....l..l..."],
            ["...........",
             "......bbb..",
             "bb..bbbkbbo",
             ".bbbbbbrrr.",
             "..bBBBbrrr.",
             "...bBBrrr..",
             "....l..l..."],
        ]
        let img = PropArt.image(PropArt.grid(rows[max(0, min(3, frame))], ["b": 0x8A6A4A, "B": 0x5E4630, "r": 0xE07A4A, "k": 0x1E1A16, "o": 0xF2B640, "l": 0x6B4A2A]))
        cache[key] = img
        return img
    }

    /// A drifting feather.
    static let feather: CGImage = PropArt.image(PropArt.grid([".b", "bB", "bB", "b."], ["b": 0xA88664, "B": 0x6B4A2A]))

    /// The pantry: a woven acorn with a leafy cap, an opening at the front showing what's stored (0...6).
    /// The rain barrel on the porch: empty (dark inside), some, most, brimming.
    static func barrel(level: Int, night: Bool) -> CGImage {
        let key = "barrel\(level)\(night)"
        if let c = cache[key] { return c }
        let water: Character = level == 0 ? "o" : level == 3 ? "L" : "q"
        var rows = [
            ".hhhhhh.",
            level == 1 ? "hoqqqqoh" : "h" + String(repeating: water, count: 6) + "h",
            "bBbBbBbB",
            "HHHHHHHH",
            "bBbBbBbB",
            "bBbBbBbB",
            "HHHHHHHH",
            ".bBbBbB.",
        ]
        if level == 3 { rows.insert("..L..L..", at: 0) }   // brimming over
        let img = PropArt.image(PropArt.grid(rows, [
            "h": 0x4A3220, "H": 0x5E5A52, "b": 0x8A5A35, "B": 0x9E6A3A, "o": 0x2A1A10,
            "q": night ? 0x3E6A8C : 0x5BA7D9, "L": night ? 0x6E9CC0 : 0x9FD8F5,
        ]))
        cache[key] = img
        return img
    }

    /// The basket lift: woven, with a rope handle at each end.
    static let basket: CGImage = PropArt.image(PropArt.grid([
        "w..........w",
        "Wc........cW",
        "wWwWwWwWwWwW",
        "WwWwWwWwWwWw",
        "wWwWwWwWwWwW",
        ".WwWwWwWwWw.",
    ], ["w": 0xC9A15A, "W": 0x9C7840, "c": 0x6B4428]))

    static func pantry(fill: Int) -> CGImage {
        let key = "pantry\(fill)"
        if let c = cache[key] { return c }
        var rows = [
            "....s....",
            "..ccccc..",
            ".cCcCcCc.",
            "ccccccccc",
            ".wWwWwWw.",
            ".wWoooWw.",
            ".wooooow.",
            ".wooooow.",
            "..wWwWw..",
            "...wWw...",
            "....w....",
        ].map { Array($0) }
        // Fill the opening from the bottom: berries, seeds, acorns, mushrooms.
        let holes = [(7, [2, 3, 4, 5, 6]), (6, [2, 3, 4, 5, 6]), (5, [3, 4, 5])].flatMap { r, xs in xs.map { (r, $0) } }
        let filled = Int((Double(holes.count) * Double(max(0, min(World.pantryMax, fill))) / Double(World.pantryMax)).rounded())
        let goods: [Character] = ["r", "y", "a", "p", "r", "m"]
        for (i, (r, x)) in holes.prefix(filled).enumerated() { rows[r][x] = goods[(i * 5 + r) % goods.count] }
        let img = PropArt.image(PropArt.grid(rows.map { String($0) }, [
            "s": 0x6B4428, "c": 0x8A5A35, "C": 0xA9743F, "w": 0xC9A15A, "W": 0x9C7840, "o": 0x3A2614,
            "r": 0xD9443A, "y": 0xF2D27A, "a": 0x9E6A3A, "p": 0x7B4FB0, "m": 0xF2E6D0,
        ]))
        cache[key] = img
        return img
    }

    static func critter(_ kind: Critter.Kind, frame: Int) -> CGImage {
        let key = "\(kind.rawValue)\(frame)"
        if let c = cache[key] { return c }
        let img: CGImage
        switch kind {
        case .ladybug:
            // Red shell with spots, black head (facing right); frames 0/1 walking, 2/3 wings out flying.
            let legs = frame % 2 == 0 ? ".k.k.k..." : "k.k.k...."
            let wings = frame >= 2 ? (frame == 2 ? ".ww..ww.." : "..ww.ww..") : "........."
            img = PropArt.image(PropArt.grid([
                wings,
                "..rrrr...",
                ".rhrkrkk.",
                "rrkrrrkwk",
                ".rrrkrkk.",
                legs,
            ], ["r": 0xE0453A, "h": 0xFF8A7A, "k": 0x2B2620, "w": 0xEAF4FF]))
        case .bee:
            // Fuzzy and round, wings a blur (two frames).
            let wings = frame == 0 ? "...ww.ww." : "..www.ww."
            img = PropArt.image(PropArt.grid([
                wings,
                "....wwww.",
                ".yykyykyk",
                "kyykyykwk",
                ".yykyyky.",
                "..k...k..",
            ], ["y": 0xFFD84A, "k": 0x3A2E22, "w": 0xEAF4FF]))
        case .snail:
            // A little snail: a stretching foot (frames 0-3) or resting with its eyestalks looking about (4-5).
            let stretch = frame < 4 ? [0, 1, 1, 0][frame] : 0
            let look = frame >= 4 ? frame - 4 : 0
            var rows = [
                look == 0 ? ".......k.k" : "......k..k",
                look == 0 ? ".......b.b" : "......b..b",
                "..sss...bb",
                ".sSSss..bb",
                "sSsSsss.bb",
                "sSSSss.bbb",
            ]
            rows.append(String(repeating: "b", count: 10 + stretch))
            rows = rows.map { stretch > 0 && !$0.hasPrefix("b") ? "." + $0 : $0 }
            img = PropArt.image(PropArt.grid(rows, ["s": 0xC98B4A, "S": 0x8A5A35, "b": 0xB9C98A, "k": 0x2B2620]))
        }
        cache[key] = img
        return img
    }

    /// A hollow mossy log lying at the screen's edge, its open end facing in (drawn opening on the left).
    static func log(month: Int) -> CGImage {
        let key = "log\(month)"
        if let c = cache[key] { return c }
        let w = 32, h = 15, top = 4
        var g: PropArt.Grid = Array(repeating: Array(repeating: nil, count: w), count: h + top)
        func put(_ x: Int, _ y: Int, _ c: UInt32) { if x >= 0, x < w, y >= 0, y < h + top { g[y][x] = c } }
        let barkHi: UInt32 = 0xA27A55, bark: UInt32 = 0x84603F, barkLow: UInt32 = 0x654630, barkDeep: UInt32 = 0x4A3222
        let ring: UInt32 = 0xE2BE8A, ringMid: UInt32 = 0xC99C66, ringDark: UInt32 = 0x9E7146
        let hollow: UInt32 = 0x24170C, hollowMid: UInt32 = 0x3B2715
        let moss: UInt32 = 0x6CC04A, mossDark: UInt32 = 0x3E8A3A, mossLight: UInt32 = 0x9BDB6E
        // The trunk: a lying cylinder (lit from above), its bark in long horizontal furrows.
        for y in 0..<h {
            let band = y < 3 ? barkHi : y < 8 ? bark : y < 12 ? barkLow : barkDeep
            for x in 4..<w {
                var c = band
                let off = (y * 7) % 11
                if y > 1, y < h - 1, (x + off) % 12 < 4, y % 3 != 0 { c = y < 8 ? barkLow : barkDeep }
                if y == 0 && x % 6 == 3 { c = bark }
                put(x, y + top, c)
            }
        }
        // The open end: rings of pale wood round a dark hollow.
        let cx = 5.0, cy = Double(h) / 2, rx = 5.2, ry = Double(h) / 2
        for y in 0..<h { for x in 0..<11 {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
            let e = dx * dx + dy * dy
            guard e <= 1 else { continue }
            put(x, y + top, e < 0.38 ? hollow : e < 0.55 ? hollowMid : e < 0.7 ? ringDark : e < 0.86 ? ringMid : ring)
        }}
        // Moss draped over the top in soft lumps, spilling down the side here and there.
        var seed: UInt32 = 0x9E3779B9
        func rnd() -> UInt32 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed }
        for x in 3..<w {
            let lump = Int(rnd() % 3)
            for y in (top - lump)..<(top + 2) { put(x, y, y == top + 1 ? mossDark : (rnd() % 5 == 0 ? mossLight : moss)) }
            if rnd() % 6 == 0 { let len = 2 + Int(rnd() % 4); for y in (top + 2)..<(top + 2 + len) { put(x, y, y == top + 1 + len ? mossDark : moss) } }
        }
        // A pair of little mushrooms on top.
        let autumn = [9, 10, 11].contains(month)
        let cap: UInt32 = autumn ? 0xC8642E : 0xE0453A, dot: UInt32 = 0xFFF4E0, stem: UInt32 = 0xEFE3C8
        for (mx, big) in [(19, true), (26, false)] {
            let base = top - 2
            put(mx, base, stem)
            if big {
                for dx in -2...2 { put(mx + dx, base - 1, cap) }
                for dx in -1...1 { put(mx + dx, base - 2, cap) }
                put(mx - 1, base - 1, dot); put(mx + 1, base - 2, dot)
            } else {
                for dx in -1...1 { put(mx + dx, base - 1, cap) }
                put(mx, base - 2, cap)
            }
        }
        let img = PropArt.image(g)
        cache[key] = img
        return img
    }
}
