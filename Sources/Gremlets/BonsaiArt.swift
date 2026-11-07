import AppKit
import GremletsCore

/// Draws a project's bonsai from its layout: pot, surface roots, a tapering trunk with bark, limbs and twigs, clouds
/// of foliage in the species' colours for the season, blossoms, golden fruit, and the marks of age (moss on the pot,
/// lichen on old bark, silvered deadwood on an old juniper). Also the ivy that creeps along a Claude window while
/// Claude works, the mossy ledges that grow out of its side, and the nursery's bracket shelves.
enum BonsaiArt {
    struct Palette {
        var bark: UInt32, barkLight: UInt32, barkDark: UInt32
        var leaf: UInt32, leafLight: UInt32, leafDark: UInt32
        var bloom: UInt32, bloomLight: UInt32
    }

    static func palette(_ sp: BonsaiSpecies, month: Int) -> Palette {
        let autumn = (9...11).contains(month), spring = (3...5).contains(month)
        switch sp {
        case .pine:
            return Palette(bark: 0x6E5A4A, barkLight: 0x8C7560, barkDark: 0x4A3A2E, leaf: 0x2F6B3A, leafLight: 0x4E9A4A, leafDark: 0x1F4A2A, bloom: 0xC9A24A, bloomLight: 0xF2D37A)
        case .maple:
            let (l, ll, ld): (UInt32, UInt32, UInt32) = autumn ? (0xE0582C, 0xF7B45C, 0xA83A1E) : (0x5DBB46, 0x9BE36A, 0x2F7A2C)
            return Palette(bark: 0x8A8278, barkLight: 0xA59D92, barkDark: 0x5E5850, leaf: l, leafLight: ll, leafDark: ld, bloom: 0xE8574A, bloomLight: 0xFF9A8A)
        case .cherry:
            let (l, ll, ld): (UInt32, UInt32, UInt32) = spring ? (0xF7B6D2, 0xFFE0EF, 0xD6789F) : (0x4FA83A, 0x8BD66A, 0x2F7A2C)
            return Palette(bark: 0x5A3A2A, barkLight: 0x7A5232, barkDark: 0x3A2418, leaf: l, leafLight: ll, leafDark: ld, bloom: 0xFF8FB1, bloomLight: 0xFFE0EF)
        case .juniper:
            return Palette(bark: 0x8A4A3A, barkLight: 0xA8685A, barkDark: 0x5E2E22, leaf: 0x4F8F7A, leafLight: 0x7FBFA8, leafDark: 0x2F5F52, bloom: 0xF2D37A, bloomLight: 0xFFF3C4)
        case .wisteria:
            return Palette(bark: 0x6E6258, barkLight: 0x8E8276, barkDark: 0x4A4038, leaf: 0x5E9E46, leafLight: 0x8BD66A, leafDark: 0x3E7A34, bloom: 0xB98CFF, bloomLight: 0xE0C2FF)
        case .olive:
            return Palette(bark: 0x7A7060, barkLight: 0x9A9080, barkDark: 0x524A3E, leaf: 0x8FA98A, leafLight: 0xC2D4B8, leafDark: 0x5F7A5C, bloom: 0xFFFFFF, bloomLight: 0xFFFFFF)
        }
    }

    static func isWinter(_ m: Int) -> Bool { m == 12 || m <= 2 }

