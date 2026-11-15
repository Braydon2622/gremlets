// Gremlets Version One: the nine guardians approved for the Series 1 vinyl blind box (2026-11-11),
// redrawn as 32 px Gremlets. Each body draws the whole figure (legs, limbs, moss); the shared renderer adds the face.

import Foundation

private let MOSS: UInt32 = 0x7CC46A
private let LEAF: UInt32 = 0x6FAF4A
private let WOOD: UInt32 = 0x7A5232

private func stepOf(_ c: Ctx) -> Double { if case .step(let v) = c.p.legs { return v }; return 0 }

private func pebble(_ cv: inout Canvas, _ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ col: UInt32) {
    cv.ellipse(x, y, rx, ry, Ramp(col))
}

/// A moss blanket: a dome over `w` that ends in a scalloped edge with hanging drips.
private func moss(_ cv: inout Canvas, _ cx: Double, top: Double, w: Double, h: Double, drips: [(Double, Int)]) {
    let M = Ramp(MOSS)
    let base = top + h
    cv.blob([Ell(cx: cx, cy: base, rx: w / 2, ry: h)], M, clipMaxY: base + 0.6)
    for (dx, len) in drips {
        let x = cx + dx
        for k in 0..<len { cv.plot(x, base + Double(k), k == len - 1 ? M.shade : M.base) }
        cv.plot(x + 1, base + 1, M.outline)
    }
    for k in stride(from: cx - w / 2 + 2, to: cx + w / 2 - 1.5, by: 3.2) { cv.plot(k, base - h * 0.5, M.light) }
}

private func flower(_ cv: inout Canvas, _ x: Double, _ y: Double, _ col: UInt32) {
    let F = Ramp(col)
    cv.plot(x, y, 0xFFD24D); cv.plot(x - 1, y, F.base); cv.plot(x + 1, y, F.base); cv.plot(x, y - 1, F.light); cv.plot(x, y + 1, F.shade)
}

private func mushroom(_ cv: inout Canvas, _ x: Double, _ y: Double, _ cap: UInt32, size: Double = 1.6) {
    cv.plot(x, y, 0xF3E8D2); cv.plot(x, y - 1, 0xF3E8D2)
    cv.blob([Ell(cx: x + 0.5, cy: y - 1.2, rx: size, ry: size * 0.75)], Ramp(cap), clipMaxY: y - 1.0)
    cv.plot(x, y - 2, 0xFFFFFF)
}

private func bird(_ cv: inout Canvas, _ x: Double, _ y: Double) {
    let B = Ramp(0xB8BEC6)
    cv.ellipse(x, y, 2.0, 1.4, B)
    cv.ellipse(x - 1.4, y - 1.5, 1.2, 1.1, B)
    cv.plot(x - 3, y - 1.5, 0xE9A43A); cv.plot(x - 1.6, y - 1.9, 0x1E2024)
}

private func glowDot(_ cv: inout Canvas, _ x: Double, _ y: Double, _ col: UInt32) {
    cv.plot(x, y, col); cv.plot(x + 1, y, Ramp(col).shade); cv.plot(x, y + 1, Ramp(col).shade); cv.plot(x + 1, y + 1, Ramp(col).light)
}

private func thickLine(_ cv: inout Canvas, _ a: (Double, Double), _ b: (Double, Double), _ col: UInt32) {
    let R = Ramp(col)
    cv.line(a.0, a.1, b.0, b.1, R.base); cv.line(a.0 + 1, a.1, b.0 + 1, b.1, R.shade)
}

// MARK: - Bodies

