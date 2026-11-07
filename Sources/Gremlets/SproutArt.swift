import CoreGraphics
import GremletsCore

/// Little things growing in the moss (see Sprouts.swift): 9 × 11 px, drawn at artScale, the base on row 0.
enum SproutArt {
    private static let stem: UInt32 = 0x5E9E46, leaf: UInt32 = 0x8BD66A, dark: UInt32 = 0x3F7A34

    private static var cache: [String: CGImage] = [:]

    static func image(_ kind: MossSprout.Kind, stage: Int, night: Bool) -> CGImage {
        let key = "\(kind.rawValue)\(stage)\(night)"
        if let i = cache[key] { return i }
        var cv = PixelCanvas(9, 11)
        if stage == 0 {
            // A shoot, whatever it'll be.
            cv.set(4, 0, stem); cv.set(4, 1, stem); cv.set(3, 2, leaf); cv.set(5, 2, leaf); cv.set(4, 2, stem)
        } else {
            draw(kind, ripe: stage == 2, on: &cv)
        }
        let white = cv.px.indices.filter { cv.px[$0] == 0xFFFFFF }
        cv.outline(0.66)
        for i in white { cv.px[i] = 0xFFFFFF }
        if night { cv.px = cv.px.map { $0.map { c in c == 0xFFFFFF ? 0xD8DCE8 : SproutArt.dimmed(c) } } }
        let img = cv.image
        cache[key] = img
        return img
    }

    /// Held overhead after picking (the ripe one, a little smaller).
    static func carried(_ kind: MossSprout.Kind) -> CGImage { image(kind, stage: 2, night: false) }

    private static func draw(_ kind: MossSprout.Kind, ripe: Bool, on cv: inout PixelCanvas) {
        switch kind {
        case .daisy:
            for y in 0...5 { cv.set(4, y, stem) }
            cv.set(3, 2, leaf); cv.set(2, 3, leaf); cv.set(5, 3, leaf); cv.set(6, 4, leaf)
            if ripe {
                for (x, y) in [(4, 9), (4, 6), (2, 8), (6, 8), (3, 9), (5, 9), (3, 7), (5, 7), (2, 7), (6, 7)] { cv.set(x, y, 0xFFFFFF) }
                cv.set(3, 8, 0xF2C94C); cv.set(4, 8, 0xF5B82E); cv.set(5, 8, 0xF2C94C); cv.set(4, 7, 0xE0A030)
            } else {
                cv.set(4, 6, leaf); cv.set(4, 7, 0xF2E6B0); cv.set(3, 6, stem); cv.set(5, 6, stem)
            }
        case .mushroom:
            let cap: UInt32 = 0xD9534F, capLight: UInt32 = 0xEE7A6A, stalk: UInt32 = 0xF2E6D0
            if ripe {
                cv.rect(3, 0, 3, 3, stalk); cv.set(5, 1, 0xD8C8AE)
                cv.rect(1, 3, 7, 2, cap); cv.rect(2, 5, 5, 1, cap); cv.rect(3, 6, 3, 1, capLight)
                cv.set(2, 4, 0xFFFFFF); cv.set(5, 5, 0xFFFFFF); cv.set(6, 3, 0xFFFFFF)
                cv.set(0, 0, leaf); cv.set(7, 0, leaf); cv.set(8, 1, leaf)
            } else {
                cv.rect(4, 0, 1, 2, stalk); cv.rect(3, 2, 3, 1, cap); cv.set(4, 3, capLight)
                cv.set(2, 0, leaf); cv.set(6, 0, leaf)
            }
        case .berries:
            for y in 0...4 { cv.set(4, y, stem) }
            cv.set(3, 5, stem); cv.set(5, 5, stem); cv.set(2, 6, stem); cv.set(6, 6, stem)
            cv.set(1, 6, leaf); cv.set(2, 7, leaf); cv.set(7, 6, leaf); cv.set(6, 7, leaf); cv.set(4, 5, leaf); cv.set(4, 6, leaf)
            let b: UInt32 = ripe ? 0x6A4FC8 : 0x9CCB6A, bl: UInt32 = ripe ? 0x9A84E8 : 0xC4E39A
            for (x, y) in [(2, 3), (6, 3), (3, 2), (5, 4)] { cv.set(x, y, b) }
            cv.set(2, 4, bl); cv.set(6, 4, bl)
            if ripe { cv.set(3, 3, 0xD9534F); cv.set(5, 2, 0xD9534F) }
        case .dandelion:
            for y in 0...6 { cv.set(4, y, stem) }
            cv.set(3, 1, leaf); cv.set(2, 1, leaf); cv.set(5, 2, leaf); cv.set(6, 1, leaf); cv.set(1, 0, dark); cv.set(7, 0, dark)
            if ripe {
                // The seed clock.
                for (x, y) in [(4, 10), (2, 9), (6, 9), (1, 8), (7, 8), (2, 7), (6, 7), (4, 6), (3, 10), (5, 10), (1, 7), (7, 7)] { cv.set(x, y, 0xFFFFFF) }
                for (x, y) in [(3, 8), (4, 8), (5, 8), (3, 9), (5, 9), (4, 9), (3, 7), (5, 7), (4, 7)] { cv.set(x, y, 0xE8E4DA) }
                cv.set(4, 8, 0xC9C2B0)
            } else {
                cv.rect(3, 7, 3, 2, 0xF5C431); cv.set(4, 9, 0xF5D75A); cv.set(2, 8, 0xF5C431); cv.set(6, 8, 0xF5C431)
            }
        }
    }

    static func dimmed(_ c: UInt32) -> UInt32 {
        let r = Double((c >> 16) & 0xFF) * 0.72, g = Double((c >> 8) & 0xFF) * 0.74, b = Double(c & 0xFF) * 0.85
        return (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }

    /// One drifting dandelion seed.
    static let seed: CGImage = {
        var cv = PixelCanvas(3, 4)
        cv.set(1, 0, 0x9C8F78); cv.set(1, 1, 0xD9D2C5); cv.set(0, 2, 0xFFFFFF); cv.set(1, 3, 0xFFFFFF); cv.set(2, 2, 0xFFFFFF); cv.set(1, 2, 0xF4F0E8)
        return cv.image
    }()
}

/// Claude's mood over its Gremlet: a thought cloud while it thinks (the dots fill in one by one).
enum MoodArt {
    private static var cache: [Int: CGImage] = [:]

    /// `dots` 0...3 lit.
    static func thought(dots: Int) -> CGImage {
        if let i = cache[dots] { return i }
        var cv = PixelCanvas(17, 12)
        let white: UInt32 = 0xFFFFFF, soft: UInt32 = 0xE6EAF2
        // The cloud: three puffs.
        cv.blob(6, 7.5, 4.2, 3.2, base: white, light: white, shade: soft)
        cv.blob(11, 7.8, 4.4, 3.4, base: white, light: white, shade: soft)
        cv.blob(8.5, 9.2, 3.6, 2.4, base: white, light: white, shade: soft)
        // Two little bubbles trailing down to its head.
        cv.blob(3.2, 2.6, 1.3, 1.2, base: white, light: white, shade: soft)
        cv.set(1, 0, white)
        for k in 0..<3 { cv.set(5 + k * 3, 7, k < dots ? 0x6E7891 : 0xC9CFDC); cv.set(6 + k * 3, 7, k < dots ? 0x6E7891 : 0xC9CFDC) }
        let keep = cv.px.indices.filter { cv.px[$0] == white }
        cv.outline(0.7)
        for i in keep { cv.px[i] = white }
        let img = cv.image
        cache[dots] = img
        return img
    }
}
