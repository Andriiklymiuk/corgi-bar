import SwiftUI
import AppKit
import Combine

@main
struct CorgiBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var watcher = BoardWatcher.shared
    @StateObject private var talk: Talk
    @ObservedObject private var settings = Preferences.shared

    init() {
        let watcher = BoardWatcher.shared
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

/// Opens the Settings scene. `showSettingsWindow:` was the selector on
/// macOS 13; from 14 a MenuBarExtra ignores it, and SwiftUI's own
/// `openSettings` is the way. The app comes forward first so the window
/// is not born behind whatever was in front.
struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14, *) {
            ModernSettingsButton()
        } else {
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }.font(.caption)
        }
    }
}

@available(macOS 14, *)
private struct ModernSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }.font(.caption)
    }
}

/// The quick prompt hotkey opens the dropdown and asks the field to take focus.
final class PromptFocus: ObservableObject {
    static let shared = PromptFocus()
    @Published var requested = false
}

/// Opens the MenuBarExtra dropdown the way a click would: SwiftUI exposes no
/// call for it, so the status item's button is pressed.
enum MenuBarOpener {
    static func open() {
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            if let button = button(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func button(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let b = view as? NSStatusBarButton { return b }
        for sub in view.subviews {
            if let b = button(in: sub) { return b }
        }
        return nil
    }
}

/// Wires the pieces that need the app lifecycle: the watcher, the hotkeys,
/// notifications, and the talk state that follows the board.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var talkKey: HotKey?
    private var promptKey: HotKey?
    private var nextKey: HotKey?
    private var attached = false
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Notifier.shared.prepare()
        // Siri learns the workspace names ("start acme-api in corgi-bar")
        // from here; off the main thread, it runs corgi to list them.
        Task.detached(priority: .utility) { CorgiShortcuts.updateAppShortcutParameters() }
    }

    @MainActor
    func attach(watcher: BoardWatcher, talk: Talk) {
        guard !attached else { return }
        attached = true
        watcher.start()
        Notifier.shared.onOpen = { id in Corgi.shared.runInBackground(["agent", "focus", id]) }
        talkKey = HotKey { Task { @MainActor in talk.press() } }
        promptKey = HotKey {
            Task { @MainActor in
                PromptFocus.shared.requested = true
                MenuBarOpener.open()
            }
        }
        nextKey = HotKey {
            Task { @MainActor in
                if let s = watcher.board.nextNeedingYou() {
                    talk.noteClick(s.id)
                    Corgi.shared.runInBackground(["agent", "focus", s.id])
                }
            }
        }
        let prefs = Preferences.shared
        prefs.$hotKey.sink { [weak self] in self?.talkKey?.register(named: $0) }.store(in: &bag)
        prefs.$promptHotKey.sink { [weak self] in self?.promptKey?.register(named: $0) }.store(in: &bag)
        prefs.$nextHotKey.sink { [weak self] in self?.nextKey?.register(named: $0) }.store(in: &bag)
        watcher.$board.sink { board in talk.boardMoved(board) }.store(in: &bag)
    }
}

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

enum Palette {
    // System colours: AppKit picks the light or dark variant, and keeps them
    // legible over the popover's translucent material, which fixed tints
    // tuned for one appearance are not.
    static let amber = Color(nsColor: .systemOrange)
    static let red = Color(nsColor: .systemRed)
    static let green = Color(nsColor: .systemGreen)
    static let blue = Color(nsColor: .systemBlue)

    static func status(_ s: Status) -> Color {
        switch s {
        case .working: return amber
        case .needsInput: return red
        case .done: return green
        case .limited: return blue
        case .stale, .gone, .unknown: return Color.secondary
        }
    }

    /// Grey while there is room, red from 85: the Stream Deck plugin's rule.
    static func context(_ percent: Int) -> Color {
        percent >= 85 ? red : Color.secondary.opacity(0.3)
    }

    static let sectionTitle = Font.system(size: 11, weight: .semibold)
}

