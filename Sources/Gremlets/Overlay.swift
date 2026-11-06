import AppKit
import QuartzCore
import GremletsCore

/// A transparent, borderless, always-on-top panel covering one screen.
///
/// Click-through: the panel ignores mouse events by default, so clicks fall through to whatever is
/// underneath. `OverlayController` flips `ignoresMouseEvents` off only while the cursor is over an opaque
/// sprite pixel, so creatures are clickable but transparent areas never block your work.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Present on every Space and over full-screen apps; never shows in Cmd-Tab or Mission Control.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Root view; forwards mouse events (in global coordinates) to the controller.
final class OverlayView: NSView {
    weak var controller: OverlayController?
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { controller?.mouseDown(at: NSEvent.mouseLocation, time: e.timestamp) }
    override func mouseDragged(with e: NSEvent) { controller?.mouseDragged(to: NSEvent.mouseLocation, time: e.timestamp) }
    override func mouseUp(with e: NSEvent) { controller?.mouseUp(at: NSEvent.mouseLocation, time: e.timestamp) }
}

/// Owns one panel per screen, mirrors world state into CALayers, and handles mouse input.
final class OverlayController {
    private struct Screen {
        let frame: CGRect
        let panel: OverlayPanel
        let root: CALayer
    }

    let world: World
    let species: [String: LoadedSpecies]
    private var screens: [Screen] = []
    private var layers: [Int: CALayer] = [:]
    private var shownFrame: [Int: Int] = [:]
    private var layerScreen: [Int: Int] = [:]
    private var sleepBubbleTimer: [Int: Double] = [:]
    /// Speech bubbles: creature id → bubble layer, the screen it's on, and when it goes away.
    private var bubbles: [Int: (layer: CALayer, screen: Int, until: CFTimeInterval)] = [:]
    /// Hobby / Claude-buddy props per worker (creature id): the creation and the ladder.
    private var props: [Int: PropState] = [:]
    private var balloons: [Int: CALayer] = [:]
    let keepsakes = KeepsakeStore()
    let seedBook = SeedBook()
    /// Called when the seed book or today's harvest changes (the menu shows them).
    var onGardenChange: () -> Void = {}
    private var nextButterfly: [Int: Double] = [:]
    private var keepsakeLayers: [CALayer] = []
    private struct PropState {
        var screen: Int
        var anchorX: Double = 0
        var harvest: [Plant] = []
        var nextSparkle = 0.0
        var nextFirefly = 0.0
        var glow = ""
        var contentRows = 10
        var recorded = 0
        let item = CALayer()
        var shelf: CALayer?
        var shelfPx = 0
        var lantern: CALayer?
        var wasOnShelf = false
        var key = ""
        var beat = 0
        var celebrated = false
        var lingerUntil: CFTimeInterval?
    }

    // Input state.
    private var pressed: Creature?
    /// A creation you pressed on (worker id).
    private var pressedProp: Int?
    private var hoverID: Int?
    private var hoverSince = 0.0
    private var hoverShown: [Int: Double] = [:]
    private var pressStart: Vec2 = .zero
    private var dragging = false
    private var lastMouse: Vec2?
    private var monitors: [Any] = []

    var paused = false { didSet { if paused { setClickThrough(nil) } } }

    /// Hidden (boss key / on a call): panels leave the screen entirely, so nothing can show up in a screen share.
    var hidden = false {
        didSet {
            guard hidden != oldValue else { return }
            for s in screens {
                if hidden {
                    s.panel.orderOut(nil)
                } else {
                    s.panel.orderFrontRegardless()
                }
            }
            if hidden {
                // Let go of anything mid-drag so it drops normally when they come back.
                if dragging, let c = pressed { world.endDrag(c, time: CACurrentMediaTime()); NSCursor.pop() }
                pressed = nil; dragging = false; setClickThrough(nil)
            }
        }
    }

