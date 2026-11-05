// Custom silhouettes for the spirit Gremlets: everyday objects, plants and weather that came alive.
// Each draws the whole body; the shared renderer adds the face, arms, feet and emotes on top.

import Foundation

/// Draws a straight line, but only over pixels that already hold one of `onto` (keeps details inside a shape).
func lineInside(_ cv: inout Canvas, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ col: UInt32, onto: Set<UInt32>) {
    let n = max(1, Int(max(abs(x1 - x0), abs(y1 - y0)).rounded(.up)))
    for i in 0...n {
        let t = Double(i) / Double(n)
        let x = Int((x0 + (x1 - x0) * t).rounded(.down)), y = Int((y0 + (y1 - y0) * t).rounded(.down))
        if let c = cv.get(x, y), onto.contains(c) { cv.plot(x, y, col) }
    }
}

func tones(_ r: Ramp) -> Set<UInt32> { [r.base, r.light, r.shade, r.spec] }

// MARK: Objects

/// Paper umbrella on one hopping leg (one-eyed, like the old folk tales).
func umbrellaBody(_ paper: UInt32, _ rib: UInt32, _ leg: UInt32) -> Draw {
    return { cv, c in
        let w = c.rx + 1.5, top = c.cy - c.ry - 3.5, edge = c.cy - 0.5
        var pts: [(Double, Double)] = []
        for i in 0...14 {
            let a = Double.pi * Double(i) / 14
            pts.append((c.cx - cos(a) * w, edge - sin(a) * (edge - top)))
        }
        for i in stride(from: 6, through: 0, by: -1) {
            pts.append((c.cx - w + Double(i) * (2 * w / 6), edge + (i % 2 == 1 ? 1.4 : 0)))
        }
        cv.line(c.cx, edge, c.cx, c.bottom - 1, Ramp(leg).base)
        cv.line(c.cx + 1, edge, c.cx + 1, c.bottom - 1, Ramp(leg).shade)
        cv.ellipse(c.cx + 0.5, c.bottom + 0.2, 2.0, 1.1, Ramp(leg))
        cv.poly(pts, Ramp(paper))
        let p = Ramp(paper)
        for k in [-0.62, 0.62] { lineInside(&cv, c.cx, top + 1, c.cx + k * w, edge, Ramp(rib).base, onto: tones(p)) }
        cv.ellipse(c.cx, top - 0.8, 0.9, 1.3, Ramp(rib))
    }
}

/// Diamond kite with a ribbon tail.
func kiteBody(_ a: UInt32, _ b: UInt32, _ tail: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy - 1, rx = c.rx, ry = c.ry
        let sway = c.p.tail
        let es = curve((cx, cy + ry * 0.9), (cx - 4 + sway * 2, GROUND - 2), (cx - 10 + sway * 3, GROUND - 6), r0: 0.5, r1: 0.5, steps: 14)
        for e in es { cv.plot(e.cx, e.cy, Ramp(tail).shade) }
        for (i, e) in es.enumerated() where i % 4 == 3 { cv.ellipse(e.cx, e.cy, 1.4, 0.8, Ramp(tail), rot: 0.6) }
        let top = (cx, cy - ry * 1.15), right = (cx + rx, cy - ry * 0.15), bot = (cx, cy + ry), left = (cx - rx, cy - ry * 0.15)
        cv.poly([top, right, bot, left], Ramp(a))
        cv.poly([top, right, (cx, cy - ry * 0.15)], Ramp(b), outline: false)
        cv.poly([(cx, cy - ry * 0.15), bot, left], Ramp(b), outline: false)
    }
}

/// Folded paper crane: one bold silhouette with soft fold lines.
func craneBody(_ col: UInt32, _ fold: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry, w = c.p.wing * 2
        let R = Ramp(col)
        let pts: [(Double, Double)] = [
            (cx, cy + ry * 0.85), (cx - rx * 0.6, cy + ry * 0.15), (cx - rx - 3, cy - ry * 0.75), (cx - rx * 0.3, cy - ry * 0.05),
            (cx - rx * 0.75, cy - ry * 1.45 - w), (cx - 0.5, cy - ry * 0.3), (cx + rx * 0.45, cy - ry * 1.35 - w),
            (cx + rx * 0.4, cy - ry * 0.05), (cx + rx + 2.5, cy - ry * 1.1), (cx + rx + 4.5, cy - ry * 0.75), (cx + rx * 0.7, cy + ry * 0.25),
        ]
        cv.poly(pts, R, flat: true)
        let F = Ramp(fold).base
        let inside = tones(R)
        lineInside(&cv, cx, cy + ry * 0.8, cx, cy - ry * 0.25, F, onto: inside)
        lineInside(&cv, cx - 0.5, cy - ry * 0.3, cx - rx * 0.7, cy - ry * 1.4 - w, F, onto: inside)
        lineInside(&cv, cx, cy - ry * 0.25, cx + rx * 0.42, cy - ry * 1.3 - w, F, onto: inside)
        lineInside(&cv, cx + rx * 0.45, cy - ry * 0.05, cx + rx + 2.3, cy - ry * 1.0, F, onto: inside)
    }
}

/// Folded paper boat.
func boatBody(_ hull: UInt32, _ sail: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry
        cv.poly([(cx - 0.5, cy - ry * 1.35), (cx + rx * 0.8, cy - ry * 0.1), (cx - 0.5, cy - ry * 0.1)], Ramp(sail))
        cv.poly([(cx - 0.5, cy - ry * 1.15), (cx - rx * 0.65, cy - ry * 0.1), (cx - 0.5, cy - ry * 0.1)], Ramp(Ramp(sail).shade))
        cv.poly([(cx - rx - 1.5, cy - ry * 0.15), (cx + rx + 1.5, cy - ry * 0.15), (cx + rx * 0.7, cy + ry), (cx - rx * 0.7, cy + ry)], Ramp(hull))
        cv.line(cx - rx - 0.5, cy - ry * 0.15 + 1, cx + rx + 0.5, cy - ry * 0.15 + 1, Ramp(hull).light)
    }
}

/// Rice ball with a seaweed band.
func riceBody(_ rice: UInt32, _ nori: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry
        let R = Ramp(rice)
        let body = [Ell(cx: cx, cy: cy - ry * 0.5, rx: rx * 0.55, ry: ry * 0.52), Ell(cx: cx - rx * 0.48, cy: cy + ry * 0.38, rx: rx * 0.55, ry: ry * 0.6),
                    Ell(cx: cx + rx * 0.48, cy: cy + ry * 0.38, rx: rx * 0.55, ry: ry * 0.6), Ell(cx: cx, cy: cy + ry * 0.2, rx: rx * 0.82, ry: ry * 0.75)]
        cv.blob(body, R)
        for (u, v) in [(-0.4, -0.3), (0.35, -0.5), (0.65, 0.1), (-0.7, 0.2), (0.1, -0.8)] { cv.plot(cx + u * rx, cy + v * ry, R.shade) }
        for e in [Ell(cx: cx, cy: cy + ry * 0.75, rx: rx * 0.4, ry: ry * 0.6)] {
            let (set, _) = blobPixels([e], clipMinY: cy + ry * 0.45)
            for q in set where tones(R).contains(cv.px[q] ?? 0) { cv.px[q] = Ramp(nori).base }
        }
    }
}

