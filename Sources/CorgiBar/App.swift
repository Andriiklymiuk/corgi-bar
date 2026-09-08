import SwiftUI
import AppKit

@main
struct CorgiBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var watcher = BoardWatcher()
    @StateObject private var talk: Talk
    @ObservedObject private var settings = Preferences.shared

    init() {
        let watcher = BoardWatcher()
        _watcher = StateObject(wrappedValue: watcher)
        _talk = StateObject(wrappedValue: Talk(watcher: watcher))
    }

    var body: some Scene {
        MenuBarExtra {
            BoardView(watcher: watcher, talk: talk)
                .onAppear { delegate.attach(watcher: watcher, talk: talk) }
        } label: {
            MenuBarLabel(board: watcher.board, corgiPresent: watcher.corgiPresent)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Wires the pieces that need the app lifecycle: the watcher, the hotkey,
/// notifications, and the talk state that follows the board.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private var attached = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Notifier.shared.prepare()
    }

    @MainActor
    func attach(watcher: BoardWatcher, talk: Talk) {
        guard !attached else { return }
        attached = true
        watcher.start()
        Notifier.shared.onOpen = { id in Corgi.shared.runInBackground(["agent", "focus", id]) }
        hotKey = HotKey { Task { @MainActor in talk.press() } }
        applyHotKey(talk: talk)
        watcher.$board.sink { board in talk.boardMoved(board) }.store(in: &bag)
        Preferences.shared.$hotKey.sink { [weak self] _ in self?.applyHotKey(talk: talk) }.store(in: &bag)
    }

    private func applyHotKey(talk: Talk) {
        let name = Preferences.shared.hotKey
        if let preset = HotKey.presets.first(where: { $0.name == name }) {
            hotKey?.register(preset)
        }
    }

    private var bag = Set<AnyCancellable>()
}

import Combine

/// The menu bar item: a dog, tinted by the loudest thing on the board, and
/// the count of sessions that need you. Drawn as a bitmap so the colour
/// survives the menu bar's template rendering.
struct MenuBarLabel: View {
    var board: Board
    var corgiPresent: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarLabel.icon(for: corgiPresent ? board.mood : .off))
            if board.needsInput > 0 {
                Text("\(board.needsInput)").font(.system(size: 12, weight: .bold))
            }
        }
    }

    private static var cache: [Mood: NSImage] = [:]

    static func icon(for mood: Mood) -> NSImage {
        if let cached = cache[mood] { return cached }
        let image = draw(mood)
        cache[mood] = image
        return image
    }

    private static func draw(_ mood: Mood) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let symbol = NSImage(systemSymbolName: "dog", accessibilityDescription: nil) ?? NSImage(systemSymbolName: "pawprint", accessibilityDescription: nil)
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let tint: NSColor
            switch mood {
            case .off: tint = .tertiaryLabelColor
            case .quiet: tint = .labelColor
            case .working: tint = NSColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1)
            case .needsInput: tint = NSColor(red: 0.90, green: 0.28, blue: 0.30, alpha: 1)
            case .limited: tint = NSColor(red: 0.36, green: 0.55, blue: 0.94, alpha: 1)
            }
            if let symbol = symbol?.withSymbolConfiguration(config) {
                tint.set()
                let tinted = symbol.copy() as! NSImage
                tinted.lockFocus()
                tint.set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                let origin = NSPoint(x: (rect.width - tinted.size.width) / 2, y: (rect.height - tinted.size.height) / 2)
                tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct BoardView: View {
    @ObservedObject var watcher: BoardWatcher
    @ObservedObject var talk: Talk
    @State private var now = Date()
    @State private var flashed: Set<String> = []
    private let ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Corgi.shared.runInBackground(["agent", "new"])
            } label: {
                Label("New session", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!watcher.board.daemonRunning || watcher.board.windows.isEmpty)
            .help(watcher.board.windows.isEmpty ? "Open a folder in VS Code with the corgi extension" : "A claude terminal in the window in front")

            Divider()
            if watcher.board.sessions.isEmpty {
                Text(watcher.board.daemonRunning ? "No Claude Code session running" : "corgi agent is not running")
                    .foregroundStyle(.secondary).padding(.vertical, 4)
            }
            ForEach(watcher.board.orderedSessions) { session in
                SessionRow(session: session, board: watcher.board, now: now, talk: talk)
            }
            AccountsView(watcher: watcher)
            RemoteView(watcher: watcher)
            Divider()
            HStack {
                Button {
                    talk.press()
                } label: {
                    Label(talk.state == .recording ? "REC · press to send" : "Talk", systemImage: talk.state == .recording ? "record.circle.fill" : "mic")
                        .foregroundStyle(talk.state == .recording ? Color.red : Color.primary)
                }
                .keyboardShortcut("t", modifiers: [.command])
                Spacer()
                Text(Preferences.shared.hotKey).font(.caption).foregroundStyle(.secondary)
            }
            if let err = talk.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if let notice = watcher.board.notice, let at = watcher.board.noticeAt, now.timeIntervalSince(at) < 60 {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }.font(.caption)
                Button("Quit") { NSApp.terminate(nil) }.font(.caption)
            }
        }
        .padding(10)
        .frame(width: 340)
        .onReceive(ticker) { now = $0 }
        .onAppear { watcher.refreshStatus(force: true) }
    }

    private var footer: String {
        guard watcher.corgiPresent else { return "corgi not found — brew install andriiklymiuk/homebrew-tools/corgi" }
        let v = watcher.corgiVersion.map { "corgi \($0)" } ?? "corgi"
        return watcher.board.daemonRunning ? "\(v) · daemon running" : "\(v) · daemon off — corgi agent install"
    }
}

