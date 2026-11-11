/// A one-way horizontal platform creatures can stand on: a screen floor or the visible part of a window's top edge.
public struct Surface: Equatable, Sendable {
    public enum Kind: Sendable { case floor, windowTop, creature, shelf, windowLedge, icon, plant }
    /// Window number for window tops; negative ids for screen floors.
    public var ownerID: Int
    public var kind: Kind
    public var y: Double
    public var minX: Double
    public var maxX: Double

    public init(ownerID: Int, kind: Kind, y: Double, minX: Double, maxX: Double) {
        self.ownerID = ownerID; self.kind = kind; self.y = y; self.minX = minX; self.maxX = maxX
    }
    public var width: Double { maxX - minX }
    public func supports(x: Double) -> Bool { x >= minX && x <= maxX }
}

/// A desktop window as reported by the platform layer, in global y-up coordinates.
public struct WindowInfo: Equatable, Sendable {
    public var id: Int
    public var frame: Rect
    /// Ledges inside the window, as distances below its top edge (e.g. the bottom of a browser's tab and address bar).
    public var ledges: [Double]
    /// Shorter ledges found in the window's content (the tops of text lines, labels, search fields), if enabled.
    public var spans: [WindowSpan]
    /// A desktop widget (behind every window, on the desktop).
    public var isWidget = false
    public init(id: Int, frame: Rect, ledges: [Double] = [], spans: [WindowSpan] = [], isWidget: Bool = false) { self.id = id; self.frame = frame; self.ledges = ledges; self.spans = spans; self.isWidget = isWidget }
}

/// A short ledge inside a window: `fromTop` points below its top edge, from `minX` to `maxX` points from its left edge.
public struct WindowSpan: Equatable, Sendable {
    public var fromTop: Double, minX: Double, maxX: Double
    public init(fromTop: Double, minX: Double, maxX: Double) { self.fromTop = fromTop; self.minX = minX; self.maxX = maxX }
}

/// The menu bar along the top of a screen (the strip above its usable area): how tall it is, and the stretches of it
/// with nothing in them (no menus, no status icons, no notch), where a Gremlet may stand on a window top just below it.
public struct MenuBar: Equatable, Sendable {
    public var height: Double
    public var clear: [Span]
    public init(height: Double, clear: [Span]) { self.height = height; self.clear = clear }
    /// Room a Gremlet needs between a window top and the very top of the screen.
    public static let minRoom: Double = 36
}

public enum SurfaceBuilder {
    /// Minimum visible length of a window edge worth standing on.
    public static let minSegment: Double = 24

    /// Builds standable surfaces from screens and windows.
    ///
    /// - Parameters:
    ///   - screens: usable screen areas (Cocoa `visibleFrame`, so the floor sits above the Dock).
    ///   - windowsFrontToBack: on-screen windows, front-most first (the order CGWindowList returns).
    ///   - menuBars: each screen's menu bar, if known: window tops right up under it are walkable where it's empty.
    ///   - headroom: how much space a creature needs above an edge; closer to the top of the screen than that, only
    ///     the stretches under an empty bit of menu bar count.
    ///
    /// A window's top edge only counts where no window in front of it covers that edge, so creatures never
    /// stand on a line that's hidden behind another window.
    /// The visible stretches of window `i`'s top edge (nothing in front covering them) and the screen it's on, however
    /// close to the top of the screen it is.
    public static func visibleTop(_ i: Int, _ windowsFrontToBack: [WindowInfo], screens: [Rect]) -> (screen: Int, spans: [Span])? {
        let win = windowsFrontToBack[i]
        let y = win.frame.maxY
        guard let si = screens.firstIndex(where: { y > $0.minY + 1 && y <= $0.maxY + 1
            && win.frame.maxX > $0.minX && win.frame.minX < $0.maxX }) else { return nil }
        let screen = screens[si]
        var spans = [Span(max(win.frame.minX, screen.minX), min(win.frame.maxX, screen.maxX))]
        for front in windowsFrontToBack[..<i] where front.frame.minY < y + 2 && front.frame.maxY > y - 2 {
            spans = Span.subtract(spans, Span(front.frame.minX, front.frame.maxX))
            if spans.isEmpty { break }
        }
        return (si, spans)
    }

