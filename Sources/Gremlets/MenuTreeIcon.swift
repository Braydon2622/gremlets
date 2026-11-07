import AppKit
import GremletsCore

/// The menu bar icon while a tree grows on a terminal: that tree, eighteen points tall, redrawn as it fills out.
enum MenuTreeIcon {
    private static var cache: (key: String, image: NSImage)?

    static func image(_ t: Bonsai, month: Int) -> NSImage {
        // Redrawn every few edits, not every one.
        let key = "\(t.project)|\(t.edits / 4)|\(t.blooms)|\(t.fruit)|\(t.branches.count)|\(month)"
        if let c = cache, c.key == key { return c.image }
        let layout = BonsaiGeometry.layout(t)
        let bare = BonsaiArt.isWinter(month) && t.species.deciduous
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let b = layout.bounds
            let s = min(18 / max(1, b.w), 13 / max(1, b.h))
            func P(_ v: Vec2) -> CGPoint { CGPoint(x: 10 + (v.x - (b.minX + b.w / 2)) * s, y: 3 + (v.y - b.minY) * s) }
            // Pot
            let pw = max(5, layout.potWidth * s)
            ctx.setFillColor(CGColor(red: 0.36, green: 0.45, blue: 0.62, alpha: 1))
            ctx.fill(CGRect(x: 10 - pw / 2, y: 0.5, width: pw, height: 3))
            // Trunk and limbs
            ctx.setStrokeColor(CGColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1)); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.setLineWidth(max(1.2, layout.thickness * s))
            if let f = layout.trunk.first { ctx.move(to: P(f)); for v in layout.trunk.dropFirst() { ctx.addLine(to: P(v)) } }
            ctx.strokePath()
            ctx.setLineWidth(1)
            for limb in layout.limbs { if let f = limb.points.first { ctx.move(to: P(f)); for v in limb.points.dropFirst() { ctx.addLine(to: P(v)) } } }
            ctx.strokePath()
            // Pads, blossoms, fruit
            if !bare {
                ctx.setFillColor(CGColor(red: 0.37, green: 0.7, blue: 0.3, alpha: 1))
                for pad in layout.pads {
                    let c = P(pad.center), rx = max(1.6, pad.rx * s), ry = max(1.2, pad.ry * s)
                    ctx.fillEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry))
                }
                if t.blooms > 0 {
                    ctx.setFillColor(CGColor(red: 1, green: 0.6, blue: 0.78, alpha: 1))
                    for pad in layout.pads.prefix(t.blooms) { let c = P(pad.center); ctx.fillEllipse(in: CGRect(x: c.x - 0.9, y: c.y - 0.9, width: 1.8, height: 1.8)) }
                }
                if t.fruit > 0 {
                    ctx.setFillColor(CGColor(red: 1, green: 0.78, blue: 0.3, alpha: 1))
                    for pad in layout.pads.suffix(min(3, t.fruit)) { let c = P(pad.center); ctx.fillEllipse(in: CGRect(x: c.x + 1, y: c.y - 1.6, width: 2, height: 2)) }
                }
            }
            return true
        }
        img.isTemplate = false
        cache = (key, img)
        return img
    }
}
