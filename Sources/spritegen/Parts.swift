// Part library: each function returns a Draw step that adapts to the current pose
// (ears droop, wings flap, tails sway, accessories flare when excited).

import Foundation

let sides: [Double] = [-1, 1]

// MARK: - Ears

func longEars(_ inner: UInt32, tip: UInt32? = nil) -> Draw {
    return { cv, c in
        let spread = c.hrx * 0.48
        for side in sides {
            let droop = max(0, c.p.ear), back = max(0, -c.p.ear)
            let ex = c.hx + side * (spread + droop * 2.5) - back * 1.2
            let ey = c.headTop - 3.6 + droop * 3 + back * 0.5
            let ery = 5.0 - droop * 1.2
            cv.ellipse(ex, ey, 2.0 + droop * 0.4, ery, c.R)
            cv.ellipse(ex + 0.2, ey + 0.8, 0.9, ery - 2, Ramp(inner), outline: false, flat: true)
            if let t = tip { cv.ellipse(ex, ey - ery + 1.3, 1.6, 1.3, Ramp(t), outline: false, glossy: true) }
        }
    }
}

func catEars(_ inner: UInt32, size: Double = 1, color: UInt32? = nil, spread: Double = 0.5) -> Draw {
    return { cv, c in
        let r = Ramp(color ?? c.sp.head ?? c.sp.main)
        for side in sides {
            let ex = c.hx + side * c.hrx * spread, droop = max(0, c.p.ear) * 2, back = max(0, -c.p.ear)
            let top = c.headTop
            cv.poly([(ex - 2.6 * size, top + 2.5), (ex + side * (1 + droop) - back * 1.5, top - 4 * size + droop), (ex + 2.6 * size, top + 2.5)], r)
            cv.poly([(ex - 1.2 * size, top + 2), (ex + side * (0.8 + droop) - back * 1.5, top - 1.8 * size + droop), (ex + 1.2 * size, top + 2)], Ramp(inner), outline: false)
        }
    }
}

func roundEars(_ inner: UInt32, size: Double = 1, color: UInt32? = nil, spread: Double = 0.62) -> Draw {
    return { cv, c in
        let r = Ramp(color ?? c.sp.head ?? c.sp.main)
        for side in sides {
            let ex = c.hx + side * (c.hrx * spread + 0.6), ey = c.headTop + 1.4 + max(0, c.p.ear) - size * 0.4
            cv.ellipse(ex, ey, 2.2 * size, 2.0 * size, r)
            cv.ellipse(ex, ey + 0.3, 1.1 * size, 0.9 * size, Ramp(inner), outline: false, flat: true)
        }
    }
}

func fawnEars(_ inner: UInt32) -> Draw {
    return { cv, c in
        for side in sides {
            let droop = max(0, c.p.ear), perk = max(0, -c.p.ear)
            let ex = c.hx + side * (c.hrx * 0.85 + 1.2), ey = c.headTop + c.hry * 0.35 + droop * 1.5 - perk
            let rot = side * (-0.35 + droop * 0.5 - perk * 0.2)
            cv.ellipse(ex, ey, 3.2, 1.5, Ramp(c.sp.head ?? c.sp.main), rot: rot)
            cv.ellipse(ex + side * 0.3, ey, 1.9, 0.6, Ramp(inner), outline: false, flat: true, rot: rot)
        }
    }
}

func batEars(_ inner: UInt32) -> Draw { catEars(inner, size: 1.55, spread: 0.62) }

func tassels(_ c1: UInt32, _ c2: UInt32) -> Draw {
    return { cv, c in
        for (i, side) in sides.enumerated() {
            let x = c.hx + side * (c.hrx * 0.62 + 2.2), y = c.headTop + 1.5
            cv.line(x, y, x + side * 0.5, y + 3, Ramp(c1).outline)
            cv.ellipse(x + side * 0.6, y + 4, 1.2, 1.2, Ramp(i == 0 ? c1 : c2))
        }
    }
}

// MARK: - Horns, crests, frills

func hornNubs(_ col: UInt32, spread: Double = 0.35, height: Double = 3.4) -> Draw {
    return { cv, c in
        for side in sides {
            let x = c.hx + side * c.hrx * spread, top = c.headTop
            cv.poly([(x - 1.4, top + 1.8), (x + side * 0.7 - max(0, -c.p.ear) * 0.6, top - height), (x + 1.4, top + 1.8)], Ramp(col))
        }
    }
}

func curvedHorns(_ col: UInt32) -> Draw {
    return { cv, c in
        for side in sides {
            let bx = c.hx + side * c.hrx * 0.42, top = c.headTop
            cv.blob(curve((bx, top + 1.5), (bx + side * 1.5, top - 3), (bx + side * 4 - 1, top - 3.2), r0: 1.4, r1: 0.55, steps: 7), Ramp(col))
        }
    }
}

func antlers(_ col: UInt32, mushroom: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        for side in sides {
            let bx = c.hx + side * c.hrx * 0.35, top = c.headTop + 1
            let tip = (bx + side * 3.5, top - 4.5), mid = (bx + side * 1.6, top - 2.4)
            cv.line(bx, top, tip.0, tip.1, r.base)
            cv.line(bx + side, top, tip.0 + side * 0.5, tip.1 + 1, r.shade)
            cv.line(mid.0, mid.1, mid.0 - side * 0.8, mid.1 - 2.6, r.base)
            if let m = mushroom {
                cv.ellipse(tip.0, tip.1 - 0.6, 1.9, 1.2, Ramp(m), glossy: true)
                cv.plot(tip.0 - 0.6, tip.1 - 1.2, 0xFFFFFF)
                cv.ellipse(mid.0 - side * 0.8, mid.1 - 3, 1.3, 0.9, Ramp(m))
            }
        }
    }
}

func noseHorn(_ col: UInt32) -> Draw {
    return { cv, c in
        let x = Double(c.mx) + 0.5, y = Double(c.eyeY) + 1.2
        cv.poly([(x - 1.2, y + 1.5), (x + 0.8, y - 2.8), (x + 1.4, y + 1.5)], Ramp(col))
    }
}

func frill(_ col: UInt32, _ spot: UInt32) -> Draw {
    return { cv, c in
        let fy = c.headTop + c.hry * 0.6
        let flare = c.p.acc == 2 ? 1.0 : 0
        cv.blob([Ell(cx: c.hx, cy: fy, rx: c.hrx * 1.45 + flare, ry: c.hry * 1.0 + flare)], Ramp(col), clipMaxY: c.hcy + c.hry * 0.3)
        let n = 7
        for i in 0..<n {
            let a = Double.pi + Double(i) / Double(n - 1) * Double.pi
            let x = c.hx + cos(a) * (c.hrx * 1.2 + flare), y = fy + sin(a) * (c.hry * 0.8 + flare)
            cv.ellipse(x, y, 0.9, 0.9, Ramp(spot), outline: false, flat: true)
        }
    }
}

func domeHead(_ col: UInt32, _ knob: UInt32) -> Draw {
    return { cv, c in
        let top = c.headTop
        cv.blob([Ell(cx: c.hx, cy: top + 2.6, rx: c.hrx * 0.86, ry: 3.6)], Ramp(col), glossy: true, clipMaxY: top + 3.8)
        for i in 0..<5 {
            let a = Double.pi + Double(i) / 4 * Double.pi
            cv.ellipse(c.hx + cos(a) * c.hrx * 0.95, top + 3.2 + sin(a) * 1.2, 0.8, 0.8, Ramp(knob))
        }
    }
}

func crest(_ col: UInt32) -> Draw {
    return { cv, c in
        let top = c.headTop, sway = c.p.wing * 0.8
        cv.poly([(c.hx - 0.5, top + 2.5), (c.hx - c.hrx - 6, top - 1.5 - sway), (c.hx - c.hrx - 4.5, top + 0.5 - sway), (c.hx + 1.5, top + 1)], Ramp(col))
    }
}

