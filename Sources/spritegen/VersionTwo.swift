// Gremlets Version Two: the nine Series 1 guardians redrawn from the final polished vinyl designs (2026-11-12).
// Each body draws the whole figure; the shared renderer adds the main face (placed with rx/ry/faceV).

import Foundation

private let MOSS: UInt32 = 0x86C25A
private let LEAF: UInt32 = 0x6FAF4A
private let WOOD: UInt32 = 0x8A5E3A
private let BRASS: UInt32 = 0xC9A24A
private let IRON: UInt32 = 0x4A4E54
private let MINT: UInt32 = 0x8FE3C8

private func stepOf(_ c: Ctx) -> Double { if case .step(let v) = c.p.legs { return v }; return 0 }
private func peb(_ cv: inout Canvas, _ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ col: UInt32) { cv.ellipse(x, y, rx, ry, Ramp(col)) }

/// Moss blanket: dome over `w` ending in a scalloped edge with hanging drips.
private func moss(_ cv: inout Canvas, _ cx: Double, top: Double, w: Double, h: Double, drips: [(Double, Int)]) {
    let M = Ramp(MOSS), base = top + h
    cv.blob([Ell(cx: cx, cy: base, rx: w / 2, ry: h)], M, clipMaxY: base + 0.6)
    for (dx, len) in drips {
        let x = cx + dx
        for k in 0..<len { cv.plot(x, base + Double(k), k == len - 1 ? M.shade : M.base) }
        cv.plot(x + 1, base + 1, M.outline)
    }
    for k in stride(from: cx - w / 2 + 2, to: cx + w / 2 - 1.5, by: 2.7) { cv.plot(k, base - h * 0.55, M.light) }
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

/// A round little songbird (red cardinal or blue), facing `dir` (-1 left, 1 right).
private func songbird(_ cv: inout Canvas, _ x: Double, _ y: Double, _ col: UInt32, dir: Double = -1) {
    let B = Ramp(col)
    cv.ellipse(x, y, 2.1, 1.6, B)
    cv.ellipse(x + dir * 1.3, y - 1.5, 1.3, 1.2, B)
    cv.plot(x + dir * 2.8, y - 1.4, 0xF2A23A)
    cv.plot(x + dir * 1.6, y - 1.8, 0x1E2024)
    cv.plot(x - dir * 2.3, y - 0.5, B.shade); cv.plot(x - dir * 2.9, y - 1.0, B.shade)
}

private func thick(_ cv: inout Canvas, _ a: (Double, Double), _ b: (Double, Double), _ col: UInt32) {
    let R = Ramp(col)
    cv.line(a.0, a.1, b.0, b.1, R.base); cv.line(a.0 + 1, a.1, b.0 + 1, b.1, R.shade)
}

// MARK: - Bodies

/// 1. Nestkeeper: an old beige robot, round and rust-freckled with a brass band, a mossy dome on its back,
/// a bonsai with a red bird on top, and a red bird cupped in its hands.
func nestKeeperV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.1, sw = c.p.tilt * 0.3
        let beige: UInt32 = 0xD8C4A2, rust: UInt32 = 0xB9774A
        for s in [-1.0, 1.0] {
            peb(&cv, x + s * 4.2 + s * st, B - 1.6, 3.0, 1.8, beige)
            for k in 0..<3 { cv.plot(x + s * 4.2 + s * st - 1.5 + Double(k) * 1.5, B - 0.5, Ramp(beige).shade) }
        }
        // bonsai with a bird, growing from the moss
        thick(&cv, (x - 1 + sw, B - 19), (x + 1 + sw, B - 24), WOOD)
        cv.ellipse(x + 2.5 + sw, B - 25.2, 3.6, 1.5, Ramp(LEAF)); cv.ellipse(x - 2.5 + sw, B - 22.6, 2.6, 1.2, Ramp(LEAF))
        songbird(&cv, x + 4.5 + sw, B - 27.4, 0xE2513F, dir: 1)
        cv.ellipse(x, B - 10, 10, 7.4, Ramp(beige))
        cv.line(x - 9.4, B - 12, x + 9.4, B - 12, Ramp(rust).shade)
        for k in stride(from: x - 8.0, through: x + 8, by: 2.6) { cv.plot(k, B - 12, BRASS) }
        for (dx, dy) in [(-6.0, -6.0), (-3.0, -4.5), (6.0, -7.0), (4.0, -5.0)] { cv.plot(x + dx, B + dy, rust) }
        moss(&cv, x, top: B - 20, w: 18, h: 4, drips: [(-8, 4), (-6, 2), (-3.5, 3), (6.5, 3), (8, 5)])
        // little square head on the front, antenna
        cv.poly(roundedRect(x + 0.5, B - 13.4, 7.4, 5.4, 1.2), Ramp(0xE2D2B4))
        cv.line(x + 2.5, B - 16, x + 2.5, B - 18, IRON); cv.plot(x + 2.5, B - 19, BRASS)
        // arms forward, cupping a red bird
        for s in [-1.0, 1.0] { thick(&cv, (x + s * 8.5, B - 9.5), (x + s * 3.2, B - 5.4), beige); cv.plot(x + s * 5.5, B - 7.3, BRASS) }
        peb(&cv, x, B - 4.6, 3.3, 1.5, 0xE8DCC6)
        songbird(&cv, x - 0.3, B - 6.4, 0xE2513F, dir: -1)
    }
}

