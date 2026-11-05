// Species description + the core renderer that assembles a creature for one pose.

import Foundation

/// A drawing step that can read the computed body/head/face geometry.
typealias Draw = (inout Canvas, Ctx) -> Void

enum BodyKind { case round, egg, pear, pebble, cloud, coil, longneck, bugHead }
enum EyeStyle { case normal, light, bug(UInt32), spider, hollow, glow(UInt32) }
enum Feet { case nubs, big, hooves(UInt32), talons(UInt32), insect, webbed(UInt32), slime(UInt32), none }

struct Species {
    var id: String
    var name: String
    var element: String
    var family: String
    var blurb: String
    var body: BodyKind = .round
    var rx = 7.5, ry = 7.0
    var main: UInt32
    var accent: UInt32 = 0xFFFFFF
    var accent2: UInt32 = 0xFFFFFF
    var belly: UInt32? = nil
    var head: UInt32? = nil
    var limb: UInt32? = nil
    var eye: UInt32 = 0x2A1A14
    var cheek: UInt32 = 0xFF9EB0
    var eyeStyle: EyeStyle = .normal
    var restEyes: Eyes? = nil
    var feet: Feet = .nubs
    var fluffy = false
    var glossy = false
    var beak = false
    var fangs = false
    var teeth = false
    var faceV = -0.12
    var eyeGap = 0.42
    var mouthDY = 2
    var armsUp = false
    var noArms = false
    var back: [Draw] = []
    var surface: [Draw] = []
    var muzzle: Draw? = nil
    var top: [Draw] = []
    var front: [Draw] = []
    var flies = false
    var floats = false
    var special = "sparkle"
    var walkSpeed = 65.0
    var jumpPower = 1.0
    var sleepiness = 1.0
}

func species(_ id: String, _ name: String, _ element: String, _ family: String, main: UInt32, _ blurb: String,
             _ f: (inout Species) -> Void) -> Species {
    var s = Species(id: id, name: name, element: element, family: family, blurb: blurb, main: main)
    f(&s)
    return s
}

struct Ctx {
    let sp: Species
    let p: Pose
    let R: Ramp, A: Ramp, A2: Ramp, L: Ramp
    let cx: Double, cy: Double, rx: Double, ry: Double, bottom: Double
    var hcx: Double, hcy: Double, hrx: Double, hry: Double
    var bodyEll: [Ell] = []
    var eyeY = 0, lx = 0, rxp = 0, mx = 0, mouthY = 0
    var faceCX = 0.0
    var headTop: Double { hcy - hry }
    /// Head-top anchor x (follows head tilt).
    var hx: Double { hcx + p.tilt * 0.8 }
}

