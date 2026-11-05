/// Who gets which Gremlets on the desktop.
///
/// - Gremlets whose NFT you own (proven with a free wallet signature, read from the chain) are yours to keep out.
/// - Your own drop-in sprites (species not in the collection) are always yours.
/// - Everyone can try any other Gremlet in a demo: a few at a time, for a limited session.
///
/// Pure logic: the macOS layer does the networking and the wallet page; this file builds the requests and
/// interprets the answers so it can be unit tested without a network.

// MARK: - Hex & Ethereum encoding helpers

public enum Hex {
    public static func encode(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef")
        var s = "0x"
        s.reserveCapacity(2 + bytes.count * 2)
        for b in bytes { s.append(digits[Int(b >> 4)]); s.append(digits[Int(b & 15)]) }
        return s
    }

    public static func decode(_ text: String) -> [UInt8]? {
        var s = Substring(text)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = s.dropFirst(2) }
        guard s.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(s.count / 2)
        var it = s.makeIterator()
        while let hi = it.next(), let lo = it.next() {
            guard let h = hi.hexDigitValue, let l = lo.hexDigitValue else { return nil }
            out.append(UInt8(h << 4 | l))
        }
        return out
    }
}

public enum Ethereum {
    /// The only chain the app talks to until Braydon approves mainnet: Base Sepolia (testnet).
    public static let baseSepoliaChainID = 84532
    public static let baseSepoliaRPC = "https://sepolia.base.org"

    /// Lower-cased 0x + 40 hex chars, or nil.
    public static func normalizeAddress(_ s: String) -> String? {
        let t = s.filter { !$0.isWhitespace }.lowercased()
        guard t.count == 42, t.hasPrefix("0x"), Hex.decode(t)?.count == 20 else { return nil }
        return t
    }

    /// EIP-55 mixed-case checksum form, for display.
    public static func checksumAddress(_ s: String) -> String? {
        guard let a = normalizeAddress(s) else { return nil }
        let body = String(a.dropFirst(2))
        let hash = Keccak.hash256(body)
        var out = "0x"
        for (i, ch) in body.enumerated() {
            let nibble = (hash[i / 2] >> (i % 2 == 0 ? 4 : 0)) & 0xF
            out.append(ch.isLetter && nibble >= 8 ? Character(ch.uppercased()) : ch)
        }
        return out
    }

    /// "0x1234…abcd"
    public static func shortAddress(_ s: String) -> String {
        let a = checksumAddress(s) ?? s
        return a.count > 12 ? "\(a.prefix(6))…\(a.suffix(4))" : a
    }

    /// EIP-191 `personal_sign` hash: keccak256("\x19Ethereum Signed Message:\n" + len + message).
    public static func personalMessageHash(_ message: String) -> [UInt8] {
        let body = Array(message.utf8)
        return Keccak.hash256(Array("\u{19}Ethereum Signed Message:\n\(body.count)".utf8) + body)
    }

    /// First 4 bytes of keccak256(signature), e.g. "ownerOf(uint256)" → 0x6352211e.
    public static func selector(_ signature: String) -> [UInt8] { Array(Keccak.hash256(signature).prefix(4)) }

    static func word(_ value: UInt64) -> [UInt8] {
        var w = [UInt8](repeating: 0, count: 32)
        for i in 0..<8 { w[31 - i] = UInt8(truncatingIfNeeded: value >> UInt64(8 * i)) }
        return w
    }

    /// Calldata for ERC-721 `ownerOf(tokenId)`.
    public static func ownerOfCall(_ tokenId: Int) -> String { Hex.encode(selector("ownerOf(uint256)") + word(UInt64(tokenId))) }

    /// Address held in the last 20 bytes of a 32-byte ABI word (eth_call result). nil for empty/short results.
    public static func addressFromWord(_ result: String) -> String? {
        guard let b = Hex.decode(result), b.count >= 32 else { return nil }
        let addr = Array(b[12..<32])
        if addr.allSatisfy({ $0 == 0 }) { return nil }
        return Hex.encode(addr)
    }

    /// Input for the `ecrecover` precompile (address 0x…01): hash ‖ v ‖ r ‖ s, each 32 bytes.
    /// Accepts a 65-byte r‖s‖v signature with v as 27/28 or 0/1. Returns nil for malformed signatures.
    /// Rejects "high-s" signatures (EIP-2) so each message has a single valid signature.
    public static func ecrecoverInput(hash: [UInt8], signature: String) -> String? {
        guard hash.count == 32, let sig = Hex.decode(signature), sig.count == 65 else { return nil }
        var v = sig[64]
        if v < 27 { v += 27 }
        guard v == 27 || v == 28 else { return nil }
        let r = Array(sig[0..<32]), s = Array(sig[32..<64])
        guard r.contains(where: { $0 != 0 }), s.contains(where: { $0 != 0 }) else { return nil }
        // secp256k1n / 2
        let halfN: [UInt8] = Hex.decode("7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0")!
        guard s.lexicographicallyPrecedes(halfN) || s == halfN else { return nil }
        return Hex.encode(hash + word(UInt64(v)) + r + s)
    }

    public static let ecrecoverPrecompile = "0x0000000000000000000000000000000000000001"

