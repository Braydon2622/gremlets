import AppKit
import GremletsCore

/// Floating islands: every shelf a Gremlet puts up is a little chunk of a world, each with its own biome.
/// A layered terrain body (topsoil, dirt, stone, ore) that tapers to a jagged underside with roots, vines or icicles
/// hanging off it, plus a strip of life on top (grass tufts, flowers, trees, cacti, crystals, glowing mushrooms).
enum Biome: String, CaseIterable {
    case meadow, snow, desert, jungle, glowshroom, crystal, cherry, autumn, sky

    /// Which biome a shelf becomes: its style picks the family, the window picks the variant, the season nudges it.
    static func pick(_ style: ShelfStyle, seed: UInt64, month: Int) -> Biome {
        switch style {
        case .stone: return .crystal
        case .leaf: return .jungle
        case .mushroom: return .glowshroom
        case .cloud: return .sky
        default:
            var pool: [Biome] = [.meadow, .meadow, .desert, .jungle, .autumn, .cherry, .snow]
            if [12, 1, 2].contains(month) { pool += [.snow, .snow] }
            if [3, 4, 5].contains(month) { pool += [.cherry, .cherry] }
            if [9, 10, 11].contains(month) { pool += [.autumn, .autumn] }
            return pool[Int(seed % UInt64(pool.count))]
        }
    }

    /// Top layer, its highlight, soil, deep stone, and a gem/ore colour.
    var palette: (top: UInt32, topLight: UInt32, soil: UInt32, soilDark: UInt32, stone: UInt32, stoneDark: UInt32, ore: UInt32) {
        switch self {
        case .meadow:     return (0x5DBB46, 0x9BE36A, 0x8A5A35, 0x6B4428, 0x7D7A74, 0x5A5752, 0xF2C94C)
        case .snow:       return (0xF4FAFF, 0xFFFFFF, 0x7B6A62, 0x5C4F49, 0x8C9BB0, 0x66738A, 0x8FE3FF)
        case .desert:     return (0xF0D58C, 0xFFEDB3, 0xD9B26A, 0xB98E4E, 0xC98E5A, 0x9E6B40, 0xE85D5D)
        case .jungle:     return (0x3E9E3A, 0x6BD15A, 0x5B4434, 0x433226, 0x5E6B4C, 0x434E36, 0xB6F05C)
        case .glowshroom: return (0x3F7FE0, 0x7FB8FF, 0x3B3A5A, 0x2A2944, 0x4A4A66, 0x33334D, 0x6FF2FF)
        case .crystal:    return (0x7BA889, 0xA9D3B2, 0x6E6A78, 0x524E5C, 0x5D5870, 0x423E52, 0xD58CFF)
        case .cherry:     return (0x7CCB6A, 0xF7B6D2, 0x8A5A35, 0x6B4428, 0x7D7A74, 0x5A5752, 0xFF9EC7)
        case .autumn:     return (0xD98A3A, 0xF2B45C, 0x7A5232, 0x5C3D24, 0x7D7A74, 0x5A5752, 0xF2C94C)
        case .sky:        return (0x6CC04A, 0x9BE36A, 0x8A5A35, 0x6B4428, 0xA9BCD6, 0x7E93B3, 0xFFE45C)
        }
    }
}

enum IslandArt {
    /// The island's body, from the walking surface down. Top-left of the image sits at the shelf's top-left.
    static func body(_ b: Biome, widthPx w: Int, seed: UInt64) -> CGImage {
        let pal = b.palette
        let depth = max(9, min(22, Int(Double(w) * 0.3)))
        let h = depth + 8   // room for things hanging off the bottom
        var cv = PixelCanvas(w, h)
        var r = ArtRNG(s: seed &+ 11)
        // Underside profile: deepest in the middle, tapering to the ends, with a ragged edge.
        var bottom = [Int](repeating: 0, count: w)
        for x in 0..<w {
            let u = (Double(x) + 0.5) / Double(w) * 2 - 1
            let shape = pow(max(0, 1 - u * u), 0.65)
            let ragged = r.range(-1.4, 1.4) + sin(Double(x) * 0.9 + Double(seed % 7)) * 0.8
            bottom[x] = max(2, Int(Double(depth) * shape + ragged))
        }
        // Canvas y is bottom-up; the surface is the top row (y = h - 1).
        let top = h - 1
        for x in 0..<w {
            for d in 0..<bottom[x] {
                let y = top - d
                var c: UInt32
                if d == 0 {
                    c = (x + Int(seed)) % 7 == 0 ? pal.topLight : pal.top
                } else if d == 1 {
                    c = b == .snow || b == .desert ? pal.top : (x % 3 == 0 ? pal.top : pal.soil)   // grass roots into the dirt
                } else if d < 4 + Int(r.range(0, 2)) {
                    c = (x * 7 + d * 3) % 11 == 0 ? pal.soilDark : pal.soil
                } else {
                    c = (x * 5 + d * 7) % 13 == 0 ? pal.stoneDark : pal.stone
                    // Ore and gems glinting in the stone.
                    if r.next() < 0.045 { c = pal.ore }
                }
                if b == .desert && d > 1 && d % 3 == 0 { c = pal.soilDark }     // sandstone strata
                cv.set(x, y, c)
            }
        }
        cv.outline(0.62)
        // Re-light the top edge (outline darkened it).
        for x in 0..<w where cv.get(x, top) != nil { cv.set(x, top, (x + Int(seed)) % 7 == 0 ? pal.topLight : pal.top) }
        // Things hanging off the underside.
        for x in stride(from: 2, to: w - 2, by: 1) where r.next() < 0.16 {
            let y0 = top - bottom[x]
            let len = Int(r.range(1, 6))
            for k in 0..<len {
                let c: UInt32
                switch b {
                case .snow: c = k == len - 1 ? 0xFFFFFF : 0xBFE6FF                         // icicles
                case .jungle, .meadow, .cherry, .autumn: c = k % 2 == 0 ? 0x4F8A3A : 0x3E7030  // roots and vines
                case .glowshroom: c = k == len - 1 ? 0x6FF2FF : 0x3B5A8A                   // glowing tendrils
                case .crystal: c = k == len - 1 ? 0xE6B8FF : 0xA06BD6                      // hanging crystals
                case .desert: c = 0xB98E4E                                                 // trickling sand
                case .sky: continue                                                        // clouds instead (below)
                }
                cv.set(x, y0 - k, c)
            }
        }
        // A sky island floats on a wreath of cloud hugging its underside.
        if b == .sky {
            var cr = ArtRNG(s: seed &+ 21)
            var x = 1.0
            while x < Double(w) - 1 {
                let ix = Int(x)
                let under = Double(top - bottom[min(w - 1, max(0, ix))])
                let rad = cr.range(2.4, 4.2)
                cv.blob(x, under + 0.5, rad, rad * 0.7, base: 0xF5FAFF, light: 0xFFFFFF, shade: 0xC6D6EA)
                x += rad * 1.3
            }
            cv.blob(-1, Double(top - bottom[0]) + 3, 3.5, 2.5, base: 0xF5FAFF, light: 0xFFFFFF, shade: 0xC6D6EA)
            cv.blob(Double(w), Double(top - bottom[w - 1]) + 3, 3.5, 2.5, base: 0xF5FAFF, light: 0xFFFFFF, shade: 0xC6D6EA)
        }
        return cv.image
    }