    init(world: World, species: [String: LoadedSpecies]) {
        self.world = world
        self.species = species
        rebuildScreens()
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.mouseMoved() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { handler($0); return $0 }) { monitors.append(l) }
    }

    func rebuildScreens() {
        for s in screens { s.panel.orderOut(nil) }
        screens = NSScreen.screens.map { ns in
            let panel = OverlayPanel(screen: ns)
            let view = OverlayView(frame: CGRect(origin: .zero, size: ns.frame.size))
            view.controller = self
            let root = CALayer()
            root.frame = view.bounds
            view.layer = root
            view.wantsLayer = true
            panel.contentView = view
            if !hidden { panel.orderFrontRegardless() }
            return Screen(frame: ns.frame, panel: panel, root: root)
        }
        layerScreen.removeAll()
        for (_, l) in layers { l.removeFromSuperlayer() }
        refreshKeepsakes()
    }

    /// Draws the keepsake garden along the floor of the main screen, behind everything else.
    func refreshKeepsakes() {
        for l in keepsakeLayers { l.removeFromSuperlayer() }
        keepsakeLayers.removeAll()
        guard let main = NSScreen.screens.first, !screens.isEmpty else { return }
        let floorY = main.visibleFrame.minY - main.frame.minY
        for item in keepsakes.items {
            guard let img = PropArt.keepsakeImage(item.kind, golden: item.variant == 1) else { continue }
            let l = pixelLayer(0, anchor: CGPoint(x: 0.5, y: 0))
            setImage(l, img)
            l.position = CGPoint(x: (item.x * main.frame.width).rounded(), y: floorY)
            screens[0].root.insertSublayer(l, at: 0)
            keepsakeLayers.append(l)
        }
        world.gardenSpots = keepsakes.items.filter { PropArt.keepsakeImage($0.kind) != nil }.map { main.frame.minX + $0.x * main.frame.width }
    }

    var keepsakeCount: Int { keepsakes.items.count }

    func clearKeepsakes() { keepsakes.clear(); refreshKeepsakes() }

    private func screenIndex(for p: Vec2) -> Int {
        screens.firstIndex { $0.frame.contains(CGPoint(x: p.x, y: p.y)) }
            ?? screens.indices.min { distance(p, screens[$0].frame) < distance(p, screens[$1].frame) } ?? 0
    }

    private func distance(_ p: Vec2, _ r: CGRect) -> Double {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    // MARK: Rendering

    func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var alive = Set<Int>()
        for c in world.creatures {
            alive.insert(c.id)
            guard let sp = species[c.species.id], !screens.isEmpty else { continue }
            let layer = layers[c.id] ?? makeLayer(for: c)
            let si = screenIndex(for: c.pos + Vec2(0, c.size.y / 2))
            if layerScreen[c.id] != si {
                layer.removeFromSuperlayer()
                screens[si].root.addSublayer(layer)
                layer.contentsScale = screens[si].panel.backingScaleFactor
                layerScreen[c.id] = si
            }
            let origin = screens[si].frame.origin
            // Only touch layer properties that changed; every write dirties the layer tree for the next commit.
            let pos = CGPoint(x: (c.pos.x - origin.x).rounded(), y: (c.pos.y - origin.y).rounded())
            if layer.position != pos { layer.position = pos }
            let flip: CGFloat = c.facing < 0 ? -1 : 1
            if layer.affineTransform().a != flip { layer.setAffineTransform(CGAffineTransform(scaleX: flip, y: 1)) }
            let f = c.currentFrame
            if shownFrame[c.id] != f, f < sp.frames.count {
                layer.contents = sp.frames[f]
                shownFrame[c.id] = f
            }
            if c.activity == .sleep || c.isDozingAtWork {
                let now = CACurrentMediaTime()
                if now - (sleepBubbleTimer[c.id] ?? 0) > 1.6 {
                    sleepBubbleTimer[c.id] = now
                    spawnEffect(Effects.zzz, above: c, drift: 18 * c.facing)
                }
            }
        }
        updateBubbles(alive: alive)
        updateProps()
        updateHover()
        for id in layers.keys where !alive.contains(id) {
            layers[id]?.removeFromSuperlayer()
            layers[id] = nil; shownFrame[id] = nil; layerScreen[id] = nil
        }
        CATransaction.commit()
    }

    private func makeLayer(for c: Creature) -> CALayer {
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: c.size.x, height: c.size.y)
        l.anchorPoint = CGPoint(x: 0.5, y: 0)
        l.magnificationFilter = .nearest
        l.minificationFilter = .nearest
        layers[c.id] = l
        return l
    }

    func handle(_ events: [WorldEvent]) {
        for e in events {
            switch e {
            case .poked(let id):
                if let c = creature(id) { spawnEffect(Effects.heart, above: c, drift: 0) }
            case .petted(let id):
                if let c = creature(id) {
                    spawnEffect(Effects.heart, above: c, drift: -14)
                    spawnEffect(Effects.smallHeart, above: c, drift: 16, delay: 0.25)
                }
            case .alert(let id):
                if let c = creature(id) { spawnPop(Effects.bang, above: c) }
            case .wokeUp(let id):
                if let c = creature(id), c.activity == .wake { spawnPop(Effects.bang, above: c) }
            case .dizzy(let id):
                if let c = creature(id) { spawnStars(around: c) }
            case .landed(let id, let impact):
                if impact > 650, let c = creature(id) { spawnDust(at: c, strength: min(1, impact / 2000)) }
            case .special(let id, let effect):
                if let c = creature(id) { spawnSpecial(effect, c) }
            case .greet(let a, let b):
                if let ca = creature(a), let cb = creature(b), let (si, pa) = localPoint(ca, dy: ca.size.y * 0.8), let (_, pb) = localPoint(cb) {
                    burst([Effects.heart], si: si, at: CGPoint(x: (pa.x + pb.x) / 2, y: pa.y), count: 1, dx: 0...0, dy: 30...40, duration: 1.3)
                }
            case .tagged(let id), .startled(let id):
                if let c = creature(id) { spawnPop(Effects.bang, above: c) }
            case .bump(let a, let b):
                if let ca = creature(a), let cb = creature(b), let (si, pa) = localPoint(ca, dy: ca.size.y * 0.5), let (_, pb) = localPoint(cb) {
                    burst([Effects.smallStar, Effects.star], si: si, at: CGPoint(x: (pa.x + pb.x) / 2, y: pa.y), count: 4, dx: -26...26, dy: 4...26, duration: 0.6)
                }
            case .stacked(let rider, _):
                if let c = creature(rider) { spawnEffect(Effects.smallHeart, above: c, drift: 10) }
            case .danceBeat(let id):
                if let c = creature(id), let (si, p) = localPoint(c, dy: c.size.y * 0.75) {
                    burst([Effects.note, Effects.note2], si: si, at: p, count: 1, dx: -26...26, dy: 26...42, duration: 1.1)
                }
            case .tookOff(let id):
                if let c = creature(id) { spawnDust(at: c, strength: 0.3) }
            default: break
            }
        }
    }

    /// Signature-move particles, timed to the "action" frames of the special animation (after the wind-up).
    private func spawnSpecial(_ effect: String, _ c: Creature) {
        guard let (si, feet) = localPoint(c) else { return }
        let f = c.facing
        let mouth = CGPoint(x: feet.x + f * c.size.x * 0.22, y: feet.y + c.size.y * 0.42)
        let head = CGPoint(x: feet.x, y: feet.y + c.size.y * 0.75)
        let mid = CGPoint(x: feet.x, y: feet.y + c.size.y * 0.45)
        let d = 0.3
        switch effect {
        case "fire":
            burst([Effects.flame, Effects.flame2], si: si, at: mouth, count: 7, dx: f < 0 ? -90 ... -45 : 45...90, dy: -4...18, duration: 0.55, delay: d, stagger: 0.05)
        case "smoke":
            burst([Effects.smoke], si: si, at: mouth, count: 5, dx: f < 0 ? -50 ... -20 : 20...50, dy: 10...30, duration: 0.9, delay: d, stagger: 0.06)
        case "snow":
            burst([Effects.snow], si: si, at: CGPoint(x: head.x, y: head.y + 30), count: 7, dx: -45...45, dy: -60 ... -30, duration: 1.4, delay: d, stagger: 0.07)
        case "rain":
            burst([Effects.rain], si: si, at: CGPoint(x: head.x, y: head.y + 24), count: 8, dx: -22...22, dy: -70 ... -50, duration: 0.7, delay: d, stagger: 0.06)
        case "petals", "leaves", "seeds", "pollen":
            let img: [CGImage] = effect == "petals" ? [Effects.petal] : effect == "leaves" ? [Effects.leaf, Effects.leaf2] : effect == "seeds" ? [Effects.seed] : [Effects.pollen]
            burst(img, si: si, at: head, count: 7, dx: -40...40, dy: 20...50, duration: 1.2, delay: d, stagger: 0.04)
        case "steam", "clouds":
            burst([effect == "steam" ? Effects.steam : Effects.cloud], si: si, at: head, count: 4, dx: -18...18, dy: 30...55, duration: 1.4, delay: d, stagger: 0.18)
        case "bubbles":
            burst([Effects.bubble], si: si, at: mouth, count: 6, dx: -20...30, dy: 30...60, duration: 1.3, delay: d, stagger: 0.1)
        case "notes":
            burst([Effects.note, Effects.note2], si: si, at: head, count: 5, dx: -30...30, dy: 25...50, duration: 1.3, delay: d, stagger: 0.15)
        case "ink":
            burst([Effects.ink], si: si, at: mid, count: 6, dx: f < 0 ? 20...50 : -50 ... -20, dy: -6...12, duration: 0.9, delay: d, stagger: 0.03)
        case "stomp", "bonk", "roar":
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                self?.spawnDust(at: c, strength: 0.9)
                if effect != "stomp" { self?.spawnPop(Effects.bang, above: c) }
            }
        case "bark":
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + d + Double(i) * 0.18) { [weak self] in
                    guard let self, let (si2, _) = self.localPoint(c) else { return }
                    let off = CGFloat(i - 1) * 22
                    self.burst([Effects.smallBang], si: si2, at: CGPoint(x: head.x + off, y: head.y + 8), count: 1, dx: -4...4, dy: 14...22, duration: 0.6)
                }
            }
        default: // sparkle, glow
            burst([Effects.sparkle, Effects.smallStar], si: si, at: mid, count: 6, dx: -40...40, dy: -10...40, duration: 0.9, delay: d, stagger: 0.06)
        }
    }

    /// Fire-and-forget particles: each flies from `at` by a random offset in (dx, dy), fading out. Pure Core Animation.
    func burst(_ images: [CGImage], si: Int, at p: CGPoint, count: Int, dx: ClosedRange<Double>, dy: ClosedRange<Double>,
               duration: Double, delay: Double = 0, stagger: Double = 0) {
        guard si < screens.count, !images.isEmpty else { return }
        for i in 0..<count {
            let l = particle(images[i % images.count], si)
            l.position = p
            l.opacity = 0
            let end = CGPoint(x: p.x + Double.random(in: dx), y: p.y + Double.random(in: dy))
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: p)
            move.toValue = NSValue(point: end)
            move.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.1, 0.6, 1]
            let spin = CABasicAnimation(keyPath: "transform.rotation")
            spin.toValue = Double.random(in: -1.2...1.2)
            let g = CAAnimationGroup()
            g.animations = [move, fade, spin]
            g.duration = duration * Double.random(in: 0.85...1.15)
            g.beginTime = CACurrentMediaTime() + delay + Double(i) * stagger
            g.fillMode = .both
            run(l, g)
        }
    }

    private func creature(_ id: Int) -> Creature? { world.creatures.first { $0.id == id } }

    /// A shower of hearts when a Gremlet's bond with you grows.
    func bondLevelUp(_ c: Creature) {
        guard let (si, p) = localPoint(c, dy: c.size.y * 0.7) else { return }
        burst([Effects.heart, Effects.smallHeart, Effects.sparkle], si: si, at: p, count: 9, dx: -45...45, dy: 20...60, duration: 1.6, stagger: 0.06)
    }

    private func localPoint(_ c: Creature, dy: Double = 0) -> (Int, CGPoint)? {
        guard let si = layerScreen[c.id] else { return nil }
        let o = screens[si].frame.origin
        return (si, CGPoint(x: c.pos.x - o.x, y: c.pos.y - o.y + dy))
    }

    private func particle(_ image: CGImage, _ si: Int, scale: Double = 3) -> CALayer {
        let l = CALayer()
        l.contents = image
        l.magnificationFilter = .nearest
        l.contentsScale = screens[si].panel.backingScaleFactor
        l.bounds = CGRect(x: 0, y: 0, width: Double(image.width) * scale, height: Double(image.height) * scale)
        screens[si].root.addSublayer(l)
        return l
    }

    private func run(_ l: CALayer, _ anim: CAAnimation) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        l.add(anim, forKey: "fx")
        CATransaction.commit()
    }

    /// "!" that pops in with a springy overshoot above the head.
    private func spawnPop(_ image: CGImage, above c: Creature) {
        guard let (si, p) = localPoint(c, dy: c.size.y * 0.78) else { return }
        let l = particle(image, si)
        l.position = CGPoint(x: p.x + c.facing * c.size.x * 0.18, y: p.y)
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.2, 1.35, 0.9, 1.0, 1.0]
        scale.keyTimes = [0, 0.15, 0.3, 0.4, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.75, 1]
        let g = CAAnimationGroup()
        g.animations = [scale, fade]
        g.duration = 0.9
        run(l, g)
    }

    /// Three stars orbiting above the head (dizzy).
    private func spawnStars(around c: Creature) {
        guard let (si, p) = localPoint(c, dy: c.size.y * 0.72) else { return }
        for i in 0..<3 {
            let l = particle(i == 1 ? Effects.smallStar : Effects.star, si)
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: p.x - 22, y: p.y - 6, width: 44, height: 12))
            let orbit = CAKeyframeAnimation(keyPath: "position")
            orbit.path = path
            orbit.calculationMode = .paced
            orbit.duration = 0.8
            orbit.repeatCount = 2.3
            orbit.timeOffset = Double(i) * 0.8 / 3
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.1, 0.85, 1]
            let g = CAAnimationGroup()
            g.animations = [orbit, fade]
            g.duration = 1.85
            run(l, g)
        }
    }

    /// Dust puffs kicked out sideways from the feet on a hard landing.
    private func spawnDust(at c: Creature, strength: Double) {
        guard let (si, p) = localPoint(c, dy: 4) else { return }
        for side in [-1.0, 1.0] {
            let l = particle(Effects.dust, si, scale: 2.5)
            l.position = p
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: CGPoint(x: p.x + side * 10, y: p.y))
            move.toValue = NSValue(point: CGPoint(x: p.x + side * (26 + 26 * strength), y: p.y + 8))
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.6
            scale.toValue = 1.2 + strength * 0.5
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [move, scale, fade]
            g.duration = 0.45
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            run(l, g)
        }
    }

    /// Small floating particle (heart, zzz). Animated entirely by Core Animation, so it costs no CPU per frame.
    private func spawnEffect(_ image: CGImage, above c: Creature, drift: Double, delay: Double = 0) {
        guard let si = layerScreen[c.id] else { return }
        let origin = screens[si].frame.origin
        let l = CALayer()
        l.contents = image
        l.magnificationFilter = .nearest
        l.contentsScale = screens[si].panel.backingScaleFactor
        l.bounds = CGRect(x: 0, y: 0, width: Double(image.width) * 3, height: Double(image.height) * 3)
        let start = CGPoint(x: c.pos.x - origin.x + c.facing * c.size.x * 0.2, y: c.pos.y - origin.y + c.size.y * 0.85)
        l.position = start
        l.opacity = 0
        screens[si].root.addSublayer(l)

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: start)
        move.toValue = NSValue(point: CGPoint(x: start.x + drift, y: start.y + 46))
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.15, 0.7, 1]
        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = 1.4
        group.beginTime = delay > 0 ? CACurrentMediaTime() + delay : 0
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(group, forKey: "float")
        CATransaction.commit()
    }

    // MARK: Hobby & Claude-buddy props

    var hasProps: Bool { !props.isEmpty || !balloons.isEmpty }

    private func artKey(_ j: Job) -> (String, () -> CGImage) {
        (PropArt.boxKey(j.garden), { PropArt.windowBox(j.garden) })
    }

    /// Centre of a planting spot (0...2) in the box, in screen-local points, and the top of what's growing there.
    private func slotPoint(_ st: PropState, _ i: Int, _ j: Job?) -> (x: CGFloat, soil: CGFloat, top: CGFloat) {
        let f = st.item.frame
        let x = f.midX + CGFloat(PropArt.slotCenters[i] - PropArt.boxWidth / 2) * 3
        let soil = f.minY + CGFloat(PropArt.boxRows) * 3
        let rows = j?.garden.plants[i].map { PropArt.plantRows($0).count } ?? 1
        return (x, soil, soil + CGFloat(rows) * 3)
    }

    /// The little effect for each chore, right where it happens.
    private func gardenEffect(_ action: GardenAction, _ st: PropState, _ j: Job) {
        let si = st.screen
        switch action {
        case .plant(let i):
            let p = slotPoint(st, i, j)
            burst([Effects.dust], si: si, at: CGPoint(x: p.x, y: p.soil), count: 3, dx: -14...14, dy: 0...8, duration: 0.45)
            burst([Effects.seed], si: si, at: CGPoint(x: p.x, y: p.soil + 26), count: 1, dx: -2...2, dy: -24 ... -20, duration: 0.5)
        case .water(let i):
            let p = slotPoint(st, i, j)
            let can = particle(PropArt.wateringCan, si, scale: 3)
            can.position = CGPoint(x: p.x - 20, y: p.top + 26)
            let tilt = CABasicAnimation(keyPath: "transform.rotation")
            tilt.fromValue = 0; tilt.toValue = -0.5
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.15, 0.8, 1]
            let g = CAAnimationGroup(); g.animations = [tilt, fade]; g.duration = 1.3
            run(can, g)
            burst([Effects.rain], si: si, at: CGPoint(x: p.x + 4, y: p.top + 18), count: 7, dx: -10...10, dy: -30 ... -16, duration: 0.6, delay: 0.25, stagger: 0.07)
        case .shoo(let i):
            let p = slotPoint(st, i, j)
            burst([PropArt.aphid], si: si, at: CGPoint(x: p.x + 6, y: p.top - 10), count: 1, dx: 40...70, dy: 50...80, duration: 0.9)
            burst([Effects.dust], si: si, at: CGPoint(x: p.x + 6, y: p.top - 10), count: 2, dx: -10...10, dy: -4...6, duration: 0.35)
        case .weed(let i):
            let p = slotPoint(st, i, j)
            burst([Effects.leaf, Effects.leaf2], si: si, at: CGPoint(x: p.x - 10, y: p.soil + 4), count: 2, dx: -30 ... -10, dy: 10...26, duration: 0.7)
        case .bloom(let i):
            let p = slotPoint(st, i, j)
            burst([Effects.sparkle, Effects.petal, Effects.smallStar], si: si, at: CGPoint(x: p.x, y: p.top - 6), count: 7, dx: -24...24, dy: 0...30, duration: 1.0, stagger: 0.04)
        case .rain:
            rainShower(st)
        case .ladybug(let i):
            let p = slotPoint(st, i, j)
            let l = particle(PropArt.ladybug, si, scale: 3)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: p.x - 90, y: p.top + 70))
            path.addQuadCurve(to: CGPoint(x: p.x + 4, y: p.top - 8), control: CGPoint(x: p.x - 50, y: p.top + 10))
            path.addLine(to: CGPoint(x: p.x + 6, y: p.top - 6))
            path.addQuadCurve(to: CGPoint(x: p.x + 100, y: p.top + 90), control: CGPoint(x: p.x + 60, y: p.top + 10))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path; move.calculationMode = .paced
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.1, 0.85, 1]
            let g = CAAnimationGroup(); g.animations = [move, fade]; g.duration = 2.6
            run(l, g)
            burst([Effects.smallHeart], si: si, at: CGPoint(x: p.x + 4, y: p.top), count: 1, dx: -4...4, dy: 14...22, duration: 0.8, delay: 1.2)
        case .mystery(let i):
            let p = slotPoint(st, i, j)
            burst([Effects.sparkle, Effects.smallStar], si: si, at: CGPoint(x: p.x, y: p.soil + 10), count: 10, dx: -30...30, dy: 0...40, duration: 1.1, stagger: 0.03)
        case .harvest:
            let f = st.item.frame
            burst([Effects.sparkle, Effects.heart, Effects.smallStar, Effects.petal], si: si, at: CGPoint(x: f.midX, y: f.maxY), count: 12, dx: -60...60, dy: 10...60, duration: 1.4, stagger: 0.05)
        }
    }

    /// A little rain cloud drifts over the box, rains for a few seconds, and leaves a rainbow behind.
    private func rainShower(_ st: PropState) {
        let si = st.screen, f = st.item.frame
        let top = f.minY + CGFloat(PropArt.boxRows) * 3 + 70
        let cloud = particle(Effects.cloud, si, scale: 5)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: CGPoint(x: f.minX - 60, y: top + 20))
        move.toValue = NSValue(point: CGPoint(x: f.maxX + 40, y: top + 20))
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.95, 0.95, 0]; fade.keyTimes = [0, 0.15, 0.85, 1]
        let g = CAAnimationGroup(); g.animations = [move, fade]; g.duration = 4.5
        run(cloud, g)
        for k in 0..<8 {
            let x = f.minX - 20 + (f.width + 40) * CGFloat(k) / 7
            burst([Effects.rain], si: si, at: CGPoint(x: x, y: top + 8), count: 4, dx: -6...6, dy: -70 ... -50, duration: 0.6, delay: 0.5 + Double(k) * 0.4, stagger: 0.08)
        }
        let bow = particle(PropArt.rainbow, si, scale: 4)
        bow.position = CGPoint(x: f.midX, y: top + 10)
        bow.opacity = 0
        let bf = CAKeyframeAnimation(keyPath: "opacity")
        bf.values = [0, 0.85, 0.85, 0]; bf.keyTimes = [0, 0.2, 0.75, 1]
        bf.duration = 4; bf.beginTime = CACurrentMediaTime() + 3.8
        bf.fillMode = .both
        run(bow, bf)
    }

    /// Fireflies drift around a garden after dark.
    private func spawnFirefly(_ st: PropState) {
        let si = st.screen, f = st.item.frame
        let l = particle(PropArt.firefly, si, scale: 3)
        l.shadowColor = NSColor(red: 0.95, green: 1, blue: 0.5, alpha: 1).cgColor
        l.shadowOpacity = 1; l.shadowRadius = 5; l.shadowOffset = .zero
        let path = CGMutablePath()
        let start = CGPoint(x: f.minX + CGFloat.random(in: 0...f.width), y: f.minY + CGFloat.random(in: 10...60))
        path.move(to: start)
        path.addCurve(to: CGPoint(x: start.x + CGFloat.random(in: -60...60), y: start.y + CGFloat.random(in: 20...70)),
                      control1: CGPoint(x: start.x + 40, y: start.y + 10), control2: CGPoint(x: start.x - 40, y: start.y + 40))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0, 1, 0.2, 1, 0]; blink.keyTimes = [0, 0.2, 0.5, 0.75, 1]
        let g = CAAnimationGroup(); g.animations = [move, blink]; g.duration = 4
        run(l, g)
    }

    /// A shooting star streaks across the top of the main screen.
    func shootingStar() {
        guard !screens.isEmpty, !hidden else { return }
        let f = screens[0].frame
        let l = particle(PropArt.shootingStar, 0, scale: 4)
        l.shadowColor = NSColor.white.cgColor; l.shadowOpacity = 1; l.shadowRadius = 6; l.shadowOffset = .zero
        let y = f.height - CGFloat.random(in: 60...160)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: CGPoint(x: f.width * 0.15, y: y))
        move.toValue = NSValue(point: CGPoint(x: f.width * 0.75, y: y - 120))
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.1, 0.7, 1]
        let g = CAAnimationGroup(); g.animations = [move, fade]; g.duration = 1.4
        g.timingFunction = CAMediaTimingFunction(name: .easeIn)
        run(l, g)
    }

    /// A butterfly that flutters a loop around the blooms, then drifts off.
    private func spawnButterfly(_ st: PropState) {
        let si = st.screen, f = st.item.frame
        let l = particle(PropArt.butterflies.randomElement()!, si, scale: 3)
        let path = CGMutablePath()
        let start = CGPoint(x: f.minX - 30, y: f.maxY + 40)
        path.move(to: start)
        path.addCurve(to: CGPoint(x: f.midX, y: f.maxY + 6), control1: CGPoint(x: f.minX, y: f.maxY + 70), control2: CGPoint(x: f.midX - 30, y: f.maxY - 10))
        path.addCurve(to: CGPoint(x: f.maxX - 10, y: f.maxY + 20), control1: CGPoint(x: f.midX + 20, y: f.maxY + 30), control2: CGPoint(x: f.maxX - 30, y: f.maxY))
        path.addCurve(to: CGPoint(x: f.maxX + 40, y: f.maxY + 90), control1: CGPoint(x: f.maxX + 10, y: f.maxY + 40), control2: CGPoint(x: f.maxX + 20, y: f.maxY + 60))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path; move.calculationMode = .paced
        let flap = CABasicAnimation(keyPath: "transform.scale.x")
        flap.fromValue = 1; flap.toValue = 0.3; flap.duration = 0.12; flap.autoreverses = true; flap.repeatCount = 30
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.1, 0.85, 1]
        let g = CAAnimationGroup(); g.animations = [move, flap, fade]; g.duration = 6
        run(l, g)
    }

    private func pixelLayer(_ si: Int, anchor: CGPoint) -> CALayer {
        let l = CALayer()
        l.magnificationFilter = .nearest
        l.anchorPoint = anchor
        l.contentsScale = screens[si].panel.backingScaleFactor
        return l
    }

    private func setImage(_ l: CALayer, _ img: CGImage) {
        l.contents = img
        l.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3)
    }

    private func popIn(_ l: CALayer) {
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.2, 1.12, 1.0]
        pop.keyTimes = [0, 0.6, 1]
        pop.duration = 0.35
        l.add(pop, forKey: "pop")
    }

    /// Shelves, creations and balloons: kept in place every frame (they ride along with their window), creations grow,
    /// a little effect plays for each bit of work, and a finished creation lingers for a minute after the job ends.
    private func updateProps() {
        let now = CACurrentMediaTime()
        var busy = Set<Int>()
        for c in world.creatures {
            updateBalloon(c)
            guard let j = c.job else { continue }
            busy.insert(c.id)
            let shelf = world.jobShelf(j, workerID: c.id)
            let anchor = world.jobAnchor(j, workerID: c.id)
            guard let ref = anchor ?? shelf.map({ Vec2($0.minX + $0.width / 2, $0.y) }) else { continue }
            let si = screenIndex(for: ref + Vec2(0, 1))
            var st = props[c.id] ?? PropState(screen: si)
            st.lingerUntil = nil
            let o = screens[si].frame.origin

            // The shelf (pops in when it goes up).
            if let s = shelf {
                let px = max(8, Int((s.width / 3).rounded()))
                if st.shelf == nil || st.shelfPx != px || st.screen != si {
                    st.shelf?.removeFromSuperlayer()
                    let l = pixelLayer(si, anchor: CGPoint(x: 0, y: 1))
                    setImage(l, PropArt.shelf(widthPx: px))
                    screens[si].root.insertSublayer(l, at: 0)
                    if st.shelf == nil { popIn(l); burst([Effects.dust], si: si, at: CGPoint(x: s.minX - o.x + s.width / 2, y: s.y - o.y), count: 3, dx: -40...40, dy: -6...6, duration: 0.5) }
                    st.shelf = l; st.shelfPx = px
                }
                let flip: CGFloat = (j.shelfSide ?? 1) < 0 ? -1 : 1
                st.shelf?.setAffineTransform(CGAffineTransform(scaleX: flip, y: 1))
                let p = CGPoint(x: (s.minX - o.x).rounded() + (flip < 0 ? s.width : 0), y: (s.y - o.y).rounded())
                st.shelf?.anchorPoint = CGPoint(x: 0, y: 1)
                if st.shelf?.position != p { st.shelf?.position = p }
                // A little lantern at the outer end in the evening.
                if PropArt.isEvening {
                    if st.lantern == nil {
                        let l = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 1))   // hangs from the underside
                        setImage(l, PropArt.lantern)
                        l.shadowColor = NSColor(red: 1, green: 0.8, blue: 0.35, alpha: 1).cgColor
                        l.shadowOpacity = 0.9; l.shadowRadius = 9; l.shadowOffset = .zero
                        screens[si].root.addSublayer(l)
                        popIn(l)
                        st.lantern = l
                    }
                    let side = j.shelfSide ?? 1
                    let lx = side > 0 ? s.maxX - 12 : s.minX + 12
                    st.lantern?.position = CGPoint(x: (lx - o.x).rounded(), y: (s.y - o.y - 9).rounded())
                } else if let l = st.lantern { l.removeFromSuperlayer(); st.lantern = nil }
            } else if let l = st.shelf { l.removeFromSuperlayer(); st.shelf = nil; st.lantern?.removeFromSuperlayer(); st.lantern = nil }

            // The creation.
            if let a = anchor {
                let (key, make) = artKey(j)
                if st.key != key || st.item.superlayer == nil || st.screen != si {
                    let fresh = st.item.superlayer == nil
                    st.item.removeFromSuperlayer()
                    st.item.magnificationFilter = .nearest
                    st.item.anchorPoint = CGPoint(x: 0.5, y: 0)
                    st.item.contentsScale = screens[si].panel.backingScaleFactor
                    setImage(st.item, make())
                    screens[si].root.addSublayer(st.item)
                    if fresh { popIn(st.item) }
                    else if st.key != key {
                        burst([Effects.sparkle], si: si, at: CGPoint(x: a.x - o.x, y: a.y - o.y + st.item.bounds.height), count: 2, dx: -14...14, dy: 4...16, duration: 0.6)
                    }
                    st.key = key
                }
                let pos = CGPoint(x: (a.x - o.x).rounded(), y: (a.y - o.y).rounded())
                if st.item.position != pos { st.item.position = pos }
                let top = CGPoint(x: pos.x, y: pos.y + st.item.bounds.height)

                // Each chore gets its own little effect, right at that plant.
                if j.beat != st.beat {
                    st.beat = j.beat
                    if let act = j.garden.lastAction { gardenEffect(act, st, j) }
                }
                // New blooms go in the seed book; the first of a kind gets a speech bubble.
                while st.recorded < j.garden.bloomed.count {
                    let p = j.garden.bloomed[st.recorded]
                    st.recorded += 1
                    if seedBook.record(p) {
                        showBubble("New seed: \(p.kind.name)! (\(p.kind.rarityName), \(seedBook.found)/\(PlantKind.allCases.count))", on: c.id, seconds: 5)
                    } else if p.golden {
                        showBubble("Ooh, a golden \(p.kind.name.lowercased())!", on: c.id, seconds: 4)
                    }
                    onGardenChange()
                }
                st.harvest = j.garden.planted.filter { $0.stage == 4 }
                st.contentRows = j.garden.plants.compactMap { $0.map { PropArt.plantRows($0).count } }.max() ?? 1
                // Special blooms glow; golden ones sparkle now and then.
                let glow = st.harvest.contains { $0.kind == .moonflower } ? "moon" : st.harvest.contains { $0.golden } ? "gold"
                    : st.harvest.contains { $0.kind == .crystalRose } ? "crystal" : st.harvest.contains { $0.kind == .wishingTree } ? "gold" : ""
                if glow != st.glow {
                    st.glow = glow
                    let color: NSColor? = glow == "moon" ? NSColor(red: 0.85, green: 0.8, blue: 1, alpha: 1)
                        : glow == "gold" ? NSColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
                        : glow == "crystal" ? NSColor(red: 0.6, green: 0.95, blue: 1, alpha: 1) : nil
                    st.item.shadowColor = color?.cgColor
                    st.item.shadowOpacity = color == nil ? 0 : 0.9
                    st.item.shadowRadius = 8
                    st.item.shadowOffset = .zero
                }
                if st.harvest.contains(where: { $0.golden }) && now >= st.nextSparkle {
                    st.nextSparkle = now + Double.random(in: 2.5...4.5)
                    burst([Effects.sparkle, Effects.smallStar], si: si, at: top, count: 2, dx: -40...40, dy: -30...10, duration: 0.8)
                }
                // Fireflies after dark.
                if PropArt.isEvening && !j.garden.planted.isEmpty && now >= st.nextFirefly {
                    st.nextFirefly = now + Double.random(in: 1.5...3.5)
                    spawnFirefly(st)
                }
                // Butterflies come to visit while something is in bloom.
                if !st.harvest.isEmpty, now >= (nextButterfly[c.id] ?? 0) {
                    nextButterfly[c.id] = now + Double.random(in: 5...10)
                    spawnButterfly(st)
                }
                if (j.phase == .finished || j.phase == .leaving) && !st.celebrated {
                    st.celebrated = true
                    // Something special in this harvest? The gardener offers it to you.
                    if let best = st.harvest.max(by: { ($0.golden ? 10 : 0) + $0.kind.rarity < ($1.golden ? 10 : 0) + $1.kind.rarity }),
                       best.isSpecial || best.kind.rarity >= 2 {
                        let what = (best.golden ? "a golden " + best.kind.name.lowercased() : (best.kind.isGiant ? "a " : "a ") + best.kind.name.lowercased())
                        showBubble("For you! \(what.prefix(1).uppercased() + what.dropFirst()) \(best.golden || best.kind.rarity >= 3 ? "✨" : "")", on: c.id, seconds: 5)
                        burst([Effects.heart, Effects.smallHeart, Effects.sparkle], si: si, at: CGPoint(x: c.pos.x - o.x, y: c.pos.y - o.y + c.size.y), count: 9, dx: -40...40, dy: 20...70, duration: 1.4, stagger: 0.05)
                    }
                }
            }
            st.screen = si
            if let a = anchor { st.anchorX = a.x }
            props[c.id] = st
        }
        // Job over: the shelf comes down now; the creation lingers a minute (on the floor, or where it was), then fades.
        for (id, var st) in props where !busy.contains(id) {
            if let l = st.shelf { fadeOut(l, 0.4); st.shelf = nil }
            if let l = st.lantern { fadeOut(l, 0.4); st.lantern = nil }
            if st.lingerUntil == nil { st.lingerUntil = now + (st.wasOnShelf ? 0 : 60) }
            if now >= st.lingerUntil! || st.item.superlayer == nil {
                fadeOut(st.item, 0.8)
                props[id] = nil
                // The harvest gets planted in the garden along the bottom of the screen.
                if !st.harvest.isEmpty, let main = NSScreen.screens.first {
                    let x = (st.anchorX - main.frame.minX) / main.frame.width
                    for (i, p) in st.harvest.enumerated() {
                        keepsakes.add(kind: p.kind.rawValue, x: x + Double(i - 1) * (p.kind.isGiant ? 0 : 0.03), variant: p.golden ? 1 : 0)
                    }
                    refreshKeepsakes()
                    for l in keepsakeLayers.suffix(st.harvest.count) { popIn(l) }
                    onGardenChange()
                }
            } else {
                props[id] = st
            }
        }
        for c in world.creatures where c.job?.shelfSide != nil { props[c.id]?.wasOnShelf = true }
    }

    /// The worker whose creation is under the cursor, if any (creations are clickable: tap to help out).
    private func propOwner(at p: Vec2) -> Int? {
        for (id, st) in props where st.item.superlayer != nil && st.lingerUntil == nil && st.screen < screens.count {
            let o = screens[st.screen].frame.origin
            // Only the planter and what's actually growing in it, not the empty air above.
            var box = st.item.frame
            box.size.height = CGFloat(PropArt.boxRows + st.contentRows) * 3
            let f = box.insetBy(dx: -4, dy: -4).offsetBy(dx: o.x, dy: o.y)
            if f.contains(CGPoint(x: p.x, y: p.y)) { return id }
        }
        return nil
    }

    /// You clicked the window box: shoo a bug if there is one, otherwise water the driest plant.
    private func tend(_ workerID: Int) {
        guard let c = world.creatures.first(where: { $0.id == workerID }), let j = c.job, var st = props[workerID],
              let did = world.helpGarden(workerID: workerID) else { return }
        gardenEffect(did, st, j)
        st.beat = j.beat
        props[workerID] = st
        let si = st.screen
        burst([Effects.smallHeart], si: si, at: CGPoint(x: st.item.frame.midX, y: st.item.frame.maxY + 10), count: 1, dx: -6...6, dy: 20...30, duration: 0.9)
    }

    /// Rest the cursor on a busy Gremlet (or its creation) and it tells you what it's making.
    private func updateHover() {
        guard !paused, let cur = world.cursor else { return }
        let now = CACurrentMediaTime()
        let id = world.creature(at: cur).flatMap { $0.job != nil ? $0.id : nil } ?? propOwner(at: cur)
        guard let id else { hoverID = nil; return }
        if hoverID != id { hoverID = id; hoverSince = now; return }
        guard now - hoverSince > 0.6, now - (hoverShown[id] ?? 0) > 8,
              let c = world.creatures.first(where: { $0.id == id }), let j = c.job else { return }
        hoverShown[id] = now
        showBubble(PropArt.describe(j, dozing: c.isDozingAtWork), on: id, seconds: 3.5)
    }

    private func fadeOut(_ l: CALayer, _ d: Double) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = d
        fade.isRemovedOnCompletion = false; fade.fillMode = .forwards
        l.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    /// A balloon on a string over a Gremlet's head while it floats; let go (drifting up and away) when it lands.
    private func updateBalloon(_ c: Creature) {
        let floating = c.activity == .float
        if !floating {
            if let b = balloons.removeValue(forKey: c.id) {
                let start = b.position
                let drift = CABasicAnimation(keyPath: "position")
                drift.fromValue = NSValue(point: start)
                drift.toValue = NSValue(point: CGPoint(x: start.x + 30, y: start.y + 260))
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1; fade.toValue = 0
                let g = CAAnimationGroup()
                g.animations = [drift, fade]; g.duration = 2.2
                g.timingFunction = CAMediaTimingFunction(name: .easeIn)
                run(b, g)
            }
            return
        }
        guard let si = layerScreen[c.id] else { return }
        let b: CALayer
        if let existing = balloons[c.id] { b = existing } else {
            b = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
            let img = PropArt.balloon(c.id)
            b.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3 + 30)
            let face = CALayer()
            face.contents = img
            face.magnificationFilter = .nearest
            face.frame = CGRect(x: 0, y: 30, width: img.width * 3, height: img.height * 3)
            let string = CALayer()
            string.backgroundColor = NSColor(white: 0.25, alpha: 0.9).cgColor
            string.frame = CGRect(x: Double(img.width) * 1.5 - 1, y: 0, width: 1.5, height: 32)
            b.addSublayer(string); b.addSublayer(face)
            screens[si].root.addSublayer(b)
            popIn(b)
            balloons[c.id] = b
        }
        let o = screens[si].frame.origin
        let hand = CGPoint(x: (c.pos.x - o.x + c.facing * c.size.x * 0.06).rounded(), y: (c.pos.y - o.y + c.size.y * 0.72).rounded())
        if b.superlayer !== screens[si].root { b.removeFromSuperlayer(); screens[si].root.addSublayer(b) }
        if b.position != hand { b.position = hand }
    }

    // MARK: Speech bubbles

    /// Shows `text` in a speech bubble over a Gremlet's head for `seconds`. The text is drawn as plain text (never
    /// interpreted), and the bubble is click-through like everything else that isn't a creature.
    func showBubble(_ text: String, on id: Int, seconds: Double) {
        guard let c = creature(id), let si = layerScreen[c.id] else { return }
        bubbles[id]?.layer.removeFromSuperlayer()
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.12, alpha: 1)]
        let str = NSAttributedString(string: text, attributes: attrs)
        let maxW: CGFloat = 240, pad: CGFloat = 9
        let size = str.boundingRect(with: CGSize(width: maxW, height: 200), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let w = ceil(size.width) + pad * 2 + 8, h = ceil(size.height) + pad * 2 - 4
        let scale = screens[si].panel.backingScaleFactor

        let bubble = CALayer()
        bubble.bounds = CGRect(x: 0, y: 0, width: w, height: h + 7)
        bubble.anchorPoint = CGPoint(x: 0.5, y: 0)
        bubble.contentsScale = scale
        let bg = CAShapeLayer()
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 1, y: 8, width: w - 2, height: h - 2), cornerWidth: 9, cornerHeight: 9)
        // Little tail pointing down at the Gremlet.
        path.move(to: CGPoint(x: w / 2 - 6, y: 9)); path.addLine(to: CGPoint(x: w / 2, y: 1)); path.addLine(to: CGPoint(x: w / 2 + 6, y: 9))
        bg.path = path
        bg.fillColor = NSColor(white: 1, alpha: 0.97).cgColor
        bg.strokeColor = NSColor(white: 0.15, alpha: 1).cgColor
        bg.lineWidth = 2
        bg.contentsScale = scale
        bubble.addSublayer(bg)
        // Cover the stroke where the tail joins the box so it reads as one shape.
        let seam = CALayer()
        seam.backgroundColor = bg.fillColor
        seam.frame = CGRect(x: w / 2 - 5, y: 8, width: 10, height: 3)
        bubble.addSublayer(seam)
        let label = CATextLayer()
        label.string = str
        label.isWrapped = true
        label.contentsScale = scale
        label.frame = CGRect(x: pad, y: 8 + pad - 4, width: w - pad * 2, height: ceil(size.height) + 2)
        bubble.addSublayer(label)

        screens[si].root.addSublayer(bubble)
        bubbles[id] = (bubble, si, CACurrentMediaTime() + seconds)
        positionBubble(id)
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.3, 1.08, 1.0]
        pop.keyTimes = [0, 0.6, 1]
        pop.duration = 0.25
        bubble.add(pop, forKey: "pop")
    }

    private func positionBubble(_ id: Int) {
        guard let b = bubbles[id], let c = creature(id) else { return }
        let frame = screens[b.screen].frame
        let half = b.layer.bounds.width / 2
        let x = min(max(c.pos.x - frame.minX, half + 4), frame.width - half - 4)
        let y = min(c.pos.y - frame.minY + c.size.y * 0.95 + 26, frame.height - b.layer.bounds.height - 4)
        let p = CGPoint(x: x.rounded(), y: y.rounded())
        if b.layer.position != p { b.layer.position = p }
    }

    private func updateBubbles(alive: Set<Int>) {
        let now = CACurrentMediaTime()
        for (id, b) in bubbles {
            if !alive.contains(id) || now >= b.until || layerScreen[id] != b.screen {
                let l = b.layer
                bubbles[id] = nil
                CATransaction.begin()
                CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.3
                fade.isRemovedOnCompletion = false; fade.fillMode = .forwards
                l.add(fade, forKey: "fade")
                CATransaction.commit()
            } else {
                positionBubble(id)
            }
        }
    }

    var hasBubbles: Bool { !bubbles.isEmpty }

    // MARK: Click-through + input

    /// Lets the panel under the cursor receive clicks only while the cursor is over a creature's opaque pixels.
    func updateClickThrough() {
        if paused { return }
        let p = vec(NSEvent.mouseLocation)
        if dragging || pressed != nil { return }
        setClickThrough(world.creature(at: p) != nil || propOwner(at: p) != nil ? screenIndex(for: p) : nil)
    }

    private func setClickThrough(_ activeScreen: Int?) {
        for (i, s) in screens.enumerated() {
            let ignore = i != activeScreen
            if s.panel.ignoresMouseEvents != ignore { s.panel.ignoresMouseEvents = ignore }
        }
    }

    private func mouseMoved() {
        let p = vec(NSEvent.mouseLocation)
        defer { lastMouse = p }
        world.cursor = p
        updateClickThrough()
        if paused { return }
        if let last = lastMouse, let c = world.creature(at: p) { world.pet(c, distance: (p - last).length) }
    }

    func mouseDown(at p: CGPoint, time: Double) {
        guard !paused else { return }
        if world.creature(at: vec(p)) == nil, let owner = propOwner(at: vec(p)) { pressedProp = owner; return }
        guard let c = world.creature(at: vec(p)) else { return }
        pressed = c
        pressStart = vec(p)
        dragging = false
    }

    func mouseDragged(to p: CGPoint, time: Double) {
        guard let c = pressed else { return }
        let v = vec(p)
        if !dragging && (v - pressStart).length > 4 {
            dragging = true
            world.beginDrag(c, at: pressStart, time: time)
            NSCursor.closedHand.push()
        }
        if dragging { world.drag(c, to: v, time: time) }
    }

    func mouseUp(at p: CGPoint, time: Double) {
        if let owner = pressedProp {
            pressedProp = nil
            if propOwner(at: vec(p)) == owner { tend(owner) }
            updateClickThrough()
            return
        }
        guard let c = pressed else { return }
        if dragging {
            world.drag(c, to: vec(p), time: time)
            world.endDrag(c, time: time)
            NSCursor.pop()
        } else {
            world.poke(c)
        }
        pressed = nil
        dragging = false
        updateClickThrough()
    }

    var isInteracting: Bool { dragging }

    private func vec(_ p: CGPoint) -> Vec2 { Vec2(Double(p.x), Double(p.y)) }
}

