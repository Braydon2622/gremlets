import AppKit
import GremletsCore

/// Reads the frames of other apps' on-screen windows so creatures can stand on them.
///
/// Uses `CGWindowListCopyWindowInfo`. Window *bounds* are readable without Screen Recording permission
/// (only titles need it), so no permission prompt is needed for this feature.
enum WindowTracker {
    static let ownPID = Int(ProcessInfo.processInfo.processIdentifier)

    /// Normal app windows, front-most first, in global y-up (Cocoa) coordinates.
    static func snapshot() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primary = NSScreen.screens.first else { return [] }
        // CG window bounds are top-left based, relative to the primary display.
        let primaryHeight = Double(primary.frame.height)
        var out: [WindowInfo] = []
        out.reserveCapacity(list.count)
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width >= 80, height >= 40 else { continue }
            out.append(WindowInfo(id: id, frame: Rect(x: x, y: primaryHeight - y - height, w: width, h: height)))
        }
        return out
    }

    /// Usable area of every screen (above the Dock, below the menu bar).
    static func screens() -> [Rect] {
        NSScreen.screens.map { s in
            let f = s.visibleFrame
            return Rect(x: f.minX, y: f.minY, w: f.width, h: f.height)
        }
    }
}