/// 1. Gatekeeper, Nest Cradler: warm sandstone keeper, mossy mane, bonsai on its back, nest held in its hands.
func nestKeeperBody(_ stone: UInt32) -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.2
        pebble(&cv, x - 4.5 + st, B - 1.8, 3.0, 2.2, stone); pebble(&cv, x + 4.5 - st, B - 1.8, 3.0, 2.2, stone)
        // bonsai behind the mane
        thickLine(&cv, (x + 3, B - 17), (x + 4 + c.p.tilt * 0.3, B - 22), WOOD)
        cv.ellipse(x + 4.5 + c.p.tilt * 0.3, B - 23.5, 3.2, 1.4, Ramp(LEAF))
        cv.ellipse(x + 1.8 + c.p.tilt * 0.3, B - 21.2, 2.1, 1.1, Ramp(LEAF))
        cv.ellipse(x, B - 10, 9.5, 7.2, Ramp(stone))
        moss(&cv, x, top: B - 19.5, w: 19, h: 4, drips: [(-8, 3), (-5.5, 2), (-2, 4), (2, 2), (5, 3), (7.5, 2)])
        // hands cradling a nest with eggs and a little bird
        pebble(&cv, x - 4.2, B - 5.5, 2.3, 2.0, stone); pebble(&cv, x + 4.2, B - 5.5, 2.3, 2.0, stone)
        cv.ellipse(x, B - 5.6, 3.4, 1.6, Ramp(0x8A5A32))
        cv.plot(x - 1, B - 7, 0xBFE3F2); cv.plot(x + 1, B - 7, 0xBFE3F2)
        cv.plot(x + 2, B - 8, 0xB8BEC6); cv.plot(x + 3, B - 8, 0xB8BEC6); cv.plot(x + 2, B - 9, 0xB8BEC6); cv.plot(x + 1, B - 9, 0xE9A43A)
    }
}

/// 2. Boulder Golem: dark slate, broad mossy shoulders, long stone arms with fists on the ground, bird on a shoulder.
func boulderGolemBody(_ slate: UInt32) -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.0, sw = c.p.tilt * 0.3
        for s in [-1.0, 1.0] {
            pebble(&cv, x + s * 3.5 + s * st, B - 1.8, 2.7, 2.0, slate)
            pebble(&cv, x + s * 3.5, B - 5.0, 2.4, 2.1, slate)
        }
        for s in [-1.0, 1.0] {
            pebble(&cv, x + s * 10 + sw, B - 2.6, 2.8, 2.4, slate)
            pebble(&cv, x + s * 10.2 + sw, B - 7.0, 2.2, 2.2, slate)
            pebble(&cv, x + s * 9.8 + sw, B - 11.2, 2.3, 2.2, slate)
        }
        cv.ellipse(x, B - 12, 7.5, 6.5, Ramp(slate))
        for s in [-1.0, 1.0] { pebble(&cv, x + s * 7.5, B - 16, 3.1, 2.7, slate) }
        cv.ellipse(x, B - 15.5, 3.6, 2.8, Ramp(slate))
        moss(&cv, x, top: B - 21.5, w: 13, h: 2.6, drips: [(-5, 2), (-1.5, 3), (2.5, 2), (5, 3)])
        for s in [-1.0, 1.0] { moss(&cv, x + s * 7.5, top: B - 20, w: 5.5, h: 1.4, drips: [(0, 1)]) }
        for (dx, dy) in [(-4.0, -9.0), (3.0, -8.0), (5.0, -12.0), (-6.0, -12.5)] { cv.plot(x + dx, B + dy, 0xD9A43A) }
        bird(&cv, x + 8.5, B - 20.8)
        flower(&cv, x - 7.5, B - 21, 0xFF9EC4)
    }
}

/// 3. Cairnwalker, Lookout: a tall cairn of four coloured stones, pebble arms and legs, a bird on top.
func lookoutCairnBody() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.2, sw = c.p.tilt * 0.25
        for s in [-1.0, 1.0] {
            pebble(&cv, x + s * 2.6 + s * st, B - 1.8, 2.2, 1.9, 0x8A8478)
            pebble(&cv, x + s * 2.6, B - 4.6, 2.0, 1.8, 0x8A8478)
        }
        cv.ellipse(x, B - 8.6, 7.2, 2.8, Ramp(0x7A8290))
        for s in [-1.0, 1.0] {
            pebble(&cv, x + s * 8.8, B - 8.2, 1.6, 1.5, 0x8A8478)
            pebble(&cv, x + s * 9.4, B - 5.6, 1.4, 1.4, 0x8A8478)
        }
        cv.ellipse(x + 0.5 + sw, B - 13, 5.6, 2.5, Ramp(0xE3CFA6))
        cv.ellipse(x - 0.4 + sw * 2, B - 17.2, 4.6, 2.2, Ramp(0xC98A62))
        cv.ellipse(x + 0.3 + sw * 3, B - 20.6, 3.4, 1.9, Ramp(0xA9A498))
        moss(&cv, x + 0.3 + sw * 3, top: B - 23.4, w: 7, h: 1.6, drips: [(-2, 1), (1.5, 2)])
        cv.plot(x - 5, B - 11, Ramp(MOSS).base); cv.plot(x - 4, B - 11, Ramp(MOSS).light); cv.plot(x + 3, B - 15.3, Ramp(MOSS).base)
        bird(&cv, x + 1 + sw * 3, B - 25.6)
    }
}

