import Foundation

/// The corgi binary, and the few commands the bar sends it. Arguments are
/// always an array; nothing here goes through a shell.
final class Corgi {
    struct Result {
        var ok: Bool
        var stdout: String
        var stderr: String
    }

    static let shared = Corgi()

    var overridePath: String? {
        didSet { cachedPath = nil }
    }
    private var cachedPath: String?

    func path() -> String? {
        if let cachedPath { return cachedPath }
        let candidates = [overridePath, "/opt/homebrew/bin/corgi", "/usr/local/bin/corgi"].compactMap { $0 }
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            cachedPath = c
            return c
        }
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let c = String(dir) + "/corgi"
            if FileManager.default.isExecutableFile(atPath: c) {
                cachedPath = c
                return c
            }
        }
        return nil
    }

    func run(_ args: [String]) -> Result {
        guard let bin = path() else {
            return Result(ok: false, stdout: "", stderr: "corgi is not installed — brew install andriiklymiuk/homebrew-tools/corgi")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return Result(ok: false, stdout: "", stderr: error.localizedDescription)
        }
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return Result(ok: p.terminationStatus == 0, stdout: stdout, stderr: stderr)
    }

    func runInBackground(_ args: [String], done: ((Result) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = self.run(args)
            if let done { DispatchQueue.main.async { done(r) } }
        }
    }

    func version() -> String? {
        let r = run(["--version"])
        guard r.ok, let first = r.stdout.split(separator: "\n").first else { return nil }
        return String(first).replacingOccurrences(of: "corgi version ", with: "")
    }

    func board() -> Board? {
        let r = run(["agent", "sessions", "--json"])
        guard let data = r.stdout.data(using: .utf8), !data.isEmpty else { return nil }
        return try? Board.decode(data)
    }
}
