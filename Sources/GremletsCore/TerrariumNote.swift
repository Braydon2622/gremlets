import Foundation
import CryptoKit

/// The Terrarium (docs/plans/TERRARIUM.md): an iPad on the desk running the web habitat full time, linked to this Mac
/// over the screen bridge. Two pieces live here so both the app and the tests can use them:
///
/// - **`TerrariumBoard`**: what each Claude Code session is doing (thinking / waiting / done) and the last few
///   changes, as the `status` note the iPad draws (a thought cloud, a lantern with a sign, a flag in the moss).
///   Project names go out only when "Show project names" is on; otherwise "Project 1", "Project 2"…
/// - **`NoteSeal`**: every note on a Terrarium room is sealed with AES-GCM. The relay (ntfy.sh) is public, so the key
///   comes from a secret that only ever travels inside the QR code / link (in its #fragment, which browsers never
///   send to a server), stretched with HKDF-SHA256 and bound to the room. The browser does the same with WebCrypto
///   (web/js/seal.js).
public struct TerrariumStatus: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable, CaseIterable { case thinking, waiting, done }
    public struct Session: Codable, Equatable, Sendable {
        /// A short id for the session (not Claude's own session id).
        public var id: String
        public var project: String
        public var state: State
    }
    public struct Event: Codable, Equatable, Sendable {
        public var project: String
        public var state: State
        /// Unix seconds.
        public var at: Double
    }
    public var type = "status"
    public var sessions: [Session]
    /// The last few changes, oldest first.
    public var recent: [Event]

    public init(sessions: [Session], recent: [Event]) { self.sessions = sessions; self.recent = recent }

    public func json() -> [String: Any] {
        ["type": type,
         "sessions": sessions.map { ["id": $0.id, "project": $0.project, "state": $0.state.rawValue] },
         "recent": recent.map { ["project": $0.project, "state": $0.state.rawValue, "at": ($0.at * 10).rounded() / 10] }]
    }

    /// Reads a status note back (what the iPad does; used by the tests to check the round trip).
    public init?(json o: [String: Any]) {
        guard o["type"] as? String == "status", let ss = o["sessions"] as? [[String: Any]], let rs = o["recent"] as? [[String: Any]] else { return nil }
        sessions = ss.compactMap { s in
            guard let id = s["id"] as? String, let p = s["project"] as? String, let st = (s["state"] as? String).flatMap(State.init) else { return nil }
            return Session(id: id, project: p, state: st)
        }
        recent = rs.compactMap { e in
            guard let p = e["project"] as? String, let st = (e["state"] as? String).flatMap(State.init) else { return nil }
            return Event(project: p, state: st, at: (e["at"] as? NSNumber)?.doubleValue ?? 0)
        }
    }
}

public final class TerrariumBoard {
    public static let recentMax = 5
    /// A finished session stays on the board (its flag in the moss) this long.
    public static let doneLinger = 30.0 * 60

    private struct Live { var id: String; var project: String; var state: TerrariumStatus.State; var since: Double }
    private var live: [String: Live] = [:]
    private var order: [String] = []
    private var recent: [TerrariumStatus.Event] = []
    private var nextID = 0
    /// Project name → its number for "Project N" (kept by the app so the numbers stay put between launches).
    public var aliases: [String: Int] = [:]

    public init() {}

    /// A session changed state (`state` nil: it ended). Returns whether anything changed.
    @discardableResult
    public func record(session key: String, project: String, state: TerrariumStatus.State?, at now: Double) -> Bool {
        if aliases[project] == nil { aliases[project] = (aliases.values.max() ?? 0) + 1 }
        guard let state else {
            guard live[key] != nil else { return false }
            live[key] = nil; order.removeAll { $0 == key }
            return true
        }
        if let l = live[key], l.state == state, l.project == project { return false }
        if live[key] == nil { nextID += 1; order.append(key) }
        live[key] = Live(id: live[key]?.id ?? "s\(nextID)", project: project, state: state, since: now)
        recent.append(TerrariumStatus.Event(project: project, state: state, at: now))
        if recent.count > TerrariumBoard.recentMax { recent.removeFirst(recent.count - TerrariumBoard.recentMax) }
        return true
    }

    /// Drops sessions that finished a while ago. Returns whether anything went.
    @discardableResult
    public func prune(now: Double) -> Bool {
        let gone = live.filter { $0.value.state == .done && now - $0.value.since > TerrariumBoard.doneLinger }.map(\.key)
        for k in gone { live[k] = nil; order.removeAll { $0 == k } }
        return !gone.isEmpty
    }

    public func name(_ project: String, showNames: Bool) -> String {
        showNames ? String(project.prefix(32)) : "Project \(aliases[project] ?? 1)"
    }

    public func snapshot(showNames: Bool) -> TerrariumStatus {
        TerrariumStatus(sessions: order.compactMap { live[$0] }.map { .init(id: $0.id, project: name($0.project, showNames: showNames), state: $0.state) },
                        recent: recent.map { .init(project: name($0.project, showNames: showNames), state: $0.state, at: $0.at) })
    }
}

public enum NoteSeal {
    static let salt = Data("gremlets-terrarium-v1".utf8)

    /// The note key for a room, from the pairing secret.
    public static func key(secret: String, room: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(secret.utf8)), salt: salt, info: Data(room.utf8), outputByteCount: 32)
    }

    /// A random pairing secret (base32-ish, 26 characters, about 130 bits).
    public static func newSecret() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        return String((0..<26).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
    }

    /// Seals a note: `{"v":2,"n":<nonce, base64>,"c":<ciphertext + tag, base64>}`. The room is bound in as
    /// additional data, so a note can't be replayed into another room.
    public static func seal(_ plaintext: Data, key: SymmetricKey, room: String, nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> String {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: Data(room.utf8))
        let env: [String: Any] = ["v": 2, "n": Data(box.nonce).base64EncodedString(), "c": (box.ciphertext + box.tag).base64EncodedString()]
        return String(data: try JSONSerialization.data(withJSONObject: env, options: [.sortedKeys]), encoding: .utf8)!
    }

    /// Opens a sealed note (nil if it isn't one, or it doesn't open with this key and room).
    public static func open(_ envelope: String, key: SymmetricKey, room: String) -> Data? {
        guard let d = envelope.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              o["v"] as? Int == 2, let n = (o["n"] as? String).flatMap({ Data(base64Encoded: $0) }), n.count == 12,
              let c = (o["c"] as? String).flatMap({ Data(base64Encoded: $0) }), c.count >= 16,
              let nonce = try? AES.GCM.Nonce(data: n),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: c.prefix(c.count - 16), tag: c.suffix(16)) else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: Data(room.utf8))
    }
}
