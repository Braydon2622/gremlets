/// Claude's tool calls, as the Gremlet working beside that Claude window sees them. Every kind of work has its own
/// little action, so you can tell what Claude is doing at a glance, without reading the terminal:
///
/// | Claude | Gremlet |
/// |---|---|
/// | edits or writes a file | places a block on its island (a building goes up, one block per edit) |
/// | reads, searches, lists | looks around with a lantern |
/// | runs a command | stirs a bubbling pot (steam) |
/// | searches the web / fetches a page | sends a paper bird off and it comes back |
/// | starts a subagent | a tiny helper Gremlet pops out and works alongside until it's done |
/// | updates its todo list | plants a little flag |
public enum ClaudeTool: String, Sendable {
    case build, look, run, web, spawn, plan, other

    /// Maps a Claude Code tool name to what the Gremlet does.
    public static func from(_ name: String) -> ClaudeTool {
        switch name {
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return .build
        case "Read", "Grep", "Glob", "LS", "NotebookRead": return .look
        case "Bash", "BashOutput", "KillShell": return .run
        case "WebFetch", "WebSearch": return .web
        case "Task", "Agent": return .spawn
        case "TodoWrite": return .plan
        default: return name.hasPrefix("mcp__") ? .web : .other
        }
    }
}

/// Weather over a Claude session's island: a passing shower when a command fails, a little storm when things keep
/// failing, sunshine and a rainbow when the tests pass.
public enum SessionWeather: String, Sendable { case clear, rain, storm, sunny }

public enum ClaudeWorkEvent: Equatable, Sendable {
    case weather(worker: Int, SessionWeather)
    case placedBlock(worker: Int, count: Int)
    case look(Int), run(Int), web(Int), plan(Int)
    case helperJoined(worker: Int, count: Int)
    case helperLeft(worker: Int, count: Int)
}

extension World {
    /// Claude used a tool in the session this Gremlet is helping with.
    public func claudeTool(workerID: Int, _ tool: ClaudeTool) {
        guard let c = creature(id: workerID), let j = c.job, j.phase != .leaving else { return }
        j.lastTool = tool
        j.lastToolTime = clock
        j.needsYou = false
        j.beats += 1
        switch tool {
        case .build:
            j.failStreak = 0
            j.blocks += 1
            if let p = j.label { bonsaiGrow(project: p, .leaf) }
            rebuildAttached()   // a new ledge every few edits
            claudeEvents.append(.placedBlock(worker: c.id, count: j.blocks))
            if c.isGrounded && !c.isDozingAtWork { c.set(.special, duration: min(0.7, c.animationLength(for: .special))) }
        case .look: claudeEvents.append(.look(c.id))
        case .run: claudeEvents.append(.run(c.id))
        case .web: claudeEvents.append(.web(c.id))
        case .plan: claudeEvents.append(.plan(c.id))
        case .spawn:
            j.helpers = min(6, j.helpers + 1)
            claudeEvents.append(.helperJoined(worker: c.id, count: j.helpers))
        case .other: break
        }
    }

    /// A tool call went badly (PostToolUseFailure): rain, or a storm if it keeps happening.
    public func claudeToolFailed(workerID: Int, tests: Bool) {
        guard let c = creature(id: workerID), let j = c.job else { return }
        j.failStreak += 1
        j.lastToolTime = clock
        setWeather(c, j, j.failStreak >= 3 || tests ? .storm : .rain, for: j.failStreak >= 3 ? 40 : 22)
        if c.isGrounded && !c.isDozingAtWork { c.set(.dizzy, duration: 1.2) }
    }

    /// Tests passed: the clouds part, sunshine and a rainbow.
    public func claudeTestsPassed(workerID: Int) {
        guard let c = creature(id: workerID), let j = c.job else { return }
        j.failStreak = 0
        setWeather(c, j, .sunny, for: 14)
        if let p = j.label { bonsaiGrow(project: p, .fruit) }
        if c.isGrounded { startDance(c, duration: 2.5, invite: false) }
    }

    func setWeather(_ c: Creature, _ j: Job, _ w: SessionWeather, for seconds: Double) {
        j.weather = w
        j.weatherUntil = clock + seconds
        claudeEvents.append(.weather(worker: c.id, w))
    }

    /// Weather passes on its own.
    func updateSessionWeather() {
        for c in creatures { if let j = c.job, j.weather != .clear, clock > j.weatherUntil { j.weather = .clear } }
    }

    /// Names the Claude session a Gremlet is helping with (the project folder), for the village journal.
    public func labelJob(workerID: Int, _ label: String) {
        guard let j = creature(id: workerID)?.job else { return }
        j.label = label
        j.needsYou = false
        j.lastToolTime = clock
    }

    /// A subagent finished: one helper waves and goes home.
    public func claudeHelperDone(workerID: Int) {
        guard let c = creature(id: workerID), let j = c.job, j.helpers > 0 else { return }
        j.helpers -= 1
        claudeEvents.append(.helperLeft(worker: c.id, count: j.helpers))
    }

