import XCTest
@testable import CorgiBar

final class BoardTests: XCTestCase {
    func fixture() throws -> Board {
        let url = Bundle.module.url(forResource: "sessions", withExtension: "json", subdirectory: "Fixtures")!
        return try Board.decode(try Data(contentsOf: url))
    }

    func testDecodesTheFixture() throws {
        let board = try fixture()
        XCTAssertEqual(board.size, 6)
        XCTAssertEqual(board.sessions.count, 7)
        XCTAssertEqual(board.sessions[0].status, .needsInput)
        XCTAssertEqual(board.sessions[0].profileChip, "WO")
        XCTAssertNotNil(board.sessions[0].lastActivity)
        XCTAssertEqual(board.frontSession, board.sessions[0].id)
        XCTAssertEqual(board.mood, .needsInput)
        XCTAssertEqual(board.orderedSessions.count, 7)
    }

    func testUnknownStatusesAndGoZonesDecode() throws {
        let json = #"{"updatedAt":"2026-09-08T08:35:20.577423+03:00","sessions":[{"id":"x","label":"x","status":"something_new","host":{"kind":"terminal"},"statusSince":"2026-09-08T04:31:03.978409455Z"}],"daemonRunning":true}"#
        let board = try Board.decode(json.data(using: .utf8)!)
        XCTAssertEqual(board.sessions[0].status, .unknown)
        XCTAssertNotNil(board.updatedAt)
        XCTAssertEqual(board.mood, .quiet)
    }

    func testPickFollowsTheDeckRules() throws {
        var board = try fixture()
        let web = board.sessions[1]
        XCTAssertEqual(Talk.pick(board, lastClicked: web.id)?.id, board.frontSession)
        board.frontSession = nil
        XCTAssertEqual(Talk.pick(board, lastClicked: web.id)?.id, web.id)
        XCTAssertEqual(Talk.pick(board, lastClicked: "nope")?.id, board.sessions[0].id) // the only needs_input
        board.sessions = []
        XCTAssertNil(Talk.pick(board, lastClicked: nil))
    }

    func testChordsParse() {
        XCTAssertEqual(Chord.parse("ctrl+y"), Chord(keyCode: 16, flags: [.maskControl]))
        XCTAssertEqual(Chord.parse("cmd+d"), Chord(keyCode: 2, flags: [.maskCommand]))
        XCTAssertEqual(Chord.parse("ctrl+alt+space"), Chord(keyCode: 49, flags: [.maskControl, .maskAlternate]))
        XCTAssertNil(Chord.parse("hyper+q"))
        XCTAssertNil(Chord.parse(""))
    }

    func testAccountsGroupUsageByConfigDirAndCarryTheLimit() throws {
        let json = #"{"running":true,"version":"1.21.41","workspaces":[{"workspaceId":"corgi","running":true}],"usage":[{"workspaceId":"corgi","configDir":"","tokensToday":10,"tokensWeek":100},{"workspaceId":"idid","configDir":"","tokensToday":5,"tokensWeek":50},{"workspaceId":"onboarding","configDir":"/Users/me/.claude-skp","tokensToday":7,"tokensWeek":70}],"accounts":[{"profile":"default","limits":{"fetchedAt":"2026-09-08T13:35:22.38+03:00","fiveHour":{"percent":55,"resetsAt":"2026-09-08T14:10:00.244Z"},"sevenDay":{"percent":10,"resetsAt":"2026-09-15T06:00:00.244018Z"}}},{"profile":"skp","configDir":"/Users/me/.claude-skp"}],"dashboardUrl":"https://x.example"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            return Board.parseDate(raw) ?? Date.distantPast
        }
        let status = try decoder.decode(AgentStatus.self, from: json.data(using: .utf8)!)
        var board = try fixture()
        board.accounts = [] // status-only grouping; the board's accounts are covered below
        board.sessions[2].status = .limited
        board.sessions[2].profile = "skp"
        board.sessions[2].detail = "resets 1:10pm"
        let accounts = status.accounts(board: board)
        XCTAssertEqual(accounts.map(\.profile), ["default", "skp"])
        XCTAssertEqual(accounts[0].tokensToday, 15)
        XCTAssertEqual(accounts[0].chip, "")
        XCTAssertEqual(accounts[1].chip, "SK")
        XCTAssertEqual(accounts[1].limitedUntil, "resets 1:10pm")
        XCTAssertEqual(accounts[0].limits?.fiveHour.percent, 55)
        XCTAssertEqual(accounts[0].limits?.sevenDay.percent, 10)
        XCTAssertNotNil(accounts[0].limits?.fiveHour.resetsAt)
        XCTAssertNil(accounts[1].limits)
        XCTAssertEqual(formatTokens(167_252_038), "167.3M")
        XCTAssertEqual(formatTokens(2_613_997_951), "2.6B")
        XCTAssertEqual(formatTokens(950), "950")
    }

    func testElapsedBuckets() {
        let now = Date()
        XCTAssertEqual(elapsedText(since: now.addingTimeInterval(-17), now: now), "15s")
        XCTAssertEqual(elapsedText(since: now.addingTimeInterval(-540), now: now), "9m")
        XCTAssertEqual(elapsedText(since: now.addingTimeInterval(-7200), now: now), "2h")
        XCTAssertEqual(elapsedText(since: nil, now: now), "")
    }
}