    /// The tree, and where the pot's top-centre (the layout origin) sits in the image, as a fraction of its size.
    static func image(_ b: Bonsai, layout: BonsaiLayout, scale: Double, month: Int, night: Bool, ageDays: Double) -> (image: CGImage, anchor: CGPoint) {
        let k = scale / artScale
        let bounds = layout.bounds
        let w = max(4, Int((bounds.w * k).rounded(.up))), h = max(4, Int((bounds.h * k).rounded(.up)))
        var cv = PixelCanvas(w, h)
        let pal = palette(b.species, month: month)
        let winter = isWinter(month)
        var r = ArtRNG(s: b.seed &+ 9)
        func px(_ p: Vec2) -> (Double, Double) { ((p.x - bounds.minX) * k, (p.y - bounds.minY) * k) }
        func pline(_ a: Vec2, _ c: Vec2, _ col: UInt32, width: Int) {
            let (x0, y0) = px(a), (x1, y1) = px(c)
            cv.line(x0, y0, x1, y1, col, width: max(1, width))
        }

        // Pot, with a ribbon for each round number reached.
        drawPot(&cv, style: b.pot, potW: layout.potWidth * k, potH: layout.potHeight * k, origin: px(.zero), ageDays: ageDays, winter: winter)
        let (ox, oy) = px(.zero)
        let ribbons = min(5, b.milestones.count)
        for n in 0..<ribbons {
            let x = Int(ox - layout.potWidth * k / 2) + 3 + n * 3, y = Int(oy) - Int(layout.potHeight * k) + 2
            let col: UInt32 = [0xE8574A, 0xFFD45E, 0x5FB8FF, 0xB98CFF, 0xFFFFFF][n]
            cv.rect(x, y, 2, 3, col); cv.set(x, y - 1, col)
        }

        // Trunk (behind the limbs), tapering, with a lit side and a shaded side.
        var trunkPixels: [(Int, Int)] = []
        let segs = layout.trunk.count - 1
        for i in 0..<segs {
            let t = Double(i) / Double(segs)
            let thick = max(1, Int((layout.thickness * (1 - 0.7 * t) * k).rounded()))
            pline(layout.trunk[i], layout.trunk[i + 1], pal.bark, width: thick)
        }
        // Bark texture: a light column on the left of the trunk, dark on the right.
        for y in 0..<h { for x in 0..<w where cv.get(x, y) == pal.bark {
            trunkPixels.append((x, y))
            if cv.get(x - 1, y) == nil { cv.set(x, y, pal.barkLight) } else if cv.get(x + 1, y) == nil { cv.set(x, y, pal.barkDark) }
        }}
        // Surface roots over the soil.
        for root in layout.roots { for i in 0..<(root.count - 1) { pline(root[i], root[i + 1], i == 0 ? pal.bark : pal.barkDark, width: i == 0 ? 2 : 1) } }
        // Limbs and twigs.
        for limb in layout.limbs {
            for i in 0..<(limb.points.count - 1) {
                let thick = max(1, Int((limb.thickness * (1 - 0.5 * Double(i) / Double(max(1, limb.points.count - 1))) * k).rounded()))
                pline(limb.points[i], limb.points[i + 1], i == 0 ? pal.bark : pal.barkDark, width: thick)
            }
        }
        // Old juniper: a silvered streak of deadwood up the trunk.
        if b.species == .juniper && ageDays > 14 {
            for i in 0..<segs { pline(layout.trunk[i] + Vec2(2, 0), layout.trunk[i + 1] + Vec2(2, 0), 0xE8E4DA, width: 1) }
        }
        // Lichen on old bark.
        if ageDays > 7 {
            for (x, y) in trunkPixels where r.next() < min(0.18, ageDays / 200) { cv.set(x, y, 0xBFD8B0) }
        }

        // Foliage.
        for pad in layout.pads {
            let (cx, cy) = px(pad.center)
            let rx = pad.rx * k, ry = pad.ry * k
            if winter && b.species.deciduous {
                // Bare: a fan of twigs with snow at the tips.
                for n in 0..<5 {
                    let a = 0.25 + Double(n) * 0.65
                    let ex = cx + cos(a) * rx * 0.9, ey = cy + sin(a) * ry * 1.6
                    cv.line(cx, cy, ex, ey, pal.bark)
                    cv.set(Int(ex), Int(ey) + 1, 0xFFFFFF)
                }
                continue
            }
            cv.blob(cx, cy - ry * 0.25, rx, ry * 0.95, base: pal.leafDark)
            cv.blob(cx, cy, rx, ry, base: pal.leaf, light: pal.leafLight, shade: pal.leafDark)
            cv.blob(cx - rx * 0.28, cy + ry * 0.3, rx * 0.5, ry * 0.5, base: pal.leafLight)
            texture(&cv, b.species, cx: cx, cy: cy, rx: rx, ry: ry, pal: pal, r: &r)
            if winter {
                // Snow along the top of evergreen pads.
                for x in Int(cx - rx)...Int(cx + rx) {
                    let dx = (Double(x) + 0.5 - cx) / rx
                    guard abs(dx) < 1 else { continue }
                    let top = Int(cy + ry * (1 - dx * dx).squareRoot()) - 1
                    if cv.get(x, top) != nil { cv.set(x, top, 0xFFFFFF) }
                }
            }
        }
        // Blossoms (per species) and golden fruit.
        for pad in layout.pads {
            for p in pad.blooms {
                let (x, y) = px(p)
                switch b.species {
                case .pine: cv.rect(Int(x), Int(y) - 1, 2, 3, pal.bloom); cv.set(Int(x), Int(y) + 1, pal.bloomLight)   // little cones
                case .wisteria:   // hanging racemes
                    let len = 3 + Int(r.range(0, 3))
                    for d in 0..<len { cv.set(Int(x), Int(y) - d - 2, d == 0 ? pal.bloomLight : pal.bloom) }
                default: cv.blob(x, y, 1.3, 1.3, base: pal.bloom, light: pal.bloomLight)
                }
            }
            for p in pad.fruit {
                let (x, y) = px(p)
                cv.blob(x, y, 1.7, 1.7, base: night ? 0xFFD84A : 0xF2B33A, light: 0xFFF3A0, shade: 0xB8761A)
                cv.set(Int(x), Int(y) + 2, pal.barkDark)   // its stalk
            }
        }
        cv.outline(0.66)
        let anchor = CGPoint(x: (-bounds.minX * k) / Double(w), y: (-bounds.minY * k) / Double(h))
        return (cv.image, anchor)
    }

