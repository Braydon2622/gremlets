import AppKit

/// The menu bar logo: a little Gremlet peeking out of a mound of moss with a sprout on its head. While Claude works
/// the sprout has a third leaf; while Claude waits for you a tiny lantern glows beside it. Pixel art, 2 pt a pixel.
enum MenuLogo {
    enum State { case idle, working, waiting }
    private static var cache: [String: NSImage] = [:]

    static func image(_ state: State) -> NSImage {
        let key = "\(state)"
        if let c = cache[key] { return c }
        // 11 × 9 art pixels (x right, y up), drawn at 2 pt each.
        var px: [Int: UInt32] = [:]
        func set(_ x: Int, _ y: Int, _ c: UInt32) { px[y * 11 + x] = c }
        let moss: UInt32 = 0x4F9A3E, mossLight: UInt32 = 0x8BD66A, face: UInt32 = 0xF4E7C6, faceShade: UInt32 = 0xE2CFA2
        let eye: UInt32 = 0x2B2620, blush: UInt32 = 0xF29AA8, leaf: UInt32 = 0x7CCF56, stem: UInt32 = 0x4F9A3E
        // Head (rows 2...6, x 1...7), rounded.
        for y in 2...6 { for x in 1...7 where !((y == 6 || y == 2) && (x == 1 || x == 7)) { set(x, y, y == 2 ? faceShade : face) } }
        set(3, 4, eye); set(5, 4, eye); set(2, 3, blush); set(6, 3, blush)
        // The sprout.
        set(4, 7, stem); set(3, 8, leaf); set(5, 8, leaf)
        if state == .working { set(4, 8, stem); set(2, 8, leaf); set(6, 8, leaf) }
        // Moss mound in front (rows 0...2).
        for x in 0...8 { set(x, 0, moss); set(x, 1, x % 3 == 1 ? mossLight : moss) }
        for x in [0, 2, 6, 8] { set(x, 2, moss) }
        set(1, 2, mossLight); set(7, 2, mossLight)
        // The lantern.
        if state == .waiting { set(10, 7, 0x6B4428); set(9, 6, 0xFFC845); set(10, 6, 0xFFC845); set(9, 5, 0xFF9E2C); set(10, 5, 0xFFE9A0) }
        let outline: UInt32 = 0x23331F
        var out = px
        for (k, _) in px {
            let x = k % 11, y = k / 11
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < 11, ny >= 0, ny < 9, px[ny * 11 + nx] == nil, out[ny * 11 + nx] == nil else { continue }
                out[ny * 11 + nx] = outline
            }
        }
        let img = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            for (k, c) in out {
                let x = k % 11, y = k / 11
                ctx.setFillColor(CGColor(red: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255, blue: CGFloat(c & 0xFF) / 255, alpha: 1))
                ctx.fill(CGRect(x: x * 2, y: y * 2, width: 2, height: 2))
            }
            return true
        }
        img.isTemplate = false
        cache[key] = img
        return img
    }
}