/// Steamed bun with a pleated swirl on top.
func baoBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.25, rx: c.rx, ry: c.ry)], R, clipMaxY: c.cy + c.ry * 0.95)
        let tx = c.cx + c.p.tilt * 0.5, ty = c.cy - c.ry * 0.62
        for k in 0..<5 {
            let a = Double(k) / 5 * Double.pi * 2 + 0.3
            cv.line(tx, ty, tx + cos(a) * 2.6, ty + sin(a) * 1.3 + 0.4, R.shade)
        }
        cv.plot(tx, ty, R.outline)
    }
}

/// Spinning top balanced on its point.
func topBody(_ a: UInt32, _ band: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy - 1, rx = c.rx, ry = c.ry
        let tip = c.bottom
        cv.poly([(cx - rx * 0.92, cy - ry * 0.15), (cx + rx * 0.92, cy - ry * 0.15), (cx + 0.6, tip), (cx - 0.6, tip)], Ramp(a))
        let disc = Ell(cx: cx, cy: cy - ry * 0.25, rx: rx, ry: ry * 0.55)
        cv.blob([disc], Ramp(a))
        cv.blob([disc], Ramp(band), outline: false, clipMaxY: cy + ry * 0.05, clipMinY: cy - ry * 0.12)
        cv.blob([Ell(cx: cx, cy: cy + ry * 0.35, rx: rx * 0.6, ry: ry * 0.3)], Ramp(band), outline: false, clipMaxY: cy + ry * 0.45, clipMinY: cy + ry * 0.3)
        cv.ellipse(cx, cy - ry * 0.85, 1.2, 1.4, Ramp(band))
    }
}

/// Ball of yarn with a loose thread.
func yarnBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        let es = curve((c.cx - c.rx * 0.8, c.cy + c.ry * 0.6), (c.cx - c.rx - 3, GROUND - 1), (c.cx - c.rx - 7 + c.p.tail * 2, GROUND - 1.5), r0: 0.5, r1: 0.5, steps: 12)
        for e in es { cv.plot(e.cx, e.cy, R.shade) }
        cv.ellipse(c.cx, c.cy, c.rx, c.ry, R)
        for k in -2...2 {
            let off = Double(k) * 2.6
            lineInside(&cv, c.cx + off - 3, c.cy - c.ry, c.cx + off + 3, c.cy + c.ry, R.shade, onto: [R.base, R.light])
        }
        lineInside(&cv, c.cx - c.rx, c.cy - c.ry * 0.2, c.cx + c.rx, c.cy - c.ry * 0.6, R.light, onto: [R.base, R.shade])
    }
}

/// Old clay pot that woke up after a hundred years on a shelf.
func potBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.22, rx: c.rx, ry: c.ry * 0.78), Ell(cx: c.cx, cy: c.cy - c.ry * 0.55, rx: c.rx * 0.62, ry: c.ry * 0.42)], R)
        cv.blob([Ell(cx: c.cx, cy: c.cy - c.ry * 0.92, rx: c.rx * 0.72, ry: 1.4)], Ramp(R.shade))
        let y = Int(c.cy + c.ry * 0.58)
        for x in Int(c.cx - c.rx)...Int(c.cx + c.rx) where cv.get(x, y) == R.base || cv.get(x, y) == R.light { cv.plot(x, y, R.shade) }
    }
}

// MARK: Plants

func leafBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry, R = Ramp(col)
        cv.blob(curve((cx - 0.5, cy + ry * 0.9), (cx - 2.5, cy + ry * 1.25), (cx - 5 + c.p.tail, cy + ry * 1.0), r0: 0.7, r1: 0.6, steps: 6), Ramp(R.shade))
        var pts: [(Double, Double)] = []
        for i in 0...20 { let t = Double(i) / 20 * Double.pi; pts.append((cx + sin(t) * rx * (1.0 - 0.18 * cos(t)), cy - ry * 1.1 * cos(t))) }
        for i in 0...20 { let t = Double.pi - Double(i) / 20 * Double.pi; pts.append((cx - sin(t) * rx * (1.0 - 0.18 * cos(t)), cy - ry * 1.1 * cos(t))) }
        cv.poly(pts, R)
        lineInside(&cv, cx, cy - ry * 1.05, cx, cy - ry * 0.55, R.shade, onto: tones(R))
        lineInside(&cv, cx, cy + ry * 0.45, cx, cy + ry * 1.05, R.shade, onto: tones(R))
        for side in sides { lineInside(&cv, cx, cy + ry * 0.75, cx + side * rx * 0.65, cy + ry * 0.4, R.shade, onto: tones(R)) }
    }
}

func mushroomBody(_ cap: UInt32, _ spot: UInt32, _ stem: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry
        cv.blob([Ell(cx: cx, cy: cy + ry * 0.38, rx: rx * 0.66, ry: ry * 0.62)], Ramp(stem))
        let capY = cy - ry * 0.18, lift = c.p.acc == 2 ? 1.0 : 0
        cv.blob([Ell(cx: c.hx, cy: capY - lift, rx: rx * 1.3, ry: ry * 0.9)], Ramp(cap), glossy: true, clipMaxY: capY + 0.6 - lift)
        for (u, v, r) in [(-0.62, -0.4, 1.2), (0.12, -0.78, 1.0), (0.68, -0.3, 1.1)] {
            cv.ellipse(c.hx + u * rx * 1.2, capY - lift + v * ry, r, r, Ramp(spot), outline: false, flat: true)
        }
    }
}

func logBody(_ bark: UInt32, _ wood: UInt32, _ leaf: UInt32) -> Draw {
    return { cv, c in
        let W = Ramp(wood)
        cv.ellipse(c.cx + 2, c.cy - c.ry - 1.2, 1.8, 1.0, Ramp(leaf), rot: -0.5)
        cv.line(c.cx + 1, c.cy - c.ry + 0.5, c.cx + 1.5, c.cy - c.ry - 1, Ramp(leaf).shade)
        cv.ellipse(c.cx, c.cy, c.rx, c.ry, Ramp(bark))
        cv.ellipse(c.cx, c.cy, c.rx - 1.7, c.ry - 1.7, W, outline: false, flat: true)
        var a = 0.0
        while a < 2 * Double.pi {
            cv.plot(c.cx + cos(a) * (c.rx - 3.4), c.cy + sin(a) * (c.ry - 3.4), W.shade)
            a += 0.1
        }
    }
}

func budBody(_ petal: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry, P = Ramp(petal)
        for (dx, h) in [(-rx * 0.55, 3.5), (0.0, 4.6), (rx * 0.55, 3.5)] {
            cv.poly([(cx + dx - 2.4, cy - ry * 0.4), (cx + dx + c.p.tilt * 0.4, cy - ry * 0.4 - h), (cx + dx + 2.4, cy - ry * 0.4)], P)
        }
        cv.blob([Ell(cx: cx, cy: cy + ry * 0.15, rx: rx, ry: ry * 0.85)], P)
        for side in sides { lineInside(&cv, cx + side * rx * 0.62, cy - ry * 0.4, cx + side * rx * 0.55, cy + ry * 0.75, P.shade, onto: tones(P)) }
    }
}