func render(_ sp: Species, _ pose: Pose) -> Canvas {
    var p = pose
    if case .open = p.eyes, let r = sp.restEyes { p.eyes = r }
    if sp.armsUp && !p.lying {
        func lift(_ a: Arm) -> Arm {
            switch a { case .down, .swing, .tucked: return .up; default: return a }
        }
        p.arms = (lift(p.arms.0), lift(p.arms.1))
    }
    var cv = Canvas()

    let hasFeet: Bool = { if case .none = sp.feet { return false }; if case .slime = sp.feet { return false }; return true }()
    let feetH: Double = sp.floats ? 3.5 : (hasFeet ? 2.5 : 0.8)
    let rx = sp.rx * p.sx * (p.lying ? 1.14 : 1)
    let ry = sp.ry * p.sy * (p.lying ? 0.8 : 1)
    let cx = 16 + p.lean
    let bottom = GROUND - feetH - p.lift + (p.lying ? 0.5 : 0)
    let cy = bottom - ry

    var bodyEll: [Ell]
    var head: Ell? = nil
    switch sp.body {
    case .round:
        bodyEll = [Ell(cx: cx, cy: cy, rx: rx, ry: ry)]
    case .egg:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.15, rx: rx, ry: ry * 0.85), Ell(cx: cx, cy: cy - ry * 0.25, rx: rx * 0.86, ry: ry * 0.75)]
    case .pear:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.25, rx: rx, ry: ry * 0.75), Ell(cx: cx, cy: cy - ry * 0.35, rx: rx * 0.74, ry: ry * 0.65)]
    case .pebble:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.12, rx: rx, ry: ry * 0.88), Ell(cx: cx - rx * 0.25, cy: cy - ry * 0.3, rx: rx * 0.7, ry: ry * 0.7),
                   Ell(cx: cx + rx * 0.3, cy: cy - ry * 0.15, rx: rx * 0.7, ry: ry * 0.75)]
    case .cloud:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.1, rx: rx * 0.8, ry: ry * 0.9), Ell(cx: cx - rx * 0.55, cy: cy + ry * 0.3, rx: rx * 0.5, ry: ry * 0.6),
                   Ell(cx: cx + rx * 0.55, cy: cy + ry * 0.25, rx: rx * 0.5, ry: ry * 0.62), Ell(cx: cx - rx * 0.25, cy: cy - ry * 0.5, rx: rx * 0.48, ry: ry * 0.5),
                   Ell(cx: cx + rx * 0.3, cy: cy - ry * 0.38, rx: rx * 0.45, ry: ry * 0.48)]
    case .coil:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.5, rx: rx, ry: ry * 0.5), Ell(cx: cx - 1.4, cy: cy - ry * 0.02, rx: rx * 0.78, ry: ry * 0.42)]
        head = Ell(cx: cx + 1 + p.tilt * 0.4, cy: cy - ry * 0.6, rx: rx * 0.66, ry: ry * 0.55)
    case .longneck:
        bodyEll = [Ell(cx: cx - rx * 0.15, cy: cy + ry * 0.4, rx: rx, ry: ry * 0.6)]
            + curve((cx + rx * 0.3, cy + ry * 0.15), (cx + rx * 0.62, cy - ry * 0.4), (cx + rx * 0.32 + p.tilt * 0.5, cy - ry * 0.9), r0: 2.8, r1: 2.0, steps: 6)
        head = Ell(cx: cx + rx * 0.34 + p.tilt * 0.6, cy: cy - ry * 1.02, rx: max(4.2, rx * 0.52), ry: max(3.4, ry * 0.46))
    case .bugHead:
        bodyEll = [Ell(cx: cx, cy: cy + ry * 0.18, rx: rx, ry: ry * 0.82)]
        head = Ell(cx: cx + p.tilt * 0.3, cy: cy - ry * 0.6, rx: rx * 0.66, ry: ry * 0.5)
    }

    var ctx = Ctx(sp: sp, p: p, R: Ramp(sp.main), A: Ramp(sp.accent), A2: Ramp(sp.accent2), L: Ramp(sp.limb ?? sp.main),
                  cx: cx, cy: cy, rx: rx, ry: ry, bottom: bottom,
                  hcx: head?.cx ?? cx, hcy: head?.cy ?? cy, hrx: head?.rx ?? rx, hry: head?.ry ?? ry)
    ctx.bodyEll = bodyEll

    // Face anchors (computed early so back/top parts can align with them).
    ctx.faceCX = ctx.hcx + p.look * 0.9 + p.lean * 0.3
    ctx.eyeY = Int((ctx.hcy + ctx.hry * sp.faceV).rounded()) + (p.lying ? 1 : 0)
    let gap = max(2.6, ctx.hrx * sp.eyeGap)
    ctx.lx = Int((ctx.faceCX - gap).rounded())
    ctx.rxp = Int((ctx.faceCX + gap).rounded()) - 1
    ctx.mx = Int(ctx.faceCX.rounded())
    ctx.mouthY = ctx.eyeY + sp.mouthDY

    // 1. Behind the body.
    for d in sp.back { d(&cv, ctx) }

    // 2. Feet.
    drawFeet(&cv, ctx)

    // 3. Body (+ fur) and separate head.
    cv.blob(bodyEll, ctx.R, glossy: sp.glossy)
    if sp.fluffy { fluff(&cv, bodyEll, ctx.R, cx: cx, cy: cy) }
    if let b = sp.belly {
        let by = head != nil ? cy + ry * 0.38 : cy + ry * 0.3
        let bx = sp.body == .longneck ? cx - rx * 0.1 : cx + p.look * 0.3
        let bry = sp.body == .longneck ? ry * 0.32 : ry * 0.52
        cv.ellipse(bx, by, rx * 0.58, bry, Ramp(b), outline: false, glossy: sp.glossy)
    }
    if let h = head {
        cv.blob([h], Ramp(sp.head ?? sp.main), glossy: sp.glossy)
        if sp.fluffy { fluff(&cv, [h], Ramp(sp.head ?? sp.main), cx: h.cx, cy: h.cy) }
    }

    // 4. Markings on the body.
    for d in sp.surface { d(&cv, ctx) }

    // 5. Face.
    sp.muzzle?(&cv, ctx)
    drawFace(&cv, ctx)

    // 6. Head-top accessories, 7. held items / overlays, 8. arms.
    for d in sp.top { d(&cv, ctx) }
    for d in sp.front { d(&cv, ctx) }
    if !sp.noArms { drawArms(&cv, ctx) }

    // 9. Emotes.
    let pal = facePalette(ctx)
    if p.sweat { cv.stamp([".o.", "obo", "oBo", ".o."], Int(ctx.hcx + ctx.hrx * 0.75), Int(ctx.headTop) + 1, pal) }
    if p.tear {
        for x in [ctx.lx - 2, ctx.rxp + 2] { cv.plot(x, ctx.eyeY + 1, pal["b"]!); cv.plot(x, ctx.eyeY + 2, pal["B"]!) }
    }
    if p.bubble > 0 {
        let bx = Double(ctx.mx) + 2.5, by = Double(ctx.mouthY) - p.bubble * 0.4, r = p.bubble
        for y in 0..<H { for x in 0..<W {
            let dx = Double(x) + 0.5 - bx, dy = Double(y) + 0.5 - by
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= r + 0.5 && d > r - 0.6 { cv.plot(x, y, Ramp(0xB5E6FF).base) }
        }}
        cv.plot(Int(bx - r * 0.4), Int(by - r * 0.4), 0xFFFFFF)
    }
    return cv
}