/// 4. Obelisk: an old waymarker stone on pebble legs, ivy spiralling up to a flower.
func obeliskBody(_ stone: UInt32) -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.1
        for s in [-1.0, 1.0] { pebble(&cv, x + s * 2.6 + s * st, B - 1.6, 2.1, 1.7, 0x9A9488) }
        cv.poly([(x - 4.2, B - 3), (x - 3.6, B - 24), (x + 0.2, B - 28.5), (x + 3.9, B - 24), (x + 4.5, B - 3)], Ramp(stone))
        lineInside(&cv, x - 3.6, B - 24, x + 3.9, B - 24, Ramp(stone).shade, onto: tones(Ramp(stone)))
        let V = Ramp(LEAF)
        for t in stride(from: 0.0, through: 22, by: 0.5) {
            let px = x + sin(t * 0.55) * 3.8, py = B - 4 - t
            if let col = cv.get(Int(px), Int(py)), tones(Ramp(stone)).contains(col) || col == Ramp(stone).outline { cv.plot(px, py, cos(t * 0.55) > 0 ? V.base : V.shade) }
            if Int(t * 2) % 7 == 0 { cv.plot(px + (cos(t * 0.55) > 0 ? 1 : -1), py, V.light) }
        }
        for s in [-1.0, 1.0] {
            pebble(&cv, x + s * 6.3, B - 13.5, 1.6, 1.5, 0x9A9488)
            pebble(&cv, x + s * 6.8, B - 10.8, 1.4, 1.4, 0x9A9488)
        }
        flower(&cv, x + 0.2, B - 29.5, 0xFF9EC4)
    }
}

/// 5. Canopywalker: a rust dome with a riveted band on four brass legs, moss hanging off the rim, mushrooms on top.
func canopyWalkerBody() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.3
        let brass: UInt32 = 0xC9963A
        for s in [-1.0, 1.0] {
            thickLine(&cv, (x + s * 4, B - 13), (x + s * 5.5 - s * st * 0.5, B - 1.5), 0x9A7230)
            cv.ellipse(x + s * 5.5 - s * st * 0.5, B - 1, 1.7, 1.0, Ramp(MOSS))
        }
        for s in [-1.0, 1.0] {
            thickLine(&cv, (x + s * 7, B - 13), (x + s * 8.5, B - 8), brass)
            thickLine(&cv, (x + s * 8.5, B - 8), (x + s * 9 + s * st, B - 1.5), brass)
            cv.plot(x + s * 8.5, B - 8, 0x3A3A3A)
            cv.ellipse(x + s * 9 + s * st, B - 1, 1.9, 1.0, Ramp(MOSS))
        }
        cv.ellipse(x, B - 13.6, 8.5, 2.0, Ramp(0x3A3436))
        cv.blob([Ell(cx: x, cy: B - 16.5, rx: 11.2, ry: 4.6)], Ramp(0xB4593A), clipMaxY: B - 13.2)
        cv.line(x - 11, B - 13.8, x + 11, B - 13.8, 0x4A4A4E)
        for k in stride(from: x - 9.0, through: x + 9, by: 3) { cv.plot(k, B - 13.8, 0xE8C070) }
        cv.plot(x - 6, B - 16, 0x58776B); cv.plot(x - 5, B - 16, 0x58776B); cv.plot(x + 5, B - 15.5, 0x58776B)
        moss(&cv, x, top: B - 23, w: 21, h: 3.2, drips: [(-10, 4), (-8, 6), (-5.5, 2), (-3, 3), (3.5, 2), (6, 5), (8.5, 2), (10, 6)])
        mushroom(&cv, x - 4, B - 23.5, 0xE2553F, size: 1.8); mushroom(&cv, x - 1.5, B - 23.2, 0xE2553F, size: 1.2)
        flower(&cv, x + 3.5, B - 24, 0xFFFFFF)
        for (dx, dy) in [(-3.0, -8.0), (4.0, -10.0), (1.0, -6.0)] { cv.plot(x + dx, B + dy, 0xFFE08A) }
    }
}

