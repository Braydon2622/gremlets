import AppKit
import GremletsCore

/// Pixel art for the local weather (see Weather.swift): snow lying along an edge, a snow-Gremlet in four stages, the leaf a
/// Gremlet holds over its head in the rain, and a raindrop's splash.
enum ClimateArt {
    static let snow: UInt32 = 0xF2F6FD, snowLight: UInt32 = 0xFFFFFF, snowShade: UInt32 = 0xC6D4EA, ice: UInt32 = 0xBFE3F7

    /// Snow lying along an edge, `lengthPx` long: lumpy and soft, thicker with `depth` (0...1), with icicles hanging
    /// below the edge once it's deep. Its baseline is row 3 (the edge); three rows hang below.
    static func cap(lengthPx: Int, depth: Double, seed: UInt64) -> CGImage {
        let w = max(4, lengthPx), h = 16, base = 3
        var cv = PixelCanvas(w, h)
        var r = ArtRNG(s: seed &* 1103515245 &+ 12345)
        let thick = 1.0 + depth * 8.5
        // A rolling height profile: long soft swells, rounded off at the ends like snow slumping off the edge.
        let waves = (0..<3).map { _ in (r.range(0.04, 0.12), r.range(0, 6.3), r.range(0.15, 0.35)) }
        var top = [Double](repeating: 0, count: w)
        for x in 0..<w {
            var v = 1.0
            for (f, ph, a) in waves { v += sin(Double(x) * f + ph) * a }
            let end = min(Double(x) + 0.5, Double(w) - Double(x) - 0.5)
            let round = min(1, (end / max(3, thick * 1.4)).squareRoot())
            top[x] = Double(base) + max(0.6, thick * v * 0.72 * round)
        }
        for x in 0..<w {
            let t = Int(top[x].rounded())
            for y in (base - 1)...max(base, t) {
                let fromTop = Double(t - y)
                let slope = x + 1 < w ? top[x + 1] - top[x] : 0
                var c = snow
                if fromTop < 1 { c = slope > 0.15 ? snow : snowLight }
                else if y <= base { c = snowShade }
                else if fromTop > thick * 0.55 && (x / 2 + y) % 3 == 0 { c = 0xE3EBF8 }
                cv.set(x, y, c)
            }
        }
        // Shadowed hollows under the overhang at the ends, icicles once it's deep, glints on top.
        for xx in 0..<w {
            if depth > 0.4, r.next() < 0.03 + depth * 0.07 {
                let len = 1 + Int(r.range(0, 1.5 + depth * 2))
                for k in 1...len { cv.set(xx, base - 1 - k, k == len ? snowLight : ice) }
            }
            if r.next() < 0.05 { cv.set(xx, Int(top[xx].rounded()), 0xDDF3FF) }
        }
        cv.outline(0.86)
        return cv.image
    }

    /// A snow-Gremlet: a big ball, a smaller one, a head with two little round ears, then pebble eyes, a smile, twig
    /// arms and a sprig on top when it's finished (`stage` 3).
    static func snowman(stage: Int, seed: UInt64) -> CGImage {
        var cv = PixelCanvas(21, 25)
        var r = ArtRNG(s: seed &* 7919 &+ 1)
        let lean = r.range(-0.5, 0.5)
        let bx = 10.5, mx = 10.5 + lean * 0.5, hx = 10.5 + lean
        func ball(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
            cv.blob(x, y, rx, ry, base: snow, light: snowLight, shade: snowShade)
        }
        ball(bx, 5.0, 6.4, 5.0)
        // A few lumps of packed snow on the big ball.
        cv.set(Int(bx) - 3, 3, snowShade); cv.set(Int(bx) + 2, 2, snowShade); cv.set(Int(bx) + 4, 5, 0xE3EBF8)
        if stage >= 1 { ball(mx, 11.8, 4.8, 3.9) }
        if stage >= 2 {
            ball(hx - 2.7, 20.6, 1.5, 1.4)    // ears
            ball(hx + 2.7, 20.6, 1.5, 1.4)
            ball(hx, 17.6, 4.0, 3.4)
        }
        if stage >= 3 {
            let ix = Int(hx.rounded())
            let pebble: UInt32 = 0x3A3540
            cv.set(ix - 2, 18, pebble); cv.set(ix + 1, 18, pebble)
            cv.set(ix - 2, 19, 0x5A5560); cv.set(ix + 1, 19, 0x5A5560)
            cv.set(ix - 1, 16, 0x8A6A7A); cv.set(ix, 16, 0x8A6A7A)
            cv.set(ix - 3, 17, 0xF4B6C4); cv.set(ix + 2, 17, 0xF4B6C4)
            // Twig arms, one waving.
            let twig: UInt32 = 0x6B4A2E
            cv.line(6.0, 12.2, 2.2, 14.6, twig); cv.set(1, 15, twig); cv.set(2, 16, twig); cv.set(1, 13, twig)
            cv.line(15.0, 12.4, 18.6, 16.2, twig); cv.set(19, 17, twig); cv.set(18, 18, twig); cv.set(20, 16, twig)
            // A sprig on top.
            cv.set(ix, 21, 0x4E8B3A); cv.set(ix, 22, 0x4E8B3A); cv.set(ix - 1, 23, 0x7CC55F); cv.set(ix + 1, 23, 0x8BD66A); cv.set(ix + 1, 24, 0x7CC55F)
            // Pebble buttons.
            let px = Int(mx.rounded())
            cv.set(px, 13, pebble); cv.set(px, 11, pebble)
        }
        cv.outline(0.8)
        return cv.image
    }

