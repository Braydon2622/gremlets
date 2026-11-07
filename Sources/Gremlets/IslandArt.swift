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
        case .sky:        return (0x6CC04A, 0x9BE36A, 0xF5FAFF, 0xDCE9F5, 0xC6D6EA, 0xA9BCD6, 0xFFE45C)
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
                if b == .sky {
                    // A cloud with a thin turf lid.
                    c = d == 0 ? pal.topLight : d == 1 ? pal.top : (d > bottom[x] - 3 ? pal.stoneDark : (d % 3 == 0 && x % 5 == 2 ? pal.stone : pal.soil))
                } else if d == 0 {
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
                case .sky: c = k == len - 1 ? 0xBFE6FF : 0xDCE9F5                          // drizzle
                }
                cv.set(x, y0 - k, c)
            }
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

    static func image(_ b: Biome, blocks: Int, night: Bool) -> CGImage? {
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
        return cv.image
    }

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
