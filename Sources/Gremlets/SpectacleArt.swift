import AppKit
import GremletsCore

/// A tiny pixel canvas for procedural art (grove plants, the Stormwyrm). Everything is drawn at "art pixel"
/// resolution and shown with nearest-neighbour scaling, so it matches the Gremlets' chunky pixel look.
struct PixelCanvas {
    let w: Int, h: Int
    var px: [UInt32?]

    init(_ w: Int, _ h: Int) { self.w = max(1, w); self.h = max(1, h); px = Array(repeating: nil, count: self.w * self.h) }

    /// (0,0) is the bottom-left, like the screen.
    mutating func set(_ x: Int, _ y: Int, _ c: UInt32) {
        guard x >= 0, x < w, y >= 0, y < h else { return }
        px[(h - 1 - y) * w + x] = c
    }
    func get(_ x: Int, _ y: Int) -> UInt32? {
        guard x >= 0, x < w, y >= 0, y < h else { return nil }
        return px[(h - 1 - y) * w + x]
    }
    mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: UInt32) {
        for yy in y..<(y + rh) { for xx in x..<(x + rw) { set(xx, yy, c) } }
    }
    /// Filled ellipse with a simple top-left light: `light` on the upper-left, `base` in the middle, `shade` below.
    mutating func blob(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, base: UInt32, light: UInt32? = nil, shade: UInt32? = nil) {
        let x0 = Int(cx - rx - 1), x1 = Int(cx + rx + 1), y0 = Int(cy - ry - 1), y1 = Int(cy + ry + 1)
        for y in y0...y1 { for x in x0...x1 {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
            let d = dx * dx + dy * dy
            guard d <= 1 else { continue }
            var c = base
            if let l = light, dx * -0.6 + dy * 0.8 > 0.45 { c = l }
            if let s = shade, dy < -0.45 || dx * 0.5 + dy * -0.85 > 0.62 { c = s }
            set(x, y, c)
        }}
    }
    mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: UInt32, width: Int = 1) {
        let n = max(1, Int(max(abs(x1 - x0), abs(y1 - y0))))
        for i in 0...n {
            let t = Double(i) / Double(n)
            let x = Int(x0 + (x1 - x0) * t), y = Int(y0 + (y1 - y0) * t)
            rect(x - width / 2, y, width, 1, c)
        }
    }
    /// Darkens every pixel that touches transparency: a selective outline that keeps shapes readable at any size.
    mutating func outline(_ factor: Double = 0.55) {
        var out = px
        for y in 0..<h { for x in 0..<w {
            guard let c = get(x, y) else { continue }
            if get(x - 1, y) == nil || get(x + 1, y) == nil || get(x, y - 1) == nil || get(x, y + 1) == nil {
                out[(h - 1 - y) * w + x] = PixelCanvas.darken(c, factor)
            }
        }}
        px = out
    }
    static func darken(_ c: UInt32, _ f: Double) -> UInt32 {
        let r = Double(c >> 16 & 0xFF) * f, g = Double(c >> 8 & 0xFF) * f, b = Double(c & 0xFF) * (f + (1 - f) * 0.25)
        return UInt32(r) << 16 | UInt32(g) << 8 | UInt32(min(255, b))
    }
    var image: CGImage {
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            guard let c = px[i] else { continue }
            buf[i * 4] = UInt8(c >> 16 & 0xFF); buf[i * 4 + 1] = UInt8(c >> 8 & 0xFF); buf[i * 4 + 2] = UInt8(c & 0xFF); buf[i * 4 + 3] = 255
        }
        let provider = CGDataProvider(data: Data(buf) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

/// Deterministic little RNG for art (same plant, same look every time).
struct ArtRNG {
    var s: UInt64
    mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

/// Art pixels per screen point for the grove and the boss (the Gremlets use about 3).
let artScale = 3.0

enum GroveArt {
    /// Plant image for a grove plant (variant 1 = the snapjaw's closed mouth, the bouncecap squashed).
    static func image(_ p: GrovePlant, size: Vec2, variant: Int = 0, night: Bool) -> CGImage {
        let w = Int(size.x / artScale), h = Int(size.y / artScale)
        var cv = PixelCanvas(w, h)
        var r = ArtRNG(s: UInt64(GroveKind.allCases.firstIndex(of: p.kind) ?? 0) &+ 77)
        let W = Double(w), H = Double(h), cx = W / 2
        switch p.kind {
        case .sunberry:
            // A round bush of overlapping leafy clumps, berries tucked in, sun-coloured highlights.
            let clumps = 5 + p.level
            for i in 0..<clumps {
                let t = Double(i) / Double(clumps - 1)
                let x = W * (0.18 + 0.64 * t) + r.range(-1.5, 1.5)
                let y = H * (0.38 + 0.18 * sin(t * .pi)) + r.range(-1, 1)
                let rad = H * r.range(0.26, 0.36)
                cv.blob(x, y, rad * 1.1, rad, base: 0x4E9A3C, light: 0x8BCB52, shade: 0x2F6B2E)
            }
            cv.outline()
            var br = ArtRNG(s: 991)
            for _ in 0..<min(14, p.berries) {
                let x = br.range(W * 0.18, W * 0.82), y = br.range(H * 0.25, H * 0.75)
                let rr = max(1.2, H * 0.08)
                cv.blob(x, y, rr, rr, base: 0xF2683C, light: 0xFFD45E, shade: 0xB23A2A)
            }
        case .bouncecap:
            let squash = variant == 1 ? 0.82 : 1.0
            let stemW = W * 0.24, capH = H * 0.5 * squash
            cv.rect(Int(cx - stemW / 2), 0, Int(stemW), Int(H * 0.55 * squash), 0xEBDDC3)
            cv.rect(Int(cx - stemW / 2), 0, max(1, Int(stemW * 0.3)), Int(H * 0.55 * squash), 0xC8B596)
            cv.blob(cx, H * 0.5 * squash + capH * 0.45, W * 0.49, capH * 0.62, base: 0xC4467A, light: 0xF07AA6, shade: 0x8E2A5C)
            cv.outline()
            // Spots
            var sr = ArtRNG(s: 5)
            for _ in 0..<(3 + p.level) {
                let x = sr.range(W * 0.2, W * 0.8), y = H * 0.5 * squash + capH * sr.range(0.35, 0.85)
                let rr = max(1, W * sr.range(0.04, 0.07))
                if cv.get(Int(x), Int(y)) != nil { cv.blob(x, y, rr, rr * 0.8, base: 0xFFF4E8) }
            }
        case .lanternbloom:
            // Curving stem, two leaves, a drooping bell that glows after dark.
            for y in 0..<Int(H * 0.72) {
                let x = cx + sin(Double(y) / H * 3.2) * W * 0.12
                cv.rect(Int(x), y, max(1, Int(W * 0.08)), 1, 0x3D7A3A)
            }
            cv.blob(cx - W * 0.2, H * 0.28, W * 0.2, H * 0.06, base: 0x5BAA47, light: 0x8CD066)
            cv.blob(cx + W * 0.2, H * 0.45, W * 0.2, H * 0.06, base: 0x5BAA47, light: 0x8CD066)
            let bell = night ? (0xFFC845 as UInt32, 0xFFF1A6 as UInt32, 0xE08A1E as UInt32) : (0xF2A93B, 0xFFD782, 0xB86A1C)
            cv.blob(cx + W * 0.1, H * 0.74, W * 0.34, H * 0.2, base: bell.0, light: bell.1, shade: bell.2)
            cv.outline(night ? 0.8 : 0.55)
            cv.rect(Int(cx + W * 0.1) - 1, Int(H * 0.53), 2, 2, night ? 0xFFFFFF : 0xFFE9B0)
        case .skyvine:
            // A beanstalk up the wall: the stalk hugs the screen's edge, broad leaves reach out into the room (each
            // one a rung of the ladder), tendrils curl off it, a bud at the top.
            let stalkX = 4.0
            for y in 0..<h {
                let x = stalkX + sin(Double(y) / 9) * 1.4
                cv.rect(Int(x), y, 3, 1, 0x3F8A3A)
                cv.set(Int(x), y, 0x2D6A2C)
                if y % 17 == 8 { cv.line(x + 3, Double(y), x + 7, Double(y) + 3, 0x6CC04A); cv.set(Int(x) + 8, y + 2, 0x6CC04A) }   // tendrils
            }
            let leaves = max(1, Int((size.y - 36) / 64))
            for n in 0..<leaves {
                let y = (56 + Double(n) * 64) / artScale
                cv.blob(stalkX + 11, y - 1.6, 11.5, 3.0, base: 0x6CC04A, light: 0xA6E36E, shade: 0x3F8A3A)
                cv.line(stalkX + 1, y - 1, stalkX + 21, y - 2, 0x3F8A3A)   // the midrib
            }
            cv.blob(stalkX + 1, H - 4, 4.5, 3.6, base: 0xF7B2D3, light: 0xFFE0EF, shade: 0xC9709C)
            cv.outline()
        case .snapjaw:
            let open = variant == 0
            for y in 0..<Int(H * 0.5) { cv.rect(Int(cx) - 1, y, 3, 1, 0x3D7A3A) }
            cv.blob(cx - W * 0.22, H * 0.18, W * 0.22, H * 0.07, base: 0x5BAA47)
            cv.blob(cx + W * 0.22, H * 0.26, W * 0.22, H * 0.07, base: 0x5BAA47)
            let jy = H * 0.68, gap = open ? H * 0.14 : 0
            cv.blob(cx, jy + gap, W * 0.42, H * 0.16, base: 0x7DBE3A, light: 0xB6E25C, shade: 0x4C8A2A)
            cv.blob(cx, jy - gap, W * 0.42, H * 0.16, base: 0x7DBE3A, light: 0xB6E25C, shade: 0x4C8A2A)
            if open { cv.blob(cx, jy, W * 0.34, gap * 0.9, base: 0xC23B4A, shade: 0x8A2233) }
            cv.outline()
            // Teeth
            let n = 3 + p.level
            for i in 0..<n {
                let x = Int(cx - W * 0.3 + W * 0.6 * Double(i) / Double(max(1, n - 1)))
                cv.set(x, Int(jy + gap - H * 0.06), 0xFFFFF0)
                cv.set(x, Int(jy - gap + H * 0.06), 0xFFFFF0)
            }
        case .wishwillow:
            // Trunk, two branches (the ledges), drooping strands with glowing star-fruit.
            let trunkW = W * 0.12
            cv.rect(Int(cx - trunkW / 2), 0, Int(trunkW), Int(H * 0.8), 0x7A5232)
            cv.rect(Int(cx - trunkW / 2), 0, max(1, Int(trunkW * 0.35)), Int(H * 0.8), 0x5A3A22)
            cv.line(cx, H * 0.5, cx - W * 0.44, H * 0.55, 0x7A5232, width: 2)
            cv.line(cx, H * 0.72, cx + W * 0.42, H * 0.78, 0x7A5232, width: 2)
            cv.blob(cx, H * 0.84, W * 0.48, H * 0.17, base: 0x4FA98C, light: 0x8ED9BC, shade: 0x2F7A66)
            var sr = ArtRNG(s: 31)
            for _ in 0..<(6 + p.level * 3) {
                let x = sr.range(W * 0.06, W * 0.94)
                let top = H * sr.range(0.72, 0.9), len = H * sr.range(0.18, 0.42)
                for y in Int(top - len)..<Int(top) { cv.set(Int(x + sin(Double(y) / 4)), y, 0x5DB89A) }
                if sr.next() < 0.35 { cv.blob(x, top - len, 1.4, 1.4, base: night ? 0xFFF3A0 : 0xF5E27A) }
            }
            cv.outline()
        }
        if p.golden { for i in cv.px.indices { if let c = cv.px[i] { cv.px[i] = goldify(c) } } }
        return cv.image
    }

    static func goldify(_ c: UInt32) -> UInt32 {
        let l = (Double(c >> 16 & 0xFF) * 0.3 + Double(c >> 8 & 0xFF) * 0.59 + Double(c & 0xFF) * 0.11) / 255
        return UInt32(min(255, 120 + l * 150)) << 16 | UInt32(min(255, 80 + l * 140)) << 8 | UInt32(20 + l * 60)
    }

    /// A soft round glow (lanternbloom at night, shards, bolts' impact).
    static func glow(_ color: NSColor, radius: CGFloat) -> CGImage {
        let size = Int(radius * 2)
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: radius, y: radius), startRadius: 0,
                               endCenter: CGPoint(x: radius, y: radius), endRadius: radius, options: [])
        return ctx.makeImage()!
    }
}


/// Small sprites shared by the sky and the games.
enum SkyArt {
    static let shard: CGImage = Effects.pixels([
        "..w..",
        ".wYw.",
        "wYYYw",
        ".wYw.",
        "..w..",
    ], ["w": 0xFFFFFF, "Y": 0xFFE45C])
    static let seedBall: CGImage = {
        var cv = PixelCanvas(5, 5); cv.blob(2.5, 2.5, 2.3, 2.3, base: 0xE2B45A, light: 0xFFE7A6, shade: 0x9C6E2A); return cv.image
    }()
}