    /// Species-specific texture on a foliage pad.
    private static func texture(_ cv: inout PixelCanvas, _ sp: BonsaiSpecies, cx: Double, cy: Double, rx: Double, ry: Double, pal: Palette, r: inout ArtRNG) {
        let x0 = Int(cx - rx), x1 = Int(cx + rx), y0 = Int(cy - ry), y1 = Int(cy + ry)
        guard x1 > x0, y1 > y0 else { return }
        switch sp {
        case .pine:
            // Needle layers: dithered dark rows through the lower half, and a fringe hanging under the edge.
            for y in y0...Int(cy) { for x in x0...x1 where (x + y) % 2 == 0 && cv.get(x, y) == pal.leaf { cv.set(x, y, pal.leafDark) } }
            for x in stride(from: x0 + 1, through: x1 - 1, by: 3) where cv.get(x, y0) != nil && cv.get(x, y0 - 1) == nil { cv.set(x, y0 - 1, pal.leafDark) }
        case .juniper:
            for y in stride(from: y0, through: y1, by: 2) { for x in x0...x1 where cv.get(x, y) == pal.leaf && r.next() < 0.6 { cv.set(x, y, pal.leafDark) } }
        case .olive:
            for _ in 0..<Int(rx * ry / 3) { let x = Int(r.range(Double(x0), Double(x1))), y = Int(r.range(Double(y0), Double(y1))); if cv.get(x, y) == pal.leaf { cv.set(x, y, pal.leafLight) } }
        case .maple, .cherry, .wisteria:
            for _ in 0..<Int(rx * ry / 5) { let x = Int(r.range(Double(x0), Double(x1))), y = Int(r.range(Double(y0), Double(y1))); if cv.get(x, y) == pal.leaf { cv.set(x, y, r.next() < 0.5 ? pal.leafLight : pal.leafDark) } }
        }
    }

    private static func drawPot(_ cv: inout PixelCanvas, style: Int, potW: Double, potH: Double, origin: (Double, Double), ageDays: Double, winter: Bool) {
        let (ox, oy) = origin
        let w = max(6, Int(potW)), hgt = max(4, Int(style == 2 ? potH * 0.6 : potH))
        let x0 = Int(ox - potW / 2), y0 = Int(oy) - hgt
        let (body, light, dark): (UInt32, UInt32, UInt32) = [
            (0x3F6FA8, 0x6F9FD8, 0x2A4A78),   // glazed blue
            (0xA8684A, 0xC9895F, 0x7A4A32),   // unglazed terracotta
            (0x8E8B83, 0xB8B6AE, 0x5E5B55),   // stone tray
            (0x4F9A7A, 0x7FC9A8, 0x2F6B52),   // glazed jade
        ][style % 4]
        for y in 0..<hgt {
            let taper = style == 1 ? 0 : (y < 2 ? 2 - y : 0)          // rounded bottom corners
            let inset = style == 1 ? (y == hgt - 1 ? -1 : 0) : taper     // the terracotta pot has a lip
            cv.rect(x0 + inset, y0 + y, w - inset * 2, 1, y == hgt - 1 ? light : (y == 0 ? dark : body))
        }
        cv.rect(x0 + 1, y0 + 1, 2, hgt - 2, light)          // glaze highlight
        cv.rect(x0 + w - 3, y0 + 1, 2, hgt - 2, dark)       // shaded side
        if style == 0 || style == 3 { for x in stride(from: x0 + 5, to: x0 + w - 5, by: 7) { cv.set(x, y0 + hgt / 2, light) } }   // crackle glints
        // Soil.
        let soilRows = min(2, hgt - 1)
        for y in 0..<soilRows { cv.rect(x0 + 2, y0 + hgt - 1 - y, w - 4, 1, 0x4A3424) }
        for x in stride(from: x0 + 3, to: x0 + w - 3, by: 4) { cv.set(x, y0 + hgt - 1, 0x6B4A30) }
        // Moss gathers on an old pot.
        if ageDays > 2 {
            var r = ArtRNG(s: UInt64(w * 31 + style))
            let cover = min(0.7, ageDays / 40)
            for x in x0..<(x0 + w) where r.next() < cover { cv.set(x, y0 + hgt - 1, r.next() < 0.5 ? 0x5E9E46 : 0x7DBE52) }
            for x in stride(from: x0, to: x0 + w, by: 5) where r.next() < cover * 0.6 { cv.set(x, y0 + hgt - 2, 0x5E9E46); if r.next() < 0.5 { cv.set(x, y0 + hgt - 3, 0x4F8A3A) } }
        }
        if winter { for x in x0..<(x0 + w) where x % 3 != 0 { cv.set(x, y0 + hgt, 0xFFFFFF) } }
    }

