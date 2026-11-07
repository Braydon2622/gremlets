import AppKit
import GremletsCore

/// The scrapbook: one page a day, with a flower pressed into it (a daisy if they picked one, otherwise whatever the
/// moss gave them that day), what Claude worked on, and what the Gremlets got up to in the garden. Open from the menu
/// (Open Scrapbook) or at http://127.0.0.1:47920/scrapbook. Stays on your Mac.
enum Scrapbook {
    /// Counts the day's garden moments into the log.
    static func record(_ events: [SproutEvent], moss: [MossEvent], into log: DayLog) {
        var picked: [MossSprout.Kind: Int] = [:]
        var fireflies = 0, boxed = 0, tufts = 0
        for e in events {
            switch e {
            case .picked(let k, _, _): picked[k, default: 0] += 1
            case .ate: picked[.berries, default: 0] += 1
            case .seedsBlown(_, _, let by) where by != nil: picked[.dandelion, default: 0] += 1
            case .caughtFirefly: fireflies += 1
            case .boxed: boxed += 1
            default: break
            }
        }
        for e in moss { if case .planted = e { tufts += 1 } }
        guard !picked.isEmpty || fireflies + boxed + tufts > 0 else { return }
        log.add { d in
            d.daisies = (d.daisies ?? 0) + picked[.daisy, default: 0]
            d.mushrooms = (d.mushrooms ?? 0) + picked[.mushroom, default: 0]
            d.berries = (d.berries ?? 0) + picked[.berries, default: 0]
            d.dandelions = (d.dandelions ?? 0) + picked[.dandelion, default: 0]
            d.fireflies = (d.fireflies ?? 0) + fireflies
            d.tufts = (d.tufts ?? 0) + tufts
            d.boxed = (d.boxed ?? 0) + boxed
        }
    }

    /// The flower pressed into a day's page.
    static func pressed(_ d: DayLog.Day) -> MossSprout.Kind? {
        if (d.daisies ?? 0) > 0 { return .daisy }
        if (d.dandelions ?? 0) > 0 { return .dandelion }
        if (d.mushrooms ?? 0) > 0 { return .mushroom }
        if (d.berries ?? 0) > 0 { return .berries }
        return nil
    }

    private static func png(_ img: CGImage) -> String {
        let rep = NSBitmapImageRep(cgImage: img)
        return rep.representation(using: .png, properties: [:]).map { "data:image/png;base64," + $0.base64EncodedString() } ?? ""
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "a \(one)" : "\(n) \(many)" }

    /// The lines on a page, in plain words.
    static func lines(_ d: DayLog.Day) -> [String] {
        var out: [String] = []
        if d.tasks > 0 || !(d.projects ?? [:]).isEmpty {
            let names = (d.projects ?? [:]).sorted { $0.value > $1.value }.prefix(3).map(\.key)
            let on = names.isEmpty ? "" : " on " + ListFormatter.localizedString(byJoining: names)
            out.append(d.tasks > 0 ? "Claude finished \(plural(d.tasks, "task", "tasks"))\(on)." : "Claude worked\(on).")
        }
        var finds: [String] = []
        if let n = d.daisies, n > 0 { finds.append(plural(n, "daisy", "daisies")) }
        if let n = d.mushrooms, n > 0 { finds.append(plural(n, "mushroom", "mushrooms")) }
        if !finds.isEmpty { out.append("Picked \(ListFormatter.localizedString(byJoining: finds)) from the moss.") }
        if let n = d.berries, n > 0 { out.append("Ate \(n == 1 ? "a sprig" : "\(n) sprigs") of berries.") }
        if let n = d.dandelions, n > 0 { out.append("Blew \(plural(n, "dandelion clock", "dandelion clocks")); the seeds flew off to grow more moss.") }
        if let n = d.boxed, n > 0 { out.append("Put \(plural(n, "daisy", "daisies")) in the window box at home.") }
        if let n = d.tufts, n > 0 { out.append("Planted \(plural(n, "tuft", "tufts")) of moss.") }
        for a in d.anniversaries ?? [] { out.append("\(a). A flower crown all day.") }
        if let n = d.fireflies, n > 0 { out.append("Caught \(plural(n, "firefly", "fireflies")) after dark, and let \(n == 1 ? "it" : "them") go.") }
        return out
    }

    static func page(log: DayLog) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        let days = log.recent(30).reversed().filter { !lines($0.day).isEmpty }
        var pages = ""
        for (i, entry) in days.enumerated() {
            let flower = pressed(entry.day).map { k in
                "<img class=\"flower\" alt=\"pressed \(k.rawValue)\" src=\"\(png(SproutArt.image(k, stage: 2, night: false)))\" style=\"transform: rotate(\(i % 2 == 0 ? -12 : 9)deg)\">"
            } ?? "<img class=\"flower leafy\" alt=\"pressed shoot\" src=\"\(png(SproutArt.image(.daisy, stage: 1, night: false)))\">"
            let body = lines(entry.day).map { "<li>\(esc($0))</li>" }.joined()
            pages += "<section class=\"page\">\(flower)<h2>\(esc(f.string(from: entry.date)))</h2><ul>\(body)</ul></section>"
        }
        if pages.isEmpty {
            pages = "<section class=\"page empty\"><h2>Nothing pressed yet</h2><ul><li>Pages fill in as the Gremlets pick things from the moss, catch fireflies and plant moss, and as Claude gets work done.</li></ul></section>"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Gremlets Scrapbook</title>
        <style>
        :root { --paper:#f6efdf; --ink:#4a3b2a; --soft:#8a7458; --bg:#2f3a2c; --tape:rgba(255,236,170,.7); }
        body { margin:0; background:var(--bg); font:16px/1.5 Georgia, 'Iowan Old Style', serif; color:var(--ink); }
        header { text-align:center; color:#e9e2cf; padding:32px 16px 8px; }
        header h1 { margin:0; font-size:30px; letter-spacing:.5px; }
        header p { margin:6px 0 0; color:#b9c4a8; font-size:14px; }
        main { display:grid; grid-template-columns:repeat(auto-fill,minmax(280px,1fr)); gap:22px; max-width:1100px; margin:0 auto; padding:24px 16px 48px; }
        .page { position:relative; background:var(--paper); border-radius:4px; padding:22px 22px 18px 92px; min-height:150px;
                box-shadow:0 2px 0 #d8ccb0, 0 10px 24px rgba(0,0,0,.35); }
        .page:nth-child(odd) { transform:rotate(-.6deg); } .page:nth-child(even) { transform:rotate(.5deg); }
        .page::before { content:""; position:absolute; top:-10px; left:28px; width:62px; height:20px; background:var(--tape); transform:rotate(-6deg); }
        .flower { position:absolute; left:18px; top:30px; width:54px; image-rendering:pixelated; filter:saturate(.75) sepia(.18); opacity:.92; }
        h2 { margin:0 0 8px; font-size:17px; color:var(--soft); font-weight:normal; font-style:italic; }
        ul { margin:0; padding-left:18px; } li { margin:3px 0; }
        .empty { padding-left:22px; }
        </style></head><body>
        <header><h1>Scrapbook</h1><p>A page a day from the moss: what grew, what was picked, and what Claude got done.</p></header>
        <main>\(pages)</main></body></html>
        """
    }
}