struct BoardView: View {
    @ObservedObject var watcher: BoardWatcher
    @ObservedObject var talk: Talk
    @ObservedObject private var promptFocus = PromptFocus.shared
    @ObservedObject private var settings = Preferences.shared
    @ObservedObject private var updates = UpdateCheck.shared
    @State private var now = Date()
    @State private var prompt = ""
    @State private var carriedId: String?
    @FocusState private var promptFocused: Bool
    private let ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            promptSection.padding(.vertical, 10)
            Divider()
            sessionsSection.padding(.vertical, 10)
            // What is waiting on you comes before what you have spent: the
            // menu is opened to find work, not to read a budget.
            WatchView(watcher: watcher)
            AccountsView(watcher: watcher)
            RemoteView(watcher: watcher)
            Divider()
            footerSection.padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .frame(width: 340)
        // Opaque, not the menu bar's glass: status colours have to read on a
        // known surface, not on whatever wallpaper is blurred behind them.
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(ticker) { now = $0 }
        .onAppear {
            now = Date()
            watcher.refreshStatus()
            updates.checkIfDue()
            if promptFocus.requested {
                promptFocus.requested = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { promptFocused = true }
            }
        }
        .onChange(of: promptFocus.requested) { requested in
            if requested {
                promptFocus.requested = false
                promptFocused = true
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(promptPlaceholder, text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .focused($promptFocused)
                    .onSubmit(sendPrompt)
                    .disabled(!watcher.board.daemonRunning)
                Button {
                    Corgi.shared.runInBackground(settings.isolate ? ["agent", "new", "--isolate"] : ["agent", "new"])
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!watcher.board.daemonRunning || watcher.board.windows.isEmpty)
                .help(watcher.board.windows.isEmpty ? "Open a folder in VS Code with the corgi extension" : settings.isolate ? "New session in the front window, in a worktree of its own" : "New session in the front window")
                .contextMenu {
                    Button("New session in a worktree of its own") { Corgi.shared.runInBackground(["agent", "new", "--isolate"]) }
                }
            }
            if promptFocused {
                Text("⏎ send · ⌥⏎ newline · \(HotKey.symbols(settings.promptHotKey))")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if watcher.board.sessions.isEmpty {
                Text(watcher.board.daemonRunning ? "No Claude Code session running" : "corgi agent is not running")
                    .foregroundStyle(.secondary)
            }
            ForEach(watcher.board.groups) { group in
                VStack(alignment: .leading, spacing: 2) {
                    GroupHeader(group: group)
                    ForEach(group.sessions) { session in
                        SessionRow(session: session, board: watcher.board, now: now, talk: talk, carriedId: $carriedId,
                                   showProfile: group.commonProfileChip == nil)
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let err = talk.lastError {
                Text(err).font(.caption).foregroundStyle(Palette.red)
            }
            if let notice = watcher.board.notice, let at = watcher.board.noticeAt, now.timeIntervalSince(at) < 60 {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            if let v = updates.available {
                Button("corgi-bar \(v) available") { NSWorkspace.shared.open(UpdateCheck.releasesURL) }
                    .buttonStyle(.plain).foregroundStyle(Palette.blue).font(.caption)
                    .help("brew upgrade --cask corgi-bar, or download from the release page")
            }
            HStack(spacing: 6) {
                Text(footer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { watcher.reloadEverything() } label: { Image(systemName: "arrow.clockwise") }
                    .font(.caption)
                    .help("Reload: the daemon rescans sessions and polls every tracker now; the phone and the page see it too")
                TalkButton(talk: talk, hotKey: settings.hotKey)
                SettingsButton()
                Button("Quit") { NSApp.terminate(nil) }.font(.caption)
            }
        }
    }

    private var promptPlaceholder: String {
        if let s = talk.target() { return "Prompt for \(s.name)" }
        return "Prompt"
    }

    private func sendPrompt() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let session = talk.target() else {
            talk.lastError = "no Claude Code session to send to"
            return
        }
        let withoutEnter = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        prompt = ""
        promptFocused = false
        talk.sendText(session, text, enter: !withoutEnter)
    }

    private var footer: String {
        guard watcher.corgiPresent else { return "corgi not found — brew install andriiklymiuk/homebrew-tools/corgi" }
        let v = watcher.corgiVersion.map { "corgi \($0)" } ?? "corgi"
        return watcher.board.daemonRunning ? "\(v) · daemon running" : "\(v) · daemon off — corgi agent install"
    }
}

/// One workspace's heading: its name, the account its sessions share, how many.
struct GroupHeader: View {
    var group: SessionGroup

    var body: some View {
        HStack(spacing: 6) {
            Text(group.label).font(Palette.sectionTitle).foregroundStyle(.secondary)
            if let chip = group.commonProfileChip {
                Chip(chip)
            }
            Spacer()
            if group.sessions.count > 1 {
                Text("\(group.sessions.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// The mic in the footer: red and pulsing while the session in front records.
struct TalkButton: View {
    @ObservedObject var talk: Talk
    var hotKey: String
    @State private var pulsing = false

    var body: some View {
        let recording = talk.state == .recording
        Button { talk.press() } label: {
            Image(systemName: "mic.fill")
                .foregroundStyle(recording ? Palette.red : Color.primary)
                .opacity(recording && pulsing ? 0.35 : 1)
        }
        .font(.caption)
        .keyboardShortcut("t", modifiers: [.command])
        .help(recording ? "Listening · press to send" : "Talk · \(hotKey)")
        .onAppear { pulse(recording) }
        .onChange(of: recording) { pulse($0) }
    }

    private func pulse(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulsing = true }
        } else {
            withAnimation(.default) { pulsing = false }
        }
    }
}

struct SessionRow: View {
    var session: Session
    var board: Board
    var now: Date
    @ObservedObject var talk: Talk
    @Binding var carriedId: String?
    var showProfile = true
    @ObservedObject private var settings = Preferences.shared
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button(action: focus) { main }
                    .buttonStyle(.plain)
                if settings.approveFromBar, let pending = session.answerable {
                    AnswerButtons(session: session, pending: pending, talk: talk)
                }
            }
            if let percent = session.contextPercent {
                ContextBar(percent: percent).padding(.horizontal, 4)
            }
            if session.status == .limited {
                carry
            }
            if session.isDrifting {
                fresh
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.primary.opacity(0.08) : .clear))
        .overlay(alignment: .leading) {
            if board.frontSession == session.id {
                RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 2).padding(.vertical, 4)
                    .help("The session in the window in front — what Talk and the prompt go to")
            }
        }
        .opacity(session.status == .gone ? 0.4 : 1)
        .onHover { hover = $0 }
        .contextMenu { menu }
    }

    private func focus() {
        talk.noteClick(session.id)
        Corgi.shared.runInBackground(["agent", "focus", session.id])
    }

    private var main: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(session.title ?? session.shortName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let title = session.title, session.shortName != session.label, session.shortName != title {
                        Chip(session.shortName)
                    }
                    if showProfile, let chip = session.profileChip {
                        Chip(chip)
                    }
                    if session.isStuck {
                        Text("slow").font(.system(size: 9, weight: .bold)).padding(.horizontal, 3).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.amber.opacity(0.25)))
                            .help("Working, but no event for 12 minutes")
                    }
                    if session.isDrifting {
                        Text("drift").font(.system(size: 9, weight: .bold)).padding(.horizontal, 3).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.red.opacity(0.25)))
                            .help(session.driftText)
                    }
                    // Another session on the same files: work crossing streams.
                    if session.isCrossing, let line = session.overlapLine {
                        Text("crossing").font(.system(size: 9, weight: .bold)).padding(.horizontal, 3).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.amber.opacity(0.25)))
                            .help(line)
                    }
                    if let tests = session.tests {
                        Text(tests.ok ? "✓" : "✗").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tests.ok ? Palette.green : Palette.red)
                            .help(tests.line + (tests.at.map { " · " + elapsedText(since: $0, now: now) } ?? ""))
                    }
                    if let changes = session.changesLine {
                        Chip(changes)
                    }
                    // What it has cost; red once it passed its budget.
                    if let spent = session.spendLine {
                        if session.isOverBudget {
                            Text("\(spent) over budget").font(.system(size: 9, weight: .bold)).padding(.horizontal, 3).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Palette.red.opacity(0.25)))
                                .help(session.cap.map { "budget \(formatTokens($0)) tokens · corgi agent cap" } ?? "corgi agent cap")
                        } else {
                            Chip(spent).help("tokens this session has cost, cache reads included")
                        }
                    }
                    if let e = session.focusError, !e.isEmpty {
                        Text("⚠").help(e)
                    }
                }
                if let line = secondary {
                    Text(line).font(.system(size: 10, design: .monospaced)).foregroundStyle(session.note != nil ? .primary : .secondary).lineLimit(1)
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
        .padding(.horizontal, 4)
    }

    /// The note when there is one, else what the session is doing, else the
    /// branch it is on.
    private var secondary: String? {
        if let note = session.note, !note.isEmpty { return note }
        if let why = session.drift?.first, !why.isEmpty { return why }
        if let line = session.overlapLine { return "⚠ " + line }
        if session.isStuck {
            return "no activity \(elapsedText(since: session.lastActivity, now: now))"
        }
        if let pending = session.answerable { return "permission: \(pending.text)" }
        if let line = session.limitLine(now: now) { return line }
        if let d = session.detail, !d.isEmpty { return d }
        if let b = session.branch, !b.isEmpty { return b }
        return nil
    }

    /// The way out of a drift: a clean session started from a handoff,
    /// under the same account. What the phone's Fresh button does.
    @ViewBuilder private var fresh: some View {
        HStack(spacing: 6) {
            Button("Fresh from a handoff") {
                Corgi.shared.runInBackground(["agent", "carry", session.id, "--fresh"])
            }
            .buttonStyle(.bordered).controlSize(.mini)
            .help("Leave a handoff and start this session clean:\n" + session.driftText)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var carry: some View {
        let targets = board.carryTargets(for: session)
        if !targets.isEmpty {
            HStack(spacing: 6) {
                ForEach(targets) { a in
                    Button("Carry to \(a.profile)") {
                        carriedId = session.id
                        Corgi.shared.runInBackground(["agent", "carry", session.id, "--profile", a.profile])
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .help("Continue this conversation under \(a.profile) (\(a.limits?.fiveHour.percent ?? 0)% of its 5h window used)")
                }
            }
            .padding(.horizontal, 4)
        }
        if carriedId == session.id, let notice = board.notice, notice.contains("lists no accounts"),
           let at = board.noticeAt, now.timeIntervalSince(at) < 120 {
            Text(notice).font(.system(size: 9)).foregroundStyle(.orange).padding(.horizontal, 4)
        }
    }

    @ViewBuilder private var menu: some View {
        // Escape, as you would press it: the turn stops, the session waits.
        if session.status == .working {
            Button("Interrupt") { Corgi.shared.runInBackground(["agent", "interrupt", session.id]) }
            Divider()
        }
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
        Button("Compact context") { talk.sendText(session, "/compact", enter: true) }
        Button("Fresh from a handoff") { Corgi.shared.runInBackground(["agent", "carry", session.id, "--fresh"]) }
            .disabled(session.status == .gone)
        if let pr = session.pullRequest {
            Button("Open pull request") { NSWorkspace.shared.open(pr) }
        }
        if settings.approveFromBar, session.answerable != nil {
            Divider()
            Button("Allow always") { talk.answer(session, .always) }
            Button("Deny") { talk.answer(session, .deny) }
        }
        Divider()
        Button(Notifier.shared.muted.contains(session.id) ? "Unmute session" : "Mute session") {
            if Notifier.shared.muted.contains(session.id) { Notifier.shared.muted.remove(session.id) } else { Notifier.shared.muted.insert(session.id) }
        }
        if let key = session.workspaceKey {
            let name = (key as NSString).lastPathComponent
            Button(Notifier.shared.mutedWorkspaces.contains(key) ? "Unmute workspace \(name)" : "Mute workspace \(name)") {
                if Notifier.shared.mutedWorkspaces.contains(key) { Notifier.shared.mutedWorkspaces.remove(key) } else { Notifier.shared.mutedWorkspaces.insert(key) }
            }
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

    private var color: Color { Palette.status(session.status) }
}

struct Chip: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 9, weight: .bold)).lineLimit(1).padding(.horizontal, 3).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary, lineWidth: 1))
    }
}

