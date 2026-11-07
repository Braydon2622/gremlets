import AppKit
import GremletsCore

/// `gremlet forest`: every project's tree together on one hillside, the biggest in the middle, each with its name and
/// a line of numbers, and a few of your Gremlets sitting in the grass between them. One picture of everything you've
/// worked on with Claude. Saved to ~/Pictures/Gremlets and copied.
enum ForestPoster {
    static func make(world: World, species: [String: LoadedSpecies]) -> URL? {
        guard let (image, size) = render(world: world, species: species) else { return nil }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Gremlets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let url = dir.appendingPathComponent("Forest \(f.string(from: Date())).png")
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
        return url
    }

    static func render(world: World, species: [String: LoadedSpecies]) -> (image: CGImage, size: CGSize)? {
        let trees = world.bonsaiBook.trees.sorted { $0.edits > $1.edits }
        guard !trees.isEmpty else { return nil }
        // Biggest in the middle, then alternating outward.
        var order: [Bonsai] = []
        for (i, t) in trees.enumerated() { if i % 2 == 0 { order.append(t) } else { order.insert(t, at: 0) } }
        let now = Date().timeIntervalSince1970
        let night = world.isNight
        let rendered = order.map { t -> (Bonsai, CGImage, CGPoint) in
            let (img, anchor) = BonsaiArt.image(t, layout: BonsaiGeometry.layout(t), scale: 1, month: world.month, night: night, ageDays: t.ageDays(now: now))
            return (t, img, anchor)
        }
        // Young trees are drawn bigger so a one-session sapling still reads; a whole forest keeps to screen size.
        let tallest = Double(rendered.map { $0.1.height }.max() ?? 1)
        var mult = max(3, min(6, (400 / tallest).rounded(.down)))
        let gap = 70.0
        func totalWidth(_ m: Double) -> Double { rendered.reduce(0) { $0 + Double($1.1.width) * m } + gap * Double(rendered.count + 1) + 80 }
        while mult > 3 && totalWidth(mult) > 2400 { mult -= 1 }
        let W = Int(max(1200, totalWidth(mult))), H = 760
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let sky = night ? [CGColor(red: 0.07, green: 0.09, blue: 0.22, alpha: 1), CGColor(red: 0.24, green: 0.17, blue: 0.38, alpha: 1)]
                        : [CGColor(red: 0.62, green: 0.82, blue: 0.98, alpha: 1), CGColor(red: 0.98, green: 0.95, blue: 0.86, alpha: 1)]
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        ctx.interpolationQuality = .none
        var g = ArtRNG(s: 11)
        if night {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.9, alpha: 0.9))
            for _ in 0..<(W / 10) { ctx.fill(CGRect(x: g.range(0, Double(W)), y: g.range(300, Double(H)), width: 3, height: 3)) }
        } else {
            for _ in 0..<max(3, W / 400) {
                let c = WeatherArt.cloud(storm: false)
                ctx.setAlpha(0.8)
                ctx.draw(c, in: CGRect(x: g.range(0, Double(W) - 200), y: g.range(420, Double(H) - 150), width: Double(c.width) * 6, height: Double(c.height) * 6))
                ctx.setAlpha(1)
            }
        }
        // The hill: pixel soil with a grass top, higher in the middle, with blades, a few flowers and some stones.
        let groundBase = 200.0, cell = 3.0
        func hill(_ x: Double) -> Double { groundBase + 40 * sin(.pi * x / Double(W)) }
        let f = night ? 0.55 : 1.0
        func paint(_ hex: UInt32, _ k: Double = 1) -> CGColor {
            CGColor(red: Double((hex >> 16) & 0xFF) / 255 * k, green: Double((hex >> 8) & 0xFF) / 255 * k, blue: Double(hex & 0xFF) / 255 * k, alpha: 1)
        }
        for x in stride(from: 0.0, to: Double(W), by: cell) {
            let top = (hill(x + 1.5) / cell).rounded(.down) * cell
            ctx.setFillColor(paint(0x8A5A35, f)); ctx.fill(CGRect(x: x, y: 0, width: cell, height: top - 12))
            ctx.setFillColor(paint(0x5DBB46, f)); ctx.fill(CGRect(x: x, y: top - 12, width: cell, height: 12))
            if g.next() < 0.35 { ctx.setFillColor(paint(0x9BE36A, f)); ctx.fill(CGRect(x: x, y: top - 3, width: cell, height: 3)) }
            if g.next() < 0.14 { ctx.setFillColor(paint(0x6B4428, f)); ctx.fill(CGRect(x: x, y: (g.range(0, top - 36) / cell).rounded() * cell, width: cell, height: cell)) }
            if g.next() < 0.09 { ctx.setFillColor(paint(0x5DBB46, f)); ctx.fill(CGRect(x: x, y: top, width: cell, height: cell * (g.next() < 0.5 ? 1 : 2))) }
            if g.next() < 0.03 {
                ctx.setFillColor(paint(0x3E8E3A, f)); ctx.fill(CGRect(x: x, y: top, width: cell, height: cell))
                ctx.setFillColor(paint([0xFF6B6B, 0xFFD45E, 0xFFFFFF, 0xB98CFF][Int(g.range(0, 3.99))], night ? 0.8 : 1)); ctx.fill(CGRect(x: x, y: top + cell, width: cell, height: cell))
            }
        }
        ctx.setFillColor(paint(0x6B4428, f)); ctx.fill(CGRect(x: 0, y: 0, width: Double(W), height: 45))
        for _ in 0..<(W / 90) {
            let sx = (g.range(0, Double(W)) / cell).rounded() * cell, sy = (g.range(12, 100) / cell).rounded() * cell
            ctx.setFillColor(paint(0x7D7A74, f)); ctx.fill(CGRect(x: sx, y: sy, width: cell * 3, height: cell * 2))
            ctx.setFillColor(paint(0x5A5752, f)); ctx.fill(CGRect(x: sx, y: sy, width: cell * 3, height: cell))
        }
        // The trees, and where the gaps between them are.
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        let ink = night ? NSColor.white : NSColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1)
        let widths = rendered.map { Double($0.1.width) * mult }
        var x = (Double(W) - (widths.reduce(0, +) + gap * Double(widths.count - 1))) / 2
        var gaps: [Double] = [x / 2]
        func count(_ k: Int, _ word: String) -> String { "\(k) \(word)\(k == 1 ? "" : "s")" }
        for (t, img, anchor) in rendered {
            let w = Double(img.width) * mult, h = Double(img.height) * mult
            let cx = x + w / 2, by = hill(cx) - 4
            ctx.draw(img, in: CGRect(x: cx - anchor.x * w, y: by - anchor.y * h, width: w, height: h))
            let name = NSAttributedString(string: t.project, attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .heavy), .foregroundColor: NSColor.white])
            name.draw(at: CGPoint(x: cx - name.size().width / 2, y: by - 52))
            var parts = [t.species.name, count(t.sessions, "session"), count(t.edits, "edit"), count(t.blooms, "task")]
            if t.fruit > 0 { parts.append(count(t.fruit, "green test run")) }
            let line = NSAttributedString(string: parts.joined(separator: " · "), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.78)])
            line.draw(at: CGPoint(x: cx - line.size().width / 2, y: by - 72))
            x += w + gap
            gaps.append(x - gap / 2)
        }
        gaps[gaps.count - 1] = (x - gap + Double(W)) / 2
        // A few of your Gremlets, sitting in the grass between the trees.
        let out = Array(Set(world.creatures.map(\.species.id))).sorted()
        var spots = gaps.filter { $0 > 30 && $0 < Double(W) - 30 }
        for (i, id) in out.prefix(min(6, spots.count)).enumerated() {
            guard let sp = species[id], let img = sp.frames.first else { continue }
            let j = (i * 7 + 3) % spots.count
            let sx = spots.remove(at: j)
            let w = Double(img.width) * sp.info.scale * mult / 3, h = Double(img.height) * sp.info.scale * mult / 3
            ctx.draw(img, in: CGRect(x: sx - w / 2, y: hill(sx) - 5, width: w, height: h))
            if spots.isEmpty { break }
        }
        NSAttributedString(string: "Everything I've worked on with Claude Code, as trees", attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: ink])
            .draw(at: CGPoint(x: 44, y: Double(H) - 80))
        NSAttributedString(string: "A branch per session, a leaf per edit, a flower per finished task, golden fruit when tests pass", attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.75)])
            .draw(at: CGPoint(x: 46, y: Double(H) - 112))
        NSAttributedString(string: "Gremlets", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: NSColor.white.withAlphaComponent(0.8)])
            .draw(at: CGPoint(x: Double(W) - 96, y: 14))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        return (image, CGSize(width: W, height: H))
    }
}
