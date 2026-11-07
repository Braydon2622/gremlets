import Foundation

/// The codebase castle: the project Claude is working on, built as a little castle on top of its terminal window.
/// The three biggest top-level folders are towers (taller with more files, a pointed roof in the colour of their main
/// language), the files at the root make the keep in the middle, and every edit Claude makes adds a little height to
/// that folder's tower. The keep's flat top is a lookout the Gremlets climb up to.
///
/// The app reads the file list itself (git ls-files, on your Mac); only folder names and file extensions are used,
/// and nothing about it is drawn as text or leaves the Mac.
public struct CastleTower: Codable, Equatable, Sendable {
    /// The top-level folder ("" for files at the root: the keep).
    public var name: String
    public var files: Int
    /// Language → file count.
    public var mix: [String: Int]
    /// Edits Claude has made in this folder (each adds a block).
    public var edits: Int = 0

    public init(name: String, files: Int, mix: [String: Int], edits: Int = 0) {
        self.name = name; self.files = files; self.mix = mix; self.edits = edits
    }

    public var isKeep: Bool { name.isEmpty }
    public var mainLanguage: String { mix.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? "other" }
}

public struct Castle: Codable, Equatable, Sendable {
    public var project: String
    /// Left to right: the biggest folders toward the middle, the keep in the centre.
    public var towers: [CastleTower]

    /// A small, tidy castle: the keep and the three biggest folders.
    public static let maxTowers = 3
    public static let towerWidth = 18.0, keepWidth = 30.0, gap = 6.0

    /// A language for a file extension (what colours its bricks).
    public static func language(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "js", "mjs", "cjs", "jsx": return "js"
        case "ts", "tsx": return "ts"
        case "py": return "py"
        case "rb": return "rb"
        case "go": return "go"
        case "rs": return "rust"
        case "java", "kt", "kts": return "jvm"
        case "c", "h", "cpp", "cc", "hpp", "m", "mm": return "c"
        case "html", "htm": return "html"
        case "css", "scss", "sass", "less": return "css"
        case "md", "txt", "rst": return "docs"
        case "json", "yaml", "yml", "toml", "plist", "xml": return "data"
        case "sh", "bash", "zsh": return "shell"
        case "sol": return "sol"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "mp4", "mov", "wav", "mp3": return "media"
        default: return "other"
        }
    }

    /// Builds the castle from a project's file list (paths relative to its root).
    public static func from(project: String, paths: [String]) -> Castle {
        var byDir: [String: CastleTower] = [:]
        for p in paths {
            let parts = p.split(separator: "/", omittingEmptySubsequences: true)
            guard let last = parts.last else { continue }
            let dir = parts.count > 1 ? String(parts[0]) : ""
            if dir.hasPrefix(".") { continue }
            let ext = last.contains(".") ? String(last.split(separator: ".").last ?? "") : ""
            var t = byDir[dir] ?? CastleTower(name: dir, files: 0, mix: [:])
            t.files += 1
            t.mix[language(ext), default: 0] += 1
            byDir[dir] = t
        }
        let keep = byDir.removeValue(forKey: "") ?? CastleTower(name: "", files: 0, mix: [:])
        let folders = byDir.values.sorted { $0.files > $1.files || ($0.files == $1.files && $0.name < $1.name) }.prefix(maxTowers)
        // Biggest in the middle, beside the keep: alternate them left and right.
        var left: [CastleTower] = [], right: [CastleTower] = []
        for (i, t) in folders.enumerated() { if i % 2 == 0 { left.insert(t, at: 0) } else { right.append(t) } }
        return Castle(project: project, towers: left + [keep] + right)
    }

    /// Keeps the edit counts when the file list is read again.
    public mutating func carryEdits(from old: Castle) {
        for i in towers.indices { towers[i].edits = old.towers.first { $0.name == towers[i].name }?.edits ?? 0 }
    }

    /// Height of a tower in points (before scaling): taller with more files and more edits.
    public func height(_ i: Int) -> Double {
        let t = towers[i]
        // Roofs add their own height on top (see CastleArt); the walls stay short and stout.
        let base = t.isKeep ? 26.0 : 18.0
        return min(84, base + log2(Double(t.files) + 1) * 7 + Double(min(t.edits, 20)))
    }

    public func width(_ i: Int) -> Double { towers[i].isKeep ? Castle.keepWidth : Castle.towerWidth }

    /// Total width in points (before scaling).
    public var totalWidth: Double { towers.indices.reduce(0) { $0 + width($1) } + Double(max(0, towers.count - 1)) * Castle.gap }

    /// Left edge of tower i, from the castle's left edge (points, before scaling).
    public func minX(_ i: Int) -> Double { (0..<i).reduce(0) { $0 + width($1) + Castle.gap } }

    /// The roof on top of every tower (points, before scaling).
    public static let roofHeight = 21.0
    public var tallest: Double { towers.indices.map { height($0) + (towers[$0].isKeep ? Castle.flagHeight : Castle.roofHeight) }.max() ?? 0 }
    public static let flagHeight = 12.0
}