/// Allow and Deny for the permission prompt a row is waiting on.
struct AnswerButtons: View {
    var session: Session
    var pending: Pending
    @ObservedObject var talk: Talk

    var body: some View {
        HStack(spacing: 4) {
            Button("Allow") { talk.answer(session, .allow) }
                .buttonStyle(.bordered).controlSize(.mini).tint(Palette.green)
            Button("Deny") { talk.answer(session, .deny) }
                .buttonStyle(.bordered).controlSize(.mini)
        }
        .help("Answer the \(pending.text) prompt; right-click the row for Allow always")
        .padding(.trailing, 4)
    }
}

/// Two points under a row: how full the session's context window is.
struct ContextBar: View {
    var percent: Int

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.06))
                Rectangle().fill(Palette.context(percent)).frame(width: g.size.width * CGFloat(percent) / 100)
            }
        }
        .frame(height: 2)
        .help("Context \(percent)% full")
    }
}

/// One block per Claude account: live session count, tokens today and this
/// week, the two /usage bars, the last five hours of the 5-hour window and
/// where it is heading.
struct AccountsView: View {
    @ObservedObject var watcher: BoardWatcher
    @State private var samples: [String: [UsageSample]] = [:]

    var body: some View {
        let accounts = watcher.status.accounts(board: watcher.board)
        if !accounts.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Accounts").font(Palette.sectionTitle).foregroundStyle(.secondary).padding(.horizontal, 4)
                ForEach(accounts) { a in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if !a.chip.isEmpty { Chip(a.chip) }
                            Text(a.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            if a.sessions > 0 {
                                Text("\(a.sessions) live").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if let until = a.limitedUntil {
                                Text(until).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.blue)
                            } else if a.tokensToday > 0 || a.tokensWeek > 0 {
                                Text("\(formatTokens(a.tokensToday)) today · \(formatTokens(a.tokensWeek)) week").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        if let l = a.limits {
                            HStack(spacing: 8) {
                                LimitBar(label: "5h", window: l.fiveHour)
                                LimitBar(label: "week", window: l.sevenDay)
                            }
                            HStack(spacing: 6) {
                                if let points = samples[a.profile], points.count > 1 {
                                    Sparkline(values: points.map(\.fiveHour)).frame(width: 60, height: 12)
                                }
                                if a.limitedUntil != nil || l.fiveHour.percent >= 100 {
                                    Text(l.fiveHour.resetsAt.map { "limit lifts \(ForecastLine.clock($0))" } ?? "limit reached")
                                        .font(.system(size: 9)).foregroundStyle(Palette.blue).lineLimit(1)
                                } else if let line = ForecastLine.make(a.forecast?.fiveHour, resetsAt: l.fiveHour.resetsAt) {
                                    Text(line.text).font(.system(size: 9)).foregroundStyle(line.danger ? Palette.red : Color.secondary).lineLimit(1)
                                }
                            }
                        } else {
                            Text("no usage snapshot — run /usage once under this account").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 10)
            .onAppear(perform: loadSamples)
            .onChange(of: samplesKey(accounts)) { _ in loadSamples() }
        }
    }

    /// What the samples depend on: the agent dir and the accounts listed.
    /// Both settle once after launch and then stay put.
    private func samplesKey(_ accounts: [AgentStatus.Account]) -> String {
        (watcher.board.agentDir ?? "") + "|" + accounts.map(\.profile).joined(separator: ",")
    }

    /// The samples files are read when the dropdown opens (and when the key
    /// above settles: the content is built before that), off the main thread.
    /// The profiles are read here, not captured: a closure made by an older
    /// body would carry an older list.
    private func loadSamples() {
        guard let dir = watcher.board.agentDir else { return }
        let profiles = watcher.status.accounts(board: watcher.board).map(\.profile)
        DispatchQueue.global(qos: .utility).async {
            var out: [String: [UsageSample]] = [:]
            for p in profiles { out[p] = UsageSamples.load(agentDir: dir, profile: p) }
            DispatchQueue.main.async { samples = out }
        }
    }
}

/// The last five hours of one limit, as a line.
struct Sparkline: View {
    var values: [Int]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            var path = Path()
            let stepX = size.width / CGFloat(values.count - 1)
            let span = size.height - 2
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: CGFloat(i) * stepX, y: 1 + span - span * CGFloat(min(100, max(0, v))) / 100)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            ctx.stroke(path, with: .color(Palette.context(values.last ?? 0)), lineWidth: 1.2)
        }
        .help("5-hour window over the last five hours")
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
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(watcher.status.workspaces) { w in
                        RemoteRow(workspace: w, watcher: watcher)
                    }
                    if let url = watcher.status.dashboardUrl, let u = URL(string: url) {
                        Button { NSWorkspace.shared.open(u) } label: {
                            Label("Open dashboard", systemImage: "iphone").font(.system(size: 11))
                        }.buttonStyle(.plain).foregroundStyle(Palette.blue).padding(.horizontal, 4).padding(.top, 2)
                    }
                }
                .padding(.top, 4)
            } label: {
                let live = watcher.status.workspaces.filter { $0.running && !($0.deviceOnly ?? false) }.count
                let devices = watcher.status.workspaces.filter { $0.running && ($0.deviceOnly ?? false) }.count
                Text(remoteSummary(live: live, devices: devices, total: watcher.status.workspaces.count))
                    .font(Palette.sectionTitle).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
        }
    }
}