    /// Life on top of the island: drawn upward from the surface. Bottom-left of the image sits on the shelf's top-left.
    /// Keeps the middle low (that's where the window box and the Gremlet are), with the big things out at the ends.
    static func decor(_ b: Biome, widthPx w: Int, seed: UInt64, night: Bool) -> CGImage {
        let h = 24
        var cv = PixelCanvas(w, h)
        var r = ArtRNG(s: seed &+ 99)
        let pal = b.palette
        // Low tufts all along.
        for x in 0..<w where r.next() < 0.45 {
            let t: UInt32
            switch b {
            case .snow: t = 0xE8F4FF
            case .desert: t = r.next() < 0.3 ? 0x9CB45A : pal.topLight
            case .glowshroom: t = 0x5FA0FF
            case .crystal: t = 0x7BA889
            case .autumn: t = r.next() < 0.5 ? 0xE0A04A : 0xC77A30
            default: t = r.next() < 0.5 ? pal.topLight : pal.top
            }
            cv.set(x, 0, t)
            if r.next() < 0.35 { cv.set(x, 1, t) }
        }
        // Small flowers / pebbles scattered.
        for _ in 0..<(w / 9) {
            let x = Int(r.range(1, Double(w - 2)))
            switch b {
            case .meadow: cv.set(x, 2, [0xFF6B6B, 0xFFD45E, 0xFFFFFF, 0xB98CFF][Int(r.range(0, 3.99))]); cv.set(x, 1, 0x3E8E3A)
            case .cherry: cv.set(x, 1, 0xFFB6D9)
            case .jungle: cv.set(x, 2, 0xFF5FA2); cv.set(x, 1, 0x2F7A2C)
            case .autumn: cv.blob(Double(x), 1.5, 1.6, 1.3, base: 0xE8862C, light: 0xFFB45C)   // tiny pumpkins
            case .glowshroom: cv.set(x, 1, night ? 0x9FFFFF : 0x6FD2FF); cv.set(x, 0, 0xCFE6FF)
            case .crystal: cv.set(x, 1, pal.ore); cv.set(x, 2, 0xF3D9FF)
            case .snow: cv.set(x, 0, 0xFFFFFF)
            case .desert: cv.set(x, 0, 0xC9A36A)
            case .sky: cv.set(x, 1, 0xFFE45C)
            }
        }
        // The landmark at the outer end (right side; the layer flips for left-hand shelves).
        let ex = Double(w) - 7
        switch b {
        case .meadow:
            cv.rect(Int(ex), 0, 2, 9, 0x7A5232)
            cv.blob(ex + 1, 13, 6, 5, base: 0x4FA83A, light: 0x8BD66A, shade: 0x2F7A2C)
        case .cherry:
            cv.rect(Int(ex), 0, 2, 9, 0x6B4428)
            cv.blob(ex + 1, 13, 6.5, 5, base: 0xF7A6CB, light: 0xFFD6E8, shade: 0xD6789F)
        case .autumn:
            cv.rect(Int(ex), 0, 2, 8, 0x6B4428)
            cv.blob(ex + 1, 12, 6, 5, base: 0xE0782C, light: 0xF7B45C, shade: 0xB5521F)
        case .snow:
            // A snowy pine.
            cv.rect(Int(ex), 0, 2, 3, 0x6B4428)
            for (i, rw) in [6, 5, 4, 3, 2, 1].enumerated() {
                cv.rect(Int(ex) + 1 - rw, 3 + i * 3, rw * 2, 3, 0x2F6B4A)
                cv.rect(Int(ex) + 1 - rw, 5 + i * 3, rw * 2, 1, 0xF4FAFF)
            }
        case .desert:
            // A cactus with an arm.
            cv.rect(Int(ex), 0, 3, 12, 0x5E9E4A); cv.rect(Int(ex), 0, 1, 12, 0x3E7A34)
            cv.rect(Int(ex) + 3, 5, 2, 2, 0x5E9E4A); cv.rect(Int(ex) + 4, 5, 2, 5, 0x5E9E4A)
            cv.set(Int(ex) + 1, 12, 0xFF6B9A)
        case .jungle:
            // Big drooping leaves.
            cv.rect(Int(ex), 0, 1, 10, 0x2F7A2C)
            cv.blob(ex - 3, 9, 4.5, 2, base: 0x3EA83A, light: 0x7FD66A)
            cv.blob(ex + 4, 11, 4.5, 2, base: 0x3EA83A, light: 0x7FD66A)
            cv.blob(ex, 13, 3, 2, base: 0x4FB84A, light: 0x8FE07A)
        case .glowshroom:
            for (dx, hgt, rad) in [(0.0, 9.0, 4.5), (-6, 5, 3), (5, 6, 2.6)] {
                cv.rect(Int(ex + dx), 0, 1, Int(hgt), 0xCFE6FF)
                cv.blob(ex + dx, hgt, rad, rad * 0.6, base: night ? 0x5FE8FF : 0x3FA8E0, light: 0xBFFFFF)
            }
        case .crystal:
            for (dx, hgt) in [(0.0, 11), (-3, 7), (3, 8)] as [(Double, Int)] {
                for y in 0..<hgt { let half = max(0, (hgt - y) / 3); cv.rect(Int(ex + dx) - half, y, half * 2 + 1, 1, y > hgt - 3 ? 0xF3D9FF : 0xB57AF2) }
            }
        case .sky:
            // A little golden fence and a star.
            for x in stride(from: Int(ex) - 6, through: Int(ex) + 4, by: 3) { cv.rect(x, 0, 1, 4, 0xE8C25A) }
            cv.rect(Int(ex) - 6, 3, 11, 1, 0xE8C25A)
            cv.set(Int(ex) + 3, 9, 0xFFE45C); cv.set(Int(ex) + 2, 9, 0xFFF3A0); cv.set(Int(ex) + 3, 10, 0xFFF3A0)
        }
        return cv.image
    }

