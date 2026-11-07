import AppKit
import GremletsCore

/// `gremlet wrapped [YYYY-MM]`: a month with Claude Code as one poster. The numbers, a calendar of every day shaded by
/// how much got done, the trees that grew, the busiest day. Saved to ~/Pictures/Gremlets and copied. `--sample`
/// draws a made-up month so you can see the poster before the month has happened.
enum WrappedPoster {
    struct Month {
        var year: Int
        var month: Int
        var days: [Int: DayLog.Day] = [:]
        var trees: [(tree: Bonsai, edits: Int?)] = []
        var sessions = 0
        var longestSession: TimeInterval = 0
        var testsGreen = 0

        var title: String {
            let f = DateFormatter(); f.dateFormat = "LLLL yyyy"
            return f.string(from: firstDay)
        }
        var firstDay: Date { Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date() }
        var dayCount: Int { Calendar.current.range(of: .day, in: .month, for: firstDay)?.count ?? 30 }
        var edits: Int { days.values.reduce(0) { $0 + $1.edits } }
        var tasks: Int { days.values.reduce(0) { $0 + $1.tasks } }
        var minutes: Double { days.values.reduce(0) { $0 + $1.minutes } }
        var houses: Int { days.values.reduce(0) { $0 + $1.houses } }
        var gems: Int { days.values.reduce(0) { $0 + $1.gems } }
        var activeDays: Int { days.values.filter { $0.edits > 0 || $0.tasks > 0 }.count }
        var busiest: (day: Int, edits: Int)? { days.max { $0.value.edits < $1.value.edits }.map { ($0.key, $0.value.edits) }.flatMap { $0.edits > 0 ? $0 : nil } }
        /// Longest run of days in a row with something done.
        var streak: Int {
            var best = 0, run = 0
            for d in 1...dayCount {
                if let x = days[d], x.edits > 0 || x.tasks > 0 { run += 1; best = max(best, run) } else { run = 0 }
            }
            return best
        }
    }

    /// Pulls the month together from the day log, the session log and the bonsai book.
    static func gather(year: Int, month: Int, world: World, log: DayLog, sessions: [SessionRecord]) -> Month {
        var m = Month(year: year, month: month)
        var perProject: [String: Int] = [:]
        for d in 1...m.dayCount {
            let key = String(format: "%04d-%02d-%02d", year, month, d)
            if let day = log.days[key] {
                m.days[d] = day
                for (p, n) in day.projects ?? [:] { perProject[p, default: 0] += n }
            }
        }
        let cal = Calendar.current
        func inMonth(_ t: TimeInterval) -> Bool {
            let c = cal.dateComponents([.year, .month], from: Date(timeIntervalSince1970: t))
            return c.year == year && c.month == month
        }
        m.trees = world.bonsaiBook.trees.filter { inMonth($0.lastSeen) || inMonth($0.firstSeen) || perProject[$0.project] != nil }
            .map { ($0, perProject[$0.project]) }
            .sorted { ($0.edits ?? -1, $0.tree.edits) > ($1.edits ?? -1, $1.tree.edits) }
        let ss = sessions.filter { inMonth($0.started) }
        m.sessions = ss.count
        m.longestSession = ss.map(\.seconds).max() ?? 0
        m.testsGreen = ss.reduce(0) { $0 + $1.testsPassed.count }
        return m
    }

    /// A made-up month for a preview.
    static func sample() -> Month {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        var m = Month(year: c.year ?? 2026, month: c.month ?? 11)
        var seed: UInt64 = 0xA5A5_1234_5678_9ABC
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        let names = ["DesktopPets", "SalesCheatCodeLive", "PhotoToPart"]
        for d in 1...m.dayCount {
            let wd = Calendar.current.component(.weekday, from: Calendar.current.date(byAdding: .day, value: d - 1, to: m.firstDay) ?? m.firstDay)
            let weekend = wd == 1 || wd == 7
            if next() < (weekend ? 0.45 : 0.15) { continue }
            var day = DayLog.Day()
            day.edits = Int(next() * (weekend ? 60 : 180)) + (next() < 0.1 ? 150 : 0)
            day.tasks = max(1, day.edits / 14)
            day.minutes = Double(day.edits) * 1.4 + next() * 40
            if next() < 0.25 { day.houses = 1 }
            if next() < 0.12 { day.gems = 1 }
            var pr: [String: Int] = [:]
            pr[names[0]] = day.edits * 6 / 10; pr[names[1]] = day.edits * 3 / 10; pr[names[2]] = day.edits - pr[names[0]]! - pr[names[1]]!
            day.projects = pr
            m.days[d] = day
        }
        let now = Date().timeIntervalSince1970
        for (i, n) in names.enumerated() {
            var t = Bonsai(project: n, now: now - 86400 * Double(40 - i * 9))
            let total = m.days.values.reduce(0) { $0 + ($1.projects?[n] ?? 0) }
            let sessions = [9, 5, 3][i]
            for k in 0..<sessions {
                _ = t.startSession("s\(k)", now: t.firstSeen + Double(k) * 86400 * 3)
                t.branches[k].edits = max(3, total / sessions + Int(next() * 10))
                t.branches[k].blooms = 1 + Int(next() * 3)
                if next() < 0.5 { t.branches[k].fruit = 1 }
            }
            t.endSession()
            m.trees.append((t, total))
        }
        m.sessions = 17; m.longestSession = 3 * 3600 + 12 * 60; m.testsGreen = 23
        return m
    }

