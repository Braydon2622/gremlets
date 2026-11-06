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

    // MARK: Knitting

    static let yarnPairs: [(UInt32, UInt32)] = [(0xFF8FBF, 0xFFF1F6), (0x6FB8F0, 0xFFF6D8), (0xFFB35C, 0xFFE9C9), (0x8FD6A2, 0xF7F3E8), (0xA98BEA, 0xFFE066)]
    /// A little knitting frame: the scarf hangs from a rod and grows row by row; fringe once it's done.
    static func knitting(rows: Int, finished: Bool, seed: UInt64) -> CGImage {
        let (a, b) = yarnPairs[Int(seed % UInt64(yarnPairs.count))]
        let wood: UInt32 = 0xA0703F, dark: UInt32 = 0x6E4A26
        var g: Grid = Array(repeating: Array(repeating: nil, count: 15), count: 16)
        for x in 0..<15 { g[0][x] = wood }
        for y in 1..<16 { g[y][1] = dark; g[y][12] = dark }
        let n = max(1, min(10, rows))
        for y in 0..<n { for x in 4...9 { g[1 + y][x] = (y / 2) % 2 == 0 ? a : b } }
        if finished { for x in stride(from: 4, through: 9, by: 2) { g[1 + n][x] = a; g[2 + n][x + 1] = a } }
        // Yarn ball on the floor.
        let ball: [(Int, Int)] = [(10, 13), (11, 13), (12, 13), (9, 14), (10, 14), (11, 14), (12, 14), (13, 14), (9, 15), (10, 15), (11, 15), (12, 15), (13, 15)]
        for (x, y) in ball { g[y][x] = a }
        g[14][11] = b; g[13][12] = b
        return image(g)
    }

    // MARK: Shelf & balloon

    /// A wooden shelf `widthPx` wide with two brackets underneath. The top row is the surface Gremlets stand on.
    static func shelf(widthPx: Int) -> CGImage {
        let light: UInt32 = 0xD9A066, mid: UInt32 = 0xB07A44, dark: UInt32 = 0x7A5230, leaf: UInt32 = 0x6CC04A
        let w = max(8, widthPx)
        var g: Grid = []
        g.append((0..<w).map { _ in light })
        g.append((0..<w).map { $0 % 9 == 4 ? dark : mid })
        g.append((0..<w).map { _ in dark })
        for r in 0..<5 {
            var row: [UInt32?] = Array(repeating: nil, count: w)
            for bx in [w / 5, w * 4 / 5] {
                for x in max(0, bx - (4 - r))...min(w - 1, bx) { row[x] = x == bx ? dark : mid }
            }
            g.append(row)
        }
        // A sprig of ivy hanging off one end.
        for (x, y) in [(w - 3, 3), (w - 3, 4), (w - 2, 4), (w - 3, 5), (w - 4, 6), (w - 3, 7)] where x >= 0 { g[y][x] = leaf }
        return image(g)
    }

    static let balloonColors: [UInt32] = [0xFF6F7E, 0xFFD84A, 0x6FB8F0, 0xA98BEA, 0x6CC04A, 0xFF8FBF]
    static func balloon(_ id: Int) -> CGImage {
        let c = balloonColors[id % balloonColors.count]
        let hi: UInt32 = 0xFFFFFF
        let rows = [
            "..xxxxx..",
            ".xhxxxxx.",
            "xhhxxxxxx",
            "xhxxxxxxx",
            "xxxxxxxxx",
            "xxxxxxxxx",
            ".xxxxxxx.",
            "..xxxxx..",
            "...xxx...",
            "....x....",
        ]
        return image(grid(rows, ["x": c, "h": hi]))
    }

    // MARK: Keepsakes (the garden along the bottom of the screen)

    static let flowerColors: [(UInt32, UInt32)] = [(0xFF8FBF, 0xE0588F), (0xFFD84A, 0xE0A92E), (0xA98BEA, 0x7A5FC9), (0xFF6F7E, 0xD8455A), (0x6FB8F0, 0x3F8CC9), (0xFFFFFF, 0xD8E4EC)]
    static func groundFlower(_ variant: Int) -> CGImage {
        let (f, F) = flowerColors[variant % flowerColors.count]
        let rows = variant % 2 == 0
            ? ["..f.f..", ".fFyFf.", "..fff..", "...G...", ".g.G...", "..gG.g.", "...Gg..", "...G..."]
            : [".f...f.", "fyf.fyf", ".f.G.f.", "..gG...", "...G.g.", ".g.Gg..", "..gG...", "...G..."]
        return image(grid(rows, ["f": f, "F": F, "y": 0xFFE066, "g": 0x6CC04A, "G": 0x3E8E3A]))
    }

    static func miniPainting(_ variant: Int) -> CGImage {
        let pic = grid(pictures[variant % pictures.count], paintPalette)
        let dark = paintPalette["d"]!
        var g: Grid = [Array(repeating: dark, count: 8)]
        for y in stride(from: 0, to: 9, by: 2) {
            var row: [UInt32?] = [dark]
            for x in stride(from: 0, to: 12, by: 2) { row.append(pic[y][x]) }
            row.append(dark)
            g.append(row)
        }
        g.append(Array(repeating: dark, count: 8))
        return image(g)
    }
}

/// Finished flowers get planted along the bottom of the main screen, and paintings lean there too. Kept between
/// launches (UserDefaults), at most a dozen; the oldest makes room for the newest.
final class KeepsakeStore {
    struct Item: Codable { var kind: String; var x: Double; var variant: Int }
    private let key = "keepsakes.v1"
    private(set) var items: [Item] = []
    static let limit = 12

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let v = try? JSONDecoder().decode([Item].self, from: d) { items = v }
    }

    /// `x` is 0...1 across the main screen. Nudged so keepsakes don't stack on top of each other.
    func add(kind: String, x: Double, variant: Int) {
        var x = x.clamped(0.03, 0.97)
        for _ in 0..<20 where items.contains(where: { abs($0.x - x) < 0.025 }) { x = (x + 0.03).truncatingRemainder(dividingBy: 0.94) + 0.03 }
        items.append(Item(kind: kind, x: x, variant: variant))
        if items.count > Self.limit { items.removeFirst(items.count - Self.limit) }
        save()
    }

    func clear() { items.removeAll(); save() }

    private func save() { if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) } }
}