    /// Ambient life that wanders across an island now and then.
    static func critter(_ b: Biome, frame: Int) -> CGImage {
        let hop = frame % 2 == 1
        switch b {
        case .snow:   // a little penguin
            return Effects.pixels(hop ? [".kk.", "kwwk", "kwwk", "o..o"] : [".kk.", "kwwk", "kwwk", ".oo."], ["k": 0x2A2E3A, "w": 0xFFFFFF, "o": 0xF2A33A])
        case .desert: // a lizard
            return Effects.pixels(hop ? ["....gg", "ggggg.", ".g.g.."] : ["....gg", "ggggg.", "g...g."], ["g": 0x9CB45A])
        case .jungle: // a frog
            return Effects.pixels(hop ? ["g.g.", "gggg", "g..g"] : ["g.g.", "gggg", ".gg."], ["g": 0x4FC24A])
        case .glowshroom, .crystal, .sky: // a glowing snail
            return Effects.pixels(hop ? [".cc.", "cssc", "ssss"] : [".cc.", "cssc", ".sss"], ["c": b == .crystal ? 0xD58CFF : 0x6FF2FF, "s": 0xCFE6FF])
        default:      // a bunny
            return Effects.pixels(hop ? ["w.w.", "www.", "wwww", "w..w"] : ["w.w.", "www.", "wwww", ".ww."], ["w": 0xF4EFE6])
        }
    }
}

/// What a Gremlet builds while Claude works: one block per file Claude edits, from the ground up, to a blueprint
/// that suits its island (a cottage in the meadow, an igloo in the snow, a pyramid in the desert, a mossy temple in
/// the jungle, a mushroom house, a crystal spire, a lighthouse in the sky). A long session finishes the building;
/// then lights come on and smoke curls from the chimney.
enum BuildArt {
    static let block = 5   // art pixels per block (15 points)

    /// Rows from the top down; "." is empty. Placement order is bottom row first, left to right.
    static func blueprint(_ b: Biome) -> [String] {
        switch b {
        case .meadow, .autumn, .cherry:
            return ["...c..", "..rrr.", ".rrrrr", "rrrrrr", "wwgwgw", "wwdwww", "wwdwww", "ssssss"]
        case .snow:
            return ["..iii..", ".iiiii.", "iiiiiii", "iigiiii", "iiddiii", "iiddiii"]
        case .desert:
            return ["...a...", "..aaa..", "..aga..", ".aaaaa.", "aaadaaa", "aaadaaa"]
        case .jungle:
            return ["..*.*..", ".mmmmm.", ".mgmgm.", "mmmmmmm", "mmmdmmm", "mmmdmmm", "sssssss"]
        case .glowshroom:
            return [".kkkkk.", "kkkkkkk", "kkkkkkk", "..tgt..", "..tdt..", "..tdt.."]
        case .crystal:
            return ["...x..", "..xxx.", "..xgx.", "..ttt.", "..tgt.", "..ttt.", ".tdtt.", "ssssss"]
        case .sky:
            return ["..L..", ".rrr.", ".wgw.", ".www.", ".wgw.", ".www.", ".wdw.", "ooooo"]
        }
    }

