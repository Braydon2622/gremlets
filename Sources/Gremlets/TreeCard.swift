import AppKit
import GremletsCore

/// `gremlet card <project>`: a card of one project's bonsai with its story, saved to ~/Pictures/Gremlets and copied,
/// ready to post ("my DesktopPets tree after three weeks of Claude sessions").
enum TreeCard {
    static func make(_ tree: Bonsai, world: World) -> URL? {
        guard let (image, size) = render(tree, world: world) else { return nil }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Gremlets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let safe = tree.project.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent("Tree \(safe) \(f.string(from: Date())).png")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
        return url
    }

    static func render(_ tree: Bonsai, world: World) -> (image: CGImage, size: CGSize)? {
        let W = 1000, H = 620
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let night = world.isNight
        let sky = night ? [CGColor(red: 0.08, green: 0.1, blue: 0.24, alpha: 1), CGColor(red: 0.22, green: 0.16, blue: 0.36, alpha: 1)]
                        : [CGColor(red: 0.93, green: 0.96, blue: 0.99, alpha: 1), CGColor(red: 0.99, green: 0.94, blue: 0.86, alpha: 1)]
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        ctx.interpolationQuality = .none
        // A shelf for the pot.
        let shelfY = 150.0
        let plank = BonsaiArt.bracket(widthPx: 120, hanging: false)
        ctx.draw(plank, in: CGRect(x: 60, y: shelfY - Double(plank.height) * 3 + 6, width: Double(plank.width) * 3, height: Double(plank.height) * 3))
        // The tree, as big as fits in the left two thirds.
        let now = Date().timeIntervalSince1970
        let layout = BonsaiGeometry.layout(tree)
        let (img, anchor) = BonsaiArt.image(tree, layout: layout, scale: 1, month: world.month, night: night, ageDays: tree.ageDays(now: now))
        let mult = Double(max(3, min(9, Int(min(520.0 / Double(img.width), 430.0 / Double(img.height))))))
        let wpx = Double(img.width) * mult, hpx = Double(img.height) * mult
        let bx = 60 + Double(plank.width) * 3 / 2
        ctx.draw(img, in: CGRect(x: bx - anchor.x * wpx, y: shelfY - anchor.y * hpx, width: wpx, height: hpx))
        // The story.
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let ink = night ? NSColor.white : NSColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1)
        let x = 560.0
        func line(_ s: String, _ y: Double, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1) {
            NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink.withAlphaComponent(alpha)]).draw(at: CGPoint(x: x, y: y))
        }
        let planted = DateFormatter.localizedString(from: Date(timeIntervalSince1970: tree.plantedAt), dateStyle: .long, timeStyle: .none)
        line(tree.project, Double(H) - 120, size: 40, weight: .heavy)
        line("\(tree.species.name) bonsai · \(tree.form.name)", Double(H) - 156, size: 20, weight: .semibold, alpha: 0.85)
        line("planted \(planted)", Double(H) - 184, size: 17, weight: .medium, alpha: 0.7)
        var y = Double(H) - 250
        let hours = tree.minutes / 60
        let rows: [(String, String)] = [
            ("\(tree.sessions)", "Claude session\(tree.sessions == 1 ? "" : "s") · a branch each"),
            ("\(tree.edits)", "file edit\(tree.edits == 1 ? "" : "s") · a leaf each"),
            ("\(tree.blooms)", "task\(tree.blooms == 1 ? "" : "s") finished · a flower each"),
            ("\(tree.fruit)", "test run\(tree.fruit == 1 ? "" : "s") passed · golden fruit"),
        ] + (hours >= 0.1 ? [(String(format: "%.1f h", hours), "of Claude working beside it")] : [])
          + (tree.repoCommits > 0 ? [("\(tree.repoCommits)", "commits in the repo so far")] : [])
        for (big, small) in rows {
            NSAttributedString(string: big, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold), .foregroundColor: ink]).draw(at: CGPoint(x: x, y: y))
            NSAttributedString(string: small, attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.75)]).draw(at: CGPoint(x: x + 110, y: y + 8))
            y -= 50
        }
        NSAttributedString(string: "Grown by my Claude Code sessions  ·  Gremlets", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.6)])
            .draw(at: CGPoint(x: x, y: 40))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        return (image, CGSize(width: W, height: H))
    }
}