/// Tiny procedurally drawn pixel particles.
enum Effects {
    static let heart = pixels([
        ".rr.rr.",
        "rRRrrrr",
        "rRrrrrr",
        ".rrrrr.",
        "..rrr..",
        "...r...",
    ], ["r": 0xFF5E7E, "R": 0xFFD1DC])

    static let smallHeart = pixels([
        "r.r",
        "rrr",
        ".r.",
    ], ["r": 0xFF8FA8])

    static let bang = pixels([
        ".oo.",
        "oYYo",
        "oYYo",
        "oYYo",
        "oYYo",
        ".oo.",
        "....",
        ".oo.",
        "oYYo",
        ".oo.",
    ], ["o": 0x5A2A10, "Y": 0xFFD23D])

    static let star = pixels([
        "..y..",
        ".yYy.",
        "yYYYy",
        ".yYy.",
        "y...y",
    ], ["y": 0xF5B82E, "Y": 0xFFF29A])

    static let smallStar = pixels([
        ".y.",
        "yYy",
        ".y.",
    ], ["y": 0xF5B82E, "Y": 0xFFF29A])

    static let dust = pixels([
        ".ww.",
        "wWWw",
        "wWWw",
        ".ww.",
    ], ["w": 0xD9D2C5, "W": 0xF4F0E8])