func comb(_ col: UInt32) -> Draw {
    return { cv, c in
        let top = c.headTop, r = Ramp(col)
        let k = c.p.acc == 2 ? 0.3 : 0
        cv.blob([Ell(cx: c.hx - 1.7, cy: top + 0.3, rx: 1.4 + k, ry: 1.6 + k), Ell(cx: c.hx, cy: top - 0.8, rx: 1.5 + k, ry: 1.9 + k),
                 Ell(cx: c.hx + 1.7, cy: top + 0.1, rx: 1.3 + k, ry: 1.5 + k)], r)
        cv.ellipse(Double(c.mx) + 0.5, Double(c.eyeY) + 4.5, 1.0, 1.4, r)
    }
}

func crystals(_ col: UInt32) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        let glow = c.p.acc == 2 ? 1.0 : 0
        let spots: [(Double, Double, Double)] = [(-0.55, 0.5, 4), (0.05, -0.3, 5.5 + glow), (0.6, 0.4, 3.5), (-1.15, 2.6, 3), (-1.3, 5.5, 2.5)]
        for (u, dy, h) in spots {
            let x = c.hx + u * c.hrx, y = c.headTop + dy + 1.5
            cv.poly([(x - 1.6, y), (x - 0.2, y - h), (x + 1.6, y)], r, flat: true)
            cv.line(x - 0.2, y - h + 1, x - 0.2, y - 0.5, r.light)
            cv.plot(x - 0.8, y - h * 0.5, r.spec)
        }
    }
}

func plates(_ col: UInt32, leafy: Bool) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        let xs: [Double] = [-0.9, -0.45, 0.0, 0.45]
        let hs: [Double] = [3.5, 5.0, 5.5, 4.0]
        for (i, u) in xs.enumerated() {
            let x = c.cx + u * c.rx - 0.5
            let y = c.cy - c.ry * (0.75 - abs(u) * 0.35)
            let h = hs[i] + (c.p.acc == 2 ? 1 : 0)
            cv.poly([(x - 2, y + 1.5), (x - 0.4, y - h), (x + 1.8, y + 1.5)], r)
            if leafy { cv.line(x - 0.3, y - h + 1.5, x - 0.1, y + 0.5, r.shade) }
        }
    }
}

func backSpikes(_ col: UInt32) -> Draw {
    return { cv, c in
        for i in 0..<3 {
            let a = Double.pi * (1.05 + Double(i) * 0.14)
            let x = c.cx + cos(a) * c.rx * 0.98, y = c.cy + sin(a) * c.ry * 0.95
            cv.poly([(x - 0.8, y + 1.4), (x - 2.4, y - 1.6), (x + 1.2, y - 0.2)], Ramp(col))
        }
    }
}

// MARK: - Wings (drawn behind the body)

/// Wing angle helper: `w` from the pose, larger spread while flying.
func wingState(_ c: Ctx) -> (w: Double, k: Double) {
    (c.p.wing, c.p.flying ? 1.0 : 0.72)
}

func butterflyWings(_ c1: UInt32, _ c2: UInt32) -> Draw {
    return { cv, c in
        let (w, k) = wingState(c)
        for side in sides {
            let ux = c.cx + side * (c.rx * 0.55 + 4.2 * k), uy = c.cy - c.ry * 0.55 - 2.2 * w
            let lx = c.cx + side * (c.rx * 0.45 + 3 * k), ly = c.cy + c.ry * 0.3 - w
            cv.blob([Ell(cx: ux, cy: uy, rx: 5 * k + 0.6, ry: 4 * k + 0.4, rot: side * (-0.55 - 0.25 * w))], Ramp(c1))
            cv.blob([Ell(cx: lx, cy: ly, rx: 3.4 * k + 0.4, ry: 2.8 * k + 0.4, rot: side * 0.45)], Ramp(c1))
            cv.ellipse(ux + side * 0.6, uy - 0.3, 2.6 * k, 2.0 * k, Ramp(c2), outline: false, flat: true, rot: side * -0.55)
            cv.ellipse(lx + side * 0.3, ly, 1.6 * k, 1.2 * k, Ramp(c2), outline: false, flat: true)
            cv.plot(ux + side * 3 * k, uy - 2 * k, 0xFFFFFF)
            cv.line(c.cx + side * c.rx * 0.4, c.cy - c.ry * 0.3, ux + side * 2.5 * k, uy - 1.5, Ramp(c1).outline)
        }
    }
}

func mothWings(_ col: UInt32, _ eyespot: UInt32, tails: Bool) -> Draw {
    return { cv, c in
        let (w, k) = wingState(c)
        let r = Ramp(col)
        for side in sides {
            let fx = c.cx + side * (c.rx + 2.2 * k), fy = c.cy - c.ry * 0.3 - 2 * w
            cv.blob([Ell(cx: fx, cy: fy, rx: 4.6 * k + 0.4, ry: 3.0 * k + 0.3), Ell(cx: fx + side * 1.6, cy: fy - 1.2 - w * 0.6, rx: 3 * k, ry: 2.4 * k)], r)
            let hx = c.cx + side * (c.rx + 1.2), hy = c.cy + c.ry * 0.45 - w * 0.6
            cv.blob([Ell(cx: hx, cy: hy, rx: 2.8 * k + 0.2, ry: 2.2 * k + 0.2)], r)
            if tails {
                cv.blob(curve((hx + side * 0.5, hy + 1.5), (hx + side * 2.5, hy + 4), (hx + side * 1.5, hy + 6.5 - w), r0: 1.0, r1: 0.6, steps: 5), r)
            }
            cv.ellipse(fx + side * 1.2, fy - 0.6, 1.3, 1.1, Ramp(eyespot), outline: false, flat: true)
            cv.plot(fx + side * 1.2, fy - 0.6, Ramp(eyespot).outline)
        }
    }
}

func dragonflyWings(_ col: UInt32) -> Draw {
    return { cv, c in
        let (w, k) = wingState(c)
        let r = Ramp(col)
        for side in sides {
            for (i, dy) in [-1.2, 1.4].enumerated() {
                let x = c.cx + side * (c.rx * 0.4 + 5.2 * k), y = c.cy - c.ry * 0.55 + dy - w * (2.0 - Double(i) * 0.8)
                let rot = side * (-0.18 + Double(i) * 0.3 - w * 0.2)
                cv.ellipse(x, y, 6.2 * k + 0.3, 1.45, r, glossy: true, rot: rot)
                cv.plot(x + side * (5.2 * k) * cos(rot) * side, y + 5.2 * k * sin(rot) * side, r.outline)
            }
        }
    }
}

func beeWings(_ col: UInt32 = 0xEAF8FF) -> Draw {
    return { cv, c in
        let w = c.p.wing
        let flap = c.p.flying ? 1.3 : 1.0
        for side in sides {
            let x = c.cx + side * (c.rx * 0.62 + 1), y = c.cy - c.ry * 0.9 - w * 1.6
            cv.ellipse(x, y, 2.8 * flap, 1.9, Ramp(col), glossy: true, rot: side * (-0.6 - w * 0.3))
            cv.ellipse(x + side * 1.4, y + 1.8, 1.8 * flap, 1.3, Ramp(col), glossy: true, rot: side * -0.2)
        }
    }
}

func batWings(_ membrane: UInt32, _ bone: UInt32) -> Draw {
    return { cv, c in
        let (w, k) = wingState(c)
        let s = c.p.flying ? 1.0 : 0.55
        for side in sides {
            let sx = c.cx + side * c.rx * 0.75, sy = c.cy - c.ry * 0.35
            let tip = (sx + side * (8 * s + 1), sy - 4 * s - 3 * w * k)
            let pts: [(Double, Double)] = [
                (sx, sy), tip,
                (sx + side * (7 * s), sy + 3.5 * s - w * 1.5),
                (sx + side * (4.6 * s), sy + 2.2 * s - w),
                (sx + side * (3.2 * s), sy + 4.2 * s - w * 0.6),
                (sx + side * 1, sy + 3.5),
            ]
            cv.poly(pts, Ramp(membrane))
            cv.line(sx, sy, tip.0, tip.1, Ramp(bone).base)
        }
    }
}

