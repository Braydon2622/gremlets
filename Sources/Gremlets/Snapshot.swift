import AppKit
import GremletsCore

/// "Save Village Snapshot": a postcard of your village made from your Claude Code sessions (the buildings, the grove,
/// the mine and whatever the merchant brought, with your Gremlets out front) plus the stats behind it. Saved to
/// ~/Pictures/Gremlets and copied to the clipboard, ready to paste into a post.
enum VillageSnapshot {
    static func make(world: World, species: [String: LoadedSpecies]) -> URL? {
        guard let (image, size) = render(world: world, species: species) else { return nil }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Gremlets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let url = dir.appendingPathComponent("Village \(f.string(from: Date())).png")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
        return url
    }

    /// The postcard itself.
    static func render(world: World, species: [String: LoadedSpecies]) -> (image: CGImage, size: CGSize)? {
        guard let floor = world.groveFloor else { return nil }
        let W = 1600, H = 660
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let night = world.isNight
        // Sky
        let sky = night ? [CGColor(red: 0.07, green: 0.09, blue: 0.22, alpha: 1), CGColor(red: 0.25, green: 0.18, blue: 0.38, alpha: 1)]
                        : [CGColor(red: 0.55, green: 0.78, blue: 0.98, alpha: 1), CGColor(red: 0.96, green: 0.92, blue: 0.82, alpha: 1)]
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        ctx.interpolationQuality = .none
        var r = ArtRNG(s: 5)
        if night {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.9, alpha: 0.9))
            for _ in 0..<90 { ctx.fill(CGRect(x: r.range(0, Double(W)), y: r.range(260, Double(H)), width: 3, height: 3)) }
        } else {
            for _ in 0..<4 {
                let c = WeatherArt.cloud(storm: false)
                ctx.setAlpha(0.8)
                ctx.draw(c, in: CGRect(x: r.range(0, Double(W) - 200), y: r.range(380, Double(H) - 80), width: Double(c.width) * 6, height: Double(c.height) * 6))
                ctx.setAlpha(1)
            }
        }
        // Ground: a strip of meadow terrain.
        let groundY = 110.0
        let ground = IslandArt.body(.meadow, widthPx: W / 3 + 2, seed: 9)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: Int(groundY)))
        ctx.draw(ground, in: CGRect(x: 0, y: groundY - Double(ground.height) * 3, width: Double(ground.width) * 3, height: Double(ground.height) * 3))
        ctx.restoreGState()
        ctx.setFillColor(CGColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: Int(groundY) - 60))

        let k = Double(W - 80) / floor.w
        func X(_ fx: Double) -> Double { 40 + fx * floor.w * k }
        func draw(_ img: CGImage, centerX: Double, width: Double, height: Double) {
            ctx.draw(img, in: CGRect(x: centerX - width / 2, y: groundY, width: width, height: height))
        }
        // Grove plants
        for i in world.grove.plants.indices where world.grove.featured == nil || world.grove.featured == i {
            let p = world.grove.plants[i], sz = world.grove.size(i)
            draw(GroveArt.image(p, size: sz, night: night), centerX: X(p.x), width: sz.x * k, height: sz.y * k)
        }
        // The hanging house with its hammock, up top (the village on the ground is retired on the desktop).
        if !world.villageOn {
            let house = NotchArt.house(lit: night), hm = NotchArt.hammock(widthPx: 20)
            let hx = Double(W) * 0.62, hy = Double(H) - 40 - Double(house.height) * 3
            ctx.setStrokeColor(CGColor(red: 0.54, green: 0.42, blue: 0.29, alpha: 1)); ctx.setLineWidth(2)
            for x in [hx + 6, hx + 40] { ctx.move(to: CGPoint(x: x, y: hy + 48)); ctx.addLine(to: CGPoint(x: x, y: Double(H))) }
            let mx = hx + 46 + 70
            for x in [mx - 30, mx + 30] { ctx.move(to: CGPoint(x: x, y: hy + 14)); ctx.addLine(to: CGPoint(x: x + (x < mx ? -6 : 6), y: Double(H))) }
            ctx.strokePath()
            ctx.draw(house, in: CGRect(x: hx, y: hy, width: Double(house.width) * 3, height: Double(house.height) * 3))
            ctx.draw(hm, in: CGRect(x: mx - 30, y: hy + 6, width: Double(hm.width) * 3, height: Double(hm.height) * 3))
        }
        // Village
        for (n, h) in world.grove.village.enumerated() where world.villageOn {
            let cx = X(h.x)
            if h.biome == "mine" {
                let img = AdventureArt.mine(night: night)
                draw(img, centerX: cx, width: Double(img.width) * 3 * k, height: Double(img.height) * 3 * k)
            } else if h.biome.hasPrefix("item:"), let item = VillageItem(rawValue: String(h.biome.dropFirst(5))) {
                let img = VillageArt.item(item, night: night, frame: 0)
                draw(img, centerX: cx, width: Double(img.width) * 3 * k, height: Double(img.height) * 3 * k)
            } else if let b = Biome(rawValue: h.biome) {
                let stage = BuildArt.overgrowthStage(hours: h.builtAt.map { (Date().timeIntervalSince1970 - $0) / 3600 } ?? 0)
                if let img = BuildArt.image(b, blocks: h.blocks, night: night, overgrowth: stage, seed: UInt64(n * 31 + 7), month: world.month) {
                    draw(img, centerX: cx, width: Double(img.width) * 3 * k, height: Double(img.height) * 3 * k)
                    if let o = h.owner {
                        let pn = OwnerArt.pennant(OwnerArt.color(for: o))
                        ctx.draw(pn, in: CGRect(x: cx - Double(img.width) * 3 * k * 0.25, y: groundY + Double(img.height) * 3 * k - 3, width: 15 * k, height: 15 * k))
                    }
                }
            }
        }
        // The project bonsai, on their nursery brackets up the right-hand side.
        let now = Date().timeIntervalSince1970
        for (k, t) in world.bonsaiBook.trees.sorted(by: { $0.lastSeen > $1.lastSeen }).prefix(4).enumerated() {
            let layout = BonsaiGeometry.layout(t)
            let bx = Double(W) - 150, by = groundY + 60 + Double(k) * 110
            let br = BonsaiArt.bracket(widthPx: 46, hanging: k % 2 == 1)
            ctx.draw(br, in: CGRect(x: bx - 69, y: by - 36, width: Double(br.width) * 3, height: Double(br.height) * 3))
            let fit = min(0.55, 100 / max(1, layout.bounds.h))
            let (img, anchor) = BonsaiArt.image(t, layout: layout, scale: fit, month: world.month, night: night, ageDays: t.ageDays(now: now))
            let wpx = Double(img.width) * 3, hpx = Double(img.height) * 3
            ctx.draw(img, in: CGRect(x: bx - anchor.x * wpx, y: by - anchor.y * hpx, width: wpx, height: hpx))
        }
        // Your Gremlets, out front.
        let out = Array(Set(world.creatures.map(\.species.id))).sorted().prefix(10)
        for (i, id) in out.enumerated() {
            guard let sp = species[id], let img = sp.frames.first else { continue }
            let w = Double(img.width) * sp.info.scale * k, h = Double(img.height) * sp.info.scale * k
            let x = 60 + Double(i) * (Double(W) - 160) / Double(max(1, out.count - 1)) + r.range(-20, 20)
            ctx.draw(img, in: CGRect(x: x - w / 2, y: groundY - 14, width: w, height: h))
        }
        // Words
        let g = world.grove
        let edits = g.village.filter { Biome(rawValue: $0.biome) != nil }.reduce(0) { $0 + $1.blocks }
        let houses = g.village.filter { Biome(rawValue: $0.biome) != nil }.count
        let gems = g.gems.values.reduce(0, +)
        let trees = world.bonsaiBook.trees.count
        let allEdits = edits + world.bonsaiBook.trees.reduce(0) { $0 + $1.edits }
        let stats = [(g.tasks, "Claude task"), (trees, "project tree"), (world.villageOn ? houses : 0, "building"), (allEdits, "file edit"), (gems, "gem")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let ink = night ? NSColor.white : NSColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1)
        NSAttributedString(string: "My Gremlets village", attributes: [.font: NSFont.systemFont(ofSize: 44, weight: .heavy), .foregroundColor: ink])
            .draw(at: CGPoint(x: 44, y: Double(H) - 84))
        NSAttributedString(string: "Built one block at a time by my Claude Code sessions", attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.8)])
            .draw(at: CGPoint(x: 46, y: Double(H) - 120))
        NSAttributedString(string: stats.joined(separator: "  ·  "), attributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.85)])
            .draw(at: CGPoint(x: 46, y: Double(H) - 156))
        NSAttributedString(string: "Gremlets", attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .bold), .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
            .draw(at: CGPoint(x: Double(W) - 120, y: 18))
        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage() else { return nil }
        return (image, CGSize(width: W, height: H))
    }
}