    /// The cells in placement order (bottom-up, left to right), as (column, row-from-bottom, kind).
    static func cells(_ b: Biome) -> [(Int, Int, Character)] {
        let rows = blueprint(b)
        var out: [(Int, Int, Character)] = []
        for (ri, row) in rows.reversed().enumerated() {
            for (ci, ch) in row.enumerated() where ch != "." { out.append((ci, ri, ch)) }
        }
        return out
    }

    static func size(_ b: Biome) -> (cols: Int, rows: Int) { let r = blueprint(b); return (r.map(\.count).max() ?? 0, r.count) }

    static func image(_ b: Biome, blocks: Int, night: Bool, overgrowth: Int = 0, seed: UInt64 = 1, month: Int? = nil) -> CGImage? {
        let cs = cells(b)
        let n = min(blocks, cs.count)
        guard n > 0 else { return nil }
        let (cols, rows) = size(b)
        var cv = PixelCanvas(cols * block, rows * block)
        let done = blocks >= cs.count
        for (i, cell) in cs.prefix(n).enumerated() {
            draw(&cv, cell.2, x: cell.0 * block, y: cell.1 * block, b: b, lit: done && night, i: i)
        }
        cv.outline(0.7)
        if overgrowth > 0 { overgrow(&cv, stage: overgrowth, seed: seed) }
        if let m = month { dressForSeason(&cv, month: m, seed: seed) }
        return cv.image
    }

    /// Nature slowly takes the building back: moss creeping over walls, ivy climbing from the ground, flowers on the
    /// roof, and after a week a sapling sprouting from the top. Stage 1...4.
    static func overgrow(_ cv: inout PixelCanvas, stage: Int, seed: UInt64) {
        var r = ArtRNG(s: seed &+ 404)
        let w = cv.w, h = cv.h
        func solid(_ x: Int, _ y: Int) -> Bool { cv.get(x, y) != nil }
        // Moss clumps on edges and roof tops.
        for _ in 0..<(w * h / 10 * stage) {
            let x = Int(r.range(0, Double(w))), y = Int(r.range(0, Double(h)))
            guard solid(x, y), !solid(x, y + 1) || !solid(x - 1, y) || !solid(x + 1, y) else { continue }
            let c: UInt32 = r.next() < 0.5 ? 0x5E9E46 : 0x7DBE52
            cv.set(x, y, c)
            if solid(x + 1, y) { cv.set(x + 1, y, 0x4F8A3A) }
            if solid(x, y - 1) && r.next() < 0.5 { cv.set(x, y - 1, 0x4F8A3A) }
        }
        // Ivy climbing from the ground, with leaves either side.
        if stage >= 2 {
            for _ in 0..<(stage * 2) {
                var x = Int(r.range(0, Double(w)))
                let height = Int(r.range(4, Double(h) * (0.3 + 0.17 * Double(stage))))
                for y in 0..<height {
                    if solid(x, y) { cv.set(x, y, 0x3E7A34) }
                    if y % 2 == 0 {
                        let side = (y / 2) % 2 == 0 ? -1 : 1
                        if solid(x + side, y) { cv.set(x + side, y, 0x7DBE52) }
                    }
                    if r.next() < 0.25 { x += r.next() < 0.5 ? -1 : 1 }
                }
            }
        }
        // Flowers along the roofline (they sit just above it).
        if stage >= 3 {
            for x in 1..<(w - 1) where r.next() < 0.3 {
                var top = h - 1
                while top > 0 && !solid(x, top) { top -= 1 }
                guard top > 0, top + 1 < h else { continue }
                let petal: UInt32 = [0xFF8FB1, 0xFFE45C, 0xFFFFFF, 0xB98CFF][Int(r.range(0, 3.99))]
                cv.set(x, top + 1, petal)
                if r.next() < 0.5 { cv.set(x, top, 0x5E9E46) }
            }
        }
        // A sapling growing out of the roof.
        if stage >= 4 {
            let x = w / 2 + Int(r.range(-4, 4))
            var top = h - 1
            while top > 0 && !solid(x, top) { top -= 1 }
            if top > 0 && top + 5 < h {
                cv.rect(x, top + 1, 1, 3, 0x6B4428)
                cv.blob(Double(x) + 0.5, Double(top + 5), 3.2, 2.2, base: 0x5E9E46, light: 0x8BD66A, shade: 0x3E7A34)
            }
        }
    }

    /// Seasons on the village: snow piled on every ledge in winter, blossoms in spring, fallen leaves in autumn.
    static func dressForSeason(_ cv: inout PixelCanvas, month: Int, seed: UInt64) {
        var r = ArtRNG(s: seed &+ 77)
        func solid(_ x: Int, _ y: Int) -> Bool { cv.get(x, y) != nil }
        for x in 0..<cv.w {
            for y in stride(from: cv.h - 2, through: 0, by: -1) where solid(x, y) && !solid(x, y + 1) {
                switch month {
                case 12, 1, 2:
                    // Snow on every upward-facing edge (roofs, sills, the top of the door frame).
                    cv.set(x, y + 1, 0xFFFFFF)
                    if r.next() < 0.5 && y + 2 < cv.h { cv.set(x, y + 2, 0xEAF4FF) }
                case 3, 4, 5:
                    if r.next() < 0.22 { cv.set(x, y + 1, r.next() < 0.6 ? 0xFFB6D9 : 0xFFFFFF) }
                case 9, 10, 11:
                    if r.next() < 0.2 { cv.set(x, y + 1, [0xE8862C, 0xC2562C, 0xF2C94C][Int(r.range(0, 2.99))]) }
                default: break
                }
            }
        }
    }

