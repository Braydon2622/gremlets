import AppKit
import GremletsCore

/// Developer tool: `Gremlets --render-showcase <folder>` stages a clean desktop scene from the app's real art (a
/// terminal with Claude working, a browser, the moss, a bonsai, the nest hut and leaf swing, Gremlets doing their
/// things) and writes it as PNGs for the portfolio and posts. No real windows or files appear in it.
enum ShowcaseRender {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-showcase"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let species = SpriteLibrary.loadAll()
        for (name, dusk) in [("hero", false), ("hero-dusk", true)] {
            if let img = scene(species: species, dusk: dusk) { write(img, dir.appendingPathComponent("\(name).png")) }
        }
        if let img = propsStrip() { write(img, dir.appendingPathComponent("props.png")) }
        exit(0)
    }

    static let W = 1280.0, H = 720.0, px = 3.0

    static func scene(species: [String: LoadedSpecies], dusk: Bool) -> CGImage? {
        let k = 2.0
        guard let ctx = CGContext(data: nil, width: Int(W * k), height: Int(H * k), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: k, y: k)
        ctx.interpolationQuality = .none
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        // The desktop: a soft forest gradient.
        let top = dusk ? NSColor(red: 0.13, green: 0.16, blue: 0.27, alpha: 1) : NSColor(red: 0.62, green: 0.78, blue: 0.74, alpha: 1)
        let bottom = dusk ? NSColor(red: 0.20, green: 0.28, blue: 0.24, alpha: 1) : NSColor(red: 0.30, green: 0.47, blue: 0.36, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)
        // Distant tree trunks.
        for (x, w) in [(90.0, 60.0), (340, 40), (940, 70), (1170, 46)] {
            ctx.setFillColor(NSColor(white: 0, alpha: dusk ? 0.22 : 0.12).cgColor)
            ctx.fill(CGRect(x: x, y: 0, width: w, height: H))
        }

        // Menu bar with the logo.
        let menuH = 30.0
        ctx.setFillColor(NSColor(white: dusk ? 0.12 : 0.92, alpha: 0.92).cgColor)
        ctx.fill(CGRect(x: 0, y: H - menuH, width: W, height: menuH))
        text(" Terminal    Shell    Edit    View    Window    Help", at: CGPoint(x: 14, y: H - 22), size: 13, color: dusk ? .white : .black, bold: true)
        var r = CGRect(x: 0, y: 0, width: 22, height: 18)
        if let logo = MenuLogo.image(.working).cgImage(forProposedRect: &r, context: nil, hints: nil) {
            ctx.draw(logo, in: CGRect(x: W - 250, y: H - menuH + 6, width: 22, height: 18))
        }
        text("9:41 AM", at: CGPoint(x: W - 90, y: H - 22), size: 13, color: dusk ? .white : .black, bold: false)
        let screenTop = H - menuH
        let floorY = 36.0

        // Windows: a terminal with Claude working (left), a browser (right).
        let term = CGRect(x: 170, y: 120, width: 540, height: 330)
        let browser = CGRect(x: 800, y: 190, width: 420, height: 290)
        window(ctx, browser, title: "Gremlets · braydonhartai.com", dark: false)
        window(ctx, term, title: "my-app — claude", dark: true)
        let lines = ["> make the dashboard load faster", "", "● Reading src/dashboard.tsx", "● Searching for slow queries…",
                     "● Editing src/api/stats.ts", "  + cache the weekly totals", "● Running tests", "  ✓ 42 passed"]
        for (n, l) in lines.enumerated() {
            text(l, at: CGPoint(x: term.minX + 18, y: term.maxY - 56 - Double(n) * 22), size: 14,
                 color: l.hasPrefix("●") ? NSColor(red: 0.85, green: 0.6, blue: 0.4, alpha: 1) : l.contains("✓") ? NSColor(red: 0.5, green: 0.85, blue: 0.5, alpha: 1) : NSColor(white: 0.85, alpha: 1), mono: true)
        }
        // Browser page.
        ctx.setFillColor(NSColor(red: 0.93, green: 0.95, blue: 0.93, alpha: 1).cgColor)
        ctx.fill(CGRect(x: browser.minX + 24, y: browser.minY + 40, width: browser.width - 48, height: browser.height - 130))
        for (n, w) in [0.0, 1.0, 2.0].enumerated() {
            ctx.setFillColor(NSColor(red: [0.78, 0.86, 0.8][n], green: 0.88, blue: [0.8, 0.82, 0.86][n], alpha: 1).cgColor)
            ctx.fill(CGRect(x: browser.minX + 44 + w * 116, y: browser.minY + 64, width: 100, height: 70))
        }
        text("Gremlets", at: CGPoint(x: browser.minX + 44, y: browser.maxY - 120), size: 30, color: NSColor(red: 0.18, green: 0.32, blue: 0.2, alpha: 1), bold: true)
        text("A garden that grows while Claude works.", at: CGPoint(x: browser.minX + 44, y: browser.maxY - 152), size: 15, color: NSColor(white: 0.3, alpha: 1))

        // Moss on the window tops, strands down their sides, and along the floor from both corners.
        for (w, seed) in [(term, 3), (browser, 7)] {
            let lenPx = Int(w.width / px) - 6
            draw(ctx, MossArt.carpet(lengthPx: lenPx, density: 0.85, seed: UInt64(seed), night: dusk), x: w.minX + 9, y: w.maxY - 3 * px)
            for (x, len) in [(w.minX - 2, 46), (w.maxX - 4, 64)] {
                let s = MossArt.strand(lengthPx: len, seed: UInt64(seed + Int(x)), bloom: true)
                draw(ctx, s, x: x - 8, y: w.maxY - Double(s.height) * px)
            }
        }
        for (x0, len) in [(0.0, 100), (W - 300, 100)] {
            draw(ctx, MossArt.carpet(lengthPx: len, density: 0.8, seed: UInt64(x0 + 9), night: dusk), x: x0, y: floorY - 3 * px)
        }

        // The project's bonsai on the terminal, today's win flags, the plan as stepping stones.
        var b = Bonsai(project: "my-app", now: 0)
        b.species = BonsaiSpecies.allCases[1]
        for n in 0..<5 { _ = b.startSession("s\(n)", now: 0) }
        for n in 0..<160 { b.branches[n % b.branches.count].edits += 1 }
        for n in 0..<9 { b.branches[n % b.branches.count].blooms += 1 }
        for n in 0..<3 { b.branches[n % b.branches.count].fruit += 1 }
        let layout = BonsaiGeometry.layout(b)
        let (tree, anchor) = BonsaiArt.image(b, layout: layout, scale: 0.85, month: 6, night: dusk, ageDays: 20)
        let tw = Double(tree.width) * px, th = Double(tree.height) * px
        ctx.draw(tree, in: CGRect(x: term.minX + 80 - anchor.x * tw, y: term.maxY - anchor.y * th, width: tw, height: th))
        for (n, x) in [term.minX + 250, term.minX + 268, term.minX + 286].enumerated() {
            drawScaled(ctx, SproutArt.winFlag(n), x: x, y: term.maxY - 2, scale: 3.2)
        }
        draw(ctx, PlanArt.bridge(total: 5, done: 3), x: term.maxX - 150, y: term.maxY - 2)

        // Gremlets.
        func sprite(_ id: String, _ anim: String = "idle", frame: Int = 0) -> (CGImage, Double)? {
            guard let sp = species[id] else { return nil }
            let a = sp.info.animation(anim)
            let idx = a.frames[min(frame, a.frames.count - 1)]
            guard idx < sp.frames.count else { return nil }
            return (sp.frames[idx], sp.info.scale)
        }
        func gremlet(_ id: String, at p: CGPoint, flip: Bool = false, anim: String = "idle") {
            guard let (img, s) = sprite(id, anim) else { return }
            let w = Double(img.width) * s, h = Double(img.height) * s
            ctx.saveGState()
            if flip { ctx.translateBy(x: p.x * 2, y: 0); ctx.scaleBy(x: -1, y: 1) }
            ctx.draw(img, in: CGRect(x: p.x - w / 2, y: p.y, width: w, height: h))
            ctx.restoreGState()
        }
        func headTop(_ id: String) -> Double { species[id].map { $0.info.headTop } ?? 40 }

        // Claude's Gremlet thinking on the terminal top, with its thought cloud.
        let thinker = CGPoint(x: term.minX + 190, y: term.maxY)
        gremlet("mossfawn", at: thinker, anim: "look")
        drawScaled(ctx, MoodArt.thought(dots: 3), x: thinker.x + 30, y: thinker.y + headTop("mossfawn") + 2, scale: 3.2)
        // A friend holding up a book (Claude is reading a file).
        let reader = CGPoint(x: term.maxX - 200, y: term.maxY)
        gremlet("kindlet", at: reader, flip: true)
        drawScaled(ctx, ToolPropArt.image("book")!, x: reader.x - 16, y: reader.y + headTop("kindlet") * 0.55, scale: 3.2)
        // Seedling helpers on their way along the window top.
        drawScaled(ctx, ToolPropArt.seedling(frame: 0, leaf: false), x: term.maxX - 100, y: term.maxY, scale: 3)
        drawScaled(ctx, ToolPropArt.seedling(frame: 1, leaf: true), x: term.maxX - 62, y: term.maxY, scale: 3)

        // The browser's top: sprouts in the moss, one being watered, a dandelion about to be blown.
        let tabTop = browser.maxY
        for (kind, x) in [(MossSprout.Kind.daisy, browser.minX + 70), (.mushroom, browser.minX + 150), (.berries, browser.maxX - 150), (.dandelion, browser.maxX - 70)] {
            drawScaled(ctx, SproutArt.image(kind, stage: 2, night: dusk), x: x, y: tabTop - 3, scale: px)
        }
        let gardener = CGPoint(x: browser.minX + 112, y: tabTop)
        gremlet("sproutbolt", at: gardener, flip: true, anim: "look")
        drawScaled(ctx, PropArt.wateringCan, x: gardener.x - 4, y: gardener.y + headTop("sproutbolt") - 2, scale: px)
        gremlet("puffling", at: CGPoint(x: browser.maxX - 108, y: tabTop))

        // The nest hut hanging in the top-left corner, the leaf swing in the top-right.
        let nest = TopStructureArt.nestHut(lit: dusk)
        let nestX = 22.0, porchY = screenTop - 132
        draw(ctx, nest, x: nestX - 2 * px, y: porchY - 2 * px)
        vine(ctx, from: CGPoint(x: nestX - 2 * px + 5 * px, y: porchY - 2 * px + 24 * px), to: CGPoint(x: nestX + 8, y: screenTop))
        vine(ctx, from: CGPoint(x: nestX - 2 * px + 17 * px, y: porchY - 2 * px + 24 * px), to: CGPoint(x: nestX + 54, y: screenTop))
        vine(ctx, from: CGPoint(x: nestX - 2 * px + 35 * px, y: porchY + 6 * px), to: CGPoint(x: nestX + 106, y: screenTop))
        gremlet("listenling", at: CGPoint(x: nestX + 82, y: porchY))
        let leaf = TopStructureArt.leafSwing
        let leafX = W - 142.0, leafY = screenTop - 126
        draw(ctx, leaf, x: leafX - 4, y: leafY - 3 * px)
        vine(ctx, from: CGPoint(x: leafX - 4 + 2 * px, y: leafY + 3 * px), to: CGPoint(x: leafX + 10, y: screenTop))
        vine(ctx, from: CGPoint(x: leafX - 4 + 31 * px, y: leafY + 3 * px), to: CGPoint(x: leafX + 84, y: screenTop))
        gremlet("frostmote", at: CGPoint(x: leafX + 50, y: leafY), anim: "sleep")

        // On the floor: a picnic in the moss.
        drawScaled(ctx, SproutArt.picnic, x: 170, y: floorY - 2, scale: 3)
        gremlet("rustle", at: CGPoint(x: 92, y: floorY), flip: false)
        gremlet("gumleaf", at: CGPoint(x: 262, y: floorY), flip: true)

        // A Gremlet waiting on you with a lantern, under the browser.
        let waiter = CGPoint(x: W - 200, y: floorY)
        gremlet("beaconbit", at: waiter)
        let lantern = PropArt.lantern
        drawGlow(ctx, at: CGPoint(x: waiter.x, y: waiter.y + headTop("beaconbit") + 12), radius: 18)
        drawScaled(ctx, lantern, x: waiter.x, y: waiter.y + headTop("beaconbit") + 2, scale: px)

        if dusk {
            for p in [CGPoint(x: term.minX + 120, y: term.maxY + 70), CGPoint(x: term.minX + 330, y: term.maxY + 46), CGPoint(x: browser.minX + 220, y: tabTop + 58),
                      CGPoint(x: browser.maxX - 40, y: tabTop + 80), CGPoint(x: 300, y: floorY + 60)] { drawGlow(ctx, at: p, radius: 8) }
        }
        NSGraphicsContext.current = nil
        return ctx.makeImage()
    }

    /// Everything a Gremlet holds up or sets down, in a row (transparent background).
    static func propsStrip() -> CGImage? {
        let items: [CGImage] = [MoodArt.thought(dots: 3), PropArt.lantern] + ["book", "magnifier", "telescope", "trowel", "clover", "list"].compactMap { ToolPropArt.image($0) }
            + [SproutArt.duck, SproutArt.winFlag(0), ToolPropArt.seedling(frame: 0, leaf: true), ToolPropArt.crown]
        let s = 8.0, gap = 28.0
        let w = items.reduce(gap) { $0 + Double($1.width) * s + gap }, h = Double(items.map(\.height).max() ?? 10) * s + 2 * gap
        guard let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        var x = gap
        for img in items {
            let iw = Double(img.width) * s, ih = Double(img.height) * s
            ctx.draw(img, in: CGRect(x: x, y: (h - ih) / 2, width: iw, height: ih))
            x += iw + gap
        }
        return ctx.makeImage()
    }

    // MARK: Drawing helpers

    static func draw(_ ctx: CGContext, _ img: CGImage, x: Double, y: Double) { drawScaled(ctx, img, x: x + Double(img.width) * px / 2, y: y, scale: px) }

    /// Bottom-centre at (x, y).
    static func drawScaled(_ ctx: CGContext, _ img: CGImage, x: Double, y: Double, scale: Double) {
        let w = Double(img.width) * scale, h = Double(img.height) * scale
        ctx.draw(img, in: CGRect(x: (x - w / 2).rounded(), y: y.rounded(), width: w, height: h))
    }

    static func vine(_ ctx: CGContext, from a: CGPoint, to b: CGPoint) {
        ctx.setStrokeColor(NSColor(red: 0.33, green: 0.58, blue: 0.27, alpha: 1).cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
    }

    static func drawGlow(_ ctx: CGContext, at p: CGPoint, radius: Double) {
        let colors = [NSColor(red: 1, green: 0.95, blue: 0.55, alpha: 0.9).cgColor, NSColor(red: 1, green: 0.9, blue: 0.4, alpha: 0).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
        }
    }

    static func window(_ ctx: CGContext, _ r: CGRect, title: String, dark: Bool) {
        let path = CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor(white: 0, alpha: 0.4).cgColor)
        ctx.setFillColor(dark ? NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1).cgColor : NSColor(white: 0.98, alpha: 1).cgColor)
        ctx.addPath(path); ctx.fillPath()
        ctx.restoreGState()
        ctx.setFillColor(dark ? NSColor(white: 0.2, alpha: 1).cgColor : NSColor(white: 0.9, alpha: 1).cgColor)
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        ctx.fill(CGRect(x: r.minX, y: r.maxY - 34, width: r.width, height: 34))
        ctx.restoreGState()
        for (n, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            ctx.setFillColor(c.cgColor)
            ctx.fillEllipse(in: CGRect(x: r.minX + 14 + Double(n) * 20, y: r.maxY - 23, width: 12, height: 12))
        }
        text(title, at: CGPoint(x: r.midX - Double(title.count) * 3.4, y: r.maxY - 23), size: 13, color: dark ? NSColor(white: 0.8, alpha: 1) : NSColor(white: 0.3, alpha: 1), bold: true)
    }

    static func text(_ s: String, at p: CGPoint, size: Double, color: NSColor, bold: Bool = false, mono: Bool = false) {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        NSString(string: s).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }

    static func write(_ img: CGImage, _ url: URL) {
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