final class BoardContractTests: XCTestCase {
    func fixture() throws -> Board {
        let url = Bundle.module.url(forResource: "sessions", withExtension: "json", subdirectory: "Fixtures")!
        return try Board.decode(try Data(contentsOf: url))
    }

    func testDecodesContextTitlePendingNoteStuck() throws {
        let board = try fixture()
        let acme = board.sessions[0]
        XCTAssertEqual(acme.pending?.tool, "Bash")
        XCTAssertEqual(acme.pending?.subject, "go test")
        XCTAssertEqual(acme.pending?.text, "Bash go test")
        XCTAssertEqual(acme.answerable?.tool, "Bash")
        XCTAssertEqual(acme.contextPercent, 72)
        XCTAssertEqual(acme.context?.model, "claude-opus-4-7")
        XCTAssertEqual(acme.workspaceKey, "/home/me/dev/acme-api")
        let web = board.sessions[1]
        XCTAssertEqual(web.title, "Fix the login redirect")
        XCTAssertTrue(web.isStuck)
        XCTAssertEqual(web.contextPercent, 40)
        XCTAssertEqual(board.sessions[2].note, "waiting on PR review")
        XCTAssertNil(board.sessions[2].contextPercent)
        XCTAssertFalse(board.sessions[2].isStuck)
        XCTAssertEqual(board.slots[0].context, 72)
        XCTAssertEqual(board.slots[0].pending, "Bash")
        XCTAssertEqual(board.slots[1].stuck, true)
        XCTAssertEqual(board.agentDir, "/Users/me/Library/Application Support/corgi/agent")
    }

    func testPendingOnlyCountsWhileWaiting() throws {
        var board = try fixture()
        board.sessions[0].status = .working
        XCTAssertNil(board.sessions[0].answerable)
    }

    func testDecodesAccountsWithForecast() throws {
        let board = try fixture()
        XCTAssertEqual(board.accounts.map(\.profile), ["default", "work"])
        XCTAssertEqual(board.accounts[0].sessions, 4)
        XCTAssertEqual(board.accounts[0].limits?.fiveHour.percent, 55)
        XCTAssertEqual(board.accounts[0].forecast?.fiveHour?.percentPerHour, 12.5)
        XCTAssertEqual(board.accounts[0].forecast?.fiveHour?.safe, true)
        XCTAssertNil(board.accounts[0].forecast?.fiveHour?.exhaustAt)
        XCTAssertEqual(board.accounts[1].forecast?.fiveHour?.safe, false)
        XCTAssertNotNil(board.accounts[1].forecast?.fiveHour?.exhaustAt)
        XCTAssertNil(board.accounts[1].forecast?.sevenDay)
        // The status rows take limits, forecast and session count from the board.
        let rows = AgentStatus.empty.accounts(board: board)
        XCTAssertEqual(rows.map(\.profile), ["default", "work"])
        XCTAssertEqual(rows[1].sessions, 2)
        XCTAssertEqual(rows[1].forecast?.fiveHour?.percentPerHour, 62)
        XCTAssertEqual(rows[1].configDir, "/home/me/.claude-work")
    }

    func testForecastLine() throws {
        let utc = TimeZone(identifier: "UTC")!
        let reset = Board.parseDate("2026-09-08T16:10:00Z")!
        let exhaust = Board.parseDate("2026-09-08T14:32:00Z")!
        let hot = WindowForecast(percentPerHour: 62, exhaustAt: exhaust, safe: false, samples: 20)
        XCTAssertEqual(ForecastLine.make(hot, resetsAt: reset, timeZone: utc), ForecastLine(text: "62%/h · runs out 14:32 (before the 16:10 reset)", danger: true))
        XCTAssertEqual(ForecastLine.make(hot, resetsAt: nil, timeZone: utc)?.text, "62%/h · runs out 14:32")
        let fine = WindowForecast(percentPerHour: 12.5, exhaustAt: exhaust, safe: true, samples: 20)
        XCTAssertEqual(ForecastLine.make(fine, resetsAt: reset, timeZone: utc), ForecastLine(text: "12.5%/h · lasts until the reset", danger: false))
        let flat = WindowForecast(percentPerHour: 0, exhaustAt: nil, safe: true, samples: 20)
        XCTAssertEqual(ForecastLine.make(flat, resetsAt: reset, timeZone: utc), ForecastLine(text: "0%/h · pace flat", danger: false))
        XCTAssertNil(ForecastLine.make(nil, resetsAt: reset))
    }

