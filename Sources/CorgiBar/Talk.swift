import Foundation
import AppKit

/// Dictate into the session in front: focus it through corgi, wait for the
/// board to say the focus landed, press the dictation chord. Press again to
/// send (tap mode). Same rules as the Stream Deck plugin's talk key.
@MainActor
final class Talk: ObservableObject {
    enum State { case idle, recording }
    @Published private(set) var state: State = .idle
    @Published var lastError: String?

    private let watcher: BoardWatcher
    private var recording: (sessionId: String, since: Date)?
    private var lastClicked: String?
    private var capTimer: Timer?

    init(watcher: BoardWatcher) {
        self.watcher = watcher
    }

    func noteClick(_ sessionId: String) {
        lastClicked = sessionId
    }

    /// The session a prompt or a Talk press goes to right now.
    func target() -> Session? {
        Talk.pick(watcher.board, lastClicked: lastClicked)
    }

    /// The session to dictate into: the one in the window in front, else the
    /// row last clicked, else the only one that needs you, else the latest.
    nonisolated static func pick(_ board: Board, lastClicked: String?) -> Session? {
        let live = board.sessions.filter { $0.status != .gone }
        if let front = live.first(where: { $0.id == board.frontSession }) { return front }
        if let last = live.first(where: { $0.id == lastClicked }) { return last }
        let needing = live.filter { $0.status == .needsInput }
        if needing.count == 1 { return needing[0] }
        return live.max { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }
    }

    nonisolated static func chord(for session: Session, settings: Preferences) -> String {
        session.isPanel ? settings.panelChord : settings.terminalChord
    }