func birdWings(_ col: UInt32, _ tipCol: UInt32) -> Draw {
    return { cv, c in
        let (w, k) = wingState(c)
        for side in sides {
            let x = c.cx + side * (c.rx * 0.88 + 1.5 * k), y = c.cy - c.ry * 0.05 - w * 2
            let rx = c.p.flying ? 3.2 : 2.4, ry = c.p.flying ? 4.6 : 3.4
            cv.ellipse(x, y, rx, ry, Ramp(col), rot: side * (0.55 + 0.7 * w))
            let t = Ramp(tipCol)
            let a = side * (0.55 + 0.7 * w)
            for j in 0..<2 {
                let d = ry - 0.8 - Double(j) * 1.2
                cv.plot(x - sin(a) * d + side * Double(j) * 0.6, y + cos(a) * d, t.base)
            }
        }
    }
}

/// Ladybug: the body is the shell; while flying the two shell halves lift and clear wings show.
func shellWings(_ shell: UInt32, _ wing: UInt32) -> Draw {
    return { cv, c in
        guard c.p.flying || c.p.wing > 0.6 else { return }
        let w = c.p.wing
        for side in sides {
            cv.ellipse(c.cx + side * (c.rx + 3), c.cy - c.ry * 0.2 - w * 1.5, 4.4, 2.2, Ramp(wing), glossy: true, rot: side * (-0.4 - w * 0.3))
            cv.ellipse(c.cx + side * (c.rx * 0.7), c.cy - c.ry * 0.5, 3.0, 4.6, Ramp(shell), glossy: true, rot: side * 0.6)
        }
    }
}

// MARK: - Tails and back extras

enum TailTip { case none, spade(UInt32), ember, club(UInt32), leaf(UInt32), spikes(UInt32), tuft(UInt32), fluke(UInt32) }

func lizardTail(_ col: UInt32? = nil, tip: TailTip = .none, thick: Double = 1, len: Double = 1) -> Draw {
    return { cv, c in
        let r = Ramp(col ?? c.sp.main)
        let sway = c.p.tail
        let a = (c.cx - c.rx * 0.55, c.cy + c.ry * 0.55)
        let ctl = (c.cx - c.rx - 4 * len, c.cy + c.ry * 0.85 + sway * 0.5)
        let b = (c.cx - c.rx - 6.5 * len, c.cy - c.ry * 0.1 + sway * 1.8)
        cv.blob(curve(a, ctl, b, r0: 2.6 * thick, r1: 0.9, steps: 9), r)
        switch tip {
        case .none: break
        case .spade(let t):
            cv.poly([(b.0 + 0.5, b.1 + 1), (b.0 - 2.5, b.1 - 1), (b.0 - 0.5, b.1 - 3.5), (b.0 + 1.5, b.1 - 1)], Ramp(t))
        case .ember:
            let pal: [Character: UInt32] = ["Y": 0xFFF6A8, "a": 0xFFC23D, "A": 0xFF6A2B]
            let f = c.p.acc == 2 ? [".A.", "AaA", "aYa", ".a."] : ["..A", ".Aa", "AYa", ".a."]
            cv.stamp(f, Int(b.0) - 1, Int(b.1) - 3, pal)
        case .club(let t):
            cv.ellipse(b.0 - 0.5, b.1 - 0.5, 2.6, 2.2, Ramp(t))
            cv.plot(b.0 - 2, b.1 - 2, Ramp(t).light)
        case .leaf(let t):
            cv.ellipse(b.0 - 1.5, b.1 - 1.5, 2.4, 1.3, Ramp(t), rot: -0.8)
        case .spikes(let t):
            for (dx, dy) in [(-0.5, -1.0), (1.5, -1.0)] {
                cv.poly([(b.0 + dx - 0.8, b.1 + dy + 1), (b.0 + dx - 0.4, b.1 + dy - 2.6), (b.0 + dx + 0.8, b.1 + dy + 1)], Ramp(t))
            }
        case .tuft(let t):
            cv.ellipse(b.0 - 0.5, b.1 - 0.8, 1.8, 1.8, Ramp(t))
        case .fluke(let t):
            cv.ellipse(b.0 - 1.2, b.1 - 1.8, 2.6, 1.2, Ramp(t), rot: -0.9)
            cv.ellipse(b.0 - 1.6, b.1 + 0.6, 2.6, 1.2, Ramp(t), rot: 0.5)
        }
    }
}

func thinTail(_ col: UInt32? = nil, tuft: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col ?? c.sp.main), sway = c.p.tail
        let a = (c.cx - c.rx * 0.7, c.cy + c.ry * 0.6)
        let b = (c.cx - c.rx - 4, c.cy - c.ry * 0.3 + sway * 1.5)
        cv.blob(curve(a, (c.cx - c.rx - 4.5, c.cy + c.ry * 0.9), b, r0: 1.0, r1: 0.8, steps: 8), r)
        if let t = tuft { cv.ellipse(b.0, b.1 - 0.5, 1.8, 2.0, Ramp(t)) }
    }
}

func bushyTail(_ col: UInt32? = nil, ring: UInt32? = nil, big: Double = 1, tip: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col ?? c.sp.main), sway = c.p.tail
        let es = curve((c.cx - c.rx * 0.6, c.cy + c.ry * 0.5), (c.cx - c.rx - 6 * big, c.cy + c.ry * 0.5),
                       (c.cx - c.rx - 3.5 * big, c.cy - c.ry * 0.75 + sway), r0: 2.6 * big, r1: 3.2 * big, steps: 8)
        cv.blob(es, r)
        if let tip = tip, let last = es.last {
            cv.blob([Ell(cx: last.cx, cy: last.cy, rx: last.rx * 0.95, ry: last.ry * 0.95)], Ramp(tip), outline: false)
        }
        if let ring = ring {
            let rr = Ramp(ring)
            for (i, e) in es.enumerated() where i % 3 == 1 {
                let (set, _) = blobPixels([Ell(cx: e.cx, cy: e.cy, rx: e.rx, ry: e.ry * 0.55)])
                for q in set {
                    switch cv.px[q] {
                    case r.base?: cv.px[q] = rr.base
                    case r.light?: cv.px[q] = rr.light
                    case r.shade?: cv.px[q] = rr.shade
                    default: break
                    }
                }
            }
        }
    }
}

func puffTail(_ col: UInt32 = 0xFFFFFF) -> Draw {
    return { cv, c in cv.ellipse(c.cx - c.rx - 0.3, c.cy + c.ry * 0.45 - c.p.tail * 0.5, 2.3, 2.1, Ramp(col)) }
}

func seedPuffTail(_ stem: UInt32, _ puff: UInt32) -> Draw {
    return { cv, c in
        let tx = c.cx - c.rx - 1.5, ty = c.cy + c.ry * 0.3 - c.p.tail
        cv.poly([(c.cx - c.rx * 0.6, c.cy + c.ry * 0.5), (tx, ty), (tx + 1, ty + 1)], Ramp(stem))
        cv.ellipse(tx - 0.5, ty - 2.5 - c.p.tail * 0.5, 2.1, 2.1, Ramp(puff), glossy: true)
    }
}

func curlTail(_ col: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col ?? c.sp.main)
        let tx = c.cx - c.rx - 0.5, ty = c.cy + c.ry * 0.35
        cv.blob([Ell(cx: tx, cy: ty, rx: 2.5, ry: 2), Ell(cx: tx - 1.5, cy: ty - 2.5 - c.p.tail, rx: 1.6, ry: 2)], r)
    }
}

func stinger(_ col: UInt32) -> Draw {
    return { cv, c in
        let x = c.cx - c.rx + 0.5, y = c.cy + c.ry * 0.55
        cv.poly([(x + 1.5, y - 1.5), (x - 3, y + 0.5 + c.p.tail * 0.5), (x + 1.5, y + 1.8)], Ramp(col))
    }
}

func lanternTail(_ glow: UInt32) -> Draw {
    return { cv, c in
        let dim = c.p.acc == 3
        let g = Ramp(dim ? Ramp(glow).shade : glow)
        cv.ellipse(c.cx - c.rx * 0.7, c.cy + c.ry * 0.55, 3.8, 3.1, g, glossy: !dim)
        if c.p.acc == 2 { cv.plot(c.cx - c.rx * 0.7 - 4, c.cy + c.ry * 0.3, g.spec); cv.plot(c.cx - c.rx * 0.7 - 2, c.cy + c.ry * 0.55 - 4, g.spec) }
    }
}

