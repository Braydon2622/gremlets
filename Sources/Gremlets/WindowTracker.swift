import AppKit
import GremletsCore

/// Reads the frames of other apps' on-screen windows so creatures can stand on them.
///
/// Uses `CGWindowListCopyWindowInfo`. Window *bounds* are readable without Screen Recording permission
/// (only titles need it), so no permission prompt is needed for this feature.
enum WindowTracker {
    static let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
    /// Whether the system screenshot tool (⌘⇧4 / ⌘⇧5 crosshair, toolbar or thumbnail) was on screen at the last snapshot.
    /// Only the window's owner name is read, which needs no permission.
    static var screenshotToolVisible = false

    /// Normal app windows, front-most first, in global y-up (Cocoa) coordinates.
    /// Whether the current Space is a full-screen app's: the Dock puts a black backdrop behind the full-screen app
    /// (it isn't there otherwise). Reading its name needs Screen Recording, so its window level identifies it too.
    /// Checked at most twice a second.
    static var fullScreenSpace: Bool {
        let now = CACurrentMediaTime()
        if now - lastFullScreenCheck < 0.5 { return cachedFullScreen }
        lastFullScreenCheck = now
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // Only the main screen counts (its backdrop starts at the top-left of the primary display and spans it).
        let mainWidth = Double(NSScreen.screens.first?.frame.width ?? 0)
        cachedFullScreen = list.contains { w in
            guard (w[kCGWindowOwnerName as String] as? String) == "Dock",
                  (w[kCGWindowName as String] as? String) == "Fullscreen Backdrop" || (w[kCGWindowLayer as String] as? Int) == -2147483622,
                  let b = w[kCGWindowBounds as String] as? [String: Double] else { return false }
            return abs((b["X"] ?? -1)) < 1 && abs((b["Y"] ?? -1)) < 1 && abs((b["Width"] ?? 0) - mainWidth) < 2
        }
        return cachedFullScreen
    }
    private static var lastFullScreenCheck: CFTimeInterval = 0
    private static var cachedFullScreen = false

    static func snapshot() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primary = NSScreen.screens.first else { return [] }
        // CG window bounds are top-left based, relative to the primary display.
        let primaryHeight = Double(primary.frame.height)
        var out: [WindowInfo] = []
        out.reserveCapacity(list.count)
        screenshotToolVisible = list.contains { ($0[kCGWindowOwnerName as String] as? String) == "screencaptureui" }

        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width >= 80, height >= 40 else { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            out.append(WindowInfo(id: id, frame: Rect(x: x, y: primaryHeight - y - height, w: width, h: height), ledges: ledges(for: owner)))
        }
        return out
    }

    /// Where apps keep a ledge Gremlets can walk along inside the window: the bottom edge of the tab strip + address
    /// bar in browsers, the toolbar in Finder. Measured from the window's top edge, in points (default layouts).
    static func ledges(for app: String) -> [Double] {
        switch app {
        case "Google Chrome", "Google Chrome Canary", "Brave Browser", "Microsoft Edge", "Chromium", "Vivaldi", "Opera": return [88]
        case "Arc": return [52]
        case "Safari", "Safari Technology Preview": return [80]
        case "Firefox", "Firefox Nightly", "Zen Browser": return [84]
        case "Finder": return [52]
        default: return []
        }
    }

    /// Usable area of every screen (above the Dock, below the menu bar).
    static func screens() -> [Rect] {
        NSScreen.screens.map { s in
            let f = s.visibleFrame
            return Rect(x: f.minX, y: f.minY, w: f.width, h: f.height)
        }
    }
}
