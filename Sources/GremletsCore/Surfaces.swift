/// A one-way horizontal platform creatures can stand on: a screen floor or the visible part of a window's top edge.
public struct Surface: Equatable, Sendable {
    public enum Kind: Sendable { case floor, windowTop }
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
    public init(id: Int, frame: Rect) { self.id = id; self.frame = frame }
}

public enum SurfaceBuilder {
    /// Minimum visible length of a window edge worth standing on.
    public static let minSegment: Double = 24

    /// Builds standable surfaces from screens and windows.
    ///
    /// - Parameters:
    ///   - screens: usable screen areas (Cocoa `visibleFrame`, so the floor sits above the Dock).
    ///   - windowsFrontToBack: on-screen windows, front-most first (the order CGWindowList returns).
    ///   - headroom: how much space a creature needs above an edge; edges too close to the top of the screen are skipped.
    ///
    /// A window's top edge only counts where no window in front of it covers that edge, so creatures never
    /// stand on a line that's hidden behind another window.
    public static func build(screens: [Rect], windowsFrontToBack: [WindowInfo], headroom: Double = 40) -> [Surface] {
        var out: [Surface] = []
        for (i, s) in screens.enumerated() {
            out.append(Surface(ownerID: -(i + 1), kind: .floor, y: s.minY, minX: s.minX, maxX: s.maxX))
        }
        for (i, win) in windowsFrontToBack.enumerated() {
            let y = win.frame.maxY
            // Must sit on some screen, with room above it for a creature.
            guard let screen = screens.first(where: { y > $0.minY + 1 && y <= $0.maxY - headroom
                && win.frame.maxX > $0.minX && win.frame.minX < $0.maxX }) else { continue }
            var spans = [Span(max(win.frame.minX, screen.minX), min(win.frame.maxX, screen.maxX))]
            for front in windowsFrontToBack[..<i] where front.frame.minY < y + 2 && front.frame.maxY > y - 2 {
                spans = Span.subtract(spans, Span(front.frame.minX, front.frame.maxX))
                if spans.isEmpty { break }
            }
            for sp in spans where sp.width >= minSegment {
                out.append(Surface(ownerID: win.id, kind: .windowTop, y: y, minX: sp.lo, maxX: sp.hi))
            }
        }
        return out
    }
}
