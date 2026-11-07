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

public enum ClaudeWorkEvent: Equatable, Sendable {
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
        j.beats += 1
        switch tool {
        case .build:
            j.blocks += 1
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

    /// A subagent finished: one helper waves and goes home.
    public func claudeHelperDone(workerID: Int) {
        guard let c = creature(id: workerID), let j = c.job, j.helpers > 0 else { return }
        j.helpers -= 1
        claudeEvents.append(.helperLeft(worker: c.id, count: j.helpers))
    }

    public func drainClaudeEvents() -> [ClaudeWorkEvent] {
        defer { claudeEvents.removeAll() }
        return claudeEvents
    }
}
