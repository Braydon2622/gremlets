import AppKit
import GremletsCore

// Small drawing helpers for hand-built pixel scenes.
extension PixelCanvas {
    mutating func hspan(_ x0: Int, _ x1: Int, _ y: Int, _ c: UInt32) { for x in min(x0, x1)...max(x0, x1) { set(x, y, c) } }
    mutating func vspan(_ x: Int, _ y0: Int, _ y1: Int, _ c: UInt32) { for y in min(y0, y1)...max(y0, y1) { set(x, y, c) } }
    func solid(_ x: Int, _ y: Int) -> Bool { get(x, y) != nil }

    /// Filled triangle (scanline), points in art pixels.
    mutating func triangle(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double), _ col: UInt32) {
        let pts = [a, b, c].sorted { $0.1 < $1.1 }
        let (p0, p1, p2) = (pts[0], pts[1], pts[2])
        guard p2.1 > p0.1 else { return }
        for y in Int(p0.1.rounded())...Int(p2.1.rounded()) {
            let fy = Double(y) + 0.5
            guard fy >= p0.1, fy <= p2.1 else { continue }
            let xa = p0.0 + (p2.0 - p0.0) * (fy - p0.1) / (p2.1 - p0.1)
            let xb = fy < p1.1 ? (p1.1 > p0.1 ? p0.0 + (p1.0 - p0.0) * (fy - p0.1) / (p1.1 - p0.1) : p1.0)
                : (p2.1 > p1.1 ? p1.0 + (p2.0 - p1.0) * (fy - p1.1) / (p2.1 - p1.1) : p1.0)
            hspan(Int(min(xa, xb).rounded()), Int(max(xa, xb).rounded()) - 1, y, col)
        }
    }

    /// A rectangle with its corners knocked off.
    mutating func roundedRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, radius r: Int, _ c: UInt32) {
        for yy in y..<(y + h) { for xx in x..<(x + w) {
            let dx = max(0, max(x + r - xx, xx - (x + w - 1 - r))), dy = max(0, max(y + r - yy, yy - (y + h - 1 - r)))
            if dx * dx + dy * dy <= r * r + r { set(xx, yy, c) }
        }}
    }

    /// The top half of an ellipse standing on `baseY` (igloos, mushroom caps, dome roofs).
    mutating func dome(_ cx: Double, baseY: Int, rx: Double, ry: Double, _ c: UInt32) {
        for y in baseY...Int(Double(baseY) + ry) {
            let t = (Double(y - baseY) + 0.5) / ry
            guard t <= 1 else { continue }
            let hw = rx * (1 - t * t).squareRoot()
            hspan(Int((cx - hw).rounded()), Int((cx + hw).rounded()) - 1, y, c)
        }
    }

    /// Nudges every pixel's brightness by a seeded amount, so flat fills read as weathered plaster or stone.
    mutating func weather(_ amount: Double, seed: UInt64, where keep: (UInt32) -> Bool = { _ in true }) {
        var r = ArtRNG(s: seed)
        for i in px.indices {
            guard let c = px[i], keep(c) else { r.s &+= 1; continue }
            let f = 1 + (r.next() - 0.5) * amount
            px[i] = PixelCanvas.scale(c, f)
        }
    }
    static func scale(_ c: UInt32, _ f: Double) -> UInt32 {
        func ch(_ v: UInt32) -> UInt32 { UInt32(min(255, max(0, Double(v) * f))) }
        return ch(c >> 16 & 0xFF) << 16 | ch(c >> 8 & 0xFF) << 8 | ch(c & 0xFF)
    }
}

/// The houses Gremlets put up while Claude works, one block of the picture per file Claude edits. Each biome has its
/// own hand-built home at art-pixel resolution (a timber cottage, an igloo, an adobe, a mossy temple, a mushroom
/// house, a crystal spire, a lighthouse on a cloud), so a finished house reads as a house and not as a stack of
/// blocks. `lit` is the finished house at night: windows glowing, lamps on.
enum HouseArt {
    // Shared palette.
    static let beam: UInt32 = 0x6B4428, woodDark: UInt32 = 0x5E3B22, wood: UInt32 = 0x8A5A35, woodLight: UInt32 = 0xC98B4A
    static let plaster: UInt32 = 0xF1E4C8, plasterShade: UInt32 = 0xD9C9A8
    static let stone: UInt32 = 0x8E8B83, stoneLight: UInt32 = 0xB8B6AE, stoneDark: UInt32 = 0x5E5B55
    static let glass: UInt32 = 0x9FD8F0, glassLit: UInt32 = 0xFFE08A, glassHi: UInt32 = 0xD6F2FF
    static let door: UInt32 = 0x7A4A24, doorDark: UInt32 = 0x5A3418, knob: UInt32 = 0xF2C94C
    static let leaf: UInt32 = 0x5E9E46, leafLight: UInt32 = 0x8BD66A, leafDark: UInt32 = 0x3E7A34

