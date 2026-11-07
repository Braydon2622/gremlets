import AppKit
import GremletsCore

/// Draws the project bonsai (on their terminal windows, or resting on the nursery's bracket shelves), the ivy that
/// creeps along a Claude window's top edge while Claude works, and the mossy ledges that grow out of its side.
final class BonsaiRenderer {
    unowned let overlay: OverlayController
    let world: World

    private struct TreeLayer { let layer: CALayer; var key: String; var si: Int; var tag: CATextLayer; var lastBase: CGPoint }
    private var trees: [String: TreeLayer] = [:]
    private var images: [String: (CGImage, CGPoint)] = [:]
    private var brackets: [Int: (layer: CALayer, key: String)] = [:]
    private var ivy: [Int: (layer: CALayer, key: String)] = [:]
    private var ledges: [Int: (layer: CALayer, key: String)] = [:]
    private var moveBurst = Set<String>()

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

    func rebuild() {
        for t in trees.values { t.layer.removeFromSuperlayer(); t.tag.removeFromSuperlayer() }
        trees.removeAll()
        for b in brackets.values { b.layer.removeFromSuperlayer() }; brackets.removeAll()
        for i in ivy.values { i.layer.removeFromSuperlayer() }; ivy.removeAll()
        for l in ledges.values { l.layer.removeFromSuperlayer() }; ledges.removeAll()
    }

    // MARK: Frame

    func render() {
        renderBrackets()
        renderTrees()
        renderIvy()
        renderLedges()
        renderNests()
        renderNightLife()
    }

    private var nextFirefly: [String: CFTimeInterval] = [:]
    private var lanterns: [Int: CALayer] = [:]

    /// After dark: fireflies drift through the trees that are growing right now, and a lantern hangs under the
    /// lowest ledge of every window Claude is working in.
    private func renderNightLife() {
        let now = CACurrentMediaTime()
        guard world.isNight else {
            for (_, l) in lanterns { fadeOut(l) }; lanterns.removeAll()
            return
        }
        for p in world.bonsaiPlacements where p.slot < 0 && now >= (nextFirefly[p.project] ?? 0) {
            nextFirefly[p.project] = now + Double.random(in: 0.9...1.8)
            let L = p.layout
            let x = p.base.x + Double.random(in: L.bounds.minX...L.bounds.maxX) * p.scale
            let y = p.base.y + Double.random(in: max(10, L.bounds.maxY * 0.3)...max(12, L.bounds.maxY)) * p.scale
            if let (si, pt) = local(Vec2(x, y)) { firefly(si, at: pt) }
        }
        var alive = Set<Int>()
        for l in world.terminalLedges where l.index == 0 {
            let s = l.surface
            alive.insert(s.ownerID)
            guard let (si, pt) = local(Vec2(l.side > 0 ? s.maxX - 12 : s.minX + 12, s.y - 9)) else { continue }
            let layer = lanterns[s.ownerID] ?? {
                let l = pixelLayer()
                l.contents = PropArt.lantern
                l.anchorPoint = CGPoint(x: 0.5, y: 1)
                l.bounds = CGRect(x: 0, y: 0, width: Double(PropArt.lantern.width) * artScale, height: Double(PropArt.lantern.height) * artScale)
                l.shadowColor = NSColor(red: 1, green: 0.8, blue: 0.35, alpha: 1).cgColor; l.shadowOpacity = 0.9; l.shadowRadius = 9; l.shadowOffset = .zero
                l.zPosition = 1.6
                popIn(l)
                return l
            }()
            attach(layer, si)
            layer.position = pt
            lanterns[s.ownerID] = layer
        }
        for (id, l) in lanterns where !alive.contains(id) { fadeOut(l); lanterns[id] = nil }
    }

