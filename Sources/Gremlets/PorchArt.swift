import AppKit
import GremletsCore

/// Pixel art for Porch.swift: the vegetable bed in front of the nest hut, the mailbox under the porch, the lanterns
/// on the moss, the picked vegetables, and the postcards card.
enum PorchArt {
    private static var cache: [String: CGImage] = [:]

    private static let leaf: UInt32 = 0x5E9E46, leafLight: UInt32 = 0x8BD66A, leafDark: UInt32 = 0x3E7A34
    private static let wilted: UInt32 = 0xB5A04A, wiltedDark: UInt32 = 0x8A7A3A

    /// The bed (11 × 8 px): a twig-edged strip of soil with three plots (their middles at x 2, 5 and 8). Dark soil when
    /// it's wet, pale when it's dry; the plants droop and yellow when they're thirsty.
    static func bed(_ plots: [PatchPlot]) -> CGImage {
        let key = "bed" + plots.map { p in "\(p.crop?.rawValue ?? "-")\(stage(p))\(p.dry ? "d" : "")\(p.water > 0.5 ? "w" : "")" }.joined()
        if let c = cache[key] { return c }
        var cv = PixelCanvas(11, 8)
        let wet = plots.contains { $0.crop != nil && $0.water > 0.5 }
        for x in 0..<11 { cv.set(x, 0, x % 3 == 1 ? 0x553620 : 0x6B4428) }
        for x in 0..<11 { cv.set(x, 1, wet ? (x % 2 == 0 ? 0x3A2614 : 0x4A3020) : (x % 2 == 0 ? 0x7A5A3A : 0x8A6A48)) }
        cv.set(0, 1, 0x6B4428); cv.set(10, 1, 0x6B4428)
        for (i, p) in plots.prefix(3).enumerated() { plant(&cv, cx: 2 + i * 3, p) }
        cv.outline(0.7)
        let img = cv.image
        cache[key] = img
        return img
    }

    private static func stage(_ p: PatchPlot) -> Int { p.crop == nil ? -1 : p.ripe ? 3 : p.growth < 0.3 ? 1 : 2 }

    private static func plant(_ cv: inout PixelCanvas, cx: Int, _ p: PatchPlot) {
        guard let crop = p.crop else { cv.set(cx, 1, 0x2A1A10); return }   // a little furrow, waiting for seeds
        let l = p.dry ? wilted : leafLight, d = p.dry ? wiltedDark : leaf
        let droop = p.dry ? 1 : 0
        switch stage(p) {
        case 1:
            cv.set(cx, 2, d); cv.set(cx - 1, 3 - droop, l); cv.set(cx + 1, 3 - droop, l)
        case 2:
            switch crop {
            case .carrot:
                cv.vspan(cx, 2, 4 - droop, d); cv.set(cx - 1, 4 - droop, l); cv.set(cx + 1, 5 - droop, l); cv.set(cx, 5 - droop, l)
            case .radish:
                cv.set(cx, 2, d); cv.set(cx - 1, 3, l); cv.set(cx + 1, 3, l); cv.set(cx - 1, 4 - droop, d); cv.set(cx + 1, 4 - droop, l)
            case .peas, .tomato:
                cv.vspan(cx + 1, 2, 6, 0x8A5A35)   // a little stick to climb
                cv.vspan(cx, 2, 5 - droop, d); cv.set(cx - 1, 4 - droop, l)
            case .strawberry:
                cv.set(cx - 1, 2, d); cv.set(cx, 2, l); cv.set(cx + 1, 2, d); cv.set(cx, 3 - droop, l); cv.set(cx - 1, 3 - droop, l)
            case .pumpkin:
                cv.hspan(cx - 1, cx + 1, 2, d); cv.set(cx - 1, 3 - droop, l); cv.set(cx + 1, 3 - droop, l); cv.set(cx, 4 - droop, l)
            }
        default:
            switch crop {
            case .carrot:
                cv.set(cx, 1, 0xF28A2E); cv.set(cx, 2, 0xF2A04A)
                cv.vspan(cx, 3, 5, leaf); cv.set(cx - 1, 5, leafLight); cv.set(cx + 1, 6, leafLight); cv.set(cx, 6, leafLight); cv.set(cx - 1, 7, leafLight)
            case .radish:
                cv.set(cx - 1, 2, 0xD9443A); cv.set(cx, 2, 0xE8574A); cv.set(cx + 1, 2, 0xC0303A); cv.set(cx, 1, 0xF2E6D0)
                cv.set(cx, 3, leaf); cv.set(cx - 1, 4, leafLight); cv.set(cx + 1, 4, leafLight); cv.set(cx - 1, 5, leaf); cv.set(cx + 1, 5, leafLight)
            case .peas:
                cv.vspan(cx + 1, 2, 7, 0x8A5A35)
                cv.vspan(cx, 2, 6, leaf); cv.set(cx - 1, 3, 0x9BDB6E); cv.set(cx - 1, 4, 0x9BDB6E); cv.set(cx - 1, 6, 0xFFFFFF); cv.set(cx, 7, leafLight)
            case .tomato:
                cv.vspan(cx + 1, 2, 7, 0x8A5A35)
                cv.vspan(cx, 2, 6, leaf); cv.set(cx - 1, 5, leafLight); cv.set(cx, 7, leafLight)
                cv.set(cx - 1, 3, 0xE0453A); cv.set(cx - 1, 4, 0xF06A50); cv.set(cx, 4, 0xC0303A)
            case .strawberry:
                cv.set(cx - 1, 2, leaf); cv.set(cx, 3, leafLight); cv.set(cx + 1, 2, leaf); cv.set(cx - 1, 3, leafLight)
                cv.set(cx + 1, 3, 0xE0453A); cv.set(cx + 1, 4, 0xF06A6A); cv.set(cx, 2, 0xD9343A)
            case .pumpkin:
                cv.hspan(cx - 1, cx + 1, 2, 0xE8862E); cv.hspan(cx - 1, cx + 1, 3, 0xF2A04A); cv.set(cx, 3, 0xD9741E)
                cv.set(cx, 4, 0x6B4428); cv.set(cx + 1, 4, leafLight); cv.set(cx - 1, 4, leaf)
            }
        }
    }