    /// A broad leaf held up like an umbrella by its stem, curving over and drooping to a point on the far side, with
    /// a midrib, veins and a lighter upper face. Faces right.
    static let leafUmbrella: CGImage = {
        let w = 25, h = 15
        var cv = PixelCanvas(w, h)
        let deep: UInt32 = 0x3E7A34, mid: UInt32 = 0x5E9E46, light: UInt32 = 0x7CC55F, pale: UInt32 = 0xA9DC82
        var spine = [Double](repeating: 0, count: w)
        for x in 0..<w {
            let t = Double(x) / Double(w - 1)
            // The midline arches up, then the tip droops.
            spine[x] = 8.4 + sin(t * .pi * 0.92) * 3.2 - max(0, t - 0.78) * 16
            // Width: a rounded lobe at the back, widest a third of the way, tapering to a point.
            let half = (t < 0.33 ? (t / 0.33).squareRoot() : (1 - (t - 0.33) / 0.67)) * 3.4 + 0.4
            let lo = Int((spine[x] - half).rounded()), hi = Int((spine[x] + half * 0.8).rounded())
            for y in lo...hi {
                let up = Double(y) - spine[x]
                cv.set(x, y, up > half * 0.35 ? light : (up < -half * 0.45 ? deep : mid))
            }
            // A slightly ragged edge.
            if x % 4 == 2 { cv.set(x, hi + 1, mid) }
        }
        // Midrib and veins sweeping toward the tip.
        for x in 1..<(w - 2) { cv.set(x, Int(spine[x].rounded()), deep) }
        for vx in stride(from: 3, to: w - 5, by: 4) {
            let y0 = spine[vx]
            cv.line(Double(vx), y0, Double(vx) + 2.2, y0 + 2.6, deep)
            cv.line(Double(vx), y0, Double(vx) + 2.0, y0 - 2.2, deep)
        }
        for (x, dy) in [(6, 2.4), (12, 2.6), (17, 1.8)] { cv.set(x, Int((spine[x] + dy).rounded()), pale) }
        // The stem, curving down to the hand.
        let stem: UInt32 = 0x6B8A3A
        cv.line(9, spine[9], 9.6, 4, stem); cv.vspan(10, 0, 4, stem)
        cv.outline(0.7)
        return cv.image
    }()

    /// A raindrop hitting a surface: a little crown.
    static let splash: CGImage = {
        var cv = PixelCanvas(7, 4)
        let c: UInt32 = 0xCFE6FA, d: UInt32 = 0x9CC4EA
        cv.hspan(2, 4, 0, d); cv.set(1, 1, c); cv.set(5, 1, c); cv.set(0, 2, c); cv.set(6, 2, c); cv.set(3, 2, c); cv.set(3, 3, c)
        return cv.image
    }()
}

