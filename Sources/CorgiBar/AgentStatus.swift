import Foundation

/// `corgi agent status --json`: the daemon, each workspace's remote session,
/// token usage per workspace with its account, and the dashboard URL.
struct AgentStatus: Decodable {
    struct Workspace: Decodable, Identifiable {
        var workspaceId: String
        var running: Bool
        var sessionUrl: String?
        var deviceOnly: Bool?
        var restarts: Int?
        var id: String { workspaceId }
    }
    struct Usage: Decodable {
        var workspaceId: String
        var dir: String?
        var configDir: String?
        var tokensToday: Int64
        var tokensWeek: Int64
    }
    var running: Bool = false
    var version: String?
    var workspaces: [Workspace] = []
    var usage: [Usage] = []
    var dashboardUrl: String?

    static let empty = AgentStatus()

    enum CodingKeys: String, CodingKey { case running, version, workspaces, usage, dashboardUrl }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = try c.decodeIfPresent(Bool.self, forKey: .running) ?? false
        version = try c.decodeIfPresent(String.self, forKey: .version)
        workspaces = try c.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? []
        usage = try c.decodeIfPresent([Usage].self, forKey: .usage) ?? []
        dashboardUrl = try c.decodeIfPresent(String.self, forKey: .dashboardUrl)
    }

    /// One row per Claude account: tokens summed over its workspaces, and the
    /// usage-limit reset when a session under it is limited.
    struct Account: Identifiable {
        var profile: String
        var configDir: String
        var tokensToday: Int64
        var tokensWeek: Int64
        var limitedUntil: String?
        var id: String { profile }
        var chip: String { profile == "default" ? "" : String(profile.prefix(2)).uppercased() }
        var title: String { profile == "default" ? "~/.claude" : (configDir as NSString).abbreviatingWithTildeInPath }
    }

    func accounts(board: Board) -> [Account] {
        var byProfile: [String: Account] = [:]
        for u in usage {
            let profile = AgentStatus.profileName(configDir: u.configDir)
            var a = byProfile[profile] ?? Account(profile: profile, configDir: u.configDir ?? "", tokensToday: 0, tokensWeek: 0)
            a.tokensToday += u.tokensToday
            a.tokensWeek += u.tokensWeek
            byProfile[profile] = a
        }
        for s in board.sessions where s.status == .limited {
            let profile = s.profile ?? "default"
            var a = byProfile[profile] ?? Account(profile: profile, configDir: "", tokensToday: 0, tokensWeek: 0)
            a.limitedUntil = s.detail
            byProfile[profile] = a
        }
        return byProfile.values.sorted { $0.profile == "default" ? true : $1.profile == "default" ? false : $0.profile < $1.profile }
    }

    /// The badge corgi gives a config dir: ~/.claude-work → work, ~/.claude-skp → skp.
    static func profileName(configDir: String?) -> String {
        guard let dir = configDir, !dir.isEmpty else { return "default" }
        let base = (dir as NSString).lastPathComponent
        if base == ".claude" { return "default" }
        return base.hasPrefix(".claude-") ? String(base.dropFirst(".claude-".count)) : base
    }
}

/// 167.3M, 2.6B, 12k, 0 — the same buckets `corgi agent status` prints.
func formatTokens(_ n: Int64) -> String {
    switch n {
    case ..<1_000: return "\(n)"
    case ..<1_000_000: return String(format: "%.1fk", Double(n) / 1_000)
    case ..<1_000_000_000: return String(format: "%.1fM", Double(n) / 1_000_000)
    default: return String(format: "%.1fB", Double(n) / 1_000_000_000)
    }
}
