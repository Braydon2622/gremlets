/// What a creature is doing right now. Each activity has its own update rule in `World`,
/// and `Brain` picks the next one when the current activity runs out.
public enum Activity: Equatable, Sendable {
    case idle
    case walk
    case chase        // walking toward the cursor
    case crouch       // jump anticipation; launches when the timer ends
    case airborne     // jumping, falling or thrown
    case land         // squash after landing
    case sleep
    case react        // happy reaction to a click or petting
    case dragged
}

public final class Creature {
    public let id: Int
    public let species: SpeciesInfo

    /// Bottom-centre of the sprite (the feet), global y-up points.
    public var pos: Vec2
    public var vel: Vec2 = .zero
    /// +1 = facing right, -1 = facing left. Sprites are drawn facing right.
    public var facing: Double = 1

    public internal(set) var activity: Activity = .airborne
    /// Seconds left in the current activity.
    public internal(set) var timer: Double = 0
    /// Seconds since the current animation started.
    public internal(set) var animTime: Double = 0
    /// `ownerID` of the surface we're standing on (nil while airborne/dragged).
    public internal(set) var groundOwner: Int?
    /// 1 = rested, 0 = exhausted. Drains while awake, refills while asleep.
    public internal(set) var energy: Double = 1

    var pendingLaunch: Vec2 = .zero
    var targetX: Double?
    var petAmount: Double = 0
    var edgeDecisionMade = false
    var grabOffset: Vec2 = .zero

    init(id: Int, species: SpeciesInfo, pos: Vec2) {
        self.id = id; self.species = species; self.pos = pos
    }

    public var size: Vec2 { species.pointSize }
    public var isGrounded: Bool { groundOwner != nil && activity != .airborne && activity != .dragged }

    /// Name of the animation that matches the current activity.
    public var animationName: String {
        switch activity {
        case .idle: return "idle"
        case .walk, .chase: return "walk"
        case .crouch, .land: return "land"
        case .airborne: return vel.y > 60 ? "jump" : "fall"
        case .sleep: return "sleep"
        case .react: return "react"
        case .dragged: return "drag"
        }
    }

    public var currentFrame: Int { species.frame(animationName, at: animTime) }

    /// Axis-aligned bounds of the sprite in global points.
    public var bounds: Rect { Rect(x: pos.x - size.x / 2, y: pos.y, w: size.x, h: size.y) }

    /// Per-pixel hit test against the current frame's alpha mask, with 1px of slack so tiny sprites are easy to grab.
    public func hitTest(_ p: Vec2) -> Bool {
        guard bounds.contains(p) else { return false }
        let fw = species.frameWidth, fh = species.frameHeight
        var col = Int((p.x - bounds.minX) / species.scale)
        let row = Int((bounds.maxY - p.y) / species.scale)
        if facing < 0 { col = fw - 1 - col }
        let frame = currentFrame
        guard frame < species.masks.count else { return true }
        let mask = species.masks[frame]
        for dy in -1...1 { for dx in -1...1 {
            let c = col + dx, r = row + dy
            if c >= 0, c < fw, r >= 0, r < fh, mask[r * fw + c] { return true }
        }}
        return false
    }

    func set(_ a: Activity, duration: Double = 0) {
        if a != activity { animTime = 0 }
        activity = a
        timer = duration
    }
}