func segmentTail(_ col: UInt32, band: UInt32) -> Draw {
    return { cv, c in
        let es = curve((c.cx - c.rx * 0.55, c.cy + c.ry * 0.35), (c.cx - c.rx - 5, c.cy + c.ry * 0.25),
                       (c.cx - c.rx - 9.5, c.cy - c.ry * 0.2 + c.p.tail * 1.5), r0: 1.45, r1: 0.9, steps: 12)
        cv.blob(es, Ramp(col))
        for (i, e) in es.enumerated() where i % 3 == 2 { cv.plot(e.cx, e.cy, Ramp(band).base); cv.plot(e.cx, e.cy - 1, Ramp(band).shade) }
    }
}

func featherTail(_ c1: UInt32, _ c2: UInt32) -> Draw {
    return { cv, c in
        for (i, a) in [-0.5, -0.1, 0.3].enumerated() {
            let ang = a + c.p.tail * 0.15
            let x = c.cx - c.rx - 1.5 + cos(Double.pi + ang) * 2, y = c.cy + c.ry * 0.25 + sin(Double.pi + ang) * 2
            cv.ellipse(x, y, 3.4, 1.4, Ramp(i == 1 ? c2 : c1), rot: ang)
        }
    }
}

func caterpillarSegments(_ colors: [UInt32]) -> Draw {
    return { cv, c in
        for i in (0..<colors.count).reversed() {
            let k = Double(i + 1)
            let wave = sin(k * 1.3 + c.p.tail * 1.5) * 0.8
            let x = c.cx - c.rx * 0.55 - k * 4.4, y = c.cy + c.ry * 0.38 - wave
            let r = max(2.8, c.ry * 0.62 - k * 0.35)
            cv.ellipse(x, GROUND - 1.2, 1.2, 1.1, Ramp(Ramp(colors[i]).shade))
            cv.ellipse(x, y, r, r, Ramp(colors[i]))
            fluff(&cv, [Ell(cx: x, cy: y, rx: r, ry: r)], Ramp(colors[i]), cx: x, cy: y)
        }
    }
}

func kettleShell(_ col: UInt32, _ lid: UInt32) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        let sx = c.cx - c.rx * 0.45, sy = c.cy - c.ry * 0.35
        // spout
        cv.blob(curve((sx - 4.5, sy + 1.5), (sx - 8, sy + 1), (sx - 8.5, sy - 3), r0: 1.5, r1: 1.0, steps: 6), r)
        cv.blob([Ell(cx: sx, cy: sy, rx: 6.6, ry: 6.0)], r, glossy: true)
        cv.blob([Ell(cx: sx, cy: sy - 5.6, rx: 4.0, ry: 1.4)], Ramp(lid))
        cv.ellipse(sx, sy - 7.6, 1.2, 1.0, Ramp(lid))
        // handle
        for t in stride(from: 0.0, through: Double.pi, by: 0.25) {
            cv.plot(sx + 3.8 + cos(t + Double.pi / 2) * -3.2, sy - 4 - sin(t) * 3.0, r.outline)
        }
    }
}

func humps(_ col: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col ?? c.sp.main), water = GROUND - 2.5
        cv.blob([Ell(cx: c.cx - c.rx - 1, cy: water, rx: 3.0, ry: 3.2 + c.p.tail * 0.3)], r, clipMaxY: water)
        cv.blob([Ell(cx: c.cx - c.rx - 6.5, cy: water, rx: 2.3, ry: 2.5 - c.p.tail * 0.3)], r, clipMaxY: water)
    }
}

func fanDisplay(_ c1: UInt32, _ c2: UInt32, _ c3: UInt32) -> Draw {
    return { cv, c in
        let up = c.p.acc == 2
        let k = up ? 1.0 : 0.55
        let fy = c.cy - c.ry * 0.25
        for (i, col) in [c1, c2, c3].enumerated() {
            let s = 1.0 - Double(i) * 0.3
            cv.blob([Ell(cx: c.cx - 0.5, cy: fy, rx: (c.rx * 1.35 + 1) * k * s, ry: (c.ry * 1.2 + 1) * k * s)], Ramp(col), outline: i == 0, clipMaxY: fy + 0.5)
        }
    }
}

func hopLegs(_ col: UInt32) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        for side in sides {
            let hip = (c.cx + side * c.rx * 0.6, c.cy + c.ry * 0.3)
            let knee = (c.cx + side * (c.rx + 2.6), c.cy - c.ry * 0.55 - (c.p.legs.isDangle ? -2 : 0))
            let foot = (c.cx + side * (c.rx + 1.8), GROUND - 1.2 - c.p.lift)
            cv.blob(curve(hip, (hip.0 + side * 2, hip.1 - 2), knee, r0: 1.8, r1: 1.2, steps: 5), r)
            cv.line(knee.0, knee.1, foot.0, foot.1, r.outline)
            cv.line(knee.0 + side * 0.8, knee.1, foot.0 + side * 0.8, foot.1, r.base)
        }
    }
}

extension Legs { var isDangle: Bool { if case .dangle = self { return true }; return false } }

func spiderLegs(_ col: UInt32) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        for side in sides {
            for i in 0..<4 {
                let fi = Double(i)
                let hip = (c.cx + side * c.rx * 0.7, c.cy + c.ry * 0.1 + fi * 1.2)
                let knee = (c.cx + side * (c.rx + 3 + fi * 0.3), c.cy - c.ry * 0.5 + fi * 2.2 - c.p.lift * 0.3)
                let foot = (c.cx + side * (c.rx + 4.2 - fi * 0.4 + (c.p.acc == 2 ? 1 : 0)), GROUND - 0.8 - c.p.lift)
                cv.line(hip.0, hip.1, knee.0, knee.1, r.outline)
                cv.line(knee.0, knee.1, foot.0, foot.1, r.outline)
                cv.plot(knee.0, knee.1 - 1, r.light)
            }
        }
    }
}

func extraHeads(_ ear: UInt32) -> Draw {
    return { cv, c in
        let p = c.p
        for side in sides {
            let hx = c.cx + side * (c.rx + 0.8), hy = c.cy + c.ry * 0.05 + (p.lying ? 1.5 : 0) + (side < 0 ? p.tail : -p.tail) * 0.5
            let r = Ramp(c.sp.main)
            cv.ellipse(hx + side * 2.2, hy - 1 + max(0, p.ear) * 2, 1.4, 2.6, Ramp(ear), rot: side * 0.6)
            cv.ellipse(hx, hy, 3.6, 3.2, r)
            let d: UInt32 = 0xFFFFFF
            let ex = Int(hx.rounded()) - 2, ey = Int(hy.rounded()) - 1
            switch p.eyes {
            case .happy, .squint: cv.stamp([".d.", "d.d"], ex, ey, ["d": d]); cv.stamp([".d.", "d.d"], ex + 3, ey, ["d": d])
            case .sleep, .blink, .sleepy: cv.stamp(["dd"], ex, ey + 1, ["d": d]); cv.stamp(["dd"], ex + 3, ey + 1, ["d": d])
            default: cv.plot(ex + 1, ey, d); cv.plot(ex + 1, ey + 1, d); cv.plot(ex + 3, ey, d); cv.plot(ex + 3, ey + 1, d)
            }
            if p.mouth != .none && !p.lying { cv.plot(ex + 2, ey + 3, 0xFF8FA0) }
        }
    }
}

func spiderEyes() -> Draw { return { _, _ in } }

// MARK: - Body markings

func belly(_ col: UInt32) -> Draw { return { cv, c in cv.ellipse(c.cx, c.cy + c.ry * 0.3, c.rx * 0.58, c.ry * 0.52, Ramp(col), outline: false) } }

func bellyScales(_ col: UInt32) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        let bx = c.sp.body == .longneck ? c.cx - c.rx * 0.1 : c.cx
        let by = c.sp.body == .longneck ? c.cy + c.ry * 0.42 : c.cy + c.ry * 0.32
        let bry = c.sp.body == .longneck ? c.ry * 0.32 : c.ry * 0.55
        cv.ellipse(bx, by, c.rx * 0.55, bry, r, outline: false)
        var y = by - bry + 2
        while y < by + bry - 0.5 {
            for x in Int(bx - c.rx * 0.5)...Int(bx + c.rx * 0.5) where cv.get(x, Int(y)) == r.base || cv.get(x, Int(y)) == r.light { cv.plot(x, Int(y), r.shade) }
            y += 2
        }
    }
}