func turnipBody(_ white: UInt32, _ purple: UInt32, _ leaf: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry
        for (dx, rot) in [(-2.2, -0.5), (0.0, 0.0), (2.2, 0.5)] {
            cv.ellipse(cx + dx + c.p.tilt * 0.6, cy - ry - 2.2, 1.6, 3.2, Ramp(leaf), rot: rot)
        }
        let body = [Ell(cx: cx, cy: cy + ry * 0.12, rx: rx, ry: ry * 0.88), Ell(cx: cx, cy: cy - ry * 0.55, rx: rx * 0.55, ry: ry * 0.45)]
        cv.blob(body, Ramp(white))
        cv.blob(body, Ramp(purple), outline: false, clipMaxY: cy - ry * 0.25)
    }
}

func peachBody(_ col: UInt32, _ blush: UInt32, _ leaf: UInt32) -> Draw {
    return { cv, c in
        let cx = c.cx, cy = c.cy, rx = c.rx, ry = c.ry
        cv.ellipse(cx + 2.4, cy - ry - 0.4, 2.8, 1.2, Ramp(leaf), rot: -0.45)
        let body = [Ell(cx: cx - rx * 0.24, cy: cy + ry * 0.05, rx: rx * 0.78, ry: ry * 0.95), Ell(cx: cx + rx * 0.24, cy: cy + ry * 0.05, rx: rx * 0.78, ry: ry * 0.95)]
        cv.blob(body, Ramp(col))
        let (set, _) = blobPixels([Ell(cx: cx + rx * 0.35, cy: cy + ry * 0.4, rx: rx * 0.6, ry: ry * 0.55)])
        let C = Ramp(col), B = Ramp(blush)
        for q in set { if cv.px[q] == C.base { cv.px[q] = B.base } else if cv.px[q] == C.light { cv.px[q] = B.light } }
        lineInside(&cv, cx, cy - ry * 0.95, cx + 0.5, cy - ry * 0.45, C.shade, onto: tones(C).union(tones(B)))
    }
}

func cloverBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.line(c.cx - 1, c.cy + c.ry * 0.8, c.cx - 4 + c.p.tail, GROUND - 1.5, R.shade)
        for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let x = c.cx + dx * c.rx * 0.5, y = c.cy + dy * c.ry * 0.5
            cv.ellipse(x, y, c.rx * 0.55, c.ry * 0.55, R)
            cv.plot(c.cx + dx * c.rx * 0.95, c.cy + dy * c.ry * 0.95, R.outline)
        }
        cv.ellipse(c.cx, c.cy, c.rx * 0.6, c.ry * 0.6, R)
    }
}

/// Maple seed: round seed with one long veined wing that spins when it flies.
func samaraBody(_ seed: UInt32, _ wing: UInt32) -> Draw {
    return { cv, c in
        let th = 0.45 + c.p.wing * 0.35 + (c.p.flying ? 0.3 : 0)
        let bx = c.cx - c.rx * 0.2, by = c.cy - c.ry * 0.5
        let dx = -sin(th), dy = -cos(th)
        let W = Ramp(wing)
        cv.ellipse(bx + dx * 7, by + dy * 7, 2.6, 7.2, W, rot: -th)
        for k in [-1.0, 0.0, 1.0] { cv.line(bx + k * 0.6, by, bx + dx * 12 + k * 0.8, by + dy * 12, W.shade) }
        cv.ellipse(c.cx, c.cy, c.rx, c.ry, Ramp(seed))
    }
}

func teabudBody(_ col: UInt32, _ wrap: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.poly([(c.cx - 2, c.cy - c.ry * 0.6), (c.cx + 1.5 + c.p.tilt * 0.5, c.cy - c.ry - 4), (c.cx + 2.5, c.cy - c.ry * 0.5)], R)
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.1, rx: c.rx * 0.85, ry: c.ry)], R)
        cv.ellipse(c.cx - c.rx * 0.55, c.cy + c.ry * 0.35, c.rx * 0.55, c.ry * 0.75, Ramp(wrap), rot: -0.35)
    }
}

func hexBody(_ col: UInt32, _ drip: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        var pts: [(Double, Double)] = []
        for i in 0..<6 { let a = Double(i) * Double.pi / 3 + Double.pi / 6; pts.append((c.cx + cos(a) * c.rx, c.cy + sin(a) * c.ry)) }
        cv.poly(pts, R, flat: false)
        for i in 0..<6 {
            let a0 = Double(i) * Double.pi / 3 + Double.pi / 6, a1 = a0 + Double.pi / 3
            lineInside(&cv, c.cx + cos(a0) * c.rx * 0.78, c.cy + sin(a0) * c.ry * 0.78, c.cx + cos(a1) * c.rx * 0.78, c.cy + sin(a1) * c.ry * 0.78, R.light, onto: tones(R))
        }
        cv.ellipse(c.cx + c.rx * 0.45, c.cy + c.ry + 0.8, 1.0, 1.6, Ramp(drip), glossy: true)
    }
}

func blossomBody(_ petal: UInt32, _ center: UInt32) -> Draw {
    return { cv, c in
        let P = Ramp(petal)
        for i in 0..<5 {
            let a = -Double.pi / 2 + Double(i) * 2 * Double.pi / 5 + c.p.tilt * 0.08
            cv.ellipse(c.cx + cos(a) * c.rx * 0.58, c.cy + sin(a) * c.ry * 0.58, c.rx * 0.5, c.ry * 0.46, P, rot: a + Double.pi / 2)
            cv.plot(c.cx + cos(a) * c.rx * 1.02, c.cy + sin(a) * c.ry * 1.02, P.outline)
        }
        cv.ellipse(c.cx, c.cy, c.rx * 0.5, c.ry * 0.5, Ramp(center), outline: false)
    }
}

// MARK: Weather and water

func wispBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        let tail = curve((c.cx - c.rx * 0.3, c.cy + c.ry * 0.55), (c.cx - c.rx - 2, c.cy + c.ry * 1.2), (c.cx - c.rx - 5 + c.p.tail * 2, c.cy + c.ry * 0.15), r0: c.ry * 0.5, r1: 0.8, steps: 9)
        cv.blob([Ell(cx: c.cx, cy: c.cy - c.ry * 0.1, rx: c.rx, ry: c.ry * 0.85)] + tail, R)
        var a = 0.0
        while a < 1.6 * Double.pi {
            let r = 1.0 + a * 0.9
            if let col = cv.get(Int(c.cx - c.rx * 0.35 + cos(a) * r), Int(c.cy + c.ry * 0.5 + sin(a) * r * 0.6)), tones(R).contains(col) {
                cv.plot(c.cx - c.rx * 0.35 + cos(a) * r, c.cy + c.ry * 0.5 + sin(a) * r * 0.6, R.light)
            }
            a += 0.15
        }
    }
}

func dropBody(_ col: UInt32) -> Draw {
    return { cv, c in
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.2, rx: c.rx, ry: c.ry * 0.8)]
                + curve((c.cx, c.cy - c.ry * 0.2), (c.cx + 0.3, c.cy - c.ry * 0.8), (c.cx + 0.8 + c.p.tilt, c.cy - c.ry * 1.3), r0: c.rx * 0.6, r1: 0.5, steps: 8),
                Ramp(col), glossy: true)
    }
}

func crystalBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        let pts = [(c.cx + c.p.tilt * 0.4, c.cy - c.ry * 1.4), (c.cx + c.rx * 0.75, c.cy - c.ry * 0.35), (c.cx + c.rx * 0.62, c.cy + c.ry),
                   (c.cx - c.rx * 0.62, c.cy + c.ry), (c.cx - c.rx * 0.75, c.cy - c.ry * 0.35)]
        cv.poly(pts, R, flat: true)
        lineInside(&cv, pts[0].0, pts[0].1 + 1, c.cx - c.rx * 0.2, c.cy + c.ry * 0.95, R.light, onto: [R.base])
        lineInside(&cv, pts[0].0 + 1, pts[0].1 + 2, c.cx + c.rx * 0.5, c.cy - c.ry * 0.3, R.spec, onto: [R.base, R.light])
        lineInside(&cv, c.cx + c.rx * 0.45, c.cy - c.ry * 0.2, c.cx + c.rx * 0.45, c.cy + c.ry * 0.9, R.shade, onto: [R.base])
    }
}

func jellyBody(_ bell: UInt32, _ ribbon: UInt32) -> Draw {
    return { cv, c in
        let B = Ramp(bell), Rb = Ramp(ribbon)
        let edge = c.cy + c.ry * 0.4
        for i in 0..<4 {
            let x = c.cx - c.rx * 0.6 + Double(i) * c.rx * 0.4
            let sway = sin(Double(i) * 1.7 + c.p.tail * 2) * 1.6
            let es = curve((x, edge), (x + sway, edge + 4), (x - sway, edge + 8 - c.p.lift * 0.5), r0: 0.6, r1: 0.5, steps: 8)
            for e in es { cv.plot(e.cx, e.cy, Rb.base) }
        }
        cv.blob([Ell(cx: c.cx, cy: c.cy - c.ry * 0.05, rx: c.rx, ry: c.ry * 0.9)], B, glossy: true, clipMaxY: edge)
        for i in 0..<5 {
            cv.ellipse(c.cx - c.rx * 0.8 + Double(i) * c.rx * 0.4, edge + 0.4, 1.1, 0.8, Ramp(B.shade), outline: false, flat: true)
        }
    }
}

func bubbleBody() -> Draw {
    return { cv, c in
        let r = c.rx
        for y in 0..<H { for x in 0..<W {
            let dx = Double(x) + 0.5 - c.cx, dy = Double(y) + 0.5 - c.cy
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= r - 0.5 { cv.plot(x, y, 0xF2F8FF) }
            else if d <= r + 0.6 {
                let a = atan2(dy, dx)
                let hue = (sin(a * 2) + 1) / 2
                cv.plot(x, y, hue > 0.66 ? 0xB8E4FF : hue > 0.33 ? 0xFFC2E2 : 0xFFF0A8)
            }
        }}
        cv.ellipse(c.cx - r * 0.45, c.cy - r * 0.45, 1.4, 1.0, Ramp(0xFFFFFF), outline: false, flat: true, rot: -0.6)
    }
}

// MARK: - Round 4: elementals, nature spirits and gentle monsters

/// Stream spirit: a rounded body with a curling wave crest and foam.
func waveBody(_ col: UInt32, _ crest: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.15, rx: c.rx, ry: c.ry * 0.85)]
                + curve((c.cx - c.rx * 0.55, c.cy - c.ry * 0.3), (c.cx - c.rx * 0.1, c.cy - c.ry * 1.45), (c.cx + c.rx * 0.75 + c.p.tilt, c.cy - c.ry * 0.95), r0: 3.0, r1: 1.4, steps: 10), R, glossy: true)
        let es = curve((c.cx - c.rx * 0.5, c.cy - c.ry * 0.75), (c.cx - c.rx * 0.1, c.cy - c.ry * 1.7), (c.cx + c.rx * 0.8 + c.p.tilt, c.cy - c.ry * 1.1), r0: 0.5, r1: 0.5, steps: 12)
        for (i, e) in es.enumerated() where i % 2 == 0 { cv.plot(e.cx, e.cy, Ramp(crest).base) }
        cv.plot(c.cx + c.rx * 0.95 + c.p.tilt, c.cy - c.ry * 0.85, 0xFFFFFF)
    }
}

/// Stacked river stones; the face lives on the top stone.
func cairnBody(_ a: UInt32, _ b: UInt32, _ moss: UInt32) -> Draw {
    return { cv, c in
        let sway = c.p.tilt * 0.5
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.55, rx: c.rx, ry: c.ry * 0.45)], Ramp(a))
        cv.blob([Ell(cx: c.cx - 0.6 + sway * 0.5, cy: c.cy - c.ry * 0.05, rx: c.rx * 0.76, ry: c.ry * 0.38)], Ramp(b))
        cv.ellipse(c.cx - c.rx * 0.45, c.cy - c.ry * 0.2, 1.4, 0.8, Ramp(moss), outline: false, flat: true)
        cv.blob([Ell(cx: c.cx + sway, cy: c.cy - c.ry * 0.62, rx: c.rx * 0.58, ry: c.ry * 0.38)], Ramp(a))
    }
}

/// Crackling ball of static with little lightning spikes.
func staticBody(_ col: UInt32, _ spark: UInt32) -> Draw {
    return { cv, c in
        let S = Ramp(spark)
        for i in 0..<7 {
            let a = Double(i) / 7 * 2 * Double.pi + (c.p.acc == 2 ? 0.25 : 0) + c.p.tail * 0.1
            let r0 = c.rx + 0.3, r1 = c.rx + 3.4
            let mid = (c.cx + cos(a + 0.25) * (r0 + r1) / 2, c.cy + sin(a + 0.25) * (r0 + r1) / 2)
            cv.line(c.cx + cos(a) * r0, c.cy + sin(a) * r0, mid.0, mid.1, S.base)
            cv.line(mid.0, mid.1, c.cx + cos(a) * r1, c.cy + sin(a) * r1, S.light)
        }
        cv.ellipse(c.cx, c.cy, c.rx, c.ry, Ramp(col), glossy: true)
    }
}

/// Soft orb of light with a faint halo.
func lightBody(_ col: UInt32, _ halo: UInt32) -> Draw {
    return { cv, c in
        let r = c.rx + 2.6 + (c.p.acc == 2 ? 0.8 : 0)
        var a = 0.0
        while a < 2 * Double.pi {
            if Int(a * 10) % 3 != 0 { cv.plot(c.cx + cos(a) * r, c.cy + sin(a) * r * (c.ry / c.rx), Ramp(halo).base) }
            a += 0.09
        }
        cv.ellipse(c.cx, c.cy, c.rx, c.ry, Ramp(col), glossy: true)
    }
}

/// A scrap of night sky: a teardrop with stars in it.
func nightBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.blob([Ell(cx: c.cx, cy: c.cy - c.ry * 0.15, rx: c.rx, ry: c.ry * 0.85)]
                + curve((c.cx, c.cy + c.ry * 0.3), (c.cx - 1 + c.p.tail, c.cy + c.ry * 0.9), (c.cx - 2.5 + c.p.tail * 2, c.cy + c.ry * 1.3), r0: c.rx * 0.6, r1: 0.6, steps: 8), R)
        for (u, v) in [(-0.55, -0.55), (0.6, -0.35), (-0.25, 0.45), (0.45, 0.4), (0.05, -0.85)] {
            cv.plot(c.cx + u * c.rx, c.cy + v * c.ry, 0xFFF3B0)
        }
    }
}