/// Fur tufts: pushes the outline outward at regular angles around the body so the silhouette looks fuzzy.
/// Uses angle (not x/y) so tufts stay put while the body squashes.
func fluff(_ cv: inout Canvas, _ es: [Ell], _ r: Ramp, cx: Double, cy: Double) {
    let (set, _) = blobPixels(es)
    var ring: [Int] = []
    for p in set {
        let x = p % W, y = p / W
        if [(-1, 0), (1, 0), (0, -1), (0, 1)].contains(where: { !set.contains((y + $0.1) * W + x + $0.0) }) { ring.append(p) }
    }
    for p in ring {
        let x = Double(p % W) + 0.5, y = Double(p / W) + 0.5
        let a = atan2(y - cy, x - cx)
        guard y < cy + 4, sin(a * 11) > 0.45 else { continue }
        let ox = cos(a), oy = sin(a)
        let nx = Int((x + ox * 1.3).rounded(.down)), ny = Int((y + oy * 1.3).rounded(.down))
        if cv.get(nx, ny) == nil || cv.get(nx, ny) == r.outline {
            cv.plot(p % W, p / W, sphereTone((ox * 0.9, oy * 0.9), glossy: false) >= 2 ? r.light : r.base)
            cv.plot(nx, ny, r.outline)
        }
    }
}

func facePalette(_ c: Ctx) -> [Character: UInt32] {
    var d = Ramp(c.sp.eye).outline
    if case .glow(let g) = c.sp.eyeStyle { d = Ramp(g).outline }
    return ["D": d, "W": 0xFFFFFF, "I": Ramp(c.sp.eye).light, "R": 0xD9445A, "r": 0xFF8FA0,
            "B": Ramp(0x9AD8FF).base, "b": Ramp(0x9AD8FF).light, "o": Ramp(0x9AD8FF).outline]
}

