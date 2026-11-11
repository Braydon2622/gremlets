import AppKit
import CryptoKit
import GremletsCore

/// Links this Mac to another screen (an iPad, a phone, a friend's laptop running the web habitat) so Gremlets can walk
/// off one edge of the Mac's screen and in from the opposite edge of the other screen, and back.
///
/// It speaks the same "room" protocol as the web habitat's screen bridge (web/js/bridge.js): both screens join a room
/// named after a random code and pass tiny JSON notes through ntfy.sh, a free public relay that needs no account.
/// Only Gremlet names, which edge they left through and how fast they were going are sent.
///
///   { v: 1, type: "walk", from: <device>, to: "left"|"right", species, y, vx, vy, air }
///   { v: 1, type: "visitor", from, to, kind: "ferry", y, riders: [species] }   // the sky ferry sails across
///   { v: 1, type: "hello", from, side, reply? }     // a screen is open (the other one shows "linked")
///   { v: 1, type: "status", from, sessions, recent }  // what Claude is doing, for a Terrarium (TerrariumNote.swift)
///
/// Rooms made since the Terrarium are sealed: every note goes over the relay as `{"v":2,"n":…,"c":…}` (AES-GCM, see
/// NoteSeal), with the key from a pairing secret that travels only inside the QR code / link (its #fragment) or the
/// friend code, and is kept in the Keychain. Older rooms without a secret still speak plain notes.
final class ScreenBridge {
    struct Walk { let species: String; let y: Double; let vx: Double; let vy: Double; let air: Bool; let owner: String? }
    /// This Mac's lasting id, carried by its Gremlets when they travel, so a friend's Mac knows they're visitors and
    /// sends them home, and this Mac knows its own when they come back.
    let owner: String = {
        if let o = UserDefaults.standard.string(forKey: "bridge.owner") { return o }
        let o = ScreenBridge.randomCode(10); UserDefaults.standard.set(o, forKey: "bridge.owner"); return o
    }()

    static let relay = PhoneLink.relay
    private let roomKey = "bridge.room", sideKey = "bridge.side", awayKey = "bridge.away", habitatKey = "bridge.habitat"
    /// This launch's device id, so our own notes echoed by the relay are ignored.
    let device: String = ScreenBridge.randomCode(8)
    private(set) var connected = false
    private(set) var peerSeen: Date?
    var onWalk: (Walk) -> Void = { _ in }
    /// How mossy this Mac is (minutes), sent with every hello so the other screen's branches grow to match.
    var moss: () -> Int = { 0 }
    /// The sky ferry sailing in from the other screen, with passengers (species ids) and how high up it was.
    var onFerry: ([String], Double) -> Void = { _, _ in }
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

    /// The pairing secret for this room (Keychain), and the note key made from it.
    /// (Read from the Keychain once, then kept in memory.)
    private lazy var secret: String? = Keychain.get("bridge.secret")
    private var cachedKey: (room: String, secret: String, key: SymmetricKey)?
    var sealed: Bool { secret != nil }
    private var noteKey: SymmetricKey? {
        guard let room, let secret else { return nil }
        if let c = cachedKey, c.room == room, c.secret == secret { return c.key }
        let k = NoteSeal.key(secret: secret, room: room)
        cachedKey = (room, secret, k)
        return k
    }
    /// The other screen is a Terrarium (it said so in its hello): only then does Claude's status go to it.
    private(set) var peerIsTerrarium = false
    /// The status note to send whenever a Terrarium says hello (set by the app).
    var status: () -> [String: Any]? = { nil }

    static func randomCode(_ n: Int) -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        return String((0..<n).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
    }