    func press() {
        lastError = nil
        // The click came from our own popover, which is now the key window;
        // the chord must land in the session's window, so corgi focuses it
        // first, every time.
        NSApp.hide(nil)
        if let recording {
            let id = recording.sessionId
            guard let session = watcher.board.session(id) else {
                stopRecording()
                return
            }
            focusThen(session) { [weak self] in
                guard let self else { return }
                // Second press: tap mode sends in the terminal. The panel only
                // stops recording, so a send key follows once the transcript lands.
                let sent = self.send(Talk.chord(for: session, settings: .shared))
                self.stopRecording()
                let prefs = Preferences.shared
                if sent, session.isPanel, !prefs.panelSendKey.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + prefs.panelSendDelay) { [weak self] in
                        self?.send(prefs.panelSendKey)
                    }
                }
            }
            return
        }
        guard watcher.board.daemonRunning else {
            lastError = "corgi agent is not running"
            return
        }
        guard let session = Talk.pick(watcher.board, lastClicked: lastClicked) else {
            lastError = "no Claude Code session to dictate into"
            return
        }
        focusThen(session) { [weak self] in
            guard let self else { return }
            if self.send(Talk.chord(for: session, settings: .shared)) {
                self.startRecording(session.id)
            }
        }
    }

    enum Answer: String {
        case allow, always, deny

        /// What a hand would press in the prompt when corgi cannot type it.
        var keys: [String] {
            switch self {
            case .allow: return ["return"]
            case .always: return ["2", "return"]
            case .deny: return ["escape"]
            }
        }
    }

    /// Answer the permission prompt through corgi; a panel session takes
    /// only keystrokes, so the board's "keyboard" failure is the cue to
    /// focus it and press the keys ourselves.
    func answer(_ session: Session, _ answer: Answer) {
        lastError = nil
        NSApp.hide(nil)
        runThenType(["agent", "answer", session.id, answer.rawValue], session: session) { [weak self] in
            self?.press(answer.keys)
        }
    }

    /// Type a prompt into the session through corgi, falling back to
    /// keystrokes the same way.
    func sendText(_ session: Session, _ text: String, enter: Bool) {
        lastError = nil
        NSApp.hide(nil)
        var args = ["agent", "send", session.id]
        if enter { args.append("--enter") }
        args.append(text)
        runThenType(args, session: session) { [weak self] in
            guard let self else { return }
            do {
                try Chord.type(text)
            } catch Chord.SendError.notTrusted {
                self.lastError = "corgi-bar needs Accessibility to type into the panel"
                Talk.askForAccessibility()
                return
            } catch {
                self.lastError = "cannot type into the panel"
                return
            }
            if enter { self.press(["return"]) }
        }
    }

    private func press(_ keys: [String]) {
        for (i, key) in keys.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(i)) { [weak self] in
                self?.send(key)
            }
        }
    }

    /// Run a corgi command that focuses and types; when the board (or the
    /// command) says the host takes text only from the keyboard, focus the
    /// session ourselves and type. Any other failure is shown as is.
    private func runThenType(_ args: [String], session: Session, type: @escaping () -> Void) {
        let pressedAt = Date()
        Corgi.shared.runInBackground(args) { [weak self] r in
            guard let self else { return }
            let stderr = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !r.ok, !Talk.needsKeyboard(stderr) {
                self.lastError = stderr.isEmpty ? "corgi \(args.joined(separator: " ")) failed" : stderr
                return
            }
            self.waitForFocus(session.id, since: pressedAt, deadline: Date().addingTimeInterval(1.5)) { landed in
                if r.ok, landed { return }
                let error = self.watcher.board.session(session.id)?.focusError ?? ""
                if Talk.needsKeyboard(error) || Talk.needsKeyboard(stderr) {
                    self.focusThen(session, then: type)
                } else if !error.isEmpty || !stderr.isEmpty {
                    self.lastError = error.isEmpty ? stderr : error
                }
            }
        }
    }

    nonisolated static func needsKeyboard(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("keyboard")
    }

    /// corgi brings the session's window and tab forward; the board says
    /// when it landed (or 1.5 s pass and the window is assumed up).
    private func focusThen(_ session: Session, then: @escaping () -> Void) {
        let pressedAt = Date()
        Corgi.shared.runInBackground(["agent", "focus", session.id]) { [weak self] r in
            guard let self else { return }
            guard r.ok else {
                self.lastError = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
            self.waitForFocus(session.id, since: pressedAt, deadline: Date().addingTimeInterval(1.5)) { landed in
                guard landed else {
                    self.lastError = self.watcher.board.session(session.id)?.focusError ?? "focus did not land"
                    return
                }
                // A beat for the window server to move key focus before the keystroke.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: then)
            }
        }
    }

    private func waitForFocus(_ id: String, since: Date, deadline: Date, done: @escaping (Bool) -> Void) {
        if let s = watcher.board.session(id), let at = s.focusAt, at >= since.addingTimeInterval(-1) {
            done(s.focusError == nil)
            return
        }
        if Date() >= deadline {
            done(true) // no word from corgi: assume the window is up
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForFocus(id, since: since, deadline: deadline, done: done)
        }
    }

    @discardableResult
    private func send(_ chord: String) -> Bool {
        do {
            try Chord.send(chord)
            return true
        } catch Chord.SendError.notTrusted {
            lastError = "corgi-bar needs Accessibility to press \(chord)"
            Talk.askForAccessibility()
        } catch {
            lastError = "cannot send \(chord)"
        }
        return false
    }

    static func askForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Allow corgi-bar to press keys"
        alert.informativeText = "System Settings → Privacy & Security → Accessibility → add corgi-bar. Talk presses Claude Code's dictation chord in the window in front."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startRecording(_ id: String) {
        recording = (id, Date())
        state = .recording
        capTimer?.invalidate()
        capTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stopRecording() }
        }
    }

    private func stopRecording() {
        capTimer?.invalidate()
        recording = nil
        state = .idle
    }

    /// A recording session that started working was sent.
    func boardMoved(_ board: Board) {
        guard let recording else { return }
        let s = board.session(recording.sessionId)
        if s == nil || (s?.status == .working && (s?.statusSince ?? .distantPast) > recording.since) {
            stopRecording()
        }
    }
}