/// The codebase castle (see Castle.swift): a small storybook castle. Cream stone towers with pointed roofs in the
/// colour of each folder's main language, the keep in the middle with an arched door, a flat lookout and a flag.
enum CastleArt {
    static func color(_ lang: String) -> UInt32 {
        switch lang {
        case "swift": return 0xE8743E
        case "js": return 0xE9C94A
        case "ts": return 0x4F86CF
        case "py": return 0x5A82B8
        case "rb": return 0xC2414A
        case "go": return 0x5BBFD6
        case "rust": return 0xB8794C
        case "jvm": return 0xD9823A
        case "c": return 0x7F8DA3
        case "html": return 0xDE6A45
        case "css": return 0x9670CF
        case "docs": return 0x8FB8A8
        case "data": return 0x7DBB76
        case "shell": return 0x6E9F68
        case "sol": return 0x8E8CAE
        case "media": return 0xDB8FAE
        default: return 0x9DB3C9
        }
    }

    /// The whole castle at art scale (3 points per pixel before the placement's scale).
    static func image(_ c: Castle) -> CGImage {
        let px = { (v: Double) in max(1, Int((v / 3).rounded())) }
        let w = max(4, px(c.totalWidth)), h = px(c.tallest) + 2
        var cv = PixelCanvas(w, h)
        let stone: UInt32 = 0xEFE6D2, stoneLight: UInt32 = 0xFBF5E8, stoneShade: UInt32 = 0xD3C6AA, line: UInt32 = 0xE0D4BA
        func roofColour(_ t: CastleTower) -> UInt32 {
            let main = t.mix.filter { !["docs", "data", "media"].contains($0.key) }.max { $0.value < $1.value }?.key ?? t.mainLanguage
            return color(main)
        }
        // Low curtain walls joining the towers.
        for i in c.towers.indices.dropLast() {
            let a = px(c.minX(i) + c.width(i)) - 1, b = px(c.minX(i + 1))
            let wh = px(min(c.height(i), c.height(i + 1)) * 0.42)
            cv.rect(a, 0, b - a + 1, wh, stoneShade)
            for x in stride(from: a, through: b, by: 2) { cv.set(x, wh, stoneShade) }
        }
        for (i, t) in c.towers.enumerated() {
            let x0 = px(c.minX(i)), tw = px(c.width(i)), x1 = x0 + tw - 1, th = px(c.height(i))
            // Smooth stone: lit on the left, shaded on the right, a few faint courses.
            for y in 0..<th { for x in x0...x1 {
                cv.set(x, y, x == x0 ? stoneLight : (x >= x1 - 1 ? stoneShade : (y % 4 == 3 && (x + y / 4) % 3 != 0 ? line : stone)))
            } }
            let mid = (x0 + x1) / 2
            if t.isKeep {
                // Arched door, two windows, a flat lookout with crenellations and a flag.
                cv.rect(mid - 1, 0, 3, 4, 0x6B4428); cv.set(mid, 4, 0x6B4428); cv.set(mid + 1, 2, 0xE8C060)
                for wx in [x0 + 2, x1 - 2] where th > 9 { cv.set(wx, th - 4, 0x5B4A6E); cv.set(wx, th - 5, 0x5B4A6E) }
                for x in stride(from: x0, through: x1, by: 2) { cv.set(x, th, stone); cv.set(x, th + 1, stoneShade) }
                cv.vspan(mid, th, th + 3, 0x6B4428)
                let flag = roofColour(t)
                cv.rect(mid + 1, th + 2, 3, 2, flag); cv.set(mid + 4, th + 3, flag)
            } else {
                // A round window, then a pointed roof in the folder's colour.
                if th > 7 { cv.set(mid, th - 4, 0x5B4A6E); cv.set(mid, th - 3, 0x5B4A6E) }
                let roof = roofColour(t), roofDark = PixelCanvas.darken(roof, 0.75)
                let rh = px(Castle.roofHeight)
                for k in 0..<rh {
                    let half = Double(tw + 2) / 2 * (1 - Double(k) / Double(rh))
                    let lo = Int((Double(x0 + x1) / 2 - half).rounded()), hi = Int((Double(x0 + x1) / 2 + half).rounded())
                    guard hi >= lo else { continue }
                    for x in lo...hi { cv.set(x, th + k, x <= mid ? roof : roofDark) }
                }
                cv.set(mid, th + rh, roofDark)
            }
        }
        // Moss tufts at the foot (the castle grows out of the window's moss too).
        var r = ArtRNG(s: UInt64(w * 977 + h))
        for x in 0..<w where cv.get(x, 0) != nil && r.next() < 0.45 {
            cv.set(x, 0, r.next() < 0.5 ? 0x5E9E46 : 0x8BD66A)
            if r.next() < 0.3 { cv.set(x, 1, 0x8BD66A) }
        }
        cv.outline(0.62)
        return cv.image
    }
}

