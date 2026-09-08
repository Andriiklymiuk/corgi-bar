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

    func testElapsedBuckets() {
        let now = Date()
        XCTAssertEqual(elapsedText(since: now.addingTimeInterval(-17), now: now), "15s")
        XCTAssertEqual(elapsedText(since: now.addingTimeInterval(-540), now: now), "9m")
        XCTAssertEqual(elapsedText(since: now.addingTimeInterval(-7200), now: now), "2h")
        XCTAssertEqual(elapsedText(since: nil, now: now), "")
    }
}
