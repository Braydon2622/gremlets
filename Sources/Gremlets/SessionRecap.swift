import AppKit
import GremletsCore

/// What one Claude Code session did, minute by minute: edits, other tools, failures, finished tasks, test runs,
/// helpers. Kept while the session runs and for the last thirty sessions after (UserDefaults `sessions.v1`), so a
/// recap card can be drawn when it ends or later from the menu (`gremlet recap`).
struct SessionRecord: Codable {
    struct Minute: Codable { var edits = 0; var tools = 0; var fails = 0 }
    var session: String
    var project: String
    var started: TimeInterval
    var ended: TimeInterval?
    /// The project's tree as it was when the session began (nil when this session planted it).
    var before: Bonsai?
    var minutes: [Minute] = []
    var tasks: [Int] = []        // minute of each finished task
    var testsPassed: [Int] = []  // minute of each green test run
    var testsFailed: [Int] = []
    var helpers = 0
    var attention = 0

    var edits: Int { minutes.reduce(0) { $0 + $1.edits } }
    var toolCalls: Int { minutes.reduce(0) { $0 + $1.edits + $1.tools } }
    var fails: Int { minutes.reduce(0) { $0 + $1.fails } }
    var seconds: TimeInterval { (ended ?? Date().timeIntervalSince1970) - started }

    /// Worth a card: something happened, or it ran a while.
    var worthRecapping: Bool { edits >= 10 || !tasks.isEmpty && seconds >= 15 * 60 }

    mutating func minute(_ now: TimeInterval = Date().timeIntervalSince1970) -> Int {
        let m = max(0, min(1440, Int((now - started) / 60)))
        while minutes.count <= m { minutes.append(Minute()) }
        return m
    }

    /// A made-up 48-minute session for `gremlet recap --sample`, so the card can be seen before a real session ends.
    static func sample(project: String = "Gremlets") -> (record: SessionRecord, after: Bonsai) {
        let now = Date().timeIntervalSince1970
        var tree = Bonsai(project: project, now: now - 86400 * 9)
        for (n, e) in [31, 18, 12].enumerated() {
            _ = tree.startSession("sample\(n)", now: tree.firstSeen + Double(n) * 7200)
            tree.branches[n].edits = e
            tree.branches[n].blooms = n == 0 ? 2 : 1
        }
        tree.branches[0].fruit = 1
        tree.endSession()
        var r = SessionRecord(session: "sample", project: project, started: now - 48 * 60, before: tree)
        r.ended = now
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        for m in 0..<49 {
            var minute = Minute()
            let busy = m < 4 ? 0.4 : m < 22 ? 1.0 : m < 30 ? 0.3 : 1.0
            minute.edits = Int((next() * 4 * busy).rounded())
            minute.tools = Int((next() * 3 + (m < 4 ? 3 : 0)).rounded())
            if m == 20 || m == 27 { minute.fails = 1 }
            r.minutes.append(minute)
        }
        r.testsFailed = [20]; r.testsPassed = [31, 44]; r.tasks = [12, 33, 47]; r.helpers = 2; r.attention = 1
        var after = tree
        _ = after.startSession("sample-live", now: r.started)
        let b = after.branches.count - 1
        after.branches[b].edits = r.edits; after.branches[b].blooms = r.tasks.count; after.branches[b].fruit = r.testsPassed.count
        after.endSession()
        return (r, after)
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m < 1 { return "under a minute" }
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(m % 60 == 0 ? "" : "\(m % 60) min")".trimmingCharacters(in: .whitespaces)
    }
}

