import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision
import GremletsCore

/// The opt-in features that need you to grant a permission. Both are off until you switch them on in the menu
/// (Gremlets → Your Mac), and each asks macOS for its permission only when you do.
///
/// - **Stand on text and buttons** (Screen Recording): every few seconds the front window is captured and Apple's
///   on-device text recognition finds lines of text, labels and search fields; their top edges become ledges the
///   Gremlets can stand on, like the hero in the Terraria video standing on a browser's search bar. Nothing is kept
///   or sent anywhere: only the boxes' positions are used, never the text.
/// - **Highlight clips** (Screen Recording): when something good happens (a treasure run, a boost, a summit), a few
///   frames a second of the screen are saved as a GIF in Movies › Gremlets › Highlights.
///
/// Nothing here moves, resizes or focuses your windows: Gremlets never get in the way of work.
final class ScreenSense {
    struct Spans { let size: CGSize; let spans: [WindowSpan] }

    private(set) var spans: [Int: Spans] = [:]
    private var busy = false
    private var lastScan: CFTimeInterval = 0
    private var recording: (frames: [CGImage], until: CFTimeInterval, name: String, next: CFTimeInterval)?

    var standOnText: Bool {
        get { UserDefaults.standard.bool(forKey: "sense.text") }
        set { UserDefaults.standard.set(newValue, forKey: "sense.text") }
    }
    var highlightClips: Bool {
        get { UserDefaults.standard.bool(forKey: "sense.clips") }
        set { UserDefaults.standard.set(newValue, forKey: "sense.clips") }
    }

    static var hasScreenAccess: Bool { CGPreflightScreenCaptureAccess() }
    static func requestScreenAccess() { _ = CGRequestScreenCaptureAccess() }

    // MARK: Standing on text

    /// Called often; scans the front window every few seconds when switched on.
    /// `frontWindow` is only looked up when a scan is due (listing every window each frame is costly).
    func tick(frontWindow: @autoclosure () -> (id: Int, frame: CGRect)?) {
        guard standOnText, !busy else { return }
        let now = CACurrentMediaTime()
        guard now - lastScan > 6 else { return }
        lastScan = now
        guard Self.hasScreenAccess, let fw = frontWindow() else { return }
        guard #available(macOS 14, *) else { return }
        busy = true
        Task { [weak self] in
            defer { DispatchQueue.main.async { self?.busy = false } }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
                  let win = content.windows.first(where: { Int($0.windowID) == fw.id }) else { return }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(win.frame.width); cfg.height = Int(win.frame.height)
            cfg.showsCursor = false
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg) else { return }
            let found = Self.textSpans(in: img, size: win.frame.size)
            DispatchQueue.main.async { self?.spans[fw.id] = Spans(size: win.frame.size, spans: found) }
        }
    }

    /// Top edges of recognized text lines, as spans measured from the window's top-left (points).
    static func textSpans(in img: CGImage, size: CGSize) -> [WindowSpan] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .fast
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: img).perform([req])
        var out: [WindowSpan] = []
        for o in req.results ?? [] {
            let b = o.boundingBox   // normalized, origin bottom-left
            let w = b.width * size.width, h = b.height * size.height
            guard w >= 70, h >= 8, h <= 44 else { continue }
            let top = (1 - b.maxY) * size.height - 3
            guard top > 60, top < size.height - 30 else { continue }   // skip the title bar and the very bottom
            out.append(WindowSpan(fromTop: top, minX: b.minX * size.width - 4, maxX: b.maxX * size.width + 4))
        }
        // Keep the widest few, not overlapping vertically within 20 pt of each other.
        var kept: [WindowSpan] = []
        for s in out.sorted(by: { ($0.maxX - $0.minX) > ($1.maxX - $1.minX) }) where kept.count < 10 {
            if !kept.contains(where: { abs($0.fromTop - s.fromTop) < 20 && $0.minX < s.maxX && $0.maxX > s.minX }) { kept.append(s) }
        }
        return kept
    }

    /// The spans for a window, if its size hasn't changed since the scan.
    func spans(for id: Int, size: CGSize) -> [WindowSpan] {
        guard standOnText, let s = spans[id], abs(s.size.width - size.width) < 2, abs(s.size.height - size.height) < 2 else { return [] }
        return s.spans
    }

    // MARK: Highlight clips

    /// Starts saving a clip of the main screen for `seconds` (a few frames a second, scaled down).
    func startClip(_ name: String, seconds: Double) {
        guard highlightClips, Self.hasScreenAccess, recording == nil else { return }
        recording = ([], CACurrentMediaTime() + seconds, name, 0)
    }

    func clipTick() {
        guard var r = recording else { return }
        let now = CACurrentMediaTime()
        if now >= r.until || r.frames.count >= 140 {
            let frames = r.frames, name = r.name
            recording = nil
            DispatchQueue.global(qos: .utility).async { Self.writeGIF(frames, name: name) }
            return
        }
        guard now >= r.next, #available(macOS 14, *) else { return }
        r.next = now + 0.2
        recording = r
        Task { [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { return }
            let cfg = SCStreamConfiguration()
            cfg.width = 720; cfg.height = Int(720 * Double(display.height) / Double(max(1, display.width)))
            cfg.showsCursor = false
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg) else { return }
            DispatchQueue.main.async { self?.recording?.frames.append(img) }
        }
    }

    static func writeGIF(_ frames: [CGImage], name: String) {
        guard frames.count >= 4 else { return }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Gremlets/Highlights", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = dir.appendingPathComponent("\(name) \(f.string(from: Date())).gif")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary
        for img in frames { CGImageDestinationAddImage(dest, img, props) }
        CGImageDestinationFinalize(dest)
    }
}
