import SwiftUI
import AppKit
import Combine

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

    /// Grey while there is room, orange past 60, red past 85.
    static func context(_ percent: Int) -> Color {
        switch percent {
        case 86...: return red
        case 61...85: return amber
        default: return Color.secondary.opacity(0.6)
        }
    }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(promptPlaceholder, text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .focused($promptFocused)
                    .onSubmit(sendPrompt)
                    .disabled(!watcher.board.daemonRunning)
                Button {
                    Corgi.shared.runInBackground(["agent", "new"])
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!watcher.board.daemonRunning || watcher.board.windows.isEmpty)
                .help(watcher.board.windows.isEmpty ? "Open a folder in VS Code with the corgi extension" : "New session: a claude terminal in the window in front")
            }
            Text("Return sends · ⌥Return types without Enter · \(settings.promptHotKey)").font(.system(size: 9)).foregroundStyle(.tertiary)

            Divider()
            if watcher.board.sessions.isEmpty {
                Text(watcher.board.daemonRunning ? "No Claude Code session running" : "corgi agent is not running")
                    .foregroundStyle(.secondary).padding(.vertical, 4)
            }
            ForEach(watcher.board.groups) { group in
                GroupHeader(group: group)
                ForEach(group.sessions) { session in
                    SessionRow(session: session, board: watcher.board, now: now, talk: talk, carriedId: $carriedId,
                               showProfile: group.commonProfileChip == nil)
                }
            }
            AccountsView(watcher: watcher)
            RemoteView(watcher: watcher)
            Divider()
            HStack {
                Button {
                    talk.press()
                } label: {
                    Label(talk.state == .recording ? "REC · press to send" : "Talk", systemImage: talk.state == .recording ? "record.circle.fill" : "mic")
                        .foregroundStyle(talk.state == .recording ? Palette.red : Color.primary)
                }
                .keyboardShortcut("t", modifiers: [.command])
                Spacer()
                Text(settings.hotKey).font(.caption).foregroundStyle(.secondary)
            }
            if let err = talk.lastError {
                Text(err).font(.caption).foregroundStyle(Palette.red)
            }
            if let notice = watcher.board.notice, let at = watcher.board.noticeAt, now.timeIntervalSince(at) < 60 {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                if let v = updates.available {
                    Button("\(v) available") { NSWorkspace.shared.open(UpdateCheck.releasesURL) }
                        .buttonStyle(.plain).foregroundStyle(Palette.blue).font(.caption)
                        .help("brew upgrade --cask corgi-bar, or download from the release page")
                }
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
            Text(group.label).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            if let chip = group.commonProfileChip {
                Chip(chip)
            }
            Spacer()
            if group.sessions.count > 1 {
                Text("\(group.sessions.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
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
                    if session.title != nil, session.shortName != session.label {
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

    /// The note when there is one, else what the session is doing.
    private var secondary: String? {
        if let note = session.note, !note.isEmpty { return note }
        if session.isStuck {
            return "no activity \(elapsedText(since: session.lastActivity, now: now))"
        }
        if let pending = session.answerable { return "permission: \(pending.text)" }
        if let d = session.detail, !d.isEmpty { return d }
        return nil
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

/// Two pixels under a row: how full the session's context window is.
struct ContextBar: View {
    var percent: Int

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.08))
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
                                if let line = ForecastLine.make(a.forecast?.fiveHour, resetsAt: l.fiveHour.resetsAt) {
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
                ForEach(watcher.status.workspaces) { w in
                    HStack(spacing: 6) {
                        Circle().fill(w.running ? Palette.green : Color.secondary).frame(width: 6, height: 6)
                        Text(w.workspaceId).font(.system(size: 11))
                        Spacer()
                        if let url = w.sessionUrl, let u = URL(string: url) {
                            Button("Open") { NSWorkspace.shared.open(u) }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.blue)
                        }
                        Button(w.running ? "Stop" : "Start") {
                            Corgi.shared.runInBackground(["agent", "session", w.running ? "stop" : "start", w.workspaceId]) { _ in
                                self.watcher.refreshStatus(force: true)
                            }
                        }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.blue)
                    }
                    .padding(.horizontal, 4)
                }
                if let url = watcher.status.dashboardUrl, let u = URL(string: url) {
                    Button { NSWorkspace.shared.open(u) } label: {
                        Label("Open dashboard", systemImage: "iphone").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(Palette.blue).padding(.horizontal, 4)
                }
            } label: {
                let online = watcher.status.workspaces.filter { $0.running }.count
                Text("Remote · \(online) of \(watcher.status.workspaces.count) online").font(.system(size: 11, weight: .semibold))
            }
        }
    }
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