    /// A picked vegetable, held up on the way to the pantry.
    static func crop(_ what: String) -> CGImage? {
        let key = "crop" + what
        if let c = cache[key] { return c }
        if what == "broom" {
            let img = PropArt.image(PropArt.grid(["..s", "..s", ".s.", ".s.", "yyy", "yYy", "y.y"], ["s": 0x8A5A35, "y": 0xD9B45A, "Y": 0xB8923E]))
            cache[key] = img
            return img
        }
        guard let crop = PatchPlot.Crop(rawValue: what) else { return nil }
        let rows: [String]
        switch crop {
        case .carrot: rows = [".l.l", "..l.", ".oo.", ".oO.", "..o.", "..o."]
        case .radish: rows = [".l.l", "..l.", ".rr.", "rrRr", ".rr.", "..w."]
        case .peas: rows = ["...s", ".pps", "pPPp", ".pp."]
        case .strawberry: rows = [".ll.", "rrrr", "rRrr", ".rr.", "..r."]
        case .pumpkin: rows = ["..s.", ".ooo.", "oOoOo", "oOoOo", ".ooo."]
        case .tomato: rows = [".ll.", "rrrr", "rRrr", "rrrr", ".rr."]
        }
        let img = PropArt.image(PropArt.grid(rows, ["l": leafLight, "o": 0xF28A2E, "O": 0xF2B060, "r": 0xD9443A, "R": 0xF07A6A, "w": 0xF2E6D0, "p": 0x6CC04A, "P": 0xB5F27A, "s": 0x3E7A34]))
        cache[key] = img
        return img
    }

    /// The beehive (5 × 7 px): a little straw skep hanging from its loop.
    static let hive: CGImage = PropArt.image(PropArt.grid([
        "..s..",
        ".yyy.",
        "yYyYy",
        "yyyyy",
        "YyYyY",
        "yykyy",
        ".yyy.",
    ], ["s": 0x6B4428, "y": 0xE0B45A, "Y": 0xB8923E, "k": 0x3A2614]))

    /// The firefly jar (5 × 6 px): glass with a cork, and up to five little lights inside (twinkling with `frame`).
    static func jar(count: Int, frame: Int, night: Bool) -> CGImage {
        let key = "jar\(count)\(frame)\(night)"
        if let c = cache[key] { return c }
        var cv = PixelCanvas(5, 6)
        cv.hspan(1, 3, 5, 0x9C7840)
        for y in 0...4 { cv.set(0, y, 0xA9C8D8); cv.set(4, y, 0xA9C8D8) }
        cv.hspan(0, 4, 0, 0xA9C8D8)
        for y in 1...4 { cv.hspan(1, 3, y, 0x5A7A8A) }
        let spots = [(1, 1), (3, 2), (2, 3), (1, 4), (3, 4)]
        for (i, (x, y)) in spots.prefix(max(0, min(5, count))).enumerated() {
            let on = night ? (i + frame) % 3 != 0 : false
            cv.set(x, y, on ? 0xF2FF8A : 0xB8C46A)
        }
        let img = cv.image
        cache[key] = img
        return img
    }

