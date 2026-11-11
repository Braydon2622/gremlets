import AppKit
import ApplicationServices
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
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]],
              let primary = NSScreen.screens.first else { return [] }
        // CG window bounds are top-left based, relative to the primary display.
        let primaryHeight = Double(primary.frame.height)
        var out: [WindowInfo] = []
        out.reserveCapacity(list.count)
        screenshotToolVisible = list.contains { ($0[kCGWindowOwnerName as String] as? String) == "screencaptureui" }

        var widgets: [WindowInfo] = []
        let ncPID = notificationCenterPID()
        for w in list {
            // Desktop widgets (macOS 14+) are drawn by Notification Center, below every window: moss grows on them.
            if let pid = w[kCGWindowOwnerPID as String] as? Int, pid == ncPID || (w[kCGWindowOwnerName as String] as? String) == "Notification Center",
               let layer = w[kCGWindowLayer as String] as? Int, layer < 20,
               let id = w[kCGWindowNumber as String] as? Int,
               let b = w[kCGWindowBounds as String] as? [String: Double],
               let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
               width >= 90, height >= 60, width <= 900, height <= 900, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 {
                // A little in from the rounded corners, so the moss sits on the flat part of the top.
                widgets.append(WindowInfo(id: id, frame: Rect(x: x + 8, y: primaryHeight - y - height, w: width - 16, h: height), isWidget: true))
                continue
            }
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
        // Widgets live on the desktop, behind all the windows.
        return out + widgets
    }

    /// Notification Center's process (it draws the desktop widgets), looked up once in a while.
    private static var ncPIDCache: (pid: Int, at: CFTimeInterval) = (-1, -100)
    static func notificationCenterPID() -> Int {
        let now = CACurrentMediaTime()
        if now - ncPIDCache.at < 30 { return ncPIDCache.pid }
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first.map { Int($0.processIdentifier) } ?? -1
        ncPIDCache = (pid, now)
        return pid
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

/// Where each screen's menu bar is empty, so a Gremlet can stand on a window top right up under it (a window filling
/// the screen) without covering anything: not in front of the app's menus (read through Accessibility, the same
/// permission the Dock play uses; without it, everything left of the notch or the middle counts as menus), the status
/// icons (their windows' bounds, which need no permission), or the notch. Re-read about once a second.
enum MenuBarSense {
    private static var cache: (at: CFTimeInterval, bars: [MenuBar?]) = (-10, [])

    static func bars() -> [MenuBar?] {
        let now = CACurrentMediaTime()
        if now - cache.at < 1.2 { return cache.bars }
        guard let primary = NSScreen.screens.first else { return [] }
        let primaryHeight = Double(primary.frame.height)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let status: [(x: Double, w: Double, top: Double)] = list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 25, let b = w[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let h = b["Height"], h < 60 else { return nil }
            return (x, width, primaryHeight - y)   // its top edge, y-up
        }
        let menusEnd = appMenusEnd()
        let bars = NSScreen.screens.map { s -> MenuBar? in
            let f = s.frame, v = s.visibleFrame
            let height = Double(f.maxY - v.maxY)
            guard height >= 18 else { return nil }   // hidden (or no menu bar on this screen)
            var notch: Span?
            if #available(macOS 12, *), let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea, r.minX > l.maxX {
                notch = Span(Double(f.minX + l.maxX), Double(f.minX + r.minX))
            }
            // The app's menus: as read, shifted onto this screen; or a guess.
            let menus: Double
            if let end = menusEnd { menus = Double(f.minX) + end } else { menus = notch?.lo ?? Double(f.minX + f.width * 0.5) }
            var clear = [Span(Double(f.minX), Double(f.maxX))]
            clear = Span.subtract(clear, Span(Double(f.minX), menus + 12))
            if let n = notch { clear = Span.subtract(clear, Span(n.lo - 8, n.hi + 8)) }
            let mine = status.filter { $0.x >= Double(f.minX) && $0.x < Double(f.maxX) && abs($0.top - Double(f.maxY)) < 2 }
            if let first = mine.map(\.x).min() { clear = Span.subtract(clear, Span(first - 10, Double(f.maxX))) }
            return MenuBar(height: height, clear: clear.filter { $0.width >= 60 })
        }
        cache = (now, bars)
        return bars
    }

    /// How far the frontmost app's menus reach from the left of the screen, if Accessibility lets us read them.
    private static func appMenusEnd() -> Double? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.menuBarOwningApplication else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.15)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement], !items.isEmpty else { return nil }
        var end = 0.0
        for item in items {
            var p: CFTypeRef?, z: CFTypeRef?
            var pos = CGPoint.zero, size = CGSize.zero
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &p) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &z) == .success else { continue }
            AXValueGetValue(p as! AXValue, .cgPoint, &pos)
            AXValueGetValue(z as! AXValue, .cgSize, &size)
            end = max(end, Double(pos.x + size.width))
        }
        // Relative to the screen the menus are on.
        let screen = NSScreen.screens.first { end > Double($0.frame.minX) && end <= Double($0.frame.maxX) + 1 } ?? NSScreen.screens.first
        return end > 0 ? end - Double(screen?.frame.minX ?? 0) : nil
    }
}