/// Recolours body pixels in horizontal bands, keeping the shading tone.
func stripes(_ col: UInt32, count: Int = 2, start: Double = -0.1, gap: Double = 0.42, thick: Double = 1.8) -> Draw {
    return { cv, c in
        let (set, _) = blobPixels(c.bodyEll)
        let s = Ramp(col)
        for k in 0..<count {
            let y0 = c.cy + c.ry * (start + Double(k) * gap)
            for q in set {
                let y = Double(q / W) + 0.5
                guard y >= y0 && y < y0 + thick else { continue }
                switch cv.px[q] {
                case c.R.base?: cv.px[q] = s.base
                case c.R.light?, c.R.spec?: cv.px[q] = s.light
                case c.R.shade?: cv.px[q] = s.shade
                default: break
                }
            }
        }
    }
}

func spots(_ col: UInt32, _ list: [(Double, Double, Double)]) -> Draw {
    return { cv, c in
        for (u, v, r) in list { cv.ellipse(c.cx + u * c.rx, c.cy + v * c.ry, r, r, Ramp(col), outline: false, flat: true) }
    }
}

func shellLine() -> Draw {
    return { cv, c in cv.line(c.cx, c.hcy + c.hry * 0.7, c.cx, c.cy + c.ry * 0.95, c.R.outline) }
}

func eyeMask(_ col: UInt32) -> Draw {
    return { cv, c in
        for x in [Double(c.lx) + 0.5, Double(c.rxp) + 0.5] {
            cv.ellipse(x, Double(c.eyeY) + 0.8, 2.5, 2.0, Ramp(col), outline: false, flat: true)
        }
    }
}

func facePatch(_ col: UInt32, w: Double = 0.72, h: Double = 0.55) -> Draw {
    return { cv, c in cv.ellipse(c.faceCX, Double(c.eyeY) + 1.2, c.hrx * w, c.hry * h, Ramp(col), outline: false) }
}

func browDots(_ col: UInt32) -> Draw {
    return { cv, c in
        cv.ellipse(Double(c.lx) + 0.5, Double(c.eyeY) - 2.5, 1.2, 0.8, Ramp(col), outline: false, flat: true)
        cv.ellipse(Double(c.rxp) + 0.5, Double(c.eyeY) - 2.5, 1.2, 0.8, Ramp(col), outline: false, flat: true)
    }
}

func cracks(_ glow: UInt32) -> Draw {
    return { cv, c in
        let g = Ramp(glow)
        let col = c.p.acc == 3 ? g.shade : (c.p.acc == 2 ? g.spec : g.base)
        let lines: [[(Double, Double)]] = [
            [(-0.7, -0.1), (-0.45, 0.15), (-0.55, 0.45)],
            [(0.55, -0.3), (0.7, 0.0), (0.5, 0.25), (0.62, 0.55)],
            [(-0.15, -0.65), (0.05, -0.45), (-0.05, -0.25)],
        ]
        for l in lines {
            for i in 0..<(l.count - 1) {
                cv.line(c.cx + l[i].0 * c.rx, c.cy + l[i].1 * c.ry, c.cx + l[i + 1].0 * c.rx, c.cy + l[i + 1].1 * c.ry, col)
            }
        }
    }
}

func scales(_ col: UInt32) -> Draw {
    return { cv, c in
        let (set, _) = blobPixels(c.bodyEll)
        let s = Ramp(col)
        for q in set {
            let x = q % W, y = q / W
            guard Double(y) < c.cy + c.ry * 0.25 else { continue }
            if (x + (y / 2) * 2) % 4 == 0 && y % 2 == 0 { cv.px[q] = s.shade; cv.plot(x, y - 1, s.light) }
        }
    }
}

func moss(_ col: UInt32, flower: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        cv.blob(c.bodyEll, r, outline: false, clipMaxY: c.cy - c.ry * 0.4)
        for (u, len) in [(-0.6, 2), (-0.15, 1), (0.3, 2), (0.7, 1)] {
            let x = Int(c.cx + u * c.rx), y = Int(c.cy - c.ry * 0.4)
            for d in 0...len { cv.plot(x, y + d, d == len ? r.shade : r.base) }
        }
        if let f = flower {
            for (u, v) in [(-0.5, -0.75), (0.35, -0.85), (0.75, -0.55)] {
                let x = c.cx + u * c.rx, y = c.cy + v * c.ry
                cv.plot(x, y, f); cv.plot(x - 1, y, Ramp(f).light); cv.plot(x + 1, y, Ramp(f).light); cv.plot(x, y - 1, Ramp(f).light)
            }
        }
    }
}

func waxDrips(_ col: UInt32) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        for (u, len) in [(-0.75, 2.5), (-0.3, 3.5), (0.15, 1.8), (0.6, 3.0)] {
            let x = Int(c.cx + u * c.rx)
            let y0 = Int(c.cy - c.ry * 0.55 + abs(u) * c.ry * 0.45)
            for dy in 0..<Int(len) { cv.plot(x, y0 + dy, r.base); cv.plot(x + 1, y0 + dy, dy == Int(len) - 1 ? r.shade : r.light) }
            cv.plot(x, y0 + Int(len), r.shade)
        }
    }
}

func twoTone(_ col: UInt32, below: Double = -0.05) -> Draw {
    return { cv, c in cv.blob(c.bodyEll, Ramp(col), outline: false, clipMaxY: c.cy + c.ry * below) }
}

func cheekPouches(_ col: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col ?? c.sp.main)
        let k = c.p.acc == 2 ? 0.4 : 0
        for side in sides {
            cv.ellipse(c.faceCX + side * (c.hrx * 0.78), Double(c.eyeY) + 2.6, 2.5 + k, 2.2 + k, r)
        }
    }
}

func petals(_ col: UInt32) -> Draw {
    return { cv, c in
        for side in sides {
            cv.ellipse(c.cx + side * (c.rx + 0.8), c.cy + c.ry * 0.5, 3.2, 1.8, Ramp(col), rot: side * 0.45)
            cv.ellipse(c.cx + side * (c.rx - 0.5), c.cy + c.ry * 0.85, 2.4, 1.4, Ramp(col), rot: side * 0.2)
        }
    }
}

func spikedCollar(_ band: UInt32, _ spike: UInt32) -> Draw {
    return { cv, c in
        let y = max(c.cy + c.ry * 0.45, Double(c.mouthY) + 3)
        cv.blob([Ell(cx: c.cx, cy: y, rx: c.rx * 0.85, ry: 1.5)], Ramp(band), clipMinY: y - 1.6)
        for u in [-0.5, 0.0, 0.5] { cv.poly([(c.cx + u * c.rx - 0.9, y + 1), (c.cx + u * c.rx, y + 3), (c.cx + u * c.rx + 0.9, y + 1)], Ramp(spike)) }
    }
}

func scarf(_ col: UInt32, _ stripe: UInt32) -> Draw {
    return { cv, c in
        let A = Ramp(col)
        let sy = c.cy + c.ry * 0.74
        let flutter = c.p.lift > 1.5 ? -2.0 : c.p.tail * 0.6
        cv.blob([Ell(cx: c.cx, cy: sy, rx: c.rx * 0.98, ry: 1.7)], A, clipMinY: sy - 2)
        cv.poly([(c.cx - c.rx * 0.55, sy), (c.cx - c.rx * 0.9 - 1, sy + 4.5 + flutter), (c.cx - c.rx * 0.35, sy + 4 + flutter * 0.5)], A)
        for x in Int(c.cx - c.rx)...Int(c.cx + c.rx) where x % 3 == 0 && cv.get(x, Int(sy)) == A.base { cv.plot(x, Int(sy), Ramp(stripe).base) }
    }
}

