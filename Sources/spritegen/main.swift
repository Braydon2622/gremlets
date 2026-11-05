// spritegen: generates the built-in Gremlet sprite sheets.
//
// Creatures are assembled from parts (body blobs, ears, arms, feet, accessories) and rasterized onto a
// 32x32 pixel canvas. Every rounded part gets real spherical shading from a top-left light, with
// hue-shifted colour ramps and a selective outline, so bodies read as volumes instead of flat cylinders.
// Each species is a small data description; poses are shared, which keeps all 13 species consistently animated.
//
// Output per species (in Species/<id>/):
//   sheet.png     horizontal strip of 32x32 frames
//   sheet.json    Aseprite "array" export format with frameTags
//   species.json  name, element, scale and movement tuning
//   preview.png   upscaled contact sheet for docs (not loaded by the app)
//
// Usage: swift run spritegen [outputDir]   (default: ./Species)

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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

/// Hue-shifted ramp: shadows drift toward purple/blue, highlights toward yellow, as in hand-made pixel art.
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

// MARK: - Canvas

struct Canvas {
    var px = [UInt32?](repeating: nil, count: W * H)

    func get(_ x: Int, _ y: Int) -> UInt32? { (x >= 0 && x < W && y >= 0 && y < H) ? px[y * W + x] : nil }
    mutating func plot(_ x: Int, _ y: Int, _ c: UInt32) { if x >= 0 && x < W && y >= 0 && y < H { px[y * W + x] = c } }

    /// Fills a set of pixels with shading computed by `tone` (0 shade, 1 base, 2 light, 3 spec),
    /// then draws a 1px outline around the set (selective outline in the part's own darkest colour).
    mutating func fill(_ pixels: Set<Int>, ramp: Ramp, outline: Bool = true, tone: (Int, Int) -> Int) {
        if outline {
            var ring = Set<Int>()
            for p in pixels {
                let x = p % W, y = p / W
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < W, ny >= 0, ny < H else { continue }
                    let n = ny * W + nx
                    if !pixels.contains(n) { ring.insert(n) }
                }
            }
            for p in ring { px[p] = ramp.outline }
        }
        for p in pixels {
            let t = tone(p % W, p / W)
            px[p] = [ramp.shade, ramp.base, ramp.light, ramp.spec][max(0, min(3, t))]
        }
    }

    /// Stamps ASCII art. `palette` maps characters to colours; `.` is transparent. Anchor = top-left.
    mutating func stamp(_ rows: [String], _ x0: Int, _ y0: Int, _ palette: [Character: UInt32], flipX: Bool = false) {
        for (j, row) in rows.enumerated() {
            let chars = Array(row)
            for (i, ch) in chars.enumerated() {
                guard let c = palette[ch] else { continue }
                let xi = flipX ? (chars.count - 1 - i) : i
                plot(x0 + xi, y0 + j, c)
            }
        }
    }
}

// MARK: - Shapes

struct Ell { var cx, cy, rx, ry: Double }

/// A blob is a union of ellipses. Shading uses the normal of whichever ellipse a pixel sits deepest in,
/// which gives smooth, rounded volumes for compound shapes (pears, clouds, pots).
func blobPixels(_ es: [Ell], clipMaxY: Double = .infinity, clipMinY: Double = -.infinity) -> (Set<Int>, [Int: (Double, Double)]) {
    var set = Set<Int>()
    var normals: [Int: (Double, Double)] = [:]
    for y in 0..<H { for x in 0..<W {
        let fx = Double(x) + 0.5, fy = Double(y) + 0.5
        if fy > clipMaxY || fy < clipMinY { continue }
        var best = Double.infinity
        var n = (0.0, 0.0)
        for e in es where e.rx > 0.2 && e.ry > 0.2 {
            let nx = (fx - e.cx) / e.rx, ny = (fy - e.cy) / e.ry
            let d = nx * nx + ny * ny
            if d <= 1 && d < best { best = d; n = (nx, ny) }
        }
        if best <= 1 { set.insert(y * W + x); normals[y * W + x] = n }
    }}
    return (set, normals)
}

/// Lambert-ish tone from an ellipse normal with light from the top-left, toward the viewer.
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

extension Canvas {
    mutating func blob(_ es: [Ell], _ ramp: Ramp, outline: Bool = true, glossy: Bool = false,
                       clipMaxY: Double = .infinity, clipMinY: Double = -.infinity, flat: Bool = false) {
        let (set, normals) = blobPixels(es, clipMaxY: clipMaxY, clipMinY: clipMinY)
        fill(set, ramp: ramp, outline: outline) { x, y in
            flat ? 1 : sphereTone(normals[y * W + x] ?? (0, 0), glossy: glossy)
        }
    }

    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ ramp: Ramp,
                          outline: Bool = true, glossy: Bool = false, flat: Bool = false) {
        blob([Ell(cx: cx, cy: cy, rx: rx, ry: ry)], ramp, outline: outline, glossy: glossy, flat: flat)
    }

    /// Polygon with rim lighting (light on top-left edges, shade on bottom-right edges).
    mutating func poly(_ pts: [(Double, Double)], _ ramp: Ramp, outline: Bool = true) {
        var set = Set<Int>()
        for y in 0..<H { for x in 0..<W where pointInPoly(Double(x) + 0.5, Double(y) + 0.5, pts) { set.insert(y * W + x) } }
        fill(set, ramp: ramp, outline: outline) { x, y in
            if !set.contains((y + 1) * W + x + 1) || !set.contains((y + 1) * W + x) { return 0 }
            if !set.contains((y - 1) * W + x - 1) { return 2 }
            return 1
        }
    }
}

// MARK: - Poses

enum Eyes { case open, blink, sleep, happy, wide, squint, dizzy, sleepy }
enum Mouth { case none, smile, cat, open, yell, yawn, grin, wobble }
enum Arm { case down, up, out, swing(Double), flail(Double), tucked, rub, wave(Double) }
enum Legs { case stand, step(Double), dangle(Double), tucked }
enum Brows { case none, worried, determined }

struct Pose {
    var sx = 1.0, sy = 1.0      // squash & stretch
    var lift = 0.0              // body raised off the ground
    var lean = 0.0              // whole-body x offset
    var tilt = 0.0              // head-top parts x offset
    var eyes: Eyes = .open
    var look = 0.0              // eye x shift
    var mouth: Mouth = .smile
    var arms: (Arm, Arm) = (.down, .down)
    var legs: Legs = .stand
    var brows: Brows = .none
    var ear = 0.0               // 1 = droop, -1 = swept back / perked
    var tail = 0.0              // -1...1 sway
    var acc = 0                 // accessory frame: 0/1 normal, 2 = excited, 3 = sleepy
    var sweat = false
    var bubble = 0.0            // snot bubble radius
    var tear = false
    var blush = 1
    var lying = false           // flattened sleeping pose
    var wing = 0.0              // 0 rest, 1 raised
}

struct Anim { let name: String; let frames: [(Pose, Int)] }

func P(_ f: (inout Pose) -> Void) -> Pose { var p = Pose(); f(&p); return p }

