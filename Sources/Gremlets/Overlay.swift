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

    // Input state.
    private var pressed: Creature?
    private var pressStart: Vec2 = .zero
    private var dragging = false
    private var lastMouse: Vec2?
    private var monitors: [Any] = []

    var paused = false { didSet { if paused { setClickThrough(nil) } } }

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
            panel.orderFrontRegardless()
            return Screen(frame: ns.frame, panel: panel, root: root)
        }
        layerScreen.removeAll()
        for (_, l) in layers { l.removeFromSuperlayer() }
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
            layer.position = CGPoint(x: (c.pos.x - origin.x).rounded(), y: (c.pos.y - origin.y).rounded())
            layer.setAffineTransform(CGAffineTransform(scaleX: c.facing < 0 ? -1 : 1, y: 1))
            let f = c.currentFrame
            if shownFrame[c.id] != f, f < sp.frames.count {
                layer.contents = sp.frames[f]
                shownFrame[c.id] = f
            }
            if c.activity == .sleep {
                let now = CACurrentMediaTime()
                if now - (sleepBubbleTimer[c.id] ?? 0) > 1.6 {
                    sleepBubbleTimer[c.id] = now
                    spawnEffect(Effects.zzz, above: c, drift: 18 * c.facing)
                }
            }
        }
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
            case .poked(let id), .petted(let id):
                if let c = world.creatures.first(where: { $0.id == id }) { spawnEffect(Effects.heart, above: c, drift: 0) }
            default: break
            }
        }
    }

    /// Small floating particle (heart, zzz). Animated entirely by Core Animation, so it costs no CPU per frame.
    private func spawnEffect(_ image: CGImage, above c: Creature, drift: Double) {
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
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(group, forKey: "float")
        CATransaction.commit()
    }

    // MARK: Click-through + input

    /// Lets the panel under the cursor receive clicks only while the cursor is over a creature's opaque pixels.
    func updateClickThrough() {
        if paused { return }
        let p = vec(NSEvent.mouseLocation)
        if dragging || pressed != nil { return }
        setClickThrough(world.creature(at: p) != nil ? screenIndex(for: p) : nil)
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
        guard !paused, let c = world.creature(at: vec(p)) else { return }
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
