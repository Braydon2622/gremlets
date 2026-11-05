// Minimal geometry types so the engine has no dependency on AppKit/CoreGraphics.
// Coordinate space: global desktop points, y-up (same as Cocoa screen coordinates).

public struct Vec2: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public var length: Double { (x * x + y * y).squareRoot() }
}

public struct Rect: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var minX: Double { x }
    public var maxX: Double { x + w }
    public var minY: Double { y }
    public var maxY: Double { y + h }
    public func contains(_ p: Vec2) -> Bool { p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY }
}

/// A closed interval on the x axis, used when subtracting occluded parts of window edges.
public struct Span: Equatable, Sendable {
    public var lo: Double, hi: Double
    public init(_ lo: Double, _ hi: Double) { self.lo = lo; self.hi = hi }
    public var width: Double { hi - lo }

    /// Removes `cut` from every span in `spans`.
    public static func subtract(_ spans: [Span], _ cut: Span) -> [Span] {
        var out: [Span] = []
        for s in spans {
            if cut.hi <= s.lo || cut.lo >= s.hi { out.append(s); continue }
            if cut.lo > s.lo { out.append(Span(s.lo, cut.lo)) }
            if cut.hi < s.hi { out.append(Span(cut.hi, s.hi)) }
        }
        return out
    }
}

public extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