let anims: [Anim] = {
    var a: [Anim] = []
    a.append(Anim(name: "idle", frames: [
        (P { _ in }, 520),
        (P { $0.sx = 1.06; $0.sy = 0.94; $0.acc = 1; $0.tail = 0.5 }, 420),
        (P { $0.tail = 1 }, 520),
        (P { $0.eyes = .blink; $0.acc = 1; $0.tail = 0.5 }, 110),
    ]))
    a.append(Anim(name: "look", frames: [
        (P { $0.look = -1; $0.tilt = -1 }, 380),
        (P { $0.look = -1; $0.tilt = -1; $0.acc = 1; $0.mouth = .open }, 300),
        (P { $0.eyes = .blink }, 110),
        (P { $0.look = 1; $0.tilt = 1; $0.acc = 1 }, 380),
        (P { $0.look = 1; $0.tilt = 1; $0.mouth = .cat }, 300),
        (P { $0.acc = 1 }, 200),
    ]))
    a.append(Anim(name: "walk", frames: (0..<6).map { k -> (Pose, Int) in
        let s = sin(Double(k) * .pi / 3)
        return (P {
            $0.legs = .step(s); $0.arms = (.swing(s), .swing(-s)); $0.look = 1; $0.lean = 0.5
            $0.lift = abs(s) < 0.5 ? 1 : 0; $0.ear = 0.35 * abs(s); $0.tail = s; $0.acc = k % 2
            $0.sx = abs(s) < 0.5 ? 0.97 : 1.03; $0.sy = abs(s) < 0.5 ? 1.03 : 0.97
        }, 90)
    }))
    a.append(Anim(name: "crouch", frames: [
        (P { $0.sx = 1.2; $0.sy = 0.78; $0.eyes = .squint; $0.mouth = .cat; $0.brows = .determined; $0.ear = 0.4; $0.wing = 0.3 }, 120),
    ]))
    a.append(Anim(name: "jump", frames: [
        (P { $0.sx = 0.86; $0.sy = 1.16; $0.lift = 2; $0.arms = (.up, .up); $0.legs = .dangle(0); $0.look = 1; $0.mouth = .open; $0.ear = -1; $0.acc = 2; $0.wing = 1 }, 110),
        (P { $0.sx = 0.92; $0.sy = 1.1; $0.lift = 2; $0.arms = (.up, .up); $0.legs = .dangle(0.5); $0.look = 1; $0.mouth = .grin; $0.ear = -1; $0.acc = 2 }, 110),
    ]))
    a.append(Anim(name: "fall", frames: [
        (P { $0.sy = 1.06; $0.sx = 0.95; $0.lift = 2; $0.arms = (.flail(1), .flail(-1)); $0.legs = .dangle(1); $0.eyes = .wide; $0.mouth = .yell; $0.brows = .worried; $0.sweat = true; $0.ear = -1; $0.wing = 1; $0.acc = 2 }, 80),
        (P { $0.sy = 1.06; $0.sx = 0.95; $0.lift = 2; $0.arms = (.flail(-1), .flail(1)); $0.legs = .dangle(-1); $0.eyes = .wide; $0.mouth = .yell; $0.brows = .worried; $0.sweat = true; $0.ear = -0.6; $0.acc = 0 }, 80),
    ]))
    a.append(Anim(name: "land", frames: [
        (P { $0.sx = 1.3; $0.sy = 0.7; $0.eyes = .squint; $0.mouth = .open; $0.ear = 1; $0.arms = (.out, .out) }, 80),
        (P { $0.sx = 0.92; $0.sy = 1.08; $0.lift = 1; $0.ear = -0.5 }, 110),
    ]))
    a.append(Anim(name: "dizzy", frames: (0..<4).map { k -> (Pose, Int) in
        let s = [-1.0, 0, 1, 0][k]
        return (P { $0.eyes = .dizzy; $0.mouth = .wobble; $0.lean = s; $0.tilt = s; $0.arms = k % 2 == 0 ? (.out, .down) : (.down, .out); $0.ear = 1; $0.acc = 3 }, 150)
    }))
    a.append(Anim(name: "yawn", frames: [
        (P { $0.eyes = .sleepy }, 160),
        (P { $0.sy = 1.06; $0.arms = (.up, .up); $0.eyes = .squint; $0.mouth = .open }, 180),
        (P { $0.sy = 1.13; $0.sx = 0.9; $0.arms = (.up, .up); $0.eyes = .squint; $0.mouth = .yawn; $0.tear = true; $0.ear = -1 }, 220),
        (P { $0.sy = 1.15; $0.sx = 0.89; $0.arms = (.up, .up); $0.eyes = .squint; $0.mouth = .yawn; $0.tear = true; $0.ear = -1 }, 620),
        (P { $0.sy = 0.94; $0.sx = 1.06; $0.eyes = .sleepy; $0.mouth = .cat; $0.ear = 0.6; $0.acc = 3 }, 280),
        (P { $0.sy = 0.92; $0.sx = 1.08; $0.eyes = .blink; $0.ear = 0.8; $0.acc = 3 }, 320),
    ]))
    a.append(Anim(name: "sleep", frames: [0.0, 1.0, 2.0, 1.0].enumerated().map { k, b -> (Pose, Int) in
        (P { $0.lying = true; $0.eyes = .sleep; $0.mouth = .none; $0.bubble = b + 1; $0.arms = (.tucked, .tucked); $0.legs = .tucked
            $0.ear = 1; $0.acc = 3; $0.sy = k == 2 ? 0.96 : 1.0 }, 650)
    }))
    a.append(Anim(name: "wake", frames: [
        (P { $0.lift = 3; $0.sy = 1.15; $0.sx = 0.9; $0.eyes = .wide; $0.mouth = .open; $0.sweat = true; $0.arms = (.out, .out); $0.ear = -1; $0.acc = 2 }, 170),
        (P { $0.lift = 1; $0.sy = 1.04; $0.eyes = .wide; $0.mouth = .smile; $0.ear = -0.5 }, 260),
        (P { $0.arms = (.rub, .rub); $0.eyes = .squint; $0.mouth = .cat }, 380),
        (P { $0.eyes = .blink }, 140),
    ]))
    a.append(Anim(name: "react", frames: [
        (P { $0.sx = 1.2; $0.sy = 0.8; $0.eyes = .happy; $0.mouth = .cat; $0.blush = 2; $0.ear = 0.5 }, 80),
        (P { $0.sx = 0.86; $0.sy = 1.16; $0.lift = 3; $0.arms = (.up, .up); $0.eyes = .happy; $0.mouth = .grin; $0.blush = 2; $0.ear = -1; $0.acc = 2; $0.wing = 1 }, 100),
        (P { $0.sy = 1.08; $0.lift = 4; $0.arms = (.wave(1), .up); $0.eyes = .happy; $0.mouth = .grin; $0.blush = 2; $0.ear = -1; $0.acc = 2; $0.wing = 0.5 }, 130),
        (P { $0.lift = 2; $0.arms = (.wave(-1), .up); $0.eyes = .happy; $0.mouth = .grin; $0.blush = 2; $0.acc = 2; $0.wing = 1 }, 110),
        (P { $0.sx = 1.14; $0.sy = 0.88; $0.arms = (.out, .out); $0.eyes = .happy; $0.mouth = .cat; $0.blush = 2 }, 90),
        (P { $0.eyes = .happy; $0.mouth = .smile; $0.blush = 2; $0.acc = 1 }, 280),
    ]))
    a.append(Anim(name: "pet", frames: (0..<4).map { k -> (Pose, Int) in
        let s = [-1.0, 0, 1, 0][k]
        return (P { $0.eyes = .happy; $0.mouth = .cat; $0.blush = 2; $0.tilt = s; $0.lean = s * 0.5; $0.ear = 0.5; $0.tail = s
            $0.sx = k % 2 == 0 ? 1.05 : 1.0; $0.sy = k % 2 == 0 ? 0.95 : 1.0; $0.acc = k % 2 }, 220)
    }))
    a.append(Anim(name: "drag", frames: (0..<4).map { k -> (Pose, Int) in
        let s = [1.0, 0, -1, 0][k]
        return (P { $0.lift = 3; $0.sy = 1.12; $0.sx = 0.9; $0.arms = (.up, .up); $0.legs = .dangle(s); $0.eyes = .wide; $0.mouth = .open
            $0.brows = .worried; $0.sweat = k < 2; $0.ear = -0.5; $0.tail = s; $0.lean = s * 0.5; $0.wing = k % 2 == 0 ? 1 : 0.3 }, 110)
    }))
    a.append(Anim(name: "alert", frames: [
        (P { $0.lift = 3; $0.sy = 1.14; $0.sx = 0.9; $0.eyes = .wide; $0.mouth = .open; $0.ear = -1; $0.arms = (.out, .out); $0.acc = 2 }, 150),
        (P { $0.sx = 1.08; $0.sy = 0.92; $0.look = 1; $0.brows = .determined; $0.mouth = .cat }, 260),
    ]))
    return a
}()

