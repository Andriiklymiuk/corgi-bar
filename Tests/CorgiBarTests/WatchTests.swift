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

    func testABlockedTicketSaysWhyAndNewKindsHaveWords() throws {
        let s = try decode("""
        {"events":[
          {"key":"jira:ABC-9:c1","ref":"ABC-9","kind":"issue.comment","workspace":"api","title":"still failing","at":"2026-09-10T12:00:00Z","blocked":"2 runs failed"},
          {"key":"gh:api#12:n1","ref":"api#12","kind":"review.requested","workspace":"api","at":"2026-09-10T12:00:00Z"},
          {"key":"gh:api#13:ci","ref":"api#13","kind":"ci.failed","workspace":"api","at":"2026-09-10T12:00:00Z"}]}
        """)
        XCTAssertEqual(s.events[0].blocked, "2 runs failed")
        XCTAssertNil(s.events[1].blocked)
        XCTAssertEqual(s.events[1].kindLabel, "review asked")
        XCTAssertEqual(s.events[2].kindLabel, "build red")
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

    func testAWatchSaysWhichDaysItSleeps() throws {
        let s = try decode("""
        {"workspaces":[{"workspace":"api","daysOff":["sat","sun"],"asleep":true},{"workspace":"web","daysOff":["fri"]},{"workspace":"x"}]}
        """)
        XCTAssertEqual(s.workspaces[0].daysOffLine, "asleep today")
        XCTAssertEqual(s.workspaces[1].daysOffLine, "off fri")
        XCTAssertNil(s.workspaces[2].daysOffLine)
    }

    func testAnInboxRowNamesTheSessionOnIt() throws {
        let s = try decode("""
        {"events":[{"key":"linear:A-1","ref":"A-1","kind":"issue.new","session":{"id":"s1","label":"api 2","status":"working"}},
                   {"key":"linear:A-2","ref":"A-2","kind":"issue.new"}]}
        """)
        XCTAssertEqual(s.events[0].sessionLine, "session api 2 · working")
        XCTAssertNil(s.events[1].sessionLine)
        let t = try decode("""
        {"events":[{"key":"task:1","ref":"TASK-1","kind":"task","picked":{"at":"2026-09-11T12:00:00Z","by":"phone"}}]}
        """)
        XCTAssertEqual(t.events[0].kindLabel, "task")
        XCTAssertEqual(t.events[0].sessionLine, "picked from the phone · waiting for a session")
    }

    func testARunRowOpensItsPullRequestElseItsTicket() throws {
        let s = try decode("""
        {"fixes":[
          {"key":"linear:A-1","ref":"A-1","workspace":"w","url":"https://linear.app/x/issue/A-1","running":false,"prs":["https://github.com/acme/api/pull/7"]},
          {"key":"linear:A-2","ref":"A-2","workspace":"w","url":"https://linear.app/x/issue/A-2","running":false},
          {"ref":"A-3","workspace":"w","url":"file:///etc/passwd","running":false}]}
        """)
        XCTAssertEqual(s.fixes[0].destination?.absoluteString, "https://github.com/acme/api/pull/7", "the pull request it opened comes first")
        XCTAssertEqual(s.fixes[1].destination?.absoluteString, "https://linear.app/x/issue/A-2", "else the ticket")
        XCTAssertNil(s.fixes[2].destination, "only https opens")
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

extension WatchTests {
    /// The inbox rides along with the watch status now, so the menu can show
    /// what is waiting without asking the phone.
    func testInboxItemsDecodeAndDescribeThemselves() throws {
        let json = """
        {"workspaces":[{"workspace":"api","action":"notify"}],
         "events":[
           {"key":"jira:ABC-1","ref":"ABC-1","kind":"issue.new","workspace":"api",
            "title":"Login loops","url":"https://x/browse/ABC-1","state":"READY TO DEV",
            "at":"2026-09-10T12:00:00Z"},
           {"key":"gl:acme/api!7","ref":"acme/api!7","kind":"pr.review","workspace":"api"}
         ]}
        """
        let watch = try WatchStatus.decode(Data(json.utf8))
        XCTAssertEqual(watch.events.count, 2)

        let first = watch.events[0]
        XCTAssertEqual(first.kindLabel, "issue")
        XCTAssertEqual(first.state, "READY TO DEV")
        XCTAssertEqual(first.link?.absoluteString, "https://x/browse/ABC-1")

        // A row with none of the optional fields must not fail the payload.
        let second = watch.events[1]
        XCTAssertEqual(second.kindLabel, "PR review")
        XCTAssertNil(second.link)
        XCTAssertEqual(second.title, "")

        XCTAssertEqual(watch.summary(now: Date()), "2 things waiting")
    }

    func testAnInboxLinkMustBeHttps() throws {
        let json = #"{"events":[{"key":"k","url":"javascript:alert(1)"}]}"#
        let watch = try WatchStatus.decode(Data(json.utf8))
        XCTAssertNil(watch.events[0].link, "only https is worth opening")
    }
}
