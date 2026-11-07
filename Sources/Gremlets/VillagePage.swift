import AppKit
import GremletsCore

/// `gremlet village-page [folder]`: a small read-only web page of your village as it is right now, to put online
/// (drag the folder onto Netlify, GitHub Pages, anywhere static): the village postcard, the numbers behind it, the
/// Gremlets who live there, and a share preview for X and iMessage.
///
/// Only counts and Gremlet names go on the page: no project names, file names, city or anything from your sessions.
enum VillagePage {
    struct Stats { let tasks, trees, buildings, edits, gems, mossMinutes, sessions: Int }

    static func stats(world: World) -> Stats {
        let g = world.grove
        let homes = g.village.filter { Biome(rawValue: $0.biome) != nil }
        let edits = homes.reduce(0) { $0 + $1.blocks } + world.bonsaiBook.trees.reduce(0) { $0 + $1.edits }
        return Stats(tasks: g.tasks, trees: world.bonsaiBook.trees.count, buildings: world.villageOn ? homes.count : 0, edits: edits,
                     gems: g.gems.values.reduce(0, +), mossMinutes: Int(world.mossMinutes),
                     sessions: world.bonsaiBook.trees.reduce(0) { $0 + $1.sessions })
    }

    /// Writes index.html, village.png and a portrait per Gremlet into `dir`. Returns the page's file URL.
    static func write(to dir: URL, world: World, species: [String: LoadedSpecies]) throws -> URL {
        guard let (image, _) = VillageSnapshot.render(world: world, species: species) else { throw CocoaError(.fileWriteUnknown) }
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("img", isDirectory: true), withIntermediateDirectories: true)
        try png(image).write(to: dir.appendingPathComponent("village.png"))
        var residents: [(name: String, element: String, file: String)] = []
        for id in Set(world.creatures.map(\.species.id)).sorted() {
            guard let sp = species[id], let frame = sp.frames.first else { continue }
            let file = "img/\(id).png"
            try png(frame).write(to: dir.appendingPathComponent(file))
            residents.append((sp.info.name, sp.info.element, file))
        }
        let s = stats(world: world)
        let html = page(stats: s, residents: residents, updated: Date())
        let url = dir.appendingPathComponent("index.html")
        try Data(html.utf8).write(to: url)
        return url
    }

    private static func png(_ img: CGImage) throws -> Data {
        guard let d = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return d
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func page(stats s: Stats, residents: [(name: String, element: String, file: String)], updated: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .none
        let day = esc(f.string(from: updated))
        func tile(_ n: Int, _ one: String, _ many: String, _ note: String) -> String {
            "<div class=\"tile\"><b>\(n.formatted())</b><span>\(n == 1 ? one : many)</span><small>\(note)</small></div>"
        }
        var tiles = [
            tile(s.tasks, "Claude task", "Claude tasks", "each one grew the grove"),
            tile(s.sessions, "session", "sessions", "every session adds a branch"),
            tile(s.edits, "file edit", "file edits", "a block placed for each"),
            tile(s.trees, "project tree", "project trees", "one bonsai per project"),
            tile(s.buildings, "building", "buildings", "built a block at a time"),
        ]
        tiles.append(tile(s.gems, "gem", "gems", "dug up or found on treasure runs"))
        tiles.append(tile(s.mossMinutes, "minute of moss", "minutes of moss", "the desktop grows over while Claude works"))
        // Only what's happened: an empty "0" tile reads like something's broken.
        let counts = [s.tasks, s.sessions, s.edits, s.trees, s.buildings, s.gems, s.mossMinutes]
        tiles = zip(tiles, counts).filter { $0.1 > 0 }.map(\.0)
        let folks = residents.map {
            "<li><img src=\"\(esc($0.file))\" alt=\"\" width=\"96\" height=\"96\"><b>\(esc($0.name))</b><span>\(esc($0.element))</span></li>"
        }.joined(separator: "\n      ")
        let desc = "A village grown by Claude Code sessions: \(s.tasks.formatted()) tasks, \(s.edits.formatted()) file edits, \(s.trees) project trees."
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>My Gremlets village</title>
        <meta name="description" content="\(esc(desc))">
        <meta property="og:title" content="My Gremlets village">
        <meta property="og:description" content="\(esc(desc))">
        <meta property="og:image" content="village.png">
        <meta name="twitter:card" content="summary_large_image">
        <style>
          :root { --bg: #f6f1e7; --card: #fffaf0; --ink: #1f2438; --soft: #5d6378; --line: #e4dccb; --accent: #4e8b3a; }
          @media (prefers-color-scheme: dark) { :root { --bg: #14161f; --card: #1d2030; --ink: #eef0f7; --soft: #a3a9bd; --line: #2c3045; --accent: #8bd66a; } }
          * { box-sizing: border-box; }
          body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
          main { max-width: 1040px; margin: 0 auto; padding: 32px 16px 56px; }
          h1 { font-size: clamp(28px, 5vw, 44px); line-height: 1.1; margin: 0 0 6px; letter-spacing: -0.02em; }
          .lede { color: var(--soft); margin: 0 0 22px; font-size: 18px; }
          .postcard { width: 100%; height: auto; display: block; border-radius: 14px; border: 1px solid var(--line); image-rendering: pixelated; }
          .tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; margin: 22px 0 34px; }
          .tile { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 14px 16px; }
          .tile b { display: block; font-size: 30px; font-variant-numeric: tabular-nums; line-height: 1.1; }
          .tile span { display: block; font-weight: 600; }
          .tile small { color: var(--soft); font-size: 13px; }
          h2 { font-size: 20px; margin: 0 0 12px; }
          ul { list-style: none; padding: 0; margin: 0 0 34px; display: flex; flex-wrap: wrap; gap: 12px; }
          li { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 10px 14px 12px; text-align: center; min-width: 120px; }
          li img { display: block; margin: 0 auto 4px; image-rendering: pixelated; }
          li span { display: block; color: var(--soft); font-size: 13px; text-transform: capitalize; }
          footer { color: var(--soft); font-size: 14px; border-top: 1px solid var(--line); padding-top: 16px; }
          a { color: var(--accent); }
        </style>
        </head>
        <body>
        <main>
          <h1>My Gremlets village</h1>
          <p class="lede">Gremlets are little spirits that live on my Mac's desktop. Every time Claude Code works on one of my projects, they build: a little hut hangs beside the terminal Claude works in, its tree grows with every session, and they garden the moss while it works. This is what they've made so far.</p>
          <img class="postcard" src="village.png" alt="A pixel-art scene: a little house and hammock hanging from the top, a plant in the corner, project bonsai trees on brackets and the Gremlets out front" width="1600" height="660">
          <div class="tiles">
            \(tiles.joined(separator: "\n    "))
          </div>
          <h2>Who lives here</h2>
          <ul>
              \(folks)
          </ul>
          <footer>Updated \(day). A snapshot, not a live feed: no project names or anything from the sessions themselves are on this page. <a href="https://braydonhartai.com/gremlets/">Meet the Gremlets</a>.</footer>
        </main>
        </body>
        </html>
        """
    }
}
