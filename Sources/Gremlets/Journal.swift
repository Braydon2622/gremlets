import AppKit
import GremletsCore

/// A day-by-day log of what Claude and the Gremlets got done (tasks, edits, buildings, gems), and the garden journal
/// page that shows it: open from the menu (Open Garden Journal) or at http://127.0.0.1:47920/journal. The log also
/// feeds the morning greeting ("Yesterday you finished 9 Claude tasks…").
final class DayLog {
    struct Day: Codable {
        var tasks = 0; var edits = 0; var houses = 0; var gems = 0; var minutes = 0.0
        /// Edits per project that day (optional so older logs still decode).
        var projects: [String: Int]?
        /// The garden that day, for the scrapbook (optional so older logs still decode): things picked from the moss,
        /// fireflies caught, tufts of moss planted, daisies put in the house's window box.
        var daisies: Int?, mushrooms: Int?, berries: Int?, dandelions: Int?, fireflies: Int?, tufts: Int?, boxed: Int?
    }
    private let key = "daylog.v1"
    private(set) var days: [String: Day] = [:]

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let v = try? JSONDecoder().decode([String: Day].self, from: d) { days = v }
    }

    func add(_ change: (inout Day) -> Void, on date: Date = Date()) {
        var d = days[DayLog.key(date)] ?? Day()
        change(&d)
        days[DayLog.key(date)] = d
        // Keep three months.
        if days.count > 100, let oldest = days.keys.sorted().first { days[oldest] = nil }
        if let data = try? JSONEncoder().encode(days) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    subscript(date: Date) -> Day { days[DayLog.key(date)] ?? Day() }

    /// The last `n` days, oldest first.
    func recent(_ n: Int) -> [(date: Date, day: Day)] {
        (0..<n).reversed().compactMap { back in
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: Date()) else { return nil }
            return (d, self[d])
        }
    }

    /// Days in a row (ending today or yesterday) with at least one Claude task.
    var streak: Int {
        var n = 0
        var d = Date()
        if self[d].tasks == 0 { d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d }
        while self[d].tasks > 0 { n += 1; d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d; if n > 400 { break } }
        return n
    }

    /// One line for the morning: what yesterday added up to.
    var yesterdayLine: String? {
        guard let y = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return nil }
        let d = self[y]
        guard d.tasks > 0 || d.edits > 0 else { return nil }
        var parts: [String] = []
        if d.tasks > 0 { parts.append("\(d.tasks) Claude task\(d.tasks == 1 ? "" : "s")") }
        if d.edits > 0 { parts.append("\(d.edits) edit\(d.edits == 1 ? "" : "s")") }
        if d.houses > 0 { parts.append("\(d.houses) new building\(d.houses == 1 ? "" : "s")") }
        if d.gems > 0 { parts.append("\(d.gems) gem\(d.gems == 1 ? "" : "s")") }
        let s = streak
        return "Yesterday: " + parts.joined(separator: ", ") + (s >= 2 ? ". That's \(s) days in a row." : ".")
    }
}