// MARK: - Species description

enum BodyKind { case round, pear, pebble, drop, cloud, bulb, pot, wisp, egg }
enum EarKind { case none, pointy, long, round, antennae, coil, leafy }
enum TailKind { case none, puff, curl, fin }
enum Top {
    case flame, sprout, mossCap, acornCap, bellCap, nightcap, lid, bolt, bubbles, wick, petalMane, scarf, collar, filament, frostTips, waxDrips, freckles, crescent, spots, wings, snout, glassBase
}

struct Species {
    let id, name, element, blurb: String
    let body: BodyKind
    let rx, ry: Double
    let main: UInt32
    let belly: UInt32?
    let accent: UInt32
    let accent2: UInt32
    let eye: UInt32
    let cheek: UInt32
    let ears: EarKind
    let tail: TailKind
    let tops: [Top]
    var glossy = false
    var floats = false
    var hollowEyes = false
    var tuning: [String: Double] = [:]
}

// MARK: - Renderer

func render(_ sp: Species, _ p: Pose) -> Canvas {
    var cv = Canvas()
    let R = Ramp(sp.main), A = Ramp(sp.accent), A2 = Ramp(sp.accent2)
    let feetH = sp.floats ? 1.0 : 2.5
    let rx = sp.rx * p.sx * (p.lying ? 1.14 : 1)
    let ry = sp.ry * p.sy * (p.lying ? 0.8 : 1)
    let cx = 16 + p.lean
    let bottom = GROUND - feetH - p.lift - (p.lying ? -0.5 : 0)
    let cy = bottom - ry
    let topY = cy - ry                  // top of the head
    let hx = cx + p.tilt * 0.8          // head-top anchor x
    let has = { (t: Top) in sp.tops.contains(t) }
    let eyeDark = Ramp(sp.eye).outline

    // ---------- Back layer ----------
    if has(.petalMane) {
        let n = 11
        for i in 0..<n {
            let ang = Double(i) / Double(n) * 2 * .pi + (p.acc == 2 ? 0.15 : 0)
            let px = hx + cos(ang) * (rx + 0.6), py = cy - ry * 0.15 + sin(ang) * (ry * 0.95 + 0.4)
            if py > cy + ry * 0.55 { continue }
            cv.ellipse(px, py, 2.4, 2.4, A)
        }
    }
    if has(.wings) {
        // Moth wings spread sideways behind the body: a big forewing and a small hindwing per side.
        let up = p.wing * 2.0
        for side in [-1.0, 1.0] {
            let fx = cx + side * (rx + 2.2), fy = cy - ry * 0.25 - up
            cv.blob([Ell(cx: fx, cy: fy, rx: 4.6, ry: 3.0), Ell(cx: fx + side * 1.6, cy: fy - 1.2 - up * 0.3, rx: 3.0, ry: 2.4)], A)
            cv.blob([Ell(cx: cx + side * (rx + 1.2), cy: cy + ry * 0.45 - up * 0.4, rx: 2.8, ry: 2.2)], A)
            cv.ellipse(fx + side * 1.2, fy - 0.6, 1.3, 1.1, A2, outline: false, flat: true)
            cv.plot(Int(fx + side * 1.2), Int(fy - 0.6), Ramp(sp.accent2).outline)
        }
    }
    switch sp.tail {
    case .puff:
        let tx = cx - rx - 1.5, ty = cy + ry * 0.3 - p.tail
        cv.poly([(cx - rx * 0.6, cy + ry * 0.5), (tx, ty), (tx + 1, ty + 1)], Ramp(0x6E9E4A))
        cv.ellipse(tx - 0.5, ty - 2.5 - p.tail * 0.5, 2.1, 2.1, A2, glossy: true)
    case .curl:
        let tx = cx - rx - 0.5, ty = cy + ry * 0.35
        cv.blob([Ell(cx: tx, cy: ty, rx: 2.5, ry: 2), Ell(cx: tx - 1.5, cy: ty - 2.5 - p.tail, rx: 1.6, ry: 2)], R)
    case .fin:
        cv.poly([(cx - rx * 0.7, cy + ry * 0.2), (cx - rx - 3, cy - ry * 0.2 - p.tail), (cx - rx - 2.5, cy + ry * 0.7)], A)
    case .none: break
    }

    // Ears go behind the head.
    let earSpread = rx * 0.48
    switch sp.ears {
    case .long:
        for side in [-1.0, 1.0] {
            let droop = max(0, p.ear), back = max(0, -p.ear)
            let ex = hx + side * (earSpread + droop * 2.5) - back * 1.2
            let ey = topY - 3.6 + droop * 3 + back * 0.5
            let ery = 5.0 - droop * 1.2
            cv.ellipse(ex, ey, 2.0 + droop * 0.4, ery, R)
            cv.ellipse(ex + 0.2, ey + 0.8, 0.9, ery - 2, A, outline: false, flat: true)
            if has(.frostTips) { cv.ellipse(ex, ey - ery + 1.3, 1.6, 1.3, A2, outline: false, glossy: true) }
        }
    case .pointy:
        for side in [-1.0, 1.0] {
            let ex = hx + side * earSpread, droop = max(0, p.ear) * 2, back = max(0, -p.ear)
            cv.poly([(ex - 2.6, topY + 2.5), (ex + side * (1 + droop) - back * 1.5, topY - 4 + droop), (ex + 2.6, topY + 2.5)], R)
            cv.poly([(ex - 1.2, topY + 2), (ex + side * (0.8 + droop) - back * 1.5, topY - 1.8 + droop), (ex + 1.2, topY + 2)], A, outline: false)
        }
    case .round:
        for side in [-1.0, 1.0] {
            cv.ellipse(hx + side * (earSpread + 1), topY + 1.2 + max(0, p.ear), 2.2, 2.0, R)
            cv.ellipse(hx + side * (earSpread + 1), topY + 1.5 + max(0, p.ear), 1.0, 0.9, A, outline: false, flat: true)
        }
    case .antennae:
        for side in [-1.0, 1.0] {
            let bx = hx + side * 2, droop = max(0, p.ear) * 2.5, back = max(0, -p.ear)
            let tipX = bx + side * (3.5 + droop) - back, tipY = topY - 5 + droop * 1.5
            let steps = 6
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let x = bx + (tipX - bx) * t, y = topY + 1 + (tipY - topY - 1) * t - sin(t * .pi) * 1.2
                cv.plot(Int(x), Int(y), Ramp(sp.accent).outline)
                if i % 2 == 0 && i > 0 {
                    cv.plot(Int(x) + Int(side), Int(y) - 1, A.light)
                    cv.plot(Int(x) - Int(side), Int(y) - 1, A.base)
                }
            }
            cv.ellipse(tipX, tipY, 1.4, 1.4, A2, glossy: true)
        }
    case .coil:
        let bx = hx + 1, top = topY - 1
        for i in 0..<6 {
            let y = top - Double(i)
            let x = Int(bx + p.tilt * 0.3 * Double(i) / 6)
            cv.plot(x, Int(y), A2.outline)
            if i % 2 == 1 { cv.plot(x - 1, Int(y), A2.base); cv.plot(x + 1, Int(y), A2.base) }
        }
        cv.ellipse(bx + p.tilt * 0.3, top - 7, 1.6, 1.6, A2, glossy: true)
        if p.acc == 2 { // sparks
            cv.plot(Int(bx) - 3, Int(top) - 8, A2.spec); cv.plot(Int(bx) + 3, Int(top) - 9, A2.spec); cv.plot(Int(bx) + 2, Int(top) - 5, A2.light)
        }
    case .leafy:
        for side in [-1.0, 1.0] {
            let ex = hx + side * (earSpread + 0.5), droop = max(0, p.ear) * 2
            cv.blob([Ell(cx: ex + side * 1.6, cy: topY - 0.5 + droop, rx: 2.8, ry: 1.6)], A)
        }
    case .none: break
    }

    // Back arm for wave poses etc. is drawn later with the front arm, both on top of the body (front-facing chibi).

    // ---------- Feet ----------
    let footY = GROUND - 1.4
    let footRamp = Ramp(R.shade)
    func foot(_ x: Double, _ y: Double) { cv.ellipse(x, y, 2.3, 1.5, footRamp) }
    if !sp.floats {
        switch p.legs {
        case .stand:
            foot(cx - rx * 0.45, footY); foot(cx + rx * 0.45, footY)
        case .step(let s):
            foot(cx - rx * 0.45 - s * 1.6, footY - max(0, s) * 1.2)
            foot(cx + rx * 0.45 + s * 1.6, footY - max(0, -s) * 1.2)
        case .dangle(let k):
            let fy = bottom + 1.2
            foot(cx - rx * 0.4 - k * 0.6, fy + max(0, k) * 0.8)
            foot(cx + rx * 0.4 - k * 0.6, fy + max(0, -k) * 0.8)
        case .tucked:
            foot(cx - rx * 0.55, GROUND - 1.2); foot(cx + rx * 0.55, GROUND - 1.2)
        }
    }

    // ---------- Body ----------
    var bodyEll: [Ell]
    switch sp.body {
    case .round:
        bodyEll = [Ell(cx: cx, cy: cy, rx: rx, ry: ry)]
    case .egg:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.15, rx: rx, ry: ry * 0.85), Ell(cx: cx, cy: cy - ry * 0.25, rx: rx * 0.86, ry: ry * 0.75)]
    case .pear:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.25, rx: rx, ry: ry * 0.75), Ell(cx: cx, cy: cy - ry * 0.35, rx: rx * 0.74, ry: ry * 0.65)]
    case .pebble:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.12, rx: rx, ry: ry * 0.88), Ell(cx: cx - rx * 0.25, cy: cy - ry * 0.3, rx: rx * 0.7, ry: ry * 0.7), Ell(cx: cx + rx * 0.3, cy: cy - ry * 0.15, rx: rx * 0.7, ry: ry * 0.75)]
    case .drop:
        let curl = p.tilt * 0.8 + (p.acc == 2 ? -1 : 0)
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.2, rx: rx, ry: ry * 0.8), Ell(cx: cx + curl * 0.3, cy: cy - ry * 0.45, rx: rx * 0.55, ry: ry * 0.5),
                   Ell(cx: cx + 0.6 + curl * 0.7, cy: cy - ry * 0.95, rx: rx * 0.25, ry: ry * 0.35), Ell(cx: cx + 1.6 + curl, cy: cy - ry * 1.25, rx: 0.9, ry: 1.0)]
    case .cloud:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.1, rx: rx * 0.8, ry: ry * 0.9), Ell(cx: cx - rx * 0.55, cy: cy + ry * 0.3, rx: rx * 0.5, ry: ry * 0.6),
                   Ell(cx: cx + rx * 0.55, cy: cy + ry * 0.25, rx: rx * 0.5, ry: ry * 0.62), Ell(cx: cx - rx * 0.25, cy: cy - ry * 0.5, rx: rx * 0.48, ry: ry * 0.5),
                   Ell(cx: cx + rx * 0.3, cy: cy - ry * 0.38, rx: rx * 0.45, ry: ry * 0.48)]
    case .bulb:
        bodyEll = [Ell(cx: cx, cy: cy - ry * 0.12, rx: rx, ry: ry * 0.88), Ell(cx: cx, cy: cy + ry * 0.55, rx: rx * 0.58, ry: ry * 0.42)]
    case .pot:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.22, rx: rx, ry: ry * 0.78), Ell(cx: cx, cy: cy - ry * 0.55, rx: rx * 0.62, ry: ry * 0.42)]
    case .wisp:
        let sway = p.tail + p.lean * 0.5
        bodyEll = [Ell(cx: cx, cy: cy - ry * 0.05, rx: rx, ry: ry * 0.9), Ell(cx: cx - 1 - sway * 0.5, cy: cy + ry * 0.7, rx: rx * 0.6, ry: ry * 0.4),
                   Ell(cx: cx - 3 - sway, cy: cy + ry * 0.95, rx: rx * 0.32, ry: ry * 0.22)]
    }
    cv.blob(bodyEll, R, glossy: sp.glossy)

    // Belly patch.
    if let b = sp.belly {
        let by = sp.body == .bulb ? cy - ry * 0.15 : cy + ry * 0.3
        cv.ellipse(cx + p.look * 0.3, by, rx * 0.58, ry * 0.52, Ramp(b), outline: false, glossy: sp.glossy)
    }

    // Surface details on the body.
    if has(.spots) {
        for (u, v, r) in [(-0.55, 0.15, 1.3), (0.6, 0.35, 1.0), (0.2, 0.62, 0.9)] {
            cv.ellipse(cx + u * rx, cy + v * ry, r, r, A2, outline: false, flat: true)
        }
    }
    if has(.freckles) {
        for (u, v) in [(-0.62, -0.45), (0.55, -0.55), (0.72, 0.1), (-0.7, 0.3)] {
            cv.plot(Int(cx + u * rx), Int(cy + v * ry), A2.light)
        }
    }
    if has(.crescent) {
        let mx = cx + 0.5, my = cy + ry * 0.45
        cv.ellipse(mx, my, 2.4, 2.4, A2, outline: false, flat: true)
        cv.ellipse(mx + 1.2, my - 0.8, 2.2, 2.2, Ramp(sp.belly ?? sp.main), outline: false, flat: true)
    }
    if has(.waxDrips) {
        for (u, len) in [(-0.75, 2.5), (-0.3, 3.5), (0.15, 1.8), (0.6, 3.0)] {
            let x = Int(cx + u * rx)
            let y0 = Int(cy - ry * 0.55 + abs(u) * ry * 0.45)
            for dy in 0..<Int(len) { cv.plot(x, y0 + dy, A2.base); cv.plot(x + 1, y0 + dy, dy == Int(len) - 1 ? A2.shade : A2.light) }
            cv.plot(x, y0 + Int(len), A2.shade)
        }
    }
    if has(.filament) {
        let glow = p.acc == 3 ? A.shade : (p.acc == 2 ? A.spec : A.light)
        let fy = Int(cy - ry * 0.58)
        for i in 0..<5 { cv.plot(Int(cx) - 2 + i, fy + (i % 2 == 0 ? 0 : -1), glow) }
        cv.plot(Int(cx) - 3, fy + 1, A.shade); cv.plot(Int(cx) + 3, fy + 1, A.shade)
    }
    if has(.glassBase) {
        let by = cy + ry * 0.62
        cv.blob([Ell(cx: cx, cy: by + 1.5, rx: rx * 0.55, ry: 2.4)], A2)
        for k in 0..<2 { for x in Int(cx - rx * 0.45)...Int(cx + rx * 0.45) { cv.plot(x, Int(by + 1) + k * 2, A2.shade) } }
    }

    if has(.scarf) {
        let sy = cy + ry * 0.74
        let flutter = p.lift > 1.5 ? -2.0 : p.tail * 0.6
        cv.blob([Ell(cx: cx, cy: sy, rx: rx * 0.98, ry: 1.7)], A, clipMinY: sy - 2)
        cv.poly([(cx - rx * 0.55, sy), (cx - rx * 0.9 - 1, sy + 4.5 + flutter), (cx - rx * 0.35, sy + 4 + flutter * 0.5)], A)
        for x in Int(cx - rx)...Int(cx + rx) where x % 3 == 0 && cv.get(x, Int(sy)) == A.base { cv.plot(x, Int(sy), A2.base) }
    }
    // ---------- Face ----------
    let faceV = has(.bellCap) ? 0.42 : (sp.body == .pot ? -0.05 : -0.12)
    let eyeY = Int((cy + ry * faceV).rounded()) + (p.lying ? 1 : 0)
    let faceCX = cx + p.look * 0.9 + p.lean * 0.3
    let eyeGap = max(2.6, rx * 0.42)
    let lx = Int((faceCX - eyeGap).rounded()), rxp = Int((faceCX + eyeGap).rounded()) - 1
    let D = eyeDark, Wt: UInt32 = 0xFFFFFF, I = Ramp(sp.eye).light
    let pal: [Character: UInt32] = ["D": D, "W": Wt, "I": I, "R": 0xD9445A, "r": 0xFF8FA0, "B": Ramp(0x9AD8FF).base, "b": Ramp(0x9AD8FF).light, "o": Ramp(0x9AD8FF).outline]
    func eyes(_ rows: [String], mirror: Bool = false, dy: Int = 0) {
        let w = rows[0].count
        cv.stamp(rows, lx - w / 2, eyeY - 1 + dy, pal)
        cv.stamp(rows, rxp - (w - 1) / 2, eyeY - 1 + dy, pal, flipX: mirror)
    }
    if sp.hollowEyes {
        switch p.eyes {
        case .open, .wide: eyes(["DD", "DD", "DD"])
        case .blink, .sleepy: eyes(["..", "DD"], dy: 1)
        case .sleep: eyes(["D.D", ".D."], dy: 1)
        case .happy: eyes([".D.", "D.D"])
        case .squint: eyes(["D..", ".DD", "D.."], mirror: true)
        case .dizzy: eyes(["D.D", ".D.", "D.D"])
        }
    } else {
        switch p.eyes {
        case .open: eyes(["WD", "DD", "DI"])
        case .blink: eyes(["..", "DD"], dy: 1)
        case .sleepy: eyes(["DD", "DI"], dy: 1)
        case .sleep: eyes(["D.D", ".D."], dy: 1)
        case .happy: eyes([".D.", "D.D"])
        case .wide: eyes(["DDD", "DWD", "DDD"])
        case .squint: eyes(["D..", ".DD", "D.."], mirror: true)
        case .dizzy: eyes(["D.D", ".D.", "D.D"])
        }
    }
    switch p.brows {
    case .worried:
        cv.stamp(["D.", ".D"].reversed(), lx - 1, eyeY - 3, pal); cv.stamp(["D.", ".D"], rxp, eyeY - 3, pal)
    case .determined:
        cv.stamp(["D.", ".D"], lx - 1, eyeY - 3, pal); cv.stamp([".D", "D."], rxp, eyeY - 3, pal)
    case .none: break
    }
    // Cheeks.
    if p.blush > 0 && !sp.hollowEyes {
        let c = sp.cheek
        cv.plot(lx - 2, eyeY + 2, c); cv.plot(rxp + 2, eyeY + 2, c)
        if p.blush > 1 { cv.plot(lx - 1, eyeY + 2, c); cv.plot(rxp + 1, eyeY + 2, c); cv.plot(lx - 2, eyeY + 1, Ramp(c).light) }
    }
    // Snout (drawn before the mouth so the mouth sits under it).
    let mx = Int(faceCX.rounded())
    var mouthY = eyeY + 2
    if has(.snout) {
        cv.ellipse(faceCX + 0.5, Double(eyeY) + 2.2, 2.2, 1.5, A, glossy: true)
        mouthY = eyeY + 4
    }
    switch p.mouth {
    case .none: break
    case .smile: cv.stamp(["D..D", ".DD."], mx - 2, mouthY, pal)
    case .cat: cv.stamp(["D.D.D", ".D.D."], mx - 3, mouthY, pal)
    case .open: cv.stamp(["DDD", "DRD", ".D."], mx - 2, mouthY, pal)
    case .yell: cv.stamp([".DD.", "DRRD", "DrRD", ".DD."], mx - 2, mouthY, pal)
    case .yawn: cv.stamp([".DDD.", "DRRRD", "DRrRD", "DRRRD", ".DDD."], mx - 3, mouthY - 1, pal)
    case .grin: cv.stamp(["DDDDD", "DRRRD", ".DrD."], mx - 3, mouthY, pal)
    case .wobble: cv.stamp(["D.D..", ".D.D."], mx - 3, mouthY, pal)
    }

    // ---------- Head-top accessories ----------
    let flamePal: [Character: UInt32] = ["Y": 0xFFF6A8, "a": 0xFFC23D, "A": 0xFF6A2B, "O": 0xB8321F, "c": Ramp(sp.accent2).light]
    if has(.flame) || has(.wick) {
        let frames: [[String]] = [
            ["...A...", "..AA...", "..AaA..", ".AaYaA.", ".AaYaA.", "OAaYaAO"],
            ["....A..", "...AA..", "..AaA..", ".AaYaA.", ".AaYaA.", "OAaYaAO"],
            ["..A..A.", "..AA.A.", ".AaAAA.", ".AaYaA.", "AaYYYaA", "AaYYYaA", "OAaYaAO"],
            [".......", ".......", ".......", "...A...", "..AaA..", "OAaYaAO"],
        ]
        var f = frames[min(p.acc, 3)]
        if has(.wick) { // ghostly blue lantern flame
            f = f.map { String($0.map { ch -> Character in ch == "A" ? "b" : ch == "a" ? "B" : ch == "Y" ? "W" : ch == "O" ? "o" : ch }) }
        }
        let pal2 = flamePal.merging(["b": 0x7FB8FF, "B": 0xBFE4FF, "W": 0xF4FBFF, "o": 0x3B4F9E]) { $1 }
        cv.stamp(f, Int(hx.rounded()) - 3, Int(topY.rounded()) - f.count + 2, pal2)
    }
    if has(.sprout) {
        let frames: [[String]] = [
            ["LL.LL", "lLtLl", "..t..", "..t.."],
            [".LL.LL", ".lLtLl", "...t..", "..t..."],
            ["L.....L", "LL...LL", ".lLtLl.", "...t...", "...t..."],
            [".....", "lL...", ".lLt.", "...tL", "...tl"],
        ]
        let f = frames[min(p.acc, 3)]
        cv.stamp(f, Int(hx.rounded()) - f[0].count / 2, Int(topY.rounded()) - f.count + 1, ["L": A.light, "l": A.shade, "t": A.outline])
    }
    if has(.mossCap) {
        cv.blob(bodyEll, A, outline: false, clipMaxY: cy - ry * 0.4)
        for (u, len) in [(-0.6, 2), (-0.15, 1), (0.3, 2), (0.7, 1)] {
            let x = Int(cx + u * rx), y = Int(cy - ry * 0.4)
            for d in 0...len { cv.plot(x, y + d, d == len ? A.shade : A.base) }
        }
    }
    if has(.acornCap) {
        let capY = topY + ry * 0.55
        cv.blob([Ell(cx: hx, cy: capY - 1, rx: rx * 1.08, ry: ry * 0.62)], A, clipMaxY: capY + 0.5)
        for y in Int(capY - ry * 0.6)...Int(capY) { for x in Int(hx - rx)...Int(hx + rx) where (x + y) % 3 == 0 && cv.get(x, y) == A.base { cv.plot(x, y, A.shade) } }
        for x in Int(hx - rx * 1.05)...Int(hx + rx * 1.05) where cv.get(x, Int(capY)) != nil { cv.plot(x, Int(capY), A.outline) }
        cv.stamp([".t", "tt", "t."], Int(hx) + 1, Int(capY - ry * 0.62) - 3, ["t": A2.base])
    }
    if has(.bellCap) {
        let capY = cy - ry * 0.25
        let lift = p.acc == 2 ? 1.0 : 0
        cv.blob([Ell(cx: hx, cy: capY - lift, rx: rx * 1.35, ry: ry * 1.05)], A, glossy: true, clipMaxY: capY + 1 - lift)
        for (u, v, r) in [(-0.6, -0.4, 1.3), (0.15, -0.75, 1.1), (0.7, -0.3, 1.2), (-0.15, -0.15, 0.8)] {
            let glow = p.acc == 3 ? A2.base : A2.light
            cv.ellipse(hx + u * rx * 1.2, capY - lift + v * ry, r, r, Ramp(glow), outline: false, flat: true)
        }
    }
    if has(.nightcap) {
        let droop = p.lying ? 3.0 : (p.acc == 2 ? -2 : 0)
        let bx = hx, by = topY + 2
        let tip = (bx + rx * 0.9 + droop, by - 6 + droop * 1.5)
        cv.poly([(bx - rx * 0.75, by), (tip.0, tip.1), (bx + rx * 0.75, by)], A)
        for y in stride(from: Int(by) - 2, to: Int(tip.1), by: -3) {
            for x in 0..<W where cv.get(x, y) == A.base || cv.get(x, y) == A.light { cv.plot(x, y, A2.base) }
        }
        cv.blob([Ell(cx: bx, cy: by, rx: rx * 0.85, ry: 1.3)], Ramp(0xF2EEE6))
        cv.ellipse(tip.0, tip.1, 1.7, 1.7, Ramp(0xF2EEE6))
    }
    if has(.lid) {
        let ly = topY + 1.5
        cv.blob([Ell(cx: hx, cy: ly, rx: rx * 0.72, ry: 1.6)], A)
        cv.ellipse(hx, ly - 2.2, 1.3, 1.1, A2)
    }
    if has(.bolt) {
        let frames: [[String]] = [["..YY", ".YY.", "YYYY", ".YY.", "YY.."], ["...Y", "..YY", ".YY.", "YYYY", ".YY."], ["..YYY", ".YYY.", "YYYYY", ".YYY.", "YYY.."], ["..Y.", ".Y..", "YYY.", ".Y..", "Y..."]]
        cv.stamp(frames[min(p.acc, 3)], Int(hx.rounded()) - 1, Int(topY.rounded()) - 4, ["Y": p.acc == 3 ? A.shade : A.light])
    }
    if has(.bubbles) {
        let o = [(4, -3), (5, -6), (3, -8), (2, -4)][min(p.acc, 3)]
        let bx = Int(hx) + o.0, by = Int(topY) + o.1
        cv.stamp([".o.", "obo", ".o."], bx, by, pal)
        cv.plot(bx + 3, by - 3, Ramp(0x9AD8FF).light)
    }
    if has(.collar) {
        let n = 7
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let x = cx - rx * 0.75 + t * rx * 1.5, y = cy + ry * 0.5 + sin(t * .pi) * 1.0
            cv.ellipse(x, y, 1.5, 1.3, Ramp(0xFFF8EE), outline: false)
        }
    }

    // ---------- Arms (on top) ----------
    func arm(_ a: Arm, _ side: Double) {
        let ar = Ramp(sp.main)
        let baseX = cx + side * (rx * 0.92), baseY = max(cy + ry * 0.3, Double(eyeY) + 3.2)
        switch a {
        case .down: cv.ellipse(baseX, baseY, 1.2, 1.6, ar)
        case .tucked: break
        case .up: cv.ellipse(cx + side * (rx * 0.85), cy - ry * 0.6, 1.2, 1.8, ar)
        case .out: cv.ellipse(cx + side * (rx + 1.2), cy + ry * 0.1, 1.8, 1.2, ar)
        case .swing(let s): cv.ellipse(baseX + s * 0.8, baseY - abs(s) * 0.6, 1.2, 1.6, ar)
        case .flail(let s): cv.ellipse(cx + side * (rx + 1), cy - ry * 0.3 + s * 2.2, 1.3, 1.6, ar)
        case .wave(let s): cv.ellipse(cx + side * (rx * 0.9) + s, cy - ry * 0.75, 1.2, 1.8, ar)
        case .rub: cv.ellipse(side < 0 ? Double(lx) : Double(rxp) + 1, Double(eyeY) + 1.5, 1.6, 1.6, ar)
        }
    }
    arm(p.arms.0, -1); arm(p.arms.1, 1)

    // ---------- Emotes on the sprite ----------
    if p.sweat {
        cv.stamp([".o.", "obo", "oBo", ".o."], Int(cx + rx * 0.75), Int(topY) + 1, pal)
    }
    if p.tear {
        cv.plot(lx - 2, eyeY + 1, pal["b"]!); cv.plot(lx - 2, eyeY + 2, pal["B"]!)
        cv.plot(rxp + 2, eyeY + 1, pal["b"]!); cv.plot(rxp + 2, eyeY + 2, pal["B"]!)
    }
    if p.bubble > 0 {
        let bx = Double(mx) + 2.5, by = Double(mouthY) - p.bubble * 0.4
        let r = p.bubble
        var ring = Set<Int>()
        for y in 0..<H { for x in 0..<W {
            let d = ((Double(x) + 0.5 - bx) * (Double(x) + 0.5 - bx) + (Double(y) + 0.5 - by) * (Double(y) + 0.5 - by)).squareRoot()
            if d <= r + 0.5 && d > r - 0.6 { ring.insert(y * W + x) }
        }}
        for q in ring { cv.px[q] = Ramp(0xB5E6FF).base }
        cv.plot(Int(bx - r * 0.4), Int(by - r * 0.4), 0xFFFFFF)
    }
    return cv
}