    /// How overgrown a house is after this many hours.
    static func overgrowthStage(hours: Double) -> Int { hours < 6 ? 0 : hours < 24 ? 1 : hours < 72 ? 2 : hours < 168 ? 3 : 4 }

    /// Where (in art pixels, from the bottom-left) the most recent block went, for the "pop" effect.
    static func lastCell(_ b: Biome, blocks: Int) -> (x: Int, y: Int)? {
        let cs = cells(b)
        guard blocks > 0 else { return nil }
        let c = cs[min(blocks, cs.count) - 1]
        return (c.0 * block + block / 2, c.1 * block + block / 2)
    }

    static func isComplete(_ b: Biome, blocks: Int) -> Bool { blocks >= cells(b).count }

    /// Height (art pixels) of what's been built so far: smoke and flags go on top of that, not the empty blueprint.
    static func builtHeight(_ b: Biome, blocks: Int) -> Int {
        let placed = cells(b).prefix(max(0, blocks))
        return ((placed.map(\.1).max() ?? -1) + 1) * block
    }

    private static func draw(_ cv: inout PixelCanvas, _ k: Character, x: Int, y: Int, b: Biome, lit: Bool, i: Int) {
        let s = block
        func fill(_ c: UInt32, _ hi: UInt32, _ lo: UInt32) {
            cv.rect(x, y, s, s, c)
            cv.rect(x, y + s - 1, s, 1, hi)      // lit top edge
            cv.rect(x + s - 1, y, 1, s, lo)      // shaded side
        }
        switch k {
        case "w": fill(0xC98B4A, 0xE0A866, 0x8A5A35); cv.rect(x, y + 2, s, 1, 0xA9743F)               // planks
        case "s": fill(0x8E8B83, 0xB8B6AE, 0x5E5B55); cv.set(x + 1, y + 1, 0x6E6B65)                   // stone
        case "r":
            let roof: (UInt32, UInt32, UInt32) = b == .cherry ? (0xE07AA8, 0xF7B6D2, 0xA84E7A) : b == .autumn ? (0xC2562C, 0xE07A44, 0x8A3A1E)
                : b == .sky ? (0x4A6FD0, 0x7FA0F0, 0x2E4A9A) : (0xC23B3B, 0xE06060, 0x8A2626)
            fill(roof.0, roof.1, roof.2); cv.rect(x, y + 1, s, 1, roof.2)
        case "g": fill(lit ? 0xFFE08A : 0x9FD8F0, lit ? 0xFFF3C4 : 0xD6F2FF, 0x5E5B55); cv.rect(x + 2, y, 1, s, 0x5E5B55)   // window
        case "d": fill(0x6B4428, 0x8A5A35, 0x4A2E1A); if (i % 2) == 0 { cv.set(x + 3, y + 2, 0xF2C94C) }    // door + knob
        case "c": fill(0x8E8B83, 0xB8B6AE, 0x5E5B55)                                                      // chimney
        case "i": fill(0xDDF2FF, 0xFFFFFF, 0xA9CFEA); cv.set(x + 1, y + 3, 0xFFFFFF)                       // ice brick
        case "a": fill(0xE8C98A, 0xF7E2B0, 0xC29A5A); cv.rect(x, y + 2, s, 1, 0xD6B070)                    // sandstone
        case "m": fill(0x7D8A6A, 0x9FB088, 0x55604A); cv.set(x + 1, y + 3, 0x5FB84A); cv.set(x + 3, y + 1, 0x4FA03A)   // mossy stone
        case "*": cv.rect(x + 2, y, 1, 3, 0x6B4428); cv.blob(Double(x) + 2.5, Double(y) + 3.5, 1.4, 1.4, base: 0xFFB43A, light: 0xFFF3A0)  // torch
        case "k": fill(lit ? 0x5FE8FF : 0x3FA8E0, 0xBFFFFF, 0x2A6FA8); if (x / s + y / s) % 2 == 0 { cv.set(x + 2, y + 2, 0xEAFBFF) }   // mushroom cap
        case "t": fill(0xD8D2E6, 0xF2EEFA, 0xA8A2B8)                                                      // stem / tower
        case "x": fill(0xB57AF2, 0xF3D9FF, 0x7E4AB8); cv.set(x + 2, y + 2, 0xFFFFFF)                       // crystal
        case "o": fill(0xF5FAFF, 0xFFFFFF, 0xC6D6EA)                                                      // cloud
        case "L": cv.blob(Double(x) + 2.5, Double(y) + 2.5, 2.4, 2.4, base: lit ? 0xFFF3A0 : 0xFFD45E, light: 0xFFFFFF)   // the lamp
        default: break
        }
    }
}