/// 2. Boulder Golem: grey boulders, moss melting over the shoulders, a ringed neon-purple eye,
/// multicoloured pebbles set in its chest, toed stone feet and a blue bird on its shoulder.
func boulderGolemV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.0, sw = c.p.tilt * 0.3
        let slate: UInt32 = 0x8E9198
        for s in [-1.0, 1.0] {
            peb(&cv, x + s * 3.6 + s * st, B - 1.6, 3.0, 1.8, slate)
            for k in 0..<3 { cv.plot(x + s * 3.6 + s * st - 1.4 + Double(k) * 1.4, B - 0.4, Ramp(slate).shade) }
            peb(&cv, x + s * 3.6, B - 5.0, 2.4, 2.1, slate)
        }
        for s in [-1.0, 1.0] {
            peb(&cv, x + s * 10.2 + sw, B - 3.0, 3.0, 2.6, slate)
            peb(&cv, x + s * 10.4 + sw, B - 7.6, 2.4, 2.3, slate)
            peb(&cv, x + s * 10.0 + sw, B - 11.8, 2.5, 2.3, slate)
        }
        cv.ellipse(x, B - 12, 7.8, 6.8, Ramp(slate))
        for s in [-1.0, 1.0] { peb(&cv, x + s * 7.6, B - 16.4, 3.2, 2.8, slate) }
        for (dx, dy, col) in [(-4.0, -10.0, 0xD9C3A0 as UInt32), (3.5, -9.0, 0x9DB0C4), (-1.0, -7.5, 0xE0A98A), (5.0, -12.0, 0xC9C2B4), (-5.0, -13.0, 0x9DB0C4), (1.5, -11.5, 0xD9C3A0)] {
            cv.plot(x + dx, B + dy, col); cv.plot(x + dx + 1, B + dy, Ramp(col).shade)
        }
        moss(&cv, x, top: B - 22, w: 14, h: 2.8, drips: [(-5.5, 3), (-2, 5), (1.5, 2), (4.5, 4)])
        for s in [-1.0, 1.0] { moss(&cv, x + s * 7.8, top: B - 20.6, w: 6, h: 1.5, drips: [(s * 1.5, 2)]) }
        // eye socket ring (renderer draws the purple cyclops eye inside)
        cv.ellipse(x, B - 15.8, 3.3, 3.0, Ramp(0x3E4248))
        mushroom(&cv, x - 3.5, B - 22.5, 0xE8C9A8, size: 1.3)
        cv.line(x - 6.5, B - 22.5, x - 6.5, B - 25, 0x6FAF4A); cv.plot(x - 6.5, B - 26, 0xE8C9A8)
        songbird(&cv, x + 8.6, B - 21.6, 0x5C8FD6, dir: -1)
    }
}