// MARK: - The 13 species

let roster: [Species] = [
    // Originals, redesigned.
    Species(id: "kindlet", name: "Kindlet", element: "ember", blurb: "A melting-candle sprite whose flame flares when it's happy and dims to an ember when it naps.",
            body: .egg, rx: 8, ry: 7.5, main: 0xF27A4B, belly: 0xFFD6A5, accent: 0xFF6A2B, accent2: 0xFFE3BC, eye: 0x5A2416, cheek: 0xFF8FA0,
            ears: .none, tail: .none, tops: [.waxDrips, .flame], tuning: ["walkSpeed": 70, "jumpPower": 1.0, "sleepiness": 0.8]),
    Species(id: "mossling", name: "Mossling", element: "moss", blurb: "A sleepy river pebble that grew a moss blanket and one stubborn sprout.",
            body: .pebble, rx: 9.5, ry: 6.8, main: 0xA9B4AE, belly: nil, accent: 0x6BBF59, accent2: 0x3F8F46, eye: 0x24302A, cheek: 0xF0A3B4,
            ears: .none, tail: .none, tops: [.mossCap, .sprout], tuning: ["walkSpeed": 45, "jumpPower": 0.8, "sleepiness": 1.4]),
    Species(id: "dropple", name: "Dropple", element: "tide", blurb: "A springy raindrop with a curling tip. Best jumper of the bunch.",
            body: .drop, rx: 7.5, ry: 7.5, main: 0x6EC3FF, belly: 0xCDEEFF, accent: 0x3A86D6, accent2: 0xBDE8FF, eye: 0x13204A, cheek: 0xFF9ECB,
            ears: .none, tail: .fin, tops: [.bubbles], glossy: true, tuning: ["walkSpeed": 85, "jumpPower": 1.25, "sleepiness": 0.6]),
    // New species.
    Species(id: "nimbit", name: "Nimbit", element: "storm", blurb: "A pocket-sized thundercloud. Its little bolt crackles when it gets excited.",
            body: .cloud, rx: 9.5, ry: 7, main: 0xE8ECF7, belly: nil, accent: 0xFFD93B, accent2: 0x9AA6C8, eye: 0x2B3157, cheek: 0xB9C8FF,
            ears: .none, tail: .none, tops: [.bolt], tuning: ["walkSpeed": 60, "jumpPower": 1.1, "sleepiness": 1.0]),
    Species(id: "glimmoth", name: "Glimmoth", element: "glow", blurb: "A chubby night moth with a fluffy collar and lantern-tipped feelers.",
            body: .round, rx: 7, ry: 7, main: 0xC9A6E8, belly: 0xF3E6FF, accent: 0x9C7BD1, accent2: 0xFFE98A, eye: 0x2E1B4A, cheek: 0xFFB3D9,
            ears: .antennae, tail: .none, tops: [.wings, .collar], tuning: ["walkSpeed": 55, "jumpPower": 1.3, "sleepiness": 0.7]),
    Species(id: "acornet", name: "Acornet", element: "grove", blurb: "An acorn that refused to stay a seed. Wears its cap like a beloved hat.",
            body: .egg, rx: 7, ry: 7.5, main: 0xC98A4B, belly: 0xF0CFA0, accent: 0x7A5230, accent2: 0x5E8C3A, eye: 0x2F1C0E, cheek: 0xF59C8A,
            ears: .none, tail: .none, tops: [.acornCap], tuning: ["walkSpeed": 65, "jumpPower": 1.0, "sleepiness": 1.0]),
    Species(id: "flurrie", name: "Flurrie", element: "frost", blurb: "A snowball bunny with icicle ear-tips and a scarf it never takes off.",
            body: .round, rx: 8, ry: 7.6, main: 0xF4F8FF, belly: nil, accent: 0xE0565B, accent2: 0xA8DFFF, eye: 0x1F2B4D, cheek: 0xA9C9FF,
            ears: .long, tail: .none, tops: [.frostTips, .scarf], tuning: ["walkSpeed": 75, "jumpPower": 1.2, "sleepiness": 0.9]),
    Species(id: "fizzlet", name: "Fizzlet", element: "spark", blurb: "A tiny lightbulb spirit. Its filament glows brighter the happier it is.",
            body: .bulb, rx: 7, ry: 7.5, main: 0xE6FAFF, belly: nil, accent: 0xFFB43D, accent2: 0x9AA3AD, eye: 0x24303D, cheek: 0xFFC2A8,
            ears: .coil, tail: .none, tops: [.filament, .glassBase], glossy: true, tuning: ["walkSpeed": 80, "jumpPower": 1.15, "sleepiness": 0.5]),
    Species(id: "hushwisp", name: "Hushwisp", element: "spirit", blurb: "A quiet lantern ghost that drifts instead of walking and carries a cool blue flame.",
            body: .wisp, rx: 7.5, ry: 7.5, main: 0xE9E1FF, belly: 0xFFFFFF, accent: 0x7FB8FF, accent2: 0xC7B8F0, eye: 0x332A5C, cheek: 0xFFC2E2,
            ears: .none, tail: .none, tops: [.wick], floats: true, tuning: ["walkSpeed": 50, "jumpPower": 1.2, "sleepiness": 1.1]),
    Species(id: "bellcap", name: "Bellcap", element: "spore", blurb: "A shy mushroom with a bell-shaped cap whose spots glow in the dark.",
            body: .round, rx: 6.6, ry: 6.6, main: 0xF6E7CF, belly: nil, accent: 0x7E5BC9, accent2: 0xB6F2E0, eye: 0x2D1E3D, cheek: 0xF7A6C6,
            ears: .none, tail: .none, tops: [.bellCap], tuning: ["walkSpeed": 40, "jumpPower": 0.9, "sleepiness": 1.2]),
    Species(id: "kilnby", name: "Kilnby", element: "clay", blurb: "A little clay pot that came alive after a hundred years on a shelf. Hollow eyes, warm heart.",
            body: .pot, rx: 8, ry: 8, main: 0xD07A4E, belly: nil, accent: 0xB25E37, accent2: 0x8C4529, eye: 0x3A1A0E, cheek: 0xF4A07F,
            ears: .none, tail: .none, tops: [.lid], hollowEyes: true, tuning: ["walkSpeed": 40, "jumpPower": 0.75, "sleepiness": 1.1]),
    Species(id: "dandelet", name: "Dandelet", element: "bloom", blurb: "A dandelion cub with a petal mane. Its puff tail scatters seeds when it bounces.",
            body: .round, rx: 7, ry: 6.8, main: 0xF6D776, belly: 0xFFF3C4, accent: 0xFFB830, accent2: 0xFAFAF2, eye: 0x3D2A0E, cheek: 0xFF9C7A,
            ears: .none, tail: .puff, tops: [.petalMane], tuning: ["walkSpeed": 75, "jumpPower": 1.05, "sleepiness": 0.8]),
    Species(id: "snoozle", name: "Snoozle", element: "dusk", blurb: "A velvet mole in a nightcap. Has a moon on its tummy and naps whenever it can.",
            body: .pear, rx: 8, ry: 7.5, main: 0x5B5A8C, belly: 0x8F8DC0, accent: 0xFFB5C6, accent2: 0xFFE38A, eye: 0x1A1930, cheek: 0xFF9EB8,
            ears: .round, tail: .none, tops: [.snout, .crescent, .nightcap], tuning: ["walkSpeed": 40, "jumpPower": 0.85, "sleepiness": 2.0]),
]