/// 6. Antlerstrider: a small ochre machine high on three slim birch legs, moss cap and mossy antlers.
func antlerStriderBody() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.4
        let birch = Ramp(0xE6DED0)
        func leg(_ hip: (Double, Double), _ knee: (Double, Double), _ foot: (Double, Double), _ R: Ramp) {
            cv.line(hip.0, hip.1, knee.0, knee.1, R.base); cv.line(knee.0, knee.1, foot.0, foot.1, R.base)
            cv.line(hip.0 + 1, hip.1, knee.0 + 1, knee.1, R.shade); cv.line(knee.0 + 1, knee.1, foot.0 + 1, foot.1, R.shade)
            cv.plot(knee.0, knee.1, 0x3A3A3A); cv.plot(foot.0, foot.1, 0x3A3A3A); cv.plot(foot.0 + 1, foot.1, 0x3A3A3A)
            cv.plot((hip.0 + knee.0) / 2, (hip.1 + knee.1) / 2, 0x5A544C); cv.plot((knee.0 + foot.0) / 2 + 0.5, (knee.1 + foot.1) / 2 + 2, 0x5A544C)
        }
        leg((x, B - 16), (x + 1, B - 9), (x + 0.5 - st * 0.6, B - 0.8), Ramp(0xBDB4A4))
        leg((x - 2, B - 16), (x - 6, B - 10), (x - 7 + st, B - 0.8), birch)
        leg((x + 2, B - 16), (x + 6, B - 10), (x + 6 - st, B - 0.8), birch)
        cv.ellipse(x, B - 19, 4.6, 4.0, Ramp(0xC88A3A), glossy: true)
        cv.line(x - 4, B - 17, x + 4, B - 17, 0x4A4A4E)
        let W = Ramp(WOOD), tilt = c.p.tilt * 0.4
        for s in [-1.0, 1.0] {
            cv.line(x + s * 2 + tilt, B - 24, x + s * 5 + tilt, B - 28.5, W.base)
            cv.line(x + s * 5 + tilt, B - 28.5, x + s * 7.5 + tilt, B - 29.5, W.base)
            cv.line(x + s * 4 + tilt, B - 27, x + s * 3.6 + tilt, B - 30.5, W.base)
            cv.plot(x + s * 7.5 + tilt, B - 30.5, Ramp(LEAF).light); cv.plot(x + s * 3.6 + tilt, B - 31, Ramp(LEAF).base)
            cv.plot(x + s * 4.4 + tilt, B - 27.6, Ramp(MOSS).base)
        }
        moss(&cv, x, top: B - 25, w: 9, h: 2.0, drips: [(-3, 2), (0, 3), (3, 1)])
    }
}

/// 7. Totemstack: three carved blocks, each with its own face; pebble legs, moss and a flower on top.
func totemStackBody() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.2, sw = c.p.tilt * 0.25
        for s in [-1.0, 1.0] { pebble(&cv, x + s * 2.6 + s * st, B - 1.7, 2.2, 1.8, 0x8A8478) }
        cv.poly(roundedRect(x, B - 6.2, 11, 6, 1.5), Ramp(0xC27A55))
        for dx in [-3.0, -2.0, 2.0, 3.0] { cv.plot(x + dx, B - 6.5, 0x2A1E18) }
        for dx in [-3.0, 3.0] { cv.plot(x + dx, B - 5.5, 0x2A1E18) }
        cv.poly(roundedRect(x + 0.3 + sw, B - 12.4, 9.6, 6, 1.5), Ramp(0xE3CFA6))
        for s in [-1.0, 1.0] { cv.poly(roundedRect(x + s * 6.2 + sw, B - 12.4, 2.4, 2.2, 0.6), Ramp(0xE3CFA6)) }
        cv.line(x - 1 + sw, B - 10.4, x + 1 + sw, B - 10.4, 0x2A1E18)
        cv.poly(roundedRect(x - 0.2 + sw * 2, B - 18.4, 10.6, 5.6, 1.5), Ramp(0x8A93A0))
        cv.ellipse(x + sw * 2, B - 18.6, 1.6, 1.6, Ramp(0xE0478C), glossy: true)
        cv.plot(x - 1 + sw * 2, B - 19.6, 0xFFFFFF)
        moss(&cv, x + sw * 2, top: B - 22.6, w: 10, h: 1.5, drips: [(-4, 2), (2, 2)])
        flower(&cv, x + 2 + sw * 2, B - 23.6, 0xFFFFFF)
    }
}