struct SessionRow: View {
    var session: Session
    var board: Board
    var now: Date
    @ObservedObject var talk: Talk
    @State private var hover = false

    var body: some View {
        Button {
            talk.noteClick(session.id)
            Corgi.shared.runInBackground(["agent", "focus", session.id])
        } label: {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(session.name).font(.system(size: 13, weight: .semibold))
                        if let chip = session.profileChip {
                            Text(chip).font(.system(size: 9, weight: .bold)).padding(.horizontal, 3).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary, lineWidth: 1))
                        }
                        if board.frontSession == session.id {
                            Text("●").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        if let e = session.focusError, !e.isEmpty {
                            Text("⚠").help(e)
                        }
                    }
                    if let d = session.detail, !d.isEmpty {
                        Text(d).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(session.status.word).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                    if session.status != .limited {
                        Text(elapsedText(since: session.statusSince, now: now)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.primary.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .opacity(session.status == .gone ? 0.4 : 1)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Dismiss") { Corgi.shared.runInBackground(["agent", "dismiss", session.id]) }
                .disabled(!session.status.isFinished)
            if let key = board.keyNumber(of: session.id) {
                let pinned = board.slots.first { $0.sessionId == session.id }?.pinned ?? false
                Button(pinned ? "Unpin" : "Pin") {
                    var args = ["agent", "pin", String(key)]
                    if pinned { args.append("--off") }
                    Corgi.shared.runInBackground(args)
                }
            }
            Button(Notifier.shared.muted.contains(session.id) ? "Unmute notifications" : "Mute notifications") {
                if Notifier.shared.muted.contains(session.id) { Notifier.shared.muted.remove(session.id) } else { Notifier.shared.muted.insert(session.id) }
            }
            Divider()
            Button("Copy session id") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            if let cwd = session.cwd {
                Button("Open folder in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
            }
        }
    }

    private var color: Color {
        switch session.status {
        case .working: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .needsInput: return Color(red: 0.90, green: 0.28, blue: 0.30)
        case .done: return Color(red: 0.19, green: 0.64, blue: 0.42)
        case .limited: return Color(red: 0.36, green: 0.55, blue: 0.94)
        case .stale, .gone, .unknown: return Color.secondary
        }
    }
}


/// One line per Claude account: tokens today and this week, and the
/// usage-limit reset when a session under it hit the limit.
struct AccountsView: View {
    @ObservedObject var watcher: BoardWatcher

    var body: some View {
        let accounts = watcher.status.accounts(board: watcher.board)
        if !accounts.isEmpty {
            Divider()
            ForEach(accounts) { a in
                HStack(spacing: 6) {
                    if !a.chip.isEmpty {
                        Text(a.chip).font(.system(size: 9, weight: .bold)).padding(.horizontal, 3).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary, lineWidth: 1))
                    }
                    Text(a.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if let until = a.limitedUntil {
                        Text(until).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(red: 0.36, green: 0.55, blue: 0.94))
                    } else {
                        Text("\(formatTokens(a.tokensToday)) today · \(formatTokens(a.tokensWeek)) week").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

/// The supervised remote sessions corgi runs per workspace: online or not,
/// open in the Claude app, start or stop, and the dashboard.
struct RemoteView: View {
    @ObservedObject var watcher: BoardWatcher
    @AppStorage("remoteExpanded") private var expanded = false

    var body: some View {
        if watcher.status.running, !watcher.status.workspaces.isEmpty {
            Divider()
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(watcher.status.workspaces) { w in
                    HStack(spacing: 6) {
                        Circle().fill(w.running ? Color(red: 0.19, green: 0.64, blue: 0.42) : Color.secondary).frame(width: 6, height: 6)
                        Text(w.workspaceId).font(.system(size: 11))
                        Spacer()
                        if let url = w.sessionUrl, let u = URL(string: url) {
                            Button("Open") { NSWorkspace.shared.open(u) }.font(.system(size: 10)).buttonStyle(.link)
                        }
                        Button(w.running ? "Stop" : "Start") {
                            Corgi.shared.runInBackground(["agent", "session", w.running ? "stop" : "start", w.workspaceId]) { _ in
                                self.watcher.refreshStatus(force: true)
                            }
                        }.font(.system(size: 10)).buttonStyle(.link)
                    }
                    .padding(.horizontal, 4)
                }
                if let url = watcher.status.dashboardUrl, let u = URL(string: url) {
                    Button { NSWorkspace.shared.open(u) } label: {
                        Label("Open dashboard", systemImage: "iphone").font(.system(size: 11))
                    }.buttonStyle(.link).padding(.horizontal, 4)
                }
            } label: {
                let online = watcher.status.workspaces.filter { $0.running }.count
                Text("Remote · \(online) of \(watcher.status.workspaces.count) online").font(.system(size: 11, weight: .semibold))
            }
        }
    }
}
