import Foundation
import GremletsCore

/// Reads a project's file list for its codebase castle: `git ls-files` (tracked files only, so build output and
/// dependencies stay out), or a capped walk of the folder when it isn't a git repo. Runs off the main thread; only
/// relative paths are used, and only to count files per top-level folder and extension.
enum CastleScanner {
    static func scan(project: String, root: String, done: @escaping (Castle) -> Void) {
        guard !root.isEmpty, FileManager.default.fileExists(atPath: root) else { return }
        DispatchQueue.global(qos: .utility).async {
            let paths = gitFiles(root) ?? walk(root)
            guard !paths.isEmpty else { return }
            let castle = Castle.from(project: project, paths: paths)
            DispatchQueue.main.async { done(castle) }
        }
    }

    private static func gitFiles(_ root: String) -> [String]? {
        guard FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent(".git")) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root, "ls-files"]
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(50_000).map(String.init)
    }

    private static func walk(_ root: String) -> [String] {
        let skip: Set<String> = ["node_modules", ".build", "build", "dist", ".git", "Pods", "DerivedData", ".venv", "venv", "__pycache__"]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [String] = []
        let prefix = URL(fileURLWithPath: root).standardizedFileURL.path + "/"
        for case let url as URL in e {
            if skip.contains(url.lastPathComponent) { e.skipDescendants(); continue }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(prefix) { out.append(String(path.dropFirst(prefix.count))) }
            if out.count >= 5000 { break }
        }
        return out
    }
}
