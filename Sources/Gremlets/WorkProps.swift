import AppKit
import GremletsCore

/// Pixel art for the Claude buddy's creations: a potted plant that grows, a painting that fills in, a block tower
/// that goes up, plus the ladder. Drawn in code like the other effects (1 art pixel = 3 points on screen).
enum PropArt {
    typealias Grid = [[UInt32?]]

    static func image(_ g: Grid) -> CGImage {
        let h = g.count, w = g.map(\.count).max() ?? 1
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in g.enumerated() {
            for (x, px) in row.enumerated() {
                guard let hex = px else { continue }
                let i = (y * w + x) * 4
                buf[i] = UInt8(hex >> 16 & 0xFF); buf[i + 1] = UInt8(hex >> 8 & 0xFF); buf[i + 2] = UInt8(hex & 0xFF); buf[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(buf) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Rows of characters → grid, padding every row to the same width.
    static func grid(_ rows: [String], _ palette: [Character: UInt32]) -> Grid {
        let w = rows.map(\.count).max() ?? 0
        return rows.map { row in
            var out = row.map { palette[$0] }
            while out.count < w { out.append(nil) }
            return out
        }
    }

    // MARK: Garden

    static let gardenPalette: [Character: UInt32] = [
        "p": 0xD0703F, "P": 0x9A4A28, "g": 0x6CC04A, "G": 0x3E8E3A, "f": 0xFF8FBF, "F": 0xE0588F, "y": 0xFFD84A,
    ]
    static let pot = [
        "pppppppppppp",
        "PPPPPPPPPPPP",
        ".pppppppppp.",
        ".pppppppppp.",
        "..pppppppp..",
    ]
    /// Plant above the pot, 10 rows, for stages 0 (bare soil) ... 5 (in bloom).
    static let plants: [[String]] = [
        [],
        ["....g.g.....", ".....G......", ".....G......"],
        ["..ggg.g.ggg.", "...ggGGGgg..", ".....G......", ".....G......"],
        ["......g.....", ".....ggg....", "..gg..G..gg.", ".gggg.G.gggg", "..ggGGGGGgg.", ".....G......", "...ggG......", "..gggG......", ".....G......"],
        ["......f.....", ".....fGf....", "......G.....", "..gg..G..gg.", ".ggggGG.gggg", "..gg..GGGgg.", "......G.....", "...ggGG.....", "..gggGG.....", "......G....."],
        ["....f.f.f...", "...fFfyfFf..", "....ffyff...", "...fFfffFf..", "....f.G.f...", ".gg...G..gg.", "ggggG.G.Gggg", ".ggGGGGGGgg.", "...ggGG.....", "......G....."],
    ]
    static var gardenCache: [Int: CGImage] = [:]
    static func garden(stage: Int) -> CGImage {
        if let c = gardenCache[stage] { return c }
        var rows = Array(repeating: "", count: 10 - plants[stage].count) + plants[stage] + pot
        rows = rows.map { $0.isEmpty ? "............" : $0 }
        let img = image(grid(rows, gardenPalette))
        gardenCache[stage] = img
        return img
    }

    // MARK: Painting

    static let paintPalette: [Character: UInt32] = [
        "b": 0x8EC9F0, "y": 0xFFD84A, "g": 0x6CC04A, "G": 0x3E8E3A, "n": 0x2B3A6B, "m": 0xF4F1C9, "W": 0xFFFFFF,
        "r": 0xFF6F7E, "c": 0xF7F3E8, "w": 0xA0703F, "d": 0x6E4A26, "o": 0xFFB35C,
    ]
    static let pictures: [[String]] = [
        ["bbbbbbbbbbyy", "bbbbbbbbbyyy", "bbbbbbbbbbyy", "bbbbbbbbbbbb", "bbbgggbbbbbb", "bbgggggbbGGb", "bgggggggGGGG", "ggggggGGGGGG", "GGGGGGGGGGGG"],
        ["nnnnnnnnnnnn", "nnWnnnnnnmmn", "nnnnnnWnmmmm", "nnnnnnnnnmmn", "nWnnnnnnnnnn", "nnnnnWnnnnnn", "nnnnnnnnnnnn", "GGGnnnnnGGGG", "GGGGGGGGGGGG"],
        ["cccccccccccc", "ccrrrcrrrccc", "crrrrrrrrrcc", "crrrrrrrrrcc", "ccrrrrrrrccc", "cccrrrrrcccc", "ccccrrrccccc", "cccccrcccccc", "cccccccccccc"],
        ["oooooooooooo", "oooooyyooooo", "ooooyyyyoooo", "rrrryyyyrrrr", "rrrrrrrrrrrr", "nnnnnnnnnnnn", "nnbnnnnnbnnn", "nnnnnbnnnnnn", "nnnnnnnnnnnn"],
    ]
    /// Easel with a canvas; `revealed` of the 108 picture pixels painted in, in a per-job random order.
    static func painting(picture: Int, revealed: Int, seed: UInt64) -> CGImage {
        let pic = grid(pictures[picture % pictures.count], paintPalette)
        var order = Array(0..<108)
        var rng = SplitMix64(seed: seed)
        order.shuffle(using: &rng)
        let shown = Set(order.prefix(max(0, min(108, revealed))))
        let wood = paintPalette["w"]!, dark = paintPalette["d"]!, blank = paintPalette["c"]!
        var g: Grid = []
        g.append([nil, nil, nil, nil, nil, nil, wood, wood, nil, nil, nil, nil, nil, nil])          // easel top
        g.append(Array(repeating: dark, count: 14))                                                // frame
        for y in 0..<9 {
            var row: [UInt32?] = [dark]
            for x in 0..<12 { row.append(shown.contains(y * 12 + x) ? pic[y][x] : blank) }
            row.append(dark)
            g.append(row)
        }
        g.append(Array(repeating: dark, count: 14))
        let legs: [[Int]] = [[2, 6, 11], [2, 6, 11], [1, 6, 12], [1, 6, 12], [0, 6, 13]]
        for l in legs { g.append((0..<14).map { l.contains($0) ? wood : nil }) }
        return image(g)
    }

    // MARK: Block tower

    static let blockColors: [UInt32] = [0xFF6F7E, 0xFFB35C, 0xFFD84A, 0x6CC04A, 0x6FB8F0, 0xA98BEA, 0xFF8FBF]
    static func tower(blocks: Int, finished: Bool, seed: UInt64) -> CGImage {
        var rng = SplitMix64(seed: seed)
        let w = 10
        var rows: Grid = []
        // Built bottom-up, then flipped (row 0 = top).
        for b in 0..<blocks {
            let color = blockColors[Int((seed &+ UInt64(b)) % UInt64(blockColors.count))]
            let shade = ((color & 0xFEFEFE) >> 1) + 0x7F7F7F   // lighter top edge
            let off = b == 0 ? 1 : Int(rng.next() % 3)
            for r in 0..<3 {
                var row: [UInt32?] = Array(repeating: nil, count: w)
                for x in off..<(off + 7) { row[x] = r == 0 ? shade : color }
                rows.append(row)
            }
        }
        if finished {
            let star: UInt32 = 0xFFE066
            rows.append((0..<w).map { [3, 4, 5].contains($0) ? star : nil })
            rows.append((0..<w).map { [2, 3, 4, 5, 6].contains($0) ? star : nil })
            rows.append((0..<w).map { $0 == 4 ? star : nil })
        }
        return image(rows.reversed())
    }

    // MARK: Ladder

    static func ladder(heightPx: Int) -> CGImage {
        let rail: UInt32 = 0xB07A44, rung: UInt32 = 0xD9A066
        var g: Grid = []
        for y in 0..<max(4, heightPx) {
            var row: [UInt32?] = Array(repeating: nil, count: 9)
            row[0] = rail; row[8] = rail
            if y % 5 == 2 { for x in 1..<8 { row[x] = rung } }
            g.append(row)
        }
        return image(g)
    }
}