    static func sprite(_ b: Biome, lit: Bool) -> PixelCanvas {
        switch b {
        case .meadow, .autumn, .cherry: return cottage(b, lit: lit)
        case .snow: return igloo(lit: lit)
        case .desert: return adobe(lit: lit)
        case .jungle: return temple(lit: lit)
        case .glowshroom: return mushroomHouse(lit: lit)
        case .crystal: return spire(lit: lit)
        case .sky: return lighthouse(lit: lit)
        }
    }

    /// Where a Gremlet stands on the finished house (art pixels above the ground, half width). The ridge of the
    /// cottage, the top of the dome, the adobe's roof terrace, the shrine, the cap; nowhere on a spire or a lighthouse.
    static func roof(_ b: Biome) -> (y: Double, halfW: Double) {
        switch b {
        case .meadow, .autumn, .cherry: return (44, 5)
        case .snow: return (26, 5)
        case .desert: return (32, 8)
        case .jungle: return (39, 4)
        case .glowshroom: return (39, 5)
        case .crystal, .sky: return (0, 0)
        }
    }

    /// Where the smoke comes out, as fractions of the sprite's width and height.
    static func chimney(_ b: Biome) -> (x: Double, y: Double) {
        switch b {
        case .meadow, .autumn, .cherry: return (0.77, 0.93)
        case .snow: return (0.49, 0.88)
        case .desert: return (0.69, 1.0)
        case .jungle: return (0.5, 1.0)
        case .glowshroom: return (0.6, 1.0)
        case .crystal: return (0.5, 1.0)
        case .sky: return (0.5, 0.86)
        }
    }

    // MARK: Cottage (meadow, autumn, cherry)

