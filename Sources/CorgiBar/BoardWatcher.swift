import Foundation
import Combine

/// Reads sessions.json whenever corgi rewrites it. corgi writes atomically
/// (temp file + rename), so the parent directory is what changes; a 5 s
/// poll covers a missed event and a daemon that went away.
@MainActor
final class BoardWatcher: ObservableObject {
    @Published private(set) var board: Board = .empty
    @Published private(set) var corgiVersion: String?
    @Published private(set) var corgiPresent = true
    @Published private(set) var status: AgentStatus = .empty

    private var path: String?
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var timer: Timer?
    private var lastUpdatedAt: Date?

    func start() {
        refreshFromCLI()
        refreshStatus()
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
            DispatchQueue.main.async { self.status = status }
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
        self.board = board
        Notifier.shared.boardMoved(from: previous, to: board)
    }
}
