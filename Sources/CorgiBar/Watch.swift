import Foundation

/// `corgi agent watch --json`: which workspaces are watched, whether each
/// only reports or actually works on what arrives, and what the unattended
/// runs opened. A fix takes minutes and its notification is gone in a
/// second, so the menu is where you find out what happened.
struct WatchStatus: Decodable {
    struct Budget: Decodable {
        var perHour: Int?
        var perDay: Int?
        var startedThisHour: Int?
        var startedToday: Int?
    }


    struct Workspace: Decodable, Identifiable {
        var workspace: String
        var sources: [String] = []
        var action: String = "notify"
        var interval: String?
        var quiet: String?
        var fixes: Budget?
        var id: String { workspace }

        // corgi omits empty fields, so every optional one is decoded as such:
        // a synthesized decoder would fail the whole payload over a missing key.
        enum CodingKeys: String, CodingKey { case workspace, sources, action, interval, quiet, fixes }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            workspace = try c.decode(String.self, forKey: .workspace)
            sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
            action = try c.decodeIfPresent(String.self, forKey: .action) ?? "notify"
            interval = try c.decodeIfPresent(String.self, forKey: .interval)
            quiet = try c.decodeIfPresent(String.self, forKey: .quiet)
            fixes = try c.decodeIfPresent(Budget.self, forKey: .fixes)
        }

        /// Unattended: it works on what arrives instead of only reporting it.
        var isAuto: Bool { action == "fix" }
    }

    struct Fix: Decodable, Identifiable {
        var key: String?
        var ref: String
        var workspace: String
        var kind: String?
        /// The ticket the run was about, when corgi still has its row.
        var url: String?
        var startedAt: Date?
        var running: Bool = false
        var prs: [String] = []
        var note: String?
        var error: String?
        var id: String { workspace + "/" + ref + (startedAt.map { String($0.timeIntervalSince1970) } ?? "") }

        enum CodingKeys: String, CodingKey { case key, ref, workspace, kind, url, startedAt, running, prs, note, error }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decodeIfPresent(String.self, forKey: .key)
            ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? ""
            workspace = try c.decodeIfPresent(String.self, forKey: .workspace) ?? ""
            kind = try c.decodeIfPresent(String.self, forKey: .kind)
            url = try c.decodeIfPresent(String.self, forKey: .url)
            startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
            running = try c.decodeIfPresent(Bool.self, forKey: .running) ?? false
            prs = try c.decodeIfPresent([String].self, forKey: .prs) ?? []
            note = try c.decodeIfPresent(String.self, forKey: .note)
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }

        /// The first pull request it opened, if it opened one.
        var pullRequest: URL? {
            guard let first = prs.first(where: { $0.hasPrefix("https://") }) else { return nil }
            return URL(string: first)
        }

        /// The ticket itself.
        var link: URL? {
            guard let url, url.hasPrefix("https://") else { return nil }
            return URL(string: url)
        }

        /// Where a click on the row goes: the pull request it opened, else the ticket.
        var destination: URL? { pullRequest ?? link }

        var outcome: String {
            if running { return "running" }
            if let error, !error.isEmpty { return error }
            if !prs.isEmpty { return prs.count == 1 ? "opened 1 PR" : "opened \(prs.count) PRs" }
            if let note, !note.isEmpty { return note.replacingOccurrences(of: "**", with: "") }
            return "nothing opened"
        }
    }

    /// One thing the watch saw that is still waiting on a person.
    struct Item: Decodable, Identifiable {
        var key: String
        var ref: String = ""
        var kind: String = ""
        var workspace: String = ""
        var title: String = ""
        var url: String?
        var state: String?
        var at: Date?
        /// Why unattended runs stopped on this ticket: the breaker tripped
        /// after two failed runs, or someone blocked it by hand.
        var blocked: String?
        /// The live session on the ticket, when one is: opened for it by
        /// "Work on it", or on a branch named after it.
        var session: SessionRef?
        var id: String { key }

        struct SessionRef: Decodable {
            var id: String
            var label: String
            var status: String
        }

        enum CodingKeys: String, CodingKey { case key, ref, kind, workspace, title, url, state, at, blocked, session }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
            ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? ""
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
            workspace = try c.decodeIfPresent(String.self, forKey: .workspace) ?? ""
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            url = try c.decodeIfPresent(String.self, forKey: .url)
            state = try c.decodeIfPresent(String.self, forKey: .state)
            at = try c.decodeIfPresent(Date.self, forKey: .at)
            blocked = try c.decodeIfPresent(String.self, forKey: .blocked)
            session = try? c.decodeIfPresent(SessionRef.self, forKey: .session)
        }

        /// "session api · working", when a session is on the ticket.
        var sessionLine: String? {
            guard let session else { return nil }
            let word = ["needs_input": "needs you", "working": "working", "done": "done", "stale": "idle", "limited": "limit"][session.status] ?? session.status
            return "session \(session.label) · \(word)"
        }

        /// What kind of thing it is, in the words the menu has room for.
        var kindLabel: String {
            switch kind {
            case "issue.new": return "issue"
            case "issue.comment": return "comment"
            case "pr.comment": return "PR comment"
            case "pr.review": return "PR review"
            case "review.requested": return "review asked"
            case "ci.failed": return "build red"
            case "routine": return "routine"
            default: return kind
            }
        }

        var link: URL? {
            guard let url, url.hasPrefix("https://") else { return nil }
            return URL(string: url)
        }
    }

    var workspaces: [Workspace] = []
    var fixes: [Fix] = []
    var events: [Item] = []

    static let empty = WatchStatus()
    init() {}

    enum CodingKeys: String, CodingKey { case workspaces, fixes, events }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try c.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? []
        fixes = try c.decodeIfPresent([Fix].self, forKey: .fixes) ?? []
        events = try c.decodeIfPresent([Item].self, forKey: .events) ?? []
    }

    var watched: Bool { !workspaces.isEmpty }
    var running: [Fix] { fixes.filter(\.running) }

    /// What to show when nothing is running: the finished runs worth seeing.
    func recent(now: Date, within: TimeInterval = 12 * 3600, limit: Int = 5) -> [Fix] {
        fixes.filter { !$0.running && now.timeIntervalSince($0.startedAt ?? .distantPast) <= within }
            .prefix(limit)
            .map { $0 }
    }

    /// One line for the menu section header.
    func summary(now: Date) -> String {
        if !events.isEmpty && running.isEmpty {
            return events.count == 1 ? "1 thing waiting" : "\(events.count) things waiting"
        }
        let live = running.count
        if live == 1 { return "working on \(running[0].ref)" }
        if live > 1 { return "\(live) fixes running" }
        let opened = recent(now: now).filter { !$0.prs.isEmpty }.count
        if opened > 0 { return "\(opened) pull request\(opened == 1 ? "" : "s") opened" }
        let autos = workspaces.filter(\.isAuto).count
        if autos > 0 { return autos == 1 ? "unattended, nothing yet" : "\(autos) unattended, nothing yet" }
        return "reporting only"
    }

    static func decode(_ data: Data) throws -> WatchStatus {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = Board.parseDate(raw) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: raw)
            }
            return date
        }
        return try d.decode(WatchStatus.self, from: data)
    }
}
