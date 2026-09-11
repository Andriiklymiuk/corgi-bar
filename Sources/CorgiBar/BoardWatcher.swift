import Foundation
import Combine

/// Reads sessions.json whenever corgi rewrites it. corgi writes atomically
/// (temp file + rename), so the parent directory is what changes; a 5 s
/// poll covers a missed event and a daemon that went away.
@MainActor
final class BoardWatcher: ObservableObject {
    static let shared = BoardWatcher()

    /// What the menu shows: the board, status and watch with the hidden
    /// workspaces taken out. The raw copies stay for the picker in Settings.
    @Published private(set) var board: Board = .empty
    @Published private(set) var corgiVersion: String?
    @Published private(set) var corgiPresent = true
    @Published private(set) var status: AgentStatus = .empty
    @Published private(set) var watch: WatchStatus = .empty
    private var rawBoard: Board = .empty
    private var rawStatus: AgentStatus = .empty
    private var rawWatch: WatchStatus = .empty
    private var prefs: AnyCancellable?

    init() {
        prefs = Preferences.shared.$hiddenWorkspaces.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.refilter() }
        }
    }

    /// Every workspace the bar has heard of, for the Settings picker.
    var knownWorkspaces: [String] {
        var names = Set<String>()
        for s in rawBoard.sessions { names.insert(s.label) }
        for w in rawWatch.workspaces { names.insert(w.workspace) }
        for w in rawStatus.workspaces { names.insert(w.workspaceId) }
        return names.sorted { $0.lowercased() < $1.lowercased() }
    }

    private func refilter() {
        let hide = Preferences.shared.isHidden
        board = rawBoard.hiding(hide)
        var s = rawStatus
        s.workspaces = s.workspaces.filter { !hide($0.workspaceId) }
        status = s
        var w = rawWatch
        w.workspaces = w.workspaces.filter { !hide($0.workspace) }
        w.fixes = w.fixes.filter { !hide($0.workspace) }
        w.events = w.events.filter { !hide($0.workspace) }
        watch = w
    }

    /// The reload button: the daemon rescans and polls every tracker now, and
    /// this menu re-reads once it has had a moment to publish — the phone and
    /// the page pick up the same picture on their own.
    func reloadEverything() {
        Corgi.shared.runInBackground(["agent", "refresh"]) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.refreshFromCLI()
                self?.refreshStatus(force: true)
                self?.refreshWatch()
            }
        }
    }

    private var path: String?
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var timer: Timer?
    private var lastUpdatedAt: Date?

    func start() {
        refreshFromCLI()
        refreshStatus()
        refreshWatch()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// `corgi agent status --json` scans transcripts for token counts, so it
    /// runs every five minutes, not on every board change. Limits and
    /// forecasts come from the board itself.
    private var statusFetchedAt: Date = .distantPast
    func refreshStatus(force: Bool = false) {
        guard force || Date().timeIntervalSince(statusFetchedAt) > 300 else { return }
        statusFetchedAt = Date()
        DispatchQueue.global(qos: .utility).async {
            let r = Corgi.shared.run(["agent", "status", "--json"])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { d in
                let raw = try d.singleValueContainer().decode(String.self)
                guard let date = Board.parseDate(raw) else { throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: raw) }
                return date
            }
            guard r.ok, let data = r.stdout.data(using: .utf8), let status = try? decoder.decode(AgentStatus.self, from: data) else { return }
            DispatchQueue.main.async {
                self.rawStatus = status
                self.refilter()
            }
        }
    }

    /// `corgi agent watch --json` is cheap — it reads two files — so it can
    /// follow the 5 s tick and show a running fix while it is still running.
    func refreshWatch() {
        DispatchQueue.global(qos: .utility).async {
            let r = Corgi.shared.run(["agent", "watch", "--json"])
            guard r.ok, let data = r.stdout.data(using: .utf8),
                  let watch = try? WatchStatus.decode(data) else { return }
            DispatchQueue.main.async {
                self.rawWatch = watch
                self.refilter()
            }
        }
    }

    /// Take one inbox row out for good. corgi keeps the decision in its own
    /// file, so the phone and the editor drop the row on their next read too.
    /// The row leaves the menu at once rather than after the next tick.
    func ignore(_ item: WatchStatus.Item) {
        watch.events.removeAll { $0.key == item.key }
        Corgi.shared.runInBackground(["agent", "watch", "ignore", item.key]) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshWatch() }
        }
    }

    /// Let unattended runs work a blocked ticket again, then re-read.
    func unblock(_ item: WatchStatus.Item) {
        var args = ["agent", "watch", "unblock", item.ref.isEmpty ? item.key : item.ref]
        if !item.workspace.isEmpty { args += ["--workspace", item.workspace] }
        Corgi.shared.runInBackground(args) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshWatch() }
        }
    }

    /// Turn the unattended mode on or off for one workspace, then re-read.
    /// The daemon has to be restarted for it to take, which corgi says too.
    func setAuto(_ on: Bool, workspace id: String) {
        var args = ["agent", "watch", "enable", "--workspace", id]
        args += on ? ["--auto"] : ["--action", "notify"]
        Corgi.shared.runInBackground(args) { [weak self] _ in
            // The daemon reads the rules at start, so a change needs a restart.
            Corgi.shared.runInBackground(["agent", "restart"]) { _ in
                DispatchQueue.main.async { self?.refreshWatch() }
            }
        }
    }

    func stopWatching(workspace id: String) {
        Corgi.shared.runInBackground(["agent", "watch", "disable", "--workspace", id]) { [weak self] _ in
            Corgi.shared.runInBackground(["agent", "restart"]) { _ in
                DispatchQueue.main.async { self?.refreshWatch() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        source?.cancel()
    }

    /// Ask corgi itself: where the file is, whether the daemon runs.
    func refreshFromCLI() {
        DispatchQueue.global(qos: .utility).async {
            let corgi = Corgi.shared
            let present = corgi.path() != nil
            let version = present ? corgi.version() : nil
            let board = present ? corgi.board() : nil
            DispatchQueue.main.async {
                self.corgiPresent = present
                self.corgiVersion = version
                if let board {
                    self.apply(board)
                    if self.path != board.path, let p = board.path {
                        self.path = p
                        self.watch(p)
                    }
                } else {
                    self.apply(.empty)
                }
            }
        }
    }

    private func tick() {
        guard let path else {
            refreshFromCLI()
            return
        }
        readFile(path)
        refreshStatus()
        refreshWatch()
    }

    private func watch(_ path: String) {
        source?.cancel()
        let dir = (path as NSString).deletingLastPathComponent
        fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            // The directory carries every corgi file (events, status, commands);
            // coalesce the burst and let readFile skip an unchanged sessions.json.
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.readFile(path) }
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        source = src
    }

    private var pending: DispatchWorkItem?
    private var lastModified: Date?

    private func readFile(_ path: String) {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
        if let modified, let last = lastModified, modified == last, board.daemonRunning {
            staleTicks += 1
            if staleTicks >= 12 {
                staleTicks = 0
                refreshFromCLI()
            }
            return
        }
        lastModified = modified
        guard let data = FileManager.default.contents(atPath: path), let board = try? Board.decode(data) else { return }
        // sessions.json itself has no daemonRunning; keep what the CLI said unless the file stopped moving.
        var merged = board
        merged.daemonRunning = self.board.daemonRunning || board.daemonRunning
        merged.path = path
        staleTicks = 0
        apply(merged)
    }

    private var staleTicks = 0

    private func apply(_ board: Board) {
        let previous = self.board
        lastUpdatedAt = board.updatedAt
        rawBoard = board
        self.board = board.hiding(Preferences.shared.isHidden)
        // The notifier sees the filtered board: a hidden workspace never rings.
        Notifier.shared.boardMoved(from: previous, to: self.board)
    }
}
