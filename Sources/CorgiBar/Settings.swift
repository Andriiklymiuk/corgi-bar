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
    @Published var promptHotKey: String { didSet { d.set(promptHotKey, forKey: "promptHotKey") } }
    @Published var nextHotKey: String { didSet { d.set(nextHotKey, forKey: "nextHotKey") } }
    @Published var approveFromBar: Bool { didSet { d.set(approveFromBar, forKey: "approveFromBar") } }
    @Published var notifications: Bool { didSet { d.set(notifications, forKey: "notifications"); Notifier.shared.enabled = notifications } }
    @Published var quietHoursOn: Bool { didSet { d.set(quietHoursOn, forKey: "quietHoursOn"); pushQuietHours() } }
    @Published var quietStart: Int { didSet { d.set(quietStart, forKey: "quietStart"); pushQuietHours() } }
    @Published var quietEnd: Int { didSet { d.set(quietEnd, forKey: "quietEnd"); pushQuietHours() } }
    @Published var soundNeedsInput: String { didSet { d.set(soundNeedsInput, forKey: "soundNeedsInput"); pushSounds() } }
    @Published var soundDone: String { didSet { d.set(soundDone, forKey: "soundDone"); pushSounds() } }
    @Published var soundLimited: String { didSet { d.set(soundLimited, forKey: "soundLimited"); pushSounds() } }
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

    /// The first launch turns login start on. Nobody installs a menu bar app
    /// to open it by hand every morning, and the phone dashboard is dead after
    /// a reboot without it. Running from a build directory cannot register,
    /// so a failure just leaves the toggle off. Once only: a person who turned
    /// it off is not asked again by the next update.
    private func registerAtLoginOnFirstRun() {
        let key = "launchAtLoginDecided"
        guard !d.bool(forKey: key) else { return }
        d.set(true, forKey: key)
        guard !launchAtLogin, Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        do {
            try SMAppService.mainApp.register()
            launchAtLogin = true
        } catch {
            launchAtLogin = false
        }
    }

    private init() {
        terminalChord = d.string(forKey: "terminalChord") ?? "ctrl+y"
        panelChord = d.string(forKey: "panelChord") ?? "cmd+d"
        panelSendKey = d.string(forKey: "panelSendKey") ?? "enter"
        panelSendDelay = d.object(forKey: "panelSendDelay") as? Double ?? 1.5
        hotKey = d.string(forKey: "hotKey") ?? "ctrl+alt+space"
        promptHotKey = d.string(forKey: "promptHotKey") ?? "ctrl+alt+p"
        nextHotKey = d.string(forKey: "nextHotKey") ?? "ctrl+alt+n"
        approveFromBar = d.bool(forKey: "approveFromBar")
        notifications = d.object(forKey: "notifications") as? Bool ?? true
        quietHoursOn = d.object(forKey: "quietHoursOn") as? Bool ?? false
        quietStart = d.object(forKey: "quietStart") as? Int ?? 22 * 60
        quietEnd = d.object(forKey: "quietEnd") as? Int ?? 8 * 60
        soundNeedsInput = d.string(forKey: "soundNeedsInput") ?? ""
        soundDone = d.string(forKey: "soundDone") ?? ""
        soundLimited = d.string(forKey: "soundLimited") ?? ""
        corgiPath = d.string(forKey: "corgiPath") ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        registerAtLoginOnFirstRun()
        Notifier.shared.enabled = notifications
        Corgi.shared.overridePath = corgiPath.isEmpty ? nil : corgiPath
        pushQuietHours()
        pushSounds()
    }

    private func pushQuietHours() {
        Notifier.shared.quietHours = QuietHours(enabled: quietHoursOn, startMinutes: quietStart, endMinutes: quietEnd)
    }

    private func pushSounds() {
        Notifier.shared.sounds = [.needsInput: soundNeedsInput, .done: soundDone, .limited: soundLimited]
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            NotificationSettings().tabItem { Label("Notifications", systemImage: "bell") }
            TodayView().tabItem { Label("Today", systemImage: "calendar") }
        }
        .frame(width: 500)
        .padding()
    }
}

struct GeneralSettings: View {
    @ObservedObject var settings = Preferences.shared
    @State private var doctor = ""

    var body: some View {
        Form {
            Section("Talk") {
                TextField("Terminal chord", text: $settings.terminalChord)
                TextField("Panel chord", text: $settings.panelChord)
                TextField("Panel send key (blank: none)", text: $settings.panelSendKey)
                Stepper(value: $settings.panelSendDelay, in: 0...5, step: 0.5) { Text("Panel send delay: \(settings.panelSendDelay, specifier: "%.1f") s") }
                Text("Terminal sessions take the chord bound to voice:pushToTalk in ~/.claude/keybindings.json (run /voice tap once). The Claude Code panel has its own shortcut, and only stops recording on the second press, so the send key follows after the delay. Sending any of it needs Accessibility for corgi-bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Hotkeys") {
                HotKeyPicker(title: "Talk", selection: $settings.hotKey)
                HotKeyPicker(title: "Quick prompt", selection: $settings.promptHotKey)
                HotKeyPicker(title: "Next needs you", selection: $settings.nextHotKey)
                Text("Quick prompt opens the dropdown with the field focused. Next needs you jumps to the session that has waited longest, else the one in front.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Board") {
                Toggle("Approve from the menu bar", isOn: $settings.approveFromBar)
                Text("Shows Allow / Deny on a row waiting for permission. corgi refuses risky commands (rm, sudo, --force) unseen; go look at those.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Text("On by default: a menu bar that is not there after a reboot is the one that lied to you. macOS lists it under System Settings › General › Login Items.")
                    .font(.caption).foregroundStyle(.secondary)
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
    }
}

struct HotKeyPicker: View {
    var title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(HotKey.presets) { p in Text(p.name).tag(p.name) }
        }
    }
}

struct NotificationSettings: View {
    @ObservedObject var settings = Preferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("Notify when a session needs you or hits its limit", isOn: $settings.notifications)
                Text("Mute one session or a whole workspace from a row's secondary menu. corgi itself says when a limit lifts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Quiet hours") {
                Toggle("Suppress notifications between", isOn: $settings.quietHoursOn)
                MinutePicker(title: "From", minutes: $settings.quietStart)
                MinutePicker(title: "Until", minutes: $settings.quietEnd)
            }
            Section("Sounds") {
                SoundPicker(title: "Needs you", selection: $settings.soundNeedsInput)
                SoundPicker(title: "Done", selection: $settings.soundDone)
                SoundPicker(title: "Limit hit", selection: $settings.soundLimited)
                Text("System sounds, played by corgi-bar. Done plays a sound only; it raises no banner.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct MinutePicker: View {
    var title: String
    @Binding var minutes: Int

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(Array(stride(from: 0, to: 24 * 60, by: 30)), id: \.self) { m in
                Text(String(format: "%02d:%02d", m / 60, m % 60)).tag(m)
            }
        }
    }
}

struct SoundPicker: View {
    var title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Notifier.soundNames, id: \.self) { n in Text(n.isEmpty ? "off" : n).tag(n) }
        }
        .onChange(of: selection) { name in
            if !name.isEmpty { NSSound(named: name)?.play() }
        }
    }
}
