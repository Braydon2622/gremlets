import AppKit
import GremletsCore

// Wallet ownership check.
//
// Flow: menu "Connect Wallet…" → the app opens http://127.0.0.1:47920/connect in your browser → your wallet
// extension signs a free text message with a one-time nonce (no transaction, no permissions) → the page hands the
// signature back to the app → the app recovers the signer with the chain's ecrecover precompile, then reads
// ownerOf(1…50) from the Gremlets contract on Base Sepolia and unlocks the Gremlets you hold.
//
// The app never sees or stores a private key or seed phrase. It only stores your public address and which token
// ids it held at the last check, and re-reads ownership from the chain every few hours (so a sold Gremlet goes
// back to demo mode).

/// Where the Gremlets contract lives. Testnet only: anything other than Base Sepolia is refused.
struct Deployment {
    let chainID: Int
    let contract: String
    let rpcURL: URL

    /// `deployment.json` from the app bundle (or `nft/deployment.json` in dev builds). Env overrides for local
    /// testing: GREMLETS_CONTRACT, GREMLETS_RPC (e.g. an Anvil node started with --chain-id 84532).
    static func load() -> Deployment? {
        var json: [String: Any] = [:]
        if let url = Resources.file("deployment.json", devPath: "nft/deployment.json"),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { json = obj }
        let env = ProcessInfo.processInfo.environment
        let chain = json["chainId"] as? Int ?? Ethereum.baseSepoliaChainID
        guard chain == Ethereum.baseSepoliaChainID else {
            NSLog("Gremlets: deployment.json is for chain \(chain); this build only supports Base Sepolia (84532).")
            return nil
        }
        guard let raw = env["GREMLETS_CONTRACT"] ?? json["address"] as? String,
              let contract = Ethereum.normalizeAddress(raw),
              let rpc = URL(string: env["GREMLETS_RPC"] ?? json["rpc"] as? String ?? Ethereum.baseSepoliaRPC) else { return nil }
        return Deployment(chainID: chain, contract: contract, rpcURL: rpc)
    }
}

/// Finds files shipped in the app bundle's Resources, or in the repo for `swift run` builds.
enum Resources {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func file(_ name: String, devPath: String) -> URL? {
        if let r = Bundle.main.resourceURL?.appendingPathComponent(name), FileManager.default.fileExists(atPath: r.path) { return r }
        let dev = repo.appendingPathComponent(devPath)
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    /// token id → species id, from nft/tokens.json.
    static func tokens() -> [Int: String] {
        guard let url = file("tokens.json", devPath: "nft/tokens.json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        var out: [Int: String] = [:]
        for (k, v) in obj { if let id = Int(k) { out[id] = v } }
        return out
    }
}

// MARK: - Chain reads (JSON-RPC)

struct ChainError: Error, CustomStringConvertible { let description: String }

/// Read-only JSON-RPC client. Never sends transactions; it has no way to sign anything.
struct ChainReader {
    let deployment: Deployment

    private func post(_ body: Any) async throws -> Any {
        var req = URLRequest(url: deployment.rpcURL, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ChainError(description: "network answered \((resp as? HTTPURLResponse)?.statusCode ?? 0)") }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func rpc(_ method: String, _ params: [Any]) async throws -> Any? {
        let r = try await post(["jsonrpc": "2.0", "id": 1, "method": method, "params": params]) as? [String: Any]
        if let err = r?["error"] as? [String: Any] { throw ChainError(description: err["message"] as? String ?? "RPC error") }
        return r?["result"]
    }

    /// Refuses to continue unless the node really is Base Sepolia.
    func checkChain() async throws {
        guard let hex = try await rpc("eth_chainId", []) as? String, Int(hex.dropFirst(2), radix: 16) == deployment.chainID else {
            throw ChainError(description: "the network isn't Base Sepolia")
        }
    }

    func call(to: String, data: String) async throws -> String {
        guard let r = try await rpc("eth_call", [["to": to, "data": data], "latest"]) as? String else { throw ChainError(description: "empty eth_call result") }
        return r
    }

    /// Who signed `message`? Uses the ecrecover precompile, so no elliptic-curve code lives in the app.
    func recoverSigner(message: String, signature: String) async throws -> String {
        guard let input = Ethereum.ecrecoverInput(hash: Ethereum.personalMessageHash(message), signature: signature) else {
            throw ChainError(description: "that signature isn't valid")
        }
        guard let addr = Ethereum.addressFromWord(try await call(to: Ethereum.ecrecoverPrecompile, data: input)) else {
            throw ChainError(description: "couldn't recover the signer")
        }
        return addr
    }

    /// ownerOf for every token id in one batched request. Unminted ids revert → nil owner.
    func owners(of ids: [Int]) async throws -> [Int: String?] {
        let batch: [[String: Any]] = ids.map {
            ["jsonrpc": "2.0", "id": $0, "method": "eth_call", "params": [["to": deployment.contract, "data": Ethereum.ownerOfCall($0)], "latest"]]
        }
        guard let replies = try await post(batch) as? [[String: Any]] else { throw ChainError(description: "unexpected batch reply") }
        var out: [Int: String?] = [:]
        for r in replies {
            guard let id = r["id"] as? Int else { continue }
            out[id] = (r["result"] as? String).flatMap(Ethereum.addressFromWord)
        }
        guard out.count == ids.count else { throw ChainError(description: "incomplete ownership reply") }
        return out
    }

    func ownedTokenIDs(address: String, tokenIDs: [Int]) async throws -> [Int] {
        try await checkChain()
        return Ownership.ownedIDs(try await owners(of: tokenIDs), by: address)
    }
}

// MARK: - Persisted ownership

enum OwnershipStore {
    private static let key = "ownership.v1"

