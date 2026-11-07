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
        let sp = [StoryArt.spirit(frame: 0), StoryArt.gliderLeaf, StoryArt.pot]
        let ctx5 = CGContext(data: nil, width: 300, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx5.setFillColor(CGColor(red: 0.1, green: 0.12, blue: 0.2, alpha: 1)); ctx5.fill(CGRect(x: 0, y: 0, width: 300, height: 80)); ctx5.interpolationQuality = .none
        for (k, im) in sp.enumerated() { ctx5.draw(im, in: CGRect(x: 10 + k * 95, y: 10, width: im.width * 4, height: im.height * 4)) }
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
