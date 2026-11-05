// Pixel canvas, colour ramps and shape rasterization for the Gremlets sprite generator.

import Foundation

let W = 32, H = 32
let GROUND = 32.0

// MARK: - Colour

struct RGB { var r, g, b: Double }

func rgb(_ hex: UInt32) -> RGB {
    RGB(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
}

func toHSV(_ c: RGB) -> (h: Double, s: Double, v: Double) {
    let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
    var h = 0.0
    if d > 0 {
        if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h *= 60; if h < 0 { h += 360 }
    }
    return (h, mx == 0 ? 0 : d / mx, mx)
}

func fromHSV(_ h0: Double, _ s0: Double, _ v0: Double) -> UInt32 {
    let h = (h0.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    let s = min(max(s0, 0), 1), v = min(max(v0, 0), 1)
    let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
    var (r, g, b) = (0.0, 0.0, 0.0)
    switch Int(h / 60) {
    case 0: (r, g, b) = (c, x, 0)
    case 1: (r, g, b) = (x, c, 0)
    case 2: (r, g, b) = (0, c, x)
    case 3: (r, g, b) = (0, x, c)
    case 4: (r, g, b) = (x, 0, c)
    default: (r, g, b) = (c, 0, x)
    }
    return UInt32((r + m) * 255) << 16 | UInt32((g + m) * 255) << 8 | UInt32((b + m) * 255)
}

/// Hue-shifted ramp: shadows drift toward purple/blue, highlights toward yellow, like hand-made pixel art.
struct Ramp {
    let outline, shade, base, light, spec: UInt32
    init(_ hex: UInt32) {
        let (h, s, v) = toHSV(rgb(hex))
        func toward(_ target: Double, _ amt: Double) -> Double {
            var d = target - h
            if d > 180 { d -= 360 }; if d < -180 { d += 360 }
            return h + d * amt
        }
        base = hex
        shade = fromHSV(toward(260, 0.12), s * 1.08 + 0.06, v * 0.80)
        light = fromHSV(toward(60, 0.10), s * 0.78, min(1, v * 1.12 + 0.05))
        spec = fromHSV(toward(60, 0.10), s * 0.35, min(1, v * 1.25 + 0.15))
        outline = fromHSV(toward(260, 0.22), min(1, s * 1.1 + 0.2), v * 0.32)
    }
}

// MARK: - Shapes

/// Ellipse, optionally rotated (radians).
struct Ell {
    var cx, cy, rx, ry: Double
    var rot: Double = 0
}

/// Points along a quadratic curve as a chain of ellipses with tapering radius (tails, necks, legs).
func curve(_ a: (Double, Double), _ c: (Double, Double), _ b: (Double, Double), r0: Double, r1: Double, steps: Int = 10) -> [Ell] {
    (0...steps).map { i in
        let t = Double(i) / Double(steps)
        let x = (1 - t) * (1 - t) * a.0 + 2 * (1 - t) * t * c.0 + t * t * b.0
        let y = (1 - t) * (1 - t) * a.1 + 2 * (1 - t) * t * c.1 + t * t * b.1
        let r = r0 + (r1 - r0) * t
        return Ell(cx: x, cy: y, rx: r, ry: r)
    }
}

func blobPixels(_ es: [Ell], clipMaxY: Double = .infinity, clipMinY: Double = -.infinity) -> (Set<Int>, [Int: (Double, Double)]) {
    var set = Set<Int>()
    var normals: [Int: (Double, Double)] = [:]
    for y in 0..<H { for x in 0..<W {
        let fx = Double(x) + 0.5, fy = Double(y) + 0.5
        if fy > clipMaxY || fy < clipMinY { continue }
        var best = Double.infinity
        var n = (0.0, 0.0)
        for e in es where e.rx > 0.2 && e.ry > 0.2 {
            let dx = fx - e.cx, dy = fy - e.cy
            let c = cos(e.rot), s = sin(e.rot)
            let lx = dx * c + dy * s, ly = -dx * s + dy * c
            let nx = lx / e.rx, ny = ly / e.ry
            let d = nx * nx + ny * ny
            if d <= 1 && d < best { best = d; n = (nx * c - ny * s, nx * s + ny * c) }
        }
        if best <= 1 { set.insert(y * W + x); normals[y * W + x] = n }
    }}
    return (set, normals)
}

/// Lambert-ish tone from an ellipse normal; light from the top-left, toward the viewer.
func sphereTone(_ n: (Double, Double), glossy: Bool) -> Int {
    let nz = max(0, 1 - n.0 * n.0 - n.1 * n.1).squareRoot()
    let i = -0.50 * n.0 - 0.62 * n.1 + 0.60 * nz
    if glossy && i > 0.93 { return 3 }
    if i > 0.70 { return 2 }
    if i > 0.12 { return 1 }
    return 0
}

func pointInPoly(_ x: Double, _ y: Double, _ pts: [(Double, Double)]) -> Bool {
    var inside = false
    var j = pts.count - 1
    for i in 0..<pts.count {
        let (xi, yi) = pts[i], (xj, yj) = pts[j]
        if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
        j = i
    }
    return inside
}

// MARK: - Canvas

struct Canvas {
    var px = [UInt32?](repeating: nil, count: W * H)

    func get(_ x: Int, _ y: Int) -> UInt32? { (x >= 0 && x < W && y >= 0 && y < H) ? px[y * W + x] : nil }
    mutating func plot(_ x: Int, _ y: Int, _ c: UInt32) { if x >= 0 && x < W && y >= 0 && y < H { px[y * W + x] = c } }
    mutating func plot(_ x: Double, _ y: Double, _ c: UInt32) { plot(Int(x.rounded(.down)), Int(y.rounded(.down)), c) }

    /// Fills pixels with tones (0 shade, 1 base, 2 light, 3 spec) and a 1px selective outline around the set.
    mutating func fill(_ pixels: Set<Int>, ramp: Ramp, outline: Bool = true, tone: (Int, Int) -> Int) {
        if outline {
            for p in pixels {
                let x = p % W, y = p / W
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < W, ny >= 0, ny < H else { continue }
                    let n = ny * W + nx
                    if !pixels.contains(n) { px[n] = ramp.outline }
                }
            }
        }
        for p in pixels {
            let t = tone(p % W, p / W)
            px[p] = [ramp.shade, ramp.base, ramp.light, ramp.spec][max(0, min(3, t))]
        }
    }

    mutating func blob(_ es: [Ell], _ ramp: Ramp, outline: Bool = true, glossy: Bool = false,
                       clipMaxY: Double = .infinity, clipMinY: Double = -.infinity, flat: Bool = false) {
        let (set, normals) = blobPixels(es, clipMaxY: clipMaxY, clipMinY: clipMinY)
        fill(set, ramp: ramp, outline: outline) { x, y in
            flat ? 1 : sphereTone(normals[y * W + x] ?? (0, 0), glossy: glossy)
        }
    }

    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ ramp: Ramp,
                          outline: Bool = true, glossy: Bool = false, flat: Bool = false, rot: Double = 0) {
        blob([Ell(cx: cx, cy: cy, rx: rx, ry: ry, rot: rot)], ramp, outline: outline, glossy: glossy, flat: flat)
    }

    /// Polygon with rim lighting (light on top-left edges, shade on bottom-right edges).
    mutating func poly(_ pts: [(Double, Double)], _ ramp: Ramp, outline: Bool = true, flat: Bool = false) {
        var set = Set<Int>()
        for y in 0..<H { for x in 0..<W where pointInPoly(Double(x) + 0.5, Double(y) + 0.5, pts) { set.insert(y * W + x) } }
        fill(set, ramp: ramp, outline: outline) { x, y in
            if flat { return 1 }
            if !set.contains((y + 1) * W + x + 1) || !set.contains((y + 1) * W + x) { return 0 }
            if !set.contains((y - 1) * W + x - 1) { return 2 }
            return 1
        }
    }

    mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: UInt32) {
        let n = max(1, Int(max(abs(x1 - x0), abs(y1 - y0)).rounded(.up)))
        for i in 0...n {
            let t = Double(i) / Double(n)
            plot(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c)
        }
    }

    /// Stamps ASCII art; `.` is transparent. Anchor = top-left.
    mutating func stamp(_ rows: [String], _ x0: Int, _ y0: Int, _ palette: [Character: UInt32], flipX: Bool = false) {
        for (j, row) in rows.enumerated() {
            let chars = Array(row)
            for (i, ch) in chars.enumerated() {
                guard let c = palette[ch] else { continue }
                plot(x0 + (flipX ? chars.count - 1 - i : i), y0 + j, c)
            }
        }
    }

    /// Recolours only pixels inside `mask` that currently hold one of `from` colours.
    mutating func recolor(where test: (Int, Int, UInt32) -> UInt32?) {
        for y in 0..<H { for x in 0..<W {
            if let c = px[y * W + x], let n = test(x, y, c) { px[y * W + x] = n }
        }}
    }
}
