import Foundation

/// The board corgi publishes as sessions.json. Mirrors utils/agent/sessions
/// in the corgi repository; `corgi agent sessions --json` adds `path` and
/// `daemonRunning` on top.
struct Board: Decodable {
    var updatedAt: Date?
    var size: Int = 0
    var overflow: Int = 0
    var needsInput: Int = 0
    var working: Int = 0
    var slots: [Slot] = []
    var sessions: [Session] = []
    var windows: [Window] = []
    var frontWindow: String?
    var frontSession: String?
    var notice: String?
    var noticeAt: Date?
    var accounts: [Account] = []
    var path: String?
    var daemonRunning: Bool = false

    static let empty = Board()

    enum CodingKeys: String, CodingKey {
        case updatedAt, size, overflow, needsInput, working, slots, sessions, windows, frontWindow, frontSession, notice, noticeAt, accounts, path, daemonRunning
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        overflow = try c.decodeIfPresent(Int.self, forKey: .overflow) ?? 0
        needsInput = try c.decodeIfPresent(Int.self, forKey: .needsInput) ?? 0
        working = try c.decodeIfPresent(Int.self, forKey: .working) ?? 0
        slots = try c.decodeIfPresent([Slot].self, forKey: .slots) ?? []
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        windows = try c.decodeIfPresent([Window].self, forKey: .windows) ?? []
        frontWindow = try c.decodeIfPresent(String.self, forKey: .frontWindow)
        frontSession = try c.decodeIfPresent(String.self, forKey: .frontSession)
        notice = try c.decodeIfPresent(String.self, forKey: .notice)
        noticeAt = try c.decodeIfPresent(Date.self, forKey: .noticeAt)
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        path = try c.decodeIfPresent(String.self, forKey: .path)
        daemonRunning = try c.decodeIfPresent(Bool.self, forKey: .daemonRunning) ?? false
    }

    /// Sessions in board order: the keys first, then whatever overflowed.
    var orderedSessions: [Session] {
        let byId = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var seen = Set<String>()
        var out: [Session] = []
        for slot in slots {
            if let id = slot.sessionId, let s = byId[id], !seen.contains(id) {
                seen.insert(id)
                out.append(s)
            }
        }
        for s in sessions where !seen.contains(s.id) {
            out.append(s)
        }
        return out
    }

    func session(_ id: String?) -> Session? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    func keyNumber(of id: String) -> Int? {
        slots.first { $0.sessionId == id }.map { $0.index + 1 }
    }

    /// The directory corgi keeps its files in: sessions.json's parent.
    var agentDir: String? {
        path.map { ($0 as NSString).deletingLastPathComponent }
    }

    /// The session a "next needs you" key jumps to: the one that has waited
    /// longest, else the one in front.
    func nextNeedingYou() -> Session? {
        let waiting = sessions.filter { $0.status == .needsInput }
        if let oldest = waiting.min(by: { ($0.statusSince ?? .distantPast) < ($1.statusSince ?? .distantPast) }) {
            return oldest
        }
        return session(frontSession)
    }

    /// Other accounts a limited session could carry on under.
    func carryTargets(for session: Session) -> [Account] {
        let own = session.profile ?? "default"
        return accounts.filter { $0.profile != own && ($0.limits?.fiveHour.percent ?? 0) < 90 }
    }

    /// One state for the icon: the loudest thing on the board.
    var mood: Mood {
        if !daemonRunning { return .off }
        if sessions.contains(where: { $0.status == .needsInput }) { return .needsInput }
        if sessions.contains(where: { $0.status == .working }) { return .working }
        if sessions.contains(where: { $0.status == .limited }) { return .limited }
        return .quiet
    }
}

enum Mood { case off, quiet, working, needsInput, limited }

struct Slot: Decodable {
    var index: Int
    var empty: Bool?
    var pager: Bool?
    var overflow: Int?
    var sessionId: String?
    var pinned: Bool?
    var context: Int?
    var pending: String?
    var note: String?
    var stuck: Bool?
}

/// How full the session's context window is, from its last completed turn.
struct ContextFill: Decodable {
    var tokens: Int64?
    var window: Int64?
    var percent: Int
    var model: String?
    var at: Date?
}

/// A permission prompt the session is waiting on.
struct Pending: Decodable {
    var tool: String
    var subject: String?
    var at: Date?

    var text: String {
        guard let subject, !subject.isEmpty else { return tool }
        return "\(tool) \(subject)"
    }
}

