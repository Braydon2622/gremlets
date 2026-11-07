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
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2, let c = controller, let id = c.creatureID(at: NSEvent.mouseLocation) { c.onDoubleClick(id); return }
        controller?.mouseDown(at: NSEvent.mouseLocation, time: e.timestamp)
    }
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
    /// The grove and the little events (meteors, festivals) are drawn by their own renderer.
    private(set) var fx: SpectacleRenderer!
    /// The project bonsai, the ivy and ledges on Claude's windows, and the nursery.
    private(set) var bonsaiFX: BonsaiRenderer!
    struct ScreenRef { let frame: CGRect; let root: CALayer; let scale: CGFloat }
    var screenRefs: [ScreenRef] { screens.map { ScreenRef(frame: $0.frame, root: $0.root, scale: $0.panel.backingScaleFactor) } }
    func screenIndexFor(_ p: Vec2) -> Int { screenIndex(for: p) }
    private var shadows: [Int: CALayer] = [:]
    private var layers: [Int: CALayer] = [:]
    private var shownFrame: [Int: Int] = [:]
    private var layerScreen: [Int: Int] = [:]
    private var sleepBubbleTimer: [Int: Double] = [:]
    /// Speech bubbles: creature id → bubble layer, the screen it's on, and when it goes away.
    private var bubbles: [Int: (layer: CALayer, screen: Int, until: CFTimeInterval)] = [:]
    /// Hobby / Claude-buddy props per worker (creature id): the creation and the ladder.
    private var props: [Int: PropState] = [:]
    private var balloons: [Int: CALayer] = [:]
    /// Double-clicking a Gremlet (the app opens a chat with it).
    var onDoubleClick: (Int) -> Void = { _ in }
    func creatureID(at p: CGPoint) -> Int? { world.creature(at: Vec2(Double(p.x), Double(p.y)))?.id }
    /// Desktop icon play (set by the app; nil or disabled = off).
    var icons: DesktopIcons?
    /// Icons currently "picked up" (their platform is gone until they're put back).
    private(set) var liftedIcons = Set<Int>()
    private var carries: [Int: (icon: DesktopIcons.Icon, copy: CALayer, patch: CALayer, until: Double)] = [:]
    private var onIconSince: [Int: (icon: Int, since: Double)] = [:]
    private var nextPickup = CACurrentMediaTime() + 40
    let seedBook = SeedBook()
    /// Called when the seed book or today's harvest changes (the menu shows them).
    var onGardenChange: () -> Void = {}
    /// A Claude session's Gremlet was clicked: the app brings that session's window to the front.
    var onWorkerClicked: (Creature) -> Void = { _ in }
    private var nextButterfly: [Int: Double] = [:]
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
        /// Floating-island shelves: their biome, the life on top, and when the next critter wanders across.
        var biome: Biome?
        var decor: CALayer?
        var decorKey = ""
        var nextCritter = 0.0
        /// Claude buddy: the building going up (one block per edit) and the tiny helpers (one per subagent).
        var build: CALayer?
        var buildKey = ""
        /// Remembered so the finished building can move to the village when the job ends.
        var lastBiome: Biome?
        var lastBlocks = 0
        var project: String?
        var nextChimney = 0.0
        var flag: CALayer?
        var doneCelebrated = false
        var nextAmbient = 0.0
        var weatherLayer: CALayer?
        var weatherKind = ""
        var nextRain = 0.0
        var nextHelperBlock = 0.0
        var helpers: [CALayer] = []
        var lantern: CALayer?
        /// The tree a branch grows on, or the balloons a swing hangs from.
        var extra: CALayer?
        var extraKey = ""
        /// A second extra: the treehouse cabin, the balloon's envelope.
        var extra2: CALayer?
        var nextBird = 0.0
        var lastShelfX: CGFloat = 0
        var snailFacing: CGFloat = 1
        var snailTuckedUntil = 0.0
        var swingBoostUntil = 0.0
        var carpetPhase = -1
        var lastBounce: Double?
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
    private var pressedPlatform: Int?
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
        fx = SpectacleRenderer(overlay: self, world: world)
        bonsaiFX = BonsaiRenderer(overlay: self, world: world)
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
        for (_, l) in shadows { l.removeFromSuperlayer() }
        shadows.removeAll()
        fx?.rebuild()
        bonsaiFX?.rebuild()
    }


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
            // Asleep inside a village house: out of sight (the house shows smoke and z's instead).
            let inside = c.homeUntil != nil
            if layer.isHidden != inside { layer.isHidden = inside }
            if inside { shadows[c.id]?.isHidden = true; continue }
            // Only touch layer properties that changed; every write dirties the layer tree for the next commit.
            let pos = CGPoint(x: (c.pos.x - origin.x).rounded(), y: (c.pos.y - origin.y).rounded())
            if layer.position != pos { layer.position = pos }
            let flip: CGFloat = c.facing < 0 ? -1 : 1
            // Squash and stretch: stretch when launching or falling fast, squash on landing; spin when tossed.
            var sy: CGFloat = 1
            if c.activity == .airborne { sy = 1 + CGFloat(min(0.16, abs(c.vel.y) / 7000)) }
            else if c.activity == .land { sy = 0.84 }
            else if c.activity == .crouch { sy = 0.9 }
            var t = CGAffineTransform(scaleX: flip / sqrt(sy), y: sy)
            if let since = fx.spinning[c.id] {
                t = t.rotated(by: CGFloat((CACurrentMediaTime() - since) * 11) * flip)
            }
            if layer.affineTransform() != t { layer.setAffineTransform(t) }
            updateShadow(c, si: si, origin: origin)
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
        for id in shadows.keys where !alive.contains(id) { shadows[id]?.removeFromSuperlayer(); shadows[id] = nil }
        fx.render()
        bonsaiFX.render()
        updateBubbles(alive: alive)
        updateProps()
        updateHover()
        updateIconPlay()
        for id in layers.keys where !alive.contains(id) {
            layers[id]?.removeFromSuperlayer()
            layers[id] = nil; shownFrame[id] = nil; layerScreen[id] = nil
        }
        CATransaction.commit()
    }

    /// A soft shadow on whatever is below a Gremlet: grounds it on the desktop, and shows where it'll land.
    private func updateShadow(_ c: Creature, si: Int, origin: CGPoint) {
        let groundY: Double?
        if c.isGrounded { groundY = c.pos.y }
        else { groundY = world.surfaces.filter { $0.supports(x: c.pos.x) && $0.y <= c.pos.y + 1 }.map(\.y).max() }
        guard let gy = groundY, c.activity != .float, c.activity != .dragged || c.pos.y - gy < 400 else {
            shadows[c.id]?.isHidden = true; return
        }
        let l = shadows[c.id] ?? {
            let l = CALayer()
            l.backgroundColor = NSColor(white: 0, alpha: 1).cgColor
            l.zPosition = -1
            l.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "hidden": NSNull(), "cornerRadius": NSNull()]
            shadows[c.id] = l
            return l
        }()
        if l.superlayer !== screens[si].root { l.removeFromSuperlayer(); screens[si].root.addSublayer(l) }
        let h = max(0, c.pos.y - gy)
        let k = max(0.35, 1 - h / 500)
        let w = c.size.x * 0.46 * k
        l.bounds = CGRect(x: 0, y: 0, width: w, height: 6 * k)
        l.cornerRadius = 3 * k
        l.position = CGPoint(x: (c.pos.x - origin.x).rounded(), y: (gy - origin.y + 1).rounded())
        l.opacity = Float(0.2 * k)
        l.isHidden = false
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
            fx.handleWorld(e)
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
            case .landed(let id, _) where creature(id).flatMap({ world.iconUnder($0) }) != nil:
                if let c = creature(id), let iconID = world.iconUnder(c), let icon = icons?.visible.first(where: { $0.id == iconID }) { iconBoing(icon) }
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

    func localPoint(_ c: Creature, dy: Double = 0) -> (Int, CGPoint)? {
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
        case .snap(let f, let b):
            let pf = slotPoint(st, f, j), pb = slotPoint(st, b, j)
            burst([PropArt.aphid], si: si, at: CGPoint(x: pb.x + 6, y: pb.top - 10), count: 1, dx: (pf.x - pb.x - 6)...(pf.x - pb.x - 6), dy: (pf.top - pb.top)...(pf.top - pb.top), duration: 0.35)
            burst([Effects.smallBang], si: si, at: CGPoint(x: pf.x, y: pf.top), count: 1, dx: -2...2, dy: 10...16, duration: 0.6, delay: 0.35)
        case .mystery(let i):
            let p = slotPoint(st, i, j)
            burst([Effects.sparkle, Effects.smallStar], si: si, at: CGPoint(x: p.x, y: p.soil + 10), count: 10, dx: -30...30, dy: 0...40, duration: 1.1, stagger: 0.03)
        case .harvest:
            let f = st.item.frame
            burst([Effects.sparkle, Effects.heart, Effects.smallStar, Effects.petal], si: si, at: CGPoint(x: f.midX, y: f.maxY), count: 12, dx: -60...60, dy: 10...60, duration: 1.4, stagger: 0.05)
        }
    }

    /// Shelf extras: a whole tree for a branch shelf (trunk from the floor up, canopy around the branch), balloons
    /// and ropes holding up a swing.
    private func updateShelfExtra(_ st: inout PropState, _ j: Job, _ s: Surface, _ si: Int, _ o: CGPoint, _ flip: CGFloat) {
        let side = j.shelfSide ?? 1
        let outer = side > 0 ? s.maxX : s.minX
        switch j.shelfStyle {
        case .branch, .treehouse:
            // A whole tree from the floor up: the trunk stands just inside the shelf's outer end, one limb props the
            // shelf up, the rest spread out away from the window.
            guard let floor = world.surfaces.filter({ $0.kind == .floor && $0.supports(x: outer - side * 30) }).min(by: { $0.y < $1.y }) else { return }
            let shelfPx = Int(((s.y - floor.y) / 3).rounded())
            let hpx = max(30, shelfPx + 14)
            let key = "tree\(hpx)-\(shelfPx)-\(world.month)-\(side)"
            if st.extraKey != key || st.extra == nil {
                st.extra?.removeFromSuperlayer()
                let l = pixelLayer(si, anchor: CGPoint(x: side < 0 ? 1 - PropArt.treeAnchorX : PropArt.treeAnchorX, y: 0))
                setImage(l, PropArt.tree(heightPx: hpx, shelfPx: shelfPx, seed: j.seed, month: world.month, mirror: side < 0))
                screens[si].root.insertSublayer(l, at: 0)
                if st.extra == nil { popIn(l) }
                st.extra = l; st.extraKey = key
            }
            st.extra?.position = CGPoint(x: (outer - side * 30 - o.x).rounded(), y: (floor.y - o.y).rounded())
            if j.shelfStyle == .treehouse {
                if st.extra2 == nil {
                    let l = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
                    setImage(l, PropArt.cabin)
                    screens[si].root.insertSublayer(l, above: st.extra)
                    popIn(l)
                    st.extra2 = l
                }
                st.extra2?.position = CGPoint(x: (outer - side * 26 - o.x).rounded(), y: (s.y - o.y).rounded())
            }
        case .swing:
            if st.extra == nil {
                let c = CALayer()
                c.anchorPoint = CGPoint(x: 0.5, y: 0)
                c.bounds = CGRect(x: 0, y: 0, width: s.width, height: 130)
                for rx in [CGFloat(10), s.width - 10] {
                    let rope = CALayer()
                    rope.backgroundColor = NSColor(red: 0.55, green: 0.4, blue: 0.25, alpha: 1).cgColor
                    rope.frame = CGRect(x: rx, y: 0, width: 2, height: 96)
                    c.addSublayer(rope)
                }
                let b = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
                setImage(b, PropArt.swingBalloons())
                b.position = CGPoint(x: s.width / 2, y: 90)
                c.addSublayer(b)
                screens[si].root.insertSublayer(c, at: 0)
                popIn(c)
                st.extra = c
            }
            // Rock gently.
            let t = CACurrentMediaTime()
            st.extra?.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(sin(t * 1.2) * 0.02)))
            st.extra?.position = CGPoint(x: (s.minX + s.width / 2 - o.x).rounded(), y: (s.y - o.y).rounded())
        case .basket:
            // The envelope floats above the basket; the burner flickers now and then.
            let t = CACurrentMediaTime()
            let burning = (Int(t * 5) % 23) < 3 || t < st.swingBoostUntil
            let flame = burning ? 1 + Int(t * 8) % 2 : 0
            let key = "env\(flame)"
            if st.extraKey != key || st.extra == nil {
                let fresh = st.extra == nil
                if st.extra == nil {
                    let l = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
                    screens[si].root.insertSublayer(l, at: 0)
                    st.extra = l
                }
                setImage(st.extra!, PropArt.balloonEnvelope(seed: j.seed, flame: flame, ropeLength: 34))
                if fresh { popIn(st.extra!) }
                st.extraKey = key
            }
            st.extra?.position = CGPoint(x: (s.minX + s.width / 2 - o.x).rounded(), y: (s.y - o.y).rounded())
        case .snail:
            // The snail's body and shell under the platform; it faces the way it's crawling and wiggles its eyestalks.
            let t = CACurrentMediaTime()
            let x = s.minX + s.width / 2 - o.x
            if abs(x - st.lastShelfX) > 0.05 { st.snailFacing = x > st.lastShelfX ? 1 : -1 }
            st.lastShelfX = x
            let look = t < st.snailTuckedUntil ? 2 : Int(t / 1.7) % 2
            if st.extraKey != "snail\(look)" || st.extra == nil {
                if st.extra == nil {
                    let l = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
                    screens[si].root.insertSublayer(l, at: 0)
                    popIn(l)
                    st.extra = l
                }
                setImage(st.extra!, PropArt.snailBody(look: look))
                st.extraKey = "snail\(look)"
            }
            st.extra?.setAffineTransform(CGAffineTransform(scaleX: st.snailFacing, y: 1))
            st.extra?.position = CGPoint(x: (x + st.snailFacing * 21).rounded(), y: (s.y - 66 - o.y).rounded())
        default:
            if let l = st.extra { l.removeFromSuperlayer(); st.extra = nil }
        }
        if j.shelfStyle != .treehouse && j.shelfStyle != .basket, let l = st.extra2 { l.removeFromSuperlayer(); st.extra2 = nil }
    }

    /// The platform under the cursor (worker id), for clicking it.
    private func platformOwner(at p: Vec2) -> Int? {
        for (id, st) in props where st.lingerUntil == nil && st.screen < screens.count {
            let o = screens[st.screen].frame.origin
            for l in [st.shelf, st.extra2, st.extra].compactMap({ $0 }) where l.superlayer != nil {
                if l.frame.insetBy(dx: -2, dy: -2).offsetBy(dx: o.x, dy: o.y).contains(CGPoint(x: p.x, y: p.y)) { return id }
            }
        }
        return nil
    }

    /// You clicked a platform: each kind reacts its own way.
    private func pokePlatform(_ id: Int) {
        guard var st = props[id], let c = world.creatures.first(where: { $0.id == id }), let j = c.job, let shelf = st.shelf else { return }
        world.pokePlatform(workerID: id)
        let si = st.screen, f = shelf.frame
        let mid = CGPoint(x: f.midX, y: f.maxY)
        func wobble(_ l: CALayer, _ amount: Double) {
            let w = CAKeyframeAnimation(keyPath: "transform.rotation")
            w.values = [0, amount, -amount * 0.7, amount * 0.4, 0]
            w.duration = 0.6
            w.isAdditive = true
            l.add(w, forKey: "wobble")
        }
        switch j.shelfStyle {
        case .plank, .stone, .branch, .treehouse:
            wobble(shelf, 0.04)
            burst([j.shelfStyle == .stone ? Effects.dust : Effects.leaf, Effects.dust], si: si, at: CGPoint(x: f.midX, y: f.minY), count: 3, dx: -30...30, dy: -40 ... -15, duration: 0.8)
            if j.shelfStyle == .treehouse, let cabin = st.extra2 {
                burst([Effects.smoke], si: si, at: CGPoint(x: cabin.frame.midX + 10, y: cabin.frame.maxY), count: 3, dx: -6...6, dy: 20...45, duration: 1.4, stagger: 0.2)
            }
        case .leaf:
            wobble(shelf, 0.08)
            burst([Effects.leaf, Effects.leaf2], si: si, at: CGPoint(x: f.midX, y: f.minY), count: 4, dx: -40...40, dy: -70 ... -30, duration: 1.4, stagger: 0.08)
        case .cloud:
            burst([Effects.cloud], si: si, at: mid, count: 2, dx: -20...20, dy: 4...10, duration: 0.8)
        case .mushroom:
            burst([Effects.pollen, Effects.sparkle], si: si, at: mid, count: 8, dx: -40...40, dy: 10...50, duration: 1.2, stagger: 0.04)
        case .swing:
            st.swingBoostUntil = CACurrentMediaTime() + 2.5
        case .basket:
            st.swingBoostUntil = CACurrentMediaTime() + 1.4
            if let env = st.extra { burst([Effects.flame, Effects.flame2], si: si, at: CGPoint(x: env.frame.midX, y: env.frame.minY + 100), count: 5, dx: -6...6, dy: 10...24, duration: 0.5, stagger: 0.04) }
        case .carpet:
            wobble(shelf, 0.06)
            burst([Effects.sparkle, Effects.smallStar], si: si, at: mid, count: 6, dx: -60...60, dy: -10...20, duration: 0.8, stagger: 0.03)
        case .snail:
            st.snailTuckedUntil = CACurrentMediaTime() + 3
            if let body = st.extra { burst([Effects.smallHeart], si: si, at: CGPoint(x: body.frame.midX + st.snailFacing * 100, y: body.frame.maxY), count: 2, dx: -10...10, dy: 14...26, duration: 1.0) }
        }
        props[id] = st
    }

    /// A little bird lands on the end of a platform, looks around, and flies off.
    /// Claude buddy: the building on this Gremlet's island (a block per file Claude edits), and its helpers.
    private func updateBuild(_ st: inout PropState, _ c: Creature, _ j: Job, ground: Double, x: Double, si: Int, origin o: CGPoint) {
        guard j.kind == .claude else { return }
        let b = st.biome ?? Biome.pick(.plank, seed: UInt64(abs(j.windowID ?? c.id)), month: world.month)
        let key = "\(b.rawValue)-\(j.blocks)-\(world.isNight)-\(si)"
        st.lastBiome = b; st.lastBlocks = j.blocks
        st.project = j.label ?? st.project
        if st.buildKey != key {
            st.buildKey = key
            if let img = BuildArt.image(b, blocks: j.blocks, night: world.isNight) {
                let l = st.build ?? {
                    let l = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
                    screens[si].root.insertSublayer(l, at: 0)
                    l.zPosition = -0.2
                    return l
                }()
                setImage(l, img)
                st.build = l
            }
        }
        st.build?.position = CGPoint(x: (x - o.x).rounded(), y: (ground - o.y).rounded())
        // Session status at a glance: chimney smoke while Claude works, a red flag on the roof when Claude needs
        // you, a little shower of sparkles when it's done.
        if let l = st.build {
            var f = l.frame
            f.size.height = CGFloat(BuildArt.builtHeight(b, blocks: j.blocks) * 3)
            let now = CACurrentMediaTime()
            let working = j.phase == .working && world.time - j.lastToolTime < 25 && !j.needsYou
            if working && now >= st.nextChimney {
                st.nextChimney = now + 1.3
                let ch = BuildArt.chimney(b)
                burst([Effects.smoke], si: si, at: CGPoint(x: f.minX + f.width * ch.x, y: min(f.maxY, l.frame.minY + l.frame.height * ch.y)), count: 1, dx: 3...12, dy: 24...40, duration: 2)
            }
            if j.needsYou {
                let flag = st.flag ?? {
                    let fl = pixelLayer(si, anchor: CGPoint(x: 0, y: 0))
                    setImage(fl, ClaudeIcons.flag)
                    let wave = CABasicAnimation(keyPath: "transform.rotation.z")
                    wave.fromValue = -0.08; wave.toValue = 0.08; wave.duration = 0.5; wave.autoreverses = true; wave.repeatCount = .infinity
                    fl.add(wave, forKey: "wave")
                    screens[si].root.addSublayer(fl)
                    popIn(fl)
                    return fl
                }()
                flag.position = CGPoint(x: f.midX, y: f.maxY - 2)
                st.flag = flag
            } else if let fl = st.flag { fadeOut(fl, 0.3); st.flag = nil }
            // Weather following how Claude's work is going: a shower when a command fails, a storm when it keeps
            // failing, sunshine and a rainbow when the tests pass.
            let wk = j.weather.rawValue
            if wk != st.weatherKind {
                st.weatherKind = wk
                st.weatherLayer.map { fadeOut($0, 0.6) }
                st.weatherLayer = nil
                if j.weather != .clear {
                    let img = j.weather == .sunny ? WeatherArt.rainbow : WeatherArt.cloud(storm: j.weather == .storm)
                    let wl = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
                    setImage(wl, img)
                    wl.zPosition = 30
                    screens[si].root.addSublayer(wl)
                    popIn(wl)
                    if j.weather != .sunny {
                        let drift = CABasicAnimation(keyPath: "transform.translation.x")
                        drift.fromValue = -8; drift.toValue = 8; drift.duration = 2.2; drift.autoreverses = true; drift.repeatCount = .infinity
                        wl.add(drift, forKey: "drift")
                    }
                    st.weatherLayer = wl
                }
            }
            if let wl = st.weatherLayer {
                wl.position = CGPoint(x: f.midX, y: f.minY + max(f.height, 30) + (j.weather == .sunny ? 4 : 46))
                if j.weather != .sunny && now >= st.nextRain {
                    st.nextRain = now + (j.weather == .storm ? 0.12 : 0.25)
                    let wf = wl.frame
                    burst([Effects.rain], si: si, at: CGPoint(x: wf.minX + .random(in: 8...(wf.width - 8)), y: wf.minY + 4), count: 1, dx: -3...3, dy: -(wf.minY - f.minY) ... -(wf.minY - f.minY) + 10, duration: 0.6)
                    if j.weather == .storm && Int.random(in: 0..<14) == 0 {
                        burst([Effects.sparkle, Effects.smallStar], si: si, at: CGPoint(x: wf.midX, y: wf.minY), count: 3, dx: -10...10, dy: -40 ... -10, duration: 0.3)
                    }
                } else if j.weather == .sunny && now >= st.nextRain {
                    st.nextRain = now + 0.5
                    burst([WeatherArt.sun, Effects.sparkle], si: si, at: CGPoint(x: wl.frame.midX, y: wl.frame.maxY - 10), count: 1, dx: -40...40, dy: -10...20, duration: 1.2)
                }
            }
            if j.phase == .finished && !st.doneCelebrated {
                st.doneCelebrated = true
                burst([Effects.sparkle, Effects.star, Effects.smallStar], si: si, at: CGPoint(x: f.midX, y: f.maxY), count: 9, dx: -40...40, dy: 10...70, duration: 1.3, stagger: 0.05)
            }
        }
        // Helpers: tiny copies of the Gremlet hopping around the building, one per running subagent.
        while st.helpers.count < j.helpers, let sp = species[c.species.id], let img = sp.frames.first {
            let h = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
            h.contents = img
            h.bounds = CGRect(x: 0, y: 0, width: c.size.x * 0.5, height: c.size.y * 0.5)
            h.opacity = 0.92
            let hop = CABasicAnimation(keyPath: "transform.translation.y")
            hop.fromValue = 0; hop.toValue = 9; hop.duration = 0.28 + Double(st.helpers.count) * 0.04
            hop.autoreverses = true; hop.repeatCount = .infinity
            hop.timingFunction = CAMediaTimingFunction(name: .easeOut)
            h.add(hop, forKey: "hop")
            screens[si].root.addSublayer(h)
            popIn(h)
            burst([Effects.sparkle, Effects.smallStar], si: si, at: CGPoint(x: x - o.x, y: ground - o.y + 20), count: 5, dx: -30...30, dy: 0...40, duration: 0.7)
            st.helpers.append(h)
        }
        while st.helpers.count > j.helpers, let h = st.helpers.popLast() {
            // The subagent is done: its helper brings the result (a little scroll) to the Gremlet, then pops home.
            let pos = h.position
            let to = CGPoint(x: c.pos.x - o.x, y: c.pos.y - o.y + c.size.y * 0.6)
            let sc = particle(WeatherArt.scroll, si)
            sc.position = pos
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.values = [CGPoint(x: pos.x, y: pos.y + 20), CGPoint(x: (pos.x + to.x) / 2, y: max(pos.y, to.y) + 50), to].map { NSValue(point: $0) }
            fly.duration = 0.8
            fly.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            run(sc, fly)
            burst([Effects.sparkle, Effects.heart], si: si, at: to, count: 3, dx: -14...14, dy: 10...30, duration: 0.8, delay: 0.75)
            fadeOut(h, 0.4)
            burst([Effects.heart, Effects.sparkle], si: si, at: CGPoint(x: pos.x, y: pos.y + 14), count: 3, dx: -14...14, dy: 10...30, duration: 0.8)
        }
        for (n, h) in st.helpers.enumerated() {
            let side: Double = n % 2 == 0 ? -1 : 1
            let dx = side * (34 + Double(n / 2) * 22)
            h.position = CGPoint(x: (x + dx - o.x).rounded(), y: (ground - o.y).rounded())
            h.setAffineTransform(CGAffineTransform(scaleX: side < 0 ? 1 : -1, y: 1))
        }
        // Helpers lug blocks up to the building now and then.
        let now0 = CACurrentMediaTime()
        if !st.helpers.isEmpty, now0 >= st.nextHelperBlock, let l = st.build {
            st.nextHelperBlock = now0 + Double.random(in: 0.9...1.8)
            let h = st.helpers[Int.random(in: 0..<st.helpers.count)]
            let blk = particle(WeatherArt.block, si)
            let from = CGPoint(x: h.position.x, y: h.position.y + 22)
            let top = CGPoint(x: l.frame.midX + .random(in: -20...20), y: l.frame.minY + CGFloat(BuildArt.builtHeight(b, blocks: j.blocks) * 3))
            blk.position = from
            let arc = CAKeyframeAnimation(keyPath: "position")
            arc.values = [from, CGPoint(x: (from.x + top.x) / 2, y: max(from.y, top.y) + 40), top].map { NSValue(point: $0) }
            arc.duration = 0.7
            run(blk, arc)
            burst([Effects.dust], si: si, at: top, count: 2, dx: -8...8, dy: 0...10, duration: 0.4, delay: 0.65)
        }
    }

    /// What Claude is doing, acted out by the Gremlet beside its window.
    func handleClaude(_ events: [ClaudeWorkEvent]) {
        for e in events {
            switch e {
            case .placedBlock(let id, let count):
                guard let st = props[id], let l = st.build, let c = creature(id), let j = c.job else { continue }
                let b = st.biome ?? Biome.pick(.plank, seed: UInt64(abs(j.windowID ?? c.id)), month: world.month)
                if let cell = BuildArt.lastCell(b, blocks: count) {
                    let f = l.frame
                    let pt = CGPoint(x: f.minX + CGFloat(cell.x * 3), y: f.minY + CGFloat(cell.y * 3))
                    burst([Effects.dust, Effects.smallStar], si: st.screen, at: pt, count: 3, dx: -14...14, dy: -4...14, duration: 0.45)
                    if BuildArt.isComplete(b, blocks: count) && !BuildArt.isComplete(b, blocks: count - 1) {
                        burst([Effects.sparkle, Effects.star, Effects.heart], si: st.screen, at: CGPoint(x: f.midX, y: f.maxY), count: 10, dx: -40...40, dy: 10...60, duration: 1.4, stagger: 0.05)
                    }
                }
                let a = CAKeyframeAnimation(keyPath: "transform.scale.y"); a.values = [1, 1.06, 0.98, 1]; a.duration = 0.25
                l.add(a, forKey: "thunk")
            case .look(let id):
                if let c = creature(id) { spawnEffect(ClaudeIcons.lantern, above: c, drift: 10 * c.facing) }
            case .run(let id):
                if let c = creature(id) { spawnEffect(Effects.steam, above: c, drift: 6); spawnEffect(Effects.steam, above: c, drift: -8, delay: 0.2) }
            case .web(let id):
                if let c = creature(id), let (si, p) = localPoint(c, dy: c.size.y * 0.8) {
                    // A paper bird flies off to fetch the page and comes back.
                    let l = particle(ClaudeIcons.paperBird, si)
                    l.position = p
                    let fly = CAKeyframeAnimation(keyPath: "position")
                    let out = CGPoint(x: p.x + c.facing * 220, y: p.y + 160)
                    fly.values = [p, out, CGPoint(x: out.x + c.facing * 40, y: out.y + 30), p].map { NSValue(point: $0) }
                    fly.keyTimes = [0, 0.45, 0.55, 1]
                    fly.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    fly.duration = 2.4
                    run(l, fly)
                }
            case .plan(let id):
                if let c = creature(id) { spawnEffect(ClaudeIcons.flag, above: c, drift: 0) }
            case .helperJoined, .helperLeft, .weather:
                break   // drawn by updateBuild
            }
        }
    }

    /// Each biome breathes a little: snow drifts off the snowy island, petals off the cherry one, drips from jungle
    /// vines, sand trickling from the desert, sparks rising off glowing mushrooms and crystals.
    private func islandAmbient(_ b: Biome, si: Int, s: Surface, origin o: CGPoint) {
        let x = Double.random(in: s.minX + 10...s.maxX - 10) - o.x
        let top = CGPoint(x: x, y: s.y - o.y + 6), under = CGPoint(x: x, y: s.y - o.y - 30)
        switch b {
        case .snow: burst([Effects.snow], si: si, at: under, count: 1, dx: -20...20, dy: -120 ... -60, duration: 3)
        case .cherry: burst([Effects.petal], si: si, at: top, count: 1, dx: -60...60, dy: -110 ... -40, duration: 3.2)
        case .autumn: burst([Effects.leaf, Effects.leaf2], si: si, at: top, count: 1, dx: -50...50, dy: -110 ... -40, duration: 3)
        case .jungle: burst([Effects.rain], si: si, at: under, count: 1, dx: -2...2, dy: -90 ... -60, duration: 0.9)
        case .desert: burst([Effects.dust], si: si, at: under, count: 1, dx: -4...4, dy: -70 ... -40, duration: 1.2)
        case .glowshroom, .crystal: burst([Effects.sparkle, Effects.smallStar], si: si, at: top, count: 1, dx: -10...10, dy: 20...60, duration: 1.8)
        case .sky: burst([Effects.cloud], si: si, at: under, count: 1, dx: -40...40, dy: -20...10, duration: 3)
        case .meadow: burst([Effects.pollen], si: si, at: top, count: 1, dx: -30...30, dy: 10...50, duration: 2.2)
        }
    }

    /// A little local (bunny, penguin, frog, lizard, glowing snail) hops across its island and away.
    private func spawnCritter(_ b: Biome, si: Int, from s: Surface, origin o: CGPoint, flip: CGFloat) {
        let frames = [IslandArt.critter(b, frame: 0), IslandArt.critter(b, frame: 1)]
        let l = particle(frames[0], si)
        l.anchorPoint = CGPoint(x: 0.5, y: 0)
        l.zPosition = -0.5
        let leftToRight = Bool.random()
        let x0 = (leftToRight ? s.minX + 8 : s.maxX - 8) - o.x, x1 = (leftToRight ? s.maxX + 30 : s.minX - 30) - o.x
        let y = s.y - o.y
        l.setAffineTransform(CGAffineTransform(scaleX: leftToRight ? 1 : -1, y: 1))
        let hops = 7
        var pts: [NSValue] = []
        for i in 0...(hops * 2) {
            let t = Double(i) / Double(hops * 2)
            pts.append(NSValue(point: CGPoint(x: x0 + (x1 - x0) * t, y: y + (i % 2 == 1 ? 7 : 0))))
        }
        let move = CAKeyframeAnimation(keyPath: "position"); move.values = pts
        let anim = CAKeyframeAnimation(keyPath: "contents"); anim.values = frames; anim.calculationMode = .discrete
        anim.duration = 0.36; anim.repeatCount = .infinity
        let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.08, 0.85, 1]
        let g = CAAnimationGroup(); g.animations = [move, fade]; g.duration = Double(hops) * 0.55
        l.add(anim, forKey: "hop")
        run(l, g)
    }

    private func spawnBird(_ st: PropState, side: Double) {
        guard let shelf = st.shelf else { return }
        let si = st.screen, f = shelf.frame
        let perch = CGPoint(x: side > 0 ? f.maxX - 8 : f.minX + 8, y: f.maxY + 6)
        let l = particle(PropArt.bird[0], si, scale: 3)
        let from = CGPoint(x: perch.x + CGFloat(side) * 260, y: perch.y + 180)
        let to = CGPoint(x: perch.x + CGFloat(side) * 300, y: perch.y + 240)
        let path = CGMutablePath()
        path.move(to: from)
        path.addQuadCurve(to: perch, control: CGPoint(x: perch.x + CGFloat(side) * 60, y: perch.y + 120))
        path.addLine(to: CGPoint(x: perch.x + 0.1, y: perch.y))
        path.addQuadCurve(to: to, control: CGPoint(x: perch.x - CGFloat(side) * 20, y: perch.y + 90))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.keyTimes = [0, 0.25, 0.75, 1]
        move.calculationMode = .linear
        let hop = CAKeyframeAnimation(keyPath: "transform.scale.y")
        hop.values = [1, 0.7, 1, 1, 0.8, 1]; hop.keyTimes = [0, 0.05, 0.1, 0.5, 0.55, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.08, 0.92, 1]
        let g = CAAnimationGroup(); g.animations = [move, hop, fade]; g.duration = 7
        l.setAffineTransform(CGAffineTransform(scaleX: side > 0 ? -1 : 1, y: 1))
        run(l, g)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            self?.burst([Effects.note], si: si, at: CGPoint(x: perch.x, y: perch.y + 14), count: 1, dx: -4...4, dy: 16...24, duration: 0.9)
        }
    }

    // MARK: Desktop icons

    private func layerRect(_ r: CGRect) -> (Int, CGRect)? {
        guard !screens.isEmpty else { return nil }
        let si = screenIndex(for: Vec2(r.midX, r.midY))
        let o = screens[si].frame.origin
        return (si, r.offsetBy(dx: -o.x, dy: -o.y))
    }

    /// A Gremlet landed on an icon: it squashes and springs back (a copy over the real one, wallpaper behind it).
    private func iconBoing(_ icon: DesktopIcons.Icon) {
        guard let img = icons?.image(icon), let (si, r) = layerRect(icon.rect) else { return }
        if let patchImg = icons?.wallpaperPatch(for: icon.rect) {
            let patch = CALayer(); patch.contents = patchImg; patch.frame = r
            screens[si].root.insertSublayer(patch, at: 0)
            let keep = CABasicAnimation(keyPath: "opacity"); keep.fromValue = 1; keep.toValue = 1; keep.duration = 0.55
            run(patch, keep)
        }
        let copy = CALayer(); copy.contents = img
        copy.anchorPoint = CGPoint(x: 0.5, y: 0); copy.bounds = CGRect(origin: .zero, size: r.size)
        copy.position = CGPoint(x: r.midX, y: r.minY)
        screens[si].root.insertSublayer(copy, at: 1)
        let sq = CAKeyframeAnimation(keyPath: "transform")
        sq.values = [CATransform3DIdentity, CATransform3DMakeScale(1.12, 0.78, 1), CATransform3DMakeScale(0.94, 1.1, 1), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        sq.duration = 0.55
        run(copy, sq)
    }

    /// Pick-ups: now and then a Gremlet that's been sitting on an icon picks up a copy and carries it around over its
    /// head for a few seconds, then tosses it back into place.
    private func updateIconPlay() {
        let now = CACurrentMediaTime()
        guard let icons, icons.enabled else {
            for id in Array(carries.keys) { endCarry(id, animated: false) }
            return
        }
        for c in world.creatures {
            if let iconID = world.iconUnder(c) {
                if onIconSince[c.id]?.icon != iconID { onIconSince[c.id] = (iconID, now) }
            } else { onIconSince[c.id] = nil }
        }
        if carries.isEmpty, now >= nextPickup,
           let (cid, info) = onIconSince.first(where: { entry in
               now - entry.value.since > 3 && world.creatures.first(where: { $0.id == entry.key })?.job == nil
           }),
           let icon = icons.visible.first(where: { $0.id == info.icon }),
           let img = icons.image(icon), let patchImg = icons.wallpaperPatch(for: icon.rect), let (si, r) = layerRect(icon.rect) {
            nextPickup = now + Double.random(in: 70...150)
            let patch = CALayer(); patch.contents = patchImg; patch.frame = r
            screens[si].root.insertSublayer(patch, at: 0)
            let copy = CALayer(); copy.contents = img
            copy.anchorPoint = CGPoint(x: 0.5, y: 0); copy.bounds = CGRect(origin: .zero, size: CGSize(width: r.width * 0.7, height: r.height * 0.7))
            copy.position = CGPoint(x: r.midX, y: r.minY)
            screens[si].root.addSublayer(copy)
            carries[cid] = (icon, copy, patch, now + Double.random(in: 8...12))
            liftedIcons.insert(icon.id)
            showBubble(["Ooh, what's this?", "Borrowing this!", "Wheee!"].randomElement()!, on: cid, seconds: 2.5)
        }
        for (cid, carry) in carries {
            guard let c = world.creatures.first(where: { $0.id == cid }), let csi = layerScreen[cid] else { endCarry(cid, animated: false); continue }
            if now >= carry.until { endCarry(cid, animated: true); continue }
            let o = screens[csi].frame.origin
            if carry.copy.superlayer !== screens[csi].root { carry.copy.removeFromSuperlayer(); screens[csi].root.addSublayer(carry.copy) }
            carry.copy.position = CGPoint(x: (c.pos.x - o.x).rounded(), y: (c.pos.y - o.y + c.size.y * 0.82 + sin(now * 6) * 2).rounded())
        }
    }

    /// Back it goes: the copy arcs home onto its spot and the wallpaper patch comes away.
    private func endCarry(_ cid: Int, animated: Bool) {
        guard let carry = carries.removeValue(forKey: cid) else { return }
        liftedIcons.remove(carry.icon.id)
        guard animated, let (si, r) = layerRect(carry.icon.rect), carry.copy.superlayer != nil else {
            carry.copy.removeFromSuperlayer(); carry.patch.removeFromSuperlayer(); return
        }
        if world.creatures.contains(where: { $0.id == cid }) { showBubble("Putting it back!", on: cid, seconds: 1.8) }
        let from = carry.copy.position
        let to = CGPoint(x: r.midX, y: r.minY)
        if carry.copy.superlayer !== screens[si].root { carry.copy.removeFromSuperlayer(); screens[si].root.addSublayer(carry.copy) }
        let path = CGMutablePath()
        path.move(to: from)
        path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + 160))
        let fly = CAKeyframeAnimation(keyPath: "position"); fly.path = path
        let grow = CABasicAnimation(keyPath: "bounds.size"); grow.toValue = NSValue(size: r.size)
        let g = CAAnimationGroup(); g.animations = [fly, grow]; g.duration = 0.9
        g.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let patch = carry.patch
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            patch.removeFromSuperlayer()
            self?.burst([Effects.dust, Effects.sparkle], si: si, at: CGPoint(x: r.midX, y: r.minY), count: 4, dx: -30...30, dy: 0...20, duration: 0.5)
        }
        run(carry.copy, g)
        CATransaction.commit()
    }

    /// A swirling portal (to and from the phone).
    /// A little burst of sparkles at a world point (a Gremlet slipping through the doorway to another screen).
    func sparkle(at p: Vec2) {
        let si = screenIndexFor(p)
        guard si < screens.count else { return }
        let o = screens[si].frame.origin
        burst([Effects.sparkle, Effects.smallStar], si: si, at: CGPoint(x: p.x - o.x, y: p.y - o.y), count: 6, dx: -30...30, dy: -20...40, duration: 0.8, stagger: 0.04)
    }

    func portal(at p: Vec2) {
        guard !screens.isEmpty else { return }
        let si = screenIndex(for: p)
        let o = screens[si].frame.origin
        let c = CGPoint(x: p.x - o.x, y: p.y - o.y)
        for (i, color) in [NSColor(red: 0.66, green: 0.55, blue: 0.92, alpha: 1), NSColor(red: 0.44, green: 0.72, blue: 0.94, alpha: 1), NSColor(red: 1, green: 0.56, blue: 0.75, alpha: 1)].enumerated() {
            let ring = CAShapeLayer()
            let r = CGFloat(54 - i * 12)
            ring.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2.6)
            ring.position = c
            ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 3, dy: 3), transform: nil)
            ring.fillColor = i == 2 ? NSColor(red: 0.2, green: 0.12, blue: 0.35, alpha: 0.55).cgColor : NSColor.clear.cgColor
            ring.strokeColor = color.cgColor
            ring.lineWidth = 5
            ring.lineDashPattern = [10, 6]
            ring.shadowColor = color.cgColor; ring.shadowOpacity = 0.9; ring.shadowRadius = 8; ring.shadowOffset = .zero
            screens[si].root.addSublayer(ring)
            let spin = CABasicAnimation(keyPath: "lineDashPhase")
            spin.fromValue = 0; spin.toValue = i % 2 == 0 ? 64 : -64
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.05, 1.1, 1.0, 1.0, 0.05]; scale.keyTimes = [0, 0.2, 0.3, 0.8, 1]
            let g = CAAnimationGroup(); g.animations = [spin, scale]; g.duration = 1.6
            run(ring, g)
        }
        burst([Effects.sparkle, Effects.smallStar], si: si, at: c, count: 12, dx: -70...70, dy: -60...80, duration: 1.2, stagger: 0.04)
    }

    /// Plants grown on the phone go in the seed book and get planted in the garden here.
    func receiveHarvest(_ plants: [Plant], nearX x: Double) {
        guard !plants.isEmpty else { return }
        for p in plants { seedBook.record(p) }
        world.groveHarvestBonus()
        onGardenChange()
    }

    /// A mushroom pops out of the ground, squashes, and springs a Gremlet up.
    private func springMushroom(at p: CGPoint, _ si: Int) {
        let l = particle(PropArt.springMushroom, si, scale: 3)
        l.anchorPoint = CGPoint(x: 0.5, y: 0)
        l.position = p
        let sy = CAKeyframeAnimation(keyPath: "transform.scale.y")
        sy.values = [0.1, 1.15, 0.55, 1.2, 1.0, 1.0, 0.1]
        sy.keyTimes = [0, 0.12, 0.2, 0.3, 0.4, 0.85, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.8, 1]
        let g = CAAnimationGroup(); g.animations = [sy, fade]; g.duration = 1.6
        run(l, g)
        burst([Effects.dust], si: si, at: p, count: 3, dx: -26...26, dy: 0...8, duration: 0.45)
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
                let islandStyles: [ShelfStyle] = [.plank, .stone, .leaf, .cloud, .mushroom]
                let seed = UInt64(abs(j.windowID ?? (c.id &* 7919)))
                if islandStyles.contains(j.shelfStyle) && st.biome == nil { st.biome = Biome.pick(j.shelfStyle, seed: seed, month: world.month) }
                if st.shelf == nil || st.shelfPx != px || st.screen != si {
                    st.shelf?.removeFromSuperlayer()
                    let l = pixelLayer(si, anchor: CGPoint(x: 0, y: 1))
                    if let b = st.biome {
                        setImage(l, IslandArt.body(b, widthPx: px, seed: seed))
                    } else {
                        setImage(l, PropArt.shelf(j.shelfStyle, widthPx: px))
                    }
                    screens[si].root.insertSublayer(l, at: 0)
                    if st.shelf == nil { popIn(l); burst([Effects.dust], si: si, at: CGPoint(x: s.minX - o.x + s.width / 2, y: s.y - o.y), count: 3, dx: -40...40, dy: -6...6, duration: 0.5) }
                    st.shelf = l; st.shelfPx = px
                }
                let flip: CGFloat = (j.shelfSide ?? 1) < 0 ? -1 : 1
                st.shelf?.setAffineTransform(CGAffineTransform(scaleX: flip, y: 1))
                let p = CGPoint(x: (s.minX - o.x).rounded() + (flip < 0 ? s.width : 0), y: (s.y - o.y).rounded())
                st.shelf?.anchorPoint = CGPoint(x: 0, y: 1)
                if st.shelf?.position != p { st.shelf?.position = p }
                if let b = st.biome {
                    let key = "\(b.rawValue)-\(px)-\(world.isNight)-\(si)"
                    if st.decorKey != key {
                        st.decor?.removeFromSuperlayer()
                        let d = pixelLayer(si, anchor: CGPoint(x: 0, y: 0))
                        setImage(d, IslandArt.decor(b, widthPx: px, seed: seed, night: world.isNight))
                        screens[si].root.insertSublayer(d, at: 0)
                        if st.decor == nil { popIn(d) }
                        st.decor = d; st.decorKey = key
                    }
                    st.decor?.setAffineTransform(CGAffineTransform(scaleX: flip, y: 1))
                    st.decor?.anchorPoint = CGPoint(x: 0, y: 0)
                    if st.decor?.position != p { st.decor?.position = p }
                    if now >= st.nextAmbient {
                        st.nextAmbient = now + Double.random(in: 1.4...3.2)
                        islandAmbient(b, si: si, s: s, origin: o)
                    }
                    if j.phase == .working, now >= st.nextCritter {
                        if st.nextCritter > 0 { spawnCritter(b, si: si, from: s, origin: o, flip: flip) }
                        st.nextCritter = now + Double.random(in: 25...70)
                    }
                }
                updateShelfExtra(&st, j, s, si, o, flip)
                updateBuild(&st, c, j, ground: s.y, x: flip > 0 ? s.minX + s.width * 0.3 : s.maxX - s.width * 0.3, si: si, origin: o)
                if j.shelfStyle == .carpet {
                    let phase = Int(CACurrentMediaTime() * 7) % 8
                    if phase != st.carpetPhase { st.carpetPhase = phase; st.shelf?.contents = PropArt.carpet(widthPx: px, phase: phase) }
                    st.shelf?.position.y += 6
                }
                if j.shelfStyle == .swing, let ex = st.extra, CACurrentMediaTime() < st.swingBoostUntil {
                    ex.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(sin(CACurrentMediaTime() * 4) * 0.08)))
                }
                if j.phase == .working, now >= st.nextBird {
                    if st.nextBird > 0 && j.shelfStyle != .snail { spawnBird(st, side: j.shelfSide ?? 1) }
                    st.nextBird = now + Double.random(in: 45...110)
                }
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
            } else if let l = st.shelf { l.removeFromSuperlayer(); st.shelf = nil; st.lantern?.removeFromSuperlayer(); st.lantern = nil; st.extra?.removeFromSuperlayer(); st.extra = nil; st.decor?.removeFromSuperlayer(); st.decor = nil; st.decorKey = "" }
            // No shelf (working on the floor): the building goes up on the ground beside it.
            if shelf == nil { updateBuild(&st, c, j, ground: ref.y, x: ref.x - j.propSide * 90, si: si, origin: o) }

            // The bouncy mushroom that launches a Gremlet up to its shelf.
            if let b = j.bounceAt, b != st.lastBounce, let spot = j.bounceSpot {
                st.lastBounce = b
                springMushroom(at: CGPoint(x: spot.x - o.x, y: spot.y - o.y), si)
            }

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
                    : st.harvest.contains { $0.kind == .crystalRose || $0.kind == .starLily } ? "crystal" : st.harvest.contains { $0.kind == .wishingTree } ? "gold" : ""
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
                if st.harvest.contains(where: { $0.golden || $0.kind == .starLily }) && now >= st.nextSparkle {
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
            if let d = st.decor { fadeOut(d, 0.4); st.decor = nil; st.decorKey = "" }
            if let b = st.build {
                // The finished building moves down to the village and stays.
                if let biome = st.lastBiome, st.lastBlocks >= 4 {
                    let day = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
                    let fit = BuildArt.fit(biome)
                    world.addHouse(biome: biome.rawValue, blocks: st.lastBlocks, size: fit.size, project: st.project, day: day,
                                   builtAt: Date().timeIntervalSince1970, roof: fit.roof)
                    st.lastBlocks = 0
                }
                fadeOut(b, 0.8); st.build = nil; st.buildKey = ""
            }
            for h in st.helpers { fadeOut(h, 0.4) }
            if let fl = st.flag { fadeOut(fl, 0.3); st.flag = nil }
            if let wl = st.weatherLayer { fadeOut(wl, 0.4); st.weatherLayer = nil; st.weatherKind = "" }
            st.helpers.removeAll()
            if let l = st.lantern { fadeOut(l, 0.4); st.lantern = nil }
            if let l = st.extra { fadeOut(l, 0.5); st.extra = nil }
            if let l = st.extra2 { fadeOut(l, 0.5); st.extra2 = nil }
            if st.lingerUntil == nil { st.lingerUntil = now + (st.wasOnShelf ? 0 : 60) }
            if now >= st.lingerUntil! || st.item.superlayer == nil {
                fadeOut(st.item, 0.8)
                props[id] = nil
                // The harvest has already gone where it means something: flowers on the project's bonsai for a
                // Claude session, sparks for the grove otherwise.
                if !st.harvest.isEmpty { onGardenChange() }
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

    /// What a floating Gremlet rides: a balloon, soap bubble, dandelion puff, umbrella or big leaf. When it lands,
    /// the balloon drifts away, the bubble pops, and the rest float off and fade.
    private func updateBalloon(_ c: Creature) {
        let floating = c.activity == .float && !c.isZipping && !c.isClimbing   // zipline riders hang from a pulley, climbers from the vine
        if !floating {
            if let b = balloons.removeValue(forKey: c.id) {
                let start = b.position
                let g = CAAnimationGroup()
                if b.name == "bubble" {
                    let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 1; grow.toValue = 1.4
                    let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0
                    g.animations = [grow, fade]; g.duration = 0.25
                    if let si = layerScreen[c.id] { burst([Effects.sparkle], si: si, at: start, count: 5, dx: -40...40, dy: -20...40, duration: 0.5) }
                } else {
                    let drift = CABasicAnimation(keyPath: "position")
                    drift.fromValue = NSValue(point: start)
                    drift.toValue = NSValue(point: CGPoint(x: start.x + 30, y: start.y + (b.name == "balloon" ? 260 : 60)))
                    let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0
                    g.animations = [drift, fade]; g.duration = b.name == "balloon" ? 2.2 : 1.2
                    g.timingFunction = CAMediaTimingFunction(name: .easeIn)
                }
                run(b, g)
            }
            return
        }
        guard let si = layerScreen[c.id] else { return }
        let style = c.ride == .bounce ? Ride.balloon : c.ride
        if let existing = balloons[c.id], existing.name != style.rawValue {
            existing.removeFromSuperlayer(); balloons[c.id] = nil
        }
        let b: CALayer
        if let existing = balloons[c.id] { b = existing } else {
            if style == .bubble {
                // A soap bubble around the whole Gremlet.
                let r = c.size.x * 0.62
                let shape = CAShapeLayer()
                shape.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
                shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                shape.path = CGPath(ellipseIn: shape.bounds.insetBy(dx: 2, dy: 2), transform: nil)
                shape.fillColor = NSColor(red: 0.75, green: 0.9, blue: 1, alpha: 0.18).cgColor
                shape.strokeColor = NSColor(red: 0.7, green: 0.85, blue: 1, alpha: 0.9).cgColor
                shape.lineWidth = 2
                let shine = CAShapeLayer()
                shine.path = CGPath(ellipseIn: CGRect(x: r * 0.45, y: r * 1.35, width: r * 0.35, height: r * 0.22), transform: nil)
                shine.fillColor = NSColor(white: 1, alpha: 0.8).cgColor
                shape.addSublayer(shine)
                b = shape
            } else {
                b = pixelLayer(si, anchor: CGPoint(x: 0.5, y: 0))
                let img = PropArt.ride(style, c.id)
                if style == .balloon {
                    b.bounds = CGRect(x: 0, y: 0, width: img.width * 3, height: img.height * 3 + 30)
                    let face = CALayer()
                    face.contents = img
                    face.magnificationFilter = .nearest
                    face.frame = CGRect(x: 0, y: 30, width: img.width * 3, height: img.height * 3)
                    let string = CALayer()
                    string.backgroundColor = NSColor(white: 0.25, alpha: 0.9).cgColor
                    string.frame = CGRect(x: Double(img.width) * 1.5 - 1, y: 0, width: 1.5, height: 32)
                    b.addSublayer(string); b.addSublayer(face)
                } else {
                    setImage(b, img)
                }
            }
            b.name = style.rawValue
            screens[si].root.addSublayer(b)
            popIn(b)
            balloons[c.id] = b
        }
        let o = screens[si].frame.origin
        let p: CGPoint
        if style == .bubble {
            p = CGPoint(x: (c.pos.x - o.x).rounded(), y: (c.pos.y - o.y + c.size.y * 0.42).rounded())
        } else {
            p = CGPoint(x: (c.pos.x - o.x + c.facing * c.size.x * 0.06).rounded(), y: (c.pos.y - o.y + c.size.y * 0.72).rounded())
            // Umbrellas and leaves sway a little on the way down.
            if style == .umbrella || style == .leaf {
                b.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(sin(CACurrentMediaTime() * 2.4) * 0.12)))
            }
        }
        if b.superlayer !== screens[si].root { b.removeFromSuperlayer(); screens[si].root.addSublayer(b) }
        if b.position != p { b.position = p }
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
        let hot = world.creature(at: p) != nil || propOwner(at: p) != nil || platformOwner(at: p) != nil
            || fx.plant(at: p) != nil || fx.house(at: p) != nil || bonsaiFX.hit(at: p) != nil
        setClickThrough(hot ? screenIndex(for: p) : nil)
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
        if world.creature(at: vec(p)) == nil, propOwner(at: vec(p)) == nil, platformOwner(at: vec(p)) == nil, let b = bonsaiFX.hit(at: vec(p)) {
            bonsaiFX.describe(b); return
        }
        if world.creature(at: vec(p)) == nil, propOwner(at: vec(p)) == nil, platformOwner(at: vec(p)) == nil, let i = fx.plant(at: vec(p)) {
            fx.describePlant(i); return
        }
        if world.creature(at: vec(p)) == nil, propOwner(at: vec(p)) == nil, platformOwner(at: vec(p)) == nil, let n = fx.house(at: vec(p)) {
            fx.describeHouse(n); return
        }
        if world.creature(at: vec(p)) == nil, let owner = propOwner(at: vec(p)) { pressedProp = owner; return }
        if world.creature(at: vec(p)) == nil, let owner = platformOwner(at: vec(p)) { pressedPlatform = owner; return }
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
        if let owner = pressedPlatform {
            pressedPlatform = nil
            if platformOwner(at: vec(p)) == owner { pokePlatform(owner) }
            updateClickThrough()
            return
        }
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
            if c.job?.kind == .claude { onWorkerClicked(c) }
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

/// Tiny icons for what Claude is doing.
enum ClaudeIcons {
    static let lantern = Effects.pixels([
        ".kk.",
        "kyyk",
        "yYYy",
        "kyyk",
        ".kk.",
    ], ["k": 0x5E3B22, "y": 0xFFC845, "Y": 0xFFF3A0])
    static let paperBird = Effects.pixels([
        "w....",
        "ww..w",
        ".wwww",
        "..ww.",
    ], ["w": 0xF4F6FA])
    static let flag = Effects.pixels([
        "krr.",
        "krrr",
        "krr.",
        "k...",
        "k...",
    ], ["k": 0x6B4428, "r": 0xE8574A])
}