    /// Joins a friend's room (their code), with the doorway on the opposite edge to theirs: their Gremlets walk
    /// off their right edge and in from our left.
    func join(code: String) -> Bool {
        // "room-secret" (a sealed room), or just the room (an older Mac's code).
        let parts = code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", maxSplits: 1).map(String.init)
        let room = (parts.first ?? "").filter { $0.isLetter || $0.isNumber }
        let secret = parts.count > 1 ? parts[1].filter { $0.isLetter || $0.isNumber } : ""
        guard room.count >= 8, room.count <= 24, parts.count == 1 || secret.count >= 16 else { return false }
        stop()
        if secret.isEmpty { Keychain.delete("bridge.secret"); self.secret = nil } else { Keychain.set(secret, for: "bridge.secret"); self.secret = secret }
        UserDefaults.standard.set(room, forKey: roomKey)
        UserDefaults.standard.set("left", forKey: sideKey)
        peerSeen = nil
        start()
        return true
    }

    /// The other side is a Mac (a friend's), not the web habitat.
    private(set) var peerIsMac = false

    /// Starts a new room with the doorway on `side` of this screen.
    func create(side: String) {
        stop()
        let s = NoteSeal.newSecret()
        Keychain.set(s, for: "bridge.secret"); secret = s
        peerIsTerrarium = false
        UserDefaults.standard.set(ScreenBridge.randomCode(12), forKey: roomKey)
        UserDefaults.standard.set(side == "left" ? "left" : "right", forKey: sideKey)
        peerSeen = nil
        start()
    }

    /// The link the other screen opens: its doorway is on the opposite edge.
    var inviteURL: String? { invite(terrarium: false) }

    /// The link for the other screen; a Terrarium one opens the habitat in Terrarium mode (TERRARIUM.md). The pairing
    /// secret rides in the #fragment, which the browser keeps to itself.
    func invite(terrarium: Bool) -> String? {
        guard let room else { return nil }
        var base = habitat
        if !base.hasSuffix("/") && !base.contains("?") { base += "/" }
        return "\(base)?room=\(room)&side=\(opposite)" + (terrarium ? "&terrarium=1" : "") + (secret.map { "#k=\($0)" } ?? "")
    }

