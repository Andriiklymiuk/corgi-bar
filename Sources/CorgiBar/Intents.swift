import AppIntents
import Foundation

// Siri and Shortcuts on the Mac: the same handful of things the menu does,
// as App Intents. "Start a session in acme-api", "send 'run the tests' to
// corgi", "allow the session", "reload corgi". Each one runs the corgi
// binary the bar already drives; nothing here goes through a shell. The
// phone app carries the same intents, so a Shortcut synced over iCloud
// reads the same on both.

/// A workspace corgi supervises: the ones `corgi agent status --json` lists.
@available(macOS 13.0, *)
struct WorkspaceEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "corgi workspace")
    static var defaultQuery = WorkspaceQuery()

    var id: String
    var running: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)", subtitle: running ? "session open" : "off")
    }
}

@available(macOS 13.0, *)
struct WorkspaceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WorkspaceEntity] {
        WorkspaceQuery.all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [WorkspaceEntity] {
        WorkspaceQuery.all().filter { $0.id.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [WorkspaceEntity] { WorkspaceQuery.all() }

    static func all() -> [WorkspaceEntity] {
        let r = Corgi.shared.run(["agent", "status", "--json"])
        guard let data = r.stdout.data(using: .utf8), let status = try? JSONDecoder().decode(AgentStatus.self, from: data) else { return [] }
        return status.workspaces.map { WorkspaceEntity(id: $0.workspaceId, running: $0.running) }
    }
}

/// A Claude session on the board, by the name the board shows.
@available(macOS 13.0, *)
struct SessionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Claude session")
    static var defaultQuery = SessionQuery()

    var id: String
    var name: String
    var status: String
    var detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(status)\(detail.isEmpty ? "" : " · \(detail)")")
    }
}

@available(macOS 13.0, *)
struct SessionQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        SessionQuery.all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [SessionEntity] {
        SessionQuery.all().filter { $0.name.localizedCaseInsensitiveContains(string) || $0.id.hasPrefix(string) }
    }

    func suggestedEntities() async throws -> [SessionEntity] { SessionQuery.all() }

    static func all() -> [SessionEntity] {
        guard let board = Corgi.shared.board() else { return [] }
        return board.sessions.filter { $0.status != .gone }.map {
            SessionEntity(id: $0.id, name: $0.title ?? $0.shortName, status: $0.status.rawValue, detail: $0.detail ?? "")
        }
    }

    /// The session a Shortcut means when it names none: the one waiting on
    /// a person, else the one in the window in front, else the first.
    static func fallback() -> SessionEntity? {
        let all = SessionQuery.all()
        return all.first { $0.status == "needs_input" } ?? all.first
    }
}

enum CorgiIntentError: Error, CustomLocalizedStringResourceConvertible {
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .failed(let why): return "corgi could not do that: \(why)"
        }
    }
}

private func corgi(_ args: [String]) throws -> String {
    let r = Corgi.shared.run(args)
    guard r.ok else {
        let why = (r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        throw CorgiIntentError.failed(why.isEmpty ? "it said nothing" : why)
    }
    return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

@available(macOS 13.0, *)
struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a corgi session"
    static var description = IntentDescription("Opens a Claude session in a workspace corgi supervises. It shows up on the board here, on the phone and in the Claude app.")

    @Parameter(title: "Workspace")
    var workspace: WorkspaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start a session in \(\.$workspace)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try corgi(["agent", "session", "start", workspace.id])
        return .result(dialog: "Starting a session in \(workspace.id).")
    }
}

@available(macOS 13.0, *)
struct StopSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop a corgi session"
    static var description = IntentDescription("Ends the supervised session in a workspace; the device stays online.")

    @Parameter(title: "Workspace")
    var workspace: WorkspaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Stop the session in \(\.$workspace)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try corgi(["agent", "session", "stop", workspace.id])
        return .result(dialog: "Stopping the session in \(workspace.id).")
    }
}