/// Plank bridges and the grappling hook.
enum BridgeArt {
    static func image(blocks: Int, fromLeft: Bool, total: Int) -> CGImage {
        let n = max(1, min(blocks, total)), bw = BuildArt.block
        var cv = PixelCanvas(n * bw, 7)
        for i in 0..<n {
            let x = i * bw
            // Deck plank (bottom 2 rows), a post at every other block, and the rope rail on top.
            cv.rect(x, 0, bw, 2, i % 2 == 0 ? 0xC98B4A : 0xB97E42)
            cv.rect(x + bw - 1, 0, 1, 2, 0x8A5A35)
            if i % 2 == 0 { cv.rect(x + 1, 2, 1, 4, 0x8A5A35) }
            cv.rect(x, 5, bw, 1, 0xD9C08A)
        }
        cv.rect(0, 0, n * bw, 1, 0x7A5232)
        if !fromLeft { cv = flipped(cv) }
        return cv.image
    }

    static func flipped(_ c: PixelCanvas) -> PixelCanvas {
        var out = PixelCanvas(c.w, c.h)
        for y in 0..<c.h { for x in 0..<c.w { if let p = c.get(x, y) { out.set(c.w - 1 - x, y, p) } } }
        return out
    }

    static let plank = Effects.pixels(["wwwww", "ddddd"], ["w": 0xC98B4A, "d": 0x8A5A35])
    static let hook = Effects.pixels([
        ".kkk.",
        "k...k",
        "k..k.",
        "..k..",
    ], ["k": 0xB8C2CC])
}

/// Weather over a Claude session's island.
enum WeatherArt {
    static func cloud(storm: Bool) -> CGImage {
        var cv = PixelCanvas(26, 12)
        let (b, l, s): (UInt32, UInt32, UInt32) = storm ? (0x6E7790, 0x9AA3BA, 0x4A5168) : (0xDCE6F2, 0xFFFFFF, 0xB4C2D6)
        for (x, y, r) in [(7.0, 5.0, 5.0), (13, 7, 6), (19, 5, 5), (11, 3, 4), (16, 3, 4)] { cv.blob(x, y, r, r * 0.8, base: b, light: l, shade: s) }
        cv.outline(0.7)
        return cv.image
    }
    static let rainbow: CGImage = {
        var cv = PixelCanvas(40, 21)
        let bands: [UInt32] = [0xFF6B6B, 0xFFB45C, 0xFFE45C, 0x7BD66A, 0x5FB8FF, 0xB98CFF]
        for y in 0..<21 { for x in 0..<40 {
            let d = ((Double(x) - 19.5) * (Double(x) - 19.5) + Double(y) * Double(y)).squareRoot()
            let k = Int(20 - d)
            if k >= 0 && k < bands.count { cv.set(x, y, bands[k]) }
        }}
        return cv.image
    }()
    static let sun = Effects.pixels([
        "..y..",
        ".yYy.",
        "yYYYy",
        ".yYy.",
        "..y..",
    ], ["y": 0xFFC845, "Y": 0xFFF3A0])
    static let block = Effects.pixels(["wwww", "wddw", "wwww"], ["w": 0xC98B4A, "d": 0xA9743F])
    static let scroll = Effects.pixels(["kwwwk", ".www.", ".www.", "kwwwk"], ["k": 0xC98B4A, "w": 0xFFF6DA])
}

/// Little extras with a storybook feel.
enum StoryArt {
    /// A big leaf held overhead, for gliding down from high places.
    static let gliderLeaf: CGImage = {
        var cv = PixelCanvas(16, 7)
        cv.blob(8, 4, 7.6, 2.6, base: 0x6CC04A, light: 0xA6E36E, shade: 0x3F8A3A)
        cv.line(1, 4, 15, 4, 0x3E7A34)
        cv.rect(8, 0, 1, 3, 0x6B4428)
        cv.outline(0.7)
        return cv.image
    }()

    /// A shy night spirit: a round glowing seed with two leaf ears (original design).
    static func spirit(frame: Int) -> CGImage {
        Effects.pixels(frame % 2 == 0 ? [
            "l....l",
            ".l..l.",
            ".gggg.",
            "gGkGkg",
            "gGGGGg",
            ".gggg.",
        ] : [
            ".l..l.",
            ".l..l.",
            ".gggg.",
            "gGkGkg",
            "gGGGGg",
            ".gggg.",
        ], ["l": 0x8FD67A, "g": 0xCFF5C0, "G": 0xEFFFE8, "k": 0x3A5A3A])
    }

    /// A little cooking pot for the campfire.
    static let pot = Effects.pixels([
        ".kkkkk.",
        "kpppppk",
        "kpppppk",
        ".kkkkk.",
        "..f.f..",
        ".fFfFf.",
    ], ["k": 0x3A3A44, "p": 0x5A5A68, "f": 0xFF9A3A, "F": 0xFFE45C])
}