/// One workspace: dot, name, its state, Open. Stop, Start and Pause show
/// while the pointer is over the row.
struct RemoteRow: View {
    var workspace: AgentStatus.Workspace
    @ObservedObject var watcher: BoardWatcher
    @State private var hover = false

    var body: some View {
        let w = workspace
        let live = w.running && !(w.deviceOnly ?? false)
        HStack(spacing: 6) {
            Circle().fill(live ? Palette.green : Color.secondary).frame(width: 6, height: 6)
            OpenRow(link: w.sessionUrl.flatMap(URL.init(string:)), help: "Open the session in the Claude app") {
                Text(w.workspaceId).font(.system(size: 11)).lineLimit(1)
            }
            Text(live ? "session" : w.running ? "device" : "off").font(.system(size: 9)).foregroundStyle(.tertiary)
                .help(live ? "A session is open in the Claude app" : w.running ? "Reachable from the phone and the Claude app; no session open, nothing spent" : "Not supervised right now")
            Spacer()
            if hover {
                if live {
                    control("Stop") { session("stop") }
                        .help("End the session; the device stays online")
                } else if !w.running {
                    control("Start") { session("start") }
                }
                if w.running {
                    control("Pause") {
                        Corgi.shared.runInBackground(["agent", "workspaces", "pause", w.workspaceId]) { _ in
                            self.watcher.refreshStatus(force: true)
                        }
                    }
                    .help("Stop supervising this workspace: no device at login, no restarts. `corgi agent workspaces resume` brings it back")
                }
            }
            if let url = w.sessionUrl, let u = URL(string: url) {
                Button("Open") { NSWorkspace.shared.open(u) }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.blue)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private func control(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.secondary)
    }

    private func session(_ verb: String) {
        Corgi.shared.runInBackground(["agent", "session", verb, workspace.workspaceId]) { _ in
            self.watcher.refreshStatus(force: true)
        }
    }
}

/// A row's text as the link it stands for: a plain click opens it in the
/// browser, the pointer says so, nothing else about the row changes. With
/// no link it is just the text.
struct OpenRow<Content: View>: View {
    var link: URL?
    var help: String
    @ViewBuilder var content: () -> Content
    @State private var hover = false

