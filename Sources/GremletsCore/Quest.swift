import Foundation

/// The launch quest: a little wooden notice board standing in the moss in the bottom-left corner with the next step of
/// a project you want to finish (and how far along you are). Twice a day one of them walks over, taps it and reads it
/// out, more insistently the longer it's been since a step got done. The app keeps the list; the world draws the
/// board and sends the messenger.
public struct QuestBoard: Equatable, Sendable {
    public var next: String
    public var done: Int
    public var total: Int
    /// Days since a step was last ticked off.
    public var staleDays: Int
    public init(next: String, done: Int, total: Int, staleDays: Int) { self.next = next; self.done = done; self.total = total; self.staleDays = staleDays }
}

extension World {
    /// Where the board stands (bottom-left of the main screen, in the corner moss).
    public var questBoardSpot: Vec2? {
        guard questBoard != nil, !compact, let scr = screens.first else { return nil }
        return Vec2(scr.minX + 64, scr.minY)
    }

    /// One of them walks over to the board, taps it and reads out the next step.
    @discardableResult
    public func startQuestNag() -> Bool {
        guard let spot = questBoardSpot, let floor = surfaces.first(where: { $0.kind == .floor && $0.supports(x: spot.x) }) else { return false }
        let free = creatures.filter { canDropEverything($0, evenAsleep: false) && supportingSurface(for: $0)?.ownerID == floor.ownerID }
        guard let c = free.min(by: { abs($0.pos.x - spot.x) < abs($1.pos.x - spot.x) }) ?? creatures.filter({ canDropEverything($0) }).first else { return false }
        c.mossTask = nil; c.groveTask = nil; c.snowmanTask = nil
        if supportingSurface(for: c)?.ownerID != floor.ownerID {
            // Up on a window: down on a leaf first, landing by the board.
            startFloat(c, to: Vec2(spot.x + 36, floor.y), ride: .leaf)
            c.mossTask = MossTask(kind: .questNag, started: clock)
            return true
        }
        startMossTask(c, .questNag, walkTo: spot.x + 36)
        return true
    }

    func questNagDecide(_ c: Creature, _ t: inout MossTask, on s: Surface) {
        guard let spot = questBoardSpot else { c.mossTask = nil; c.set(.idle, duration: 0.3); return }
        let x = spot.x + 36
        if abs(c.pos.x - x) > 8, s.supports(x: x), clock - t.started < 40 { c.targetX = x; c.set(.walk, duration: 15); return }
        c.mossTask = nil
        c.facing = -1
        if let cur = cursor, abs(cur.x - c.pos.x) > 200 { c.facing = cur.x > c.pos.x ? 1 : -1 }
        c.set(.wave, duration: 2.2)
        gardenEvents.append(.questNag(by: c.id))
    }

    /// A step got ticked off: everyone nearby cheers.
    public func celebrateQuestStep() {
        guard let spot = questBoardSpot else { return }
        let near = creatures.filter { canDropEverything($0) && abs($0.pos.x - spot.x) < 600 }.prefix(3)
        for c in near { endSocial(c); c.set(.react, duration: c.animationLength(for: .react) + 0.4) }
        if let d = near.first { startDance(d, duration: 4, invite: true) }
        gardenEvents.append(.questStepDone(near.first?.id))
    }
}