/// The mine, the gems, the sky ferry and the festival lanterns.
enum AdventureArt {
    /// A grassy mound with a timber-framed mine entrance, a lantern and a little cart on rails.
    static func mine(night: Bool) -> CGImage {
        var cv = PixelCanvas(40, 22)
        for x in 0..<40 {
            let u = (Double(x) + 0.5) / 40 * 2 - 1
            let top = Int(20 * pow(max(0, 1 - u * u), 0.6))
            for y in 0..<max(1, top) {
                let c: UInt32 = y >= top - 1 ? 0x5DBB46 : y >= top - 2 ? (x % 3 == 0 ? 0x5DBB46 : 0x8A5A35) : ((x * 7 + y * 3) % 11 == 0 ? 0x6B4428 : (y < 5 && (x + y) % 9 == 0 ? 0xF2C94C : 0x8A5A35))
                cv.set(x, y, c)
            }
        }
        cv.outline(0.62)
        // Entrance: dark opening framed in timber.
        cv.rect(15, 0, 10, 11, 0x1E1A22)
        cv.rect(14, 0, 2, 12, 0x7A5232); cv.rect(24, 0, 2, 12, 0x7A5232); cv.rect(13, 11, 14, 2, 0x8A5A35)
        // Rails and a cart of ore.
        cv.rect(4, 0, 34, 1, 0x6E6A78)
        cv.rect(28, 1, 7, 3, 0x7A5232); cv.rect(29, 4, 5, 1, 0x9C9488); cv.set(30, 4, 0xD58CFF); cv.set(32, 4, 0x8FE3FF)
        // A lantern by the door.
        cv.rect(27, 8, 1, 3, 0x5E3B22); cv.blob(27.5, 11.5, 1.4, 1.4, base: night ? 0xFFF3A0 : 0xFFC845)
        return cv.image
    }

    static func gem(_ k: GemKind) -> CGImage {
        let (a, b): (UInt32, UInt32) = {
            switch k {
            case .amber: return (0xF2A33A, 0xFFE09A)
            case .emerald: return (0x3FBF6A, 0xA6F0BF)
            case .sapphire: return (0x3F7FE0, 0xA9D0FF)
            case .amethyst: return (0x9A5AE0, 0xE0C2FF)
            case .starstone: return (0xFFD84A, 0xFFFFFF)
            }
        }()
        return Effects.pixels([".bb.", "baab", "aaaa", ".aa."], ["a": a, "b": b])
    }
    static let pebble = Effects.pixels([".gg.", "gGgg", ".gg."], ["g": 0x9C9488, "G": 0xC9C2B4])

    /// The sky ferry: a little wooden boat under a patched cloth balloon, with a turning propeller.
    static func ferry(frame: Int) -> CGImage {
        var cv = PixelCanvas(44, 34)
        // Balloon
        cv.blob(22, 26, 15, 7, base: 0xE8D7B0, light: 0xFFF4DA, shade: 0xC2A878)
        cv.rect(14, 25, 4, 3, 0xD9855A); cv.rect(27, 27, 3, 3, 0x7FB0D9)   // patches
        // Ropes
        cv.line(10, 19, 9, 10, 0x8A6A4A); cv.line(34, 19, 35, 10, 0x8A6A4A); cv.line(22, 19, 22, 10, 0x8A6A4A)
        // Hull
        for y in 0..<9 { let inset = max(0, 4 - y); cv.rect(4 + inset, y, 36 - inset * 2, 1, y > 6 ? 0xB97E42 : (y % 3 == 0 ? 0x8A5A35 : 0xA9743F)) }
        cv.rect(4, 8, 36, 1, 0xD9A066)            // deck edge
        cv.rect(6, 9, 1, 2, 0x8A5A35); cv.rect(37, 9, 1, 2, 0x8A5A35); cv.rect(6, 10, 32, 1, 0xC9A36A)   // rail
        // Portholes
        cv.set(14, 4, 0xBFE6FF); cv.set(22, 4, 0xBFE6FF); cv.set(30, 4, 0xBFE6FF)
        // Propeller at the stern
        cv.rect(1, 4, 3, 1, 0x6E6A78)
        if frame % 2 == 0 { cv.rect(0, 1, 1, 7, 0xC8C8D0) } else { cv.rect(0, 4, 1, 1, 0xC8C8D0); cv.rect(0, 2, 1, 1, 0x9A9AA6); cv.rect(0, 6, 1, 1, 0x9A9AA6) }
        cv.outline(0.6)
        return cv.image
    }

    static let lantern: CGImage = {
        var cv = PixelCanvas(7, 9)
        cv.blob(3.5, 5, 3.3, 3.8, base: 0xFF9A4A, light: 0xFFE09A, shade: 0xE0703A)
        cv.rect(2, 0, 3, 1, 0x8A5A35); cv.rect(2, 8, 3, 1, 0x8A5A35)
        return cv.image
    }()
}

/// The traveling merchant and the things the village can buy from it.
enum VillageArt {
    /// A small hooded wanderer under a towering backpack hung with pots, a lantern and a bedroll (original design).
    static func merchant(frame: Int) -> CGImage {
        var cv = PixelCanvas(18, 26)
        // Backpack stack
        cv.rect(2, 8, 10, 14, 0x8A5A35); cv.rect(3, 9, 8, 12, 0xA9743F)
        cv.rect(2, 21, 10, 3, 0xD9C08A)                       // bedroll on top
        cv.blob(3, 14, 2, 2, base: 0x6E6A78)                  // pot
        cv.rect(11, 15, 1, 3, 0x5E3B22); cv.blob(11.5, 14, 1.3, 1.3, base: 0xFFC845)   // lantern
        // Hooded body
        cv.blob(13, 9, 4.2, 6, base: 0x5A6E8A, light: 0x7F95B3, shade: 0x3E4E66)
        cv.blob(14, 13.5, 3.2, 3, base: 0x5A6E8A, light: 0x7F95B3, shade: 0x3E4E66)
        cv.rect(14, 12, 3, 2, 0x1E1A22); cv.set(15, 13, 0xFFE45C); cv.set(16, 13, 0xFFE45C)   // shadowed face, glinting eyes
        // Walking stick and feet
        cv.rect(17, 0, 1, 15, 0x7A5232)
        if frame % 2 == 0 { cv.rect(11, 0, 2, 2, 0x3E4E66); cv.rect(14, 0, 2, 2, 0x3E4E66) } else { cv.rect(12, 0, 2, 2, 0x3E4E66); cv.rect(13, 1, 2, 1, 0x3E4E66) }
        cv.outline(0.6)
        return cv.image
    }