    var body: some View {
        if let link {
            Button { NSWorkspace.shared.open(link) } label: {
                content()
                    .contentShape(Rectangle())
                    .underline(hover, color: Palette.blue)
            }
            .buttonStyle(.plain)
            .onHover { over in
                hover = over
                if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help(help)
        } else {
            content()
        }
    }
}

func remoteSummary(live: Int, devices: Int, total: Int) -> String {
    var parts: [String] = []
    if live > 0 { parts.append("\(live) session\(live == 1 ? "" : "s")") }
    if devices > 0 { parts.append("\(devices) device\(devices == 1 ? "" : "s")") }
    if parts.isEmpty { parts.append("\(total) off") }
    return "Remote · " + parts.joined(separator: " · ")
}

/// One rolling limit as /usage shows it: a thin bar, the percent, the reset time.
struct LimitBar: View {
    var label: String
    var window: UsageLimits.Window

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(color).frame(width: max(2, g.size.width * CGFloat(min(100, max(0, window.percent))) / 100))
                }
            }
            .frame(height: 4)
            Text("\(window.percent)%").font(.system(size: 9, weight: .semibold)).foregroundStyle(color).frame(width: 30, alignment: .trailing)
            if let at = window.resetsAt {
                Text(LimitBar.resetText(at)).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private var color: Color {
        switch window.percent {
        case 90...: return Palette.red
        case 70..<90: return Palette.amber
        default: return Palette.green
        }
    }

    /// "5:10pm" for today, "Tue 9am" further out.
    static func resetText(_ at: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.isDateInToday(at) ? "h:mma" : "EEE ha"
        return f.string(from: at).lowercased()
    }
}

/// What `corgi agent watch` is doing: which workspaces it watches, whether
/// each only reports or works on what arrives, and what the unattended runs
/// opened. A fix runs for minutes and its notification is gone in a second,
/// so this is where you find out.
struct WatchView: View {
    @ObservedObject var watcher: BoardWatcher
    @ObservedObject private var settings = Preferences.shared
    @State private var now = Date()
    private let ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let watch = watcher.watch
        let live: [WatchStatus.Fix] = watch.running
        let done: [WatchStatus.Fix] = watch.recent(now: now)
        if watch.watched {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Watching").font(Palette.sectionTitle).foregroundStyle(.secondary)
                    Spacer()
                    Text(watch.summary(now: now)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 4)

                ForEach(watch.workspaces) { ws in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ws.isAuto ? Palette.green : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(ws.workspace).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(ws.isAuto ? "auto" : "notify")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ws.isAuto ? Palette.green : .secondary)
                        if let quiet = ws.quiet, !quiet.isEmpty {
                            Text("quiet \(quiet)").font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        if let off = ws.daysOffLine {
                            Text(off).font(.system(size: 9)).foregroundStyle(ws.asleep ? Palette.amber : Color.secondary.opacity(0.6)).lineLimit(1)
                                .help("The watch sleeps through these days: no polling, no fix, nothing rings until the next working day")
                        }
                        Spacer()
                        Button(ws.isAuto ? "Stop" : "Auto") {
                            watcher.setAuto(!ws.isAuto, workspace: ws.workspace)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ws.isAuto ? Palette.red : Palette.blue)
                        .help(ws.isAuto
                              ? "Stop working on what arrives; keep reporting it"
                              : "Work on what arrives: draft PRs only, capped, never twice on the same thing")
                    }
                    .padding(.horizontal, 4)
                }