    static func cottage(_ b: Biome, lit: Bool) -> PixelCanvas {
        var cv = PixelCanvas(35, 45)
        let roof: (base: UInt32, light: UInt32, dark: UInt32) = b == .cherry ? (0xE07AA8, 0xF7B6D2, 0xA84E7A)
            : b == .autumn ? (0xC2562C, 0xE07A44, 0x8A3A1E) : (0xC23B3B, 0xE06060, 0x8A2626)
        let pane = lit ? glassLit : glass
        // Foundation: a course of fieldstone.
        for y in 0..<4 { for x in 3...31 {
            let joint = (x + (y % 2) * 2) % 4 == 0
            cv.set(x, y, joint ? stoneDark : ((x / 4 + y) % 3 == 0 ? stoneLight : stone))
        }}
        // Plaster walls in a timber frame, shaded under the eaves.
        cv.rect(4, 4, 27, 20, plaster)
        cv.rect(4, 21, 27, 3, plasterShade)
        cv.weather(0.06, seed: 11) { $0 == plaster || $0 == plasterShade }
        for x in [4, 17, 30] { cv.vspan(x, 4, 23, beam) }
        for y in [4, 13, 23] { cv.hspan(4, 30, y, beam) }
        cv.line(18, 14, 23.5, 22, beam); cv.line(29, 14, 23.5, 22, beam)      // a brace in the upper panel
        cv.line(5, 14, 10, 22, beam)                                           // and one over the door
        // The door: arched, planked, with a step and a brass knob.
        cv.hspan(6, 13, 3, stoneLight)
        cv.rect(7, 4, 6, 9, door); cv.hspan(8, 11, 13, door); cv.hspan(9, 10, 14, door)
        cv.vspan(9, 4, 12, doorDark); cv.vspan(11, 4, 12, doorDark)
        cv.vspan(6, 4, 13, woodLight); cv.vspan(13, 4, 13, woodLight); cv.hspan(7, 12, 14, woodLight); cv.hspan(8, 11, 15, woodLight)
        cv.set(11, 8, knob)
        // A window with four panes, shutters and a flower box.
        cv.rect(19, 9, 9, 9, beam)
        for (px, py) in [(20, 10), (24, 10), (20, 14), (24, 14)] { cv.rect(px, py, 3, 3, pane); cv.set(px, py + 2, lit ? 0xFFF3C4 : glassHi) }
        for x in [17, 18, 28, 29] { for y in 10...16 { cv.set(x, y, y % 3 == 0 ? leafDark : 0x4F8A3A) } }
        cv.rect(18, 7, 11, 2, wood); cv.hspan(18, 28, 8, woodLight)
        for (i, x) in [19, 21, 23, 25, 27].enumerated() { cv.set(x, 9, [0xFF8FB1, 0xFFE45C, 0xFFFFFF, 0xFF8FB1, 0xB98CFF][i]); cv.set(x, 8, leaf) }
        // A lantern by the door.
        cv.set(15, 15, woodDark); cv.vspan(15, 11, 14, lit ? 0xFFE066 : 0xFFB43A); cv.set(15, 10, woodDark)
        if lit { cv.set(14, 12, 0xFFF3A0); cv.set(16, 12, 0xFFF3A0) }
        // The roof: a gable with deep eaves, shingles in staggered rows, a lighter ridge.
        cv.hspan(0, 34, 24, woodDark)
        for y in 25...43 {
            let t = Double(y - 25) / 18.0
            let hw = 17.5 * (1 - t)
            let x0 = Int((17.5 - hw).rounded()), x1 = Int((17.5 + hw).rounded()) - 1
            guard x1 >= x0 else { continue }
            let band = (y - 25) % 3
            for x in x0...x1 {
                var c = band == 0 ? roof.dark : roof.base
                if band != 0 && (x + ((y - 25) / 3) * 2) % 5 == 0 { c = roof.dark }
                if x <= x0 + 1 { c = roof.light }
                if y >= 42 { c = roof.light }
                cv.set(x, y, c)
            }
        }
        // Attic window in the gable.
        cv.blob(17.5, 31.5, 2.8, 2.8, base: beam)
        cv.blob(17.5, 31.5, 1.6, 1.6, base: pane, light: lit ? 0xFFF3C4 : glassHi)
        // Chimney rising through the roof.
        for y in 31...40 { for x in 25...28 { cv.set(x, y, (x + y) % 3 == 0 ? stoneDark : (y % 2 == 0 ? stone : stoneLight)) } }
        cv.hspan(24, 29, 41, stoneDark); cv.hspan(26, 27, 40, 0x3A3A3A)
        // A bush and a mushroom by the wall.
        cv.blob(1.8, 2.6, 2.4, 2.2, base: leaf, light: leafLight, shade: leafDark)
        cv.set(1, 3, b == .cherry ? 0xFF9EC7 : 0xFFE45C)
        cv.set(33, 0, 0xEBDDC3); cv.hspan(32, 34, 1, 0xC23B3B); cv.set(33, 1, 0xFFF4E8)
        cv.outline(0.7)
        return cv
    }

    // MARK: Igloo

    static func igloo(lit: Bool) -> PixelCanvas {
        var cv = PixelCanvas(35, 30)
        let ice: UInt32 = 0xDDF2FF, mortar: UInt32 = 0xA9CFEA, shade: UInt32 = 0xBFD9EE
        func brick(_ x: Int, _ y: Int, hw: Double, cx: Double) -> UInt32 {
            if y % 4 == 3 { return mortar }
            if (x + (y / 4) * 3) % 7 == 0 { return mortar }
            if Double(x) > cx + hw * 0.55 { return shade }
            if Double(x) < cx - hw * 0.25 && y > 12 { return 0xFFFFFF }
            return ice
        }
        for y in 0..<26 {
            let t = max(0, Double(y) - 1) / 25
            let hw = 16.5 * (1 - t * t).squareRoot()
            for x in Int((17.5 - hw).rounded())..<Int((17.5 + hw).rounded()) { cv.set(x, y, brick(x, y, hw: hw, cx: 17.5)) }
        }
        for y in 24...25 { for x in 10...25 where cv.solid(x, y) { cv.set(x, y, 0xFFFFFF) } }   // fresh snow on top
        // The tunnel entrance, with a warm glow inside after dark.
        for y in 0..<10 {
            let hw = 7.5 * (1 - pow(Double(y) / 10, 2)).squareRoot()
            for x in Int((27.5 - hw).rounded())..<Int((27.5 + hw).rounded()) { cv.set(x, y, brick(x, y, hw: hw, cx: 27.5)) }
        }
        for y in 0..<7 {
            let hw = 4.2 * (1 - pow(Double(y) / 7, 2)).squareRoot()
            for x in Int((27.5 - hw).rounded())..<Int((27.5 + hw).rounded()) { cv.set(x, y, lit ? (y < 3 ? 0xFFC26B : 0x8A5A35) : 0x2F4A66) }
        }
        if lit { cv.set(27, 1, 0xFFF3A0) }
        for (x, y0, n) in [(21, 7, 2), (33, 5, 2), (24, 9, 1)] { for k in 0..<n { cv.set(x, y0 - k, 0xBFE8FF) } }   // icicles
        cv.hspan(17, 18, 25, 0x3A4A5A)                                            // smoke hole
        // A stacked snowball and a fish on a line.
        cv.blob(3, 2, 2.2, 2, base: 0xFFFFFF, shade: shade); cv.blob(3, 4.5, 1.4, 1.3, base: 0xFFFFFF, shade: shade)
        cv.vspan(2, 6, 9, woodDark); cv.set(3, 8, 0x8FE3FF); cv.set(4, 8, 0x6FB8F0)
        cv.outline(0.78)
        return cv
    }

