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