public struct CastlePlacement: Sendable {
    public var project: String
    /// Bottom-left corner of the castle (on the window's top edge), global points.
    public var origin: Vec2
    public var scale: Double
    public var windowID: Int
}

public enum CastleEvent: Equatable, Sendable {
    /// A block landed on a tower (an edit in that folder).
    case block(project: String, tower: Int)
}

extension World {
    static let castleOwnerBase = -440_000
    static func isCastleOwner(_ o: Int?) -> Bool { guard let o else { return false }; return o <= castleOwnerBase && o > castleOwnerBase - 1000 }

    /// The castle for a project (from its file list); kept until the app quits, and redrawn when it changes.
    public func setCastle(_ c: Castle) {
        var c = c
        if let old = castles[c.project] { c.carryEdits(from: old) }
        guard castles[c.project] != c else { return }
        castles[c.project] = c
        rebuildAttached()
    }

    /// Claude edited a file in `area` (the top-level folder, "" for the root): a block lands on that tower.
    public func castleEdit(project: String, area: String) {
        guard var c = castles[project] else { return }
        let i = c.towers.firstIndex { $0.name == area } ?? c.towers.firstIndex { $0.isKeep } ?? 0
        guard c.towers.indices.contains(i) else { return }
        c.towers[i].edits += 1
        castles[project] = c
        castleEvents.append(.block(project: project, tower: i))
        rebuildAttached()
    }

    public func drainCastleEvents() -> [CastleEvent] { defer { castleEvents.removeAll() }; return castleEvents }

    /// Where the castle of a live project goes: on its terminal window's top edge, at the end away from the bonsai,
    /// if there's room. Returns its placement and the platforms its towers offer.
    func castleLayout(for tree: BonsaiPlacement, k: Int) -> (CastlePlacement, [Surface])? {
        guard let wid = tree.windowID, let c = castles[tree.project], !c.towers.isEmpty, let w = windows[wid],
              let scr = screens.first(where: { w.midX >= $0.minX && w.midX < $0.maxX }) ?? screens.first,
              let seg = builtSurfaces.filter({ $0.ownerID == wid && $0.kind == .windowTop }).max(by: { $0.width < $1.width }) else { return nil }
        let headroom = scr.maxY - w.maxY - 8
        let scale = min(1, max(0.45, headroom / max(1, c.tallest)))
        let width = c.totalWidth * scale
        let treeHalf = tree.layout.potWidth * tree.scale / 2 + 30
        // The free stretch of the window top, minus the tree's corner.
        let treeOnLeft = tree.base.x < seg.minX + seg.width / 2
        let lo = treeOnLeft ? tree.base.x + treeHalf : seg.minX + 24
        let hi = treeOnLeft ? seg.maxX - 24 : tree.base.x - treeHalf
        guard headroom > 40, hi - lo > width else { return nil }
        let x0 = treeOnLeft ? hi - width : lo
        let place = CastlePlacement(project: c.project, origin: Vec2(x0, w.maxY), scale: scale, windowID: wid)
        // The keep's flat, crenellated top is the lookout (the other towers wear pointed roofs).
        let tops = c.towers.indices.filter { c.towers[$0].isKeep }.map { i in
            Surface(ownerID: World.castleOwnerBase - (k * 10 + i), kind: .shelf, y: w.maxY + c.height(i) * scale,
                    minX: x0 + c.minX(i) * scale + 1, maxX: x0 + (c.minX(i) + c.width(i)) * scale - 1)
        }
        return (place, tops)
    }
}