func nemesLappets(_ c1: UInt32, _ c2: UInt32) -> Draw {
    return { cv, c in
        for side in sides {
            let x = c.hx + side * (c.hrx * 0.78)
            cv.poly([(x - 2, c.headTop + 3), (x + 2, c.headTop + 3), (x + 2.2 + side, c.cy + c.ry * 0.5), (x - 2.2 + side, c.cy + c.ry * 0.5)], Ramp(c1))
            var y = c.headTop + 5
            while y < c.cy + c.ry * 0.5 { cv.line(x - 1.6 + side * 0.5, y, x + 1.6 + side * 0.5, y, Ramp(c2).base); y += 2 }
        }
    }
}

func nemesBand(_ c1: UInt32, _ c2: UInt32) -> Draw {
    return { cv, c in
        let top = c.headTop
        cv.blob([Ell(cx: c.hx, cy: top + 2.5, rx: c.hrx * 0.95, ry: 3.4)], Ramp(c1), clipMaxY: top + 3.6)
        for x in stride(from: Int(c.hx - c.hrx), through: Int(c.hx + c.hrx), by: 2) {
            for y in Int(top)...Int(top + 3) where cv.get(x, y) == Ramp(c1).base || cv.get(x, y) == Ramp(c1).light { cv.plot(x, y, Ramp(c2).base) }
        }
        cv.ellipse(c.hx, top + 0.8, 1.0, 1.2, Ramp(0xFFD54A))
    }
}

// MARK: - Muzzles

func snout(_ col: UInt32, nose: UInt32 = 0x3A2420, w: Double = 0.38) -> Draw {
    return { cv, c in
        let y = Double(c.eyeY) + 2.6
        cv.ellipse(c.faceCX + 0.4, y, max(2.3, c.hrx * w), 1.8, Ramp(col), outline: false)
        cv.plot(c.mx, c.eyeY + 1, nose); cv.plot(c.mx - 1, c.eyeY + 1, nose); cv.plot(c.mx, c.eyeY + 2, Ramp(nose).light)
    }
}

func bigSnout(_ col: UInt32) -> Draw {
    return { cv, c in
        let y = Double(c.eyeY) + 3.0
        cv.ellipse(c.faceCX + 0.8, y, max(3.0, c.hrx * 0.55), 2.3, Ramp(col))
        cv.plot(c.mx - 1, c.eyeY + 2, Ramp(col).outline); cv.plot(c.mx + 2, c.eyeY + 2, Ramp(col).outline)
    }
}

enum BeakKind { case short, long, puffin, hook, bill, needle }

func beak(_ col: UInt32, _ kind: BeakKind = .short) -> Draw {
    return { cv, c in
        let x = Double(c.mx) + 0.5, y = Double(c.eyeY) + 1.2
        let r = Ramp(col)
        switch kind {
        case .short: cv.poly([(x - 1.9, y), (x + 1.9, y), (x + 0.3, y + 2.9)], r)
        case .needle:
            cv.line(x, y + 1.2, x + 7, y + 2.6, r.base); cv.line(x, y + 2.0, x + 6, y + 3.2, r.shade)
            cv.plot(x - 0.6, y + 1.6, r.outline)
        case .bill: cv.blob([Ell(cx: x + 1.2, cy: y + 2.6, rx: 3.0, ry: 1.4)], r)
        case .hook: cv.poly([(x - 1.9, y), (x + 2.2, y), (x + 1.4, y + 2.8), (x + 0.2, y + 1.8)], r)
        case .long: cv.poly([(x - 1.6, y - 0.2), (x + 1.6, y - 0.2), (x + 6.5, y + 1.8), (x + 0.5, y + 2.6)], r)
        case .puffin:
            cv.poly([(x - 2.5, y - 0.4), (x + 2.5, y - 0.4), (x + 0.6, y + 4.6)], r)
            cv.line(x - 2, y + 0.4, x + 2, y + 0.4, 0x9AA3AD)
            cv.line(x - 1.2, y + 2, x + 1.4, y + 2, 0xFFD54A)
        }
    }
}

func koalaNose(_ col: UInt32 = 0x2E2A33) -> Draw {
    return { cv, c in cv.ellipse(Double(c.mx) + 0.5, Double(c.eyeY) + 2.2, 1.9, 2.3, Ramp(col), glossy: true) }
}

func capyMuzzle(_ col: UInt32) -> Draw {
    return { cv, c in
        cv.blob([Ell(cx: c.faceCX + 0.6, cy: Double(c.eyeY) + 3.0, rx: c.hrx * 0.6, ry: 2.6)], Ramp(col))
        cv.plot(c.mx - 1, c.eyeY + 2, Ramp(col).outline); cv.plot(c.mx + 2, c.eyeY + 2, Ramp(col).outline)
    }
}

func mandibles(_ col: UInt32) -> Draw {
    return { cv, c in
        let o = Ramp(col).outline, b = Ramp(col).base
        let y = c.mouthY + 1
        cv.stamp(["ob", ".o"], c.mx - 4, y, ["o": o, "b": b])
        cv.stamp(["bo", "o."], c.mx + 2, y, ["o": o, "b": b])
    }
}

// MARK: - Head-top accessories

func flame(blue: Bool = false) -> Draw {
    return { cv, c in
        let frames: [[String]] = [
            ["...A...", "..AA...", "..AaA..", ".AaYaA.", ".AaYaA.", "OAaYaAO"],
            ["....A..", "...AA..", "..AaA..", ".AaYaA.", ".AaYaA.", "OAaYaAO"],
            ["..A..A.", "..AA.A.", ".AaAAA.", ".AaYaA.", "AaYYYaA", "AaYYYaA", "OAaYaAO"],
            [".......", ".......", ".......", "...A...", "..AaA..", "OAaYaAO"],
        ]
        let f = frames[min(c.p.acc, 3)]
        let pal: [Character: UInt32] = blue
            ? ["Y": 0xF4FBFF, "a": 0xBFE4FF, "A": 0x7FB8FF, "O": 0x3B4F9E]
            : ["Y": 0xFFF6A8, "a": 0xFFC23D, "A": 0xFF6A2B, "O": 0xB8321F]
        cv.stamp(f, Int(c.hx.rounded()) - 3, Int(c.headTop.rounded()) - f.count + 2, pal)
    }
}

func petalMane(_ col: UInt32) -> Draw {
    return { cv, c in
        let n = 11
        for i in 0..<n {
            let ang = Double(i) / Double(n) * 2 * Double.pi + (c.p.acc == 2 ? 0.15 : 0)
            let px = c.hx + cos(ang) * (c.rx + 0.6), py = c.cy - c.ry * 0.15 + sin(ang) * (c.ry * 0.95 + 0.4)
            if py > c.cy + c.ry * 0.55 { continue }
            cv.ellipse(px, py, 2.4, 2.4, Ramp(col))
        }
    }
}

func furMane(_ col: UInt32) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        for i in 0..<9 {
            let ang = Double.pi * (0.9 + Double(i) / 8 * 1.2)
            cv.ellipse(c.hx + cos(ang) * (c.hrx + 0.3), c.hcy + sin(ang) * (c.hry + 0.3) + 1, 2.2, 2.2, r)
        }
    }
}

func leafHat(_ col: UInt32) -> Draw {
    return { cv, c in
        let x = c.hx + 1, y = c.headTop - 0.5
        let rot = -0.5 + (c.p.acc == 2 ? -0.3 : 0) + c.p.tilt * 0.1
        cv.ellipse(x, y, 3.8, 1.7, Ramp(col), rot: rot)
        cv.line(x - 3 * cos(rot), y - 3 * sin(rot), x + 3 * cos(rot), y + 3 * sin(rot), Ramp(col).shade)
    }
}

func fruit(_ col: UInt32, _ leaf: UInt32) -> Draw {
    return { cv, c in
        let x = c.hx + 0.5, y = c.headTop - 1.5 + (c.p.lift > 2 ? -1 : 0)
        cv.ellipse(x, y, 2.8, 2.5, Ramp(col), glossy: true)
        cv.ellipse(x + 1.8, y - 2.4, 1.6, 0.8, Ramp(leaf), rot: -0.5)
        cv.plot(x, y - 2.6, Ramp(leaf).outline)
    }
}