/// Moss-covered boulder golem.
func boulderBody(_ stone: UInt32, _ moss: UInt32) -> Draw {
    return { cv, c in
        let body = [Ell(cx: c.cx, cy: c.cy + c.ry * 0.12, rx: c.rx, ry: c.ry * 0.88), Ell(cx: c.cx - c.rx * 0.25, cy: c.cy - c.ry * 0.3, rx: c.rx * 0.7, ry: c.ry * 0.7),
                    Ell(cx: c.cx + c.rx * 0.3, cy: c.cy - c.ry * 0.15, rx: c.rx * 0.7, ry: c.ry * 0.75)]
        cv.blob(body, Ramp(stone))
        cv.blob(body, Ramp(moss), outline: false, clipMaxY: c.cy - c.ry * 0.45)
        for (u, len) in [(-0.6, 2), (-0.1, 1), (0.35, 2), (0.75, 1)] {
            let x = Int(c.cx + u * c.rx), y = Int(c.cy - c.ry * 0.45)
            for d in 0...len { cv.plot(x, y + d, d == len ? Ramp(moss).shade : Ramp(moss).base) }
        }
        cv.plot(c.cx - c.rx * 0.5, c.cy + c.ry * 0.4, Ramp(stone).shade); cv.plot(c.cx + c.rx * 0.55, c.cy + c.ry * 0.2, Ramp(stone).shade)
    }
}

/// Root spirit: a little root body with a leafy sprout and tendril legs.
func rootBody(_ col: UInt32, _ leaf: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        for (dx, rot) in [(-1.8, -0.5), (0.0, 0.0), (1.8, 0.5)] { cv.ellipse(c.cx + dx + c.p.tilt * 0.5, c.cy - c.ry - 2.0, 1.4, 2.8, Ramp(leaf), rot: rot) }
        for (i, dx) in [-0.5, 0.0, 0.5].enumerated() {
            let x = c.cx + dx * c.rx, step = (i % 2 == 0 ? 1.0 : -1.0) * c.p.tail
            for e in curve((x, c.cy + c.ry * 0.7), (x + dx * 3 + step, c.bottom), (x + dx * 5 + step * 1.5, c.bottom + 2.4), r0: 0.5, r1: 0.5, steps: 6) {
                cv.plot(e.cx, e.cy, R.shade)
            }
        }
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.1, rx: c.rx, ry: c.ry * 0.9), Ell(cx: c.cx, cy: c.cy - c.ry * 0.5, rx: c.rx * 0.6, ry: c.ry * 0.5)], R)
    }
}

/// Fiddlehead fern: a curled frond on a stem.
func fernBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.blob(curve((c.cx - 0.5, c.bottom + 1), (c.cx - 1.5 + c.p.tail, c.cy + c.ry * 0.7), (c.cx, c.cy + c.ry * 0.3), r0: 1.2, r1: 1.4, steps: 6), R)
        for k in [0.85, 0.6] { for side in sides { cv.ellipse(c.cx + side * 2.2, c.cy + c.ry * k + 1, 1.8, 0.8, R, rot: side * -0.5) } }
        var es: [Ell] = []
        var a = 0.0
        while a < 2.6 * Double.pi {
            let r = c.rx * (1.0 - a / (3.4 * Double.pi))
            es.append(Ell(cx: c.cx + cos(a + Double.pi / 2) * r * 0.9, cy: c.cy - c.ry * 0.25 + sin(a + Double.pi / 2) * r * 0.9, rx: 1.9, ry: 1.9))
            a += 0.3
        }
        cv.blob(es + [Ell(cx: c.cx, cy: c.cy - c.ry * 0.25, rx: c.rx * 0.6, ry: c.ry * 0.6)], R)
        var b = 0.6
        while b < 2.5 * Double.pi {
            let r = c.rx * (1.0 - b / (3.4 * Double.pi)) * 0.9 - 1.6
            if r > 2.2 { cv.plot(c.cx + cos(b + Double.pi / 2) * r, c.cy - c.ry * 0.25 + sin(b + Double.pi / 2) * r, R.shade) }
            b += 0.12
        }
    }
}

/// Willow spirit: a dome hidden under drooping green fronds.
func willowBody(_ col: UInt32, _ frond: UInt32) -> Draw {
    return { cv, c in
        let F = Ramp(frond)
        cv.blob([Ell(cx: c.cx, cy: c.cy, rx: c.rx, ry: c.ry)], Ramp(col))
        var x = c.cx - c.rx - 1
        var i = 0
        while x <= c.cx + c.rx + 1 {
            let d = (x - c.cx) / (c.rx + 1)
            let topY = c.cy - c.ry * (1 - d * d * 0.8) + 0.5
            let len = c.bottom - topY + (i % 3 == 0 ? 0 : -1.5)
            let sway = c.p.tail * 0.6 * (i % 2 == 0 ? 1 : -1)
            if abs(x - (Double(c.lx) + 0.5)) > 1.6 && abs(x - (Double(c.rxp) + 0.5)) > 1.6 {
                cv.line(x, topY, x + sway, topY + len, i % 2 == 0 ? F.base : F.shade)
            }
            x += 1; i += 1
        }
        cv.blob([Ell(cx: c.cx, cy: c.cy - c.ry * 0.75, rx: c.rx * 0.8, ry: c.ry * 0.35)], F, clipMaxY: c.cy - c.ry * 0.55)
    }
}

/// Geode: a rough stone shell split open to show crystals inside.
func geodeBody(_ shell: UInt32, _ crystal: UInt32) -> Draw {
    return { cv, c in
        let S = Ramp(shell), K = Ramp(crystal)
        cv.blob([Ell(cx: c.cx, cy: c.cy, rx: c.rx, ry: c.ry)], S)
        cv.blob([Ell(cx: c.cx + 0.5, cy: c.cy + 0.3, rx: c.rx * 0.72, ry: c.ry * 0.74)], K, outline: false, flat: true)
        for (u, v) in [(-0.45, -0.35), (0.4, -0.5), (0.55, 0.2), (-0.5, 0.35), (0.0, 0.55)] {
            let x = c.cx + u * c.rx * 0.7, y = c.cy + v * c.ry * 0.7
            cv.poly([(x - 1.2, y + 1.2), (x, y - 1.6), (x + 1.2, y + 1.2)], K, outline: false)
            cv.plot(x, y - 0.6, K.spec)
        }
    }
}

/// Sand dune spirit with wind ripples.
func duneBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.35, rx: c.rx, ry: c.ry)], R, clipMaxY: c.cy + c.ry * 0.95)
        for k in 0..<3 {
            let y = c.cy + c.ry * (0.45 + Double(k) * 0.18)
            lineInside(&cv, c.cx - c.rx * 0.8, y, c.cx + c.rx * 0.8, y - 1, R.shade, onto: tones(R))
        }
        var a = 0.0
        while a < 1.7 * Double.pi { cv.plot(c.cx + 1 + cos(a) * (0.5 + a * 0.5), c.cy - c.ry * 0.6 - 1.5 + sin(a) * (0.5 + a * 0.4), R.light); a += 0.3 }
    }
}

