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