/// The /usage picture Claude Code last cached for one account.
struct UsageLimits: Decodable {
    struct Window: Decodable {
        var percent: Int
        var resetsAt: Date?
    }
    var fetchedAt: Date?
    var fiveHour: Window
    var sevenDay: Window
}

/// Where one limit is heading at the current pace.
struct WindowForecast: Decodable {
    var percentPerHour: Double
    var exhaustAt: Date?
    var safe: Bool
    var samples: Int
}

struct Forecast: Decodable {
    var fiveHour: WindowForecast?
    var sevenDay: WindowForecast?
}

/// One Claude account the board's sessions run under.
struct Account: Decodable, Identifiable {
    var profile: String
    var configDir: String?
    var limits: UsageLimits?
    var forecast: Forecast?
    var sessions: Int = 0
    var id: String { profile }

    enum CodingKeys: String, CodingKey { case profile, configDir, limits, forecast, sessions }
    init(profile: String, configDir: String? = nil, limits: UsageLimits? = nil, forecast: Forecast? = nil, sessions: Int = 0) {
        self.profile = profile
        self.configDir = configDir
        self.limits = limits
        self.forecast = forecast
        self.sessions = sessions
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decodeIfPresent(String.self, forKey: .profile) ?? "default"
        configDir = try c.decodeIfPresent(String.self, forKey: .configDir)
        limits = try c.decodeIfPresent(UsageLimits.self, forKey: .limits)
        forecast = try c.decodeIfPresent(Forecast.self, forKey: .forecast)
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
    }
}

struct Window: Decodable {
    var id: String
    var folders: [String]?
    var focusedAt: Date?
}

enum Status: String, Decodable {
    case working, needsInput = "needs_input", done, stale, gone, unknown, limited

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Status(rawValue: raw) ?? .unknown
    }

    var word: String {
        switch self {
        case .working: return "WORKING"
        case .needsInput: return "NEEDS YOU"
        case .done: return "DONE"
        case .stale: return "IDLE"
        case .gone: return "CLOSED"
        case .unknown: return ""
        case .limited: return "LIMIT"
        }
    }

    /// Finished enough that dismiss makes sense.
    var isFinished: Bool {
        switch self {
        case .done, .stale, .gone, .unknown, .limited: return true
        case .working, .needsInput: return false
        }
    }
}

struct SessionHost: Decodable {
    var kind: String
    var windowId: String?
    var app: String?
    var connected: Bool?
}

struct Session: Decodable, Identifiable {
    var id: String
    var label: String
    var display: String?
    var cwd: String?
    var folder: String?
    var profile: String?
    var status: Status
    var statusSince: Date?
    var detail: String?
    var lastActivity: Date?
    var host: SessionHost
    var focusError: String?
    var focusAt: Date?
    var context: ContextFill?
    var title: String?
    var pending: Pending?
    var note: String?
    var stuck: Bool?

    var name: String { display ?? label }

    /// The workspace the session belongs to, for a mute that covers all of it.
    var workspaceKey: String? { folder ?? cwd }

    var contextPercent: Int? {
        guard let p = context?.percent, p > 0 else { return nil }
        return min(100, p)
    }

    /// The permission prompt to answer, only while the session waits on it.
    var answerable: Pending? { status == .needsInput ? pending : nil }

    var isStuck: Bool { stuck == true && status == .working }

    /// The two-letter chip for another account: ~/.claude-work → WK, skp → SP.
    var profileChip: String? {
        guard let p = profile, p != "default", !p.isEmpty else { return nil }
        return String(p.prefix(2)).uppercased()
    }

    var isPanel: Bool { host.kind == "vscode-panel" }
}

extension Board {
    static func decode(_ data: Data) throws -> Board {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = Board.parseDate(raw) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "not a date: \(raw)")
        }
        return try decoder.decode(Board.self, from: data)
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Go writes nanoseconds and "+03:00" zones; ISO8601DateFormatter wants at most three fraction digits.
    static func parseDate(_ raw: String) -> Date? {
        if let d = plain.date(from: raw) { return d }
        var trimmed = raw
        if let dot = raw.firstIndex(of: "."), let end = raw[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let digits = raw[raw.index(after: dot)..<end]
            let kept = digits.prefix(3)
            trimmed = String(raw[..<dot]) + "." + kept + (kept.count < 3 ? String(repeating: "0", count: 3 - kept.count) : "") + String(raw[end...])
        }
        return fractional.date(from: trimmed) ?? plain.date(from: trimmed)
    }
}