func crown(_ col: UInt32 = 0xFFC93C, gem: UInt32 = 0xE0465A) -> Draw {
    return { cv, c in
        let x = c.hx, y = c.headTop + 0.5
        let r = Ramp(col)
        cv.poly([(x - 3.2, y + 0.5), (x - 3.2, y - 3), (x - 1.6, y - 1.2), (x, y - 3.6), (x + 1.6, y - 1.2), (x + 3.2, y - 3), (x + 3.2, y + 0.5)], r)
        cv.plot(x, y - 0.6, Ramp(gem).light); cv.plot(x - 2, y - 0.4, Ramp(0x6FD6FF).base); cv.plot(x + 2, y - 0.4, Ramp(0x6FD6FF).base)
    }
}

func tuft(_ col: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col ?? c.sp.main)
        let y = c.headTop + 0.5
        cv.blob([Ell(cx: c.hx - 2, cy: y, rx: 2.2, ry: 2.0), Ell(cx: c.hx + 0.3, cy: y - 1.4, rx: 2.4, ry: 2.2), Ell(cx: c.hx + 2.4, cy: y, rx: 2.0, ry: 1.8)], r)
    }
}

func sunDisk(_ col: UInt32 = 0xFFC93C) -> Draw {
    return { cv, c in
        let x = c.cx, y = c.cy - c.ry - 3.5 - (c.p.acc == 2 ? 1 : 0)
        let r = Ramp(col)
        cv.ellipse(x, y, 3.2, 3.0, r, glossy: true)
        if c.p.acc == 2 || c.p.acc == 1 {
            for (dx, dy) in [(-5.0, 0.0), (5.0, 0.0), (0.0, -4.5), (-3.8, -3.2), (3.8, -3.2)] { cv.plot(x + dx, y + dy, r.spec) }
        }
    }
}

func sailorHat(_ col: UInt32 = 0xFFFFFF, _ band: UInt32 = 0x2F4A8C) -> Draw {
    return { cv, c in
        let x = c.hx + 1, y = c.headTop + 0.5
        cv.blob([Ell(cx: x, cy: y - 0.5, rx: 3.6, ry: 2.4)], Ramp(col), clipMaxY: y + 0.3)
        cv.blob([Ell(cx: x, cy: y + 0.2, rx: 4.0, ry: 1.0)], Ramp(band))
    }
}

func eyeStalks(_ col: UInt32) -> Draw {
    return { cv, c in
        for side in sides {
            let bx = c.hx + side * 2, top = c.headTop + 1
            let tip = (bx + side * 1.5 - max(0, -c.p.ear), top - 5 + max(0, c.p.ear) * 2.5)
            cv.line(bx, top, tip.0, tip.1, Ramp(c.sp.main).outline)
            cv.line(bx + 1, top, tip.0 + 1, tip.1, Ramp(c.sp.main).base)
            cv.ellipse(tip.0 + 0.5, tip.1 - 0.5, 1.3, 1.3, Ramp(col), glossy: true)
        }
    }
}

enum AntennaKind { case ball, feather, elbow, long }

func antennae(_ kind: AntennaKind, _ col: UInt32, tip: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        for side in sides {
            let bx = c.hx + side * 1.8, top = c.headTop + 1
            let droop = max(0, c.p.ear) * 2.5, back = max(0, -c.p.ear)
            switch kind {
            case .ball:
                let tipP = (bx + side * 2.5 - back, top - 4.5 + droop)
                cv.line(bx, top, tipP.0, tipP.1, r.outline)
                cv.ellipse(tipP.0, tipP.1 - 0.5, 1.2, 1.2, Ramp(tip ?? col), glossy: true)
            case .feather:
                let tipX = bx + side * (3.5 + droop) - back, tipY = top - 5.5 + droop * 1.5
                for i in 0...6 {
                    let t = Double(i) / 6
                    let x = bx + (tipX - bx) * t, y = top + (tipY - top) * t - sin(t * Double.pi) * 1.2
                    cv.plot(x, y, r.outline)
                    if i % 2 == 0 && i > 0 { cv.plot(x + side, y - 1, r.light); cv.plot(x - side, y - 1, r.base) }
                }
                if let t = tip { cv.ellipse(tipX, tipY, 1.3, 1.3, Ramp(t), glossy: true) }
            case .elbow:
                let knee = (bx + side * 0.5, top - 3.5 + droop * 0.5)
                cv.line(bx, top, knee.0, knee.1, r.outline)
                cv.line(knee.0, knee.1, knee.0 + side * 3 - back, knee.1 - 1.5 + droop, r.outline)
            case .long:
                let mid = (bx + side * 1.5, top - 5)
                let end = (bx + side * 5 - back * 2, top - 7 + droop * 2)
                cv.line(bx, top, mid.0, mid.1, r.outline)
                cv.line(mid.0, mid.1, end.0, end.1, r.outline)
            }
        }
    }
}

func whiskers(_ col: UInt32, long: Bool = false) -> Draw {
    return { cv, c in
        let y = Double(c.eyeY) + 2.5
        for side in sides {
            let x0 = c.faceCX + side * 2.5
            if long {
                let sway = c.p.tail * 0.8
                for i in 0..<6 {
                    let t = Double(i)
                    cv.plot(x0 + side * (1.5 + t), y + sin(t * 0.8 + sway) * 1.2 + t * 0.3, Ramp(col).base)
                }
            } else {
                cv.line(x0 + side * 2, y, x0 + side * 4.5, y - 0.8, Ramp(col).light)
                cv.line(x0 + side * 2, y + 1, x0 + side * 4.5, y + 1.5, Ramp(col).light)
            }
        }
    }
}

// MARK: - Front: held items and overlays

enum Item { case pebble, fig, seed, sprig, violin, bigLeaf, flower, berry }

func holds(_ item: Item) -> Draw {
    return { cv, c in
        let up: Bool = { if case .up = c.p.arms.0 { return true }; return false }()
        if c.p.lying && item != .bigLeaf { return }
        // Held in the front (right) hand at the side so the face stays visible; overhead when arms are up.
        let x = up ? c.cx + 0.5 : c.cx + c.rx * 0.78
        let y = up ? c.headTop - 2.5 : c.cy + c.ry * 0.38
        switch item {
        case .pebble: cv.ellipse(x, y, 2.4, 1.9, Ramp(0x9DA7B3), glossy: true)
        case .fig:
            cv.ellipse(x, y + 0.5, 2.3, 2.4, Ramp(0x7B3F8C), glossy: true)
            cv.plot(x, y - 2.2, 0x5E8C3A)
        case .seed:
            cv.ellipse(x, y, 1.6, 2.6, Ramp(0x3A3A40), rot: 0.4)
            cv.line(x - 0.8, y - 1.6, x + 0.6, y + 1.8, 0xE8E2D0)
        case .sprig:
            cv.line(x - 2, y + 2, x + 2, y - 3, 0x6E5A3A)
            for (dx, dy) in [(-1.5, 0.0), (1.2, -1.2), (2.3, -3.3), (-0.2, -2.4)] { cv.ellipse(x + dx, y + dy, 1.5, 0.9, Ramp(0x8DB89A), rot: -0.6) }
        case .violin:
            cv.blob([Ell(cx: x - 0.5, cy: y + 1, rx: 2.2, ry: 1.8), Ell(cx: x + 0.6, cy: y - 1.2, rx: 1.7, ry: 1.4)], Ramp(0xB5652B), glossy: true)
            cv.line(x + 1.5, y - 2.5, x + 4, y - 5.5, 0x4A2A12)
            let bow = c.p.acc == 2 ? 1.5 : 0
            cv.line(x - 4 + bow, y - 2.5, x + 3 + bow, y + 3, 0xE8D5B0)
        case .bigLeaf:
            let ly = c.p.lying ? c.headTop + 0.5 : c.headTop - 3
            cv.ellipse(x, ly, 6.5, 2.6, Ramp(0x6CC24A), rot: c.p.lying ? 0 : -0.15)
            cv.line(x - 5.5, ly + 0.5, x + 5.5, ly - 0.8, Ramp(0x6CC24A).shade)
            cv.line(x - 5.5, ly + 1.5, x - 7.5, ly + 2.5, 0x4A7A2A)
        case .berry:
            cv.ellipse(x, y, 2.2, 2.1, Ramp(0x4A5FC1), glossy: true)
            cv.plot(x - 0.5, y - 2, 0x2A3070); cv.plot(x + 0.5, y - 2, 0x2A3070)
        case .flower:
            for (dx, dy) in [(-1.2, 0.0), (1.2, 0.0), (0.0, -1.2), (0.0, 1.2)] { cv.ellipse(x + dx, y + dy, 1.2, 1.2, Ramp(0xFF9EC4)) }
            cv.plot(x, y, 0xFFD54A)
        }
    }
}

