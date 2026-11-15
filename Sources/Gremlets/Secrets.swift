import Foundation

/// Gremlets' small secrets: the Terrarium's pairing secret and any key
/// Braydon types into Settings.
///
/// They used to live in the login Keychain, but Gremlets is ad-hoc signed, so every rebuild is a "new app" to the
/// Keychain and macOS stopped the app with a password prompt each time (Nov 10: the menu bar app froze until it was
/// answered). They now live in one private file, ~/Library/Application Support/Gremlets/secrets.json, readable only by
/// Braydon's account (0600, folder 0700), never in the repo or UserDefaults. A stable signing identity would allow
/// going back to the Keychain.
enum Secrets {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gremlets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("secrets.json")
    }
    private static var cache: [String: String]?

    private static func load() -> [String: String] {
        if let c = cache { return c }
        let d = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
        cache = d
        return d
    }

    private static func save(_ d: [String: String]) {
        cache = d
        guard let data = try? JSONSerialization.data(withJSONObject: d) else { return }
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func get(_ account: String) -> String? { load()[account] }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        var d = load(); d[account] = value; save(d); return true
    }

    static func delete(_ account: String) {
        var d = load(); d[account] = nil; save(d)
    }
}