    /// A little pot with a sprig, carried overhead to the window.
    static let carriedPot: CGImage = Effects.pixels([
        "...g...",
        "..ggg..",
        "...k...",
        "bbbbbbb",
        ".bbbbb.",
        ".bbbbb.",
        "..bbb..",
        "..bbb..",
    ], ["g": 0x6CC04A, "k": 0x4A3424, "b": 0x3F6FA8])

    /// A nest of twigs with two small birds, for a tree whose session has run an hour.
    static let nest: CGImage = Effects.pixels([
        "..b...b..",
        ".bbb.bbb.",
        "..y...y..",
        "tttttttttt",
        ".ttttttt.",
        "..ttttt..",
    ].map { $0.padding(toLength: 10, withPad: ".", startingAt: 0) }, ["b": 0x5FB8FF, "y": 0xFFC845, "t": 0x8A5A35])

    // MARK: Around a Claude window

    /// Ivy creeping along the top edge of a terminal Claude is working in: a stem with heart leaves, the odd tiny
    /// mushroom and fern. Grows from the pot outward.
    static func ivy(lengthPx: Int, seed: UInt64) -> CGImage {
        let w = max(3, lengthPx), h = 7
        var cv = PixelCanvas(w, h)
        var r = ArtRNG(s: seed &+ 3)
        for x in 0..<w {
            let y = 1 + Int((sin(Double(x) / 5 + Double(seed % 7)) + 1) * 0.6)   // a gently waving stem
            cv.set(x, y, 0x3E7A34)
            if x % 4 == 2 {
                let up = r.next() < 0.7
                let ly = up ? y + 1 : max(0, y - 1)
                let c: UInt32 = r.next() < 0.5 ? 0x5DBB46 : 0x7DBE52
                cv.set(x, ly, c); cv.set(x + 1, ly, c); cv.set(x, ly + (up ? 1 : -1), 0x9BE36A)
            }
            if x % 23 == 11 && x + 3 < w {
                // A tiny mushroom.
                cv.rect(x + 1, 0, 1, 3, 0xEBDDC3)
                cv.rect(x, 3, 3, 1, r.next() < 0.5 ? 0xC4467A : 0xD9855A); cv.set(x + 1, 4, 0xF07AA6)
            }
            if x % 31 == 25 && x + 2 < w {
                // A small fern.
                cv.line(Double(x), 0, Double(x) + 2, 5, 0x4F8A3A)
                cv.set(x + 1, 2, 0x8BD66A); cv.set(x + 2, 3, 0x8BD66A); cv.set(x, 1, 0x8BD66A)
            }
        }
        return cv.image
    }