/// Aurora: a floating curtain of light in three soft bands.
func auroraBody(_ a: UInt32, _ b: UInt32, _ cc: UInt32) -> Draw {
    return { cv, c in
        var es: [Ell] = []
        for i in 0...10 {
            let t = Double(i) / 10
            let x = c.cx - c.rx + t * 2 * c.rx
            es.append(Ell(cx: x, cy: c.cy + sin(t * Double.pi * 2 + c.p.tail * 1.5) * 1.6, rx: 2.4, ry: c.ry))
        }
        cv.blob(es, Ramp(a))
        cv.blob(es, Ramp(b), outline: false, clipMinY: c.cy - c.ry * 0.2)
        cv.blob(es, Ramp(cc), outline: false, clipMinY: c.cy + c.ry * 0.45)
    }
}

/// Wind spirit: a little core with leaves orbiting it.
func leafSwirlBody(_ core: UInt32, _ leafA: UInt32, _ leafB: UInt32) -> Draw {
    return { cv, c in
        let spin = c.p.tail * 0.6 + c.p.tilt * 0.3 + c.p.wing * 0.4
        for i in 0..<4 where i % 2 == 1 {
            let a = Double(i) * Double.pi / 2 + spin
            cv.ellipse(c.cx + cos(a) * (c.rx + 2), c.cy + sin(a) * (c.ry + 1.5) * 0.7, 2.6, 1.2, Ramp(i == 1 ? leafA : leafB), rot: a + 1.2)
        }
        cv.ellipse(c.cx, c.cy, c.rx, c.ry, Ramp(core), glossy: true)
        for i in 0..<4 where i % 2 == 0 {
            let a = Double(i) * Double.pi / 2 + spin
            cv.ellipse(c.cx + cos(a) * (c.rx + 2), c.cy + sin(a) * (c.ry + 1.5) * 0.7, 2.6, 1.2, Ramp(i == 0 ? leafA : leafB), rot: a + 1.2)
        }
    }
}

/// Tumbleweed: a loose ball of dry twigs around a straw core.
func tumbleBody(_ core: UInt32, _ twig: UInt32) -> Draw {
    return { cv, c in
        let T = Ramp(twig)
        cv.ellipse(c.cx, c.cy, c.rx * 0.8, c.ry * 0.8, Ramp(core), outline: false)
        let rot = c.p.tail * 0.4
        for i in 0..<5 {
            let a = Double(i) / 5 * Double.pi + rot + 0.3
            let r = c.rx + 0.8
            cv.line(c.cx + cos(a) * r, c.cy + sin(a) * r * (c.ry / c.rx), c.cx - cos(a) * r, c.cy - sin(a) * r * (c.ry / c.rx), i % 2 == 0 ? T.base : T.shade)
        }
        var a = 0.0
        while a < 2 * Double.pi { cv.plot(c.cx + cos(a) * (c.rx + 0.6), c.cy + sin(a) * (c.ry + 0.6), T.shade); a += 0.15 }
        cv.ellipse(c.cx + 0.4, c.cy - c.ry * 0.05, c.rx * 0.68, c.ry * 0.6, Ramp(core), outline: false)
    }
}

/// Bean seed splitting open with a two-leaf sprout.
func sproutBody(_ seed: UInt32, _ leaf: UInt32) -> Draw {
    return { cv, c in
        let L = Ramp(leaf)
        let sway = c.p.tilt * 0.6 + (c.p.acc == 2 ? 0.8 : 0)
        cv.line(c.cx + 0.5, c.cy - c.ry * 0.7, c.cx + 0.5 + sway * 0.5, c.cy - c.ry - 2.5, L.shade)
        cv.ellipse(c.cx - 1.8 + sway, c.cy - c.ry - 3, 2.6, 1.4, L, rot: -0.4)
        cv.ellipse(c.cx + 2.8 + sway, c.cy - c.ry - 3.2, 2.6, 1.4, L, rot: 0.4)
        cv.blob([Ell(cx: c.cx - c.rx * 0.2, cy: c.cy, rx: c.rx * 0.85, ry: c.ry), Ell(cx: c.cx + c.rx * 0.35, cy: c.cy + c.ry * 0.15, rx: c.rx * 0.7, ry: c.ry * 0.85)], Ramp(seed))
        lineInside(&cv, c.cx + 0.5, c.cy - c.ry * 0.95, c.cx + 0.8, c.cy - c.ry * 0.45, Ramp(seed).shade, onto: tones(Ramp(seed)))
    }
}

/// A smooth river stone glowing warm from inside, with curls of steam.
func warmStoneBody(_ stone: UInt32, _ glow: UInt32) -> Draw {
    return { cv, c in
        for (dx, ph) in [(-2.0, 0.0), (2.5, 1.5)] {
            var t = 0.0
            while t < 4 { cv.plot(c.cx + dx + sin(t * 1.6 + ph + c.p.tail) * 0.9, c.cy - c.ry - 1 - t, 0xEEF2F6); t += 0.7 }
        }
        cv.ellipse(c.cx, c.cy + c.ry * 0.1, c.rx, c.ry * 0.9, Ramp(stone), glossy: true)
        let G = Ramp(glow)
        let (set, _) = blobPixels([Ell(cx: c.cx, cy: c.cy + c.ry * 0.25, rx: c.rx * 0.6, ry: c.ry * 0.5)])
        let S = Ramp(stone)
        for q in set { if cv.px[q] == S.base || cv.px[q] == S.shade { cv.px[q] = c.p.acc == 3 ? G.shade : G.base } else if cv.px[q] == S.light { cv.px[q] = G.light } }
    }
}

/// A shaggy little haystack monster.
func haystackBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        var pts: [(Double, Double)] = []
        for i in 0...16 {
            let a = Double.pi * Double(i) / 16
            pts.append((c.cx - cos(a) * c.rx, c.bottom - sin(a) * (c.bottom - (c.cy - c.ry * 1.1)) + (i % 2 == 0 ? 0 : 0.8)))
        }
        cv.poly(pts, R)
        var x = c.cx - c.rx + 1
        var i = 0
        while x < c.cx + c.rx - 1 {
            let d = (x - c.cx) / c.rx
            let top = c.bottom - (1 - d * d) * (c.bottom - (c.cy - c.ry * 1.1)) + 2
            if i % 2 == 0 { lineInside(&cv, x, top, x + c.p.tail * 0.5, c.bottom - 0.5, R.shade, onto: tones(R)) }
            x += 1.5; i += 1
        }
        cv.line(c.cx - 1, c.cy - c.ry * 1.1 - 1, c.cx + 0.5, c.cy - c.ry * 1.1 - 3, R.base)
    }
}

// MARK: - Round 5: overgrown guardian machines (original designs) and more motes and stones

/// Rounded-rectangle outline points (for machine bodies).
func roundedRect(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ r: Double) -> [(Double, Double)] {
    var pts: [(Double, Double)] = []
    let corners = [(cx + w / 2 - r, cy - h / 2 + r, -Double.pi / 2), (cx + w / 2 - r, cy + h / 2 - r, 0.0),
                   (cx - w / 2 + r, cy + h / 2 - r, Double.pi / 2), (cx - w / 2 + r, cy - h / 2 + r, Double.pi)]
    for (x, y, a0) in corners {
        for k in 0...4 { let a = a0 + Double(k) / 4 * Double.pi / 2; pts.append((x + cos(a) * r, y + sin(a) * r)) }
    }
    return pts
}

func rivets(_ cv: inout Canvas, _ pts: [(Double, Double)], _ col: UInt32) {
    for (x, y) in pts { cv.plot(x, y, Ramp(col).light); cv.plot(x + 1, y + 1, Ramp(col).shade) }
}

