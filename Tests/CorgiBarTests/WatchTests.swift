import XCTest
@testable import CorgiBar

final class WatchTests: XCTestCase {
    private func decode(_ json: String) throws -> WatchStatus {
        try WatchStatus.decode(Data(json.utf8))
    }

    func testReadsWhatIsWatchedAndWhetherItActs() throws {
        let s = try decode("""
        {"workspaces":[
          {"workspace":"api","sources":["jira","gitlab"],"action":"fix","interval":"3m0s","quiet":"17:00-08:00",
           "fixes":{"perHour":3,"perDay":10,"startedToday":2}},
          {"workspace":"web","sources":["linear"],"action":"notify","interval":"3m0s"}],
         "fixes":[]}
        """)
        XCTAssertTrue(s.watched)
        XCTAssertEqual(s.workspaces.count, 2)
        XCTAssertTrue(s.workspaces[0].isAuto, "action fix is the unattended mode")
        XCTAssertFalse(s.workspaces[1].isAuto)
        XCTAssertEqual(s.workspaces[0].quiet, "17:00-08:00")
        XCTAssertEqual(s.workspaces[0].fixes?.perDay, 10)
    }

    func testEmptyAndMalformedAreNotACrash() throws {
        XCTAssertFalse(try decode("{}").watched)
        XCTAssertEqual(try decode("{}").fixes.count, 0)
        XCTAssertThrowsError(try decode("not json"))
    }

    func testAFixReportsWhatItOpened() throws {
        let s = try decode("""
        {"workspaces":[{"workspace":"api","action":"fix"}],"fixes":[
          {"ref":"ABC-1","workspace":"api","startedAt":"2026-09-10T12:00:00Z","running":true},
          {"ref":"ABC-2","workspace":"api","startedAt":"2026-09-10T11:00:00Z","running":false,
           "prs":["https://github.com/acme/api/pull/7"]},
          {"ref":"ABC-3","workspace":"api","startedAt":"2026-09-10T10:00:00Z","running":false,"error":"timed out"},
          {"ref":"ABC-4","workspace":"api","startedAt":"2026-09-10T09:00:00Z","running":false,"note":"no change needed"}]}
        """)
        XCTAssertEqual(s.running.map(\.ref), ["ABC-1"])
        XCTAssertEqual(s.fixes[0].outcome, "running")
        XCTAssertEqual(s.fixes[1].outcome, "opened 1 PR")
        XCTAssertEqual(s.fixes[1].pullRequest?.absoluteString, "https://github.com/acme/api/pull/7")
        XCTAssertEqual(s.fixes[2].outcome, "timed out")
        XCTAssertEqual(s.fixes[3].outcome, "no change needed")
        XCTAssertNil(s.fixes[0].pullRequest, "a run with no PR has nothing to open")
    }

    func testOnlyHttpsPullRequestsAreOffered() throws {
        let s = try decode("""
        {"fixes":[{"ref":"A","workspace":"w","running":false,"prs":["javascript:alert(1)"]}]}
        """)
        XCTAssertNil(s.fixes[0].pullRequest, "anything that is not https is not a link to open")
    }

    func testRecentForgetsOldNewsAndTheSummaryReadsPlainly() throws {
        let now = Date(timeIntervalSince1970: 1_757_500_000)
        let old = ISO8601DateFormatter().string(from: now.addingTimeInterval(-48 * 3600))
        let s = try decode("""
        {"workspaces":[{"workspace":"api","action":"fix"}],"fixes":[
          {"ref":"OLD","workspace":"api","startedAt":"\(old)","running":false,"prs":["https://x/pull/1"]}]}
        """)
        XCTAssertEqual(s.recent(now: now).count, 0, "two days old is history")
        XCTAssertEqual(s.summary(now: now), "unattended, nothing yet")

        let live = try decode("""
        {"workspaces":[{"workspace":"api","action":"fix"}],"fixes":[
          {"ref":"ABC-9","workspace":"api","running":true}]}
        """)
        XCTAssertEqual(live.summary(now: now), "working on ABC-9")

        let reporting = try decode(#"{"workspaces":[{"workspace":"api","action":"notify"}]}"#)
        XCTAssertEqual(reporting.summary(now: now), "reporting only")
    }

    func testElapsedReadsAsAPersonWouldSayIt() {
        let now = Date(timeIntervalSince1970: 1_757_500_000)
        XCTAssertEqual(elapsedSince(now.addingTimeInterval(-6 * 60), now: now), "6m")
        XCTAssertEqual(elapsedSince(now.addingTimeInterval(-80 * 60), now: now), "1h 20m")
        XCTAssertEqual(elapsedSince(now.addingTimeInterval(-120 * 60), now: now), "2h")
        XCTAssertEqual(elapsedSince(nil, now: now), "")
    }
}