/// 3. Lookout: a cairn on a wide slate (stacked-stone arms with two stone fingers hang beneath it),
/// a cream face stone, a peach stone, a mossy cap stone and a squirrel on top.
func lookoutV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.1, sw = c.p.tilt * 0.25
        let grey: UInt32 = 0xA7A49C
        for s in [-1.0, 1.0] {
            peb(&cv, x + s * 2.6 + s * st, B - 1.3, 2.6, 1.4, grey)
            peb(&cv, x + s * 2.4, B - 3.8, 1.8, 1.4, grey)
        }
        cv.ellipse(x, B - 7.2, 8.2, 2.6, Ramp(0x7E8794))
        cv.plot(x - 4, B - 8, 0xB6C98E); cv.plot(x + 3, B - 7, 0xB6C98E); cv.plot(x + 5, B - 8, 0xC9D8A8)
        for s in [-1.0, 1.0] {
            peb(&cv, x + s * 8.2, B - 5.0, 1.5, 1.2, grey); peb(&cv, x + s * 8.5, B - 2.9, 1.4, 1.1, grey)
            cv.plot(x + s * 8.0, B - 1.4, Ramp(grey).base); cv.plot(x + s * 9.0, B - 1.4, Ramp(grey).base)
            cv.plot(x + s * 8.0, B - 0.6, Ramp(grey).shade); cv.plot(x + s * 9.0, B - 0.6, Ramp(grey).shade)
        }
        cv.ellipse(x + sw, B - 12.4, 5.8, 3.0, Ramp(0xF0E2C2))
        cv.ellipse(x - 0.3 + sw * 2, B - 17.2, 4.6, 2.2, Ramp(0xE8A27A))
        cv.plot(x + 2 + sw * 2, B - 18, Ramp(MOSS).base); cv.plot(x + 3 + sw * 2, B - 17, Ramp(MOSS).base)
        cv.ellipse(x + sw * 3, B - 20.6, 3.4, 1.7, Ramp(0xBDB9B0))
        moss(&cv, x + sw * 3, top: B - 23.4, w: 7, h: 1.3, drips: [(-2.5, 2), (2, 1)])
        // squirrel: body, head, ear and a big curled tail
        let S = Ramp(0xE08A3C), sx = x + sw * 3
        cv.ellipse(sx + 3, B - 27.5, 1.8, 3.0, S); cv.plot(sx + 4, B - 30.5, S.light)
        cv.ellipse(sx - 0.4, B - 25.6, 1.8, 1.6, S)
        cv.ellipse(sx - 0.8, B - 28.0, 1.4, 1.3, S); cv.plot(sx - 1.2, B - 29.6, S.shade)
        cv.plot(sx - 1.6, B - 28.2, 0x1E2024); cv.plot(sx - 0.2, B - 25.4, 0xF3E3C8)
    }
}

/// 4. Obelisk: a tapered pale stone with a pyramid tip, carved glyphs, little mini-obelisk arms with mint bands,
/// an ivy vine spiralling to the tip, floating on two stone orbs with mint rings.
func obeliskV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, bob = (stepOf(c) != 0 ? 0.5 : 0)
        let stone: UInt32 = 0xD2CABB
        for s in [-1.0, 1.0] {
            cv.ellipse(x + s * 2.4, B - 2.0 - bob, 1.9, 1.9, Ramp(0xB7B0A4))
            cv.line(x + s * 2.4 - 1.6, B - 2.0 - bob, x + s * 2.4 + 1.6, B - 2.0 - bob, MINT)
        }
        cv.poly([(x - 4.4, B - 5), (x - 3.4, B - 24), (x + 0.2, B - 29), (x + 3.8, B - 24), (x + 4.8, B - 5)], Ramp(stone))
        lineInside(&cv, x - 3.4, B - 24, x + 3.8, B - 24, Ramp(stone).shade, onto: tones(Ramp(stone)))
        let G: UInt32 = 0x9FB8C0
        cv.plot(x, B - 17, G); cv.plot(x - 1, B - 16.5, G); cv.plot(x + 1, B - 16.5, G)          // eye glyph
        cv.plot(x - 1, B - 14, G); cv.plot(x + 1, B - 14, G)                                      // dots
        cv.plot(x, B - 12, G); cv.plot(x - 1, B - 11, G); cv.plot(x + 1, B - 11, G)              // triangle
        cv.plot(x - 1, B - 9, G); cv.plot(x, B - 8.5, G); cv.plot(x + 1, B - 9, G)               // wave
        cv.plot(x, B - 6.5, 0xE8C070)                                                             // sun
        let V = Ramp(LEAF)
        for t in stride(from: 0.0, through: 23, by: 0.5) {
            let px = x + sin(t * 0.55 + 1.2) * 4.2, py = B - 5 - t
            if let col = cv.get(Int(px), Int(py)), tones(Ramp(stone)).contains(col) || col == Ramp(stone).outline { cv.plot(px, py, cos(t * 0.55 + 1.2) > 0 ? V.base : V.shade) }
            if Int(t * 2) % 5 == 0 { cv.plot(px + (cos(t * 0.55 + 1.2) > 0 ? 1 : -1), py, V.light) }
        }
        for s in [-1.0, 1.0] {
            cv.poly([(x + s * 6.2 - 1.1, B - 9), (x + s * 6.2 - 1.0, B - 15.5), (x + s * 6.2, B - 17), (x + s * 6.2 + 1.0, B - 15.5), (x + s * 6.2 + 1.1, B - 9)], Ramp(stone))
            cv.line(x + s * 6.2 - 0.5, B - 11, x + s * 6.2 + 0.5, B - 11, MINT)
        }
        flower(&cv, x + 0.2, B - 30, 0xFF9EC4)
    }
}

