import AppKit
import GremletsCore

/// Links this Mac to another screen (an iPad, a phone, a friend's laptop running the web habitat) so Gremlets can walk
/// off one edge of the Mac's screen and in from the opposite edge of the other screen, and back.
///
/// It speaks the same "room" protocol as the web habitat's screen bridge (web/js/bridge.js): both screens join a room
/// named after a random code and pass tiny JSON notes through ntfy.sh, a free public relay that needs no account.
/// Only Gremlet names, which edge they left through and how fast they were going are sent.
///
///   { v: 1, type: "walk", from: <device>, to: "left"|"right", species, y, vx, vy, air }
///   { v: 1, type: "hello", from, side, reply? }     // a screen is open (the other one shows "linked")
final class ScreenBridge {
    struct Walk { let species: String; let y: Double; let vx: Double; let vy: Double; let air: Bool }

    static let relay = PhoneLink.relay
    private let roomKey = "bridge.room", sideKey = "bridge.side", awayKey = "bridge.away", habitatKey = "bridge.habitat"
    /// This launch's device id, so our own notes echoed by the relay are ignored.
    let device: String = ScreenBridge.randomCode(8)
    private(set) var connected = false
    private(set) var peerSeen: Date?
    var onWalk: (Walk) -> Void = { _ in }
    var onStatus: () -> Void = {}
    private var task: Task<Void, Never>?
    private var beat: Timer?

    var room: String? { UserDefaults.standard.string(forKey: roomKey) }
    /// The edge of THIS screen that leads to the other one ("left" or "right").
    var side: String? { UserDefaults.standard.string(forKey: sideKey) }
    var linked: Bool { room != nil && side != nil }
    var peerOnline: Bool { peerSeen.map { Date().timeIntervalSince($0) < 90 } ?? false }
    var opposite: String { side == "right" ? "left" : "right" }
    /// Gremlets away on the other screen (so they aren't brought back on relaunch).
    var away: [String] {
        get { UserDefaults.standard.stringArray(forKey: awayKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: awayKey) }
    }
    /// Where the other screen opens the habitat (the live site, or a local server while developing).
    var habitat: String {
        get { UserDefaults.standard.string(forKey: habitatKey) ?? PhoneLink.habitat }
        set { UserDefaults.standard.set(newValue, forKey: habitatKey) }
    }
    private var topic: String? { room.map { "gremlets-room-\($0)" } }

    static func randomCode(_ n: Int) -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        return String((0..<n).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
    }

    /// Starts a new room with the doorway on `side` of this screen.
    func create(side: String) {
        stop()
        UserDefaults.standard.set(ScreenBridge.randomCode(12), forKey: roomKey)
        UserDefaults.standard.set(side == "left" ? "left" : "right", forKey: sideKey)
        peerSeen = nil
        start()
    }

    /// The link the other screen opens: its doorway is on the opposite edge.
    var inviteURL: String? {
        guard let room else { return nil }
        var base = habitat
        if !base.hasSuffix("/") && !base.contains("?") { base += "/" }
        return "\(base)?room=\(room)&side=\(opposite)"
    }