    // MARK: Adobe

    static func adobe(lit: Bool) -> PixelCanvas {
        var cv = PixelCanvas(35, 35)
        let sand: UInt32 = 0xE8C98A, sandLight: UInt32 = 0xF7E2B0, sandShade: UInt32 = 0xD0A866, teal: UInt32 = 0x3FA8A0
        cv.roundedRect(3, 3, 29, 22, radius: 2, sand)
        cv.roundedRect(10, 24, 17, 8, radius: 2, sand)
        cv.weather(0.05, seed: 23)
        for y in 3...24 { cv.set(29, y, sandShade); cv.set(30, y, sandShade); if y < 23 { cv.set(31, y, sandShade) } }
        for y in 24...31 where y < 31 { cv.set(25, y, sandShade); cv.set(26, y, sandShade) }
        for x in 4...8 { cv.set(x, 24, sandLight) }
        cv.hspan(3, 31, 25, sandShade); cv.hspan(10, 26, 32, sandShade)
        for x in [5, 10, 15, 20, 25] { cv.set(x, 21, woodDark); cv.set(x, 22, wood) }       // vigas
        for x in [13, 18, 23] { cv.set(x, 29, woodDark); cv.set(x, 30, wood) }
        cv.hspan(3, 31, 3, sandShade)
        // Arched door in a turquoise frame.
        cv.rect(14, 3, 6, 9, 0x4A2E1A); cv.hspan(15, 18, 12, 0x4A2E1A); cv.hspan(16, 17, 13, 0x4A2E1A)
        cv.vspan(13, 3, 12, teal); cv.vspan(20, 3, 12, teal); cv.set(14, 13, teal); cv.set(19, 13, teal); cv.set(15, 14, teal); cv.set(18, 14, teal); cv.hspan(16, 17, 15, teal)
        cv.set(18, 8, knob)
        // Two framed windows, and a small one upstairs.
        let pane = lit ? glassLit : glass
        for wx in [5, 23] {
            cv.rect(wx, 13, 6, 6, teal); cv.rect(wx + 1, 14, 4, 4, pane); cv.set(wx + 1, 17, lit ? 0xFFF3C4 : glassHi)
        }
        cv.rect(15, 26, 6, 4, teal); cv.rect(16, 27, 4, 2, pane)
        // A striped awning over the door.
        for x in 11...22 { for y in 16...17 { cv.set(x, y, (x / 2) % 2 == 0 ? 0xC23B3B : 0xFFF6DA) } }
        for x in stride(from: 11, through: 21, by: 2) { cv.set(x, 15, 0xC23B3B) }
        // A ladder up to the roof terrace.
        cv.vspan(28, 4, 31, 0xA9743F); cv.vspan(30, 4, 31, 0xA9743F)
        for y in stride(from: 6, through: 30, by: 3) { cv.set(29, y, 0xC98B4A) }
        // A chimney pipe, a potted cactus, a string of chillies.
        cv.rect(23, 32, 2, 3, stone); cv.set(23, 34, stoneDark)
        cv.hspan(0, 2, 0, 0xB8463E); cv.hspan(0, 2, 1, 0xD8645A); cv.vspan(1, 2, 7, 0x4F8A3A); cv.set(0, 5, 0x4F8A3A); cv.set(0, 6, 0x4F8A3A); cv.set(1, 8, 0xFF8FB1)
        for (i, y) in [19, 18, 17, 16].enumerated() { cv.set(7 + i % 2, y, 0xC23B3B) }
        cv.outline(0.72)
        return cv
    }