func drawFace(_ cv: inout Canvas, _ c: Ctx) {
    let p = c.p
    var pal = facePalette(c)
    let lx = c.lx, rxp = c.rxp, eyeY = c.eyeY
    func eyes(_ rows: [String], mirror: Bool = false, dy: Int = 0, palette: [Character: UInt32]? = nil) {
        let w = rows[0].count
        let pl = palette ?? pal
        cv.stamp(rows, lx - w / 2, eyeY - 1 + dy, pl)
        cv.stamp(rows, rxp - (w - 1) / 2, eyeY - 1 + dy, pl, flipX: mirror)
    }
    func common() -> Bool {
        switch p.eyes {
        case .blink: eyes(["..", "DD"], dy: 1); return true
        case .sleep: eyes(["D.D", ".D."], dy: 1); return true
        case .happy: eyes([".D.", "D.D"]); return true
        case .squint: eyes(["D..", ".DD", "D.."], mirror: true); return true
        case .dizzy: eyes(["D.D", ".D.", "D.D"]); return true
        default: return false
        }
    }
    switch c.sp.eyeStyle {
    case .normal, .spider:
        if !common() {
            switch p.eyes {
            case .open: eyes(["WD", "DD", "DI"])
            case .sleepy: eyes(["DD", "DI"], dy: 1)
            case .wide: eyes(["DDD", "DWD", "DDD"])
            default: break
            }
        }
        if case .spider = c.sp.eyeStyle, p.eyes != .sleep && p.eyes != .blink {
            cv.plot(lx - 2, eyeY - 2, pal["D"]!); cv.plot(rxp + 2, eyeY - 2, pal["D"]!)
            cv.plot(lx, eyeY - 3, pal["D"]!); cv.plot(rxp, eyeY - 3, pal["D"]!)
        }
    case .light:
        pal["D"] = 0xFFFFFF
        var dark = pal; dark["P"] = Ramp(c.sp.eye).outline
        if !common() {
            switch p.eyes {
            case .open: eyes(["DD", "DP", "DP"], palette: dark)
            case .sleepy: eyes(["DD", "DP"], dy: 1, palette: dark)
            case .wide: eyes(["DDD", "DPD", "DDD"], palette: dark)
            default: break
            }
        }
    case .bug(let col):
        let b = Ramp(col)
        let bugPal: [Character: UInt32] = ["o": b.outline, "c": b.base, "s": b.shade, "W": 0xFFFFFF, "l": b.light]
        let wide = max(3.5, c.hrx * 0.62)
        let bl = Int((c.faceCX - wide).rounded()) - 1, br = Int((c.faceCX + wide).rounded()) - 2
        switch p.eyes {
        case .open, .wide, .sleepy:
            let rows = p.eyes == .wide ? [".oo.", "oWWo", "oWWo", ".oo."] : [".oo.", "oWlo", "ocso", ".oo."]
            cv.stamp(rows, bl, eyeY - 2, bugPal); cv.stamp(rows, br, eyeY - 2, bugPal)
        default:
            pal["D"] = b.outline
            _ = common()
        }
    case .hollow:
        if !common() {
            switch p.eyes {
            case .open, .wide: eyes(["DD", "DD", "DD"])
            case .sleepy: eyes(["..", "DD"], dy: 1)
            default: break
            }
        }
    case .glow(let g):
        let gr = Ramp(g)
        pal["W"] = gr.spec; pal["I"] = gr.light
        var gp = pal; gp["G"] = gr.base
        if !common() {
            switch p.eyes {
            case .open: eyes(["WG", "GG", "GI"], palette: gp)
            case .sleepy: eyes(["GG", "GI"], dy: 1, palette: gp)
            case .wide: eyes(["DDD", "DWD", "DDD"])
            default: break
            }
        }
    }

    // Brows.
    switch p.brows {
    case .worried:
        cv.stamp([".D", "D."], lx - 1, eyeY - 3, pal); cv.stamp(["D.", ".D"], rxp, eyeY - 3, pal)
    case .determined:
        cv.stamp(["D.", ".D"], lx - 1, eyeY - 3, pal); cv.stamp([".D", "D."], rxp, eyeY - 3, pal)
    case .none: break
    }
    // Cheeks.
    if p.blush > 0, case .hollow = c.sp.eyeStyle {} else if p.blush > 0 {
        let ch = c.sp.cheek
        cv.plot(lx - 2, eyeY + 2, ch); cv.plot(rxp + 2, eyeY + 2, ch)
        if p.blush > 1 { cv.plot(lx - 1, eyeY + 2, ch); cv.plot(rxp + 1, eyeY + 2, ch) }
    }
    // Mouth.
    let mx = c.mx, my = c.mouthY
    var mp = facePalette(c)
    if case .light = c.sp.eyeStyle { mp["D"] = Ramp(c.sp.head ?? c.sp.main).outline }
    if c.sp.beak {
        switch p.mouth {
        case .open, .grin: cv.stamp(["DD"], mx - 1, my, mp)
        case .yell, .yawn: cv.stamp(["DDD", "DRD"], mx - 2, my, mp)
        default: break
        }
        return
    }
    switch p.mouth {
    case .none: break
    case .smile: cv.stamp(["D..D", ".DD."], mx - 2, my, mp)
    case .cat: cv.stamp(["D.D.D", ".D.D."], mx - 3, my, mp)
    case .open: cv.stamp(["DDD", "DRD", ".D."], mx - 2, my, mp)
    case .yell: cv.stamp([".DD.", "DRRD", "DrRD", ".DD."], mx - 2, my, mp)
    case .yawn: cv.stamp([".DDD.", "DRRRD", "DRrRD", "DRRRD", ".DDD."], mx - 3, my - 1, mp)
    case .grin: cv.stamp(["DDDDD", "DRRRD", ".DrD."], mx - 3, my, mp)
    case .wobble: cv.stamp(["D.D..", ".D.D."], mx - 3, my, mp)
    }
    if c.sp.fangs, [Mouth.smile, .cat, .grin].contains(p.mouth) {
        cv.plot(mx, my + 2, 0xFFFFFF)
        if case .grin = p.mouth { cv.plot(mx - 2, my + 1, 0xFFFFFF) }
    }
    if c.sp.teeth, [Mouth.smile, .cat].contains(p.mouth) {
        cv.plot(mx - 1, my + 2, 0xFFFFFF); cv.plot(mx, my + 2, 0xFFFFFF)
        cv.plot(mx - 1, my + 3, mp["D"]!); cv.plot(mx, my + 3, mp["D"]!)
    }
}