/// The home under the notch (see Notch.swift).
enum NotchArt {
    /// A little wooden house with a mossy roof and a round window, its porch running out to the right. `lit`: the
    /// window glows (Claude is working, or it's night).
    static func house(lit: Bool) -> CGImage {
        // 46 + 22 pt wide, 38 pt tall + roof and chimney: in art pixels (3 pt each).
        let w = 23, h = 17
        var cv = PixelCanvas(w, h)
        let plank: UInt32 = 0xB07A47, plankDark: UInt32 = 0x8A5A35, plankLight: UInt32 = 0xC99460
        // Walls (15 px wide), boards running across.
        for y in 1..<10 { for x in 0..<15 { cv.set(x, y, y % 3 == 0 ? plankDark : (x == 0 ? plankDark : plank)) } }
        for x in stride(from: 3, to: 15, by: 5) { cv.set(x, 5, plankLight) }
        // The porch floor, out to the right, with a little rail post.
        cv.hspan(0, w - 1, 0, plankDark); cv.hspan(0, w - 1, 1, plank)
        cv.vspan(w - 1, 2, 4, plankDark); cv.hspan(15, w - 1, 4, plankLight)
        // Roof: a mossy gable overhanging both sides.
        for k in 0..<6 { cv.hspan(-1 + k, 15 - k, 10 + k, k < 2 ? 0x6E4428 : 0x5E9E46) }
        for x in stride(from: 0, to: 15, by: 3) { cv.set(x, 11, 0x8BD66A); cv.set(x + 1, 12, 0x3E7A34) }
        // A stone chimney poking out of the roof, and a flower box under the window.
        cv.rect(11, 12, 2, 5, 0x8E877B); cv.hspan(11, 12, 16, 0x5E584F)
        cv.hspan(2, 7, 3, 0x6E4428)
        for (x, col) in [(2, 0xFF8FB1), (4, 0xFFE45C), (6, 0xB98CFF)] as [(Int, UInt32)] { cv.set(x, 4, col); cv.set(x + 1, 4, 0x5E9E46) }
        // Round window and the door.
        let glass: UInt32 = lit ? 0xFFD36B : 0x3B4660, glow: UInt32 = lit ? 0xFFF0B8 : 0x56627E
        cv.blob(4.5, 6.5, 2.1, 2.1, base: glass, light: glow)
        cv.set(4, 6, 0x6E4428); cv.set(5, 6, 0x6E4428); cv.set(4, 7, 0x6E4428)
        cv.rect(9, 2, 4, 6, 0x5E3B22); cv.set(12, 5, 0xE0B04A)
        // A tiny lantern on the porch post when it's lit.
        if lit { cv.set(w - 1, 5, 0xFFC845); cv.set(w - 1, 6, 0xFFE9A0) }
        cv.outline(0.6)
        return cv.image
    }

    /// A hammock, sagging, woven in two colours, `widthPx` long.
    static func hammock(widthPx: Int) -> CGImage {
        let w = max(10, widthPx), h = 6
        var cv = PixelCanvas(w, h)
        for x in 0..<w {
            let t = Double(x) / Double(w - 1)
            let sag = Int((sin(t * .pi) * 3.2).rounded())
            let top = 4 - sag
            cv.set(x, top, x % 4 < 2 ? 0xE8D7B0 : 0xD9855A)
            cv.set(x, top + 1, x % 4 < 2 ? 0xC9B48A : 0xB8683F)
        }
        cv.outline(0.7)
        return cv.image
    }
}

extension SkyArt {
    /// The little cloud that rides under the pointer (the cursor elevator).
    static let liftCloud: CGImage = {
        var cv = PixelCanvas(15, 5)
        cv.blob(4, 2.6, 3.6, 2.2, base: 0xF4F7FF, light: 0xFFFFFF, shade: 0xC9D6EE)
        cv.blob(9.5, 3, 4.2, 2.3, base: 0xF4F7FF, light: 0xFFFFFF, shade: 0xC9D6EE)
        cv.blob(7, 1.6, 6.5, 1.6, base: 0xE8EEFA, shade: 0xC9D6EE)
        cv.outline(0.8)
        return cv.image
    }()
}