    static func make(_ m: Month, world: World) -> URL? {
        guard let (image, size) = render(m, world: world) else { return nil }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Gremlets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Wrapped \(String(format: "%04d-%02d", m.year, m.month)).png")
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
        return url
    }

    static func render(_ m: Month, world: World) -> (image: CGImage, size: CGSize)? {
        let W = 1080, H = 1350
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let night = world.isNight
        let sky = night ? [CGColor(red: 0.07, green: 0.09, blue: 0.22, alpha: 1), CGColor(red: 0.2, green: 0.15, blue: 0.34, alpha: 1)]
                        : [CGColor(red: 0.9, green: 0.95, blue: 0.99, alpha: 1), CGColor(red: 0.99, green: 0.94, blue: 0.85, alpha: 1)]
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        ctx.interpolationQuality = .none
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        let ink = night ? NSColor.white : NSColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1)
        func text(_ s: String, _ x: Double, _ y: Double, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1, mono: Bool = false, centered: Bool = false, right: Bool = false) {
            let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink.withAlphaComponent(alpha)])
            a.draw(at: CGPoint(x: right ? x - a.size().width : centered ? x - a.size().width / 2 : x, y: y))
        }
        func tile(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            let p = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: 18, cornerHeight: 18, transform: nil)
            ctx.addPath(p); ctx.setFillColor(ink.withAlphaComponent(night ? 0.1 : 0.06).cgColor); ctx.fillPath()
        }
        // Header
        text(m.title, 60, Double(H) - 118, size: 58, weight: .heavy)
        text("with Claude Code, as it happened on my desktop", 62, Double(H) - 156, size: 21, weight: .semibold, alpha: 0.78)
        text("Gremlets", Double(W) - 60, Double(H) - 108, size: 20, weight: .bold, alpha: 0.7, right: true)

        // Numbers
        let hours = m.minutes / 60
        var stats: [(String, String)] = [
            ("\(m.edits)", "file edits · a leaf each"),
            ("\(m.tasks)", "tasks finished · a flower each"),
            (hours >= 10 ? "\(Int(hours.rounded()))" : String(format: "%.1f", hours), "hours beside Claude"),
            ("\(m.activeDays)", "day\(m.activeDays == 1 ? "" : "s") you worked with Claude"),
        ]
        if m.streak >= 2 { stats.append(("\(m.streak)", "days in a row at best")) }
        if m.sessions > 0 { stats.append(("\(m.sessions)", "session\(m.sessions == 1 ? "" : "s") · longest \(SessionRecord.duration(m.longestSession))")) }
        if m.testsGreen > 0 { stats.append(("\(m.testsGreen)", "green test run\(m.testsGreen == 1 ? "" : "s")")) }
        if m.houses > 0 { stats.append(("\(m.houses)", "building\(m.houses == 1 ? "" : "s") added to the village")) }
        if m.gems > 0 { stats.append(("\(m.gems)", "gem\(m.gems == 1 ? "" : "s") dug up")) }
        let tileW = 468.0, tileH = 104.0, top = Double(H) - 200
        for (i, s) in stats.prefix(6).enumerated() {
            let x = 60 + Double(i % 2) * (tileW + 24), y = top - Double(i / 2) * (tileH + 16) - tileH
            tile(x, y, tileW, tileH)
            text(s.0, x + 24, y + 44, size: 40, weight: .bold, mono: true)
            text(s.1, x + 24, y + 18, size: 15, weight: .medium, alpha: 0.75)
        }
        let rows = Int(ceil(Double(min(6, stats.count)) / 2))
        var y = top - Double(rows) * (tileH + 16) - 40

        // Calendar: Monday first, each day shaded by its edits.
        text("Every day", 60, y - 28, size: 22, weight: .heavy)
        let cell = 58.0, gap = 8.0
        let cal = Calendar.current
        let firstWD = (cal.component(.weekday, from: m.firstDay) + 5) % 7   // 0 = Monday
        let maxEdits = max(1, m.days.values.map(\.edits).max() ?? 1)
        let todayC = cal.dateComponents([.year, .month, .day], from: Date())
        let gridTop = y - 44
        for (i, n) in ["M", "T", "W", "T", "F", "S", "S"].enumerated() { text(n, 60 + Double(i) * (cell + gap) + cell / 2, gridTop - 16, size: 12, weight: .bold, alpha: 0.5, centered: true) }
        for d in 1...m.dayCount {
            let slot = firstWD + d - 1, col = slot % 7, row = slot / 7
            let x = 60 + Double(col) * (cell + gap), cy = gridTop - 24 - Double(row + 1) * (cell + gap) + gap
            let day = m.days[d]
            let isFuture = (todayC.year ?? 0, todayC.month ?? 0, todayC.day ?? 0) < (m.year, m.month, d)
            let level = day.map { Double($0.edits) / Double(maxEdits) } ?? 0
            let p = CGPath(roundedRect: CGRect(x: x, y: cy, width: cell, height: cell), cornerWidth: 10, cornerHeight: 10, transform: nil)
            ctx.addPath(p)
            if let day, day.edits > 0 || day.tasks > 0 {
                ctx.setFillColor(CGColor(red: 0.36 - 0.1 * level, green: 0.72 + 0.1 * level, blue: 0.28, alpha: 0.35 + 0.65 * max(0.15, level)))
            } else {
                ctx.setFillColor(ink.withAlphaComponent(isFuture ? 0.03 : 0.08).cgColor)
            }
            ctx.fillPath()
            let isToday = todayC.year == m.year && todayC.month == m.month && todayC.day == d
            if isToday { ctx.addPath(p); ctx.setStrokeColor(ink.withAlphaComponent(0.8).cgColor); ctx.setLineWidth(2); ctx.strokePath() }
            let strong = (day?.edits ?? 0) > 0
            NSAttributedString(string: "\(d)", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold),
                                                               .foregroundColor: strong ? NSColor.white : ink.withAlphaComponent(isFuture ? 0.3 : 0.6)])
                .draw(at: CGPoint(x: x + 8, y: cy + cell - 22))
            if let day, day.tasks > 0 {
                ctx.setFillColor(CGColor(red: 1, green: 0.55, blue: 0.75, alpha: 1))
                for k in 0..<min(4, day.tasks) { ctx.fillEllipse(in: CGRect(x: x + 8 + Double(k) * 9, y: cy + 8, width: 6, height: 6)) }
            }
        }
        let gridRows = Int(ceil(Double(firstWD + m.dayCount) / 7))
        let gridBottom = gridTop - 24 - Double(gridRows) * (cell + gap) + gap
        if let b = m.busiest {
            let f = DateFormatter(); f.dateFormat = "EEEE d"
            let date = cal.date(byAdding: .day, value: b.day - 1, to: m.firstDay) ?? m.firstDay
            text("Busiest day: \(f.string(from: date)), \(b.edits) edits", 60, gridBottom - 30, size: 15, weight: .semibold, alpha: 0.75)
        }

        // The trees, to the right of the calendar.
        let tx = 60 + 7 * (cell + gap) + 36
        text(m.trees.isEmpty ? "No trees yet" : "Trees this month", tx, y - 28, size: 22, weight: .heavy)
        let now = Date().timeIntervalSince1970
        var ty = gridTop - 10
        for (t, edits) in m.trees.prefix(4) {
            let layout = BonsaiGeometry.layout(t)
            let fit = min(1, 96 / max(1, layout.bounds.h), 130 / max(1, layout.bounds.w))
            let (img, anchor) = BonsaiArt.image(t, layout: layout, scale: fit, month: m.month, night: night, ageDays: t.ageDays(now: now))
            let w = Double(img.width) * 3, h = Double(img.height) * 3
            let base = ty - 110
            ctx.draw(img, in: CGRect(x: tx + 70 - anchor.x * w, y: base + layout.potHeight * fit - anchor.y * h, width: w, height: h))
            text(t.project, tx + 160, base + 58, size: 19, weight: .heavy)
            let line = edits.map { "\($0) edit\($0 == 1 ? "" : "s") this month" } ?? "\(t.species.name) · \(t.sessions) session\(t.sessions == 1 ? "" : "s")"
            text(line, tx + 160, base + 34, size: 14, weight: .medium, alpha: 0.7)
            text("\(t.blooms) ✿  \(t.fruit) ●  \(t.edits) leaves", tx + 160, base + 12, size: 13, weight: .medium, alpha: 0.55)
            ty -= 126
        }
        y = min(gridBottom, ty) - 60
        text("Every edit grew a leaf, every finished task a flower, every green test run a golden fruit.", 60, max(40, y), size: 15, weight: .semibold, alpha: 0.6)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        return (image, CGSize(width: W, height: H))
    }
}
