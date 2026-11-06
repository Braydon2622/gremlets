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
        "v": 0xA98BEA, "V": 0x7A5FC9, "B": 0x6F8FF0, "i": 0xD8F0FF, "I": 0x9FD3F5, "l": 0xC9B8FF, "L": 0xF2EEFF,
        "x": 0x7FE3F0, "X": 0xC6F7FF, "z": 0xA98BEA, "P": 0xE0588F,
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
            case .carrot: return "g"; case .tomato: return "y"; case .cactus: return "p"; case .mushroom: return "W"
            case .lavender: return "v"; case .bluebell: return "B"; case .cherryBlossom: return "p"; case .frostbell: return "i"
            case .moonflower: return "l"; case .crystalRose: return "x"; case .giantPumpkin, .wishingTree: return "g" } }()
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
        case .lavender: return ["..v...v.....", ".vV..vV.....", "..v.v.v.v...", "..vV.vVvV...", "...v.v.v....", "...g.G.g....", "..gg.G.gg...", ".....G......", "....gGg.....", ".....G......"]
        case .bluebell: return ["....GGG.....", "...G.G.G....", "..B..G..B...", ".BBB.G.BBB..", ".B.B.G.B.B..", ".....G......", "..gg.G......", "...gGG.gg...", ".....GGg....", ".....G......"]
        case .cherryBlossom: return ["..p.pp..p...", ".pPpppp.pp..", "..pp.sppPp..", ".pP.s.ss....", "....s.s.....", ".....ss.....", ".....s......", ".....s......", "....ss......", ".....s......"]
        case .frostbell: return ["....i.i.....", "...iIiIi....", "....iii.....", "..i..G..i...", ".iIi.G.iIi..", "..i..G..i...", ".....G......", "..gg.G.gg...", "...gGGGg....", ".....G......"]
        case .moonflower: return ["....lllll...", "...lLLLLLl..", "..lLLyyLLl..", "..lLyyyyLl..", "..lLLyyLLl..", "...lLLLLl...", "....lllll...", ".....G......", "..gg.G.gg...", ".ggg.G.ggg..", ".....G......", "....gGg.....", ".....G......"]
        case .crystalRose: return [".....x......", "....xXx.....", "...xXzXx....", "..xXzzzXx...", "...xXzXx....", "....xXx.....", ".....G......", "..g..G..g...", "...gGG......", ".....G.gg...", ".....G......"]
        case .giantPumpkin, .wishingTree: return giantRows(k)
        }
    }
    static func plantRows(_ p: Plant) -> [String] {
        if p.kind.isGiant {
            // Giants start like anything else, then get big: a half-size version at the bud stage.
            switch p.stage {
            case 0...1: return earlyStages[p.stage]
            case 2: return ["..gg...gg...", ".gggg.gggg..", "..ggGGGgg...", "....gGg.....", "...ggGgg....", ".....G......", ".....G......"]
            case 3: return giantRows(p.kind, half: true)
            default: return giantRows(p.kind)
            }
        }
        switch p.stage { case 0...2: return earlyStages[p.stage]; case 3: return bud(p.kind); default: return bloom(p.kind) }
    }

    /// The legendary giants, drawn procedurally: 36 art pixels wide (the whole box).
    static func giantRows(_ k: PlantKind, half: Bool = false) -> [String] {
        let w = half ? 20 : 36
        let h = k == .wishingTree ? (half ? 14 : 26) : (half ? 9 : 16)
        var g = Array(repeating: Array(repeating: Character("."), count: w), count: h)
        func put(_ x: Int, _ y: Int, _ c: Character) { if x >= 0 && x < w && y >= 0 && y < h { g[y][x] = c } }
        let cx = Double(w) / 2 - 0.5
        if k == .giantPumpkin {
            let cy = Double(h) - Double(h) * 0.38, rx = Double(w) / 2 - 1.5, ry = Double(h) * 0.38
            for y in 0..<h { for x in 0..<w {
                let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
                if dx * dx + dy * dy <= 1 {
                    let rib = Int(Double(x) - cx + 100) % (half ? 4 : 6) == 0
                    put(x, y, rib ? "O" : (dx < -0.3 && dy < -0.2 ? "y" : "o"))
                }
            }}
            let top = Int(cy - ry)
            for y in max(0, top - 4)...max(0, top) { put(Int(cx), y, "G"); put(Int(cx) + 1, y, "G") }
            for (i, x) in stride(from: Int(cx) + 2, to: min(w - 1, Int(cx) + 12), by: 1).enumerated() {
                put(x, max(0, top - 3 + (i % 4 == 0 ? 1 : 0)), "g")
                if i % 4 == 2 { put(x, max(0, top - 4), "g"); put(x + 1, max(0, top - 4), "g"); put(x, max(0, top - 2), "g") }
            }
        } else {
            let canopy = half ? [(6.0, 4.0, 4.5), (13.0, 4.0, 4.5), (9.5, 2.5, 4.0)] : [(11.0, 8.0, 7.5), (24.0, 8.0, 7.5), (17.5, 5.0, 7.0), (17.5, 11.0, 6.5)]
            for y in 0..<h { for x in 0..<w {
                for (ccx, ccy, r) in canopy {
                    let dx = Double(x) - ccx, dy = Double(y) - ccy
                    if dx * dx + dy * dy <= r * r { put(x, y, dx > r * 0.35 || dy > r * 0.45 ? "G" : "g") }
                }
            }}
            let fruit = half ? [(5, 3), (12, 2), (9, 6), (15, 5)] : [(8, 7), (15, 3), (22, 9), (27, 6), (18, 12), (12, 12), (25, 13)]
            for (fx, fy) in fruit { put(fx, fy, "y"); put(fx + 1, fy, "Y"); put(fx, fy + 1, "Y") }
            let trunkTop = half ? 8 : 14
            for y in trunkTop..<h { for x in (Int(cx) - 1)...(Int(cx) + 2) { put(x, y, (x + y) % 3 == 0 ? "b" : "s") } }
            for x in (Int(cx) - 4)...(Int(cx) + 5) { put(x, h - 1, "s") }
        }
        return g.map { String($0) }
    }

    /// Golden plants: every colour mapped onto a ramp of golds by brightness.
    static func goldify(_ c: UInt32) -> UInt32 {
        let r = Double(c >> 16 & 0xFF), g = Double(c >> 8 & 0xFF), b = Double(c & 0xFF)
        let lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255
        let ramp: [UInt32] = [0x6E4E10, 0xA8781E, 0xD9A72E, 0xF2CB52, 0xFFE58A, 0xFFF6CF]
        return ramp[min(ramp.count - 1, Int(lum * Double(ramp.count)))]
    }

    static let boxWidth = 38, boxRows = 6, plantRows = 26
    /// Art-pixel x of each spot's centre in the box.
    static let slotCenters = [6, 19, 32]

    static var boxCache: [String: CGImage] = [:]
    static func boxKey(_ g: GardenBox) -> String {
        g.plants.map { p in
            guard let p else { return "-" }
            let wet = p.water > 0.55 ? "w" : p.water > 0.2 ? "m" : "d"
            return "\(p.kind.rawValue.prefix(4))\(p.stage)\(p.bug ? "b" : "")\(p.golden ? "g" : "")\(wet)"
        }.joined(separator: "|")
    }

    /// The planter with its three spots: soil darker where it's been watered, each plant at its stage, aphids on top.
    static func windowBox(_ g: GardenBox) -> CGImage {
        let key = boxKey(g)
        if let c = boxCache[key] { return c }
        let w = boxWidth, h = boxRows + plantRows
        var grid: Grid = Array(repeating: Array(repeating: nil, count: w), count: h)
        let light: UInt32 = 0xD9A066, mid: UInt32 = 0xB07A44, dark: UInt32 = 0x7A5230
        for (i, cx0) in slotCenters.enumerated() {
            let p = g.plants[i]
            if g.giant != nil && i != 1 {
                // A giant fills the box: soil only.
                let soil: UInt32 = (g.giant!.water > 0.55) ? 0x4A2E1A : g.giant!.water > 0.2 ? 0x6B4428 : 0x9C7048
                for x in max(1, cx0 - 6)...min(w - 2, cx0 + 6) { grid[plantRows][x] = soil }
                continue
            }
            let cx = cx0
            // Soil.
            let soil: UInt32 = p == nil ? 0x8A5A35 : p!.water > 0.55 ? 0x4A2E1A : p!.water > 0.2 ? 0x6B4428 : 0x9C7048
            for x in max(1, cx - 6)...min(w - 2, cx + 6) { grid[plantRows][x] = soil }
            guard let p else { continue }
            let rows = plantRows(p)
            let rowsTop = plantRows - rows.count
            let left = (p.kind.isGiant && p.stage >= 3) ? cx - row0Width(rows) / 2 + (rows.first?.count ?? 12) / 2 - (rows.first?.count ?? 12) / 2 : cx - 5
            for (ry, row) in rows.enumerated() {
                for (rx, ch) in row.enumerated() {
                    guard var col = G[ch] else { continue }
                    if p.golden { col = goldify(col) }
                    let x = left + rx
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

    static func row0Width(_ rows: [String]) -> Int { rows.first?.count ?? 12 }

    /// A planted keepsake: the bloomed plant on a little mound of soil (gold all over if it was golden).
    static func keepsake(_ k: PlantKind, golden: Bool = false) -> CGImage {
        let rows = bloom(k)
        let width = rows.first?.count ?? 12
        let mound = String(repeating: ".", count: max(0, width / 2 - 4)) + "mmmmmmmm"
        var g = grid(rows + [mound], G)
        if golden { g = g.map { $0.map { $0.map(goldify) } } }
        return image(g)
    }

    static let ladybug = image(grid([".k.", "rkr", "rrr"], ["r": 0xE8343F, "k": 0x2B2620]))
    static let firefly = image(grid(["y"], ["y": 0xF7FF9C]))
    static let shootingStar = image(grid(["....w", "..wWw", "wwW.."], ["w": 0xFFFFFF, "W": 0xFFF6B0]))
    static let rainbow: CGImage = {
        let colors: [UInt32] = [0xFF6F7E, 0xFFB35C, 0xFFE066, 0x8FD6A2, 0x6FB8F0, 0xA98BEA]
        let w = 30, h = 11
        var g: Grid = Array(repeating: Array(repeating: nil, count: w), count: h)
        for (band, col) in colors.enumerated() {
            let r = Double(w) / 2 - Double(band)
            for x in 0..<w {
                let dx = Double(x) - Double(w - 1) / 2
                guard abs(dx) <= r else { continue }
                let y = Int((r * r - dx * dx).squareRoot().rounded())
                let row = h - 1 - min(h - 1, y)
                g[row][x] = col
            }
        }
        return image(g)
    }()

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
            return "Harvest! " + g.planted.map { ($0.golden ? "golden " : "") + $0.kind.name.lowercased() }.joined(separator: ", ")
        }
        let slots: [Plant?] = g.giant.map { [$0] } ?? g.plants
        let parts = slots.map { p -> String in
            guard let p else { return "empty spot" }
            let name = (p.golden ? "Golden " + p.kind.name.lowercased() : p.kind.name)
            if p.bug { return "\(name) has a bug!" }
            if p.isThirsty { return "\(name) is thirsty" }
            if p.stage == 4 { return "\(name) in bloom" }
            return "\(name) \(Int((p.growth * 100).rounded()))%"
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
    static func keepsakeImage(_ kind: String, golden: Bool = false) -> CGImage? {
        if let k = PlantKind(rawValue: kind) { return keepsake(k, golden: golden) }
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

    private(set) var goldens: [String: Int] = UserDefaults.standard.dictionary(forKey: "seedbook.golden.v1") as? [String: Int] ?? [:]
    func goldenCount(_ k: PlantKind) -> Int { goldens[k.rawValue] ?? 0 }

    /// Records a bloom. Returns true the first time this kind is ever grown.
    @discardableResult
    func record(_ p: Plant) -> Bool {
        let k = p.kind
        let isNew = count(k) == 0
        if p.golden {
            goldens[k.rawValue, default: 0] += 1
            UserDefaults.standard.set(goldens, forKey: "seedbook.golden.v1")
        }
        counts[k.rawValue, default: 0] += 1
        days[BondStore.dayKey(), default: 0] += 1
        UserDefaults.standard.set(counts, forKey: key)
        UserDefaults.standard.set(days, forKey: dayKey)
        return isNew
    }
}