final class SessionLog {
    private let key = "sessions.v1"
    private var active: [String: SessionRecord] = [:]
    private(set) var recent: [SessionRecord] = []

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let v = try? JSONDecoder().decode([SessionRecord].self, from: d) { recent = v }
    }

    func begin(_ session: String, project: String, before: Bonsai?) {
        if let r = active[session], r.project == project { return }   // a second prompt in the same session
        active[session] = SessionRecord(session: session, project: project, started: Date().timeIntervalSince1970, before: before)
    }

    func tool(_ session: String, edit: Bool, failed: Bool, test: Bool) {
        guard var r = active[session] else { return }
        let m = r.minute()
        if failed { r.minutes[m].fails += 1 } else if edit { r.minutes[m].edits += 1 } else { r.minutes[m].tools += 1 }
        if test { if failed { r.testsFailed.append(m) } else { r.testsPassed.append(m) } }
        active[session] = r
    }

    func task(_ session: String) { guard var r = active[session] else { return }; let m = r.minute(); r.tasks.append(m); active[session] = r }
    func helper(_ session: String) { active[session]?.helpers += 1 }
    func attention(_ session: String) { active[session]?.attention += 1 }

    /// Closes the record and keeps it. Returns it, so the platform can draw a card.
    @discardableResult
    func end(_ session: String) -> SessionRecord? {
        guard var r = active.removeValue(forKey: session) else { return nil }
        r.ended = Date().timeIntervalSince1970
        _ = r.minute(r.ended!)
        recent.append(r)
        if recent.count > 30 { recent.removeFirst(recent.count - 30) }
        if let d = try? JSONEncoder().encode(recent) { UserDefaults.standard.set(d, forKey: key) }
        return r
    }

    func last(project: String?) -> SessionRecord? {
        guard let project, !project.isEmpty else { return recent.last }
        return recent.last { $0.project == project }
    }
}