// MARK: - Output

func writePNG(_ frames: [Canvas], to url: URL, scale k: Int = 1, background: UInt32? = nil, cellPad: Int = 0) throws {
    let cellW = W * k + cellPad, height = H * k
    let width = cellW * frames.count
    var buf = [UInt8](repeating: 0, count: width * height * 4)
    if let bg = background {
        let c = [UInt8(bg >> 16 & 0xFF), UInt8(bg >> 8 & 0xFF), UInt8(bg & 0xFF), 255]
        for i in stride(from: 0, to: buf.count, by: 4) { buf.replaceSubrange(i..<(i + 4), with: c) }
    }
    for (fi, f) in frames.enumerated() {
        for y in 0..<height { for x in 0..<(W * k) {
            guard let c = f.px[(y / k) * W + x / k] else { continue }
            let i = (y * width + fi * cellW + x) * 4
            buf[i] = UInt8(c >> 16 & 0xFF); buf[i + 1] = UInt8(c >> 8 & 0xFF); buf[i + 2] = UInt8(c & 0xFF); buf[i + 3] = 255
        }}
    }
    let provider = CGDataProvider(data: Data(buf) as CFData)!
    let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "spritegen", code: 1) }
}

func writeJSON(_ obj: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Species")
var lineup: [Canvas] = []

for sp in roster {
    let dir = outDir.appendingPathComponent(sp.id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var frames: [Canvas] = [], frameJSON: [[String: Any]] = [], tags: [[String: Any]] = []
    for a in anims {
        let from = frames.count
        for (pose, ms) in a.frames {
            frameJSON.append(["filename": "\(sp.id) \(frames.count).aseprite",
                              "frame": ["x": frames.count * W, "y": 0, "w": W, "h": H], "duration": ms])
            frames.append(render(sp, pose))
        }
        tags.append(["name": a.name, "from": from, "to": frames.count - 1, "direction": "forward"])
    }
    try writePNG(frames, to: dir.appendingPathComponent("sheet.png"))
    try writeJSON(["frames": frameJSON,
                   "meta": ["app": "gremlets-spritegen", "image": "sheet.png", "format": "RGBA8888",
                            "size": ["w": frames.count * W, "h": H], "scale": "1", "frameTags": tags]],
                  to: dir.appendingPathComponent("sheet.json"))
    var info: [String: Any] = ["name": sp.name, "element": sp.element, "description": sp.blurb, "scale": 3]
    for (k, v) in sp.tuning { info[k] = v }
    if sp.floats { info["floats"] = true }
    try writeJSON(info, to: dir.appendingPathComponent("species.json"))

    // Contact sheet of key poses: idle, walk, jump, fall, dizzy, yawn, sleep, react, pet, drag.
    let key = ["idle": 0, "walk": 1, "jump": 0, "fall": 0, "dizzy": 0, "yawn": 3, "sleep": 2, "react": 2, "pet": 0, "drag": 0]
    var keyFrames: [Canvas] = []
    for name in ["idle", "walk", "jump", "fall", "dizzy", "yawn", "sleep", "react", "pet", "drag"] {
        let tag = tags.first { ($0["name"] as! String) == name }!
        keyFrames.append(frames[(tag["from"] as! Int) + key[name]!])
    }
    try writePNG(keyFrames, to: dir.appendingPathComponent("preview.png"), scale: 5, background: 0xF3EFE6, cellPad: 6)
    lineup.append(frames[0])
    print("\(sp.name) (\(sp.element)): \(frames.count) frames")
}
try writePNG(lineup, to: outDir.appendingPathComponent("lineup.png"), scale: 6, background: 0xF3EFE6, cellPad: 6)

// Debug: SPRITEGEN_DEBUG="flurrie:0,fizzlet:5" writes big single frames to the output dir's parent /tmp-ish folder.
if let dbg = ProcessInfo.processInfo.environment["SPRITEGEN_DEBUG"], let dbgOut = ProcessInfo.processInfo.environment["SPRITEGEN_DEBUG_DIR"] {
    var cells: [Canvas] = []
    for item in dbg.split(separator: ",") {
        let parts = item.split(separator: ":")
        guard let sp = roster.first(where: { $0.id == parts[0] }) else { continue }
        let flat = anims.flatMap { $0.frames }
        let idx = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        cells.append(render(sp, flat[min(idx, flat.count - 1)].0))
    }
    try writePNG(cells, to: URL(fileURLWithPath: dbgOut).appendingPathComponent("debug.png"), scale: 12, background: 0xF3EFE6, cellPad: 12)
}