func drawFeet(_ cv: inout Canvas, _ c: Ctx) {
    let p = c.p, rx = c.rx, cx = c.cx
    let footY = GROUND - 1.4
    var rampF = Ramp(c.L.shade)
    var frx = 2.3, fry = 1.5
    switch c.sp.feet {
    case .none: return
    case .slime(let col):
        cv.ellipse(cx, GROUND - 1.2, rx * 1.05, 1.5, Ramp(col), glossy: true)
        return
    case .big: frx = 2.9; fry = 1.8
    case .hooves(let col): rampF = Ramp(col)
    case .webbed(let col): rampF = Ramp(col); frx = 2.8; fry = 1.3
    case .talons(let col): rampF = Ramp(col); frx = 2.0; fry = 1.2
    case .insect:
        let leg = c.L.outline
        cv.line(cx - rx * 0.85, c.cy + c.ry * 0.45, cx - rx - 2, GROUND - 1, leg)
        cv.line(cx + rx * 0.85, c.cy + c.ry * 0.45, cx + rx + 2, GROUND - 1, leg)
    case .nubs: break
    }
    if c.sp.floats { return }
    func foot(_ x: Double, _ y: Double) {
        cv.ellipse(x, y, frx, fry, rampF)
        if case .talons(let col) = c.sp.feet {
            let t = Ramp(col).outline
            cv.plot(x - 2, y + 1, t); cv.plot(x + 2, y + 1, t)
        }
        if case .big = c.sp.feet {
            cv.plot(x + 1, y + 1, 0xFFF6E8); cv.plot(x + 2.5, y + 0.5, 0xFFF6E8)
        }
    }
    switch p.legs {
    case .stand:
        foot(cx - rx * 0.45, footY); foot(cx + rx * 0.45, footY)
    case .step(let s):
        foot(cx - rx * 0.45 - s * 1.6, footY - max(0, s) * 1.2)
        foot(cx + rx * 0.45 + s * 1.6, footY - max(0, -s) * 1.2)
    case .dangle(let k):
        let fy = c.bottom + 1.2
        foot(cx - rx * 0.4 - k * 0.6, fy + max(0, k) * 0.8)
        foot(cx + rx * 0.4 - k * 0.6, fy + max(0, -k) * 0.8)
    case .tucked:
        foot(cx - rx * 0.55, GROUND - 1.2); foot(cx + rx * 0.55, GROUND - 1.2)
    }
}

func drawArms(_ cv: inout Canvas, _ c: Ctx) {
    let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry
    let ar = c.L
    let baseY = max(cy + ry * 0.3, Double(c.eyeY) + 3.2)
    func arm(_ a: Arm, _ side: Double) {
        let baseX = cx + side * (rx * 0.92)
        switch a {
        case .down: cv.ellipse(baseX, baseY, 1.2, 1.6, ar)
        case .tucked: break
        case .up: cv.ellipse(cx + side * (rx * 0.85), cy - ry * 0.6, 1.2, 1.8, ar)
        case .out: cv.ellipse(cx + side * (rx + 1.2), cy + ry * 0.1, 1.8, 1.2, ar)
        case .swing(let s): cv.ellipse(baseX + s * 0.8, baseY - abs(s) * 0.6, 1.2, 1.6, ar)
        case .flail(let s): cv.ellipse(cx + side * (rx + 1), cy - ry * 0.3 + s * 2.2, 1.3, 1.6, ar)
        case .wave(let s): cv.ellipse(cx + side * (rx * 0.9) + s, cy - ry * 0.75, 1.2, 1.8, ar)
        case .rub: cv.ellipse(side < 0 ? Double(c.lx) : Double(c.rxp) + 1, Double(c.eyeY) + 1.5, 1.6, 1.6, ar)
        }
    }
    arm(c.p.arms.0, -1); arm(c.p.arms.1, 1)
}