enum Journal {
    static func pngDataURI(_ img: CGImage) -> String {
        let rep = NSBitmapImageRep(cgImage: img)
        guard let png = rep.representation(using: .png, properties: [:]) else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The whole page: the postcard, every project's tree with its story, the last two weeks, the village and the mine.
    static func page(world: World, species: [String: LoadedSpecies], log: DayLog, sessions: [SessionRecord] = []) -> String {
        let now = Date().timeIntervalSince1970
        let df = DateFormatter(); df.dateStyle = .full; df.timeStyle = .none
        let card = VillageSnapshot.render(world: world, species: species).map { pngDataURI($0.image) }
        var trees = ""
        for t in world.bonsaiBook.trees.sorted(by: { $0.lastSeen > $1.lastSeen }) {
            let layout = BonsaiGeometry.layout(t)
            let (img, _) = BonsaiArt.image(t, layout: layout, scale: 1, month: world.month, night: false, ageDays: t.ageDays(now: now))
            let live = world.bonsaiPlacements.contains { $0.project == t.project && $0.slot < 0 }
            let planted = DateFormatter.localizedString(from: Date(timeIntervalSince1970: t.plantedAt), dateStyle: .medium, timeStyle: .none)
            let hours = t.minutes / 60
            trees += """
            <div class="tree"><img src="\(pngDataURI(img))" width="\(img.width * 3)" height="\(img.height * 3)" alt="">
            <h3>\(esc(t.project)) \(live ? "<span class=live>growing now</span>" : "")</h3>
            <p>\(t.species.name) · \(t.form.name) · planted \(planted)\(t.repoCommits > 0 ? " · \(t.repoCommits) commits in the repo" : "")</p>
            \(t.milestones.isEmpty ? "" : "<p>Milestones: " + t.milestones.map { $0.replacingOccurrences(of: "-", with: " ") }.joined(separator: ", ") + "</p>")
            <p><b>\(t.sessions)</b> session\(t.sessions == 1 ? "" : "s") · <b>\(t.edits)</b> edit\(t.edits == 1 ? "" : "s") · <b>\(t.blooms)</b> task\(t.blooms == 1 ? "" : "s") finished · <b>\(t.fruit)</b> test pass\(t.fruit == 1 ? "" : "es")\(hours >= 0.1 ? String(format: " · %.1f h", hours) : "")</p></div>
            """
        }
        if trees.isEmpty { trees = "<p class=muted>No trees yet. The first Claude Code session you run plants one on its terminal.</p>" }
        let recent = log.recent(14)
        let maxTasks = max(1, recent.map(\.day.tasks).max() ?? 1)
        let wd = DateFormatter(); wd.dateFormat = "EEE"
        let bars = recent.map { r -> String in
            let h = Int(Double(r.day.tasks) / Double(maxTasks) * 72)
            return "<div class=bar title=\"\(DayLog.key(r.date)): \(r.day.tasks) tasks, \(r.day.edits) edits\"><i style=\"height:\(max(2, h))px\"></i><span>\(wd.string(from: r.date).prefix(2))</span><b>\(r.day.tasks)</b></div>"
        }.joined()
        let g = world.grove
        let houses = g.village.filter { Biome(rawValue: $0.biome) != nil }
        let gems = GemKind.allCases.compactMap { k -> String? in let n = g.gems[k.rawValue] ?? 0; return n > 0 ? "\(n) \(k.name.lowercased())" : nil }
        let items = VillageItem.allCases.filter { world.owns($0) }.map(\.name)
        let today = log[Date()]
        let sf = DateFormatter(); sf.dateFormat = "EEE d MMM, HH:mm"
        var sess = ""
        for r in sessions.suffix(8).reversed() {
            let maxM = max(1, r.minutes.map { $0.edits + $0.tools }.max() ?? 1)
            let bars = r.minutes.map { m in "<i style=\"height:\(max(2, Int(Double(m.edits + m.tools) / Double(maxM) * 28)))px;opacity:\(m.edits > 0 ? 1 : 0.4)\"></i>" }.joined()
            let extras = (r.testsPassed.isEmpty ? "" : " · \(r.testsPassed.count) green test\(r.testsPassed.count == 1 ? "" : "s")") + (r.helpers > 0 ? " · \(r.helpers) helper\(r.helpers == 1 ? "" : "s")" : "")
            sess += "<div class=sess><div><b>\(esc(r.project))</b> · \(sf.string(from: Date(timeIntervalSince1970: r.started))) · \(SessionRecord.duration(r.seconds))<br><span class=muted>\(r.edits) edit\(r.edits == 1 ? "" : "s") · \(r.tasks.count) task\(r.tasks.count == 1 ? "" : "s")\(extras)</span></div><div class=strip title=\"edits and other tool calls, a bar per minute\">\(bars)</div></div>"
        }
        if sess.isEmpty { sess = "<p class=muted>No finished sessions yet. When a Claude Code session ends, its minute-by-minute strip shows here and a recap card is saved to Pictures › Gremlets › Sessions.</p>" }
        return """
        <!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
        <title>Garden journal</title>
        <style>
        :root{--bg:#0f1220;--card:#181c2e;--ink:#eef1f8;--muted:#9aa3bd;--accent:#8fd67a;color-scheme:dark}
        body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 -apple-system,system-ui,sans-serif;padding:28px 20px 60px}
        main{max-width:1040px;margin:0 auto}
        h1{font-size:30px;margin:0 0 4px}h2{font-size:18px;margin:34px 0 12px;color:var(--accent)}h3{margin:8px 0 2px;font-size:16px}
        .muted{color:var(--muted)}.card img{width:100%;height:auto;border-radius:14px;display:block;image-rendering:pixelated}
        .stats{display:flex;flex-wrap:wrap;gap:10px;margin:14px 0}.stat{background:var(--card);border-radius:12px;padding:10px 14px;min-width:120px}
        .stat b{display:block;font-size:22px}
        .trees{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}
        .tree{background:var(--card);border-radius:14px;padding:14px;display:flex;flex-direction:column;align-items:flex-start}
        .tree img{image-rendering:pixelated;max-width:100%;height:auto;align-self:center;margin:4px 0 8px}.tree p{margin:2px 0;color:var(--muted)}.tree b{color:var(--ink)}
        .live{font-size:12px;background:#2f6b3a;color:#dfffd0;border-radius:999px;padding:2px 8px;margin-left:6px;vertical-align:middle}
        .chart{display:flex;gap:6px;align-items:flex-end;background:var(--card);border-radius:14px;padding:16px 14px 8px;height:120px}
        .bar{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;font-size:11px;color:var(--muted)}
        .bar i{display:block;width:100%;max-width:34px;background:linear-gradient(#b8f2a0,#5db446);border-radius:5px 5px 2px 2px}
        .bar b{color:var(--ink);font-size:12px;margin-top:2px}
        footer{margin-top:40px;color:var(--muted);font-size:13px}
        .sess{display:grid;grid-template-columns:minmax(220px,1fr) 2fr;gap:14px;background:var(--card);border-radius:12px;padding:10px 14px;margin:8px 0;align-items:center}
        .strip{display:flex;gap:1px;align-items:flex-end;height:30px}.strip i{flex:1;background:#7fd36a;border-radius:1px 1px 0 0;display:block;min-width:1px}
        @media (max-width:640px){.sess{grid-template-columns:1fr}}
        </style></head><body><main>
        <h1>Garden journal</h1><p class=muted>\(df.string(from: Date()))</p>
        <div class=stats>
          <div class=stat><b>\(today.tasks)</b>Claude tasks today</div>
          <div class=stat><b>\(log.streak)</b>day streak</div>
          <div class=stat><b>\(g.tasks)</b>tasks all time</div>
          <div class=stat><b>\(world.bonsaiBook.trees.count)</b>project trees</div>
          <div class=stat><b>\(houses.count)</b>buildings</div>
          <div class=stat><b>\(g.gems.values.reduce(0, +))</b>gems</div>
        </div>
        \(card.map { "<div class=card><img src=\"\($0)\" alt=\"Your village\"></div>" } ?? "")
        <h2>Your projects' trees</h2><div class=trees>\(trees)</div>
        <h2>The last two weeks</h2><div class=chart>\(bars)</div>
        <h2>Recent sessions</h2>\(sess)
        <h2>The village</h2>
        <p>\(houses.isEmpty ? "No buildings yet. A Claude session with four or more file edits leaves a house behind." : houses.map { "\(esc($0.project ?? "a project")) (\($0.blocks) edits\($0.day.map { ", \($0)" } ?? ""))\($0.owner.map { " · home of \(esc(species[$0]?.info.name ?? $0))" } ?? "")" }.joined(separator: " · "))</p>
        <p class=muted>\(gems.isEmpty ? "No gems yet (\(g.digCharges) dig\(g.digCharges == 1 ? "" : "s") earned)." : "Gems: " + gems.joined(separator: ", ") + ".") \(items.isEmpty ? "" : "From the merchant: " + items.joined(separator: ", ") + ".")</p>
        <footer>Gremlets keeps this on your Mac. Nothing here leaves it.</footer>
        </main></body></html>
        """
    }
}
