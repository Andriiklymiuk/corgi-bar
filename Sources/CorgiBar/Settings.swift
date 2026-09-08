import Foundation
import SwiftUI
import ServiceManagement

/// Everything a person can change, in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    @Published var terminalChord: String { didSet { d.set(terminalChord, forKey: "terminalChord") } }
    @Published var panelChord: String { didSet { d.set(panelChord, forKey: "panelChord") } }
    @Published var panelSendKey: String { didSet { d.set(panelSendKey, forKey: "panelSendKey") } }
    @Published var panelSendDelay: Double { didSet { d.set(panelSendDelay, forKey: "panelSendDelay") } }
    @Published var hotKey: String { didSet { d.set(hotKey, forKey: "hotKey") } }
    @Published var notifications: Bool { didSet { d.set(notifications, forKey: "notifications"); Notifier.shared.enabled = notifications } }
    @Published var corgiPath: String { didSet { d.set(corgiPath, forKey: "corgiPath"); Corgi.shared.overridePath = corgiPath.isEmpty ? nil : corgiPath } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private init() {
        terminalChord = d.string(forKey: "terminalChord") ?? "ctrl+y"
        panelChord = d.string(forKey: "panelChord") ?? "cmd+d"
        panelSendKey = d.string(forKey: "panelSendKey") ?? "enter"
        panelSendDelay = d.object(forKey: "panelSendDelay") as? Double ?? 1.5
        hotKey = d.string(forKey: "hotKey") ?? "ctrl+alt+space"
        notifications = d.object(forKey: "notifications") as? Bool ?? true
        corgiPath = d.string(forKey: "corgiPath") ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Notifier.shared.enabled = notifications
        Corgi.shared.overridePath = corgiPath.isEmpty ? nil : corgiPath
    }
}

struct SettingsView: View {
    @ObservedObject var settings = Preferences.shared
    @State private var doctor = ""

    var body: some View {
        Form {
            Section("Talk") {
                TextField("Terminal chord", text: $settings.terminalChord)
                TextField("Panel chord", text: $settings.panelChord)
                TextField("Panel send key (blank: none)", text: $settings.panelSendKey)
                Stepper(value: $settings.panelSendDelay, in: 0...5, step: 0.5) { Text("Panel send delay: \(settings.panelSendDelay, specifier: "%.1f") s") }
                Picker("Global hotkey", selection: $settings.hotKey) {
                    ForEach(HotKey.presets) { p in Text(p.name).tag(p.name) }
                }
                Text("Terminal sessions take the chord bound to voice:pushToTalk in ~/.claude/keybindings.json (run /voice tap once). The Claude Code panel has its own shortcut, and only stops recording on the second press, so the send key follows after the delay. Sending any of it needs Accessibility for corgi-bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Notify when a session needs you", isOn: $settings.notifications)
                TextField("corgi path (blank = automatic)", text: $settings.corgiPath)
                Button("Run corgi agent doctor") {
                    Corgi.shared.runInBackground(["agent", "doctor"]) { r in doctor = r.stdout + r.stderr }
                }
                if !doctor.isEmpty {
                    ScrollView { Text(doctor).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 220)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
