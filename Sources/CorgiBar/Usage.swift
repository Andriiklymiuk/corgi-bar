import Foundation

/// One reading of an account's limits, as corgi appends them to
/// `<agentDir>/usage/<profile>.jsonl`.
struct UsageSample: Decodable {
    var at: Date
    var fetchedAt: Date?
    var fiveHour: Int
    var sevenDay: Int
}

enum UsageSamples {
    /// The file corgi keeps for a profile; the name is sanitised the way corgi does it.
    static func path(agentDir: String, profile: String) -> String {
        var name = String(profile.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
        if name.isEmpty { name = "default" }
        return (agentDir as NSString).appendingPathComponent("usage/\(name).jsonl")
    }

    /// Readings from the last `span` seconds, oldest first. Only the file's
    /// tail is read: a day of samples is a few hundred KB at most.
    static func load(agentDir: String, profile: String, span: TimeInterval = 5 * 3600, now: Date = Date()) -> [UsageSample] {
        guard let data = FileManager.default.contents(atPath: path(agentDir: agentDir, profile: profile)) else { return [] }
        return parse(data, since: now.addingTimeInterval(-span))
    }

    static func parse(_ data: Data, since: Date) -> [UsageSample] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            guard let date = Board.parseDate(raw) else { throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: raw) }
            return date
        }
        var out: [UsageSample] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let s = try? decoder.decode(UsageSample.self, from: Data(line)), s.at >= since else { continue }
            out.append(s)
        }
        return out.sorted { $0.at < $1.at }
    }
}

/// The one line under a limit bar: the pace and where it lands.
struct ForecastLine: Equatable {
    var text: String
    var danger: Bool

    /// "62%/h · runs out 14:32 (before the 16:10 reset)" in red when the
    /// window empties first, "62%/h · lasts until the reset" when it does
    /// not, "pace flat" when nothing is climbing.
    static func make(_ f: WindowForecast?, resetsAt: Date?, timeZone: TimeZone = .current) -> ForecastLine? {
        guard let f else { return nil }
        let rate = ForecastLine.rate(f.percentPerHour)
        guard let exhaustAt = f.exhaustAt else {
            return ForecastLine(text: "\(rate) · pace flat", danger: false)
        }
        if f.safe {
            return ForecastLine(text: "\(rate) · lasts until the reset", danger: false)
        }
        var text = "\(rate) · runs out \(clock(exhaustAt, timeZone: timeZone))"
        if let resetsAt {
            text += " (before the \(clock(resetsAt, timeZone: timeZone)) reset)"
        }
        return ForecastLine(text: text, danger: true)
    }

    static func rate(_ perHour: Double) -> String {
        let rounded = (perHour * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))%/h" }
        return String(format: "%.1f%%/h", rounded)
    }

    static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
