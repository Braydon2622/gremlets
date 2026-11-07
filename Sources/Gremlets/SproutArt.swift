import CoreGraphics
import GremletsCore

/// Little things growing in the moss (see Sprouts.swift): 9 × 11 px, drawn at artScale, the base on row 0.
enum SproutArt {
    private static let stem: UInt32 = 0x5E9E46, leaf: UInt32 = 0x8BD66A, dark: UInt32 = 0x3F7A34

    private static var cache: [String: CGImage] = [:]

    static func image(_ kind: MossSprout.Kind, stage: Int, night: Bool, tint: UInt32? = nil) -> CGImage {
        let key = "\(kind.rawValue)\(stage)\(night)\(tint ?? 0)"
        if let i = cache[key] { return i }
        var cv = PixelCanvas(9, 11)
        if stage == 0 {
            // A shoot, whatever it'll be.
            cv.set(4, 0, stem); cv.set(4, 1, stem); cv.set(3, 2, leaf); cv.set(5, 2, leaf); cv.set(4, 2, stem)
        } else {
            draw(kind, ripe: stage == 2, tint: tint ?? 0xFF8FB1, on: &cv)
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

    /// A tiny win flag for the moss (5 × 7 px), in one of five colours.
    static func winFlag(_ tint: Int) -> CGImage {
        let key = "flag\(tint)"
        if let i = cache[key] { return i }
        var cv = PixelCanvas(5, 7)
        let col: UInt32 = [0xE8574A, 0xF5B82E, 0x5FB8FF, 0xB98CFF, 0xFF8FB1][tint % 5]
        cv.vspan(0, 0, 6, 0x6B4428)
        cv.rect(1, 4, 3, 2, col); cv.set(4, 5, col); cv.set(1, 3, PixelCanvas.darken(col, 0.8))
        cv.outline(0.6)
        let img = cv.image
        cache[key] = img
        return img
    }

    /// The rubber duck (6 × 5 px).
    static let duck: CGImage = {
        var cv = PixelCanvas(6, 5)
        let y: UInt32 = 0xFFD94A, d: UInt32 = 0xE8B830
        cv.rect(0, 0, 5, 2, y); cv.hspan(1, 3, 2, y); cv.rect(3, 2, 2, 2, y); cv.set(4, 4, y); cv.set(3, 4, y)
        cv.set(5, 3, 0xF29A2E); cv.set(4, 3, 0x2B2620); cv.hspan(0, 4, 0, d)
        cv.outline(0.6)
        return cv.image
    }()

    /// A checked picnic blanket with a basket (24 × 6 px), and a folded blanket (8 × 3 px).
    static let picnic: CGImage = {
        var cv = PixelCanvas(24, 6)
        for x in 0..<24 { cv.set(x, 0, (x / 2) % 2 == 0 ? 0xE8574A : 0xF6EFDF); cv.set(x, 1, (x / 2) % 2 == 1 ? 0xE8574A : 0xF6EFDF) }
        cv.rect(16, 2, 5, 2, 0xC9A15A); cv.hspan(16, 20, 3, 0xA88445); cv.hspan(17, 19, 5, 0x8A5A35); cv.set(16, 4, 0x8A5A35); cv.set(20, 4, 0x8A5A35)
        cv.set(5, 2, 0xF5B82E); cv.set(6, 2, 0xC0503C); cv.set(9, 2, 0x6CC04A)
        cv.outline(0.6)
        return cv.image
    }()
    static let foldedBlanket: CGImage = {
        var cv = PixelCanvas(8, 3)
        for x in 0..<8 { cv.set(x, 0, 0x7A8BC8); cv.set(x, 1, x % 3 == 0 ? 0xF6EFDF : 0x9AA8E0); cv.set(x, 2, 0x7A8BC8) }
        cv.outline(0.6)
        return cv.image
    }()

    private static func draw(_ kind: MossSprout.Kind, ripe: Bool, tint: UInt32, on cv: inout PixelCanvas) {
        switch kind {
        case .friendBloom:
            // A tall star flower in the friend's colour, with a white heart.
            for y in 0...6 { cv.set(4, y, stem) }
            cv.set(3, 2, leaf); cv.set(2, 3, leaf); cv.set(5, 4, leaf); cv.set(6, 5, leaf)
            if ripe {
                for (x, y) in [(4, 10), (2, 9), (6, 9), (3, 7), (5, 7), (1, 8), (7, 8), (4, 9), (3, 8), (5, 8)] { cv.set(x, y, tint) }
                cv.set(4, 8, 0xFFFFFF)
            } else {
                cv.rect(3, 7, 3, 2, tint); cv.set(4, 9, tint)
            }
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

/// Little things a Gremlet holds up while Claude works (and other small companions' bits).
enum ToolPropArt {
    private static var cache: [String: CGImage] = [:]

    static func image(_ name: String) -> CGImage? {
        if let c = cache[name] { return c }
        var cv: PixelCanvas
        switch name {
        case "book":
            cv = PixelCanvas(7, 5)
            cv.rect(0, 0, 3, 5, 0xC0503C); cv.rect(4, 0, 3, 5, 0xC0503C)
            cv.rect(1, 1, 2, 4, 0xF6EFDF); cv.rect(4, 1, 2, 4, 0xF6EFDF); cv.vspan(3, 0, 4, 0x8A2E22)
            cv.hspan(1, 2, 3, 0xB8AA8C); cv.hspan(4, 5, 3, 0xB8AA8C); cv.hspan(1, 2, 2, 0xB8AA8C)
        case "magnifier":
            cv = PixelCanvas(6, 6)
            cv.blob(3.5, 3.6, 2.2, 2.2, base: 0x9FD8F0, light: 0xDFF4FF); cv.set(1, 1, 0x8A5A35); cv.set(0, 0, 0x6B4428)
            for (x, y) in [(2, 5), (3, 5), (4, 5), (5, 4), (5, 3), (5, 2), (1, 4), (1, 3), (2, 2)] { if cv.get(x, y) == nil { cv.set(x, y, 0xB8B6AE) } }
        case "telescope":
            cv = PixelCanvas(8, 5)
            for x in 0..<7 { cv.set(x, 1 + x / 3, x < 3 ? 0xB07A44 : 0xD9A066); cv.set(x, 2 + x / 3, x < 3 ? 0x8A5A35 : 0xB07A44) }
            cv.set(7, 3, 0x9FD8F0); cv.set(7, 4, 0x9FD8F0); cv.set(2, 0, 0x6B4428)
        case "trowel":
            cv = PixelCanvas(4, 8)
            cv.rect(1, 0, 2, 3, 0x8A5A35); cv.set(1, 3, 0x6B4428); cv.set(2, 3, 0x6B4428)
            cv.rect(0, 4, 4, 3, 0xB8C2CC); cv.rect(1, 7, 2, 1, 0xB8C2CC); cv.set(1, 5, 0xE4ECF2)
        case "clover":
            cv = PixelCanvas(5, 6)
            cv.vspan(2, 0, 2, 0x4F9A3E)
            for (x, y) in [(1, 3), (3, 3), (1, 5), (3, 5)] { cv.set(x, y, 0x6CC04A); cv.set(x + (x < 2 ? -1 : 1), y, 0x8BD66A) }
            cv.set(2, 4, 0x4F9A3E)
        case "list":
            cv = PixelCanvas(5, 7)
            cv.rect(0, 0, 5, 7, 0xF6EFDF); cv.hspan(0, 4, 6, 0xC9A15A); cv.hspan(0, 4, 0, 0xC9A15A)
            for y in [4, 2] { cv.set(1, y, 0x6CC04A); cv.hspan(2, 3, y, 0x8A7458) }
        case "lantern":
            return PropArt.lantern
        default:
            return nil
        }
        cv.outline(0.6)
        let img = cv.image
        cache[name] = img
        return img
    }

    /// A seedling helper (one per subagent), two hopping frames, holding a leaf on the way back if `leaf`.
    static func seedling(frame: Int, leaf: Bool) -> CGImage {
        let key = "seed\(frame)\(leaf)"
        if let c = cache[key] { return c }
        var cv = PixelCanvas(7, 9)
        let body: UInt32 = 0x8BD66A, shade: UInt32 = 0x5E9E46
        let lift = frame == 1 ? 1 : 0
        cv.blob(3, 2.6 + Double(lift), 2.4, 2.2, base: body, light: 0xB0E37A, shade: shade)
        cv.set(2, 3 + lift, 0x2B2620); cv.set(4, 3 + lift, 0x2B2620)
        cv.set(3, 5 + lift, shade); cv.set(2, 6 + lift, 0x7CCF56); cv.set(4, 6 + lift, 0x7CCF56); cv.set(1, 6 + lift, 0x7CCF56)
        if frame == 0 { cv.set(1, 0, shade); cv.set(5, 0, shade) } else { cv.set(2, 0, shade); cv.set(4, 0, shade) }
        if leaf { cv.set(5, 6 + lift, 0x4F9A3E); cv.set(6, 7 + lift, 0x6CC04A); cv.set(5, 7 + lift, 0x6CC04A); cv.set(6, 8 + lift > 8 ? 8 : 8, 0x8BD66A) }
        cv.outline(0.6)
        let img = cv.image
        cache[key] = img
        return img
    }

    /// A flower crown for an anniversary (9 × 3 px).
    static let crown: CGImage = {
        var cv = PixelCanvas(9, 3)
        for x in 0..<9 { cv.set(x, 0, x % 2 == 0 ? 0x5E9E46 : 0x6CC04A) }
        for (x, c) in [(0, 0xFF8FB1), (2, 0xFFE45C), (4, 0xFFFFFF), (6, 0xB98CFF), (8, 0xFF8FB1)] as [(Int, UInt32)] { cv.set(x, 1, c); cv.set(x, 2, c) }
        cv.set(4, 1, 0xFFE45C)
        let white = cv.px.indices.filter { cv.px[$0] == 0xFFFFFF }
        cv.outline(0.6)
        for i in white { cv.px[i] = 0xFFFFFF }
        return cv.image
    }()
}