    /// A mossy ledge growing out of a terminal's side: a stone slab under moss, bracket fungi on its underside.
    static func ledge(index: Int) -> CGImage {
        var cv = PixelCanvas(25, 10)
        var r = ArtRNG(s: UInt64(index + 1) &* 7919)
        // The slab: a stone shelf wedged into the window's side, lighter on top, dark underneath.
        for x in 1..<24 { cv.rect(x, 3, 1, 4, x % 7 == 0 ? 0x6E6B65 : 0x8E8B83); cv.set(x, 6, 0xB8B6AE); cv.set(x, 3, 0x5E5B55) }
        cv.rect(0, 3, 1, 4, 0x5E5B55); cv.rect(24, 4, 1, 2, 0x6E6B65)
        // Moss over the top, spilling down the front.
        for x in 1..<24 where r.next() < 0.85 { cv.set(x, 7, r.next() < 0.5 ? 0x5DBB46 : 0x7DBE52); if r.next() < 0.35 { cv.set(x, 8, 0x9BE36A) }; if r.next() < 0.2 { cv.set(x, 5, 0x4F8A3A) } }
        // Bracket fungi underneath, a fern at the end, two tiny flowers.
        for x in [5, 13, 20] { cv.blob(Double(x), 2.2, 2.6, 1.4, base: 0xD9855A, light: 0xF2B48A, shade: 0xA8582E) }
        cv.line(22, 7, 24, 9, 0x4F8A3A); cv.set(23, 9, 0x8BD66A); cv.set(21, 8, 0x8BD66A)
        cv.set(9, 9, 0xFF6B6B); cv.set(16, 9, 0xFFD45E)
        cv.outline(0.65)
        return cv.image
    }

    /// A bracket shelf for the nursery: a plank on a brace against the wall, ivy trailing underneath.
    static func bracket(widthPx: Int, hanging: Bool) -> CGImage {
        let w = max(10, widthPx), h = 14
        var cv = PixelCanvas(w, h)
        cv.rect(0, h - 3, w, 2, 0xC98B4A); cv.rect(0, h - 1, w, 1, 0xE0A866); cv.rect(0, h - 4, w, 1, 0x8A5A35)
        for x in stride(from: 3, to: w, by: 9) { cv.set(x, h - 2, 0x5E3B22) }   // nails
        cv.line(1, Double(h - 5), Double(w) * 0.42, 2, 0x8A5A35, width: 2)       // the brace
        cv.rect(0, 0, 2, h - 3, 0x7A5232)                                       // the wall mount
        if hanging { for x in stride(from: 6, to: w - 2, by: 11) { for y in stride(from: h - 5, through: max(0, h - 11 + (x % 3)), by: -1) { cv.set(x, y, y % 2 == 0 ? 0x5DBB46 : 0x3E7A34) } } }
        cv.outline(0.7)
        return cv.image
    }
}

/// Overgrowth: the moss that spreads over the whole desktop the longer Claude works (see `World.mossMinutes`).
enum MossArt {
    static let deep: UInt32 = 0x3E7A34, mid: UInt32 = 0x5E9E46, light: UInt32 = 0x8BD66A, pale: UInt32 = 0xB6E28A

    /// A carpet of moss lying along an edge: `lengthPx` long, thicker and with more going on at higher `density`
    /// (0...1): clumps, a few drips hanging over the edge, then flowers, ferns and mushrooms. Its baseline is row 3
    /// (the edge itself); three rows hang below it.
    static func carpet(lengthPx: Int, density: Double, seed: UInt64, night: Bool) -> CGImage {
        let w = max(4, lengthPx), h = 14, base = 3
        var cv = PixelCanvas(w, h)
        var r = ArtRNG(s: seed &* 2654435761 &+ 11)
        let thick = 1.2 + density * 3.2
        var x = 0.0
        while x < Double(w) {
            let rad = r.range(1.6, 2.6) + density * r.range(0.5, 2.0)
            let hgt = thick * r.range(0.6, 1.1)
            cv.blob(x, Double(base) + hgt * 0.45, rad, hgt * 0.62, base: mid, light: light, shade: deep)
            x += rad * r.range(0.9, 1.5)
        }
        cv.hspan(0, w - 1, base, deep)
        for xx in 0..<w {
            // Drips over the edge.
            if r.next() < 0.1 + density * 0.25 {
                let len = 1 + Int(r.range(0, 1 + density * 2.5))
                for k in 1...len { cv.set(xx, base - k, k == len ? light : mid) }
            }
            // Speckles on top.
            if r.next() < 0.18, let top = (base..<h).last(where: { cv.solid(xx, $0) }) { cv.set(xx, top, r.next() < 0.5 ? pale : light) }
        }
        if density > 0.35 {
            for xx in stride(from: Int(r.range(3, 9)), to: w - 3, by: max(5, Int(22 - density * 14))) {
                guard let top = (base..<h).last(where: { cv.solid(xx, $0) }), top + 3 < h else { continue }
                switch Int(r.range(0, 4.99)) {
                case 0, 1:
                    // A flower on a short stem.
                    let petal: UInt32 = [0xFF8FB1, 0xFFE45C, 0xFFFFFF, 0xB98CFF, 0x8FD3FF][Int(r.range(0, 4.99))]
                    cv.set(xx, top + 1, deep); cv.set(xx, top + 2, petal); cv.set(xx - 1, top + 2, petal); cv.set(xx + 1, top + 2, petal); cv.set(xx, top + 3, petal)
                    cv.set(xx, top + 2, 0xFFF3A0)
                case 2:
                    // A mushroom (glowing after dark).
                    cv.vspan(xx, top + 1, top + 2, 0xEBDDC3)
                    let cap: UInt32 = night ? 0x5FE8FF : (r.next() < 0.5 ? 0xC4467A : 0xD9855A)
                    cv.hspan(xx - 1, xx + 1, top + 3, cap); cv.set(xx, top + 4 < h ? top + 4 : top + 3, cap)
                case 3:
                    // A fern frond.
                    cv.line(Double(xx), Double(top), Double(xx) + 2, Double(min(h - 1, top + 5)), deep)
                    cv.set(xx + 1, top + 2, light); cv.set(xx + 2, top + 3, light); cv.set(xx, top + 1, light)
                default:
                    // A tuft of grass.
                    cv.set(xx, top + 1, light); cv.set(xx - 1, top + 2, mid); cv.set(xx + 1, top + 2, light)
                }
            }
        }
        cv.outline(0.8)
        return cv.image
    }

