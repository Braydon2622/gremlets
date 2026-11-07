import AppKit
import Network
import GremletsCore

// MARK: - Bond storage

/// Saves how long you've had each Gremlet and how often you've petted and poked it (UserDefaults, per species).
final class BondStore {
    private struct Record: Codable {
        var days = 0, pets = 0, pokes = 0, focus = 0
        var hours = 0.0
        var lastDay = ""
        /// Seconds spent in each kind of place (its favourite spot is the one with the most).
        var spots: [String: Double] = [:]

        init() {}
        // Tolerant decoding: records saved by older versions lack newer fields, and must still load.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 0
            pets = try c.decodeIfPresent(Int.self, forKey: .pets) ?? 0
            pokes = try c.decodeIfPresent(Int.self, forKey: .pokes) ?? 0
            focus = try c.decodeIfPresent(Int.self, forKey: .focus) ?? 0
            hours = try c.decodeIfPresent(Double.self, forKey: .hours) ?? 0
            lastDay = try c.decodeIfPresent(String.self, forKey: .lastDay) ?? ""
            spots = try c.decodeIfPresent([String: Double].self, forKey: .spots) ?? [:]
        }
    }
    private var records: [String: Record] = [:]
    private let key = "bonds.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let r = try? JSONDecoder().decode([String: Record].self, from: data) { records = r }
    }

    func bond(_ id: String) -> Bond {
        let r = records[id] ?? Record()
        return Bond(daysTogether: r.days, pets: r.pets, pokes: r.pokes, hoursTogether: r.hours, focusSessions: r.focus)
    }

    static func dayKey(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: d)
    }
    private static var today: String { dayKey() }

    /// Counts today as a day together (once per calendar day).
    func markSeenToday(_ id: String) {
        var r = records[id] ?? Record()
        let t = BondStore.today
        if r.lastDay != t { r.days += 1; r.lastDay = t }
        records[id] = r
    }

    func addPet(_ id: String) { records[id, default: Record()].pets += 1 }
    func addPoke(_ id: String) { records[id, default: Record()].pokes += 1 }
    func addFocusSession(_ id: String) { records[id, default: Record()].focus += 1 }
    func addTime(_ id: String, seconds: Double) { records[id, default: Record()].hours += seconds / 3600 }
    func addSpot(_ id: String, _ place: String, seconds: Double) { records[id, default: Record()].spots[place, default: 0] += seconds }
    func favouriteSpot(_ id: String) -> String? { records[id]?.spots.max { $0.value < $1.value }?.key }
    func daysTogether(_ id: String) -> Int { records[id]?.days ?? 0 }

    func save() {
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Focus log

/// Minutes focused per day and the streak (UserDefaults).
final class FocusLogStore {
    private let key = "focusLog.v1"
    private(set) var log = FocusLog()

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let l = try? JSONDecoder().decode(FocusLog.self, from: d) { log = l }
    }

    func record(minutes: Double) {
        log.record(minutes: minutes, day: BondStore.dayKey())
        if let d = try? JSONEncoder().encode(log) { UserDefaults.standard.set(d, forKey: key) }
    }

    var todayMinutes: Double { log.minutes(on: BondStore.dayKey()) }

    var streak: Int {
        log.streak(today: BondStore.dayKey()) { day in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            guard let d = f.date(from: day), let prev = Calendar.current.date(byAdding: .day, value: -1, to: d) else { return "" }
            return BondStore.dayKey(prev)
        }
    }
}

// MARK: - Focus timer

/// A simple focus/break timer. Gremlets doze during focus and throw a dance party when the break starts.
final class FocusTimer {
    enum Phase: Equatable { case idle, focus(end: Date), rest(end: Date) }
    private(set) var phase: Phase = .idle
    var breakMinutes = 5.0
    /// Length of the current/last focus session.
    private(set) var focusMinutes = 0.0

    var onFocusStart: () -> Void = {}
    var onBreakStart: () -> Void = {}
    var onBreakEnd: () -> Void = {}

    func startFocus(minutes: Double) {
        focusMinutes = minutes
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
/// focus timer or open the wallet-link page. The Host header must be 127.0.0.1/localhost, so a hostile site that
/// re-points its own domain at 127.0.0.1 (DNS rebinding) is turned away too.
///
/// Exception: registered `pages` (the wallet-link page) are plain GETs without the custom header, so the browser can
/// open them. They have no side effects; anything they do goes back through header-protected POSTs.
final class ControlServer {
    /// Read-only HTML pages served on GET without the X-Gremlets header.
    var pages: [String: () -> String] = [:]
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
            let (status, body, type) = self.route(text)
            let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict"][status] ?? "OK"
            var headers = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\n"
            headers += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\n"
            if type.hasPrefix("text/html") {
                // Page may only talk back to this server; scripts must be the inline one we wrote.
                headers += "Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'\r\n"
            }
            let resp = headers + "Connection: close\r\n\r\n" + body
            conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private static let json = "application/json"

    private func route(_ request: String) -> (Int, String, String) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return (400, #"{"ok":false,"error":"bad request"}"#, Self.json) }
        let method = String(parts[0]).uppercased()
        guard method == "GET" || method == "POST" else { return (405, #"{"ok":false,"error":"method not allowed"}"#, Self.json) }
        let headerLines = lines.dropFirst().map { $0.lowercased() }
        let host = headerLines.first { $0.hasPrefix("host:") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) } ?? ""
        let hostName = host.split(separator: ":").first.map(String.init) ?? ""
        guard hostName == "127.0.0.1" || hostName == "localhost" else { return (403, #"{"ok":false,"error":"bad host"}"#, Self.json) }
        let target = String(parts[1])
        let pathAndQuery = target.split(separator: "?", maxSplits: 1).map(String.init)
        if method == "GET", let page = pages[pathAndQuery[0]] { return (200, page(), "text/html; charset=utf-8") }
        let hasHeader = headerLines.contains { $0.hasPrefix("x-gremlets:") }
        guard hasHeader else { return (403, #"{"ok":false,"error":"missing X-Gremlets header"}"#, Self.json) }
        var query: [String: String] = [:]
        if pathAndQuery.count > 1 {
            for pair in pathAndQuery[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { query[kv[0]] = kv[1] }
            }
        }
        if method == "POST", let split = request.range(of: "\r\n\r\n") {
            let body = String(request[split.upperBound...])
            if !body.isEmpty { query["_body"] = String(body.prefix(4000)) }
        }
        let (status, body) = handle(method, pathAndQuery[0], query)
        return (status, body, Self.json)
    }
}