    private func firefly(_ si: Int, at p: CGPoint) {
        guard si < screens.count else { return }
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
        l.cornerRadius = 2
        l.backgroundColor = NSColor(red: 1, green: 0.9, blue: 0.45, alpha: 1).cgColor
        l.shadowColor = NSColor(red: 1, green: 0.85, blue: 0.3, alpha: 1).cgColor; l.shadowRadius = 5; l.shadowOpacity = 1; l.shadowOffset = .zero
        l.position = p
        l.zPosition = 26
        screens[si].root.addSublayer(l)
        let path = CAKeyframeAnimation(keyPath: "position")
        var pts: [NSValue] = [NSValue(point: p)]
        var cur = p
        for _ in 0..<5 { cur = CGPoint(x: cur.x + .random(in: -26...26), y: cur.y + .random(in: -14...18)); pts.append(NSValue(point: cur)) }
        path.values = pts
        let blink = CAKeyframeAnimation(keyPath: "opacity"); blink.values = [0, 1, 0.2, 1, 0.3, 1, 0]
        let g = CAAnimationGroup(); g.animations = [path, blink]; g.duration = Double.random(in: 3...5)
        g.isRemovedOnCompletion = false; g.fillMode = .forwards
        CATransaction.begin(); CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(g, forKey: "fly"); CATransaction.commit()
    }

    private var carried: [Int: CALayer] = [:]
    private var nests: [String: CALayer] = [:]
    private var nextBird: [String: CFTimeInterval] = [:]

    /// Seconds Claude has been working in the session this live tree belongs to.
    private func sessionSeconds(_ p: BonsaiPlacement) -> Double {
        world.creatures.first { $0.job?.label == p.project && $0.job?.kind == .claude }?.job?.workSeconds ?? 0
    }

    /// An hour into a session a pair of birds nests in the lowest pad; after two, one flies off and back now and then.
    private func renderNests() {
        var alive = Set<String>()
        let now = CACurrentMediaTime()
        for p in world.bonsaiPlacements where p.slot < 0 {
            let worked = sessionSeconds(p)
            guard worked >= 3600, let pad = p.layout.pads.filter({ $0.branch >= 0 }).min(by: { $0.center.y < $1.center.y }),
                  let (si, pt) = local(p.base + (pad.center + Vec2(0, pad.ry * 0.5)) * p.scale) else { continue }
            alive.insert(p.project)
            let l = nests[p.project] ?? { let l = pixelLayer(); l.contents = BonsaiArt.nest; l.anchorPoint = CGPoint(x: 0.5, y: 0); l.bounds = CGRect(x: 0, y: 0, width: 30, height: 18); l.zPosition = 2.5; popIn(l); return l }()
            attach(l, si)
            l.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
            nests[p.project] = l
            if worked >= 7200, now >= (nextBird[p.project] ?? now + 10) {
                nextBird[p.project] = now + Double.random(in: 30...60)
                birdVisit(si, nest: CGPoint(x: pt.x, y: pt.y + 10))
            } else if nextBird[p.project] == nil { nextBird[p.project] = now + 15 }
        }
        for (k, l) in nests where !alive.contains(k) { fadeOut(l); nests[k] = nil }
    }

    private func birdVisit(_ si: Int, nest: CGPoint) {
        guard si < screens.count, PropArt.bird.count > 1 else { return }
        let l = pixelLayer()
        l.contents = PropArt.bird[0]
        l.bounds = CGRect(x: 0, y: 0, width: Double(PropArt.bird[0].width) * artScale, height: Double(PropArt.bird[0].height) * artScale)
        l.zPosition = 27
        attach(l, si)
        let side: CGFloat = Bool.random() ? 1 : -1
        let away = CGPoint(x: nest.x + side * 320, y: nest.y + 220)
        let fly = CAKeyframeAnimation(keyPath: "position")
        fly.values = [nest, CGPoint(x: (nest.x + away.x) / 2, y: max(nest.y, away.y) + 60), away, CGPoint(x: (nest.x + away.x) / 2, y: max(nest.y, away.y) + 60), nest].map { NSValue(point: $0) }
        fly.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        fly.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let flap = CAKeyframeAnimation(keyPath: "contents"); flap.values = PropArt.bird; flap.calculationMode = .discrete; flap.duration = 0.3; flap.repeatCount = .infinity
        let g = CAAnimationGroup(); g.animations = [fly]; g.duration = 6
        g.isRemovedOnCompletion = false; g.fillMode = .forwards
        l.add(flap, forKey: "flap")
        CATransaction.begin(); CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(g, forKey: "visit"); CATransaction.commit()
    }

