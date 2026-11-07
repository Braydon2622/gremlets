import AppKit
import ApplicationServices
import GremletsCore

/// Gremlets can stand on real controls in the app you're using: the address bar, search fields, wide buttons,
/// toolbars. Uses macOS Accessibility (you grant it once in System Settings) to read *where* those controls are in the
/// front window, never what's in them. Web page content is skipped entirely (browsers stay fast), and scanning runs
/// in the background every couple of seconds.
final class AppControls {
    static let ownerBase = 10_000_000

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "controls.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "controls.enabled"); if !newValue { latest = [] } }
    }
    var trusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends you to System Settings › Privacy & Security › Accessibility.
    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private(set) var latest: [Surface] = []
    private var scanning = false
    private var lastScan = 0.0
    private let queue = DispatchQueue(label: "gremlets.appcontrols", qos: .utility)

    /// Latest control surfaces (refreshed in the background at most every 2 seconds).
    func surfaces(now: Double) -> [Surface] {
        guard enabled, trusted else { return [] }
        if !scanning && now - lastScan > 2 {
            scanning = true
            lastScan = now
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let mine = ProcessInfo.processInfo.processIdentifier
            let primaryHeight = Double(NSScreen.screens.first?.frame.height ?? 0)
            queue.async { [weak self] in
                let found = (pid != nil && pid != mine) ? AppControls.scan(pid: pid!, primaryHeight: primaryHeight) : []
                DispatchQueue.main.async { self?.latest = found; self?.scanning = false }
            }
        }
        return latest
    }

    private static func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p: AXValue = attr(e, kAXPositionAttribute), let s: AXValue = attr(e, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p, .cgPoint, &pt); AXValueGetValue(s, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    /// Walks the front window's controls (not web content), collecting the tops of fields and wide buttons.
    static func scan(pid: pid_t, primaryHeight: Double) -> [Surface] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let win: AXUIElement = attr(app, kAXFocusedWindowAttribute), let wf = frame(win) else { return [] }
        var out: [Surface] = []
        var queue: [(AXUIElement, Int)] = [(win, 0)]
        var visited = 0
        while !queue.isEmpty && visited < 450 && out.count < 24 {
            let (e, depth) = queue.removeFirst()
            visited += 1
            let role: String = attr(e, kAXRoleAttribute) ?? ""
            if role == "AXWebArea" || role == "AXScrollArea" && depth > 3 { continue }   // skip page content
            let standable = ["AXTextField", "AXSearchField", "AXComboBox", "AXButton", "AXPopUpButton", "AXSegmentedControl"].contains(role)
            if standable, let f = frame(e), f.width >= (role == "AXButton" ? 64 : 110), f.height >= 16, f.height <= 60,
               f.minY > wf.minY + 24, f.minY < wf.maxY - 40, f.minX >= wf.minX - 1, f.maxX <= wf.maxX + 1 {
                let topY = primaryHeight - Double(f.minY)   // Cocoa y of the control's top edge
                out.append(Surface(ownerID: ownerBase + out.count, kind: .windowLedge, y: topY,
                                   minX: Double(f.minX) + 4, maxX: Double(f.maxX) - 4))
            }
            if depth < 10, let kids: [AXUIElement] = attr(e, kAXChildrenAttribute) {
                for k in kids.prefix(60) { queue.append((k, depth + 1)) }
            }
        }
        // Drop controls hidden under another control's top (keep the highest at each spot).
        return out.filter { s in !out.contains { o in o.ownerID != s.ownerID && o.y > s.y && o.y - s.y < 30 && o.minX < s.maxX && o.maxX > s.minX && o.y - s.y > 0 } }
    }
}