func mossCap(_ cv: inout Canvas, _ x: Double, _ y: Double, _ w: Double, _ moss: UInt32, flower: UInt32?) {
    let M = Ramp(moss)
    cv.blob([Ell(cx: x, cy: y, rx: w / 2, ry: 2.0)], M, clipMinY: y - 2.2)
    for k in stride(from: x - w / 2 + 1.5, to: x + w / 2 - 1, by: 3) { cv.plot(k, y + 2.0, M.shade) }
    if let f = flower { cv.plot(x + w * 0.2, y - 2.2, f); cv.plot(x + w * 0.2 - 1, y - 2.2, Ramp(f).light); cv.plot(x + w * 0.2, y - 3.2, Ramp(f).light) }
}

/// Round guardian with a moss blanket and a flower on top.
func cogwardenBody(_ metal: UInt32, _ moss: UInt32, _ flower: UInt32) -> Draw {
    return { cv, c in
        cv.poly(roundedRect(c.cx, c.cy + 0.5, c.rx * 2, c.ry * 1.9, 4.5), Ramp(metal))
        rivets(&cv, [(c.cx - c.rx + 2, c.cy + c.ry * 0.6), (c.cx + c.rx - 3, c.cy + c.ry * 0.6), (c.cx - c.rx + 2, c.cy - c.ry * 0.3), (c.cx + c.rx - 3, c.cy - c.ry * 0.3)], metal)
        mossCap(&cv, c.cx, c.cy - c.ry * 0.9, c.rx * 1.9, moss, flower: flower)
    }
}

/// Small boxy machine with a sapling growing from its antenna socket.
func rivetBody(_ metal: UInt32, _ panel: UInt32, _ leaf: UInt32) -> Draw {
    return { cv, c in
        let top = c.cy - c.ry * 0.95
        cv.line(c.cx + 0.5, top, c.cx + 0.5 + c.p.tilt * 0.5, top - 4, Ramp(leaf).shade)
        cv.ellipse(c.cx - 1.2 + c.p.tilt * 0.5, top - 4.2, 1.8, 1.0, Ramp(leaf), rot: -0.5)
        cv.ellipse(c.cx + 2.4 + c.p.tilt * 0.5, top - 4.6, 1.8, 1.0, Ramp(leaf), rot: 0.5)
        cv.poly(roundedRect(c.cx, c.cy, c.rx * 2, c.ry * 1.9, 2.5), Ramp(metal))
        cv.poly(roundedRect(c.cx, c.cy + c.ry * 0.55, c.rx * 1.1, c.ry * 0.55, 1.2), Ramp(panel), outline: false)
        rivets(&cv, [(c.cx - c.rx + 1.5, c.cy - c.ry * 0.7), (c.cx + c.rx - 2.5, c.cy - c.ry * 0.7)], metal)
    }
}

/// Floating sphere drone with an equator band, side fins and trailing vines.
func orbDroneBody(_ metal: UInt32, _ band: UInt32, _ vine: UInt32) -> Draw {
    return { cv, c in
        let V = Ramp(vine)
        for (i, dx) in [-0.45, 0.1, 0.5].enumerated() {
            let x = c.cx + dx * c.rx
            let len = [6.0, 8.5, 5.0][i]
            for t in stride(from: 0.0, through: len, by: 1) {
                cv.plot(x + sin(t * 0.9 + c.p.tail * 2 + Double(i)) * 0.8, c.cy + c.ry * 0.85 + t, V.base)
            }
            cv.ellipse(x + 0.8, c.cy + c.ry * 0.85 + len * 0.6, 1.1, 0.7, V, outline: false)
        }
        for side in sides { cv.ellipse(c.cx + side * (c.rx + 1.2), c.cy, 1.6, 2.6, Ramp(band), rot: side * (0.3 + c.p.wing * 0.3)) }
        cv.ellipse(c.cx, c.cy, c.rx, c.ry, Ramp(metal), glossy: true)
        cv.blob([Ell(cx: c.cx, cy: c.cy, rx: c.rx, ry: c.ry)], Ramp(band), outline: false, clipMaxY: c.cy + c.ry * 0.45, clipMinY: c.cy + c.ry * 0.25)
    }
}

/// Little tread-wheeled machine with a mushroom growing on its head.
func treadBody(_ metal: UInt32, _ tread: UInt32, _ cap: UInt32) -> Draw {
    return { cv, c in
        let T = Ramp(tread)
        let ty = c.bottom - 1.6
        cv.poly(roundedRect(c.cx, ty, c.rx * 2.1, 4.2, 2.0), T)
        for k in stride(from: c.cx - c.rx + 1.5, through: c.cx + c.rx - 1, by: 2.5) {
            cv.plot(k + (c.p.legs.isDangle ? 0 : c.p.tail), ty, T.light)
        }
        cv.poly(roundedRect(c.cx, c.cy - 1, c.rx * 1.8, c.ry * 1.6, 3.5), Ramp(metal))
        let top = c.cy - 1 - c.ry * 0.8
        cv.line(c.cx + 2, top, c.cx + 2, top - 2.5, 0xF2E8D6)
        cv.blob([Ell(cx: c.cx + 2, cy: top - 2.8, rx: 3.0, ry: 2.0)], Ramp(cap), clipMaxY: top - 2.4)
        cv.plot(c.cx + 1, top - 3.8, 0xFFFFFF)
    }
}

/// Brass boiler machine with a chimney that puffs steam and a pressure gauge on its chest.
func boilerBody(_ brass: UInt32, _ band: UInt32) -> Draw {
    return { cv, c in
        let B = Ramp(brass)
        cv.poly(roundedRect(c.cx - c.rx * 0.5, c.cy - c.ry - 1.5, 2.6, 4.5, 0.6), Ramp(band))
        cv.poly(roundedRect(c.cx, c.cy, c.rx * 1.9, c.ry * 2.0, 4.0), B)
        for y in [c.cy - c.ry * 0.45, c.cy + c.ry * 0.5] {
            lineInside(&cv, c.cx - c.rx, y, c.cx + c.rx, y, Ramp(band).base, onto: tones(B))
        }
        cv.ellipse(c.cx + c.rx * 0.5, c.cy + c.ry * 0.62, 1.4, 1.4, Ramp(0xF6F2E6))
        cv.plot(c.cx + c.rx * 0.5 + 0.6, c.cy + c.ry * 0.62 - 0.6, 0xC0392B)
    }
}

/// Round machine with a mossy listening dish on top.
func dishBody(_ metal: UInt32, _ moss: UInt32) -> Draw {
    return { cv, c in
        let tilt = -0.35 + c.p.tilt * 0.15
        let dy = c.cy - c.ry - 2.8
        cv.line(c.cx, c.cy - c.ry * 0.8, c.cx, dy + 1, Ramp(metal).shade)
        cv.ellipse(c.cx + 0.5, dy, 5.2, 2.2, Ramp(metal), rot: tilt)
        cv.ellipse(c.cx + 0.6, dy - 0.4, 3.6, 1.2, Ramp(moss), outline: false, rot: tilt)
        cv.line(c.cx + 0.5, dy, c.cx + 1.5, dy - 3, Ramp(metal).outline)
        cv.ellipse(c.cx, c.cy + c.ry * 0.05, c.rx, c.ry * 0.95, Ramp(metal), glossy: true)
    }
}