    // MARK: Jungle temple

    static func temple(lit: Bool) -> PixelCanvas {
        var cv = PixelCanvas(35, 40)
        let base: UInt32 = 0x7D8A6A, light: UInt32 = 0x9FB088, dark: UInt32 = 0x55604A, moss: UInt32 = 0x5FB84A, gold: UInt32 = 0xD6B050
        var r = ArtRNG(s: 404)
        let tiers = [(1, 33, 0, 11), (6, 28, 12, 23), (11, 23, 24, 32)]
        for (x0, x1, y0, y1) in tiers {
            for y in y0...y1 { for x in x0...x1 {
                var c = y % 3 == 2 ? dark : ((x + (y / 3) * 4) % 6 == 0 ? dark : base)
                if y == y1 { c = light }
                if x == x0 { c = light }
                cv.set(x, y, c)
            }}
            for x in x0...x1 where r.next() < 0.35 { cv.set(x, y1, moss) }
            for x in x0...(x0 + 2) where r.next() < 0.5 { cv.set(x, Int(r.range(Double(y0), Double(y1))), moss) }
        }
        // The shrine on top with a golden sun.
        cv.rect(14, 33, 7, 5, base); cv.hspan(13, 21, 38, light); cv.hspan(13, 21, 33, dark)
        cv.blob(17.5, 35.5, 1.8, 1.8, base: gold, light: lit ? 0xFFF3A0 : 0xF2D97A)
        // Steps up the middle to the shrine.
        for y in 12...32 { for x in 15...19 { cv.set(x, y, y % 2 == 0 ? dark : light) } }
        // The doorway with its lintel, and carved glyphs either side.
        cv.rect(14, 0, 7, 10, lit ? 0x3E4A32 : 0x2E3A2C); cv.hspan(13, 21, 10, light); cv.hspan(13, 21, 11, dark)
        if lit { cv.set(17, 4, 0xFFB43A); cv.set(17, 5, 0xFFE066) }
        for (gx, gy) in [(5, 5), (8, 5), (26, 5), (29, 5)] {
            cv.rect(gx, gy, 2, 2, gold); cv.set(gx, gy + 3, dark); cv.set(gx + 1, gy - 1, dark)
        }
        // Torches on the first terrace.
        for x in [3, 31] {
            cv.vspan(x, 12, 13, beam)
            cv.set(x, 14, 0xFFB43A); cv.set(x, 15, lit ? 0xFFE066 : 0xFF9A3C)
            if lit { cv.set(x - 1, 14, 0xFFE066); cv.set(x + 1, 14, 0xFFE066) }
        }
        // Vines spilling over the terraces, and a fern.
        for (x, top, len) in [(2, 11, 6), (9, 23, 8), (27, 23, 6), (33, 11, 5), (23, 32, 5)] {
            for k in 0..<len { cv.set(x + (k % 3 == 2 ? 1 : 0), top - k, k % 2 == 0 ? 0x4FA03A : 0x6BD15A) }
        }
        cv.blob(1.5, 1.5, 1.8, 1.6, base: 0x4FA03A, light: 0x6BD15A)
        cv.outline(0.72)
        return cv
    }

    // MARK: Mushroom house