    static func item(_ i: VillageItem, night: Bool, frame: Int) -> CGImage {
        switch i {
        case .lamps:
            var cv = PixelCanvas(50, 20)
            for x in [4, 24, 44] {
                cv.rect(x, 0, 1, 15, 0x3A3A44); cv.rect(x - 1, 0, 3, 1, 0x3A3A44)
                cv.blob(Double(x) + 0.5, 16, 2, 2.2, base: night ? 0xFFF3A0 : 0xE8D7A0, light: 0xFFFFFF)
                cv.rect(x - 2, 18, 5, 1, 0x3A3A44)
            }
            // A garland strung between them
            for x in 4...44 { let y = 13 - Int(2 * sin(Double(x - 4) / 20 * .pi).magnitude); cv.set(x, y, (x % 4 == 0) ? (night ? 0xFFB45C : 0xC23B3B) : 0x6B4428) }
            return cv.image
        case .well:
            var cv = PixelCanvas(22, 24)
            cv.rect(2, 0, 18, 8, 0x8E8B83); for x in stride(from: 2, to: 20, by: 4) { cv.rect(x, 0, 1, 8, 0x6E6B65) }; cv.rect(2, 4, 18, 1, 0x6E6B65)
            cv.rect(4, 8, 1, 10, 0x7A5232); cv.rect(17, 8, 1, 10, 0x7A5232)
            for y in 0..<4 { cv.rect(1 + y, 18 + y, 20 - y * 2, 1, 0xC23B3B) }
            cv.rect(10, 10, 2, 3, 0x8A5A35); cv.line(11, 13, 11, 17, 0xD9C08A)
            cv.rect(3, 7, 16, 1, 0x3F7FE0)
            cv.outline(0.6)
            return cv.image
        case .spring:
            var cv = PixelCanvas(40, 12)
            cv.blob(20, 4, 19, 4.5, base: 0x8E8B83, light: 0xB8B6AE, shade: 0x5E5B55)
            cv.blob(20, 5, 16, 3, base: night ? 0x3F8FD0 : 0x6FC8E8, light: 0xBFF0FF)
            for (x, y) in [(6.0, 8.0), (34, 8), (12, 9)] { cv.blob(x, y, 2.5, 2, base: 0x9C9488, light: 0xC9C2B4) }
            cv.outline(0.7)
            return cv.image
        case .windmill:
            var cv = PixelCanvas(26, 50)
            for y in 0..<30 { let inset = y / 8; cv.rect(6 + inset, y, 14 - inset * 2, 1, y % 6 == 0 ? 0xB8B6AE : 0xE8DCC4) }
            cv.rect(9, 0, 4, 7, 0x6B4428); cv.rect(14, 14, 3, 4, night ? 0xFFE08A : 0x9FD8F0)
            for y in 30..<34 { cv.rect(5 + (y - 30), y, 16 - (y - 30) * 2, 1, 0xC23B3B) }
            // Sails turn (two frames)
            let c = (13.0, 31.0)
            let arms: [(Double, Double)] = frame % 2 == 0 ? [(1, 1), (-1, -1), (1, -1), (-1, 1)] : [(1.4, 0), (-1.4, 0), (0, 1.4), (0, -1.4)]
            for (dx, dy) in arms { cv.line(c.0, c.1, c.0 + dx * 11, c.1 + dy * 11, 0xF4EFE6, width: 2) }
            cv.blob(c.0, c.1, 1.6, 1.6, base: 0x6B4428)
            cv.outline(0.6)
            return cv.image
        case .arch:
            var cv = PixelCanvas(30, 32)
            for (x, _) in [(2, 0), (25, 0)] { cv.rect(x, 0, 3, 24, 0x7A5232) }
            for k in 0..<28 {
                let a = Double(k) / 27 * .pi
                let x = 15 - cos(a) * 12, y = 22 + sin(a) * 8
                cv.blob(x, y, 2.2, 2, base: 0x5E9E46, light: 0x8BD66A)
                if k % 3 == 0 { cv.set(Int(x), Int(y) + 1, [0xFF8FB1, 0xFFE45C, 0xFFFFFF][k % 3 == 0 ? (k / 3) % 3 : 0]) }
            }
            if night { for k in stride(from: 2, to: 28, by: 5) { let a = Double(k) / 27 * .pi; cv.set(Int(15 - cos(a) * 12), Int(22 + sin(a) * 8) - 2, 0xFFF3A0) } }
            cv.outline(0.7)
            return cv.image
        }
    }
}

enum OwnerArt {
    /// A little pennant on the roof in the owner's colour (from its element).
    static func pennant(_ color: UInt32) -> CGImage {
        Effects.pixels(["kcc..", "kcccc", "kcc..", "k....", "k...."], ["k": 0x5E3B22, "c": color])
    }
    static func color(for speciesID: String) -> UInt32 {
        let palette: [UInt32] = [0xE8574A, 0x3F7FE0, 0x5DBB46, 0xF2C94C, 0xB57AF2, 0xF07AA6, 0x3FC0B0, 0xE8862C]
        let h = speciesID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[h % palette.count]
    }
}
