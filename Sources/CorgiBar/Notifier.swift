import Foundation
import UserNotifications

/// A notification when a session starts needing you, or hits its limit.
/// UNUserNotificationCenter only works from a real .app bundle; unbundled
/// (swift run) it is skipped.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    var enabled = true
    var muted: Set<String> = []
    var onOpen: ((String) -> Void)?

    private var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }()

    func prepare() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func boardMoved(from old: Board, to new: Board) {
        guard enabled, let center else { return }
        let before = Dictionary(uniqueKeysWithValues: old.sessions.map { ($0.id, $0.status) })
        for s in new.sessions where !muted.contains(s.id) && before[s.id] != s.status {
            let content = UNMutableNotificationContent()
            switch s.status {
            case .needsInput:
                content.title = "\(s.name) needs you"
                content.body = s.detail ?? ""
                content.sound = .default
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