/// Machine whose chest panel fell open; a flower grew out of it.
func bloomChestBody(_ metal: UInt32, _ petal: UInt32, _ vine: UInt32) -> Draw {
    return { cv, c in
        cv.poly(roundedRect(c.cx, c.cy, c.rx * 1.9, c.ry * 2.0, 3.5), Ramp(metal))
        let px = c.cx, py = c.cy + c.ry * 0.5
        cv.poly(roundedRect(px, py, 6, 4.5, 0.8), Ramp(0x3A3A40), outline: false)
        let open = c.p.acc == 2 ? 1.2 : 0
        for i in 0..<5 {
            let a = Double(i) / 5 * 2 * Double.pi - Double.pi / 2
            cv.ellipse(px + cos(a) * (1.5 + open), py - 0.5 + sin(a) * (1.3 + open), 1.1, 1.1, Ramp(petal), outline: false)
        }
        cv.plot(px, py - 0.5, 0xFFE38A)
        let V = Ramp(vine)
        for t in stride(from: 0.0, through: 9, by: 1) { cv.plot(c.cx - c.rx + 0.5 + sin(t * 0.7) * 0.8, c.cy - c.ry * 0.8 + t * 1.6, V.base) }
        cv.ellipse(c.cx - c.rx + 1.2, c.cy - c.ry * 0.2, 1.2, 0.7, V, outline: false, rot: -0.5)
    }
}

/// Sleepy armoured machine curled up like a pill bug, with moss patches.
func shellBotBody(_ metal: UInt32, _ moss: UInt32) -> Draw {
    return { cv, c in
        let M = Ramp(metal)
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.25, rx: c.rx, ry: c.ry)], M, clipMaxY: c.cy + c.ry * 0.95)
        for k in [-0.55, -0.15, 0.25] {
            lineInside(&cv, c.cx + k * c.rx * 2, c.cy - c.ry * 0.6, c.cx + k * c.rx * 2 + 1, c.cy + c.ry * 0.95, M.shade, onto: tones(M))
        }
        cv.ellipse(c.cx - c.rx * 0.55, c.cy - c.ry * 0.45, 2.0, 1.2, Ramp(moss), outline: false)
        cv.ellipse(c.cx + c.rx * 0.5, c.cy - c.ry * 0.6, 1.6, 1.0, Ramp(moss), outline: false)
    }
}

/// Tiny machine that flies with a two-blade rotor on its head.
func rotorBody(_ metal: UInt32, _ blade: UInt32) -> Draw {
    return { cv, c in
        let mastTop = c.cy - c.ry - 3
        cv.line(c.cx, c.cy - c.ry * 0.8, c.cx, mastTop, Ramp(metal).outline)
        let spin = c.p.flying ? (c.p.wing > 0 ? 1.0 : 0.35) : 1.0
        cv.ellipse(c.cx - 3.5 * spin, mastTop, 3.2 * spin + 0.6, 0.9, Ramp(blade), rot: -0.08)
        cv.ellipse(c.cx + 3.5 * spin, mastTop, 3.2 * spin + 0.6, 0.9, Ramp(blade), rot: 0.08)
        cv.ellipse(c.cx, mastTop, 1.0, 1.0, Ramp(metal))
        cv.poly(roundedRect(c.cx, c.cy + 0.5, c.rx * 1.9, c.ry * 1.8, 4.0), Ramp(metal))
    }
}

/// Round visor machine on springy reverse-knee legs.
func walkerBody(_ metal: UInt32, _ leg: UInt32) -> Draw {
    return { cv, c in
        let L = Ramp(leg)
        let by = c.cy - 4.5
        let hipY = by + c.ry * 0.6
        for (side, s) in [(-1.0, 1.0), (1.0, -1.0)] {
            let step: Double = { if case .step(let v) = c.p.legs { return v * s * 1.5 }; return 0 }()
            let hip = (c.cx + side * c.rx * 0.45, hipY)
            let knee = (hip.0 - 2.5 + step, (hipY + c.bottom) / 2)
            let foot = (hip.0 + step * 0.6, c.bottom)
            cv.line(hip.0, hip.1, knee.0, knee.1, L.base); cv.line(hip.0 + 1, hip.1, knee.0 + 1, knee.1, L.shade)
            cv.line(knee.0, knee.1, foot.0, foot.1, L.base); cv.line(knee.0 + 1, knee.1, foot.0 + 1, foot.1, L.shade)
            cv.ellipse(foot.0 + 0.8, foot.1 + 0.3, 2.0, 0.9, L)
        }
        cv.ellipse(c.cx, by, c.rx, c.ry * 0.9, Ramp(metal), glossy: true)
    }
}

// Stones and motes.

func skipStoneBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        cv.ellipse(c.cx, c.cy + c.ry * 0.3, c.rx, c.ry * 0.7, R, glossy: true)
        for k in [-0.15, 0.25] { lineInside(&cv, c.cx - c.rx * 0.8, c.cy + c.ry * (0.3 + k), c.cx + c.rx * 0.8, c.cy + c.ry * (0.15 + k), R.light, onto: [R.base, R.shade]) }
    }
}

func seaglassBody(_ col: UInt32) -> Draw {
    return { cv, c in
        let R = Ramp(col)
        let pts: [(Double, Double)] = [(c.cx - c.rx * 0.6, c.cy - c.ry * 0.95), (c.cx + c.rx * 0.5, c.cy - c.ry * 1.0), (c.cx + c.rx, c.cy - c.ry * 0.1),
                                       (c.cx + c.rx * 0.7, c.cy + c.ry), (c.cx - c.rx * 0.65, c.cy + c.ry * 0.95), (c.cx - c.rx, c.cy + c.ry * 0.05)]
        var es: [Ell] = []
        for (x, y) in pts { es.append(Ell(cx: c.cx + (x - c.cx) * 0.78, cy: c.cy + (y - c.cy) * 0.78, rx: 2.4, ry: 2.4)) }
        es.append(Ell(cx: c.cx, cy: c.cy, rx: c.rx * 0.85, ry: c.ry * 0.85))
        cv.blob(es, R, glossy: true)
        cv.plot(c.cx - c.rx * 0.45, c.cy - c.ry * 0.55, R.spec); cv.plot(c.cx - c.rx * 0.35, c.cy - c.ry * 0.65, R.spec)
    }
}

func amberBody(_ col: UInt32, _ leaf: UInt32) -> Draw {
    return { cv, c in
        cv.blob([Ell(cx: c.cx, cy: c.cy + c.ry * 0.2, rx: c.rx, ry: c.ry * 0.8)]
                + curve((c.cx, c.cy - c.ry * 0.2), (c.cx + 0.3, c.cy - c.ry * 0.8), (c.cx + 0.8 + c.p.tilt, c.cy - c.ry * 1.25), r0: c.rx * 0.6, r1: 0.5, steps: 8),
                Ramp(col), glossy: true)
        let L = Ramp(leaf)
        cv.ellipse(c.cx - c.rx * 0.3, c.cy + c.ry * 0.55, 1.6, 0.8, L, outline: false, rot: -0.6)
        cv.plot(c.cx - c.rx * 0.3 + 1.4, c.cy + c.ry * 0.55 + 1, L.shade)
    }
}