/// 5. Canopywalker: a copper-red steampunk dome with a riveted band, gauge and patch plate, a ringed pink eye,
/// thick moss curtains, red and white mushrooms on the roof, a glowing antenna and four brass legs.
func canopyWalkerV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.3
        for s in [-1.0, 1.0] {
            thick(&cv, (x + s * 3.6, B - 13), (x + s * 4.6 - s * st * 0.5, B - 2), 0xB08A3A)
            cv.plot(x + s * 4.0, B - 8, IRON); cv.plot(x + s * 4.0 + 1, B - 8, IRON)
            cv.line(x + s * 4.6 - s * st * 0.5 - 1, B - 1, x + s * 4.6 - s * st * 0.5 + 2, B - 1, 0x2E3034)
        }
        for s in [-1.0, 1.0] {
            thick(&cv, (x + s * 7.5, B - 13), (x + s * 9.2, B - 8), BRASS)
            thick(&cv, (x + s * 9.2, B - 8), (x + s * 9.4 + s * st, B - 2), BRASS)
            cv.ellipse(x + s * 9.2, B - 8, 1.2, 1.2, Ramp(IRON))
            cv.line(x + s * 9.4 + s * st - 1, B - 1, x + s * 9.4 + s * st + 2, B - 1, 0x2E3034)
        }
        cv.ellipse(x, B - 13.4, 8.6, 1.8, Ramp(0x3A3436))
        cv.blob([Ell(cx: x, cy: B - 16.4, rx: 11.4, ry: 4.4)], Ramp(0xB65A3A), clipMaxY: B - 13.0)
        cv.line(x - 11, B - 13.6, x + 11, B - 13.6, IRON)
        for k in stride(from: x - 9.0, through: x + 9, by: 2.2) { cv.plot(k, B - 13.6, 0xE8C070) }
        cv.poly(roundedRect(x - 6.5, B - 15.6, 3.6, 2.2, 0.4), Ramp(0x6A6E74))
        cv.ellipse(x + 6.8, B - 15.6, 1.3, 1.2, Ramp(0xF2EEE4)); cv.plot(x + 6.8, B - 15.6, 0xD24A3A)
        cv.ellipse(x, B - 15.8, 2.8, 2.6, Ramp(IRON))
        moss(&cv, x, top: B - 23.2, w: 22, h: 3.4, drips: [(-10.5, 5), (-8.5, 7), (-6, 3), (-3.5, 2), (4.5, 3), (7, 6), (9, 2), (10.5, 6)])
        mushroom(&cv, x - 3.2, B - 23.8, 0xE2553F, size: 2.0); mushroom(&cv, x - 6.2, B - 23.4, 0xF2EEE4, size: 1.2)
        mushroom(&cv, x + 4.5, B - 23.4, 0xE2553F, size: 1.0)
        cv.plot(x + 1, B - 24.5, LEAF); cv.plot(x + 2, B - 25.5, Ramp(LEAF).light); cv.plot(x + 0, B - 25.5, LEAF)
        cv.line(x - 9, B - 20, x - 10, B - 26, IRON); cv.plot(x - 10, B - 27, 0xFFF2B0); cv.plot(x - 11, B - 27, 0xFFE08A)
    }
}

