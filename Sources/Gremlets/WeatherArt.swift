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
    /// A little timber house hanging under the menu bar: stone footing, board walls, a round window with a flower
    /// box, an arched door with a lantern, a shingled roof under a drape of moss, a stone chimney, and a porch running
    /// out to the right with a mailbox, a potted fern and a lantern post. `lit`: windows and lanterns glow (Claude is
    /// working, or it's night). It grows: a balcony rail (stage 1), a loft (2), a rooftop garden (3), a birdhouse and
    /// a string of lights (4). The footprint stays put (23 px wide; porch floor on the bottom two rows; door at 9-12).
    static func house(lit: Bool, month: Int = 6, mail: Bool = false, stage: Int = 0, daisies: Int = 3) -> CGImage {
        let w = 23, h = 18 + (stage >= 2 ? 8 : 0) + (stage >= 3 ? 2 : 0)
        var cv = PixelCanvas(w, h)
        let beam: UInt32 = 0x5E3B22, plank: UInt32 = 0xB07A47, plankAlt: UInt32 = 0xA06C3E, plankLight: UInt32 = 0xC99460
        let stone: UInt32 = 0x9A958B, stoneDark: UInt32 = 0x6E6A62, stoneLight: UInt32 = 0xBDB8AE
        let moss: UInt32 = 0x5E9E46, mossLight: UInt32 = 0x8BD66A, mossDark: UInt32 = 0x3E7A34
        let shingle: UInt32 = 0x7A5236, shingleDark: UInt32 = 0x5E3B22
        let warm: UInt32 = 0xFFD36B, warmHi: UInt32 = 0xFFF0B8, night: UInt32 = 0x3B4660, nightHi: UInt32 = 0x6A7898
        // The porch: a beam under planks, seams every few boards.
        cv.hspan(0, w - 1, 0, 0x6E4428)
        for x in 0..<w { cv.set(x, 1, x % 4 == 3 ? 0x8A5A35 : (x % 7 == 1 ? plankLight : plank)) }
        // Walls: vertical boards between corner posts, on a stone footing, a top plate along the eaves.
        for y in 3...9 { for x in 1...13 { cv.set(x, y, x % 2 == 0 ? plank : plankAlt) } }
        for x in 0...14 { cv.set(x, 2, x % 3 == 0 ? stoneDark : (x % 3 == 1 ? stone : stoneLight)) }
        cv.vspan(0, 3, 10, beam); cv.vspan(14, 3, 10, beam); cv.hspan(0, 14, 10, beam)
        cv.set(3, 8, 0x8A5A35); cv.set(12, 9, 0x8A5A35)   // knots
        // The window: a wooden frame round four panes of glass, warm with curtains drawn back when it's lit.
        cv.hspan(3, 6, 9, beam); cv.hspan(3, 6, 5, beam); cv.vspan(2, 6, 8, beam); cv.vspan(7, 6, 8, beam)
        cv.rect(3, 6, 4, 3, lit ? warm : night)
        cv.set(4, 8, lit ? warmHi : nightHi); cv.set(5, 7, lit ? warmHi : nightHi)
        if lit { cv.set(3, 8, 0xE89AA8); cv.set(6, 8, 0xE89AA8); cv.set(3, 7, 0xE89AA8) }
        // The window box under it: it starts the day with leaves and fills up with the daisies they bring home.
        cv.hspan(2, 7, 3, 0x6E4428)
        for k in 0..<6 { cv.set(2 + k, 4, k < daisies ? (k % 2 == 0 ? 0xFFFFFF : 0xFFF2B0) : (k % 2 == 0 ? moss : 0x6CC04A)) }
        if daisies >= 6 { cv.set(2, 5, 0xFFFFFF); cv.set(7, 5, 0xFFF2B0) }
        // An arched door with a step, a brass knob and a little lantern beside it.
        cv.rect(9, 3, 4, 5, 0x6E4428); cv.hspan(10, 11, 8, 0x6E4428)
        cv.vspan(10, 3, 7, 0x5E3B22); cv.set(12, 5, 0xE0B04A)
        cv.hspan(8, 13, 2, stoneLight)
        cv.set(13, 7, 0x3A2A1C); cv.set(13, 6, lit ? 0xFFC845 : 0x8E7A52)
        // The roof: overhanging eaves, rows of wooden shingles, moss draped over the top and dripping off the edge.
        cv.hspan(-1, 15, 11, shingleDark)
        for k in 0..<6 {
            let y = 12 + k
            for x in (-1 + k)...(15 - k) { cv.set(x, y, (x + k * 2) % 4 == 0 ? shingleDark : shingle) }
        }
        var r = ArtRNG(s: 9137)
        for k in 2..<6 { for x in (-1 + k)...(15 - k) where r.next() < 0.75 { cv.set(x, 12 + k, r.next() < 0.3 ? mossLight : moss) } }
        for x in stride(from: 0, through: 14, by: 2) where r.next() < 0.7 { cv.set(x, 12, moss); cv.set(x, 11, r.next() < 0.5 ? mossDark : moss) }
        cv.set(1, 10, mossDark); cv.set(1, 9, moss); cv.set(13, 10, mossDark)   // strands off the eaves
        cv.set(7, 15, beam); cv.set(7, 14, 0x3A2A1C)   // the vent in the gable
        // A stone chimney with a cap.
        cv.rect(11, 14, 2, 3, stone); cv.set(11, 15, stoneDark); cv.hspan(10, 13, 17, stoneDark)
        // The porch: a potted fern, the mailbox (its red flag up when there's a postcard in it), a lantern post.
        cv.set(17, 2, 0xC2643A); cv.set(17, 3, moss); cv.set(16, 4, mossLight); cv.set(18, 4, moss)
        cv.vspan(19, 2, 3, 0x6B4428); cv.rect(18, 4, 3, 2, 0x8E877B); cv.set(18, 5, 0xB8B1A4)
        if mail { cv.vspan(21, 4, 6, 0x5E3B22); cv.set(20, 6, 0xE8574A); cv.set(20, 7, 0xE8574A) }
        cv.vspan(22, 2, 8, beam); cv.set(21, 8, beam)
        cv.set(21, 7, 0x3A2A1C); cv.set(21, 6, lit ? 0xFFC845 : 0x8E7A52); cv.set(21, 5, lit ? 0xFFE9A0 : 0x6E6A62)
        // The roof through the seasons.
        for y in 11..<18 { for x in -1..<16 {
            guard let c = cv.get(x, y), [moss, mossLight, mossDark].contains(c) else { continue }
            switch month {
            case 3, 4, 5: if r.next() < 0.25 { cv.set(x, y, r.next() < 0.5 ? 0xFF8FB1 : 0xFFD6E6) }            // blossom
            case 9, 10, 11: cv.set(x, y, [0xD9853A, 0xC2462E, 0xE8B04A, 0x9E5C34][Int(r.next() * 4)])         // autumn leaves
            case 12, 1, 2: cv.set(x, y, r.next() < 0.8 ? 0xF4F8FF : 0xD6E2F2)                                // snow
            default: break
            }
        } }
        if [12, 1, 2].contains(month) { for x in stride(from: 0, to: 15, by: 3) { cv.set(x, 10, 0xBFE3F7) } }   // icicles
        // Growing with you.
        if stage >= 1 {
            // A balcony rail round the porch.
            for x in stride(from: 15, through: 21, by: 2) where x != 19 { cv.vspan(x, 2, 3, 0x8A5A35) }
            cv.hspan(15, 21, 4, plankLight)
        }
        if stage >= 2 {
            // A loft on top, its own little shingled roof and a round window with a box of flowers.
            let by = 18
            for y in by..<(by + 5) { for x in 2...9 { cv.set(x, y, x == 2 || x == 9 ? beam : (x % 2 == 0 ? plank : plankAlt)) } }
            cv.blob(5.5, Double(by + 2) + 0.5, 1.5, 1.5, base: lit ? warm : night, light: lit ? warmHi : nightHi)
            cv.hspan(4, 7, by, 0x6E4428); cv.set(4, by + 1, 0xFF8FB1); cv.set(7, by + 1, 0xFFE45C)
            for k in 0..<3 { for x in (1 + k)...(10 - k) { cv.set(x, by + 5 + k, k == 2 ? mossLight : ((x + k) % 3 == 0 ? shingleDark : moss)) } }
        }
        if stage >= 3 {
            // A rooftop garden: a sapling and flowers on the loft.
            let gy = 26
            for (x, c) in [(3, 0xFF8FB1), (5, 0xFFE45C), (8, 0xB98CFF)] as [(Int, UInt32)] { cv.set(x, gy, c); cv.set(x, gy - 1, moss) }
            cv.vspan(6, gy - 1, gy, 0x6B4428); cv.set(6, gy + 1, mossLight); cv.set(5, gy + 1, 0x6CC04A); cv.set(7, gy + 1, mossLight)
        }
        if stage >= 4 {
            // A birdhouse up on the porch post, and a string of lights from the loft down to it.
            cv.vspan(22, 8, 10, beam)
            cv.rect(20, 11, 3, 2, 0xC2643A); cv.set(21, 11, 0x3A2A1C); cv.hspan(19, 23, 13, 0x8A5A35); cv.set(21, 14, 0x8A5A35)
            let bulbs: [UInt32] = lit ? [0xFFE45C, 0xFF8FB1, 0x8FD3FF, 0xB5F27A] : [0x9A8F6A, 0x9A7F88, 0x7F96A6, 0x88A070]
            for (k, x) in stride(from: 10, through: 19, by: 1).enumerated() {
                let t = Double(x - 10) / 9
                let y = Int((22 - t * 9 - sin(t * .pi) * 2.2).rounded())
                cv.set(x, y, k % 2 == 0 ? bulbs[(k / 2) % bulbs.count] : 0x4A4038)
            }
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


/// The little places hanging from the top of the screen in its corners (out of full screen).
enum TopStructureArt {
    /// A woven nest hut with a leaf roof, a round door and window, on a twig porch that runs out to the right
    /// (36 × 28 px; the porch top, where Gremlets stand, is 2 px up from the bottom). The window glows when `lit`.
    static func nestHut(lit: Bool, stage: Int = 0) -> CGImage {
        var cv = PixelCanvas(36, 28)
        // The twig porch.
        for x in 0..<36 { cv.set(x, 0, x % 4 == 1 ? 0x553620 : 0x6B4428); cv.set(x, 1, x % 5 == 2 ? 0xA9743F : 0x8A5A35) }
        for x in [6, 14, 33] { cv.vspan(x, 0, 1, 0x553620) }
        // The woven nest body.
        cv.blob(11, 10.5, 10, 8.6, base: 0xC9A15A, light: 0xE0BE78, shade: 0x9C7840)
        for y in stride(from: 4, through: 17, by: 3) { for x in 2...20 where cv.solid(x, y) && (x + y) % 4 != 0 { cv.set(x, y, 0xA88445) } }
        for x in stride(from: 3, through: 19, by: 4) { for y in 3...17 where cv.solid(x, y) && y % 2 == 0 { cv.set(x, y, 0xB8924E) } }
        // Leaf roof.
        cv.blob(11, 19.5, 12, 4.6, base: 0x6CC04A, light: 0x9BDB6E, shade: 0x3E8E3A)
        for x in stride(from: 0, through: 22, by: 3) { cv.set(x, 16, 0x5E9E46); cv.set(x + 1, 15, 0x4C8A3A) }
        cv.vspan(11, 24, 26, 0x6B4428); cv.set(12, 26, 0x8BD66A); cv.set(13, 27, 0x6CC04A)
        // Round door and window.
        cv.blob(8, 6.6, 3.0, 3.6, base: 0x4A3020, light: 0x5E3B22)
        cv.set(10, 6, 0xE0B04A)
        cv.blob(16, 11, 1.8, 1.8, base: lit ? 0xFFD36B : 0x3B4660, light: lit ? 0xFFF0B8 : 0x56627E)
        // Flowers along the porch, a tiny lantern hanging at its end.
        for (x, c) in [(23, 0xFF8FB1), (25, 0xFFE45C), (28, 0xFFFFFF)] as [(Int, UInt32)] { cv.set(x, 2, 0x5E9E46); cv.set(x, 3, c) }
        cv.vspan(35, 2, 6, 0x6B4428); cv.set(34, 7, 0x6B4428); cv.rect(33, 3, 2, 3, lit ? 0xFFC845 : 0xC9A15A); cv.set(33, 4, lit ? 0xFFF0B8 : 0xE0BE78)
        // A clay chimney poking up through the leaf roof (it smokes while someone naps inside).
        cv.rect(15, 21, 2, 4, 0xB0603A); cv.hspan(14, 17, 25, 0x8A4A2E)
        // Growing with the care they put into it (and the Claude sessions): a step ladder and a fern by the door (1),
        // bunting along the porch (2), mushrooms and flowers on the roof (3), a string of lights and a birdhouse (4).
        if stage >= 1 {
            for y in [2, 4] { cv.hspan(1, 3, y, 0x8A5A35) }; cv.vspan(1, 2, 5, 0x6B4428); cv.vspan(3, 2, 5, 0x6B4428)
            cv.set(13, 2, 0xC2643A); cv.set(13, 3, 0x5E9E46); cv.set(12, 4, 0x8BD66A); cv.set(14, 4, 0x5E9E46)
        }
        if stage >= 2 {
            let flags: [UInt32] = [0xE8574A, 0xFFE45C, 0x8FD3FF, 0xFF8FB1, 0xB5F27A]
            for (k, x) in stride(from: 21, through: 33, by: 3).enumerated() { cv.set(x, 8, flags[k % flags.count]); cv.set(x, 7, flags[k % flags.count]); cv.set(x + 1, 8, 0x6B4428) }
            cv.hspan(20, 34, 9, 0x6B4428)
        }
        if stage >= 3 {
            for (x, c) in [(5, 0xE0453A), (8, 0xFFE45C), (19, 0xFF8FB1)] as [(Int, UInt32)] { cv.set(x, 24, 0xF2E6D0); cv.set(x, 25, c) }
            cv.set(4, 25, 0xE0453A); cv.set(6, 25, 0xE0453A); cv.set(5, 26, 0xE0453A)
        }
        if stage >= 4 {
            let bulbs: [UInt32] = lit ? [0xFFE45C, 0xFF8FB1, 0x8FD3FF, 0xB5F27A] : [0x9A8F6A, 0x9A7F88, 0x7F96A6, 0x88A070]
            for x in stride(from: 1, through: 21, by: 2) { cv.set(x, 15 + Int((sin(Double(x) / 21 * .pi) * -1.5).rounded()), bulbs[(x / 2) % bulbs.count]) }
            cv.rect(29, 10, 3, 2, 0xC2643A); cv.set(30, 10, 0x3A2A1C); cv.hspan(28, 32, 12, 0x8A5A35); cv.vspan(30, 2, 9, 0x6B4428)
        }
        let white = cv.px.indices.filter { cv.px[$0] == 0xFFFFFF }
        cv.outline(0.62)
        for i in white { cv.px[i] = 0xFFFFFF }
        return cv.image
    }

    /// A big leaf, gently cupped, with its midrib and a curl of stem (34 × 10 px; the leaf's middle, where Gremlets
    /// stand, is 3 px up from the bottom).
    static let leafSwing: CGImage = {
        var cv = PixelCanvas(34, 10)
        let leaf: UInt32 = 0x7CC24E, light: UInt32 = 0xB0E37A, dark: UInt32 = 0x4A8E36, rib: UInt32 = 0x3E7A34
        for x in 1..<33 {
            let t = Double(x - 1) / 31
            let cup = Int((pow(abs(t - 0.5) * 2, 2) * 4).rounded())   // ends curl up
            let thick = 3 + Int((sin(t * .pi) * 2).rounded())
            for y in 0..<thick { cv.set(x, 1 + cup + y, y == thick - 1 ? light : (y == 0 ? dark : leaf)) }
            cv.set(x, 1 + cup + max(0, thick / 2 - 1), rib)
        }
        // Veins.
        for x in stride(from: 5, to: 30, by: 4) { cv.set(x, 2 + Int((pow(abs(Double(x - 1) / 31 - 0.5) * 2, 2) * 4).rounded()), dark) }
        // The stem curling off the right end, a dewdrop and two flowers.
        cv.set(33, 6, rib); cv.set(33, 7, rib); cv.set(32, 8, rib); cv.set(31, 9, rib)
        cv.set(12, 4, 0xDFF4FF); cv.set(20, 5, 0xFF8FB1); cv.set(22, 5, 0xFFE45C)
        cv.outline(0.62)
        return cv.image
    }()
}