    /// The code a friend's Mac pastes: the room, and the secret when the room is sealed.
    var friendCode: String? { room.map { r in secret.map { "\(r)-\($0)" } ?? r } }

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
                    await MainActor.run { self.connected = true; self.onStatus(); self.send(["type": "hello", "side": self.side ?? "right", "moss": self.moss(), "device": "mac"]) }
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
            self.send(["type": "hello", "side": self.side ?? "right", "moss": self.moss(), "device": "mac"])
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
        Keychain.delete("bridge.secret"); secret = nil
        peerIsTerrarium = false
        UserDefaults.standard.removeObject(forKey: roomKey)
        UserDefaults.standard.removeObject(forKey: sideKey)
        peerSeen = nil
        onStatus()
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              msg["event"] as? String == "message", let text = msg["message"] as? String else { return }
        // A sealed room only takes sealed notes.
        let body: Data?
        if let key = noteKey, let room { body = NoteSeal.open(text, key: key, room: room) } else { body = text.data(using: .utf8) }
        guard let body, let note = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              note["v"] as? Int == 1, let from = note["from"] as? String, from != device else { return }
        DispatchQueue.main.async {
            self.peerSeen = Date()
            switch note["type"] as? String {
            case "hello":
                self.peerIsMac = note["device"] as? String == "mac"
                let terrarium = note["terrarium"] as? Bool == true
                let fresh = terrarium && !self.peerIsTerrarium
                self.peerIsTerrarium = terrarium
                if note["reply"] == nil { self.send(["type": "hello", "side": self.side ?? "right", "reply": true, "moss": self.moss(), "device": "mac"]) }
                // A Terrarium just opened (or reloaded): catch it up on Claude straight away.
                if terrarium, note["reply"] == nil || fresh, let s = self.status() { self.send(s) }
                self.onStatus()
            case "walk":
                // Notes are addressed to the edge they arrive through, which is our doorway.
                guard note["to"] as? String == self.side, let species = note["species"] as? String, species.count < 40 else { return }
                func num(_ k: String) -> Double { (note[k] as? NSNumber)?.doubleValue ?? 0 }
                self.onWalk(Walk(species: species, y: num("y"), vx: num("vx"), vy: num("vy"), air: (note["air"] as? Bool) ?? false,
                                 owner: (note["owner"] as? String).map { String($0.prefix(24)) }))
                self.onStatus()
            case "visitor":
                guard note["to"] as? String == self.side, note["kind"] as? String == "ferry" else { return }
                let riders = ((note["riders"] as? [Any]) ?? []).compactMap { $0 as? String }.filter { $0.count < 40 }.prefix(3)
                self.onFerry(Array(riders), (note["y"] as? NSNumber)?.doubleValue ?? 0.5)
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
        guard let json = try? JSONSerialization.data(withJSONObject: full) else { return }
        let body: Data
        if let key = noteKey, let room {
            guard let s = try? NoteSeal.seal(json, key: key, room: room) else { return }
            body = Data(s.utf8)
        } else { body = json }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Claude's sessions, for a Terrarium on the other side (never to a friend's Mac or a plain linked screen).
    func sendStatus(_ note: [String: Any]) {
        guard linked, peerIsTerrarium, peerOnline else { return }
        send(note)
    }

    /// Something leaves through our doorway; on the other screen it arrives through the opposite edge.
    func cross(_ note: [String: Any]) {
        var n = note
        n["to"] = opposite
        send(n)
    }

    // MARK: Link page (served on 127.0.0.1 only)

    func linkPage(terrarium: Bool = false) -> String {
        guard let url = invite(terrarium: terrarium), let side else { return "<p>No screen linked. Use the Gremlets menu → Link Another Screen.</p>" }
        if terrarium { return terrariumPage(url) }
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
          <p><a href="/terrarium">Make this iPad a Terrarium →</a> (a home for Gremlets that stays on all day, and shows what Claude is up to)</p>
          <p style="font-size: .85rem">Only Gremlet names, which edge they left through and how fast they were going pass through ntfy.sh, a free public relay, on a channel named after this private code\(sealed ? ", sealed with a key that's only in this code" : ""). Unlink from the menu any time.</p>
        </main>
        """
    }

    /// The Terrarium version of the link page: the same room, opened in Terrarium mode.
    private func terrariumPage(_ url: String) -> String {
        let qr = PhoneLink.qrPNG(url).map { "<img src=\"data:image/png;base64,\($0)\" alt=\"QR code\">" } ?? ""
        let state = peerIsTerrarium && peerOnline ? "<p class=\"ok\">The Terrarium is open and linked.</p>" : "<p>Waiting for the iPad to open the link…</p>"
        return """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Make this iPad a Terrarium</title>
        <style>
          body { font: 16px/1.5 -apple-system, system-ui, sans-serif; background: #f3f6ef; color: #1f2a22; margin: 0; display: grid; place-items: center; min-height: 100vh; }
          main { max-width: 500px; padding: 32px 20px; text-align: center; }
          h1 { font-size: 1.5rem; margin: 0 0 8px; }
          img { width: 240px; height: 240px; image-rendering: pixelated; background: #fff; padding: 12px; border-radius: 12px; margin: 16px 0; }
          p, li { color: #5c6b5f; margin: 8px 0; } ol { text-align: left; }
          .ok { color: #2f7a3a; }
        </style>
        <main>
          <h1>Make this iPad a Terrarium</h1>
          <p>A Gremlets home that stays on all day on the desk: Gremlets walk over from your Mac and live there, sleep at night, and show what Claude is doing (a thought cloud while it works, a lantern when it needs you, a flag when it's done).</p>
          \(qr)
          <ol>
            <li>Point the iPad's camera at the code and open the link in Safari.</li>
            <li>Tap Share → <b>Add to Home Screen</b>, then open Gremlets from the Home Screen (full screen, no Safari bars).</li>
            <li>Keep it on its charger: Settings → Display &amp; Brightness → Auto-Lock → <b>Never</b>.</li>
          </ol>
          \(state)
          <p style="font-size: .85rem">Notes pass through ntfy.sh, a free public relay, sealed with a key that only lives in this code. Project names are sent only if you turn on Show Project Names on the Terrarium in the Gremlets menu; otherwise they're "Project 1", "Project 2".</p>
        </main>
        """
    }
}
