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
