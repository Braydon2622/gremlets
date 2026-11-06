/// Pure text helpers for the AI companion (shared by the app; tested).
public enum CompanionText {
    /// Actions a reply may ask for.
    public static let actions: Set<String> = ["focus", "garden", "dance", "wave", "hide", "nap", "wish", "water"]

    /// Splits a trailing `<do>action</do>` tag off a reply. Unknown actions are dropped.
    public static func parseAction(_ raw: String) -> (text: String, action: String?) {
        guard let open = raw.range(of: "<do>"), let close = raw.range(of: "</do>", range: open.upperBound..<raw.endIndex) else {
            return (trim(raw), nil)
        }
        let action = raw[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
        var text = raw
        text.removeSubrange(open.lowerBound..<close.upperBound)
        return (trim(text), actions.contains(action) ? action : nil)
    }

    /// What a message is asking for, when there's no AI to ask (built-in replies).
    public static func intent(_ message: String) -> String? {
        let t = " " + message.lowercased() + " "
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        let table: [(String, [String])] = [
            ("focus", ["focus", "concentrate", "work mode", "pomodoro"]),
            ("hide", ["hide", "meeting", "presenting", "screen share"]),
            ("garden", ["garden", "plant", "grow"]),
            ("water", ["water"]),
            ("dance", ["dance", "party", "celebrate"]),
            ("nap", ["sleep", "nap", "tired"]),
            ("wish", ["wish", "shooting star"]),
            ("recap", ["how was my day", "recap", "today", "stats", "how am i doing"]),
            ("whoami", ["your name", "who are you", "what are you"]),
            ("love", ["love you", "good job", "thank", "cute"]),
            ("sad", ["sad", "stressed", "anxious", "overwhelmed", "bad day"]),
            ("hello", [" hi ", " hey", "hello", "morning", " yo "]),
        ]
        return table.first { has($0.1) }?.0
    }

    static func trim(_ s: String) -> String {
        var out = Substring(s)
        while let f = out.first, f.isWhitespace { out.removeFirst() }
        while let l = out.last, l.isWhitespace { out.removeLast() }
        return String(out)
    }
}
