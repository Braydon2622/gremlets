import Foundation
import Security
import GremletsCore

/// The AI companion: chat with any Gremlet, in its own personality, about your day.
///
/// Each Gremlet knows what kind of creature it is, its nickname, how close you two are, and what today looked like
/// (focus minutes, streak, plants grown, Claude tasks finished). It remembers your last few messages, can do a few
/// things for you (start a focus session, garden, dance, hide...) and says hello in the morning and recaps your day in
/// the evening. Replies come from Claude when you've added an Anthropic API key (stored in your Keychain); without one,
/// the Gremlets answer with built-in lines and can still do everything else.
final class CompanionAI {
    struct Message: Codable { let role: String; let text: String; let at: Double }
    enum CallResult { case success(String), failure(String) }

    /// What the companion may know about your day (filled in by the app).
    struct Day {
        var focusMinutes = 0, streak = 0, plantsToday = 0, seedsFound = 0, seedsTotal = 0, claudeToday = 0
        var gremletsOut: [String] = []
        var userName: String?
    }

    /// Actions a reply may ask for (the app decides whether to do them).
    enum Action: String, CaseIterable { case focus, garden, dance, wave, hide, nap, wish, water }

    static let model = "claude-opus-5-5"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: API key (Keychain)

    private let service = "com.braydonhart.gremlets.anthropic"
    var hasKey: Bool { key() != nil }
    /// Why the last AI reply failed, in plain words (shown on the chat page).
    private(set) var lastProblem: String?

