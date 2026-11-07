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
            case .moonflower: return "l"; case .crystalRose: return "x"; case .starLily: return "L"; case .flytrap: return "R"
            case .giantPumpkin, .wishingTree, .bonsai: return "g" } }()
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
        case .flytrap: return ["..G......G..", ".gRg....gRg.", "gRRRg..gRRRg", "gRwRg..gRwRg", ".gRg.GG.gRg.", "...G.G.G....", "....GGG.....", ".....G......", "..gg.G.gg...", ".....G......"]
        case .starLily: return ["....p.p.....", "...pLpLp....", ".pLLLyLLLp..", "..pLyYyLp...", ".pLLLyLLLp..", "...pLpLp....", "....p.p.....", ".....G......", "..gg.G.gg...", "...gGG......", ".....G......"]
        case .giantPumpkin, .wishingTree, .bonsai: return giantRows(k)
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
        let h = k == .wishingTree ? (half ? 14 : 26) : k == .bonsai ? (half ? 12 : 22) : (half ? 9 : 16)
        var g = Array(repeating: Array(repeating: Character("."), count: w), count: h)
        func put(_ x: Int, _ y: Int, _ c: Character) { if x >= 0 && x < w && y >= 0 && y < h { g[y][x] = c } }
        let cx = Double(w) / 2 - 0.5
        if k == .bonsai {
            // A twisting trunk with flat, cloud-like pads of foliage.
            let sx = Double(w) / 36
            let trunk: [(Double, Double)] = [(18, 21), (19, 19), (19, 17), (18, 15), (16, 13), (14, 11), (12, 10), (11, 8), (16, 12), (20, 11), (23, 10), (25, 9), (17, 9), (17, 7), (17, 5)]
            for (tx, ty) in trunk {
                let x = Int(tx * sx), y = Int(ty * Double(h) / 22)
                put(x, y, "s"); put(x + 1, y, "b"); put(x, y + 1, "s")
            }
            let pads: [(Double, Double, Double, Double)] = [(9, 6, 6, 2.6), (26, 7, 6.5, 2.6), (17, 3, 7, 2.8), (13, 13, 4, 1.8)]
            for (pcx, pcy, rx, ry) in pads {
                for y in 0..<h { for x in 0..<w {
                    let dx = (Double(x) - pcx * sx) / (rx * sx), dy = (Double(y) - pcy * Double(h) / 22) / (ry * Double(h) / 22)
                    if dx * dx + dy * dy <= 1 { put(x, y, dy < -0.2 ? "g" : "G") }
                }}
            }
            for x in (Int(cx) - 3)...(Int(cx) + 3) { put(x, h - 1, "s") }
        } else if k == .giantPumpkin {
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
        // No planter: a soft mound of moss the plants grow out of (rounded ends, tufts along the top, darker below).
        _ = (light, mid, dark)
        let moss: UInt32 = 0x5E9E46, mossLight: UInt32 = 0x8BD66A, mossDark: UInt32 = 0x3E7A34, tuft: UInt32 = 0x6CC04A
        for x in 0..<w where grid[plantRows][x] == nil && x >= 2 && x < w - 2 { grid[plantRows][x] = x % 3 == 0 ? mossLight : tuft }
        for r in 1...5 {
            let inset = r == 1 ? 1 : r >= 4 ? 0 : 0
            for x in inset..<(w - inset) {
                grid[plantRows + r][x] = r == 5 ? mossDark : (r == 1 ? (x % 4 == 1 ? mossLight : moss) : ((x * 7 + r * 3) % 11 == 0 ? mossDark : moss))
            }
        }
        // A few tiny flowers in the moss.
        for x in [3, 15, 27, 35] where x < w { grid[plantRows + 2][x] = [0xFFF2B0, 0xFF8FB1, 0xFFFFFF, 0xB98CFF][x % 4] as UInt32 }
        // Rounded top corners.
        grid[plantRows][0] = nil; grid[plantRows][1] = nil; grid[plantRows][w - 1] = nil; grid[plantRows][w - 2] = nil
        let img = image(grid)
        if boxCache.count > 400 { boxCache.removeAll() }
        boxCache[key] = img
        return img
    }

    static func row0Width(_ rows: [String]) -> Int { rows.first?.count ?? 12 }

    /// A planted keepsake: the bloomed plant on a little mound of soil (gold all over if it was golden).
    static func keepsake(_ k: PlantKind, golden: Bool = false) -> CGImage {
        if k.isGiant {
            var g = grid(giantRows(k) + [String(repeating: ".", count: 12) + "mmmmmmmmmmmm"], G)
            if golden { g = g.map { $0.map { $0.map(goldify) } } }
            return image(g)
        }
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
        // Tall enough for the whole arc (it used to be 11 rows for a 15-row arc, which flattened the top off).
        let w = 30, h = w / 2 + 1
        var g: Grid = Array(repeating: Array(repeating: nil, count: w), count: h)
        for (band, col) in colors.enumerated() {
            let r = Double(w) / 2 - Double(band)
            // Every pixel within the band's ring, so the arc has no gaps at its steep sides.
            for row in 0..<h { for x in 0..<w {
                let dx = Double(x) - Double(w - 1) / 2, dy = Double(h - 1 - row)
                let d = (dx * dx + dy * dy).squareRoot()
                if d <= r && d > r - 1 && g[row][x] == nil { g[row][x] = col }
            } }
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
        let grain: UInt32 = 0x9A6A3C, nail: UInt32 = 0x4A4A4A
        g.append((0..<w).map { _ in light })
        g.append((0..<w).map { x in x == 2 || x == w - 3 ? nail : x % 9 == 4 ? dark : (x % 13 == 7 ? grain : mid) })
        g.append((0..<w).map { x in x % 11 == 5 || x % 11 == 6 ? grain : mid })
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

    /// The shelves: each style is `widthPx` wide; its top row is the surface the Gremlet stands on. Drawn as if
    /// sticking out to the right of the window (flipped for the left side).
    static func shelf(_ style: ShelfStyle, widthPx: Int) -> CGImage {
        let w = max(12, widthPx)
        var g: Grid = []
        func row(_ f: (Int) -> UInt32?) -> [UInt32?] { (0..<w).map(f) }
        switch style {
        case .plank:
            return shelf(widthPx: w)
        case .basket:
            // Woven wicker: a rim, a diagonal weave, a darker base, rounded bottom corners.
            let rim: UInt32 = 0xC98B4A, a: UInt32 = 0xD9A066, b: UInt32 = 0xB07A44, base: UInt32 = 0x7A5230
            g.append(row { _ in rim })
            g.append(row { x in x % 4 == 0 ? base : rim })
            for r in 0..<6 { g.append(row { x in (x + r) % 4 < 2 ? a : b }) }
            g.append(row { x in x == 0 || x == w - 1 ? nil : base })
            g.append(row { x in x < 2 || x > w - 3 ? nil : base })
        case .carpet:
            return carpet(widthPx: w, phase: 0)
        case .treehouse:
            // Porch boards with a little lip, and a ladder rung or two hanging below.
            let board: UInt32 = 0xC98B4A, gap: UInt32 = 0x8A5A35, dark: UInt32 = 0x5E3B22
            g.append(row { x in x % 7 == 6 ? gap : board })
            g.append(row { x in x % 7 == 6 ? gap : 0xB07A44 })
            g.append(row { _ in dark })
            for r in 0..<6 { g.append(row { x in (x == w - 8 || x == w - 3) ? dark : (r % 3 == 1 && x > w - 8 && x < w - 3 ? 0xB07A44 : nil) }) }
        case .snail:
            // The flat top of the snail's mossy shell.
            let moss: UInt32 = 0x7DC45E, mossDark: UInt32 = 0x4F9A44, shell: UInt32 = 0xC98B4A
            g.append(row { x in x % 6 == 2 ? mossDark : moss })
            g.append(row { x in x % 5 == 1 ? moss : shell })
        case .stone:
            let top: UInt32 = 0x8FA88A, moss: UInt32 = 0x6CC04A, light: UInt32 = 0xB8B6AE, mid: UInt32 = 0x8E8B83, dark: UInt32 = 0x5E5B55
            g.append(row { $0 % 5 == 1 || $0 % 7 == 3 ? moss : top })
            for r in 0..<4 {
                g.append(row { x in
                    if x >= w - (r + 1) { return nil }                       // rounded outer end
                    if (x + r * 3) % 11 == 0 { return dark }                 // cracks
                    return r == 0 ? light : r == 3 ? dark : mid
                })
            }
            g.append(row { x in x < w - 6 && x % 9 == 4 ? moss : nil })    // moss dripping off
            g.append(row { x in x < w - 6 && x % 9 == 4 ? moss : nil })
        case .leaf:
            let light: UInt32 = 0x8FD67A, mid: UInt32 = 0x6CC04A, dark: UInt32 = 0x3E8E3A
            g.append(row { x in x > w - 3 ? nil : light })
            for r in 1...5 {
                let inset = r * r / 2 + 1
                g.append(row { x in
                    guard x < w - inset else { return nil }
                    if r == 1 { return mid }
                    if r == 3 { return dark }                                 // the midrib
                    return (x + r) % 8 == 0 || (x - r) % 8 == 0 ? dark : (x % 5 == 0 ? light : mid)   // veins
                })
            }
            g.append(row { x in x < 3 ? dark : nil })                      // stem into the window's side
        case .cloud:
            let white: UInt32 = 0xFFFFFF, shade: UInt32 = 0xDCE9F5, edge: UInt32 = 0xB9CCE0
            g.append(row { _ in white })
            for r in 1...5 {
                g.append(row { x in
                    let bump = abs(sin(Double(x) / 4.5)) * 2
                    if Double(r) > 4 - bump + 1 { return nil }
                    return r >= 3 ? (r == 4 ? edge : shade) : white
                })
            }
        case .mushroom:
            // A bracket fungus growing out of the window's side, in layered bands.
            let bands: [UInt32] = [0xE8B26A, 0xD9935A, 0xC27A45, 0x9E5C34, 0x7A4628]
            g.append(row { x in x > w - 2 ? nil : 0xF2CF92 })
            for (r, c) in bands.enumerated() {
                let inset = (r + 1) * (r + 1) / 2 + 1
                g.append(row { x in x < w - inset ? c : nil })
            }
        case .branch:
            let bark: UInt32 = 0x8A5A35, dark: UInt32 = 0x5E3B22, leaf: UInt32 = 0x6CC04A
            g.append(row { x in x % 6 == 2 ? dark : bark })
            g.append(row { x in x % 6 == 5 ? dark : bark })
            g.append(row { x in x < w - 2 ? dark : nil })
            g.append(row { x in [w / 4, w / 2 + 3].contains(x) ? leaf : nil })
            g.append(row { x in [w / 4, w / 4 + 1, w / 2 + 3].contains(x) ? leaf : nil })
        case .swing:
            let seat: UInt32 = 0xD9A066, mid: UInt32 = 0xB07A44, dark: UInt32 = 0x7A5230
            g.append(row { _ in seat })
            g.append(row { x in x % 10 == 4 ? dark : mid })
            g.append(row { _ in dark })
        }
        return image(g)
    }

    /// The tree a branch shelf or treehouse grows on. Not a pole: a leaning, tapering trunk with flared roots and a
    /// knot hole, limbs reaching out at different heights (mostly away from the window, where there's room), twigs,
    /// leaf clusters at every tip, vines trailing off some of them, and a crown around the top. One thick limb reaches
    /// back under the shelf at `shelfPx` to prop it up. Every tree is a little different (`seed`), and the leaves turn
    /// with the season. The trunk stands a third of the way in from the left edge of the image (`treeAnchorX`);
    /// `mirror` draws it for a shelf on the window's left side.
    static let treeWidthPx = 132
    static let treeAnchorX = 50.0 / 132.0
    static func tree(heightPx: Int, shelfPx: Int, seed: UInt64, month: Int, mirror: Bool = false) -> CGImage {
        // A wider picture than the tree needs, so no leaf or limb is ever cut off at its edges.
        let W = treeWidthPx, H = max(30, heightPx) + 12, x0 = 50.0
        var cv = PixelCanvas(W, H)
        var r = ArtRNG(s: seed &* 31 &+ 17)
        let autumn = [9, 10, 11].contains(month), spring = [3, 4, 5].contains(month)
        // Every tree is a kind: oak, pine, maple, birch, cherry or willow, each with its own colours and its own
        // autumn (the pine stays green, the maple goes red, the birch gold), so a desktop of them is never all one hue.
        let kind = Int(seed % 6)
        let evergreen = kind == 1
        let winter = [12, 1, 2].contains(month) && !evergreen
        let bark: UInt32 = kind == 3 ? 0xD8D2C4 : 0x8A5A35, dark: UInt32 = kind == 3 ? 0x5A5650 : 0x5E3B22, light: UInt32 = kind == 3 ? 0xF0ECE2 : 0xA9743F
        let palettes: [(UInt32, UInt32, UInt32)] = [
            (0x6CC04A, 0xA6E36E, 0x3E8E3A),   // oak
            (0x3E8E5A, 0x6CB87A, 0x2A6640),   // pine
            (0x7CC24E, 0xB0E37A, 0x4A8E36),   // maple
            (0x9ACD5A, 0xC8EC8A, 0x6A9E3A),   // birch
            (0x6CC04A, 0xA6E36E, 0x3E8E3A),   // cherry
            (0x8CC860, 0xBCE68C, 0x5E9A44),   // willow
        ]
        let autumnPalettes: [(UInt32, UInt32, UInt32)] = [
            (0xE08A2C, 0xF2B45C, 0xA8521E),   // oak: orange
            (0x3E8E5A, 0x6CB87A, 0x2A6640),   // pine: still green
            (0xC8402E, 0xE8705A, 0x8E2A20),   // maple: red
            (0xE8C04A, 0xF8E07A, 0xB8902A),   // birch: gold
            (0xD8644A, 0xF0957A, 0xA8402E),   // cherry: coral
            (0xC8C04A, 0xE4DC7A, 0x8E8A2E),   // willow: yellow-green
        ]
        let (lf, lfL, lfD) = autumn ? autumnPalettes[kind] : palettes[kind]
        let vine: UInt32 = 0x4FA03A
        let lean: Double = r.range(-3, 8)
        let wobble: Double = r.range(2.4, 4.2)
        let phase: Double = r.range(0, 3)
        let hh = Double(H - 12)          // the tree itself; the 12 rows above are headroom for the crown
        func trunkX(_ y: Double) -> Double { let t = y / hh; return x0 + lean * t + sin(t * 4.2 + phase) * wobble * (0.25 + t) }
        func trunkW(_ y: Double) -> Double { 12 - 7 * (y / hh) }
        // Limbs: (height, direction, length, rise). Mostly toward the open side; one props up the shelf.
        var limbs: [(y: Double, dir: Double, len: Double, rise: Double, prop: Bool)] = []
        let n = max(4, min(7, 3 + H / 24))
        for i in 0..<n {
            let spread: Double = 0.64 * Double(i) / Double(max(1, n - 1))
            let y: Double = hh * (0.26 + spread) + r.range(-4, 4)
            guard abs(y - Double(shelfPx)) > 7 else { continue }
            let dir: Double = (i % 3 == 1) ? -1 : (r.next() < 0.8 ? 1 : -1)
            // Taller trees spread wider (within the picture: more room on the open side than over the window).
            let reach: Double = min(1.7, 0.75 + hh / 130)
            let len: Double = min(dir < 0 ? 26 : 50, r.range(17, 36) * reach * (dir < 0 ? 0.7 : 1))
            let rise: Double = r.range(4, 16)
            limbs.append((y: y, dir: dir, len: len, rise: rise, prop: false))
        }
        limbs.append((y: Double(shelfPx) - 4, dir: -1, len: 30, rise: 3, prop: true))
        func leafCluster(_ x0: Double, _ y: Double, _ big: Double) {
            // Kept inside the picture.
            let x = x0.clamped(big + 2, Double(W) - big - 2)
            guard !winter else { if r.next() < 0.3 { cv.blob(x, y, 2.5, 1.6, base: 0xB8B6AE, light: 0xE8F4FF) }; return }
            cv.blob(x, y, big, big * 0.64, base: lf, light: lfL, shade: lfD)
            cv.blob(x - big * 0.55, y + big * 0.3, big * 0.62, big * 0.45, base: lf, light: lfL, shade: lfD)
            cv.blob(x + big * 0.5, y - big * 0.22, big * 0.58, big * 0.42, base: lf, light: lfL, shade: lfD)
            cv.blob(x + big * 0.1, y + big * 0.5, big * 0.5, big * 0.36, base: lf, light: lfL, shade: lfD)
            if spring || kind == 4 && !autumn { for _ in 0..<4 { cv.set(Int(x + r.range(-big, big)), Int(y + r.range(-2, 4)), 0xFFB6D9) } }   // blossom
            if evergreen && [12, 1, 2].contains(month) { for _ in 0..<3 { cv.set(Int(x + r.range(-big, big)), Int(y + big * 0.5), 0xFFFFFF) } }
            if autumn && r.next() < 0.6 { cv.set(Int(x + r.range(-big, big)), Int(y - big * 0.5), 0xC2562C) }
        }
        func hangingVine(_ x: Double, _ y: Double, _ len: Int) {
            var vx = x
            for k in 0..<len {
                if k % 3 == 2 { vx += r.next() < 0.5 ? -1 : 1 }
                let yy = y - Double(k)
                cv.set(Int(vx.rounded()), Int(yy.rounded()), k % 2 == 0 ? vine : lf)
                if k % 4 == 1 { cv.set(Int(vx.rounded()) + (k % 8 == 1 ? 1 : -1), Int(yy.rounded()), lfL) }
            }
        }
        // The crown, behind everything: a wide mass of clusters around the top of the trunk.
        let top = hh - 2, tx = trunkX(top)
        let crown: Double = min(1.5, 0.8 + hh / 160)
        for (dx, dy, rad) in [(-11.0, -5.0, 9.0), (9.0, -3.0, 9.0), (0.0, 0.0, 8.0), (-4.0, -11.0, 7.0), (17.0, -9.0, 7.5), (-16.0, -11.0, 6.0), (6.0, -14.0, 6.5), (22.0, -15.0, 5.5), (28.0, -8.0, 6.0)] {
            leafCluster(tx + dx * crown, top + dy * min(1.2, crown), rad * min(1.25, crown))
        }
        // Trunk with bark, roots, a knot hole, and a vine winding up it.
        for y in 0..<Int(hh) {
            let cx = trunkX(Double(y)), w = trunkW(Double(y))
            let xa = Int((cx - w / 2).rounded()), xb = Int((cx + w / 2).rounded()) - 1
            guard xb >= xa else { continue }
            for x in xa...xb {
                var c = bark
                if x == xa || x == xa + 1 && w > 7 || (x * 3 + y) % 13 == 0 || (x + y * 2) % 17 == 0 { c = dark }
                if x == xb && w > 4 { c = light }
                if x == xb - 1 && w > 8 && y % 5 != 0 { c = light }
                cv.set(x, y, c)
            }
        }
        for (side, len, lift) in [(-1.0, 12.0, 5.0), (1.0, 11.0, 5.0), (-1.0, 6.0, 2.5), (1.0, 5.0, 3.0), (0.3, 3.0, 1.0)] {
            cv.line(trunkX(lift) + side * 3, lift, trunkX(0) + side * len, 0, side < 0 ? dark : bark, width: 2)
        }
        let ky = hh * r.range(0.36, 0.52)
        cv.blob(trunkX(ky) + 0.5, ky, 1.7, 2.6, base: dark); cv.set(Int(trunkX(ky)), Int(ky), 0x3A2412); cv.set(Int(trunkX(ky)) + 1, Int(ky) + 1, 0x3A2412)
        for y in stride(from: 2, to: H - 4, by: 1) {
            let a = Double(y) / 4.5 + phase
            guard cos(a) > -0.2 else { continue }
            let vx = trunkX(Double(y)) + sin(a) * trunkW(Double(y)) * 0.45
            cv.set(Int(vx.rounded()), y, y % 2 == 0 ? vine : lf)
            if y % 5 == 0 { cv.set(Int(vx.rounded()) + (sin(a) > 0 ? 1 : -1), y, lfL) }
        }
        // Limbs: thick at the trunk, tapering, each with twigs, leaf clusters along it and a vine or two.
        var swingDone = false
        for l in limbs {
            let sx = trunkX(l.y) + l.dir * trunkW(l.y) * 0.3
            let steps = Int(l.len)
            var tipX = sx, tipY = l.y
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let x = sx + l.dir * l.len * t, y = l.y + l.rise * (0.35 * t + 0.65 * t * t) * (l.prop ? 0.4 : 1)
                let w = max(1, Int((4.6 * (1 - t) + (l.prop ? 2.2 : 1.0)).rounded()))
                cv.rect(Int(x.rounded()), Int(y.rounded()) - w / 2, 1, w, i % 6 == 2 ? dark : (i % 9 == 4 ? light : bark))
                if w >= 3 { cv.set(Int(x.rounded()), Int(y.rounded()) - w / 2, dark) }
                // Moss along the top of the limb, like everywhere else they live.
                if i % 3 != 2 && t < 0.85 { cv.set(Int(x.rounded()), Int(y.rounded()) - w / 2 + w, i % 5 == 0 ? 0x8BD66A : 0x5E9E46) }
                tipX = x; tipY = y
            }
            if l.prop {
                leafCluster(sx + l.dir * l.len * 0.5, l.y - 4, r.range(4, 5))
                continue
            }
            // Twigs off the limb, up and down.
            let mx = sx + l.dir * l.len * 0.5, my = l.y + l.rise * 0.28
            cv.line(mx, my, mx + l.dir * 6, my + 8, bark, width: 1)
            let dx2 = sx + l.dir * l.len * 0.72, dy2 = l.y + l.rise * 0.55
            cv.line(dx2, dy2, dx2 + l.dir * 4, dy2 - 6, dark, width: 1)
            leafCluster(mx + l.dir * 6, my + 9.5, r.range(5, 6.5))
            leafCluster(sx + l.dir * l.len * 0.8, tipY - 1, r.range(5.5, 7))
            leafCluster(tipX + l.dir * 2, tipY + 2.5, r.range(7, 9.5))
            if r.next() < 0.7 { hangingVine(tipX + l.dir * 4, tipY - 2, Int(r.range(8, 18))) }
            if r.next() < 0.5 { hangingVine(dx2 + l.dir * 4, dy2 - 7, Int(r.range(5, 10))) }
            // A rope swing under the first long limb on the open side.
            if !swingDone && l.dir > 0 && l.len > 24 && l.y > 34 {
                swingDone = true
                let ax = sx + l.dir * l.len * 0.62, ay = l.y + l.rise * 0.4
                cv.vspan(Int(ax.rounded()) - 2, Int(ay.rounded()) - 13, Int(ay.rounded()) - 1, 0xC9A66B)
                cv.vspan(Int(ax.rounded()) + 2, Int(ay.rounded()) - 13, Int(ay.rounded()) - 1, 0xC9A66B)
                cv.hspan(Int(ax.rounded()) - 3, Int(ax.rounded()) + 3, Int(ay.rounded()) - 14, light)
                cv.hspan(Int(ax.rounded()) - 3, Int(ax.rounded()) + 3, Int(ay.rounded()) - 15, dark)
            }
        }
        // A bird's nest in the crotch of a limb, moss and a toadstool at the foot.
        if let nest = limbs.first(where: { !$0.prop && $0.y < hh * 0.7 }) {
            let nx = trunkX(nest.y) + nest.dir * (trunkW(nest.y) * 0.5 + 3), ny = nest.y + 2.5
            cv.blob(nx, ny, 2.6, 1.3, base: 0xA9743F, shade: 0x6B4428)
            cv.set(Int(nx.rounded()), Int(ny.rounded()) + 1, 0xF4EFE6); cv.set(Int(nx.rounded()) + 1, Int(ny.rounded()) + 1, 0xDCE6F2)
        }
        cv.blob(trunkX(0) - 8, 1.6, 3.6, 1.5, base: 0x5E9E46, light: 0x8BD66A)
        cv.blob(trunkX(0) + 8, 1.2, 3.0, 1.3, base: 0x5E9E46, light: 0x8BD66A)
        cv.vspan(Int(trunkX(0)) + 11, 0, 1, 0xEBDDC3); cv.blob(trunkX(0) + 11.5, 2.6, 1.9, 1.1, base: 0xC23B3B, light: 0xE06060); cv.set(Int(trunkX(0)) + 11, 3, 0xFFF4E8)
        cv.outline(0.62)
        return mirror ? BridgeArt.flipped(cv).image : cv.image
    }

    /// The balloons a swing hangs from.
    static func swingBalloons() -> CGImage {
        var g: Grid = Array(repeating: Array(repeating: nil, count: 21), count: 12)
        let colors: [UInt32] = [0xFF6F7E, 0xFFD84A, 0x6FB8F0]
        for (i, cx) in [4, 10, 16].enumerated() {
            let cy = i == 1 ? 3 : 5
            for y in 0..<12 { for x in 0..<21 {
                let dx = Double(x - cx), dy = Double(y - cy) * 1.2
                if dx * dx + dy * dy <= 10 { g[y][x] = colors[i] }
            }}
            g[cy - 1][cx - 1] = 0xFFFFFF
        }
        return image(g)
    }

    /// Things to float with (held over the head) and the bouncy mushroom.
    static func ride(_ r: Ride, _ id: Int) -> CGImage {
        switch r {
        case .balloon, .bounce, .seed: return mapleSeed
        case .umbrella: return ClimateArt.leafUmbrella
        case .bubble: return image(grid([".", "."], [:]))
        case .dandelion:
            return image(grid([
                "..w.w.w..", ".w.www.w.", "w.wwWww.w", ".wwWWWww.", "wwWWyWWww", ".wwWWWww.", "w.wwWww.w", ".w.www.w.", "..w.w.w..",
                "....g....", "....g....", "....g....", "....g....",
            ], ["w": 0xFFFFFF, "W": 0xEDEDED, "y": 0xC9B79C, "g": 0x6CC04A]))
        case .leaf:
            return image(grid([
                "....gggg.....", "..gggGgggg...", ".ggGggGggggg.", "gggggGgggGggg", ".gGggggGggg..", "....GG.......",
                ".....G.......", ".....G.......",
            ], ["g": 0x8FD67A, "G": 0x3E8E3A]))
        }
    }

    /// A pair of maple-seed wings joined at the seeds, held over the head by a little stem (spun by the renderer).
    static let mapleSeed: CGImage = {
        var cv = PixelCanvas(19, 9)
        let wing: UInt32 = 0xD9A25E, wingLight: UInt32 = 0xF0C987, vein: UInt32 = 0xA8743E, seed: UInt32 = 0x8A5A35
        for (dir, x0) in [(-1.0, 9.0), (1.0, 9.0)] {
            for k in 0..<9 {
                let x = Int(x0 + dir * Double(k + 1))
                let lift = Int((Double(k) * 0.35).rounded())
                let thick = k < 2 ? 2 : (k < 7 ? 3 : 2)
                for y in 0..<thick { cv.set(x, 5 + lift - y + 1, y == 0 ? wingLight : wing) }
                if k % 3 == 1 { cv.set(x, 5 + lift, vein) }
            }
        }
        cv.blob(9, 5, 2.2, 1.7, base: seed, light: 0xB07A47)
        cv.vspan(9, 0, 3, 0x6B8A3A)
        cv.outline(0.7)
        return cv.image
    }()

    static let springMushroom = image(grid([
        "...rrrrrr...", ".rrWrrrrWrr.", "rrrrrWrrrrrr", "rWrrrrrrrWrr", "wwwwwwwwwwww", "....wwww....", "....wwww....", "...wwwwww...",
    ], ["r": 0xE8343F, "W": 0xFFFFFF, "w": 0xF4EAD8]))

    // MARK: Platform extras (drawn behind the platform's Gremlet)

    /// A flying carpet: patterned, with tassels; rippling (`phase` 0..<8).
    static var carpetCache: [String: CGImage] = [:]
    static func carpet(widthPx: Int, phase: Int) -> CGImage {
        let key = "\(widthPx)-\(phase)"
        if let c = carpetCache[key] { return c }
        let w = widthPx, h = 9
        var g: Grid = Array(repeating: Array(repeating: nil, count: w), count: h)
        let red: UInt32 = 0xC0393B, deep: UInt32 = 0x8A2430, gold: UInt32 = 0xF2C14E, teal: UInt32 = 0x3FA7A0
        for x in 0..<w {
            let off = Int((sin(Double(x) / 6 + Double(phase) / 8 * 2 * .pi) * 1.5).rounded()) + 2
            let rows: [UInt32] = [gold, x % 6 < 3 ? red : deep, (x % 8 == 3 || x % 8 == 4) ? teal : red, gold]
            for (i, c) in rows.enumerated() where off + i < h { g[off + i][x] = c }
            if x == 0 || x == w - 1 { for t in 0..<2 where off + 4 + t < h { g[off + 4 + t][x] = gold } }
        }
        let img = image(g)
        carpetCache[key] = img
        return img
    }

    /// A hot-air balloon envelope with stripes, its ropes, and the burner flame (`flame` 0 = off, 1-2 flickers).
    static func balloonEnvelope(seed: UInt64, flame: Int, ropeLength: Int) -> CGImage {
        let w = 44, bodyH = 40, h = bodyH + ropeLength
        var g: Grid = Array(repeating: Array(repeating: nil, count: w), count: h)
        let palettes: [[UInt32]] = [[0xFF6F7E, 0xFFE066], [0x6FB8F0, 0xFFFFFF], [0xA98BEA, 0xFFB35C], [0x8FD6A2, 0xFF8FBF]]
        let pal = palettes[Int(seed % UInt64(palettes.count))]
        let cx = Double(w) / 2 - 0.5
        for y in 0..<bodyH {
            // Teardrop: round on top, narrowing to the mouth.
            let t = Double(y) / Double(bodyH)
            let r = t < 0.62 ? max(0, 1 - pow((t - 0.42) / 0.42, 2)).squareRoot() * 21 : (1 - (t - 0.62) / 0.38) * 14 + 4
            for x in 0..<w {
                let dx = Double(x) - cx
                guard abs(dx) <= max(1, r) else { continue }
                let stripe = Int(((dx / max(1, r)) + 1) * 3) % 2
                var c = pal[stripe]
                if dx < -r * 0.45 && t < 0.5 { c = 0xFFFFFF }          // highlight
                if dx > r * 0.6 { c = stripe == 0 ? 0xD8455A : 0xD0D0D0 } // shade
                g[y][x] = t > 0.9 ? 0x7A5230 : c
            }
        }
        if flame > 0 {
            let fy = bodyH - 3
            for (dx, dy) in [(0, 0), (-1, 1), (1, 1), (0, 1), (0, 2)] + (flame == 2 ? [(-1, 2), (1, 2), (0, 3)] : []) {
                g[min(h - 1, fy + dy)][Int(cx) + dx] = dy < 2 ? 0xFFE066 : 0xFF9A3C
            }
        }
        for y in bodyH..<h {   // ropes down to the basket corners
            let k = Double(y - bodyH) / Double(max(1, ropeLength))
            g[y][min(w - 1, max(0, Int(cx - 9 - k * 9)))] = 0x5E3B22
            g[y][min(w - 1, max(0, Int(cx + 9 + k * 9)))] = 0x5E3B22
        }
        return image(g)
    }

    /// The treehouse: a little cabin with a pointed roof, round window and door.
    static let cabin: CGImage = image(grid([
        ".......rr.......",
        "......rRRr......",
        ".....rRRRRr.....",
        "....rRRRRRRr....",
        "...rRRRRRRRRr...",
        "..rRRRRRRRRRRr..",
        ".rrrrrrrrrrrrrr.",
        "..wwwwwwwwwwww..",
        "..wwbbwwwwkkww..",
        "..wwbbwwwwkkww..",
        "..wwwwwwwwkkww..",
        "..wwwwwwwwkkww..",
        "..dddddddddddd..",
    ], ["r": 0xB8463E, "R": 0xD8645A, "w": 0xD9A066, "b": 0xFFE9A8, "k": 0x6E4A26, "d": 0x7A5230]))

    /// The garden snail: body along the floor, a spiral shell rising to the platform, eyestalks (`look` 0-2).
    static var snailCache: [Int: CGImage] = [:]
    static func snailBody(look: Int) -> CGImage {
        if let c = snailCache[look] { return c }
        let w = 82, h = 24
        var g: Grid = Array(repeating: Array(repeating: nil, count: w), count: h)
        let body: UInt32 = 0xB9C98A, bodyDark: UInt32 = 0x8FA36A, shell: UInt32 = 0xC98B4A, shellDark: UInt32 = 0x8A5A35, swirl: UInt32 = 0xE8B26A
        // Foot along the ground, head at the front (right).
        for y in 18..<h { for x in 4..<(w - 2) { g[y][x] = y == h - 1 ? bodyDark : body } }
        for y in 10..<18 { for x in (w - 16)..<(w - 3) where (x - (w - 10)) * (x - (w - 10)) + (y - 15) * (y - 15) * 2 < 50 { g[y][x] = body } }
        g[15][w - 7] = 0x2B2620                                            // a smile-ish eye spot
        // Eyestalks: up, tilted, or tucked in.
        let stalk = [(-1, 7), (1, 6), (0, 2)][look]
        for i in 0..<stalk.1 { g[10 - i][w - 11 + (i * stalk.0) / 3] = bodyDark; g[10 - i][w - 7 + (i * stalk.0) / 3] = bodyDark }
        if stalk.1 > 3 { g[10 - stalk.1][w - 11 + (stalk.1 * stalk.0) / 3] = 0x2B2620; g[10 - stalk.1][w - 7 + (stalk.1 * stalk.0) / 3] = 0x2B2620 }
        // Shell: a big spiral sitting on the foot, its flat top lines up with the platform.
        let scx = 34.0, scy = 9.0
        for y in 0..<19 { for x in 6..<62 {
            let dx = Double(x) - scx, dy = (Double(y) - scy) * 1.6
            let d = (dx * dx + dy * dy).squareRoot()
            guard d < 27 else { continue }
            let ang = atan2(dy, dx)
            let ring = (d + ang * 4.3).truncatingRemainder(dividingBy: 9)
            g[y][x] = abs(ring) < 1.4 ? shellDark : (dx < -8 && dy < 0 ? swirl : shell)
        }}
        let img = image(g)
        snailCache[look] = img
        return img
    }

    static let bird: [CGImage] = [
        image(grid(["..k.", ".bbo", "bbb.", ".b..", ], ["b": 0x6F8FA6, "k": 0x2B2620, "o": 0xFFB35C])),
        image(grid(["b..b", ".bbo", "bbb.", "....", ], ["b": 0x6F8FA6, "k": 0x2B2620, "o": 0xFFB35C])),
    ]

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
        // Claude sessions: what Claude is up to, at a glance.
        if j.kind == .claude {
            var parts: [String] = [j.label ?? "Claude"]
            if j.needsYou { parts.append("needs you") }
            else if j.phase == .finished || j.phase == .leaving { parts.append("done ✓") }
            else {
                switch j.lastTool {
                case .build?: parts.append("editing files")
                case .look?: parts.append("reading")
                case .run?: parts.append("running commands")
                case .web?: parts.append("on the web")
                case .spawn?: parts.append("sent out helpers")
                case .plan?: parts.append("planning")
                default: parts.append("thinking")
                }
            }
            if j.blocks > 0 { parts.append("\(j.blocks) edit\(j.blocks == 1 ? "" : "s")") }
            if j.helpers > 0 { parts.append("\(j.helpers) helper\(j.helpers == 1 ? "" : "s")") }
            switch j.weather { case .storm: parts.append("stormy ⛈"); case .rain: parts.append("a failed command"); case .sunny: parts.append("tests passed ☀︎"); case .clear: break }
            let mins = Int(j.workSeconds / 60)
            if mins > 0 { parts.append("\(mins) min") }
            return parts.joined(separator: " · ")
        }
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

}

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