    func start() {
        guard task == nil, let topic else { return }
        task = Task { [weak self] in
            var backoff: UInt64 = 2
            while !Task.isCancelled {
                guard let self else { return }
                let since = Int(Date().timeIntervalSince1970) - 30
                guard let url = URL(string: "\(ScreenBridge.relay)/\(topic)/json?since=\(since)") else { return }
                do {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 300
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    await MainActor.run { self.connected = true; self.onStatus(); self.send(["type": "hello", "side": self.side ?? "right"]) }
                    backoff = 2
                    for try await line in bytes.lines { self.handle(line) }
                } catch {
                    if Task.isCancelled { return }
                }
                await MainActor.run { self.connected = false; self.onStatus() }
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(60, backoff * 2)
            }
        }
        beat?.invalidate()
        beat = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.send(["type": "hello", "side": self.side ?? "right"])
            self.onStatus()   // lets the door close when the other screen has gone quiet
        }
    }

    func stop() {
        task?.cancel(); task = nil
        beat?.invalidate(); beat = nil
        connected = false
    }

    func unlink() {
        stop()
        UserDefaults.standard.removeObject(forKey: roomKey)
        UserDefaults.standard.removeObject(forKey: sideKey)
        peerSeen = nil
        onStatus()
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              msg["event"] as? String == "message",
              let body = (msg["message"] as? String)?.data(using: .utf8),
              let note = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              note["v"] as? Int == 1, let from = note["from"] as? String, from != device else { return }
        DispatchQueue.main.async {
            self.peerSeen = Date()
            switch note["type"] as? String {
            case "hello":
                if note["reply"] == nil { self.send(["type": "hello", "side": self.side ?? "right", "reply": true]) }
                self.onStatus()
            case "walk":
                // Notes are addressed to the edge they arrive through, which is our doorway.
                guard note["to"] as? String == self.side, let species = note["species"] as? String, species.count < 40 else { return }
                func num(_ k: String) -> Double { (note[k] as? NSNumber)?.doubleValue ?? 0 }
                self.onWalk(Walk(species: species, y: num("y"), vx: num("vx"), vy: num("vy"), air: (note["air"] as? Bool) ?? false))
                self.onStatus()
            default:
                self.onStatus()
            }
        }
    }

    func send(_ note: [String: Any]) {
        guard let topic, let url = URL(string: "\(ScreenBridge.relay)/\(topic)") else { return }
        var full = note
        full["v"] = 1; full["from"] = device
        guard let body = try? JSONSerialization.data(withJSONObject: full) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Something leaves through our doorway; on the other screen it arrives through the opposite edge.
    func cross(_ note: [String: Any]) {
        var n = note
        n["to"] = opposite
        send(n)
    }

    // MARK: Link page (served on 127.0.0.1 only)

    func linkPage() -> String {
        guard let url = inviteURL, let side else { return "<p>No screen linked. Use the Gremlets menu → Link Another Screen.</p>" }
        let qr = PhoneLink.qrPNG(url).map { "<img src=\"data:image/png;base64,\($0)\" alt=\"QR code\">" } ?? ""
        let status = peerOnline ? "The other screen is open: the doorway is on the \(side) edge of your Mac." : "Waiting for the other screen to open the link…"
        return """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Link another screen</title>
        <style>
          body { font: 16px/1.5 -apple-system, system-ui, sans-serif; background: #f3f6ef; color: #1f2a22; margin: 0; display: grid; place-items: center; min-height: 100vh; }
          main { max-width: 460px; padding: 32px 20px; text-align: center; }
          h1 { font-size: 1.5rem; margin: 0 0 8px; }
          img { width: 240px; height: 240px; image-rendering: pixelated; background: #fff; padding: 12px; border-radius: 12px; margin: 16px 0; }
          p { color: #5c6b5f; margin: 8px 0; }
          code { font-size: 0.8rem; word-break: break-all; background: #e7eee3; padding: 4px 6px; border-radius: 4px; }
          .ok { color: #2f7a3a; }
        </style>
        <main>
          <h1>Link another screen</h1>
          <p>Put your iPad (or phone) against the <b>\(side)</b> edge of your Mac, point its camera at this code and open the link. Keep that page open.</p>
          \(qr)
          <p>Or open this on the other screen:<br><code>\(url)</code></p>
          <p class="\(peerOnline ? "ok" : "")">\(status)</p>
          <p>Then watch: a Gremlet that wanders to that edge walks straight off your Mac and in from the edge of the other screen, and wanders back the same way. <code>gremlet cross</code> sends one over now.</p>
          <p style="font-size: .85rem">Only Gremlet names, which edge they left through and how fast they were going pass through ntfy.sh, a free public relay, on a channel named after this private code. Unlink from the menu any time.</p>
        </main>
        """
    }
}