    /// The message the wallet page asks you to sign. Free, no transaction; the nonce stops replaying old signatures.
    public static func proofMessage(nonce: String) -> String {
        """
        Gremlets desktop app: prove this wallet is mine so my Gremlets can come out.

        This signature is free. It does not send a transaction or give any permission.

        Network: Base Sepolia (testnet)
        Nonce: \(nonce)
        """
    }
}

// MARK: - Access rules

/// What the app knows about your collection (persisted by the platform layer).
public struct Ownership: Codable, Equatable, Sendable {
    public var address: String?            // proven wallet address (lower-case)
    public var ownedTokenIDs: [Int]        // token ids this wallet held at the last check
    public var checkedAt: Double?          // seconds since 1970

    public init(address: String? = nil, ownedTokenIDs: [Int] = [], checkedAt: Double? = nil) {
        self.address = address; self.ownedTokenIDs = ownedTokenIDs; self.checkedAt = checkedAt
    }

    /// Token ids from a batch of `ownerOf` results (tokenId → owner address, nil if unminted/burned).
    public static func ownedIDs(_ owners: [Int: String?], by address: String) -> [Int] {
        guard let me = Ethereum.normalizeAddress(address) else { return [] }
        return owners.compactMap { id, owner in owner.flatMap(Ethereum.normalizeAddress) == me ? id : nil }.sorted()
    }
}

/// Demo limits for Gremlets you don't own. Tunable in one place.
public struct DemoPolicy: Equatable, Sendable {
    public var maxOut: Int                // demo Gremlets allowed out at once
    public var sessionSeconds: Double     // how long a demo session lasts
    public var cooldownSeconds: Double    // wait before a new session can start

    public init(maxOut: Int = 3, sessionSeconds: Double = 15 * 60, cooldownSeconds: Double = 0) {
        self.maxOut = maxOut; self.sessionSeconds = sessionSeconds; self.cooldownSeconds = cooldownSeconds
    }
}

public enum AccessKind: Equatable, Sendable {
    case owned          // NFT held by your proven wallet
    case custom         // your own drop-in sprites (not part of the collection)
    case unlocked       // collection not on chain yet (preview build) or dev override: everything is open
    case demo           // try it out within the demo limits
}

/// Decides, per species, whether it's yours or a demo, and runs the demo session clock.
public struct Access: Sendable {
    /// token id → species id (nft/tokens.json).
    public let tokens: [Int: String]
    public var ownership: Ownership
    public var policy: DemoPolicy
    /// When true (no contract configured yet, or `--unlock-all`), nothing is gated.
    public var gatingEnabled: Bool

    public private(set) var sessionStart: Double?
    public private(set) var lastSessionEnd: Double?

    public init(tokens: [Int: String], ownership: Ownership = Ownership(), policy: DemoPolicy = DemoPolicy(), gatingEnabled: Bool) {
        self.tokens = tokens; self.ownership = ownership; self.policy = policy; self.gatingEnabled = gatingEnabled
    }

    private var collection: Set<String> { Set(tokens.values) }

    public var ownedSpecies: Set<String> { Set(ownership.ownedTokenIDs.compactMap { tokens[$0] }) }

    public func kind(_ species: String) -> AccessKind {
        if !gatingEnabled { return .unlocked }
        if !collection.contains(species) { return .custom }
        return ownedSpecies.contains(species) ? .owned : .demo
    }

    public func isDemo(_ species: String) -> Bool { kind(species) == .demo }

    public enum AddResult: Equatable, Sendable {
        case ok
        case demoFull(max: Int)                 // already at the demo limit
        case cooldown(secondsLeft: Double)      // session just ended
    }

    /// Can one more of `species` come out, given the species currently out?
    public func canAdd(_ species: String, out: [String], now: Double) -> AddResult {
        guard isDemo(species) else { return .ok }
        if sessionStart == nil, let end = lastSessionEnd, now - end < policy.cooldownSeconds {
            return .cooldown(secondsLeft: policy.cooldownSeconds - (now - end))
        }
        let demoOut = out.filter(isDemo).count
        return demoOut < policy.maxOut ? .ok : .demoFull(max: policy.maxOut)
    }

    /// Call after adding a demo Gremlet; starts the session clock if needed.
    public mutating func noteDemoAdded(now: Double) {
        if sessionStart == nil { sessionStart = now }
    }

    public func secondsLeft(now: Double) -> Double? {
        sessionStart.map { max(0, policy.sessionSeconds - (now - $0)) }
    }

    /// Call regularly. Returns true exactly once when the session runs out (time for demo Gremlets to head home).
    /// Also quietly ends the session if no demo Gremlets are out any more.
    public mutating func tick(out: [String], now: Double) -> Bool {
        guard let start = sessionStart else { return false }
        if !out.contains(where: isDemo) { sessionStart = nil; return false }
        if now - start >= policy.sessionSeconds {
            sessionStart = nil
            lastSessionEnd = now
            return true
        }
        return false
    }

    /// Picks which species may be restored at launch: everything you own/custom, plus up to `maxOut` demos.
    public func filterRestore(_ ids: [String]) -> [String] {
        var demos = 0
        return ids.filter { id in
            guard isDemo(id) else { return true }
            demos += 1
            return demos <= policy.maxOut
        }
    }
}
