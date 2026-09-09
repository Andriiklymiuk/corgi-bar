import Foundation
import Combine

/// Asks GitHub for the newest corgi-bar release once every few hours and
/// remembers it, so the footer can say "0.6.0 available". No downloads, no
/// Sparkle: Homebrew or the release page does the install.
final class UpdateCheck: ObservableObject {
    static let shared = UpdateCheck()

    @Published private(set) var latest: String?
    private var lastChecked: Date = .distantPast
    private let interval: TimeInterval = 6 * 3600

    var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The newer version when there is one, else nil.
    var available: String? {
        guard let latest, Self.isNewer(latest, than: current) else { return nil }
        return latest
    }

    static let releasesURL = URL(string: "https://github.com/Andriiklymiuk/corgi-bar/releases/latest")!

    func checkIfDue() {
        guard Date().timeIntervalSince(lastChecked) > interval else { return }
        lastChecked = Date()
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/Andriiklymiuk/corgi-bar/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async { self.latest = version }
        }.resume()
    }

    /// Dotted numeric compare: "0.10.0" is newer than "0.9.1".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
