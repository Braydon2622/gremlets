/// Animation data for one species, decoupled from any image type.
/// The platform layer keeps the actual bitmaps; the engine only needs timing and alpha masks (for hit testing).
public struct SpeciesInfo: Sendable {
    public struct Animation: Sendable {
        public var frames: [Int]
        public var durations: [Double] // seconds per frame
        public var totalDuration: Double { durations.reduce(0, +) }
        public init(frames: [Int], durations: [Double]) { self.frames = frames; self.durations = durations }
    }

    public var id: String
    public var name: String
    public var element: String
    public var frameWidth: Int
    public var frameHeight: Int
    /// On-screen points per sprite pixel.
    public var scale: Double
    public var animations: [String: Animation]
    /// Per-frame opaque-pixel masks, row-major from the top-left. Used for per-pixel click hit testing.
    public var masks: [[Bool]]
    public var walkSpeed: Double
    public var jumpPower: Double
    public var sleepiness: Double
    public var blurb: String

    public init(id: String, name: String, element: String, frameWidth: Int, frameHeight: Int, scale: Double,
                animations: [String: Animation], masks: [[Bool]],
                walkSpeed: Double = 70, jumpPower: Double = 1, sleepiness: Double = 1, blurb: String = "") {
        self.id = id; self.name = name; self.element = element; self.blurb = blurb
        self.frameWidth = frameWidth; self.frameHeight = frameHeight; self.scale = scale
        self.animations = animations; self.masks = masks
        self.walkSpeed = walkSpeed; self.jumpPower = jumpPower; self.sleepiness = sleepiness
    }

    public var pointSize: Vec2 { Vec2(Double(frameWidth) * scale, Double(frameHeight) * scale) }

    /// Fallback chain so art packs can omit optional animations.
    static let fallbacks: [String: [String]] = [
        "land": ["react", "idle"], "react": ["idle"], "drag": ["fall", "jump", "idle"],
        "fall": ["jump", "idle"], "jump": ["fall", "idle"], "sleep": ["idle"], "walk": ["idle"],
        "look": ["idle"], "crouch": ["land", "idle"], "pet": ["react", "idle"], "yawn": ["sleep", "idle"],
        "wake": ["react", "idle"], "dizzy": ["land", "idle"], "alert": ["react", "idle"],
    ]

    public func animation(_ name: String) -> Animation {
        if let a = animations[name] { return a }
        for alt in Self.fallbacks[name] ?? [] { if let a = animations[alt] { return a } }
        return animations["idle"] ?? animations.values.first ?? Animation(frames: [0], durations: [1])
    }

    /// Frame index for an animation at time `t` (loops).
    public func frame(_ name: String, at t: Double, loop: Bool = true) -> Int {
        let a = animation(name)
        guard a.frames.count > 1 else { return a.frames.first ?? 0 }
        let total = a.totalDuration
        var local = loop ? t.truncatingRemainder(dividingBy: total) : min(t, total - 0.0001)
        for (i, d) in a.durations.enumerated() {
            if local < d { return a.frames[i] }
            local -= d
        }
        return a.frames.last!
    }
}