    static func mushroomHouse(lit: Bool) -> PixelCanvas {
        var cv = PixelCanvas(35, 40)
        let cream: UInt32 = 0xEBDDC3, creamShade: UInt32 = 0xC8B596, cap: UInt32 = lit ? 0x5FE8FF : 0x3FA8E0
        let capLight: UInt32 = lit ? 0xBFFFFF : 0x7FD0F0, capDark: UInt32 = lit ? 0x2E9AC8 : 0x2A6FA8
        // The stem is the house.
        cv.roundedRect(10, 0, 15, 22, radius: 2, cream)
        cv.weather(0.05, seed: 7)
        for y in 0...21 { cv.set(23, y, creamShade); cv.set(24, y, creamShade); cv.set(10, y, 0xF7EEDC) }
        // A round-topped door and two porthole windows.
        cv.rect(14, 0, 7, 8, 0x6E4A26); cv.hspan(15, 19, 8, 0x6E4A26); cv.hspan(16, 18, 9, 0x6E4A26)
        cv.vspan(13, 0, 8, 0xA9743F); cv.vspan(21, 0, 8, 0xA9743F); cv.set(14, 9, 0xA9743F); cv.set(20, 9, 0xA9743F); cv.hspan(15, 19, 10, 0xA9743F)
        cv.vspan(17, 0, 7, 0x5A3418); cv.set(19, 4, knob)
        let pane = lit ? glassLit : glass
        for cx in [12.5, 22.5] {
            cv.blob(cx, 15.5, 2.7, 2.7, base: 0x6E4A26)
            cv.blob(cx, 15.5, 1.7, 1.7, base: pane, light: lit ? 0xFFF3C4 : glassHi)
        }
        // Gills under the cap, then the cap itself: a broad brim and a dome, spotted.
        for y in 20...22 { for x in 6...28 { cv.set(x, y, x % 2 == 0 ? 0xB8A585 : 0xD7C7A4) } }
        cv.blob(17.5, 27, 17.5, 6.5, base: cap, light: capLight, shade: capDark)
        cv.dome(17.5, baseY: 26, rx: 13, ry: 13, cap)
        for y in 26...39 { for x in 0..<35 where cv.get(x, y) == cap {
            let dx = Double(x) - 17.5, dy = Double(y - 26)
            if dx < -4 && dy > 2 && dy < 11 { cv.set(x, y, capLight) }
            if dx > 8 || (dy > 11 && dx > 2) { cv.set(x, y, capDark) }
        }}
        var r = ArtRNG(s: 99)
        for _ in 0..<9 {
            let x = r.range(3, 32), y = r.range(23, 37), rad = r.range(1.2, 2.3)
            if cv.get(Int(x), Int(y)) == cap || cv.get(Int(x), Int(y)) == capLight || cv.get(Int(x), Int(y)) == capDark {
                cv.blob(x, y, rad, rad * 0.85, base: 0xEAFBFF)
            }
        }
        if lit { for (x, y) in [(6, 30), (28, 31), (17, 38)] { cv.set(x, y, 0xFFFFFF) } }
        // Little mushrooms growing at the base.
        cv.vspan(6, 0, 2, cream); cv.blob(6.5, 3.2, 2.2, 1.4, base: 0xC4467A, light: 0xF07AA6); cv.set(6, 3, 0xFFF4E8)
        cv.vspan(29, 0, 1, cream); cv.blob(29.5, 2.2, 1.6, 1.1, base: 0xC4467A, light: 0xF07AA6)
        cv.outline(0.72)
        return cv
    }

    // MARK: Crystal spire

    static func spire(lit: Bool) -> PixelCanvas {
        var cv = PixelCanvas(30, 50)
        let lightF: UInt32 = 0xF3D9FF, midF: UInt32 = 0xB57AF2, darkF: UInt32 = 0x7E4AB8, edge: UInt32 = 0x5A2F8E
        cv.blob(14.5, 2.5, 13.5, 3.2, base: 0x6E6A78, light: 0x8F8A9E, shade: 0x524E5C)
        for y in 4..<48 {
            let w: Double = y < 10 ? 16 : y < 38 ? 16 - Double(y - 10) * 0.15 : 11.8 - Double(y - 38) * 1.15
            guard w > 0.6 else { continue }
            let x0 = 14.5 - w / 2, x1 = 14.5 + w / 2
            for x in Int(x0.rounded())..<Int(x1.rounded()) {
                let t = (Double(x) + 0.5 - x0) / w
                var c = t < 0.3 ? lightF : t < 0.62 ? midF : darkF
                if x == Int(x0.rounded()) + 1 && y > 8 && y < 44 { c = 0xFFFFFF }
                if abs(t - 0.3) < 0.04 || abs(t - 0.62) < 0.04 { c = edge }
                if lit && t > 0.42 && t < 0.52 && y % 2 == 0 { c = 0xE6CCFF }
                cv.set(x, y, c)
            }
        }
        // Door and a diamond window that glows.
        cv.rect(12, 4, 6, 8, 0x3A2A52); cv.hspan(13, 16, 12, 0x3A2A52); cv.hspan(14, 15, 13, 0x3A2A52)
        cv.vspan(11, 4, 12, darkF); cv.vspan(18, 4, 12, darkF); cv.hspan(12, 17, 14, darkF)
        if lit { cv.set(14, 8, 0xFFB43A) }
        for dy in -3...3 { let hw = 3 - abs(dy); cv.hspan(14 - hw, 15 + hw, 26 + dy, dy == 3 || dy == -3 ? edge : (lit ? 0xFFF3A0 : glassHi)) }
        cv.set(14, 26, lit ? 0xFFFFFF : 0xFFFFFF)
        // Shards leaning against the base.
        cv.triangle((1, 2), (7, 2), (5.5, 18), lightF); cv.triangle((4.5, 2), (7, 2), (5.5, 18), darkF)
        cv.triangle((22, 2), (29, 2), (26, 14), lightF); cv.triangle((25.5, 2), (29, 2), (26, 14), darkF)
        cv.triangle((8, 2), (12, 2), (10.5, 9), midF)
        if lit { for (x, y) in [(5, 14), (26, 11), (14, 40)] { cv.set(x, y, 0xFFFFFF) } }
        cv.outline(0.72)
        return cv
    }