    func testNextNeedingYouIsTheOldestWaiter() throws {
        var board = try fixture()
        XCTAssertEqual(board.nextNeedingYou()?.id, board.sessions[0].id)
        board.sessions[3].status = .needsInput
        board.sessions[3].statusSince = board.sessions[0].statusSince?.addingTimeInterval(-600)
        XCTAssertEqual(board.nextNeedingYou()?.id, board.sessions[3].id)
        for i in board.sessions.indices { board.sessions[i].status = .done }
        XCTAssertEqual(board.nextNeedingYou()?.id, board.frontSession)
        board.frontSession = nil
        XCTAssertNil(board.nextNeedingYou())
    }

    func testCarryTargetsSkipOwnAndExhaustedAccounts() throws {
        var board = try fixture()
        board.sessions[0].status = .limited
        XCTAssertEqual(board.carryTargets(for: board.sessions[0]).map(\.profile), ["default"]) // work is its own, at 96%
        XCTAssertEqual(board.carryTargets(for: board.sessions[1]).map(\.profile), []) // default's only other account is at 96%
        board.accounts[1].limits?.fiveHour.percent = 20
        XCTAssertEqual(board.carryTargets(for: board.sessions[1]).map(\.profile), ["work"])
    }

    func testQuietHoursWrapMidnight() {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 8
        let cal = Calendar(identifier: .gregorian)
        func at(_ h: Int, _ m: Int) -> Date { c.hour = h; c.minute = m; return cal.date(from: c)! }
        let night = QuietHours(enabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)
        XCTAssertTrue(night.contains(at(23, 0), calendar: cal))
        XCTAssertTrue(night.contains(at(3, 30), calendar: cal))
        XCTAssertFalse(night.contains(at(8, 0), calendar: cal))
        XCTAssertFalse(night.contains(at(12, 0), calendar: cal))
        let lunch = QuietHours(enabled: true, startMinutes: 12 * 60, endMinutes: 13 * 60)
        XCTAssertTrue(lunch.contains(at(12, 30), calendar: cal))
        XCTAssertFalse(lunch.contains(at(13, 0), calendar: cal))
        XCTAssertFalse(QuietHours(enabled: false, startMinutes: 0, endMinutes: 1440).contains(at(5, 0), calendar: cal))
        XCTAssertFalse(QuietHours(enabled: true, startMinutes: 600, endMinutes: 600).contains(at(10, 0), calendar: cal))
    }

    func testUsageSamplesKeepTheLastSpan() {
        let lines = """
        {"at":"2026-09-08T09:00:00Z","fetchedAt":"2026-09-08T09:00:00Z","fiveHour":10,"sevenDay":3}
        {"at":"2026-09-08T13:00:00Z","fetchedAt":"2026-09-08T13:00:00Z","fiveHour":40,"sevenDay":5}
        not json
        {"at":"2026-09-08T14:00:00Z","fetchedAt":"2026-09-08T14:00:00Z","fiveHour":55,"sevenDay":6}
        """
        let since = Board.parseDate("2026-09-08T10:00:00Z")!
        let samples = UsageSamples.parse(lines.data(using: .utf8)!, since: since)
        XCTAssertEqual(samples.map(\.fiveHour), [40, 55])
        XCTAssertEqual(UsageSamples.path(agentDir: "/a", profile: "work/x"), "/a/usage/work_x.jsonl")
        XCTAssertEqual(UsageSamples.path(agentDir: "/a", profile: ""), "/a/usage/default.jsonl")
    }

    func testStatsHeatmapAndHours() throws {
        let json = #"{"dailyActivity":[{"date":"2026-09-07","messageCount":12,"sessionCount":1,"toolCallCount":3},{"date":"2026-09-08","messageCount":5,"sessionCount":1,"toolCallCount":1}],"dailyModelTokens":[{"date":"2026-09-08","tokensByModel":{"claude-opus-4-7":1000,"claude-haiku-4-5":20}}],"hourCounts":{"9":4,"23":1}}"#
        let stats = try JSONDecoder().decode(ClaudeStats.self, from: json.data(using: .utf8)!)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 9, day: 8))! // a Tuesday
        let cells = stats.heatmap(weeks: 12, today: today, calendar: cal)
        XCTAssertEqual(cells.count, 11 * 7 + 2)
        XCTAssertEqual(cells.last?.count, 5)
        XCTAssertEqual(cells[cells.count - 2].count, 12)
        XCTAssertEqual(stats.hours[9], 4)
        XCTAssertEqual(stats.hours[0], 0)
        XCTAssertEqual(stats.hours.count, 24)
        XCTAssertEqual(stats.tokensToday(today: today, calendar: cal).map(\.model), ["claude-opus-4-7", "claude-haiku-4-5"])
    }
}