/// 8. Bonsaiback: a low sandstone boulder carrying a proper bonsai and a tiny stone lantern.
func bonsaiBackBody(_ stone: UInt32) -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c)
        for (i, dx) in [-6.0, -2.2, 2.2, 6.0].enumerated() { pebble(&cv, x + dx + (i % 2 == 0 ? st : -st), B - 1.3, 2.0, 1.4, stone) }
        let sway = c.p.tilt * 0.35
        let W = Ramp(WOOD)
        let trunk = [(x - 1, B - 11.5), (x + 1.2 + sway * 0.4, B - 15.5), (x - 0.8 + sway * 0.7, B - 19), (x + 1 + sway, B - 22.5)]
        for (a, b) in zip(trunk, trunk.dropFirst()) {
            cv.line(a.0, a.1, b.0, b.1, W.base); cv.line(a.0 + 1, a.1, b.0 + 1, b.1, W.shade); cv.line(a.0 - 1, a.1, b.0 - 1, b.1, W.outline)
        }
        cv.line(x - 1, B - 18.5, x - 4 + sway, B - 18, W.base); cv.line(x + 1, B - 15, x + 4 + sway, B - 15.5, W.base)
        let G = Ramp(LEAF)
        cv.ellipse(x + 1.5 + sway, B - 24.2, 4.6, 2.0, G)
        cv.ellipse(x + 5 + sway, B - 16.4, 2.6, 1.3, G)
        cv.ellipse(x - 4.5 + sway, B - 18.8, 3.2, 1.5, G)
        cv.ellipse(x + 4.2 + sway, B - 20.6, 2.4, 1.2, G)
        cv.ellipse(x, B - 6, 9.6, 4.8, Ramp(stone))
        moss(&cv, x, top: B - 12, w: 16, h: 1.8, drips: [(-7, 2), (-3, 1), (2, 2), (6, 2)])
        cv.plot(x - 3, B - 11.4, W.base); cv.plot(x + 1, B - 11.4, W.base)
        let S = Ramp(0xB8B2A6)
        cv.plot(x + 7, B - 13, S.base); cv.plot(x + 8, B - 13, S.base); cv.plot(x + 7, B - 12, S.shade); cv.plot(x + 8, B - 12, S.shade)
        cv.plot(x + 7, B - 14, 0xFFE08A); cv.plot(x + 8, B - 14, S.light)
        cv.plot(x + 6, B - 15, S.base); cv.plot(x + 7, B - 15, S.base); cv.plot(x + 8, B - 15, S.base); cv.plot(x + 9, B - 15, S.base)
    }
}

/// 9. Cairnling: a short cairn with chunky feet, little pebble hands and a tilted slate hat with glowing mushrooms.
func cairnlingBody() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.2
        for s in [-1.0, 1.0] { pebble(&cv, x + s * 2.8 + s * st, B - 1.3, 2.6, 1.5, 0x6E6A62) }
        cv.ellipse(x, B - 5, 5.9, 3.2, Ramp(0xDCC096))
        cv.ellipse(x, B - 10.4, 4.9, 3.2, Ramp(0xA9A498))
        for s in [-1.0, 1.0] { pebble(&cv, x + s * 6.3, B - 7.6, 1.4, 1.3, 0xA9A498) }
        let tilt = c.p.tilt * 0.3
        cv.ellipse(x + 0.5 + tilt, B - 15.2, 8.6, 1.9, Ramp(0x6C7584), rot: -0.07)
        moss(&cv, x + 0.5 + tilt, top: B - 18.6, w: 15, h: 1.7, drips: [(-6, 2), (-2.5, 3), (2.5, 2), (6, 3)])
        let G = Ramp(0x9AF0B0)
        for (dx, dy) in [(2.0, -19.5), (3.5, -19.0)] {
            cv.plot(x + dx + tilt, B + dy + 1, 0xF3E8D2)
            cv.plot(x + dx + tilt, B + dy, G.base); cv.plot(x + dx - 1 + tilt, B + dy, G.light)
        }
        cv.plot(x - 3 + tilt, B - 19.5, Ramp(LEAF).shade); cv.plot(x - 4 + tilt, B - 20.5, Ramp(LEAF).base); cv.plot(x - 2 + tilt, B - 20.5, Ramp(LEAF).base)
    }
}

// MARK: - Roster

