import AppKit
import GremletsCore

/// Desktop icons as things to play with: their tops are little platforms, a Gremlet landing on one makes it boing, and
/// now and then one is picked up and carried around for a bit before being put back exactly where it was.
///
/// Positions come from Finder (`desktop position of every item of desktop`), which macOS asks you to allow once
/// ("Gremlets wants to control Finder"). Nothing is ever moved, renamed or opened: the icon that gets carried is a copy,
/// and the spot it came from is covered with a matching piece of your wallpaper until it's put back.
/// Off until you turn on "Play with Desktop Icons".
final class DesktopIcons {
    struct Icon: Equatable {
        let name: String
        /// Icon image rectangle, global Cocoa coordinates (y up).
        let rect: CGRect
        var id: Int
    }

    private(set) var icons: [Icon] = []
    /// Icons not covered by any window right now.
    private(set) var visible: [Icon] = []
    private(set) var lastError: String?
    var onChange: () -> Void = {}
    private var fetching = false

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "icons.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "icons.enabled"); if !newValue { icons = []; visible = []; onChange() } }
    }

    /// Asks Finder where the desktop icons are (in the background; a few times a minute at most).
    func refresh() {
        guard enabled, !fetching else { return }
        fetching = true
        let script = """
        tell application "Finder"
            set out to ""
            set sz to 64
            try
                set sz to icon size of icon view options of window of desktop
            end try
            set out to out & "size" & tab & sz & linefeed
            repeat with i in (items of desktop)
                set p to desktop position of i
                set out to out & (name of i) & tab & (item 1 of p) & tab & (item 2 of p) & linefeed
            end repeat
            return out
        end tell
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            var text = "", problem: String?
            do {
                try p.run(); p.waitUntilExit()
                text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if p.terminationStatus != 0 {
                    problem = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch { problem = error.localizedDescription }
            DispatchQueue.main.async { self?.apply(text, problem) }
        }
    }

    private func apply(_ text: String, _ problem: String?) {
        fetching = false
        lastError = problem.map { $0.contains("-1743") || $0.contains("Not authorized") ? "Allow Gremlets to control Finder in System Settings → Privacy & Security → Automation" : $0 }
        guard problem == nil, let primary = NSScreen.screens.first else { onChange(); return }
        var size = 64.0
        var parsed: [Icon] = []
        for (n, line) in text.split(separator: "\n").enumerated() {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if f.first == "size", f.count >= 2 { size = Double(f[1]) ?? 64; continue }
            guard f.count >= 3, let x = Double(f[1]), let y = Double(f[2]) else { continue }
            // Finder reports each icon's centre, top-left based; flip to Cocoa coordinates.
            let cy = Double(primary.frame.height) - y
            parsed.append(Icon(name: f[0], rect: CGRect(x: x - size / 2, y: cy - size / 2, width: size, height: size), id: n))
        }
        icons = parsed
        onChange()
    }

    /// Recomputes which icons are visible (no window in front of them). Call when windows change.
    func updateVisibility(windows: [WindowInfo]) {
        visible = icons.filter { icon in
            !windows.contains { w in CGRect(x: w.frame.x, y: w.frame.y, width: w.frame.w, height: w.frame.h).intersects(icon.rect.insetBy(dx: -4, dy: -24)) }
        }
    }

    /// The platforms: the top of each visible icon (a bit narrower than the icon, so feet land on the picture).
    func surfaces(excluding lifted: Set<Int>) -> [Surface] {
        visible.filter { !lifted.contains($0.id) }.map { i in
            Surface(ownerID: World.iconOwnerBase - i.id, kind: .icon, y: i.rect.maxY - i.rect.height * 0.08,
                    minX: i.rect.midX - i.rect.width * 0.36, maxX: i.rect.midX + i.rect.width * 0.36)
        }
    }

    // MARK: Images

    private var imageCache: [String: CGImage] = [:]
    /// The icon's picture, at its size on screen.
    func image(_ icon: Icon) -> CGImage? {
        if let c = imageCache[icon.name] { return c }
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/\(icon.name)")
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: path)
        let px = Int(icon.rect.width * 2)
        img.size = NSSize(width: px, height: px)
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        imageCache[icon.name] = cg
        return cg
    }

    private var wallpaper: (image: CGImage, screen: CGRect)?
    /// A piece of the wallpaper exactly where `rect` is (to cover an icon that's been "picked up"), or nil if the
    /// wallpaper can't be matched (dynamic or tiled ones).
    func wallpaperPatch(for rect: CGRect) -> CGImage? {
        guard let screen = NSScreen.screens.first else { return nil }
        if wallpaper == nil {
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen), let ns = NSImage(contentsOf: url),
                  let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            wallpaper = (cg, screen.frame)
        }
        guard let (img, sf) = wallpaper else { return nil }
        // Default scaling: fill the screen, centred, cropping the overflow.
        let iw = Double(img.width), ih = Double(img.height)
        let scale = max(sf.width / iw, sf.height / ih)
        let ox = (sf.width - iw * scale) / 2, oy = (sf.height - ih * scale) / 2
        let local = CGRect(x: rect.minX - sf.minX, y: rect.minY - sf.minY, width: rect.width, height: rect.height)
        // Image pixel space is top-left based.
        let crop = CGRect(x: (local.minX - ox) / scale, y: ih - (local.maxY - oy) / scale, width: local.width / scale, height: local.height / scale)
        return img.cropping(to: crop.integral)
    }
}
