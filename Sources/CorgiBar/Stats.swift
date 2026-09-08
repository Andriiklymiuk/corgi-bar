import Foundation

/// What Claude Code keeps in ~/.claude/stats-cache.json: activity per day,
/// per hour, and tokens per model per day. Read only when the Today tab shows.
struct ClaudeStats: Decodable {
    struct Day: Decodable {
        var date: String
        var messageCount: Int
        var sessionCount: Int
        var toolCallCount: Int
    }
    struct ModelDay: Decodable {
        var date: String
        var tokensByModel: [String: Int64]
    }
    var dailyActivity: [Day] = []
    var dailyModelTokens: [ModelDay] = []
    var hourCounts: [String: Int] = [:]

    enum CodingKeys: String, CodingKey { case dailyActivity, dailyModelTokens, hourCounts }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyActivity = try c.decodeIfPresent([Day].self, forKey: .dailyActivity) ?? []
        dailyModelTokens = try c.decodeIfPresent([ModelDay].self, forKey: .dailyModelTokens) ?? []
        hourCounts = try c.decodeIfPresent([String: Int].self, forKey: .hourCounts) ?? [:]
    }

    static let defaultPath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/stats-cache.json")

    static func load(path: String = defaultPath) -> ClaudeStats? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(ClaudeStats.self, from: data)
    }

    /// One cell per day for the last `weeks` weeks ending today, oldest first, Monday-aligned.
    func heatmap(weeks: Int = 12, today: Date = Date(), calendar: Calendar = .current) -> [(date: Date, count: Int)] {
        let byDate = Dictionary(dailyActivity.map { ($0.date, $0.messageCount) }, uniquingKeysWith: +)
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        let end = calendar.startOfDay(for: today)
        let weekday = (calendar.component(.weekday, from: end) + 5) % 7 // Monday = 0
        let days = (weeks - 1) * 7 + weekday + 1
        return (0..<days).reversed().compactMap { back in
            guard let d = calendar.date(byAdding: .day, value: -back, to: end) else { return nil }
            return (d, byDate[f.string(from: d)] ?? 0)
        }
    }

    var hours: [Int] {
        (0..<24).map { hourCounts[String($0)] ?? 0 }
    }

    /// Tokens by model for today, or nothing when the cache has no entry for it.
    func tokensToday(today: Date = Date(), calendar: Calendar = .current) -> [(model: String, tokens: Int64)] {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        let key = f.string(from: today)
        guard let day = dailyModelTokens.last(where: { $0.date == key }) else { return [] }
        return day.tokensByModel.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}