/// The card: the tree before and after the session at the same scale, the numbers, and a minute-by-minute strip of
/// the session (edits as bars, flowers for finished tasks, gold for green tests, red for failures). 16:9, for posting.
enum SessionRecapCard {
    static func make(_ r: SessionRecord, after: Bonsai?, world: World, copy: Bool = false) -> URL? {
        guard let (image, size) = render(r, after: after, world: world) else { return nil }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Gremlets/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let safe = r.project.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent("Session \(safe) \(f.string(from: Date(timeIntervalSince1970: r.started))).png")
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else { return nil }
        if copy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: size)])
        }
        return url
    }

    static func render(_ r: SessionRecord, after: Bonsai?, world: World) -> (image: CGImage, size: CGSize)? {
        let W = 1200, H = 675
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let night = world.isNight
        let sky = night ? [CGColor(red: 0.08, green: 0.1, blue: 0.24, alpha: 1), CGColor(red: 0.22, green: 0.16, blue: 0.36, alpha: 1)]
                        : [CGColor(red: 0.93, green: 0.96, blue: 0.99, alpha: 1), CGColor(red: 0.99, green: 0.94, blue: 0.86, alpha: 1)]
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        ctx.interpolationQuality = .none
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        let ink = night ? NSColor.white : NSColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1)
        func text(_ s: String, _ x: Double, _ y: Double, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1, mono: Bool = false, centered: Bool = false) {
            let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink.withAlphaComponent(alpha)])
            a.draw(at: CGPoint(x: centered ? x - a.size().width / 2 : x, y: y))
        }
        // Header.
        let day = DateFormatter(); day.dateFormat = "EEE d MMM, HH:mm"
        let n = after?.sessions ?? (r.before?.sessions ?? 0) + 1
        text("\(r.project) · session \(n)", 56, Double(H) - 92, size: 36, weight: .heavy)
        text("\(day.string(from: Date(timeIntervalSince1970: r.started))) · \(SessionRecord.duration(r.seconds)) with Claude Code", 58, Double(H) - 124, size: 18, weight: .semibold, alpha: 0.8)

        // The tree, before and after, on one shelf at the same scale.
        let shelfY = 230.0
        let now = Date().timeIntervalSince1970
        let month = world.month
        let afterLayout = after.map { BonsaiGeometry.layout($0) }
        let beforeLayout = r.before.map { BonsaiGeometry.layout($0) }
        let afterImg = after.flatMap { t in afterLayout.map { BonsaiArt.image(t, layout: $0, scale: 1, month: month, night: night, ageDays: t.ageDays(now: now)) } }
        let beforeImg = r.before.flatMap { t in beforeLayout.map { BonsaiArt.image(t, layout: $0, scale: 1, month: month, night: night, ageDays: t.ageDays(now: r.started)) } }
        let big = afterImg?.0 ?? beforeImg?.0
        var mult = 3.0
        if let big { mult = max(2, min(5, (min(330 / Double(big.width), 300 / Double(big.height))).rounded(.down))) }
        let plank = BonsaiArt.bracket(widthPx: 190, hanging: false)
        ctx.draw(plank, in: CGRect(x: 56, y: shelfY - Double(plank.height) * 3 + 6, width: Double(plank.width) * 3, height: Double(plank.height) * 3))
        // The image's anchor is the soil line (on a window the pot hangs over the title bar); here the pot stands on
        // the plank, so each tree is lifted by its own pot height.
        let beforeX = 170.0, afterX = 470.0, standY = shelfY + 4
        if let (img, anchor) = beforeImg, let layout = beforeLayout {
            let w = Double(img.width) * mult, h = Double(img.height) * mult
            ctx.setAlpha(0.85)
            ctx.draw(img, in: CGRect(x: beforeX - anchor.x * w, y: standY + layout.potHeight * mult / 3 - anchor.y * h, width: w, height: h))
            ctx.setAlpha(1)
            text("before", beforeX, shelfY - 46, size: 13, weight: .bold, alpha: 0.6, centered: true)
        } else {
            text("planted this session", beforeX, shelfY - 46, size: 13, weight: .bold, alpha: 0.6, centered: true)
        }
        // A small arrow between them.
        ctx.setStrokeColor(ink.withAlphaComponent(0.45).cgColor); ctx.setLineWidth(3); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 300, y: shelfY + 70)); ctx.addLine(to: CGPoint(x: 345, y: shelfY + 70))
        ctx.move(to: CGPoint(x: 333, y: shelfY + 82)); ctx.addLine(to: CGPoint(x: 345, y: shelfY + 70)); ctx.addLine(to: CGPoint(x: 333, y: shelfY + 58))
        ctx.strokePath()
        if let (img, anchor) = afterImg, let layout = afterLayout {
            let w = Double(img.width) * mult, h = Double(img.height) * mult
            ctx.draw(img, in: CGRect(x: afterX - anchor.x * w, y: standY + layout.potHeight * mult / 3 - anchor.y * h, width: w, height: h))
            text("after", afterX, shelfY - 46, size: 13, weight: .bold, alpha: 0.6, centered: true)
        }

        // The numbers.
        var rows: [(String, String)] = [("\(r.edits)", "file edit\(r.edits == 1 ? "" : "s") · a leaf each")]
        rows.append(("\(r.tasks.count)", "task\(r.tasks.count == 1 ? "" : "s") finished · a flower each"))
        if !r.testsPassed.isEmpty { rows.append(("\(r.testsPassed.count)", "green test run\(r.testsPassed.count == 1 ? "" : "s") · golden fruit")) }
        if !r.testsFailed.isEmpty { rows.append(("\(r.testsFailed.count)", "test run\(r.testsFailed.count == 1 ? "" : "s") that failed first")) }
        if r.helpers > 0 { rows.append(("\(r.helpers)", "subagent\(r.helpers == 1 ? "" : "s") helped")) }
        let other = r.toolCalls - r.edits
        if other > 0 { rows.append(("\(other)", "other tool call\(other == 1 ? "" : "s") (reads, searches, commands)")) }
        if r.attention > 0 { rows.append(("\(r.attention)", "time\(r.attention == 1 ? "" : "s") Claude waited for you")) }
        var y = Double(H) - 190
        for (big, small) in rows.prefix(6) {
            text(big, 700, y, size: 30, weight: .bold, mono: true)
            text(small, 800, y + 8, size: 16, weight: .medium, alpha: 0.78)
            y -= 46
        }

        // The heartbeat strip: one bar per minute.
        let stripX = 56.0, stripW = Double(W) - 112, stripY = 64.0, stripH = 64.0
        let count = max(1, r.minutes.count)
        let barW = stripW / Double(count)
        let maxEdits = max(1, r.minutes.map { $0.edits + $0.tools }.max() ?? 1)
        ctx.setFillColor(ink.withAlphaComponent(0.08).cgColor)
        ctx.fill(CGRect(x: stripX, y: stripY - 2, width: stripW, height: 2))
        for (i, m) in r.minutes.enumerated() {
            let x = stripX + Double(i) * barW
            let total = m.edits + m.tools
            guard total > 0 || m.fails > 0 else { continue }
            let h = max(3, stripH * Double(total) / Double(maxEdits))
            let editShare = total > 0 ? Double(m.edits) / Double(total) : 0
            ctx.setFillColor(CGColor(red: 0.45, green: 0.72, blue: 0.35, alpha: 0.5)); ctx.fill(CGRect(x: x + 0.5, y: stripY, width: max(1, barW - 1), height: h))
            ctx.setFillColor(CGColor(red: 0.36, green: 0.71, blue: 0.27, alpha: 1)); ctx.fill(CGRect(x: x + 0.5, y: stripY, width: max(1, barW - 1), height: h * editShare))
            if m.fails > 0 { ctx.setFillColor(CGColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 0.9)); ctx.fill(CGRect(x: x + 0.5, y: stripY, width: max(1, barW - 1), height: 3)) }
        }
        func dot(_ minute: Int, _ color: CGColor, _ lift: Double, size: Double) {
            let x = stripX + (Double(minute) + 0.5) * barW
            ctx.setFillColor(color); ctx.fillEllipse(in: CGRect(x: x - size / 2, y: stripY + stripH + lift, width: size, height: size))
        }
        for m in r.testsFailed { dot(m, CGColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 1), 4, size: 7) }
        for m in r.testsPassed { dot(m, CGColor(red: 1, green: 0.78, blue: 0.3, alpha: 1), 4, size: 9) }
        for m in r.tasks { dot(m, CGColor(red: 1, green: 0.55, blue: 0.75, alpha: 1), 14, size: 9) }
        text("start", stripX, stripY - 20, size: 11, weight: .semibold, alpha: 0.55)
        let endLabel = NSAttributedString(string: SessionRecord.duration(r.seconds), attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.55)])
        endLabel.draw(at: CGPoint(x: stripX + stripW - endLabel.size().width, y: stripY - 20))
        text("edits per minute  ·  ● task finished  ● tests green  ● tests failed", stripX, stripY + stripH + 28, size: 11, weight: .semibold, alpha: 0.5)
        // Colour the legend dots.
        for (i, c) in [CGColor(red: 1, green: 0.55, blue: 0.75, alpha: 1), CGColor(red: 1, green: 0.78, blue: 0.3, alpha: 1), CGColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 1)].enumerated() {
            let probe = ["edits per minute  ·  ", "edits per minute  ·  ● task finished  ", "edits per minute  ·  ● task finished  ● tests green  "][i]
            let w = NSAttributedString(string: probe, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).size().width
            ctx.setFillColor(sky[1]); ctx.fill(CGRect(x: stripX + w - 1, y: stripY + stripH + 28, width: 11, height: 14))
            ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: stripX + w, y: stripY + stripH + 31, width: 8, height: 8))
        }
        NSAttributedString(string: "Grown by my Claude Code sessions  ·  Gremlets", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.5)])
            .draw(at: CGPoint(x: Double(W) - 330, y: 18))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        return (image, CGSize(width: W, height: H))
    }
}
