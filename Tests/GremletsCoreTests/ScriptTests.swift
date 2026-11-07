import Foundation
import Testing

/// The shell scripts Claude Code runs on every event fail silently by design (they must never block Claude), so a
/// syntax slip (an apostrophe inside the quoted Python block) would quietly switch the Claude buddy off. Catch it here.
@Suite struct ScriptTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func run(_ tool: String, _ args: [String], stdin: String? = nil) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = out; p.standardInput = inp
        try p.run()
        if let s = stdin { inp.fileHandleForWriting.write(Data(s.utf8)) }
        try? inp.fileHandleForWriting.close()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    @Test(arguments: ["gremlet", "gremlet-claude-hook", "gremlet-statusline", "install-claude-extras", "bundle.sh"])
    func shellScriptParses(_ name: String) throws {
        let path = Self.repo.appendingPathComponent("scripts/\(name)").path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let (status, out) = try run("/bin/bash", ["-n", path])
        #expect(status == 0, "\(name): \(out)")
    }

    /// The hook's Python block must build a query (nothing on stdout; the request goes to a port nobody listens on).
    @Test func hookBuildsAQueryWithoutPrinting() throws {
        let path = Self.repo.appendingPathComponent("scripts/gremlet-claude-hook").path
        let (status, out) = try run("/usr/bin/env", ["GREMLETS_PORT=1", "/bin/bash", "-x", path],
                                    stdin: #"{"hook_event_name":"UserPromptSubmit","session_id":"t","cwd":"/x/Probe"}"#)
        #expect(status == 0)
        #expect(out.contains("query='event=start&session=t&project=Probe"), "\(out)")
    }

    @Test func mcpServerCompiles() throws {
        let path = Self.repo.appendingPathComponent("scripts/gremlets-mcp.py").path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let (status, out) = try run("/usr/bin/python3", ["-c", "import ast,sys; ast.parse(open(sys.argv[1]).read())", path])
        #expect(status == 0, "\(out)")
    }
}
