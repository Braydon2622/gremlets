import AppKit
import ApplicationServices
import GremletsCore

/// Where the Dock's icons are, so the Gremlets can play on them: hop across them, cheer an app you open (its icon
/// bounces whoever is standing on it into the air), knock on one that gets a badge, nap on the Trash.
///
/// Positions, names, badges and whether an app is running come from the Dock through macOS Accessibility (the same
/// one-time permission as "Stand on Buttons and Search Bars"). Nothing is clicked or changed. Opened/quit apps come
/// from NSWorkspace, which needs no permission. Only a Dock along the bottom of the main screen is used.
final class DockWatcher {
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "dock.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dock.enabled"); if !newValue { icons = []; onChange(icons) } }
    }
    var trusted: Bool { AXIsProcessTrusted() }

    private(set) var icons: [DockIcon] = []
    var onChange: ([DockIcon]) -> Void = { _ in }
    var onOpened: (String) -> Void = { _ in }
    var onQuit: (String) -> Void = { _ in }
    var onBadge: (String) -> Void = { _ in }

    private var scanning = false
    private var lastScan = 0.0
    private var badges: [String: String] = [:]
    private let queue = DispatchQueue(label: "gremlets.dock", qos: .utility)
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.enabled, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular, let name = app.localizedName else { return }
            self.onOpened(name)
            self.lastScan = 0   // its running dot, and the Dock may have grown an icon for it
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.enabled, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular, let name = app.localizedName else { return }
            self.onQuit(name)
            self.lastScan = 0
        })
    }

    /// Re-reads the Dock in the background (every few seconds at most).
    func tick(now: Double, fullScreen: Bool) {
        guard enabled, trusted, !fullScreen else {
            if !icons.isEmpty { icons = []; onChange(icons) }
            return
        }
        guard !scanning, now - lastScan > 4 else { return }
        scanning = true
        lastScan = now
        guard let main = NSScreen.screens.first else { scanning = false; return }
        // A Dock on the bottom edge (not hidden, not on a side).
        let dockHeight = Double(main.visibleFrame.minY - main.frame.minY)
        let primaryHeight = Double(main.frame.height)
        let floorY = Double(main.visibleFrame.minY)
        guard dockHeight > 12, let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            scanning = false
            if !icons.isEmpty { icons = []; onChange(icons) }
            return
        }
        queue.async { [weak self] in
            let found = DockWatcher.scan(pid: pid, primaryHeight: primaryHeight, floorY: floorY, screenMinX: Double(main.frame.minX), screenMaxX: Double(main.frame.maxX))
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                // A badge that's new, or a bigger number than before: someone goes and knocks on it.
                for i in found where i.badge != nil && !i.isTrash {
                    let old = self.badges[i.app]
                    let grew: Bool
                    if let old { grew = Int(i.badge!).flatMap { n in Int(old).map { n > $0 } } ?? (old != i.badge) } else { grew = true }
                    if grew && self.didFirstScan { self.onBadge(i.app) }
                }
                self.badges = Dictionary(found.compactMap { i in i.badge.map { (i.app, $0) } }, uniquingKeysWith: { a, _ in a })
                self.didFirstScan = true
                if found != self.icons { self.icons = found; self.onChange(found) }
            }
        }
    }
    private var didFirstScan = false

    private static func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    static func scan(pid: pid_t, primaryHeight: Double, floorY: Double, screenMinX: Double, screenMaxX: Double) -> [DockIcon] {
        let dock = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dock, 0.5)
        guard let kids: [AXUIElement] = attr(dock, kAXChildrenAttribute),
              let list = kids.first(where: { (attr($0, kAXRoleAttribute) as String?) == "AXList" }),
              let items: [AXUIElement] = attr(list, kAXChildrenAttribute) else { return [] }
        var out: [DockIcon] = []
        for item in items {
            let sub: String = attr(item, kAXSubroleAttribute) ?? ""
            guard sub != "AXSeparatorDockItem", let title: String = attr(item, kAXTitleAttribute), !title.isEmpty,
                  let p: AXValue = attr(item, kAXPositionAttribute), let s: AXValue = attr(item, kAXSizeAttribute) else { continue }
            var pt = CGPoint.zero, sz = CGSize.zero
            AXValueGetValue(p, .cgPoint, &pt); AXValueGetValue(s, .cgSize, &sz)
            let minX = Double(pt.x), maxX = Double(pt.x + sz.width)
            let top = primaryHeight - Double(pt.y)
            // Only icons along the bottom of the main screen.
            guard sz.width > 10, minX >= screenMinX - 1, maxX <= screenMaxX + 1, abs(top - floorY) < 40 else { continue }
            let badge: String? = attr(item, "AXStatusLabel")
            let running: Bool = (attr(item, "AXIsApplicationRunning") as NSNumber?)?.boolValue ?? false
            out.append(DockIcon(app: title, minX: minX + 3, maxX: maxX - 3, top: min(top, floorY), badge: badge?.isEmpty == false ? badge : nil,
                                running: running, isTrash: sub == "AXTrashDockItem"))
        }
        return out
    }
}