    /// Claude is compacting its context: the Gremlet crouches to tidy up and the project's tree sheds some leaves.
    public func claudeCompact(workerID: Int) {
        guard let c = creature(id: workerID), let j = c.job else { return }
        c.workPose = "crouch"; j.poseTimer = 4
        if let label = j.label, bonsaiPlacements.contains(where: { $0.project == label }) { bonsaiEvents.append(.shed(label)) }
    }

    public func drainClaudeEvents() -> [ClaudeWorkEvent] {
        defer { claudeEvents.removeAll() }
        return claudeEvents
    }

    /// A lift for the Gremlet on its way to a Claude window, so it arrives in a couple of seconds instead of
    /// crossing the whole desktop first. The demo uses it; a real session lets it walk.
    public func hurryClaudeWorker(project: String) {
        guard let c = creatures.first(where: { $0.job?.kind == .claude && $0.job?.label == project && $0.job?.phase == .travel }),
              let j = c.job, let sp = standPoint(j, workerID: c.id) else { return }
        let floor = screen(containingX: sp.x, y: sp.y)?.minY ?? (sp.y - 90)
        c.pos = Vec2(sp.x + (c.pos.x < sp.x ? -70 : 70), max(sp.y - 90, floor))
        startFloat(c, to: sp)
    }
}

extension World {
    /// A Claude session's tab moved to another window (dragged out into its own window, or into another one): the
    /// worker, its shelf, the project's tree, the ivy and the mossy ledges all move over to the new window.
    public func moveClaudeSession(workerID: Int, project: String, to windowID: Int) {
        guard windows[windowID] != nil, let c = creature(id: workerID), let j = c.job, j.kind == .claude, j.windowID != windowID else { return }
        let onShelf = c.groundOwner == World.shelfOwner(c.id)
        j.windowID = windowID
        j.shelfSide = shelfSideFor(window: windowID, near: c.pos.x, for: c.id)
        j.lastShelfMinX = nil; j.lastShelfY = nil
        if var live = liveBonsai[project] { live.windowID = windowID; liveBonsai[project] = live }
        rebuildAttached()
        bonsaiEvents.append(.moved(project, live: true))
        // The worker follows: a balloon over to its new spot.
        if (onShelf || j.phase == .working), let sp = standPoint(j, workerID: c.id) {
            j.phase = .travel
            startFloat(c, to: sp)
        }
    }
}

public enum ClaudePlanEvent: Equatable, Sendable {
    case planSet(worker: Int, total: Int)
    case stepDone(worker: Int, step: Int)
    case planComplete(worker: Int)
    case contextFilling(worker: Int, pct: Int)
}

extension World {
    /// Claude wrote or updated its to-do list: `done` of `total` steps finished.
    public func claudePlan(workerID: Int, total: Int, done: Int) {
        guard let c = creature(id: workerID), let j = c.job, j.kind == .claude else { return }
        let total = max(0, min(30, total)), done = max(0, min(total, done))
        if total != j.planTotal { j.planTotal = total; planEvents.append(.planSet(worker: c.id, total: total)) }
        if done > j.planDone {
            for k in j.planDone..<done { planEvents.append(.stepDone(worker: c.id, step: k)) }
            if c.isGrounded && c.activity != .work { c.set(.special, duration: min(0.4, c.animationLength(for: .special))) }
        }
        let wasComplete = j.planTotal > 0 && j.planDone >= j.planTotal
        j.planDone = done
        if total > 0 && done >= total && !wasComplete { planEvents.append(.planComplete(worker: c.id)) }
    }

    /// The status line reported how full the context window is.
    public func claudeContext(workerID: Int, pct: Int) {
        guard let c = creature(id: workerID), let j = c.job, j.kind == .claude else { return }
        let before = j.contextPct ?? 0
        j.contextPct = max(0, min(100, pct))
        if before < 85 && pct >= 85 {
            planEvents.append(.contextFilling(worker: c.id, pct: pct))
            if c.isGrounded { c.set(.yawn, duration: c.animationLength(for: .yawn)) }
        }
    }

    public func drainPlanEvents() -> [ClaudePlanEvent] {
        defer { planEvents.removeAll() }
        return planEvents
    }
}

extension World {
    /// Claude asked the Gremlets to celebrate: the worker dances and friends nearby join in.
    public func celebrate(around id: Int?) {
        let c = creature(id: id) ?? creatures.first
        guard let c else { return }
        if c.isGrounded { startDance(c, duration: 3.2, invite: true) }
        for o in creatures where o !== c && o.isGrounded && isFree(o) && abs(o.pos.x - c.pos.x) < 500 && abs(o.pos.y - c.pos.y) < 200 {
            startDance(o, duration: 3.0, invite: false)
        }
    }

    /// Claude wants the user's eyes: the worker waves and its tree gets the waiting lantern until the next tool use.
    public func requestReview(workerID: Int) { jobNeedsAttention(workerID) }
}