    static let note = pixels([
        "..nn",
        "..nN",
        "..n.",
        "..n.",
        "nnn.",
        "nnn.",
    ], ["n": 0x3A3A6A, "N": 0x6F6FB0])
    static let note2 = pixels([
        ".nnnn",
        ".n..n",
        ".n..n",
        "nn.nn",
        "nn.nn",
    ], ["n": 0x5A2A6A])
    static let flame = pixels([
        "..A.",
        ".AaA",
        "AaYa",
        ".aa.",
    ], ["A": 0xFF6A2B, "a": 0xFFC23D, "Y": 0xFFF6A8])
    static let flame2 = pixels([
        ".A.",
        "AYA",
        ".A.",
    ], ["A": 0xFF8A3D, "Y": 0xFFF6A8])
    static let smoke = pixels([
        ".ss.",
        "sSSs",
        "sSSs",
        ".ss.",
    ], ["s": 0x8A8494, "S": 0xBDB8C6])
    static let snow = pixels([
        "w.w",
        ".W.",
        "w.w",
    ], ["w": 0xCFE8FF, "W": 0xFFFFFF])
    static let rain = pixels([
        ".b",
        "bB",
        "bb",
    ], ["b": 0x6FB8F0, "B": 0xD8F0FF])
    static let petal = pixels([
        ".pp",
        "pPp",
        "pp.",
    ], ["p": 0xFF9EC4, "P": 0xFFE0EE])
    static let leaf = pixels([
        "..gg",
        ".gGg",
        "gGg.",
        "g...",
    ], ["g": 0x5FAF4A, "G": 0xA8E08A])
    static let leaf2 = pixels([
        "..oo",
        ".oOo",
        "oOo.",
        "o...",
    ], ["o": 0xE8784A, "O": 0xFFC08A])
    static let seed = pixels([
        ".k.",
        "kKk",
        ".k.",
    ], ["k": 0x3A3A40, "K": 0xE8E2D0])
    static let pollen = pixels([
        ".y.",
        "yYy",
        ".y.",
    ], ["y": 0xFFC93C, "Y": 0xFFF29A])
    static let steam = pixels([
        ".ww.",
        "wWWw",
        ".ww.",
    ], ["w": 0xE8EEF4, "W": 0xFFFFFF])
    static let cloud = pixels([
        ".ww..",
        "wWWww",
        "wwwww",
    ], ["w": 0xE8EEF8, "W": 0xFFFFFF])
    static let bubble = pixels([
        ".bb.",
        "bW.b",
        "b..b",
        ".bb.",
    ], ["b": 0x8FD3F0, "W": 0xFFFFFF])
    static let ink = pixels([
        ".kk.",
        "kKkk",
        "kkkk",
        ".kk.",
    ], ["k": 0x2A1E3A, "K": 0x5A4A7A])
    static let sparkle = pixels([
        "..y..",
        "..y..",
        "yyWyy",
        "..y..",
        "..y..",
    ], ["y": 0xFFE98A, "W": 0xFFFFFF])
    static let smallBang = pixels([
        "oYo",
        "oYo",
        "...",
        "oYo",
    ], ["o": 0x5A2A10, "Y": 0xFFD23D])

    static let zzz = pixels([
        "zzzz",
        "..z.",
        ".z..",
        "zzzz",
    ], ["z": 0xBFD7FF])

    static func pixels(_ rows: [String], _ palette: [Character: UInt32]) -> CGImage {
        let h = rows.count, w = rows[0].count
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let hex = palette[ch] else { continue }
                let i = (y * w + x) * 4
                buf[i] = UInt8(hex >> 16 & 0xFF); buf[i + 1] = UInt8(hex >> 8 & 0xFF); buf[i + 2] = UInt8(hex & 0xFF); buf[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(buf) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