func teacup(_ col: UInt32 = 0xF4F1EA, _ pattern: UInt32 = 0x5B8FD9) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        let top = c.cy + c.ry * 0.15, bot = GROUND - 1.2
        let w = c.rx + 1.8
        cv.poly([(c.cx - w, top), (c.cx + w, top), (c.cx + w * 0.72, bot), (c.cx - w * 0.72, bot)], r)
        cv.blob([Ell(cx: c.cx, cy: top, rx: w, ry: 1.3)], r, glossy: true, clipMinY: top - 0.2)
        for t in stride(from: -1.2, through: 1.2, by: 0.3) { cv.plot(c.cx + w + 1.6 + cos(t) * 1.8, top + 3.2 + sin(t) * 2.2, r.outline) }
        for u in [-0.55, -0.15, 0.25, 0.65] { cv.plot(c.cx + u * w, top + 3, Ramp(pattern).base); cv.plot(c.cx + u * w + 0.8, top + 3.8, Ramp(pattern).light) }
        cv.blob([Ell(cx: c.cx, cy: bot + 0.3, rx: w * 0.62, ry: 0.9)], r)
    }
}

func cloudPuffs() -> Draw {
    return { cv, c in
        let r = Ramp(0xF6F8FF)
        let y = GROUND - 2.5
        cv.blob([Ell(cx: c.cx - 5, cy: y, rx: 3.6, ry: 2.4), Ell(cx: c.cx, cy: y - 0.8, rx: 4.2, ry: 2.8), Ell(cx: c.cx + 5, cy: y, rx: 3.4, ry: 2.3)], r)
    }
}

func ripples() -> Draw {
    return { cv, c in
        let r = Ramp(0x8FD3F0)
        cv.blob([Ell(cx: c.cx - 2, cy: GROUND - 1.2, rx: 13, ry: 2.2)], r, glossy: true, clipMinY: GROUND - 2.6)
        for x in stride(from: Int(c.cx - 10), through: Int(c.cx + 8), by: 4) { cv.plot(x + Int(c.p.tail * 2), Int(GROUND - 2), 0xFFFFFF) }
    }
}

func tentacles(_ col: UInt32? = nil) -> Draw {
    return { cv, c in
        let r = Ramp(col ?? c.sp.main)
        for i in 0..<6 {
            let u = -0.85 + Double(i) * 0.34
            let x = c.cx + u * c.rx, out = u < 0 ? -1.0 : 1.0
            let sway = sin(Double(i) + c.p.tail * 2) * 0.8 + c.p.lean * 0.3
            let lift = c.p.lift > 1 ? -1.5 : 0
            let es = curve((x, c.cy + c.ry * 0.55), (x + out * 1.5, GROUND - 2 + lift), (x + out * 3 + sway, GROUND - 3.6 + lift), r0: 1.6, r1: 0.7, steps: 6)
            cv.blob(es, r)
            cv.plot(es[3].cx, es[3].cy + 0.5, r.light)
        }
    }
}

func scytheArms(_ col: UInt32) -> Draw {
    return { cv, c in
        let r = Ramp(col)
        let raised = c.p.acc == 2 || c.p.lift > 1.5
        for side in sides {
            let sh = (c.cx + side * c.rx * 0.55, c.cy - c.ry * 0.05)
            let elbow = (c.cx + side * c.rx * 0.25, c.cy + c.ry * (raised ? -0.5 : 0.4))
            let hand = (c.cx + side * c.rx * 0.05 + (raised ? side * 3 : 0), c.cy - c.ry * (raised ? 1.0 : 0.05))
            cv.blob(curve(sh, elbow, hand, r0: 1.3, r1: 1.0, steps: 5), r)
            cv.plot(hand.0 - side * 0.5, hand.1 - 1, r.outline)
        }
    }
}

func blossomCrown(_ c1: UInt32, _ c2: UInt32) -> Draw {
    return { cv, c in
        for (i, u) in [-0.6, -0.2, 0.2, 0.6].enumerated() {
            let x = c.hx + u * c.hrx, y = c.headTop + 1.2 + abs(u) * 1.5
            let col = Ramp(i % 2 == 0 ? c1 : c2)
            for (dx, dy) in [(-0.9, 0.0), (0.9, 0.0), (0.0, -0.9), (0.0, 0.9)] { cv.plot(x + dx, y + dy, col.base) }
            cv.plot(x, y, 0xFFE38A)
        }
    }
}

/// Lace-like side lobes (mantis).
func laceLobes(_ col: UInt32) -> Draw {
    return { cv, c in
        for side in sides {
            cv.ellipse(c.cx + side * (c.rx + 0.4), c.cy + c.ry * 0.55, 2.6, 1.5, Ramp(col), rot: side * 0.6)
        }
    }
}

/// Plain spiral snail shell behind the body.
func swirlShell(_ col: UInt32, _ line: UInt32) -> Draw {
    return { cv, c in
        let r = 7.6, sx = c.cx - c.rx * 0.95, sy = c.cy - c.ry * 0.55 - 1.5
        cv.ellipse(sx, sy, r, r, Ramp(col), glossy: true)
        let l = Ramp(line).base
        var a = 0.0
        while a < 4.2 * Double.pi {
            let rr = 0.6 + a / (4.2 * Double.pi) * (r - 1.6)
            cv.plot(sx + cos(a) * rr, sy + sin(a) * rr, l)
            a += 0.18
        }
    }
}

/// Little fur tufts on top of pointed ears (lynx).
func earTufts(_ col: UInt32, spread: Double = 0.5) -> Draw {
    return { cv, c in
        for side in sides {
            let x = c.hx + side * c.hrx * spread + side * (1 + max(0, c.p.ear) * 2) - max(0, -c.p.ear) * 1.5
            let y = c.headTop - 4.5 + max(0, c.p.ear) * 2
            cv.line(x, y, x + side * 0.6, y - 2.5, Ramp(col).base)
        }
    }
}

/// White face with two dark stripes running up through the eyes (badger).
func badgerStripes(_ face: UInt32, _ stripe: UInt32) -> Draw {
    return { cv, c in
        cv.ellipse(c.faceCX, Double(c.eyeY) + 0.5, c.hrx * 0.72, c.hry * 0.75, Ramp(face), outline: false)
        for x in [Double(c.lx) + 0.5, Double(c.rxp) + 0.5] {
            cv.blob([Ell(cx: x, cy: Double(c.eyeY) - 1.5, rx: 1.7, ry: 4.2)], Ramp(stripe), outline: false, flat: true)
        }
    }
}

/// Small chin tuft (goat kid).
func beard(_ col: UInt32) -> Draw {
    return { cv, c in cv.ellipse(c.faceCX + 0.5, Double(c.mouthY) + 3.2, 1.3, 2.0, Ramp(col)) }
}

/// Soft fins along the back of a long neck (lake monster).
func neckFins(_ col: UInt32) -> Draw {
    return { cv, c in
        for t in [0.25, 0.5, 0.75] {
            let x = c.cx + c.rx * (0.3 + 0.35 * (1 - t)) - 2.2, y = c.cy + c.ry * (0.15 - 1.0 * t)
            cv.ellipse(x, y, 1.6, 1.0, Ramp(col), rot: -0.6)
        }
    }
}

/// Raindrop / snowflake / freckle dots in a fixed pattern on the cheeks and back.
func freckles(_ col: UInt32) -> Draw {
    return { cv, c in
        for (u, v) in [(-0.62, -0.35), (0.58, -0.45), (-0.45, -0.7), (0.72, -0.05)] {
            cv.plot(c.cx + u * c.rx, c.cy + v * c.ry, Ramp(col).base)
            cv.plot(c.cx + u * c.rx, c.cy + v * c.ry + 1, Ramp(col).light)
        }
    }
}