/// 6. Antlerstrider: a small copper pod with a brass band and pink eye under a moss cap, tall copper antlers
/// with green patina and brass tips, high on four thin brass legs with iron knees.
func antlerStriderV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.4
        let brass = Ramp(0xC9A24A)
        func leg(_ hip: (Double, Double), _ knee: (Double, Double), _ foot: (Double, Double)) {
            cv.line(hip.0, hip.1, knee.0, knee.1, brass.base); cv.line(hip.0, hip.1 + 1, knee.0, knee.1 + 1, brass.shade)
            cv.line(knee.0, knee.1, foot.0, foot.1, brass.base)
            cv.line(knee.0 + 1, knee.1, foot.0 + 1, foot.1, brass.shade)
            cv.plot(knee.0, knee.1, IRON); cv.plot(knee.0 + 1, knee.1, IRON)
            cv.plot(foot.0 - 1, foot.1, 0x2E3034); cv.plot(foot.0, foot.1, 0x2E3034); cv.plot(foot.0 + 1, foot.1, 0x2E3034)
        }
        leg((x - 3, B - 14), (x - 7, B - 11), (x - 7 + st, B - 0.8))
        leg((x + 3, B - 14), (x + 7, B - 11), (x + 7 - st, B - 0.8))
        leg((x - 1, B - 13.5), (x - 3, B - 9.5), (x - 3 - st * 0.5, B - 0.8))
        leg((x + 1, B - 13.5), (x + 3, B - 9.5), (x + 3 + st * 0.5, B - 0.8))
        cv.ellipse(x, B - 17.5, 4.8, 4.2, Ramp(0xC97A45), glossy: true)
        cv.ellipse(x, B - 14.4, 3.4, 1.4, Ramp(0x4E5258))
        cv.line(x - 4.6, B - 16.6, x + 4.6, B - 16.6, BRASS)
        let tilt = c.p.tilt * 0.4, CU = Ramp(0xD08A5A), PAT: UInt32 = 0x6FB8A0
        for s in [-1.0, 1.0] {
            thick(&cv, (x + s * 2 + tilt, B - 22), (x + s * 5 + tilt, B - 28.5), 0xD08A5A)
            cv.line(x + s * 3.6 + tilt, B - 25, x + s * 7 + tilt, B - 26.5, CU.base)
            cv.line(x + s * 4.4 + tilt, B - 27, x + s * 3.4 + tilt, B - 30.5, CU.base)
            cv.plot(x + s * 3 + tilt, B - 24, PAT); cv.plot(x + s * 4.6 + tilt, B - 27.4, PAT)
            for (tx, ty) in [(5.0, -29.0), (7.5, -27.0), (3.4, -31.0)] { cv.plot(x + s * tx + tilt, B + ty, 0xE8C070) }
            cv.plot(x + s * 2.6 + tilt, B - 23, Ramp(MOSS).base)
        }
        moss(&cv, x, top: B - 23.5, w: 9.5, h: 2.2, drips: [(-3.5, 3), (-1, 2), (2, 3), (4, 1)])
    }
}

