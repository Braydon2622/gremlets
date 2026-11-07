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
    case react        // happy reaction to a click
    case pet          // blissful wiggle while being petted
    case yawn         // big stretch before falling asleep
    case wake         // startled wake-up, then rubs its eyes
    case dizzy        // seeing stars after a hard landing
    case alert        // "!" before chasing the cursor
    case dragged
    case fly          // winged flight to another surface
    case special      // the species' signature move
    case dance
    case wave         // greeting a friend or the cursor
    case run          // playing tag (chasing or fleeing)
    case follow       // walking to / after a friend (greet, follow, nap together)
    case peek         // sneaking to a screen edge to peek around it
    case float        // riding a balloon up to (or down from) a shelf on a window
    case work         // gardening / painting / building / knitting (pose in `workPose`)
}

enum SocialMode { case none, greet, follow, nap, chaser, runner }

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
    /// Heading to a grove plant to do something there.
    var groveTask: GroveVisit?
    /// Holding a sunberry (eaten later, or thrown at a boss).
    public internal(set) var heldBerry = false
    /// Sitting by the lanternbloom after dark.
    public internal(set) var campfire = false
    /// Floating down from somewhere high on a big leaf.
    public internal(set) var gliding = false
    /// Two-Gremlet play (toss, catch, high five) in progress.
    var play: PlayState?
    /// Building a bridge (its id) and when the next block goes down.
    var building: Int?
    var buildTimer = 0.0
    /// Reeling in on a grappling hook toward this point.
    public internal(set) var grapple: Vec2?
    var grappleTime = 0.0
    /// Asleep inside a village house until this time (hidden from view; pops back out after).
    public internal(set) var homeUntil: Double?
    public internal(set) var homeHouse: Int?
    var petAmount: Double = 0
    var edgeDecisionMade = false
    var grabOffset: Vec2 = .zero
    /// Idle has variants ("idle", "look") so standing around doesn't look looped.
    var idleVariant = "idle"
    var prevPos: Vec2 = .zero
    var friendID: Int?
    var social: SocialMode = .none
    var flyTarget: Vec2?
    var peekX: Double?
    var lastGreet: [Int: Double] = [:]
    var bumpCooldown = 0.0
    var startleCooldown = 0.0
    var tagImmunity = 0.0
    var beatTimer = 0.0
    var animSpeed = 1.0
    /// The Claude-buddy job this Gremlet is on, if any (see Work.swift).
    public internal(set) var job: Job?
    /// Which animation plays while working ("crouch" = tending, "look", "pet" = happy wiggle, "sleep" = dozing).
    var workPose = "crouch"
    /// Pokes in quick succession (five in a row while gardening digs up a mystery seed).
    var pokeStreak = 0
    var lastPoke = -10.0
    /// Going to water a planted flower at this x.
    var tendX: Double?
    /// Watching a friend work (their id) and until when.
    var visitingID: Int?
    var visitUntil = 0.0
    /// No new hobby before this (world clock): a breather after finishing one.
    var hobbyRestUntil = 0.0
    /// What it's floating with (balloon, bubble, dandelion, umbrella, leaf), for the platform layer to draw.
    public internal(set) var ride: Ride = .balloon
    /// Where a balloon ride is headed.
    var floatTarget: Vec2?
    /// Dozing next to its project because you stepped away.
    public var isDozingAtWork: Bool { activity == .work && workPose == "sleep" }
    /// 0...1: how close this Gremlet is to you (see `Bond`).
    public internal(set) var bond = 0.0

    /// Surface owner id used when another creature stands on this one's head.
    var carrierOwnerID: Int { World.creatureOwner(id) }

    init(id: Int, species: SpeciesInfo, pos: Vec2) {
        self.id = id; self.species = species; self.pos = pos
    }

    public var size: Vec2 { species.pointSize }
    public var isGrounded: Bool { groundOwner != nil && ![.airborne, .dragged, .fly, .float].contains(activity) }
    public var isAsleep: Bool { activity == .sleep || activity == .yawn }

    /// Name of the animation that matches the current activity.
    public var animationName: String {
        switch activity {
        case .idle: return idleVariant
        case .walk, .chase: return "walk"
        case .crouch: return "crouch"
        case .land: return "land"
        case .airborne: return vel.y > -600 ? "jump" : "fall" // only real drops get the panic face
        case .sleep: return "sleep"
        case .react: return "react"
        case .pet: return "pet"
        case .yawn: return "yawn"
        case .wake: return "wake"
        case .dizzy: return "dizzy"
        case .alert: return "alert"
        case .dragged: return "drag"
        case .fly: return "fly"
        case .special: return "special"
        case .dance: return "dance"
        case .wave: return "wave"
        case .run: return "run"
        case .follow: return "walk"
        case .peek: return "walk"
        case .float: return "drag"       // dangling from the balloon string
        case .work: return workPose
        }
    }

    /// One-shot animations play once and hold their last frame; everything else loops.
    var animationLoops: Bool {
        if activity == .work { return workPose != "crouch" }
        return ![.yawn, .wake, .react, .land, .alert, .crouch, .special].contains(activity)
    }

    public var currentFrame: Int { species.frame(animationName, at: animTime, loop: animationLoops) }

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

    /// Length of the animation that goes with an activity, so one-shot activities last exactly one play-through.
    func animationLength(for a: Activity) -> Double {
        let saved = activity
        activity = a
        defer { activity = saved }
        return species.animation(animationName).totalDuration
    }

    func set(_ a: Activity, duration: Double = 0) {
        if a != activity { animTime = 0 }
        activity = a
        timer = duration
    }
}
