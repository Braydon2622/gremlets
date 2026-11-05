import AppKit
import Network
import GremletsCore

// MARK: - Bond storage

/// Saves how long you've had each Gremlet and how often you've petted and poked it (UserDefaults, per species).
final class BondStore {
    private struct Record: Codable {
        var days = 0, pets = 0, pokes = 0
        var hours = 0.0
        var lastDay = ""
    }
    private var records: [String: Record] = [:]
    private let key = "bonds.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let r = try? JSONDecoder().decode([String: Record].self, from: data) { records = r }
    }

    func bond(_ id: String) -> Bond {
        let r = records[id] ?? Record()
        return Bond(daysTogether: r.days, pets: r.pets, pokes: r.pokes, hoursTogether: r.hours)
    }

    private static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    /// Counts today as a day together (once per calendar day).
    func markSeenToday(_ id: String) {
        var r = records[id] ?? Record()
        let t = BondStore.today
        if r.lastDay != t { r.days += 1; r.lastDay = t }
        records[id] = r
    }

    func addPet(_ id: String) { records[id, default: Record()].pets += 1 }
    func addPoke(_ id: String) { records[id, default: Record()].pokes += 1 }
    func addTime(_ id: String, seconds: Double) { records[id, default: Record()].hours += seconds / 3600 }

    func save() {
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Focus timer

/// A simple focus/break timer. Gremlets doze during focus and throw a dance party when the break starts.
final class FocusTimer {
    enum Phase: Equatable { case idle, focus(end: Date), rest(end: Date) }
    private(set) var phase: Phase = .idle
    var breakMinutes = 5.0

    var onFocusStart: () -> Void = {}
    var onBreakStart: () -> Void = {}
    var onBreakEnd: () -> Void = {}

    func startFocus(minutes: Double) {
        phase = .focus(end: Date().addingTimeInterval(minutes * 60))
        onFocusStart()
    }

    func stop() { phase = .idle }

    /// Call regularly (the app ticks it about once a second).
    func update(now: Date = Date()) {
        switch phase {
        case .focus(let end) where now >= end:
            phase = .rest(end: now.addingTimeInterval(breakMinutes * 60))
            onBreakStart()
        case .rest(let end) where now >= end:
            phase = .idle
            onBreakEnd()
        default: break
        }
    }

    /// Text for the menu bar, e.g. "24:59" or "Break 4:12"; nil when idle.
    var label: String? {
        func mmss(_ d: Date) -> String {
            let s = max(0, Int(d.timeIntervalSinceNow.rounded(.up)))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        switch phase {
        case .idle: return nil
        case .focus(let end): return mmss(end)
        case .rest(let end): return "Break " + mmss(end)
        }
    }

    var isFocusing: Bool { if case .focus = phase { return true }; return false }
}

// MARK: - Local control channel

/// Tiny HTTP endpoint on 127.0.0.1 so scripts and the `gremlet` command can make the Gremlets react.
///
/// Safety: it only listens on the loopback interface (nothing on your network can reach it), every request must
/// carry an `X-Gremlets` header (web pages can't add custom headers to cross-site requests without a CORS
/// preflight, which this server never approves), and the only things it can do are trigger animations and the
/// focus timer.
final class ControlServer {
    static let defaultPort: UInt16 = 47920
    private var listener: NWListener?
    private let handle: (_ method: String, _ path: String, _ query: [String: String]) -> (Int, String)

    init(handle: @escaping (_ method: String, _ path: String, _ query: [String: String]) -> (Int, String)) {
        self.handle = handle
    }

    func start(port: UInt16 = ControlServer.defaultPort) {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        do {
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                self?.receive(conn)
            }
            l.stateUpdateHandler = { state in
                if case .failed(let err) = state { NSLog("Gremlets control channel failed: \(err)") }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            NSLog("Gremlets control channel unavailable: \(error)")
        }
    }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            let (status, body) = self.route(text)
            let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
            let resp = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private func route(_ request: String) -> (Int, String) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return (400, #"{"ok":false,"error":"bad request"}"#) }
        let method = String(parts[0]).uppercased()
        guard method == "GET" || method == "POST" else { return (405, #"{"ok":false,"error":"method not allowed"}"#) }
        let hasHeader = lines.dropFirst().contains { $0.lowercased().hasPrefix("x-gremlets:") }
        guard hasHeader else { return (403, #"{"ok":false,"error":"missing X-Gremlets header"}"#) }
        let target = String(parts[1])
        let pathAndQuery = target.split(separator: "?", maxSplits: 1).map(String.init)
        var query: [String: String] = [:]
        if pathAndQuery.count > 1 {
            for pair in pathAndQuery[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { query[kv[0]] = kv[1] }
            }
        }
        return handle(method, pathAndQuery[0], query)
    }
}