let versionOne: [Species] = [
    species("nestkeeper", "Nestkeeper", "sandstone", "versionone", main: 0xD9A46A, "A gentle sandstone keeper with a mossy mane. It carries a bird's nest in its hands, and a bonsai grows on its back.") {
        $0.rx = 9.5; $0.ry = 7.5; $0.eye = 0x2A1E18; $0.eyeStyle = .dot; $0.faceV = -0.45; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = nestKeeperBody(0xD9A46A)
        $0.special = "leaves"; $0.walkSpeed = 35; $0.jumpPower = 0.75; $0.sleepiness = 1.3
    },
    species("bouldergolem", "Boulder Golem", "slate", "versionone", main: 0x6A707A, "A heavy golem of dark slate with mossy shoulders and fists that rest on the ground. A bird lives on its shoulder.") {
        $0.rx = 8; $0.ry = 8; $0.eye = 0xD9447A; $0.eyeStyle = .cyclops; $0.faceV = -0.95; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = boulderGolemBody(0x6A707A)
        $0.special = "stomp"; $0.walkSpeed = 30; $0.jumpPower = 0.7
    },
    species("lookoutcairn", "Lookout", "cairn", "versionone", main: 0xE3CFA6, "A tall cairn of four coloured stones that keeps watch from the hilltop. A bird rests on its top stone.") {
        $0.rx = 7; $0.ry = 9; $0.eye = 0x2AB88A; $0.eyeStyle = .cyclops; $0.faceV = -0.45; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = lookoutCairnBody()
        $0.special = "sparkle"; $0.walkSpeed = 40; $0.jumpPower = 0.85
    },
    species("obelisk", "Obelisk", "waymarker", "versionone", main: 0xD6D0C4, "An old waymarker stone that grew pebble legs. Ivy spirals up to the flower on its peak.") {
        $0.rx = 4; $0.ry = 12; $0.eye = 0x2A2620; $0.eyeStyle = .dot; $0.faceV = -0.75; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = obeliskBody(0xD6D0C4)
        $0.special = "leaves"; $0.walkSpeed = 35; $0.jumpPower = 0.8
    },
    species("canopywalker", "Canopywalker", "rust", "versionone", main: 0xB4593A, "A rust-red dome on four brass legs. Moss hangs off its rim like curtains, fireflies glow underneath, and mushrooms grow on its roof.") {
        $0.rx = 11; $0.ry = 9; $0.eye = 0xD9447A; $0.eyeStyle = .cyclops; $0.faceV = -0.8; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = canopyWalkerBody()
        $0.special = "glow"; $0.walkSpeed = 40; $0.jumpPower = 0.9
    },
    species("antlerstrider", "Antlerstrider", "birch", "versionone", main: 0xC88A3A, "A small ochre machine high on three slim birch legs, with a moss cap and big mossy antlers.") {
        $0.rx = 4.5; $0.ry = 13; $0.eye = 0xD9447A; $0.eyeStyle = .cyclops; $0.faceV = -0.46; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = antlerStriderBody()
        $0.special = "leaves"; $0.walkSpeed = 70; $0.jumpPower = 1.3
    },
    species("totemstack", "Totemstack", "carved", "versionone", main: 0xE3CFA6, "Three carved blocks stacked into a walking totem, each block with a face of its own.") {
        $0.rx = 5.5; $0.ry = 10; $0.eye = 0x1A3A2A; $0.eyeStyle = .glow(0x7FE3C3); $0.faceV = -0.3; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = totemStackBody()
        $0.special = "sparkle"; $0.walkSpeed = 40
    },
    species("bonsaiback", "Bonsaiback", "garden", "versionone", main: 0xDCC096, "A low sandstone boulder that carries a whole bonsai tree on its back, plus a tiny stone lantern for night walks.") {
        $0.rx = 9.5; $0.ry = 5; $0.eye = 0x2A1E18; $0.eyeStyle = .dot; $0.faceV = -0.2; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = bonsaiBackBody(0xDCC096)
        $0.special = "leaves"; $0.walkSpeed = 30; $0.jumpPower = 0.7; $0.sleepiness = 1.4
    },
    species("cairnling", "Cairnling", "slate", "versionone", main: 0xA9A498, "A short cairn in a tilted slate hat, with moss on the brim and glowing mushrooms on top.") {
        $0.rx = 6; $0.ry = 8; $0.eye = 0x2A2620; $0.eyeStyle = .normal; $0.faceV = -0.3; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = cairnlingBody()
        $0.special = "glow"; $0.walkSpeed = 50; $0.jumpPower = 1.0
    },
]
