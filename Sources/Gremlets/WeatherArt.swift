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

/// The home under the notch (see Notch.swift).
enum NotchArt {
    /// A little wooden house with a mossy roof and a round window, its porch running out to the right. `lit`: the
    /// window glows (Claude is working, or it's night).
    static func house(lit: Bool, month: Int = 6, mail: Bool = false, stage: Int = 0, daisies: Int = 3) -> CGImage {
        // 46 + 22 pt wide, 38 pt tall + roof and chimney: in art pixels (3 pt each). A loft (stage 2) and a rooftop
        // garden (stage 3) add rows on top.
        let w = 23, h = 17 + (stage >= 2 ? 8 : 0) + (stage >= 3 ? 3 : 0)
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
        // It starts the day with leaves and fills up with the daisies the Gremlets pick from the moss and bring home.
        for k in 0..<6 { cv.set(2 + k, 4, k < daisies ? (k % 2 == 0 ? 0xFFFFFF : 0xFFF2B0) : (k % 2 == 0 ? 0x5E9E46 : 0x6CC04A)) }
        if daisies >= 6 { cv.set(2, 5, 0xFFFFFF); cv.set(7, 5, 0xFFF2B0) }
        // Round window and the door.
        let glass: UInt32 = lit ? 0xFFD36B : 0x3B4660, glow: UInt32 = lit ? 0xFFF0B8 : 0x56627E
        cv.blob(4.5, 6.5, 2.1, 2.1, base: glass, light: glow)
        cv.set(4, 6, 0x6E4428); cv.set(5, 6, 0x6E4428); cv.set(4, 7, 0x6E4428)
        cv.rect(9, 2, 4, 6, 0x5E3B22); cv.set(12, 5, 0xE0B04A)
        // A tiny lantern on the porch post when it's lit.
        if lit { cv.set(w - 1, 5, 0xFFC845); cv.set(w - 1, 6, 0xFFE9A0) }
        // The mailbox on the porch, its little red flag up when there's a postcard in it.
        cv.vspan(18, 2, 3, 0x6B4428); cv.rect(17, 4, 3, 2, 0x8E877B); cv.set(17, 5, 0xB8B1A4)
        if mail { cv.vspan(20, 4, 6, 0x5E3B22); cv.set(21, 6, 0xE8574A); cv.set(21, 5, 0xE8574A) }
        // The roof through the seasons.
        var r = ArtRNG(s: 4242)
        for y in 10..<17 { for x in -1..<16 {
            guard let c = cv.get(x, y), [0x5E9E46, 0x8BD66A, 0x3E7A34].contains(c) else { continue }
            switch month {
            case 3, 4, 5: if r.next() < 0.3 { cv.set(x, y, r.next() < 0.5 ? 0xFF8FB1 : 0xFFD6E6) }           // blossom
            case 9, 10, 11: cv.set(x, y, [0xD9853A, 0xC2462E, 0xE8B04A, 0x9E5C34][Int(r.next() * 4)])        // autumn leaves
            case 12, 1, 2: if y >= 12 || r.next() < 0.5 { cv.set(x, y, r.next() < 0.8 ? 0xF4F8FF : 0xD6E2F2) } // snow
            default: break
            }
        } }
        if [12, 1, 2].contains(month) { for x in stride(from: 0, to: 15, by: 3) { cv.set(x, 9, 0xBFE3F7) } }   // icicles
        // Growing with you: a balcony rail on the porch (1), a loft with a round window (2), a rooftop garden (3).
        if stage >= 1 { for x in 15..<w { if x % 2 == 0 { cv.vspan(x, 2, 4, 0x8A5A35) } }; cv.hspan(15, w - 1, 5, 0xC99460) }
        if stage >= 2 {
            let by = 16
            for y in by..<(by + 6) { for x in 3..<12 { cv.set(x, y, y == by ? 0x8A5A35 : (x == 3 ? 0x8A5A35 : 0xB07A47)) } }
            cv.blob(7.5, Double(by + 3), 1.4, 1.4, base: lit ? 0xFFD36B : 0x3B4660, light: lit ? 0xFFF0B8 : 0x56627E)
            for k in 0..<3 { cv.hspan(2 + k, 12 - k, by + 6 + k, k == 2 ? 0x8BD66A : 0x5E9E46) }
        }
        if stage >= 3 {
            let gy = 16 + 9
            for (x, c) in [(4, 0xFF8FB1), (6, 0x6CC04A), (7, 0xFFE45C), (9, 0x6CC04A), (10, 0xB98CFF)] as [(Int, UInt32)] { cv.set(x, gy, c); cv.set(x, gy - 1, 0x5E9E46) }
            cv.vspan(8, gy - 1, gy + 1, 0x6B4428); cv.set(7, gy + 2, 0x6CC04A); cv.set(9, gy + 2, 0x8BD66A); cv.set(8, gy + 2, 0x8BD66A)   // a sapling
        }
        let white = cv.px.indices.filter { cv.px[$0] == 0xFFFFFF }
        cv.outline(0.6)
        for i in white { cv.px[i] = 0xFFFFFF }
        return cv.image
    }

