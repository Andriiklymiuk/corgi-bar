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

    private var path: String?
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var timer: Timer?
    private var lastUpdatedAt: Date?

    func start() {
        refreshFromCLI()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
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
    }

    private func watch(_ path: String) {
        source?.cancel()
        let dir = (path as NSString).deletingLastPathComponent
        fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.readFile(path)
        }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        source = src
    }

    private func readFile(_ path: String) {
        guard let data = FileManager.default.contents(atPath: path), let board = try? Board.decode(data) else { return }
        // sessions.json itself has no daemonRunning; keep what the CLI said unless the file stopped moving.
        var merged = board
        merged.daemonRunning = self.board.daemonRunning || board.daemonRunning
        merged.path = path
        if let at = board.updatedAt, let last = lastUpdatedAt, at <= last, self.board.daemonRunning {
            // Unchanged. Every 12th tick (a minute) re-check the daemon through the CLI.
            staleTicks += 1
            if staleTicks >= 12 {
                staleTicks = 0
                refreshFromCLI()
            }
            return
        }
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