/// 7. Totemstack: three boxy blocks (grey stone with dot eyes and a brow, cream with glowing eyes, terracotta
/// with slots), broad painted wings with coral and teal stripes, moss and a tiny white flower on top.
func totemStackV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.2, sw = c.p.tilt * 0.25
        for s in [-1.0, 1.0] {
            cv.line(x + s * 2.5 + s * st * 0.5, B - 5, x + s * 2.5 + s * st * 0.5, B - 2.5, 0x9A6A44)
            cv.line(x + s * 2.5 + s * st * 0.5 + 1, B - 5, x + s * 2.5 + s * st * 0.5 + 1, B - 2.5, 0x7A5234)
            cv.poly(roundedRect(x + s * 2.8 + s * st, B - 1.3, 4.2, 2.2, 0.6), Ramp(0xA8A6A0))
        }
        cv.poly(roundedRect(x, B - 8.0, 11, 6, 1.2), Ramp(0xC98262))
        for s in [-1.0, 1.0] { cv.plot(x + s * 2, B - 8.2, 0x2A1E18); cv.plot(x + s * 2 + s, B - 8.2, 0x2A1E18) }
        cv.poly(roundedRect(x + 0.3 + sw, B - 14.2, 9.6, 6, 1.2), Ramp(0xEDE2CC))
        for s in [-1.0, 1.0] {
            cv.poly(roundedRect(x + s * 6.0 + sw, B - 13.4, 2.2, 3.0, 0.6), Ramp(0xC9A27A))
            cv.plot(x + s * 2 + sw, B - 15, 0xFFFFFF); cv.plot(x + s * 2 + sw, B - 14, 0xE4F4FF)
        }
        cv.line(x - 1 + sw, B - 12.6, x + 1 + sw, B - 12.6, 0x2A1E18)
        // wings behind the top block
        for s in [-1.0, 1.0] {
            let wx = x + s * 7.5 + sw * 2
            cv.poly([(wx - s * 2, B - 23), (wx + s * 4, B - 25), (wx + s * 4.5, B - 21), (wx - s * 2, B - 18.5)], Ramp(0xC9A27A))
            cv.line(wx + s * 2.5, B - 24.4, wx + s * 3, B - 20, 0xE86A5A)
            cv.line(wx + s * 3.6, B - 24.8, wx + s * 4, B - 20.5, 0x5AB8B0)
        }
        cv.poly(roundedRect(x - 0.2 + sw * 2, B - 20.6, 11, 6.4, 1.4), Ramp(0x9AA0AA))
        cv.line(x - 3.5 + sw * 2, B - 22.4, x + 3.5 + sw * 2, B - 22.4, Ramp(0x9AA0AA).shade)
        for dx in [-4.0, -1.5, 1.0, 3.5] { cv.plot(x + dx + sw * 2, B - 24, Ramp(MOSS).base); cv.plot(x + dx + 1 + sw * 2, B - 24, Ramp(MOSS).light) }
        cv.line(x + 0.5 + sw * 2, B - 24.5, x + 0.5 + sw * 2, B - 27, LEAF)
        cv.plot(x + 0.5 + sw * 2, B - 28, 0xFFD24D); cv.plot(x - 0.5 + sw * 2, B - 28, 0xFFFFFF); cv.plot(x + 1.5 + sw * 2, B - 28, 0xFFFFFF)
    }
}

/// 8. Bonsaiback: a glazed blue bonsai pot that walks on four stubby blue feet, with a cream rim band and brass
/// studs, mossy soil spilling over the edges, a twisting bonsai and a tiny stone lantern.
func bonsaiBackV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c)
        let glaze: UInt32 = 0x6FA8D6
        for (i, dx) in [-7.0, -2.6, 2.6, 7.0].enumerated() {
            peb(&cv, x + dx + (i % 2 == 0 ? st : -st), B - 1.4, 2.0, 1.6, glaze)
            cv.plot(x + dx + (i % 2 == 0 ? st : -st) - 1, B - 0.4, Ramp(glaze).shade); cv.plot(x + dx + (i % 2 == 0 ? st : -st) + 1, B - 0.4, Ramp(glaze).shade)
        }
        let sway = c.p.tilt * 0.35, W = Ramp(0xB08A64)
        let trunk = [(x - 2, B - 12.5), (x + 0.6 + sway * 0.4, B - 16.5), (x - 1.4 + sway * 0.7, B - 20), (x + 0.4 + sway, B - 23.5)]
        for (a, b) in zip(trunk, trunk.dropFirst()) {
            cv.line(a.0, a.1, b.0, b.1, W.base); cv.line(a.0 + 1, a.1, b.0 + 1, b.1, W.shade); cv.line(a.0 - 1, a.1, b.0 - 1, b.1, W.outline)
        }
        let G = Ramp(0x8CCB5A)
        cv.ellipse(x + 0.5 + sway, B - 25.2, 4.8, 2.0, G)
        cv.ellipse(x + 4.8 + sway, B - 20.6, 3.0, 1.3, G)
        cv.ellipse(x - 5.0 + sway, B - 18.4, 3.2, 1.4, G)
        cv.ellipse(x + 3.6 + sway, B - 15.6, 2.4, 1.1, G)
        cv.poly(roundedRect(x, B - 7.4, 20, 9.2, 1.6), Ramp(glaze))
        cv.line(x - 9.6, B - 11.6, x + 9.6, B - 11.6, Ramp(glaze).light)
        cv.line(x - 6, B - 5.2, x + 6, B - 5.2, 0xF0E4C8)
        cv.plot(x - 6.6, B - 5.2, BRASS); cv.plot(x + 6.6, B - 5.2, BRASS)
        moss(&cv, x, top: B - 14.4, w: 21, h: 2.2, drips: [(-10, 4), (-8, 2), (-5.5, 3), (5, 2), (7.5, 4), (9.5, 3)])
        let S = Ramp(0xC8C2B6)
        cv.plot(x + 7, B - 15, S.base); cv.plot(x + 8, B - 15, S.base); cv.plot(x + 7, B - 16, 0xFFE08A); cv.plot(x + 8, B - 16, S.light)
        cv.plot(x + 6, B - 17, S.base); cv.plot(x + 7, B - 17, S.base); cv.plot(x + 8, B - 17, S.base); cv.plot(x + 9, B - 17, S.base); cv.plot(x + 7.5, B - 18, S.shade)
    }
}

