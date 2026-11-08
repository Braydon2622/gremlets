import Foundation
import GremletsCore

/// The launch quest list (UserDefaults `quest.v1`): the steps to finish and go public with a project, in order.
/// Shown on the notice board in the bottom-left corner and read out by a Gremlet twice a day.
final class QuestStore {
    struct Step: Codable { var text: String; var done: Bool; var doneAt: Date? }
    private let key = "quest.v1"
    private(set) var steps: [Step] = []
    /// When a step was last ticked off (or the quest started).
    private(set) var lastProgress = Date()

    static let launchPlan = [
        "Ask Claude to build the showtime command for filming",
        "Record a 30 to 45 second real clip (Mac and iPad over Sidecar)",
        "Record the 2 to 3 minute walkthrough video",
        "Add both videos to the portfolio",
        "Get the Apple Developer account for a signed download",
        "Publish the code (MIT) with a signed download",
        "Post the first clip on X, TikTok and Reels",
        "Show HN, r/ClaudeAI and r/macapps posts",
        "Get Gremlets onto the awesome Claude Code list",
    ]

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([Step].self, from: d) {
            steps = s
            lastProgress = UserDefaults.standard.object(forKey: key + ".progress") as? Date ?? Date()
        } else {
            steps = Self.launchPlan.map { Step(text: $0, done: false, doneAt: nil) }
            save()
        }
    }

    var next: (index: Int, step: Step)? { steps.enumerated().first { !$0.element.done }.map { ($0.offset, $0.element) } }
    var doneCount: Int { steps.filter(\.done).count }
    var staleDays: Int { Calendar.current.dateComponents([.day], from: lastProgress, to: Date()).day ?? 0 }

    var board: QuestBoard? {
        guard !steps.isEmpty else { return nil }
        guard let n = next else { return QuestBoard(next: "All done! You shipped it. 🎉", done: steps.count, total: steps.count, staleDays: 0) }
        return QuestBoard(next: n.step.text, done: doneCount, total: steps.count, staleDays: staleDays)
    }

    /// Ticks a step off (1-based), or undoes it. Returns true if something changed.
    @discardableResult
    func setDone(_ n: Int, _ done: Bool) -> Bool {
        guard steps.indices.contains(n - 1), steps[n - 1].done != done else { return false }
        steps[n - 1].done = done
        steps[n - 1].doneAt = done ? Date() : nil
        if done { lastProgress = Date() }
        save()
        return true
    }

    func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        steps.append(Step(text: String(t.prefix(80)), done: false, doneAt: nil))
        save()
    }

    func remove(_ n: Int) { guard steps.indices.contains(n - 1) else { return }; steps.remove(at: n - 1); save() }
    func clear() { steps = []; save() }

    private func save() {
        if let d = try? JSONEncoder().encode(steps) { UserDefaults.standard.set(d, forKey: key) }
        UserDefaults.standard.set(lastProgress, forKey: key + ".progress")
    }

    /// What the messenger says: the next step, more insistent the longer it's been.
    func nagLine() -> String {
        guard let b = board, let n = next else { return "Every step done. You shipped Gremlets!" }
        let progress = "Step \(n.index + 1) of \(b.total)"
        let push: String
        switch b.staleDays {
        case 0 where b.done == 0: push = ["Let's start today!", "First step is the easiest one.", "This is the project that gets you hired."].randomElement()!
        case 0: push = ["Keep it rolling!", "You're on a roll.", "Nice momentum."].randomElement()!
        case 1...2: push = ["Ten minutes today moves it forward.", "This is the project that gets you hired.", "Just the next step."].randomElement()!
        case 3...6: push = "\(b.staleDays) days since the last step. Ten minutes today?"
        default: push = "It's been \(b.staleDays) days! Your portfolio is waiting. One step today, please?"
        }
        return "\(progress): \(n.step.text). \(push)"
    }
}