    /// Autumn leaves and winter snow on the nest hut (the same 36 × 28 px as its picture, laid over it): on the leaf
    /// roof, the chimney, and along the porch.
    static func season(leaves: Int, snow: Int) -> CGImage? {
        guard leaves > 0 || snow > 0 else { return nil }
        let key = "season\(leaves)\(snow)"
        if let c = cache[key] { return c }
        var cv = PixelCanvas(36, 28)
        func roofTop(_ x: Int) -> Int? {
            let dx = (Double(x) + 0.5 - 11) / 12
            guard abs(dx) < 1 else { return nil }
            return Int((19.5 + 4.6 * (1 - dx * dx).squareRoot() - 0.5).rounded(.down))
        }
        var seed: UInt32 = 0x2F6B_1D3A
        func rnd(_ n: Int) -> Int { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return Int(seed % UInt32(n)) }
        if snow > 0 {
            let white: UInt32 = 0xF4F8FF, shade: UInt32 = 0xC8D4E6
            for x in 0..<23 { if let t = roofTop(x) { for k in 1...min(2, snow) { cv.set(x, t + k, k == 1 && snow < 3 && x % 3 == 0 ? shade : white) }; if snow >= 2 { cv.set(x, t, white) } } }
            cv.hspan(14, 17, 26, white)
            if snow >= 2 { for x in 21...35 where x % 4 != 3 || snow == 3 { cv.set(x, 2, x % 5 == 0 ? shade : white) } }
            if snow >= 3 { cv.set(1, 14, white); cv.set(21, 15, white); cv.vspan(22, 13, 14, shade) }   // icicles at the eaves
        }
        if leaves > 0 {
            let cols: [UInt32] = [0xE8862E, 0xD9443A, 0xF2C04A, 0xA9643A]
            for _ in 0..<(leaves * 6) { let x = rnd(23); if let t = roofTop(x) { cv.set(x, t + 1, cols[rnd(cols.count)]) } }
            for _ in 0..<(leaves * 4) { cv.set(20 + rnd(15), 2, cols[rnd(cols.count)]) }
            if leaves >= 3 { for x in [23, 24, 30, 31] { cv.set(x, 3, cols[rnd(cols.count)]) } }
        }
        let img = cv.image
        cache[key] = img
        return img
    }

    /// The mailbox (9 × 8 px): a little wooden box with a slot, its red flag up while there's unread post (and the
    /// corner of a postcard peeking out of the slot).
    static func mailbox(flag: Bool, card: Bool) -> CGImage {
        let key = "mail\(flag)\(card)"
        if let c = cache[key] { return c }
        let slot = card ? "bkwwkkkb" : "bkkkkkkb"
        let rows = flag ? [
            "..hhhh.RR",
            ".hHHHHhRR",
            "hHHHHHHhp",
            "bbbbbbbbp",
            slot + "p",
            "bBbBbBbB.",
            "bbbbbbbb.",
            ".bbbbbb..",
        ] : [
            "..hhhh...",
            ".hHHHHh..",
            "hHHHHHHh.",
            "bbbbbbbb.",
            slot + "R",
            "bBbBbBbBR",
            "bbbbbbbb.",
            ".bbbbbb..",
        ]
        let img = PropArt.image(PropArt.grid(rows, ["h": 0x6B4428, "H": 0x8A5A35, "b": 0xA9743F, "B": 0x8A5A35, "k": 0x2A1A10, "w": 0xF6EFDF, "R": 0xE0453A, "p": 0x553620]))
        cache[key] = img
        return img
    }

    /// A lantern on a little shepherd's crook (7 × 10 px; the post is at x 1, the lantern hangs at x 4...6).
    static func lantern(lit: Bool) -> CGImage {
        let key = "lantern\(lit)"
        if let c = cache[key] { return c }
        let rows = [
            ".ppppp.",
            ".p...k.",
            ".p..ccc",
            ".p..gLg",
            ".p..gLg",
            ".p..ccc",
            ".p.....",
            ".p.....",
            ".p.....",
            "ppp....",
        ]
        let img = PropArt.image(PropArt.grid(rows, ["p": 0x6B4428, "k": 0x3A2A1C, "c": 0x553620,
                                                    "g": lit ? 0xFFC845 : 0x8A7A58, "L": lit ? 0xFFF0B8 : 0x9A8A68]))
        cache[key] = img
        return img
    }