/// 9. Cairnling: a wide mossy cap stone dripping moss with a sprout on top, a grey stone head, a cream belly stone
/// with a crack, fern and crystal, pebble arms and a glowing mushroom lantern in its right hand.
func cairnlingV2() -> Draw {
    return { cv, c in
        let B = c.bottom, x = c.cx, st = stepOf(c) * 1.1
        for s in [-1.0, 1.0] { peb(&cv, x + s * 3.0 + s * st, B - 1.3, 2.8, 1.4, 0x9C9890) }
        cv.ellipse(x, B - 5.4, 6.4, 3.6, Ramp(0xE6C9A0))
        cv.line(x + 1, B - 7, x + 0, B - 4, 0x7A6A58); cv.plot(x - 3, B - 5.5, 0xBFE3F2); cv.plot(x - 3, B - 6.5, 0xE4F6FF)
        cv.plot(x + 4, B - 6, LEAF); cv.plot(x + 4, B - 7, Ramp(LEAF).light); cv.plot(x + 5, B - 5, LEAF)
        cv.ellipse(x, B - 11, 5.0, 3.2, Ramp(0xB2AEA6))
        for s in [-1.0, 1.0] { peb(&cv, x + s * 6.6, B - 8.2, 1.5, 1.4, 0xB2AEA6) }
        // glowcap lantern in the right hand
        cv.plot(x + 7.6, B - 9.5, 0xF3E8D2); cv.plot(x + 7.6, B - 10.5, 0xF3E8D2)
        cv.ellipse(x + 7.8, B - 12, 1.6, 1.0, Ramp(0xFFE9A8)); cv.plot(x + 7.4, B - 12.3, 0xFFFFFF)
        let tilt = c.p.tilt * 0.3
        cv.ellipse(x + tilt, B - 15.4, 9.4, 1.9, Ramp(0x8E929A))
        moss(&cv, x + tilt, top: B - 19.6, w: 18, h: 2.6, drips: [(-8.5, 4), (-6.5, 2), (-3, 3), (3, 2), (6.5, 4), (8.5, 3)])
        cv.line(x + tilt, B - 20, x + tilt, B - 21.5, LEAF)
        cv.plot(x - 1 + tilt, B - 22.5, Ramp(LEAF).light); cv.plot(x + 1 + tilt, B - 22.5, LEAF); cv.plot(x + 2 + tilt, B - 23, Ramp(LEAF).light)
    }
}

// MARK: - Roster