                // The inbox: what arrived and is still waiting on a person.
                // The phone has had this since the tabs; the menu bar is
                // where the day is actually spent.
                if !watch.events.isEmpty {
                    Divider().padding(.vertical, 2)
                    ForEach(watch.events.prefix(5)) { item in
                        HStack(spacing: 6) {
                            Circle().fill(Palette.blue.opacity(0.7)).frame(width: 7, height: 7)
                            OpenRow(link: item.link, help: "Open \(item.ref.isEmpty ? item.key : item.ref) on the tracker") {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(item.ref.isEmpty ? item.key : item.ref)
                                        .font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    Text(item.kindLabel)
                                        .font(.system(size: 9)).foregroundStyle(.secondary)
                                    if let state = item.state, !state.isEmpty {
                                        Text(state).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                if !item.title.isEmpty {
                                    Text(item.title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if let why = item.blocked, !why.isEmpty {
                                    Text("blocked: \(why)").font(.system(size: 10)).foregroundStyle(Palette.red).lineLimit(1)
                                }
                                if let line = item.sessionLine {
                                    Text(line).font(.system(size: 10)).foregroundStyle(Palette.amber).lineLimit(1)
                                }
                            }
                            }
                            Spacer()
                            if item.blocked != nil {
                                Button("Unblock") { watcher.unblock(item) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.blue)
                                    .help("Let unattended runs work this ticket again")
                            }
                            if let link = item.link {
                                Button("Open") { NSWorkspace.shared.open(link) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.blue)
                            }
                            Button { watcher.ignore(item) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Ignore: out of the inbox everywhere, nothing written to the tracker")
                        }
                        .padding(.horizontal, 4)
                        .contextMenu {
                            if let link = item.link { Button("Open") { NSWorkspace.shared.open(link) } }
                            if item.isIssue {
                                Button("Work on it") { watcher.workOn(item, isolate: settings.isolate) }
                                Button("Work on it in a worktree of its own") { watcher.workOn(item, isolate: true) }
                            }
                            if item.blocked != nil { Button("Unblock") { watcher.unblock(item) } }
                            if let pr = item.pullRequest {
                                Divider()
                                Button("Open pull request") { NSWorkspace.shared.open(pr) }
                                Button("Ready for review") { watcher.pullRequest("ready", key: item.key) }
                                Button("Merge") { watcher.pullRequest("merge", key: item.key) }
                                Button("Close pull request") { watcher.pullRequest("close", key: item.key) }
                                Divider()
                            }
                            Button("Ignore") { watcher.ignore(item) }
                        }
                    }
                    if watch.events.count > 5 {
                        Text("and \(watch.events.count - 5) more")
                            .font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                }

                // A run's row is the ticket: click it for the tracker, or
                // the pull request it opened when it opened one.
                ForEach(live) { fix in
                    HStack(spacing: 6) {
                        Circle().fill(Palette.amber).frame(width: 7, height: 7)
                        OpenRow(link: fix.link, help: "Open \(fix.ref) on the tracker") {
                            Text(fix.ref).font(.system(size: 11)).lineLimit(1)
                        }
                        Spacer()
                        Text(elapsedSince(fix.startedAt, now: now)).font(.system(size: 10)).foregroundStyle(Palette.amber)
                    }
                    .padding(.horizontal, 4)
                }

                ForEach(done) { fix in
                    HStack(spacing: 6) {
                        OpenRow(link: fix.destination, help: fix.pullRequest != nil ? "Open the pull request" : "Open \(fix.ref) on the tracker") {
                            HStack(spacing: 6) {
                                Text(fix.ref).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                Text(fix.outcome).font(.system(size: 10)).foregroundStyle(fix.error == nil ? Color.secondary : Palette.red).lineLimit(1)
                            }
                        }
                        Spacer()
                        if let pr = fix.pullRequest {
                            Button("PR") { NSWorkspace.shared.open(pr) }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.blue)
                                .help("Open the pull request")
                        }
                        if let link = fix.link, fix.pullRequest != nil {
                            Button("Ticket") { NSWorkspace.shared.open(link) }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.blue)
                        }
                    }
                    .padding(.horizontal, 4)
                    .contextMenu {
                        if let link = fix.link { Button("Open ticket") { NSWorkspace.shared.open(link) } }
                        if let pr = fix.pullRequest {
                            Button("Open pull request") { NSWorkspace.shared.open(pr) }
                            if let key = fix.key {
                                Divider()
                                Button("Ready for review") { watcher.pullRequest("ready", key: key) }
                                Button("Merge") { watcher.pullRequest("merge", key: key) }
                                Button("Close pull request") { watcher.pullRequest("close", key: key) }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .onReceive(ticker) { now = $0 }
        }
    }
}

/// "6m" / "1h 20m" since a fix started; empty when there is no start time.
func elapsedSince(_ start: Date?, now: Date) -> String {
    guard let start else { return "" }
    let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
    if minutes < 60 { return "\(minutes)m" }
    let rest = minutes % 60
    return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
}
