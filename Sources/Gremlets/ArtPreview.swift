import AppKit
import GremletsCore

/// Developer tool: `Gremlets --render-art <folder>` writes a contact sheet of the procedural art (biome islands,
/// grove plants at every level) and exits. Used to review art changes without waiting for a Gremlet to build one.
enum ArtPreview {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-art"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scale = 3
        // Islands: one row per biome (body + decor + a critter), day and night.
        var rows: [(CGImage, CGImage, CGImage)] = []
        for (n, b) in Biome.allCases.enumerated() {
            rows.append((IslandArt.body(b, widthPx: 59, seed: UInt64(n * 37 + 5)), IslandArt.decor(b, widthPx: 59, seed: UInt64(n * 37 + 5), night: n % 2 == 1), IslandArt.critter(b, frame: 0)))
        }
        let cellW = 59 * scale + 40, cellH = (24 + 30) * scale + 20
        let cols = 3
        let W = cellW * cols, H = cellH * ((rows.count + cols - 1) / cols)
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.interpolationQuality = .none
        for (k, (body, decor, critter)) in rows.enumerated() {
            let cx = (k % cols) * cellW + 20, top = H - (k / cols) * cellH - 10 - 24 * scale
            ctx.draw(decor, in: CGRect(x: cx, y: top, width: decor.width * scale, height: decor.height * scale))
            ctx.draw(body, in: CGRect(x: cx, y: top - body.height * scale, width: body.width * scale, height: body.height * scale))
            ctx.draw(critter, in: CGRect(x: cx + 40 * scale, y: top, width: critter.width * scale, height: critter.height * scale))
        }
        write(ctx.makeImage()!, dir.appendingPathComponent("islands.png"))
        // The full-screen corner stump.
        let st = PodArt.stump
        let ctxS = CGContext(data: nil, width: st.width * 8 + 40, height: st.height * 8 + 40, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxS.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxS.fill(CGRect(x: 0, y: 0, width: ctxS.width, height: ctxS.height))
        ctxS.interpolationQuality = .none
        ctxS.draw(st, in: CGRect(x: 20, y: 20, width: st.width * 8, height: st.height * 8))
        write(ctxS.makeImage()!, dir.appendingPathComponent("stump.png"))
        // The ecosystem: the snail's stride, the critters, the hollow log.
        let ctxE = CGContext(data: nil, width: 1400, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxE.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxE.fill(CGRect(x: 0, y: 0, width: 1400, height: 900))
        ctxE.interpolationQuality = .none
        for f in 0..<6 {
            let img = PropArt.snailBody(frame: f, eyeL: f % 5, eyeR: (f + 2) % 5, tucked: false)
            ctxE.draw(img, in: CGRect(x: 20 + (f % 3) * 450, y: 650 - (f / 3) * 110, width: img.width * 5, height: img.height * 5))
        }
        let tk = PropArt.snailBody(frame: 3, eyeL: 2, eyeR: 2, tucked: true)
        ctxE.draw(tk, in: CGRect(x: 20, y: 420, width: tk.width * 5, height: tk.height * 5))
        var ex = 480
        for kind in Critter.Kind.allCases {
            for f in 0..<(kind == .snail ? 6 : kind == .ladybug ? 4 : 2) {
                let img = EcoArt.critter(kind, frame: f)
                ctxE.draw(img, in: CGRect(x: ex, y: 440, width: img.width * 8, height: img.height * 8))
                ex += img.width * 8 + 14
            }
        }
        let lg = EcoArt.log(month: 6)
        ctxE.draw(lg, in: CGRect(x: 20, y: 40, width: lg.width * 10, height: lg.height * 10))
        let lg2 = EcoArt.log(month: 10)
        ctxE.draw(lg2, in: CGRect(x: 360, y: 40, width: lg2.width * 10, height: lg2.height * 10))
        write(ctxE.makeImage()!, dir.appendingPathComponent("ecosystem.png"))
        // Both rainbows, whole.
        let rb = [PropArt.rainbow, WeatherArt.rainbow]
        let ctxR = CGContext(data: nil, width: 40 * 8 * 2 + 60, height: 21 * 8 + 40, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxR.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxR.fill(CGRect(x: 0, y: 0, width: ctxR.width, height: ctxR.height))
        ctxR.interpolationQuality = .none
        for (k, img) in rb.enumerated() { ctxR.draw(img, in: CGRect(x: 20 + k * (40 * 8 + 20), y: 20, width: img.width * 8, height: img.height * 8)) }
        write(ctxR.makeImage()!, dir.appendingPathComponent("rainbows.png"))
        // The hanging places in the top corners.
        let tops = [TopStructureArt.nestHut(lit: false, stage: 0), TopStructureArt.nestHut(lit: true, stage: 0), TopStructureArt.leafSwing]
        let ctxTop = CGContext(data: nil, width: 36 * 6 * 3 + 80, height: 28 * 6 + 40, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxTop.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxTop.fill(CGRect(x: 0, y: 0, width: ctxTop.width, height: ctxTop.height))
        ctxTop.interpolationQuality = .none
        for (k, img) in tops.enumerated() { ctxTop.draw(img, in: CGRect(x: 20 + k * (36 * 6 + 20), y: 20, width: img.width * 6, height: img.height * 6)) }
        // The menu bar logo, idle / working / waiting, on a light and a dark bar.
        let ctxL = CGContext(data: nil, width: 3 * 22 * 4 + 80, height: 2 * 18 * 4 + 60, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxL.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1)); ctxL.fill(CGRect(x: 0, y: 0, width: ctxL.width, height: ctxL.height / 2))
        ctxL.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)); ctxL.fill(CGRect(x: 0, y: ctxL.height / 2, width: ctxL.width, height: ctxL.height / 2))
        ctxL.interpolationQuality = .none
        for (k, st) in [MenuLogo.State.idle, .working, .waiting].enumerated() {
            var r = CGRect(x: 0, y: 0, width: 22, height: 18)
            if let cg = MenuLogo.image(st).cgImage(forProposedRect: &r, context: nil, hints: nil) {
                for row in 0..<2 { ctxL.draw(cg, in: CGRect(x: 20 + k * (22 * 4 + 20), y: 15 + row * (ctxL.height / 2), width: 22 * 4, height: 18 * 4)) }
            }
        }
        write(ctxL.makeImage()!, dir.appendingPathComponent("menulogo.png"))
        // The web habitat's Home Screen icons (web/icons, for the Terrarium): the menu logo on a sky over a moss strip.
        for size in [180, 192, 512] {
            let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.interpolationQuality = .none
            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.75, green: 0.88, blue: 0.95, alpha: 1), CGColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(sky, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
            let k = Double(size) / 16
            c.setFillColor(CGColor(red: 0.49, green: 0.77, blue: 0.42, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: Double(size), height: k * 3))
            c.setFillColor(CGColor(red: 0.35, green: 0.65, blue: 0.31, alpha: 1)); c.fill(CGRect(x: 0, y: k * 2.4, width: Double(size), height: k * 0.6))
            var r = CGRect(x: 0, y: 0, width: 22, height: 18)
            if let cg = MenuLogo.image(.idle).cgImage(forProposedRect: &r, context: nil, hints: nil) {
                let w = k * 10, h = w * Double(cg.height) / Double(cg.width)
                c.draw(cg, in: CGRect(x: (Double(size) - w) / 2, y: k * 2.6, width: w, height: h))
            }
            write(c.makeImage()!, dir.appendingPathComponent("icon-\(size).png"))
        }
        write(ctxTop.makeImage()!, dir.appendingPathComponent("topcorners.png"))
        // The hanging home at every stage (unlit, then lit with the post), the nest hut, the pantry filling, the bird.
        let ctxH = CGContext(data: nil, width: 1500, height: 820, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxH.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxH.fill(CGRect(x: 0, y: 0, width: 1500, height: 820))
        ctxH.interpolationQuality = .none
        for stage in 0...4 {
            for (r, lit) in [false, true].enumerated() {
                let img = NotchArt.house(lit: lit, month: 6, mail: lit, stage: stage, daisies: lit ? 6 : 2)
                ctxH.draw(img, in: CGRect(x: 20 + stage * 290, y: 470 - r * 230, width: img.width * 6, height: img.height * 6))
            }
        }
        for (k, (lit, stage)) in [(false, 0), (true, 2), (true, 4)].enumerated() {
            let nh = TopStructureArt.nestHut(lit: lit, stage: stage)
            ctxH.draw(nh, in: CGRect(x: 20 + k * 260, y: 20, width: nh.width * 6, height: nh.height * 6))
        }
        let lsw = TopStructureArt.leafSwing
        ctxH.draw(lsw, in: CGRect(x: 800, y: 30, width: lsw.width * 6, height: lsw.height * 6))
        for f in 0...6 {
            let pt = EcoArt.pantry(fill: f)
            ctxH.draw(pt, in: CGRect(x: 800 + f * 70, y: 110, width: pt.width * 6, height: pt.height * 6))
        }
        for f in 0..<4 {
            let b = EcoArt.bird(frame: f)
            ctxH.draw(b, in: CGRect(x: 1080 + f * 100, y: 20, width: b.width * 7, height: b.height * 7))
        }
        // The rain barrel (empty, some, most, brimming) and the basket lift.
        for lv in 0...3 {
            let br = EcoArt.barrel(level: lv, night: false)
            ctxH.draw(br, in: CGRect(x: 20 + lv * 80, y: 700, width: br.width * 6, height: br.height * 6))
        }
        let bk = EcoArt.basket
        ctxH.draw(bk, in: CGRect(x: 360, y: 700, width: bk.width * 6, height: bk.height * 6))
        write(ctxH.makeImage()!, dir.appendingPathComponent("hanging.png"))
        // The nest hut's porch put together as on screen (Porch.swift): the vegetable bed, the barrel, the pantry, the
        // mailbox and the basket; then the bed's stages, the lanterns, the mailbox flag and the postcards card.
        let ctxPorch = CGContext(data: nil, width: 1300, height: 760, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxPorch.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxPorch.fill(CGRect(x: 0, y: 0, width: 1300, height: 760))
        ctxPorch.interpolationQuality = .none
        let k = 6.0, ox = 60.0, oy = 330.0
        /// Draws `img` with its anchor (ax, ay as fractions) at porch-relative points (dx along, dy up from the floor).
        func putPorch(_ img: CGImage, _ dx: Double, _ dy: Double, ax: Double, ay: Double, scale: Double = artScale) {
            let px = 2 + dx / 3, py = 2 + dy / 3, f = scale / 3
            let w = Double(img.width) * f, h = Double(img.height) * f
            ctxPorch.draw(img, in: CGRect(x: ox + (px - w * ax) * k, y: oy + (py - h * ay) * k, width: w * k, height: h * k))
        }
        let nest = TopStructureArt.nestHut(lit: true, stage: 2)
        ctxPorch.draw(nest, in: CGRect(x: ox, y: oy, width: Double(nest.width) * k, height: Double(nest.height) * k))
        let grown = [PatchPlot(crop: .carrot, growth: 1, water: 0.8), PatchPlot(crop: .radish, growth: 0.6, water: 0.8), PatchPlot(crop: .peas, growth: 1, water: 0.8)]
        putPorch(PorchArt.bed(grown), 45, -2, ax: 0.5, ay: 0)
        putPorch(EcoArt.barrel(level: 2, night: false), 76, -1, ax: 0.5, ay: 0)
        putPorch(EcoArt.pantry(fill: 3), 96, -13, ax: 0.5, ay: 1)
        putPorch(PorchArt.mailbox(flag: true, card: true), 8, -10, ax: 0.5, ay: 1)
        putPorch(EcoArt.basket, 58, -18, ax: 0.5, ay: 0)
        // The same hut in winter (snow, the hive, the firefly jar on the barrel) and in autumn (leaves), with the new crops.
        for (n, (leaves, snow)) in [(0, 3), (3, 0)].enumerated() {
            let bx = 300.0 + Double(n) * 260
            ctxPorch.draw(nest, in: CGRect(x: bx, y: oy, width: Double(nest.width) * k, height: Double(nest.height) * k))
            if let ov = PorchArt.season(leaves: leaves, snow: snow) { ctxPorch.draw(ov, in: CGRect(x: bx, y: oy, width: Double(ov.width) * k, height: Double(ov.height) * k)) }
            let friendBed = PorchArt.bed([PatchPlot(crop: .strawberry, growth: 1, water: 0.8), PatchPlot(crop: .pumpkin, growth: 1, water: 0.8), PatchPlot(crop: .tomato, growth: 1, water: 0.8)])
            func at(_ img: CGImage, _ dx: Double, _ dy: Double, ax: Double, ay: Double) {
                let px = 2 + dx / 3, py = 2 + dy / 3, w = Double(img.width), h = Double(img.height)
                ctxPorch.draw(img, in: CGRect(x: bx + (px - w * ax) * k, y: oy + (py - h * ay) * k, width: w * k, height: h * k))
            }
            at(friendBed, 45, -2, ax: 0.5, ay: 0)
            at(EcoArt.barrel(level: 1, night: true), 76, -1, ax: 0.5, ay: 0)
            at(PorchArt.jar(count: 4, frame: 0, night: true), 77, 24, ax: 0.5, ay: 0)
            at(PorchArt.hive, -6, 40, ax: 0.5, ay: 1)
        }
        for (i, what) in ["strawberry", "pumpkin", "tomato", "broom"].enumerated() {
            let img = PorchArt.crop(what)!
            ctxPorch.draw(img, in: CGRect(x: 880 + i * 70, y: 560, width: img.width * 8, height: img.height * 8))
        }
        // The bed through a season: empty, sown, growing, thirsty, ripe.
        let beds: [[PatchPlot]] = [
            [PatchPlot(), PatchPlot(), PatchPlot()],
            [PatchPlot(crop: .carrot, growth: 0.1, water: 0.9), PatchPlot(crop: .radish, growth: 0.1, water: 0.9), PatchPlot(crop: .peas, growth: 0.1, water: 0.9)],
            [PatchPlot(crop: .carrot, growth: 0.6, water: 0.9), PatchPlot(crop: .radish, growth: 0.6, water: 0.9), PatchPlot(crop: .peas, growth: 0.6, water: 0.9)],
            [PatchPlot(crop: .carrot, growth: 0.6, water: 0), PatchPlot(crop: .radish, growth: 0.6, water: 0), PatchPlot(crop: .peas, growth: 0.2, water: 0)],
            [PatchPlot(crop: .carrot, growth: 1, water: 0.3), PatchPlot(crop: .radish, growth: 1, water: 0.3), PatchPlot(crop: .peas, growth: 1, water: 0.3)],
        ]
        for (i, b) in beds.enumerated() {
            let img = PorchArt.bed(b)
            ctxPorch.draw(img, in: CGRect(x: 40 + i * 110, y: 640, width: img.width * 8, height: img.height * 8))
        }
        for (i, what) in ["carrot", "radish", "peas"].enumerated() {
            let img = PorchArt.crop(what)!
            ctxPorch.draw(img, in: CGRect(x: 640 + i * 70, y: 650, width: img.width * 8, height: img.height * 8))
        }
        for (i, lit) in [true, false].enumerated() {
            let img = PorchArt.lantern(lit: lit)
            ctxPorch.draw(img, in: CGRect(x: 900 + i * 90, y: 640, width: img.width * 8, height: img.height * 8))
        }
        for (i, flag) in [true, false].enumerated() {
            let img = PorchArt.mailbox(flag: flag, card: flag)
            ctxPorch.draw(img, in: CGRect(x: 1100 + i * 90, y: 650, width: img.width * 8, height: img.height * 8))
        }
        let now = Date().timeIntervalSince1970
        let cards = [Postcard(project: "PhotoToPart", text: "12 min · 9 edits · tests passing", at: now - 5 * 3600, read: true),
                     Postcard(project: "Gremlets", text: "48 min · 31 edits · 3 tasks done · tests passing · 2 helpers", at: now - 40 * 60),
                     Postcard(project: "SalesCheatCodeLive", text: "6 min · 14 looks around", at: now - 60)]
        if let card = PorchArt.postcards(cards, now: now, scale: 2) { ctxPorch.draw(card, in: CGRect(x: 840, y: 40, width: card.width, height: card.height)) }
        write(ctxPorch.makeImage()!, dir.appendingPathComponent("porch.png"))
        let ctxZ = CGContext(data: nil, width: 1240, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxZ.setFillColor(CGColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1)); ctxZ.fill(CGRect(x: 0, y: 0, width: 1240, height: 400))
        ctxZ.interpolationQuality = .none
        for (k, (lit, st)) in [(false, 0), (true, 0), (true, 4)].enumerated() {
            let img = NotchArt.house(lit: lit, month: 6, mail: st == 0 && lit, stage: st, daisies: 4)
            ctxZ.draw(img, in: CGRect(x: 20 + k * 410, y: 20, width: img.width * 12, height: img.height * 12))
        }
        write(ctxZ.makeImage()!, dir.appendingPathComponent("house_zoom.png"))
        // Sprouts: each kind at each stage, day then night.
        let ctxP = CGContext(data: nil, width: 4 * 3 * 9 * 6 + 40, height: 2 * 11 * 6 + 40, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxP.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxP.fill(CGRect(x: 0, y: 0, width: ctxP.width, height: ctxP.height))
        ctxP.interpolationQuality = .none
        for (k, kind) in MossSprout.Kind.allCases.enumerated() {
            for stage in 0..<3 {
                for (r, night) in [false, true].enumerated() {
                    ctxP.draw(SproutArt.image(kind, stage: stage, night: night), in: CGRect(x: 20 + (k * 3 + stage) * 54, y: 20 + (1 - r) * 66, width: 54, height: 66))
                }
            }
        }
        write(ctxP.makeImage()!, dir.appendingPathComponent("sprouts.png"))
        
        // Bonsai: every species, from a seedling to a venerable tree, plus autumn and winter at full growth.
        let stages: [(edits: Int, sessions: Int, blooms: Int, fruit: Int)] = [(0, 1, 0, 0), (8, 2, 1, 0), (40, 4, 4, 1), (150, 7, 9, 3), (500, 12, 16, 7)]
        let bW = 390, bH = 270
        let bcols = stages.count + 2
        let ctxB = CGContext(data: nil, width: bW * bcols, height: bH * BonsaiSpecies.allCases.count, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxB.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxB.fill(CGRect(x: 0, y: 0, width: bW * bcols, height: bH * BonsaiSpecies.allCases.count))
        ctxB.interpolationQuality = .none
        for (row, sp) in BonsaiSpecies.allCases.enumerated() {
            for col in 0..<bcols {
                let st = stages[min(col, stages.count - 1)]
                var b = Bonsai(project: "preview-\(sp.rawValue)", now: 0)
                b.species = sp
                b.form = BonsaiForm.allCases[(row + col) % BonsaiForm.allCases.count]
                for n in 0..<st.sessions { _ = b.startSession("s\(n)", now: 0) }
                for n in 0..<st.edits { b.branches[n % b.branches.count].edits += 1 }
                for n in 0..<st.blooms { b.branches[n % b.branches.count].blooms += 1 }
                for n in 0..<st.fruit { b.branches[n % b.branches.count].fruit += 1 }
                let layout = BonsaiGeometry.layout(b)
                let month = col == stages.count ? 10 : col == stages.count + 1 ? 1 : 6
                let fit = min(1, Double(bW - 20) / (layout.bounds.w * 1.0), Double(bH - 40) / (layout.bounds.h * 1.0))
                let (img, anchor) = BonsaiArt.image(b, layout: layout, scale: fit, month: month, night: col % 2 == 1, ageDays: Double(col) * 6)
                let wpx = Double(img.width) * artScale, hpx = Double(img.height) * artScale
                let ox = Double(col * bW + bW / 2), oy = Double((BonsaiSpecies.allCases.count - 1 - row) * bH + 30)
                ctxB.setFillColor(CGColor(red: 0.3, green: 0.32, blue: 0.4, alpha: 1)); ctxB.fill(CGRect(x: col * bW + 20, y: Int(oy) - 4, width: bW - 40, height: 4))
                ctxB.draw(img, in: CGRect(x: ox - anchor.x * wpx, y: oy - anchor.y * hpx, width: wpx, height: hpx))
            }
        }
        write(ctxB.makeImage()!, dir.appendingPathComponent("bonsai.png"))
        // Ivy, ledge, bracket.
        let ctxI = CGContext(data: nil, width: 900, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxI.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxI.fill(CGRect(x: 0, y: 0, width: 900, height: 120)); ctxI.interpolationQuality = .none
        let ivy = BonsaiArt.ivy(lengthPx: 120, seed: 3); ctxI.draw(ivy, in: CGRect(x: 10, y: 80, width: ivy.width * 3, height: ivy.height * 3))
        let ledge = BonsaiArt.ledge(index: 0); ctxI.draw(ledge, in: CGRect(x: 10, y: 20, width: ledge.width * 3, height: ledge.height * 3))
        let br = BonsaiArt.bracket(widthPx: 46, hanging: true); ctxI.draw(br, in: CGRect(x: 120, y: 10, width: br.width * 3, height: br.height * 3))
        write(ctxI.makeImage()!, dir.appendingPathComponent("terminal.png"))
        // Buildings at 25%, 60% and 100%, day and night, one row per biome.
        let bw = 140, bh = 150
        let ctx3 = CGContext(data: nil, width: bw * 4, height: bh * Biome.allCases.count, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx3.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctx3.fill(CGRect(x: 0, y: 0, width: bw * 4, height: bh * Biome.allCases.count))
        ctx3.interpolationQuality = .none
        for (r, b) in Biome.allCases.enumerated() {
            let total = BuildArt.cells(b).count
            for (k, (frac, night)) in [(0.25, false), (0.6, false), (1.0, false), (1.0, true)].enumerated() {
                guard let img = BuildArt.image(b, blocks: Int(Double(total) * frac), night: night) else { continue }
                ctx3.draw(img, in: CGRect(x: k * bw + 10, y: (Biome.allCases.count - 1 - r) * bh + 10, width: img.width * 3, height: img.height * 3))
            }
        }
        write(ctx3.makeImage()!, dir.appendingPathComponent("builds.png"))
        // Overgrowth stages 0...4 for a few biomes.
        let ctx4 = CGContext(data: nil, width: bw * 5, height: bh * 3, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx4.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctx4.fill(CGRect(x: 0, y: 0, width: bw * 5, height: bh * 3))
        ctx4.interpolationQuality = .none
        for (r, b) in [Biome.meadow, .desert, .snow].enumerated() {
            for st in 0...4 {
                guard let img = BuildArt.image(b, blocks: 99, night: false, overgrowth: st, seed: 3) else { continue }
                ctx4.draw(img, in: CGRect(x: st * bw + 10, y: (2 - r) * bh + 10, width: img.width * 3, height: img.height * 3))
            }
        }
        write(ctx4.makeImage()!, dir.appendingPathComponent("overgrowth.png"))
        // Weather: snow caps at four depths, the snow-Gremlet's stages, the rain leaf and a splash (all at 4x).
        let ctxW = CGContext(data: nil, width: 900, height: 420, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxW.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxW.fill(CGRect(x: 0, y: 0, width: 900, height: 420))
        ctxW.interpolationQuality = .none
        for (i, d) in [0.15, 0.4, 0.7, 1.0].enumerated() {
            let img = ClimateArt.cap(lengthPx: 100, depth: d, seed: UInt64(i + 1))
            ctxW.setFillColor(CGColor(red: 0.55, green: 0.58, blue: 0.66, alpha: 1)); ctxW.fill(CGRect(x: 20, y: 400 - (i + 1) * 60 + 12, width: 400, height: 4))
            ctxW.draw(img, in: CGRect(x: 20, y: 400 - (i + 1) * 60, width: img.width * 4, height: img.height * 4))
        }
        for st in 0...3 {
            let img = ClimateArt.snowman(stage: st, seed: 5)
            ctxW.draw(img, in: CGRect(x: 460 + st * 110, y: 270, width: img.width * 5, height: img.height * 5))
        }
        ctxW.draw(ClimateArt.leafUmbrella, in: CGRect(x: 460, y: 100, width: 25 * 7, height: 15 * 7))
        ctxW.draw(ClimateArt.splash, in: CGRect(x: 660, y: 140, width: 7 * 10, height: 4 * 10))
        for (i, month) in [4, 7, 10, 1].enumerated() {
            let h = NotchArt.house(lit: i % 2 == 1, month: month, mail: i == 2)
            ctxW.draw(h, in: CGRect(x: 10 + i * 150, y: 10, width: h.width * 5, height: h.height * 5))
        }
        let hm = NotchArt.hammock(widthPx: 20, lights: true)
        ctxW.draw(hm, in: CGRect(x: 620, y: 40, width: hm.width * 6, height: hm.height * 6))
        write(ctxW.makeImage()!, dir.appendingPathComponent("weather.png"))
        // The shelf trees: four seeds at two heights, summer and autumn, the last one mirrored, each with its shelf.
        let tW = PropArt.treeWidthPx * 3 + 30, tH = 120 * 3 + 20
        let ctxT = CGContext(data: nil, width: tW * 5, height: tH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctxT.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctxT.fill(CGRect(x: 0, y: 0, width: tW * 5, height: tH)); ctxT.interpolationQuality = .none
        for (k, (seed, shelfPx, month, mirror)) in [(UInt64(3), 70, 6, false), (11, 100, 6, false), (29, 55, 10, false), (47, 90, 4, false), (5, 80, 6, true)].enumerated() {
            let img = PropArt.tree(heightPx: shelfPx + 14, shelfPx: shelfPx, seed: seed, month: month, mirror: mirror)
            let x = k * tW + 10
            ctxT.draw(img, in: CGRect(x: x, y: 10, width: img.width * 3, height: img.height * 3))
            let shelf = PropArt.shelf(k == 1 || k == 4 ? .treehouse : .branch, widthPx: 59)
            let trunkX = Double(x) + Double(img.width * 3) * (mirror ? 1 - PropArt.treeAnchorX : PropArt.treeAnchorX)
            let sx = mirror ? trunkX - 30 : trunkX + 30 - Double(shelf.width * 3)
            ctxT.draw(shelf, in: CGRect(x: sx, y: Double(10 + shelfPx * 3 - shelf.height * 3), width: Double(shelf.width * 3), height: Double(shelf.height * 3)))
            if k == 1 || k == 4 { ctxT.draw(PropArt.cabin, in: CGRect(x: trunkX + (mirror ? 4 : -4) - Double(PropArt.cabin.width * 3) / 2, y: Double(10 + shelfPx * 3), width: Double(PropArt.cabin.width * 3), height: Double(PropArt.cabin.height * 3))) }
        }
        write(ctxT.makeImage()!, dir.appendingPathComponent("trees.png"))
        let sp = [StoryArt.spirit(frame: 0), StoryArt.gliderLeaf, StoryArt.pot, AdventureArt.mine(night: false), AdventureArt.ferry(frame: 0), AdventureArt.lantern, AdventureArt.gem(.amethyst), AdventureArt.gem(.starstone), VillageArt.merchant(frame: 0)] + VillageItem.allCases.map { VillageArt.item($0, night: true, frame: 0) }
        let ctx5 = CGContext(data: nil, width: 1700, height: 170, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx5.setFillColor(CGColor(red: 0.1, green: 0.12, blue: 0.2, alpha: 1)); ctx5.fill(CGRect(x: 0, y: 0, width: 1700, height: 170)); ctx5.interpolationQuality = .none
        var cx = 10; for im in sp { ctx5.draw(im, in: CGRect(x: cx, y: 10, width: im.width * 3, height: im.height * 3)); cx += im.width * 3 + 20 }
        write(ctx5.makeImage()!, dir.appendingPathComponent("story.png"))
        // Grove plants, levels 1...5.
        let g = Grove()
        var plants: [GrovePlant] = []
        for k in GroveKind.allCases { for lv in 1...5 { var p = GrovePlant(kind: k, x: 0); p.sparks = lv == 1 ? 0 : GrovePlant.thresholds[lv - 2] * k.cost; p.berries = lv * 2; plants.append(p) } }
        _ = g
        let pw = 300, ph = 340
        let ctx2 = CGContext(data: nil, width: pw * 5, height: ph * GroveKind.allCases.count, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx2.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)); ctx2.fill(CGRect(x: 0, y: 0, width: pw * 5, height: ph * GroveKind.allCases.count))
        ctx2.interpolationQuality = .none
        for (n, p) in plants.enumerated() {
            let s = p.scale
            let size: Vec2
            switch p.kind {
            case .bouncecap: size = Vec2(54 * s, 46 * s)
            case .skyvine: size = Vec2(60 * s, 110 * s)
            case .lanternbloom: size = Vec2(34 * s, 56 * s)
            case .sunberry: size = Vec2(52 * s, 30 * s)
            case .snapjaw: size = Vec2(40 * s, 44 * s)
            case .wishwillow: size = Vec2(90 * s, 96 * s)
            case .leafpile: size = Vec2(60, 24)
            case .puffball: size = Vec2(30, 48)
            }
            let img = GroveArt.image(p, size: size, night: false)
            let col = n % 5, row = n / 5
            let k = min(1.0, Double(ph - 10) / size.y, Double(pw - 10) / size.x)
            ctx2.draw(img, in: CGRect(x: Double(col * pw + 5), y: Double((GroveKind.allCases.count - 1 - row) * ph + 5), width: size.x * k, height: size.y * k))
        }
        write(ctx2.makeImage()!, dir.appendingPathComponent("grove.png"))
        exit(0)
    }

    static func write(_ img: CGImage, _ url: URL) {
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