    // MARK: Lighthouse on a cloud

    static func lighthouse(lit: Bool) -> PixelCanvas {
        var cv = PixelCanvas(30, 50)
        let white: UInt32 = 0xF2F2F2, red: UInt32 = 0xD8455A, redShade: UInt32 = 0xA83040, whiteShade: UInt32 = 0xC9CCD6
        for (x, y, rr) in [(6.0, 3.0, 5.5), (14.5, 4.0, 7.0), (23.0, 3.0, 5.5), (10.0, 1.8, 5.0), (19.0, 1.8, 5.0)] {
            cv.blob(x, y, rr, rr * 0.75, base: 0xF5FAFF, light: 0xFFFFFF, shade: 0xC6D6EA)
        }
        for y in 7...35 {
            let w = 16 - Double(y - 7) * (4.0 / 28)
            let x0 = Int((14.5 - w / 2).rounded()), x1 = Int((14.5 + w / 2).rounded()) - 1
            let band = ((y - 7) / 5) % 2 == 0
            for x in x0...x1 {
                var c = band ? white : red
                if x >= x1 - 1 { c = band ? whiteShade : redShade }
                if x == x0 { c = band ? 0xFFFFFF : 0xE86A7A }
                cv.set(x, y, c)
            }
        }
        cv.rect(12, 7, 6, 7, 0x5A2E3A); cv.hspan(13, 16, 14, 0x5A2E3A); cv.hspan(14, 15, 15, 0x5A2E3A)
        cv.vspan(11, 7, 14, 0x8A4A5A); cv.vspan(18, 7, 14, 0x8A4A5A); cv.hspan(12, 17, 16, 0x8A4A5A)
        cv.set(16, 10, knob)
        let pane = lit ? glassLit : glass
        for cy in [21.5, 29.5] {
            cv.blob(14.5, cy, 2.5, 2.5, base: 0x4A4A4A)
            cv.blob(14.5, cy, 1.5, 1.5, base: pane, light: lit ? 0xFFF3C4 : glassHi)
        }
        // Gallery, railing, lamp room, dome.
        cv.rect(5, 36, 20, 2, stoneDark); cv.hspan(5, 24, 37, stone)
        for x in [5, 8, 11, 18, 21, 24] { cv.vspan(x, 38, 39, stoneDark) }
        cv.hspan(5, 24, 40, stoneDark)
        cv.rect(9, 38, 12, 7, lit ? 0xFFE98A : glass)
        for x in [9, 14, 15, 20] { cv.vspan(x, 38, 44, 0x4A4A4A) }
        cv.hspan(9, 20, 38, 0x4A4A4A); cv.hspan(8, 21, 45, 0x4A4A4A)
        cv.blob(14.5, 41.5, 1.7, 1.7, base: lit ? 0xFFFFFF : 0xFFD45E, light: 0xFFFFFF)
        if lit { for x in [10, 12, 17, 19] { cv.set(x, 41, 0xFFF3A0) } }
        cv.dome(14.5, baseY: 46, rx: 6.5, ry: 2.6, red)
        cv.hspan(12, 16, 46, 0xE86A7A)
        cv.vspan(14, 48, 49, stoneDark)
        cv.outline(0.72)
        return cv
    }
}
