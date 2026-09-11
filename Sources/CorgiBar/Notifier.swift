import Foundation
import AppKit
import UserNotifications

/// Quiet hours as minutes since midnight; a window that crosses midnight
/// (22:00 → 07:00) wraps.
struct QuietHours: Equatable {
    var enabled: Bool
    var startMinutes: Int
    var endMinutes: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, startMinutes != endMinutes else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if startMinutes < endMinutes { return now >= startMinutes && now < endMinutes }
        return now >= startMinutes || now < endMinutes
    }
}

/// A notification when a session starts needing you, or hits its limit.
/// UNUserNotificationCenter only works from a real .app bundle; unbundled
/// (swift run) it is skipped. corgi itself notifies when a limit lifts.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    var enabled = true
    var quietHours = QuietHours(enabled: false, startMinutes: 22 * 60, endMinutes: 8 * 60)
    /// System sound names per event ("Glass", "Pop", …); empty means none.
    var sounds: [Status: String] = [:]
    var onOpen: ((String) -> Void)?

    static let soundNames = ["", "Glass", "Pop", "Submarine", "Ping", "Tink", "Blow", "Bottle", "Funk", "Hero", "Purr"]

    private let defaults = UserDefaults.standard
    var muted: Set<String> {
        didSet { defaults.set(Array(muted), forKey: "mutedSessions") }
    }
    var mutedWorkspaces: Set<String> {
        didSet { defaults.set(Array(mutedWorkspaces), forKey: "mutedWorkspaces") }
    }

    private override init() {
        muted = Set(defaults.stringArray(forKey: "mutedSessions") ?? [])
        mutedWorkspaces = Set(defaults.stringArray(forKey: "mutedWorkspaces") ?? [])
        super.init()
    }

    private var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }()

    func prepare() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func isMuted(_ s: Session) -> Bool {
        muted.contains(s.id) || (s.workspaceKey.map { mutedWorkspaces.contains($0) } ?? false)
    }

    func boardMoved(from old: Board, to new: Board, now: Date = Date()) {
        // A session mute lives as long as the session is on the board.
        let ids = Set(new.sessions.map(\.id))
        if !new.sessions.isEmpty, !muted.isSubset(of: ids) { muted = muted.intersection(ids) }
        guard enabled, !quietHours.contains(now) else { return }
        let before = Dictionary(uniqueKeysWithValues: old.sessions.map { ($0.id, $0.status) })
        for s in new.sessions where !isMuted(s) && before[s.id] != s.status {
            let sound = sounds[s.status].flatMap { $0.isEmpty ? nil : $0 }
            if let sound { NSSound(named: sound)?.play() }
            guard let center else { continue }
            let content = UNMutableNotificationContent()
            switch s.status {
            case .needsInput:
                content.title = "\(s.name) needs you"
                content.body = s.answerable?.text ?? s.detail ?? ""
                content.sound = sound == nil ? .default : nil
            case .limited:
                content.title = "\(s.name) hit the usage limit"
                content.body = s.detail ?? ""
            default:
                continue
            }
            content.userInfo = ["sessionId": s.id]
            center.add(UNNotificationRequest(identifier: "session-\(s.id)", content: content, trigger: nil))
        }
    }

    /// One plain notification: what corgi answered when a click could not
    /// do what it said — the menu has no room for an error line.
    func say(_ title: String, _ body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        center.add(UNNotificationRequest(identifier: "said-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["sessionId"] as? String {
            DispatchQueue.main.async { self.onOpen?(id) }
        }
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
