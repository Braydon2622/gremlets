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

    // MARK: Window-box garden

    static let G: [Character: UInt32] = [
        "g": 0x6CC04A, "G": 0x3E8E3A, "r": 0xFF6F7E, "R": 0xD8455A, "w": 0xFFFFFF, "W": 0xF4F1E8, "y": 0xFFD84A,
        "Y": 0xE0A92E, "o": 0xFF9A3C, "O": 0xD8701E, "d": 0x8A5A35, "c": 0x5FA84A, "C": 0x3E7D33, "p": 0xFF8FBF,
        "b": 0x7A4E2A, "m": 0x7A4E2A, "k": 0x2B2620, "a": 0x9ACD32, "s": 0x4A3424,
    ]
    /// Stages 0-2 (seed, sprout, young plant) look alike for every kind; stage 3 is a bud in the kind's colour.
    static let earlyStages: [[String]] = [
        [".....mm....."],
        ["....g.g.....", ".....G......", ".....G......"],
        ["..gg...gg...", "...gg.gg....", ".....G......", "..gg.G......", "...ggG......", ".....G......"],
    ]
    static func bud(_ k: PlantKind) -> [String] {
        let c: Character = { switch k {
            case .tulip: return "r"; case .daisy: return "w"; case .sunflower: return "y"; case .strawberry: return "w"
            case .carrot: return "g"; case .tomato: return "y"; case .cactus: return "p"; case .mushroom: return "W" } }()
        if k == .cactus { return [".....p......", "....ccc.....", "....cCc.....", "..c.cCc.....", "..cccCc.c...", "....cCccc...", "....cCc....."] }
        if k == .mushroom { return ["....WWW.....", "...WWWWW....", ".....W......", ".....W......", "..g..W..g..."] }
        return [".....\(c)......", "....\(c)\(c)\(c).....", ".....G......", "..gg.G.gg...", ".gggGG.Ggg..", ".....G......", "...ggG......", "..gggG......", ".....G......"]
            .map { String($0) }
    }
    static func bloom(_ k: PlantKind) -> [String] {
        switch k {
        case .tulip: return ["....r.r.r...", "....rrrrr...", "....rRrRr...", ".....rrr....", ".....G......", "..gg.G......", ".gggGG......", ".....G.gg...", ".....Ggggg..", ".....G......"]
        case .daisy: return ["...w.w.w....", "....wyw.....", "...wyyyw....", "....wyw.....", "...w.w.w....", ".....G......", "..gg.G......", "...gGG......", ".....G.gg...", ".....G......"]
        case .sunflower: return ["...y.y.y....", "..yyyyyyy...", ".yyybbbyyy..", "..yybbbyy...", ".yyybbbyyy..", "..yyyyyyy...", "...y.G.y....", ".....G......", "..ggGG......", ".gggGG......", ".....G.gg...", ".....GGggg..", ".....G......", ".....G......"]
        case .strawberry: return ["...w...w....", "..wyw.wyw...", "...w.g.w....", "..gggggggg..", ".ggGggGgggg.", "..r.gGg.r...", ".rrr.G.rrr..", ".rWr.G.rWr..", "..r..G..r..."]
        case .carrot: return ["..g..g..g...", "...g.g.g....", "..gggggg....", "...gGGGg....", "....gGg.....", "....oOo.....", "....ooo....."]
        case .tomato: return ["....s.......", "...gsg.g....", "..ggsggg....", ".rrgsg.rr...", ".rRgsg.Rr...", "..ggsgg.....", ".g.rsr.g....", "...rsR......", "....s.......", "....s......."]
        case .cactus: return [".....p......", "....pyp.....", ".....p......", "....ccc.....", ".c..cCc.....", ".cc.cCc..c..", "..cccCc.cc..", "....cCccc...", "....cCc.....", "....cCc....."]
        case .mushroom: return ["...rrrrr....", "..rWrrrWr...", ".rrrrWrrrr..", ".rrWrrrrWr..", "....WWWW....", "....WWWW....", "....WWWW....", ".gg.WWWW.gg."]
        }
    }
    static func plantRows(_ p: Plant) -> [String] {
        switch p.stage { case 0...2: return earlyStages[p.stage]; case 3: return bud(p.kind); default: return bloom(p.kind) }
    }

    static let boxWidth = 38, boxRows = 6, plantRows = 16
    /// Art-pixel x of each spot's centre in the box.
    static let slotCenters = [6, 19, 32]

    static var boxCache: [String: CGImage] = [:]
    static func boxKey(_ g: GardenBox) -> String {
        g.plants.map { p in
            guard let p else { return "-" }
            let wet = p.water > 0.55 ? "w" : p.water > 0.2 ? "m" : "d"
            return "\(p.kind.rawValue.prefix(2))\(p.stage)\(p.bug ? "b" : "")\(wet)"
        }.joined(separator: "|")
    }

    /// The planter with its three spots: soil darker where it's been watered, each plant at its stage, aphids on top.
    static func windowBox(_ g: GardenBox) -> CGImage {
        let key = boxKey(g)
        if let c = boxCache[key] { return c }
        let w = boxWidth, h = boxRows + plantRows
        var grid: Grid = Array(repeating: Array(repeating: nil, count: w), count: h)
        let light: UInt32 = 0xD9A066, mid: UInt32 = 0xB07A44, dark: UInt32 = 0x7A5230
        for (i, cx) in slotCenters.enumerated() {
            let p = g.plants[i]
            // Soil.
            let soil: UInt32 = p == nil ? 0x8A5A35 : p!.water > 0.55 ? 0x4A2E1A : p!.water > 0.2 ? 0x6B4428 : 0x9C7048
            for x in max(1, cx - 6)...min(w - 2, cx + 6) { grid[plantRows][x] = soil }
            guard let p else { continue }
            let rows = plantRows(p)
            let rowsTop = plantRows - rows.count
            for (ry, row) in rows.enumerated() {
                for (rx, ch) in row.enumerated() {
                    guard let col = G[ch] else { continue }
                    let x = cx - 5 + rx
                    if x >= 0 && x < w { grid[rowsTop + ry][x] = col }
                }
            }
            if p.bug {
                let by = rowsTop + max(1, rows.count / 3), bx = cx + 2
                if by >= 0 && bx + 1 < w { grid[by][bx] = 0x2B2620; grid[by][bx + 1] = 0x9ACD32; grid[by + 1][bx] = 0x9ACD32 }
            }
        }
        // The planter: a light rim, planks, a darker base.
        for x in 0..<w { if grid[plantRows][x] == nil { grid[plantRows][x] = light } }
        grid[plantRows][0] = light; grid[plantRows][w - 1] = light
        for x in 0..<w { grid[plantRows + 1][x] = light }
        for r in 2...4 { for x in 0..<w { grid[plantRows + r][x] = (x % 13 == 0 || r == 3 && x % 7 == 3) ? dark : mid } }
        for x in 1..<(w - 1) { grid[plantRows + 5][x] = dark }
        let img = image(grid)
        if boxCache.count > 400 { boxCache.removeAll() }
        boxCache[key] = img
        return img
    }

    /// A planted keepsake: the bloomed plant on a little mound of soil.
    static func keepsake(_ k: PlantKind) -> CGImage {
        image(grid(bloom(k) + ["...mmmmmm..."], G))
    }

    static let wateringCan = image(grid([
        "......bb...",
        ".bbbbbbb...",
        "bBBBBBBb...",
        "bBBBBBBbbbb",
        "bBBBBBBb..b",
        ".bbbbbb....",
    ], ["b": 0x3F8CC9, "B": 0x6FB8F0]))

    static let aphid = image(grid(["ak", "aa"], G))

    static let butterflies: [CGImage] = [(0xFF8FBF, 0xFFD84A), (0x6FB8F0, 0xFFFFFF), (0xFFB35C, 0x7A4E2A), (0xA98BEA, 0xFFE066)].map { (a, b) in
        image(grid(["a.a", "bkb", "a.a"], ["a": a, "b": b, "k": 0x2B2620]))
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

    // MARK: What it's growing (hover text)

    static func describe(_ j: Job, dozing: Bool) -> String {
        if dozing { return "Zzz… the garden waits for you" }
        let g = j.garden
        if j.phase == .finished || j.phase == .leaving {
            return "Harvest! " + g.planted.map { $0.kind.name }.joined(separator: ", ")
        }
        let parts = g.plants.map { p -> String in
            guard let p else { return "empty spot" }
            if p.bug { return "\(p.kind.name) has a bug!" }
            if p.isThirsty { return "\(p.kind.name) is thirsty" }
            if p.stage == 4 { return "\(p.kind.name) in bloom" }
            return "\(p.kind.name) \(Int((p.growth * 100).rounded()))%"
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Lantern (shelves light up in the evening)

    static let lantern: CGImage = image(grid([
        "..d..",
        "..d..",
        "..d..",
        ".ddd.",
        "dyYyd",
        "dYYYd",
        "dyYyd",
        ".ddd.",
    ], ["d": 0x4A3424, "y": 0xFFC94A, "Y": 0xFFF2B0]))

    static var isEvening: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 19 || h < 6
    }

    // MARK: Keepsakes (the garden along the bottom of the screen)

    /// Older keepsakes (before plant kinds) were plain flowers.
    static func keepsakeImage(_ kind: String) -> CGImage? {
        if let k = PlantKind(rawValue: kind) { return keepsake(k) }
        if kind == "flower" { return keepsake(.tulip) }
        return nil
    }
}

/// Finished flowers get planted along the bottom of the main screen, and paintings lean there too. Kept between
/// launches (UserDefaults), at most a dozen; the oldest makes room for the newest.
final class KeepsakeStore {
    struct Item: Codable { var kind: String; var x: Double; var variant: Int }
    private let key = "keepsakes.v1"
    private(set) var items: [Item] = []
    static let limit = 24

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

/// Which plants you've grown (the seed book) and how many were harvested each day (UserDefaults).
final class SeedBook {
    private let key = "seedbook.v1", dayKey = "harvests.v1"
    private(set) var counts: [String: Int] = [:]
    private var days: [String: Int] = [:]

    init() {
        counts = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        days = UserDefaults.standard.dictionary(forKey: dayKey) as? [String: Int] ?? [:]
    }

    var found: Int { PlantKind.allCases.filter { (counts[$0.rawValue] ?? 0) > 0 }.count }
    func count(_ k: PlantKind) -> Int { counts[k.rawValue] ?? 0 }
    var today: Int { days[BondStore.dayKey()] ?? 0 }

    /// Records a bloom. Returns true the first time this kind is ever grown.
    @discardableResult
    func record(_ k: PlantKind) -> Bool {
        let isNew = count(k) == 0
        counts[k.rawValue, default: 0] += 1
        days[BondStore.dayKey(), default: 0] += 1
        UserDefaults.standard.set(counts, forKey: key)
        UserDefaults.standard.set(days, forKey: dayKey)
        return isNew
    }
}