    /// The Gremlet whose session a live tree belongs to, while it's still on its way to the window.
    private func carrier(for p: BonsaiPlacement) -> Creature? {
        guard p.slot < 0 else { return nil }
        return world.creatures.first { $0.job?.label == p.project && $0.job?.kind == .claude && $0.job?.phase == .travel }
    }

    private func renderTrees() {
        let now = Date().timeIntervalSince1970
        var alive = Set<String>()
        var carrying = Set<Int>()
        for p in world.bonsaiPlacements {
            // On its way: the Gremlet carries the pot (a little pot above its head); the tree pops in when it arrives.
            if let c = carrier(for: p), let (si, pt) = local(c.pos + Vec2(c.facing * 4, c.size.y + 2)) {
                carrying.insert(c.id)
                let l = carried[c.id] ?? { let l = pixelLayer(); l.contents = BonsaiArt.carriedPot; l.anchorPoint = CGPoint(x: 0.5, y: 0); l.bounds = CGRect(x: 0, y: 0, width: 21, height: 24); l.zPosition = 3; popIn(l); return l }()
                attach(l, si)
                l.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
                l.setAffineTransform(CGAffineTransform(scaleX: c.facing < 0 ? -1 : 1, y: 1))
                carried[c.id] = l
                moveBurst.insert(p.project)
                continue
            }
            guard let tree = world.bonsaiBook[p.project], let (si, pt) = local(p.base) else { continue }
            alive.insert(p.project)
            let age = tree.ageDays(now: now)
            let scaleQ = (p.scale * 20).rounded() / 20
            let key = "\(p.project)|\(tree.edits)|\(tree.blooms)|\(tree.fruit)|\(tree.branches.count)|\(tree.sessions)|\(world.month)|\(world.isNight)|\(scaleQ)|\(Int(age))"
            var t = trees[p.project] ?? {
                let l = pixelLayer()
                l.zPosition = p.slot >= 0 ? -3 : 2
                // A slow sway from the base, like a breeze in the canopy.
                let sway = CABasicAnimation(keyPath: "transform.rotation.z")
                sway.fromValue = -0.012; sway.toValue = 0.012
                sway.duration = 3.1 + Double(tree.seed % 13) * 0.2
                sway.autoreverses = true; sway.repeatCount = .infinity
                sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                l.add(sway, forKey: "sway")
                let tag = CATextLayer()
                tag.alignmentMode = .center
                tag.cornerRadius = 4
                tag.backgroundColor = NSColor(red: 0.1, green: 0.09, blue: 0.08, alpha: 0.72).cgColor
                tag.zPosition = l.zPosition + 0.1
                tag.actions = ["position": NSNull(), "bounds": NSNull()]
                popIn(l)
                return TreeLayer(layer: l, key: "", si: -1, tag: tag, lastBase: .zero)
            }()
            if t.si != si { attach(t.layer, si); attach(t.tag, si); t.si = si }
            if t.key != key {
                let (img, anchor) = images[key] ?? {
                    let made = BonsaiArt.image(tree, layout: p.layout, scale: scaleQ, month: world.month, night: world.isNight, ageDays: age)
                    if images.count > 60 { images.removeAll() }
                    images[key] = made
                    return made
                }()
                t.layer.contents = img
                t.layer.anchorPoint = anchor
                t.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
                t.key = key
                // Golden fruit glows after dark.
                let glow = world.isNight && tree.fruit > 0
                t.layer.shadowColor = NSColor(red: 1, green: 0.82, blue: 0.4, alpha: 1).cgColor
                t.layer.shadowRadius = glow ? 7 : 0; t.layer.shadowOpacity = glow ? 0.55 : 0; t.layer.shadowOffset = .zero
                // The name tag on the pot.
                let font = NSFont.systemFont(ofSize: p.slot >= 0 ? 8 : 9, weight: .heavy)
                let name = tree.project.count > 18 ? String(tree.project.prefix(17)) + "…" : tree.project
                t.tag.string = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: NSColor.white])
                let tw = min(p.layout.potWidth * scaleQ + 30, CGFloat(name.count) * font.pointSize * 0.64 + 12)
                t.tag.bounds = CGRect(x: 0, y: 0, width: tw, height: font.pointSize + 5)
            }
            let base = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
            if t.layer.position != base { t.layer.position = base }
            // On a terminal the window says which project it is; in the nursery the tag hangs under the pot.
            t.tag.isHidden = p.slot < 0
            t.tag.position = CGPoint(x: base.x, y: base.y - p.layout.potHeight * scaleQ - 9)
            t.lastBase = base
            trees[p.project] = t
            if moveBurst.remove(p.project) != nil {
                overlay.burst([Effects.leaf, Effects.sparkle, Effects.dust], si: si, at: CGPoint(x: base.x, y: base.y + 20), count: 8, dx: -40...40, dy: 0...50, duration: 1, stagger: 0.03)
            }
        }
        for (project, t) in trees where !alive.contains(project) {
            fadeOut(t.layer); fadeOut(t.tag)
            trees[project] = nil
        }
        for (id, l) in carried where !carrying.contains(id) { fadeOut(l); carried[id] = nil }
    }

    private func renderBrackets() {
        var used = Set<Int>()
        for p in world.bonsaiPlacements where p.slot >= 0 {
            guard let br = world.nurseryBracket(p.slot), let (si, pt) = local(Vec2(br.minX, br.y)) else { continue }
            used.insert(p.slot)
            let key = "\(Int(br.width))-\(world.nurserySide)-\(si)"
            var e = brackets[p.slot] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0, y: 1); l.zPosition = -4; popIn(l); return (l, "") }()
            attach(e.layer, si)
            if e.key != key {
                let img = BonsaiArt.bracket(widthPx: Int(br.width / artScale), hanging: p.slot % 2 == 1)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
                e.key = key
            }
            // The wall mount is on the screen-edge side.
            let flip: CGFloat = world.nurserySide < 0 ? 1 : -1
            e.layer.setAffineTransform(CGAffineTransform(scaleX: flip, y: 1))
            e.layer.anchorPoint = CGPoint(x: flip > 0 ? 0 : 1, y: 1)
            e.layer.position = CGPoint(x: (flip > 0 ? pt.x : pt.x + br.width).rounded(), y: (pt.y + 3).rounded())
            brackets[p.slot] = e
        }
        for (k, e) in brackets where !used.contains(k) { fadeOut(e.layer); brackets[k] = nil }
    }

    /// Ivy along the top edge of every window a Gremlet is working at (Claude's terminals, and the windows they
    /// garden beside), growing from the tree's pot (or the corner) toward the far end: a quarter of an hour of work
    /// covers a whole terminal.
    private func renderIvy() {
        var alive = Set<Int>()
        for c in world.creatures {
            guard let j = c.job, j.phase == .working || j.phase == .finished, let wid = j.windowID,
                  let w = world.windows[wid], let scr = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: (w.minX + w.w / 2), y: w.maxY - 1)) }) ?? NSScreen.screens.first else { continue }
            let placement = world.bonsaiPlacements.first { $0.windowID == wid }
            // Start beside the pot if the tree is on this window, else at the corner nearer the screen edge.
            let potHalf = placement.map { $0.layout.potWidth * $0.scale / 2 + 6 } ?? 0
            let startX: Double, dir: Double
            if let p = placement {
                dir = p.base.x < (w.minX + w.w / 2) ? 1 : -1
                startX = p.base.x + dir * potHalf
            } else {
                dir = (w.minX - Double(scr.frame.minX)) < (Double(scr.frame.maxX) - w.maxX) ? 1 : -1
                startX = dir > 0 ? w.minX + 4 : w.maxX - 4
            }
            let room = dir > 0 ? w.maxX - 4 - startX : startX - (w.minX + 4)
            let length = min(room, w.w * min(1, j.workSeconds / 900))
            guard length >= 15, let (si, pt) = local(Vec2(startX, w.maxY)) else { continue }
            alive.insert(c.id)
            let px = Int(length / artScale / 5) * 5   // grows in steps, so the image is only remade now and then
            let key = "\(px)-\(dir)-\(si)-\(wid)"
            var e = ivy[c.id] ?? { let l = pixelLayer(); l.anchorPoint = CGPoint(x: 0, y: 0); l.zPosition = 1.5; return (l, "") }()
            attach(e.layer, si)
            if e.key != key && px >= 5 {
                let img = BonsaiArt.ivy(lengthPx: px, seed: UInt64(wid))
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
                if e.key.isEmpty { popIn(e.layer) }
                e.key = key
            }
            e.layer.setAffineTransform(CGAffineTransform(scaleX: dir > 0 ? 1 : -1, y: 1))
            e.layer.anchorPoint = CGPoint(x: dir > 0 ? 0 : 1, y: 0)
            e.layer.position = CGPoint(x: pt.x.rounded(), y: (pt.y - 2).rounded())
            ivy[c.id] = e
        }
        for (id, e) in ivy where !alive.contains(id) { fadeOut(e.layer); ivy[id] = nil }
    }

    private func renderLedges() {
        var alive = Set<Int>()
        for l in world.terminalLedges {
            let s = l.surface
            guard let (si, pt) = local(Vec2(l.side > 0 ? s.minX : s.maxX, s.y)) else { continue }
            alive.insert(s.ownerID)
            let key = "\(l.index)-\(l.side)-\(si)"
            var e = ledges[s.ownerID] ?? {
                let layer = pixelLayer(); layer.zPosition = 1.4; popIn(layer)
                if let (si2, p2) = local(Vec2((s.minX + s.maxX) / 2, s.y)) { overlay.burst([Effects.dust, Effects.leaf], si: si2, at: p2, count: 4, dx: -20...20, dy: 0...16, duration: 0.5) }
                return (layer, "")
            }()
            attach(e.layer, si)
            if e.key != key {
                let img = BonsaiArt.ledge(index: l.index)
                e.layer.contents = img
                e.layer.bounds = CGRect(x: 0, y: 0, width: Double(img.width) * artScale, height: Double(img.height) * artScale)
                e.key = key
            }
            // The slab's top row sits at the surface; it grows out of the window's side.
            e.layer.setAffineTransform(CGAffineTransform(scaleX: l.side > 0 ? 1 : -1, y: 1))
            e.layer.anchorPoint = CGPoint(x: l.side > 0 ? 0 : 1, y: 7.0 / 10.0)
            e.layer.position = CGPoint(x: pt.x.rounded(), y: pt.y.rounded())
            ledges[s.ownerID] = e
        }
        for (id, e) in ledges where !alive.contains(id) { fadeOut(e.layer); ledges[id] = nil }
    }

    // MARK: Events

    func handle(_ events: [BonsaiEvent]) {
        for e in events {
            switch e {
            case .planted(let project):
                moveBurst.insert(project)
            case .sprouted(let project, let branch):
                guard let p = world.bonsaiPlacements.first(where: { $0.project == project }), carrier(for: p) == nil, branch < p.layout.limbs.count,
                      let root = p.layout.limbs[branch].points.first, let (si, pt) = local(p.base + root * p.scale) else { continue }
                overlay.burst([Effects.dust, Effects.leaf, Effects.sparkle], si: si, at: pt, count: 6, dx: -20...20, dy: 4...30, duration: 0.8)
                if let l = trees[project]?.layer { boing(l) }
            case .grew(let project, let part, let branch):
                guard let p = world.bonsaiPlacements.first(where: { $0.project == project }), carrier(for: p) == nil,
                      let pad = p.layout.pads.first(where: { $0.branch == branch }) ?? p.layout.pads.last,
                      let (si, pt) = local(p.base + pad.center * p.scale) else { continue }
                switch part {
                case "leaf": overlay.burst([Effects.leaf, Effects.leaf2], si: si, at: pt, count: 2, dx: -16...16, dy: -30 ... -6, duration: 1.1)
                case "bloom": overlay.burst([Effects.petal, Effects.sparkle], si: si, at: pt, count: 5, dx: -26...26, dy: -10...30, duration: 1.2, stagger: 0.05)
                default: overlay.burst([Effects.star, Effects.sparkle, Effects.smallStar], si: si, at: pt, count: 7, dx: -24...24, dy: 0...36, duration: 1, stagger: 0.04)
                }
            case .moved(let project, _):
                moveBurst.insert(project)
            case .milestone(let project, let text):
                guard let p = world.bonsaiPlacements.first(where: { $0.project == project }), carrier(for: p) == nil,
                      let (si, pt) = local(p.base + Vec2(0, p.layout.bounds.maxY * p.scale * 0.6)) else { continue }
                overlay.burst([Effects.star, Effects.sparkle, Effects.heart, Effects.petal], si: si, at: pt, count: 18,
                              dx: -p.layout.bounds.w * p.scale * 0.5...p.layout.bounds.w * p.scale * 0.5, dy: -20...80, duration: 1.8, stagger: 0.04)
                overlay.fx.floatText("\(project) · \(text)", si: si, at: CGPoint(x: pt.x, y: pt.y + p.layout.bounds.maxY * p.scale * 0.5 + 16), color: .systemYellow, size: 14, rise: 34, duration: 3.2)
                if let l = trees[project]?.layer { boing(l) }
            }
        }
    }

    // MARK: Clicking

    /// Whether a point is on a tree's pot or in its foliage (tighter than the bounding box).
    func hit(at p: Vec2) -> BonsaiPlacement? {
        for pl in world.bonsaiPlacements.reversed() {
            let L = pl.layout, s = pl.scale
            let lx = (p.x - pl.base.x) / s, ly = (p.y - pl.base.y) / s
            if abs(lx) <= L.potWidth / 2 && ly >= -L.potHeight && ly <= 2 { return pl }
            for pad in L.pads {
                let dx = (lx - pad.center.x) / pad.rx, dy = (ly - pad.center.y) / max(1, pad.ry)
                if dx * dx + dy * dy <= 1.2 { return pl }
            }
        }
        return nil
    }

    /// Clicking a tree: the project's story so far.
    func describe(_ p: BonsaiPlacement) {
        guard let t = world.bonsaiBook[p.project] else { return }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        var parts = ["\(t.project) · \(t.species.name.lowercased()), \(t.form.name)",
                     "\(t.sessions) session\(t.sessions == 1 ? "" : "s")", "\(t.edits) edit\(t.edits == 1 ? "" : "s")"]
        if t.blooms > 0 { parts.append("\(t.blooms) task\(t.blooms == 1 ? "" : "s") finished") }
        if t.fruit > 0 { parts.append("tests passed \(t.fruit)×") }
        if t.repoCommits > 0 { parts.append("\(t.repoCommits) commits in the repo") }
        if t.minutes >= 1 { parts.append(t.minutes < 60 ? "\(Int(t.minutes)) min" : String(format: "%.1f h", t.minutes / 60)) }
        parts.append("planted \(f.string(from: Date(timeIntervalSince1970: t.plantedAt)))")
        let top = p.base + Vec2(0, p.layout.bounds.maxY * p.scale + 18)
        if let (si, pt) = local(top) { overlay.fx.floatText(parts.joined(separator: " · "), si: si, at: pt, color: .systemGreen, size: 13, rise: 36, duration: 4.2) }
        if let l = trees[p.project]?.layer { boing(l) }
    }

    // MARK: Little animations

    private func popIn(_ l: CALayer) {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [0.1, 1.12, 0.96, 1]; a.duration = 0.6
        l.add(a, forKey: "pop")
    }

    private func boing(_ l: CALayer) {
        let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
        a.values = [1, 0.94, 1.04, 0.99, 1]; a.duration = 0.5
        l.add(a, forKey: "boing")
    }

    private func fadeOut(_ l: CALayer) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.5
        fade.isRemovedOnCompletion = false; fade.fillMode = .forwards
        l.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}