    /// The postcards, newest first, on a little paper card (drawn at `scale`; `now` for "2h ago").
    static func postcards(_ cards: [Postcard], now: Double, scale: CGFloat) -> CGImage? {
        let shown = Array(cards.reversed().prefix(4))
        guard !shown.isEmpty else { return nil }
        let w: CGFloat = 272, pad: CGFloat = 10, row: CGFloat = 36, head: CGFloat = 22
        let h = pad * 2 + head + row * CGFloat(shown.count)
        let pw = Int(w * scale), ph = Int(h * scale)
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let paper = CGRect(x: 1, y: 1, width: w - 2, height: h - 2)
        ctx.setFillColor(NSColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 0.97).cgColor)
        ctx.addPath(CGPath(roundedRect: paper, cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.fillPath()
        ctx.setStrokeColor(NSColor(red: 0.79, green: 0.63, blue: 0.35, alpha: 1).cgColor); ctx.setLineWidth(1.5)
        ctx.addPath(CGPath(roundedRect: paper.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 8.5, cornerHeight: 8.5, transform: nil)); ctx.strokePath()
        // A little leaf stamp in the corner.
        let stamp = CGRect(x: w - pad - 18, y: h - pad - 20, width: 18, height: 20)
        ctx.setFillColor(NSColor(red: 0.42, green: 0.70, blue: 0.36, alpha: 1).cgColor); ctx.fill(stamp)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor); ctx.setLineWidth(1); ctx.setLineDash(phase: 0, lengths: [2, 1.5])
        ctx.stroke(stamp.insetBy(dx: 1.5, dy: 1.5)); ctx.setLineDash(phase: 0, lengths: [])
        ctx.setFillColor(NSColor(red: 0.85, green: 0.95, blue: 0.70, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: stamp.midX - 4, y: stamp.midY - 6, width: 8, height: 12))

        let ink = NSColor(red: 0.29, green: 0.20, blue: 0.13, alpha: 1), faded = NSColor(red: 0.50, green: 0.40, blue: 0.30, alpha: 1)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        defer { NSGraphicsContext.restoreGraphicsState() }
        func draw(_ s: String, _ font: NSFont, _ color: NSColor, _ r: CGRect, right: Bool = false) {
            let tail = NSMutableParagraphStyle(); tail.lineBreakMode = .byTruncatingTail; tail.alignment = right ? .right : .left
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: tail]).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        let unread = cards.filter { !$0.read }.count
        draw(unread > 0 ? "Postcards · \(unread) new" : "Postcards", .systemFont(ofSize: 11, weight: .semibold), faded, CGRect(x: pad, y: h - pad - 15, width: w - pad * 2 - 24, height: 15))
        for (i, c) in shown.enumerated() {
            let top = h - pad - head - CGFloat(i) * row
            if i > 0 {
                ctx.setStrokeColor(NSColor(red: 0.79, green: 0.63, blue: 0.35, alpha: 0.45).cgColor); ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: pad, y: top + 2)); ctx.addLine(to: CGPoint(x: w - pad, y: top + 2)); ctx.strokePath()
            }
            if !c.read {
                ctx.setFillColor(NSColor(red: 0.42, green: 0.70, blue: 0.36, alpha: 1).cgColor)
                ctx.fillEllipse(in: CGRect(x: pad, y: top - 12, width: 6, height: 6))
            }
            let x = pad + 10
            draw(c.project, .systemFont(ofSize: 12, weight: .semibold), ink, CGRect(x: x, y: top - 16, width: w - x - pad - 60, height: 16))
            draw(ago(now - c.at), .systemFont(ofSize: 10.5), faded, CGRect(x: w - pad - 58, y: top - 15, width: 58, height: 15), right: true)
            draw(c.text, .systemFont(ofSize: 11), faded, CGRect(x: x, y: top - 32, width: w - x - pad, height: 15))
        }
        return ctx.makeImage()
    }

    static func ago(_ s: Double) -> String {
        let s = max(0, s)
        if s < 90 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86_400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86_400))d ago"
    }
}