    /// A hammock, sagging, woven in two colours, `widthPx` long.
    static func hammock(widthPx: Int, lights: Bool = false) -> CGImage {
        let w = max(10, widthPx), h = 6
        var cv = PixelCanvas(w, h)
        for x in 0..<w {
            let t = Double(x) / Double(w - 1)
            let sag = Int((sin(t * .pi) * 3.2).rounded())
            let top = 4 - sag
            cv.set(x, top, x % 4 < 2 ? 0xE8D7B0 : 0xD9855A)
            cv.set(x, top + 1, x % 4 < 2 ? 0xC9B48A : 0xB8683F)
            // Fairy lights strung along it after dark.
            if lights && x % 5 == 2 { cv.set(x, top + 2 < h ? top + 2 : top, [0xFFE45C, 0xFF8FB1, 0x8FD3FF][(x / 5) % 3]) }
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

/// The hut that hangs beside Claude's terminal (see Pod.swift): a woven acorn with a leafy cap for a roof, a round
/// door and a round window (warm and lit while Claude works), and the mossy branch it hangs from.
enum PodArt {
    static func pod(lit: Bool) -> CGImage {
        var cv = PixelCanvas(12, 15)
        let weave: UInt32 = 0xC98B4A, weaveLight: UInt32 = 0xE0B070, weaveDark: UInt32 = 0x9A6A3A
        // The woven body, rounder at the bottom like an acorn.
        cv.blob(6, 5.2, 5.4, 5.6, base: weave, light: weaveLight, shade: weaveDark)
        for y in stride(from: 1, to: 10, by: 3) { for x in 0..<12 where cv.get(x, y) != nil && (x + y / 3) % 2 == 0 { cv.set(x, y, weaveDark) } }
        // The leafy cap roof, overhanging, with a stalk on top where the vine ties on.
        for k in 0..<4 { cv.hspan(-1 + k, 12 - k, 9 + k, k == 0 ? 0x3E7A34 : (k == 3 ? 0x8BD66A : 0x5E9E46)) }
        cv.set(1, 10, 0x8BD66A); cv.set(5, 11, 0x3E7A34); cv.set(9, 10, 0x8BD66A)
        cv.vspan(6, 13, 14, 0x6B4428)
        // A round door at the bottom and a round window above it.
        cv.blob(6, 1.6, 1.5, 1.6, base: 0x5E3B22); cv.set(7, 1, 0xE8C060)
        cv.blob(4, 6, 1.4, 1.4, base: lit ? 0xFFD36B : 0x3B4660, light: lit ? 0xFFF0B8 : 0x56627E)
        cv.set(4, 6, lit ? 0xFFF7D6 : 0x56627E)
        // A tiny flower by the window.
        cv.set(9, 6, 0xFF8FB1); cv.set(9, 5, 0x5E9E46)
        cv.outline(0.62)
        return cv.image
    }

    /// The branch, growing out from the window's corner to the right: bark, moss on top, a couple of leaves, a
    /// tapering tip.
    /// Full screen: a mossy tree stump for a bottom corner (26 × 14 px; its mossy top, the perch, is 12 px up).
    /// Faces right (mushroom on the right side); mirror it for the right corner.
    static let stump: CGImage = {
        var cv = PixelCanvas(26, 14)
        let bark = 0x6B4428 as UInt32, barkLight = 0x8A5A35 as UInt32, ring = 0xC79A62 as UInt32
        // Roots spreading into the ground.
        cv.rect(2, 0, 22, 1, bark); cv.rect(1, 0, 2, 1, barkLight); cv.rect(23, 0, 2, 1, barkLight)
        cv.rect(3, 1, 20, 1, bark)
        // Trunk with bark stripes.
        for x in 4...21 {
            for y in 2...9 { cv.set(x, y, x % 4 == 1 ? barkLight : (x == 4 || x == 21 ? 0x553620 : bark)) }
        }
        // The cut top showing a ring, under a cap of moss that drips down the sides.
        cv.rect(5, 10, 16, 1, ring); cv.rect(8, 10, 10, 1, 0xE0B47E)
        for x in 4...21 { cv.set(x, 11, x % 3 == 0 ? 0x8BD66A : 0x5E9E46) }
        for x in [5, 10, 15, 20] { cv.set(x, 10, 0x5E9E46); cv.set(x, 9, 0x4C8A3A) }
        cv.set(6, 12, 0x8BD66A); cv.set(13, 12, 0x6CC04A); cv.set(18, 12, 0x8BD66A)
        // A little red mushroom on the side, and a fern on the other.
        cv.rect(22, 2, 1, 2, 0xF2E6D0); cv.rect(21, 4, 4, 1, 0xD9534F); cv.rect(22, 5, 2, 1, 0xD9534F); cv.set(22, 4, 0xFFFFFF)
        for (x, y) in [(2, 2), (2, 3), (1, 4), (3, 4), (1, 5), (0, 6), (2, 6), (3, 5)] { cv.set(x, y, y > 4 ? 0x8BD66A : 0x5E9E46) }
        let white = cv.px.indices.filter { cv.px[$0] == 0xFFFFFF }
        cv.outline(0.66)
        for i in white { cv.px[i] = 0xFFFFFF }
        return cv.image
    }()

    static let branch: CGImage = {
        var cv = PixelCanvas(24, 6)
        for x in 0..<24 {
            let thick = x < 16 ? 3 : (x < 21 ? 2 : 1)
            for y in 0..<thick { cv.set(x, 2 + y - (x > 20 ? 0 : 0), y == thick - 1 ? 0x8A5A35 : 0x6B4428) }
            if x < 19 && x % 5 != 3 { cv.set(x, 2 + thick, x % 3 == 0 ? 0x8BD66A : 0x5E9E46) }   // moss along the top
        }
        cv.set(21, 5, 0x6CC04A); cv.set(22, 5, 0x8BD66A); cv.set(23, 4, 0x6CC04A)               // leaves at the tip
        cv.set(9, 1, 0x5E9E46); cv.set(10, 0, 0x6CC04A)                                        // and one hanging
        cv.outline(0.66)
        return cv.image
    }()
}