    /// Every window's whole visible top edge, including the ones right up under the menu bar that nobody walks along
    /// (moss still grows on them, and strands still hang from their corners).
    public static func topEdges(screens: [Rect], windowsFrontToBack: [WindowInfo]) -> [Surface] {
        windowsFrontToBack.indices.flatMap { i -> [Surface] in
            guard let (_, spans) = visibleTop(i, windowsFrontToBack, screens: screens) else { return [] }
            let w = windowsFrontToBack[i]
            return spans.filter { $0.width >= minSegment }.map { Surface(ownerID: w.id, kind: .windowTop, y: w.frame.maxY, minX: $0.lo, maxX: $0.hi) }
        }
    }

    public static func build(screens: [Rect], windowsFrontToBack: [WindowInfo], menuBars: [MenuBar?] = [], headroom: Double = 40) -> [Surface] {
        var out: [Surface] = []
        for (i, s) in screens.enumerated() {
            out.append(Surface(ownerID: -(i + 1), kind: .floor, y: s.minY, minX: s.minX, maxX: s.maxX))
        }
        for (i, win) in windowsFrontToBack.enumerated() {
            let y = win.frame.maxY
            guard let (si, spans) = visibleTop(i, windowsFrontToBack, screens: screens) else { continue }
            let screen = screens[si]
            if y <= screen.maxY - headroom {
                for sp in spans where sp.width >= minSegment {
                    out.append(Surface(ownerID: win.id, kind: .windowTop, y: y, minX: sp.lo, maxX: sp.hi))
                }
            } else if si < menuBars.count, let bar = menuBars[si], screen.maxY + bar.height - y >= MenuBar.minRoom {
                // Right up under the menu bar (a window filling the screen): only where the menu bar above is empty,
                // so nobody stands in front of a menu, a status icon or the notch.
                var walk: [Span] = []
                for sp in spans { for c in bar.clear { let lo = max(sp.lo, c.lo), hi = min(sp.hi, c.hi); if hi - lo >= 60 { walk.append(Span(lo, hi)) } } }
                for sp in walk { out.append(Surface(ownerID: win.id, kind: .windowTop, y: y, minX: sp.lo, maxX: sp.hi)) }
            }
            // Ledges inside the window (toolbars), where no window in front covers them.
            for offset in win.ledges where offset + 60 < win.frame.h {
                let ly = y - offset
                var inner = [Span(max(win.frame.minX + 8, screen.minX), min(win.frame.maxX - 8, screen.maxX))]
                for front in windowsFrontToBack[..<i] where front.frame.minY < ly + 100 && front.frame.maxY > ly - 2 {
                    inner = Span.subtract(inner, Span(front.frame.minX, front.frame.maxX))
                }
                for sp in inner where sp.width >= minSegment * 3 {
                    out.append(Surface(ownerID: win.id, kind: .windowLedge, y: ly, minX: sp.lo, maxX: sp.hi))
                }
            }
            // Spans in the content (text lines, search fields), where nothing in front covers them.
            for s in win.spans where s.fromTop + 40 < win.frame.h {
                let ly = y - s.fromTop
                var inner = [Span(max(win.frame.minX + s.minX, screen.minX), min(win.frame.minX + s.maxX, screen.maxX))]
                for front in windowsFrontToBack[..<i] where front.frame.minY < ly + 60 && front.frame.maxY > ly - 2 {
                    inner = Span.subtract(inner, Span(front.frame.minX, front.frame.maxX))
                }
                for sp in inner where sp.width >= 50 {
                    out.append(Surface(ownerID: win.id, kind: .windowLedge, y: ly, minX: sp.lo, maxX: sp.hi))
                }
            }
        }
        return out
    }
}