    static func load() -> Ownership {
        guard let d = UserDefaults.standard.data(forKey: key), let o = try? JSONDecoder().decode(Ownership.self, from: d) else { return Ownership() }
        return o
    }

    static func save(_ o: Ownership) {
        if let d = try? JSONEncoder().encode(o) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Wallet link (browser page ↔ app)

/// Runs the one-time "prove it's your wallet" handshake and the periodic ownership refresh.
/// Used from the main thread only (menu, control server and the async work all hop back to the main actor).
final class WalletLink {
    enum State: Equatable { case idle, waiting, checking, done(String), failed(String) }

    let deployment: Deployment
    let tokenIDs: [Int]
    private(set) var state: State = .idle
    private var nonce: String?
    private var nonceIssued = Date.distantPast
    private var refreshing = false

    /// Called on the main actor with the new ownership after a successful proof or refresh.
    var onOwnership: (Ownership) -> Void = { _ in }
    var onStateChange: () -> Void = {}

    init(deployment: Deployment, tokenIDs: [Int]) {
        self.deployment = deployment
        self.tokenIDs = tokenIDs
    }

    private var reader: ChainReader { ChainReader(deployment: deployment) }

    static var pageURL: URL { URL(string: "http://127.0.0.1:\(ControlServer.defaultPort)/connect")! }

    /// Issues a fresh nonce and opens the connect page in the default browser.
    func begin(openBrowser: Bool = true) {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        nonce = String(Hex.encode(bytes).dropFirst(2))
        nonceIssued = Date()
        set(.waiting)
        if openBrowser { NSWorkspace.shared.open(WalletLink.pageURL) }
    }

    /// Automated end-to-end tests only (GREMLETS_WALLET_TEST=1): issue a nonce without opening a browser.
    func beginForTest() -> String {
        begin(openBrowser: false)
        return #"{"nonce":"\#(nonce ?? "")"}"#
    }

    private func set(_ s: State) { state = s; onStateChange() }

    /// POST /wallet/proof?address=…&signature=…&nonce=…  (from the connect page; header-protected)
    func handleProof(_ q: [String: String]) -> (Int, String) {
        guard let n = nonce, q["nonce"] == n, Date().timeIntervalSince(nonceIssued) < 10 * 60 else {
            return (400, #"{"ok":false,"error":"This link expired. Choose Connect Wallet… in the Gremlets menu again."}"#)
        }
        guard let claimed = q["address"].flatMap(Ethereum.normalizeAddress), let sig = q["signature"] else {
            return (400, #"{"ok":false,"error":"missing address or signature"}"#)
        }
        nonce = nil                                  // single use
        set(.checking)
        let message = Ethereum.proofMessage(nonce: n)
        let reader = self.reader, ids = tokenIDs
        Task { @MainActor in
            do {
                try await reader.checkChain()
                let signer = try await reader.recoverSigner(message: message, signature: sig)
                guard signer == claimed else { throw ChainError(description: "the signature doesn't match that wallet") }
                let owned = try await reader.ownedTokenIDs(address: signer, tokenIDs: ids)
                let o = Ownership(address: signer, ownedTokenIDs: owned, checkedAt: Date().timeIntervalSince1970)
                self.onOwnership(o)
                self.set(.done(owned.isEmpty ? "Wallet linked. It doesn't hold any Gremlets yet, so demo mode stays on."
                                             : "Wallet linked! \(owned.count) Gremlet\(owned.count == 1 ? " is" : "s are") yours."))
            } catch {
                self.set(.failed("Couldn't verify: \(error)"))
            }
        }
        return (202, #"{"ok":true}"#)
    }

    /// GET /wallet/status → what the page should show.
    func statusJSON() -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        switch state {
        case .idle: return #"{"state":"idle"}"#
        case .waiting: return #"{"state":"waiting"}"#
        case .checking: return #"{"state":"checking"}"#
        case .done(let m): return #"{"state":"done","message":"\#(esc(m))"}"#
        case .failed(let m): return #"{"state":"failed","message":"\#(esc(m))"}"#
        }
    }

    /// Re-reads ownership for an already-proven address (no signature needed). Keeps the last known result offline.
    func refresh(_ current: Ownership, force: Bool = false) {
        guard let addr = current.address, !refreshing else { return }
        if !force, let t = current.checkedAt, Date().timeIntervalSince1970 - t < 6 * 3600 { return }
        refreshing = true
        let reader = self.reader, ids = tokenIDs
        Task { @MainActor in
            defer { self.refreshing = false }
            do {
                let owned = try await reader.ownedTokenIDs(address: addr, tokenIDs: ids)
                self.onOwnership(Ownership(address: addr, ownedTokenIDs: owned, checkedAt: Date().timeIntervalSince1970))
            } catch {
                NSLog("Gremlets: ownership refresh failed (keeping last result): \(error)")
            }
        }
    }

    /// The connect page. Served only on 127.0.0.1; it can't read anything from the app except its own status.
    func page() -> String {
        let n = nonce ?? ""
        let message = Ethereum.proofMessage(nonce: n)
        let messageJS = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "'", with: "\\'")
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Link your wallet · Gremlets</title>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        body{font:16px/1.5 -apple-system,system-ui,sans-serif;background:#fbf6ee;color:#3b3340;margin:0;display:grid;place-items:center;min-height:100vh}
        main{max-width:520px;background:#fff;border-radius:18px;padding:28px 32px;box-shadow:0 6px 30px #0001}
        h1{font-size:22px;margin:0 0 8px} pre{white-space:pre-wrap;background:#f4eee6;border-radius:10px;padding:12px;font-size:13px}
        button{font:inherit;background:#e9824a;color:#fff;border:0;border-radius:12px;padding:10px 18px;cursor:pointer}
        button:disabled{opacity:.5;cursor:default} .note{font-size:13px;color:#776f7c} #msg{margin-top:14px;font-weight:600}
        </style></head><body><main>
        <h1>Link your wallet to Gremlets</h1>
        <p>Your wallet will ask you to <b>sign</b> this message. Signing is free: it doesn't send a transaction,
        spend anything, or give the app any permission. It just proves the wallet is yours.</p>
        <pre id="text"></pre>
        <button id="go">Connect &amp; sign</button>
        <div id="msg"></div>
        <p class="note">Gremlets never asks for your seed phrase or private key. If anything ever does, it's a scam.
        Ownership is read from Base Sepolia (testnet).</p>
        </main><script>
        const NONCE = '\(n)';
        const MESSAGE = '\(messageJS)';
        const $ = (id) => document.getElementById(id);
        $('text').textContent = MESSAGE;
        const say = (t) => { $('msg').textContent = t; };
        const hex = (s) => '0x' + Array.from(new TextEncoder().encode(s), b => b.toString(16).padStart(2, '0')).join('');
        if (!NONCE) { $('go').disabled = true; say('Open this page from the Gremlets menu bar: Connect Wallet…'); }
        else if (!window.ethereum) { $('go').disabled = true; say('No wallet found in this browser. Install MetaMask or Coinbase Wallet, then reload.'); }
        async function poll() {
          for (let i = 0; i < 60; i++) {
            const r = await (await fetch('/wallet/status', { headers: { 'X-Gremlets': '1' } })).json();
            if (r.state === 'done') { say('✅ ' + r.message + ' You can close this tab.'); return; }
            if (r.state === 'failed') { say('⚠️ ' + r.message); $('go').disabled = false; return; }
            await new Promise(res => setTimeout(res, 1000));
          }
          say('Still checking… look at the Gremlets menu bar in a moment.');
        }
        $('go').onclick = async () => {
          $('go').disabled = true;
          try {
            say('Waiting for your wallet…');
            const [account] = await window.ethereum.request({ method: 'eth_requestAccounts' });
            const signature = await window.ethereum.request({ method: 'personal_sign', params: [hex(MESSAGE), account] });
            say('Checking which Gremlets this wallet holds…');
            const q = new URLSearchParams({ address: account, signature, nonce: NONCE });
            const r = await fetch('/wallet/proof?' + q, { method: 'POST', headers: { 'X-Gremlets': '1' } });
            if (!r.ok) { say('⚠️ ' + ((await r.json()).error || 'Something went wrong')); return; }
            await poll();
          } catch (e) { say('⚠️ ' + (e.message || e)); $('go').disabled = false; }
        };
        </script></body></html>
        """
    }
}
