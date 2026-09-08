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
    var path: String?
    var daemonRunning: Bool = false

    static let empty = Board()

    enum CodingKeys: String, CodingKey {
        case updatedAt, size, overflow, needsInput, working, slots, sessions, windows, frontWindow, frontSession, notice, noticeAt, path, daemonRunning
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
    var profile: String?
    var status: Status
    var statusSince: Date?
    var detail: String?
    var lastActivity: Date?
    var host: SessionHost
    var focusError: String?
    var focusAt: Date?

    var name: String { display ?? label }

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
