import AppKit
import CoreImage
import GremletsCore

/// Lets Gremlets hop between this Mac and your phone (the web habitat at braydonhartai.com/gremlets).
///
/// Pairing makes a long random code. Both sides send tiny JSON notes through ntfy.sh, a free public message relay that
/// needs no account, on a channel named after that code: "Kindlet is jumping to the phone", "Kindlet is coming home and
/// grew a tulip and a carrot". Only Gremlet names and plant kinds are sent, nothing about you. Anyone who knew the code
/// could read those notes, so it's long, random and stays on your devices; Unlink makes a fresh one next time.
final class PhoneLink {
    struct Arrival { let species: String; let harvest: [Plant] }

    private let codeKey = "phonelink.code", lastKey = "phonelink.lastID", awayKey = "phonelink.onPhone"
    static let relay = "https://ntfy.sh"
    static let habitat = "https://braydonhartai.com/gremlets/web/"

    var onArrive: (Arrival) -> Void = { _ in }
    var onStatus: () -> Void = {}
    private(set) var connected = false
    private var task: Task<Void, Never>?

    var code: String? { UserDefaults.standard.string(forKey: codeKey) }
    var isPaired: Bool { code != nil }
    private var topic: String? { code.map { "gremlets-\($0)" } }

    /// Gremlets currently visiting the phone (so they aren't brought back on relaunch).
    var onPhone: [String] {
        get { UserDefaults.standard.stringArray(forKey: awayKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: awayKey) }
    }

    var pairURL: String? { code.map { "\(PhoneLink.habitat)?pair=\($0)" } }

    /// Makes a pairing code if there isn't one yet and starts listening.
    @discardableResult
    func pair() -> String {
        if let c = code { return c }
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        let c = String((0..<24).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
        UserDefaults.standard.set(c, forKey: codeKey)
        UserDefaults.standard.removeObject(forKey: lastKey)
        start()
        return c
    }

    func unpair() {
        task?.cancel(); task = nil
        connected = false
        UserDefaults.standard.removeObject(forKey: codeKey)
        UserDefaults.standard.removeObject(forKey: lastKey)
        onStatus()
    }

    // MARK: Receiving

    /// Keeps one streaming connection open to the relay and reconnects with a backoff if it drops.
    func start() {
        guard task == nil, let topic else { return }
        task = Task { [weak self] in
            var backoff: UInt64 = 2
            while !Task.isCancelled {
                guard let self else { return }
                let since = UserDefaults.standard.string(forKey: self.lastKey) ?? "\(Int(Date().timeIntervalSince1970) - 120)"
                guard let url = URL(string: "\(PhoneLink.relay)/\(topic)/json?since=\(since)") else { return }
                do {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 300
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    await MainActor.run { self.connected = true; self.onStatus() }
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
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              msg["event"] as? String == "message", let id = msg["id"] as? String else { return }
        UserDefaults.standard.set(id, forKey: lastKey)
        guard let body = (msg["message"] as? String)?.data(using: .utf8),
              let note = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              note["type"] as? String == "jump", note["to"] as? String == "mac",
              let species = note["species"] as? String, species.count < 40 else { return }
        let harvest = (note["harvest"] as? [[String: Any]] ?? []).prefix(30).compactMap { h -> Plant? in
            guard let k = (h["kind"] as? String).flatMap(PlantKind.init(rawValue:)) else { return nil }
            var p = Plant(kind: k, golden: h["golden"] as? Bool ?? false)
            p.growth = 1
            return p
        }
        DispatchQueue.main.async { self.onArrive(Arrival(species: species, harvest: Array(harvest))) }
    }

    // MARK: Sending

    func sendToPhone(species: String) {
        post(["v": 1, "type": "jump", "to": "phone", "from": "mac", "species": species])
        onPhone = onPhone + [species]
    }

    private func post(_ note: [String: Any]) {
        guard let topic, let url = URL(string: "\(PhoneLink.relay)/\(topic)"),
              let body = try? JSONSerialization.data(withJSONObject: note) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: Pairing page (served on 127.0.0.1 only)

    func pairPage() -> String {
        guard let url = pairURL else { return "<p>Not paired.</p>" }
        let qr = PhoneLink.qrPNG(url).map { "<img src=\"data:image/png;base64,\($0)\" alt=\"QR code\">" } ?? ""
        return """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Pair Gremlets with your phone</title>
        <style>
          body { font: 16px/1.5 -apple-system, system-ui, sans-serif; background: #f3f6ef; color: #1f2a22; margin: 0; display: grid; place-items: center; min-height: 100vh; }
          main { max-width: 440px; padding: 32px 20px; text-align: center; }
          h1 { font-size: 1.5rem; margin: 0 0 8px; }
          img { width: 240px; height: 240px; image-rendering: pixelated; background: #fff; padding: 12px; border-radius: 12px; margin: 16px 0; }
          p { color: #5c6b5f; margin: 8px 0; }
          code { font-size: 0.8rem; word-break: break-all; background: #e7eee3; padding: 4px 6px; border-radius: 4px; }
        </style>
        <main>
          <h1>Pair Gremlets with your phone</h1>
          <p>Point your iPhone camera at this code and open the link. Then tap Share → Add to Home Screen to keep it handy.</p>
          \(qr)
          <p>Or open this on your phone:<br><code>\(url)</code></p>
          <p>Then use the Gremlets menu → Send to Phone, and watch one hop through the portal.</p>
          <p style="font-size: .85rem">Only Gremlet names and plant kinds pass through ntfy.sh, a free public relay, on a channel named after this private code. Unlink from the menu any time.</p>
        </main>
        """
    }

    static func qrPNG(_ text: String) -> String? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.base64EncodedString()
    }
}