@available(macOS 13.0, *)
struct SendToSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Send text to a Claude session"
    static var description = IntentDescription("Types a prompt into a session on the board and presses Enter.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Session")
    var session: SessionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$text) to \(\.$session)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = session ?? SessionQuery.fallback() else {
            throw CorgiIntentError.failed("no session is on the board")
        }
        _ = try corgi(["agent", "send", target.id, "--enter", text])
        return .result(dialog: "Sent to \(target.name).")
    }
}

@available(macOS 13.0, *)
enum PermissionAnswer: String, AppEnum {
    case allow, always, deny

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Answer")
    static var caseDisplayRepresentations: [PermissionAnswer: DisplayRepresentation] = [
        .allow: "Allow", .always: "Allow always", .deny: "Deny",
    ]
}

@available(macOS 13.0, *)
struct AnswerSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Answer a Claude session's permission prompt"
    static var description = IntentDescription("Allow, allow always or deny what a session is waiting on. A risky Bash command is refused unseen.")

    @Parameter(title: "Answer", default: .allow)
    var answer: PermissionAnswer

    @Parameter(title: "Session")
    var session: SessionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$answer) \(\.$session)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = session ?? SessionQuery.fallback() else {
            throw CorgiIntentError.failed("no session is waiting")
        }
        _ = try corgi(["agent", "answer", target.id, answer.rawValue])
        return .result(dialog: "\(answer.rawValue) sent to \(target.name).")
    }
}

@available(macOS 13.0, *)
struct BoardIntent: AppIntent {
    static var title: LocalizedStringResource = "What are the Claude sessions doing"
    static var description = IntentDescription("One line per session on the board: name, status, what it is on.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let all = SessionQuery.all()
        guard !all.isEmpty else {
            return .result(value: "", dialog: "No Claude sessions on the board.")
        }
        let lines = all.map { "\($0.name): \($0.status.replacingOccurrences(of: "_", with: " "))\($0.detail.isEmpty ? "" : ", \($0.detail)")" }
        let waiting = all.filter { $0.status == "needs_input" }.count
        let head = waiting > 0 ? "\(waiting) waiting on you. " : ""
        return .result(value: lines.joined(separator: "\n"), dialog: "\(head)\(lines.joined(separator: ". "))")
    }
}

@available(macOS 13.0, *)
struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Reload corgi"
    static var description = IntentDescription("The daemon rescans sessions and polls every tracker now; the menu bar, the phone and the editor re-read.")

    func perform() async throws -> some IntentResult {
        _ = try corgi(["agent", "refresh"])
        return .result()
    }
}

@available(macOS 13.0, *)
struct CorgiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSessionIntent(),
                    phrases: ["Start a session in \(.applicationName)", "Start a \(.applicationName) session", "Start \(\.$workspace) in \(.applicationName)"],
                    shortTitle: "Start a session", systemImageName: "play.fill")
        AppShortcut(intent: StopSessionIntent(),
                    phrases: ["Stop the session in \(.applicationName)", "Stop \(\.$workspace) in \(.applicationName)"],
                    shortTitle: "Stop a session", systemImageName: "stop.fill")
        AppShortcut(intent: SendToSessionIntent(),
                    phrases: ["Send to \(.applicationName)", "Tell \(.applicationName)"],
                    shortTitle: "Send to a session", systemImageName: "paperplane.fill")
        AppShortcut(intent: AnswerSessionIntent(),
                    phrases: ["Allow in \(.applicationName)", "Answer \(.applicationName)"],
                    shortTitle: "Allow or deny", systemImageName: "checkmark.shield")
        AppShortcut(intent: BoardIntent(),
                    phrases: ["What is \(.applicationName) doing", "\(.applicationName) status"],
                    shortTitle: "Sessions", systemImageName: "rectangle.grid.1x2")
        AppShortcut(intent: RefreshIntent(),
                    phrases: ["Reload \(.applicationName)", "Refresh \(.applicationName)"],
                    shortTitle: "Reload", systemImageName: "arrow.clockwise")
    }
}