    /// A strand of moss and vine hanging straight down `lengthPx`, swaying leaves either side, a bloom at the tip.
    static func strand(lengthPx: Int, seed: UInt64, bloom: Bool) -> CGImage {
        let h = max(4, lengthPx), w = 7
        var cv = PixelCanvas(w, h)
        var r = ArtRNG(s: seed &* 40503 &+ 5)
        var x = 3.0
        for y in stride(from: h - 1, through: 0, by: -1) {
            if (h - y) % 4 == 0 { x += r.next() < 0.5 ? -0.6 : 0.6; x = x.clamped(2, 4) }
            cv.set(Int(x.rounded()), y, deep)
            if (h - y) % 3 == 1 {
                let side = (h - y) % 6 == 1 ? -1 : 1
                cv.set(Int(x.rounded()) + side, y, r.next() < 0.5 ? mid : light)
                cv.set(Int(x.rounded()) + side * 2, y + 1 < h ? y + 1 : y, light)
            }
        }
        // A thicker mossy start at the top.
        cv.blob(3, Double(h) - 1.5, 3, 1.8, base: mid, light: light, shade: deep)
        if bloom { cv.blob(x, 1.2, 1.4, 1.2, base: 0xFF8FB1, light: 0xFFD6E6) }
        cv.outline(0.85)
        return cv.image
    }
}

extension MossArt {
    /// A platform woven into an edge vine: a mat of moss on a few twisted stems, a little hanging below.
    static func pad(seed: UInt64, night: Bool) -> CGImage {
        let w = Int(MossPad.width / 3), h = 9
        var cv = PixelCanvas(w, h)
        var r = ArtRNG(s: seed &* 7 &+ 3)
        // Twisted stems underneath.
        for x in 0..<w { cv.set(x, 4, (x / 3) % 2 == 0 ? 0x6B4428 : 0x8A5A35); if x % 4 == 1 { cv.set(x, 3, 0x6B4428) } }
        // The mat.
        var x = 0.0
        while x < Double(w) { let rad = r.range(1.8, 2.8); cv.blob(x, 6, rad, 1.8, base: mid, light: light, shade: deep); x += rad * 1.2 }
        cv.hspan(0, w - 1, 5, mid)
        // Drips and a flower or mushroom.
        for xx in stride(from: 1, to: w, by: 3) where r.next() < 0.6 { for k in 0..<Int(r.range(1, 3.9)) { cv.set(xx, 2 - k, k % 2 == 0 ? mid : light) } }
        let fx = Int(r.range(3, Double(w - 3)))
        if r.next() < 0.5 { cv.set(fx, 8, 0xFF8FB1); cv.set(fx - 1, 8, 0xFF8FB1); cv.set(fx + 1, 8, 0xFF8FB1) }
        else { cv.set(fx, 7, 0xEBDDC3); cv.hspan(fx - 1, fx + 1, 8, night ? 0x5FE8FF : 0xC4467A) }
        cv.outline(0.75)
        return cv.image
    }
}
