import Foundation

/// "15s", "9m", "2h": elapsed since a status began, bucketed to 5 s so a
/// working row redraws at most that often.
func elapsedText(since: Date?, now: Date = Date()) -> String {
    guard let since else { return "" }
    let s = max(0, Int(now.timeIntervalSince(since)) / 5 * 5)
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}