    func setKey(_ k: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        SecItemDelete(base as CFDictionary)
        guard let k, !k.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(k.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        lastProblem = nil
    }

    private func key() -> String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty { return env }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // MARK: Memory and nicknames

    func history(_ species: String) -> [Message] {
        guard let d = UserDefaults.standard.data(forKey: "chat.\(species)"),
              let m = try? JSONDecoder().decode([Message].self, from: d) else { return [] }
        return m
    }

    private func remember(_ species: String, _ msg: Message) {
        var h = history(species) + [msg]
        if h.count > 40 { h.removeFirst(h.count - 40) }
        if let d = try? JSONEncoder().encode(h) { UserDefaults.standard.set(d, forKey: "chat.\(species)") }
    }

    func forget(_ species: String) { UserDefaults.standard.removeObject(forKey: "chat.\(species)") }

    func nickname(_ species: String) -> String? { UserDefaults.standard.string(forKey: "nick.\(species)") }
    func setNickname(_ species: String, _ name: String?) {
        let clean = name.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)) }
        if let clean, !clean.isEmpty { UserDefaults.standard.set(clean, forKey: "nick.\(species)") }
        else { UserDefaults.standard.removeObject(forKey: "nick.\(species)") }
    }

    var userName: String? {
        get { UserDefaults.standard.string(forKey: "companion.userName") }
        set { UserDefaults.standard.set(newValue.map { String($0.prefix(30)) }, forKey: "companion.userName") }
    }

    // MARK: Talking

    /// Replies to `text` as this Gremlet. Calls back on the main thread with the reply and any action it asks for.
    func reply(to text: String, as info: SpeciesInfo, bond: Bond, day: Day, completion: @escaping (String, Action?) -> Void) {
        let said = String(text.prefix(800))
        remember(info.id, Message(role: "user", text: said, at: Date().timeIntervalSince1970))
        let finish: (String, Action?) -> Void = { [weak self] reply, action in
            self?.remember(info.id, Message(role: "gremlet", text: reply, at: Date().timeIntervalSince1970))
            DispatchQueue.main.async { completion(reply, action) }
        }
        guard let key = key() else {
            let (r, a) = builtInReply(to: said, info: info, bond: bond, day: day)
            finish(r, a); return
        }
        let past = history(info.id).dropLast().suffix(12)
        var messages: [[String: Any]] = []
        for m in past {
            let role = m.role == "user" ? "user" : "assistant"
            if let last = messages.last, last["role"] as? String == role {
                messages[messages.count - 1]["content"] = (last["content"] as? String ?? "") + "\n" + m.text
            } else { messages.append(["role": role, "content": m.text]) }
        }
        if messages.first?["role"] as? String == "assistant" { messages.removeFirst() }
        if messages.last?["role"] as? String == "user" {
            messages[messages.count - 1]["content"] = (messages.last?["content"] as? String ?? "") + "\n" + said
        } else { messages.append(["role": "user", "content": said]) }
        call(key: key, system: systemPrompt(info: info, bond: bond, day: day), messages: messages) { [weak self] result in
            switch result {
            case .success(let raw):
                let (r, a) = CompanionAI.parseAction(raw)
                finish(r, a)
            case .failure(let problem):
                self?.lastProblem = problem
                let (r, a) = self?.builtInReply(to: said, info: info, bond: bond, day: day) ?? ("…", nil)
                finish(r, a)
            }
        }
    }

    /// One short line for a moment of the day ("morning", "evening", "milestone"), AI-written when possible.
    func moment(_ kind: String, as info: SpeciesInfo, bond: Bond, day: Day, completion: @escaping (String) -> Void) {
        let fallback = builtInMoment(kind, info: info, day: day)
        guard let key = key() else { DispatchQueue.main.async { completion(fallback) }; return }
        let ask: String = {
            switch kind {
            case "morning": return "It's the first time you've seen me today. Say good morning in one short sentence, maybe mention yesterday's streak or that the garden missed me."
            case "evening": return "It's evening. Give me a warm one or two sentence recap of my day using the numbers you know, and nudge me to rest."
            default: return "Something nice just happened (\(kind)). React in one short sentence."
            }
        }()
        call(key: key, system: systemPrompt(info: info, bond: bond, day: day) + "\nThis is a speech bubble on the desktop: at most 110 characters, no action tag.",
             messages: [["role": "user", "content": ask]]) { result in
            let text: String
            if case .success(let raw) = result { text = CompanionAI.parseAction(raw).0 } else { text = fallback }
            DispatchQueue.main.async { completion(String(text.prefix(140))) }
        }
    }

    private func systemPrompt(info: SpeciesInfo, bond: Bond, day: Day) -> String {
        let name = nickname(info.id) ?? info.name
        let hour = Calendar.current.component(.hour, from: Date())
        let time = hour < 5 ? "late at night" : hour < 12 ? "morning" : hour < 17 ? "afternoon" : hour < 21 ? "evening" : "night"
        let who = userName ?? day.userName ?? "your human"
        return """
        You are \(name), a tiny original pixel creature called a Gremlet (species: \(info.name), element: \(info.element), family: \(info.family)). \(info.blurb)
        You live on \(who)'s Mac desktop with your friends (\(day.gremletsOut.joined(separator: ", "))). You walk on their windows, nap, garden in window boxes on little shelves, and keep them company while they work.
        Your bond with \(who) is "\(bond.name)" (\(bond.daysTogether) days together, \(bond.pets) pets).
        Today so far: \(day.focusMinutes) minutes focused (streak: \(day.streak) days), \(day.plantsToday) plants grown, \(day.claudeToday) Claude tasks finished alongside you. Seed book: \(day.seedsFound) of \(day.seedsTotal) kinds found. It's \(time).

        How to talk: warm, playful and short (one to three sentences), in character as a small creature. Be genuinely helpful when asked something real, but keep it brief. Never claim abilities you don't have; you can't read their screen, files or messages.
        If they ask you to do one of these, or it would clearly help, end your reply with exactly one tag on its own: <do>focus</do> (start a 25-minute focus session), <do>garden</do>, <do>dance</do>, <do>wave</do>, <do>hide</do> (hide everyone), <do>nap</do>, <do>water</do> (water the garden), <do>wish</do>. Otherwise no tag.
        """
    }

    private func call(key: String, system: String, messages: [[String: Any]], done: @escaping (CallResult) -> Void) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": CompanionAI.model,
            "max_tokens": 16000,
            "system": system,
            "messages": messages,
            "output_config": ["effort": "low"],
            "fallbacks": "default",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { done(.failure("Couldn't reach Claude (\(error.localizedDescription))")); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                done(.failure("Claude sent back something unexpected (HTTP \(status))")); return
            }
            if status != 200 {
                let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
                let plain = msg.lowercased().contains("credit") ? "Your Anthropic account is out of credits (Plans & Billing in the Console)"
                    : status == 401 ? "That API key didn't work; add it again on this page" : msg
                done(.failure(plain)); return
            }
            if json["stop_reason"] as? String == "refusal" { done(.success("Hmm, I'd rather not answer that one. Want to garden instead?")); return }
            let text = (json["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            done(text.isEmpty ? .failure("Claude's reply was empty") : .success(text))
        }.resume()
    }

    /// Splits a trailing <do>action</do> tag off a reply.
    static func parseAction(_ raw: String) -> (String, Action?) {
        let (text, action) = CompanionText.parseAction(raw)
        return (text, action.flatMap(Action.init(rawValue:)))
    }

    // MARK: Built-in replies (no API key, or Claude unavailable)

    func builtInReply(to text: String, info: SpeciesInfo, bond: Bond, day: Day) -> (String, Action?) {
        let name = nickname(info.id) ?? info.name
        switch CompanionText.intent(text) {
        case "focus": return ("Focus time! I'll doze quietly and wake you up for a break in 25 minutes.", .focus)
        case "hide": return ("Shh, we'll hide. Press ⌃⌥G to bring us back.", .hide)
        case "garden": return ("Ooh, gardening! Let me grab my watering can.", .garden)
        case "water": return ("Splish splash, everything's watered.", .water)
        case "dance": return ("Dance party! 💃", .dance)
        case "nap": return ("*yawns* A little nap sounds perfect.", .nap)
        case "wish": return ("Close your eyes… ✨ I made a wish for a rare seed.", .wish)
        case "recap": return (builtInMoment("evening", info: info, day: day), nil)
        case "whoami": return ("I'm \(name), a \(info.element) \(info.family) Gremlet. \(info.blurb)", nil)
        case "love": return (["Aww! *happy wiggle*", "You're the best human on this whole desktop.", "*hearts everywhere*"].randomElement()!, .wave)
        case "sad": return ("That sounds hard. Want to try 25 minutes on just one small thing? I'll keep you company.", nil)
        case "hello": return (["Hi hi! What are we working on?", "Hey you! I was just watering my tulips.", "Hello! Need a focus buddy?"].randomElement()!, .wave)
        default: break
        }
        return ([
            "Hmm! I'm small, but I'm listening. Want me to start a focus session or a garden?",
            "*tilts head* Tell me more! Or say \"focus\", \"garden\" or \"dance\".",
            "I don't know that one yet, but I can keep you company while you figure it out.",
        ].randomElement()!, nil)
    }

    func builtInMoment(_ kind: String, info: SpeciesInfo, day: Day) -> String {
        switch kind {
        case "morning":
            return day.streak > 1 ? "Good morning! Day \(day.streak + 1) of our focus streak?" : ["Good morning! The garden missed you.", "Morning! Ready when you are. ☀️"].randomElement()!
        case "evening":
            var bits: [String] = []
            if day.focusMinutes > 0 { bits.append("\(day.focusMinutes) min focused") }
            if day.claudeToday > 0 { bits.append("\(day.claudeToday) Claude tasks done") }
            if day.plantsToday > 0 { bits.append("\(day.plantsToday) plants grown") }
            return bits.isEmpty ? "Long day? Remember to rest. We'll be here tomorrow. 🌙" : "Today: " + bits.joined(separator: ", ") + ". Nice work! Time to rest? 🌙"
        default:
            return "Yay! ✨"
        }
    }
}