let versionTwo: [Species] = [
    species("nestkeeper2", "Nestkeeper", "old robot", "versiontwo", main: 0xD8C4A2, "An old beige robot, rusty at the seams, with a mossy dome on its back and a bonsai on top. One red bird lives in the tree and another rides in its hands.") {
        $0.rx = 6; $0.ry = 8; $0.eye = 0x1E1A16; $0.eyeStyle = .dot; $0.eyeGap = 0.44; $0.faceV = -0.68; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = nestKeeperV2()
        $0.special = "leaves"; $0.walkSpeed = 35; $0.jumpPower = 0.75; $0.sleepiness = 1.3
    },
    species("bouldergolem2", "Boulder Golem", "boulder", "versiontwo", main: 0x8E9198, "A heavy golem of grey boulders with moss melting off its shoulders, coloured pebbles in its chest and one glowing purple eye. A blue bird lives on its shoulder.") {
        $0.rx = 8; $0.ry = 8; $0.eye = 0xB45CFF; $0.eyeStyle = .cyclops; $0.faceV = -0.95; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = boulderGolemV2()
        $0.special = "stomp"; $0.walkSpeed = 30; $0.jumpPower = 0.7
    },
    species("lookout2", "Lookout", "cairn", "versiontwo", main: 0xF0E2C2, "A cairn of coloured stones that keeps watch from the hilltop, its stone arms hanging under a wide slate. A squirrel sits on top as its second pair of eyes.") {
        $0.rx = 6; $0.ry = 9; $0.eye = 0x1E1A16; $0.eyeStyle = .dot; $0.eyeGap = 0.44; $0.faceV = -0.39; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = lookoutV2()
        $0.special = "sparkle"; $0.walkSpeed = 40; $0.jumpPower = 0.85
    },
    species("obelisk2", "Obelisk", "waymarker", "versiontwo", main: 0xD2CABB, "An old waymarker carved with eyes, waves and suns. It floats on two stone orbs while ivy climbs all the way to its tip.") {
        $0.rx = 4; $0.ry = 12; $0.eye = 0x2A2620; $0.eyeStyle = .dot; $0.faceV = -0.62; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = obeliskV2()
        $0.special = "leaves"; $0.walkSpeed = 35; $0.jumpPower = 0.8
    },
    species("canopywalker2", "Canopywalker", "copper", "versiontwo", main: 0xB65A3A, "A copper steampunk dome on four brass legs, with a gauge, patched plates and a glowing antenna. Moss hangs off its rim and mushrooms grow on its roof.") {
        $0.rx = 11; $0.ry = 9; $0.eye = 0xF48AC0; $0.eyeStyle = .cyclops; $0.faceV = -0.75; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = canopyWalkerV2()
        $0.special = "glow"; $0.walkSpeed = 40; $0.jumpPower = 0.9
    },
    species("antlerstrider2", "Antlerstrider", "copper", "versiontwo", main: 0xC97A45, "A little copper pod under a moss cap, with tall patina antlers, striding high on four thin brass legs.") {
        $0.rx = 4.5; $0.ry = 13; $0.eye = 0xF48AC0; $0.eyeStyle = .cyclops; $0.faceV = -0.33; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = antlerStriderV2()
        $0.special = "leaves"; $0.walkSpeed = 70; $0.jumpPower = 1.3
    },
    species("totemstack2", "Totemstack", "carved", "versiontwo", main: 0x9AA0AA, "Three blocks stacked into a walking totem with painted wings. The top block does the looking, the middle one glows, and moss and a little flower grow on its head.") {
        $0.rx = 5.5; $0.ry = 10; $0.eye = 0x1E1A16; $0.eyeStyle = .dot; $0.eyeGap = 0.48; $0.faceV = -1.06; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = totemStackV2()
        $0.special = "sparkle"; $0.walkSpeed = 40
    },
    species("bonsaiback2", "Bonsaiback", "glazed", "versiontwo", main: 0x6FA8D6, "A glazed blue bonsai pot that walks on four stubby feet, with moss spilling over its rim, a twisting bonsai and a tiny stone lantern for night walks.") {
        $0.rx = 9.5; $0.ry = 5; $0.eye = 0x1E1A16; $0.eyeStyle = .normal; $0.faceV = -0.55; $0.feet = .none; $0.noArms = true; $0.cheeks = true
        $0.restMouth = Mouth.none
        $0.bodyDraw = bonsaiBackV2()
        $0.special = "leaves"; $0.walkSpeed = 30; $0.jumpPower = 0.7; $0.sleepiness = 1.4
    },
    species("cairnling2", "Cairnling", "slate", "versiontwo", main: 0xB2AEA6, "Two stacked stones under a wide mossy cap with a sprout on top. It carries a glowing mushroom lantern, and a crystal and a fern grow from its belly.") {
        $0.rx = 6; $0.ry = 8; $0.eye = 0x1E1A16; $0.eyeStyle = .dot; $0.eyeGap = 0.44; $0.faceV = -0.38; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.restMouth = Mouth.none
        $0.bodyDraw = cairnlingV2()
        $0.special = "glow"; $0.walkSpeed = 50; $0.jumpPower = 1.0
    },
]
