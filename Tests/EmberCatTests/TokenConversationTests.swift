import AgentSpeedCore
import XCTest
@testable import EmberCat

final class TokenConversationTests: XCTestCase {
    private func agent(_ id: String, source: SourceKind = .codex, parent: String? = nil,
                       subagent: Bool = false, speed: Double = 0, phase: AgentPhase = .idle,
                       activity: Date = Date(timeIntervalSince1970: 1_000)) -> AgentStatus {
        AgentStatus(id: id, source: source, project: "same-project", model: "provider/model",
                    phase: phase, isSubagent: subagent, live: Rate(output: speed), recentSpeed: 75,
                    lastActivity: activity, parentId: parent)
    }

    func testConversationsSharingProjectAndModelKeepTheirOwnRates() {
        let rows = TokenConversation.rows(in: [agent("first", speed: 12), agent("second", speed: 28)], source: .codex)
        XCTAssertEqual(rows.map(\.id), ["first", "second"])
        XCTAssertEqual(rows.map(\.speed), [12, 28])
        XCTAssertEqual(rows.map(\.shortID), ["first", "second"])
    }

    func testParentGroupsKeepCoreOrderAndInactiveAncestors() {
        let agents = [
            agent("parent", activity: .distantPast),
            agent("child", parent: "parent", subagent: true, speed: 21, phase: .generating),
            agent("grandchild", parent: "child", subagent: true, phase: .tools),
            agent("independent", speed: 100),
        ]
        let rows = TokenConversation.rows(in: agents, source: .codex)
        XCTAssertEqual(rows.map(\.id), agents.map(\.id))
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 0])
        XCTAssertEqual(rows[0].speed, 0, "The parent must not silently include its child's speed.")
    }

    func testSourceFilteringDoesNotInventParents() {
        let agents = [agent("other", source: .claudeCode), agent("child", parent: "other", subagent: true)]
        let rows = TokenConversation.rows(in: agents, source: .codex)
        XCTAssertEqual(rows.map(\.id), ["child"])
        XCTAssertEqual(rows[0].depth, 0)
        XCTAssertTrue(rows[0].agent.isSubagent)
    }

    func testCurrentRateNeverFallsBackToRecentResponseAverage() {
        let row = TokenConversation(agent: agent("idle", speed: 0), depth: 0)
        XCTAssertEqual(row.speed, 0)
        XCTAssertEqual(row.agent.recentSpeed, 75)
        XCTAssertEqual(row.status, "待机")
    }

    func testReadableRecordIdentifiersForFileAndDatabaseSources() {
        let uuid = "12345678-1234-1234-1234-123456789abc"
        let codex = TokenConversation(agent: agent("/tmp/fixtures/rollout-2026-11-06T10-00-00-\(uuid).jsonl.zst"), depth: 0)
        XCTAssertEqual(codex.recordName, uuid)
        XCTAssertEqual(codex.shortID, "12345678-1…789abc")
        let opencode = TokenConversation(agent: agent("opencode:ses_example", source: .opencode), depth: 0)
        XCTAssertEqual(opencode.recordName, "ses_example")
        let zcode = TokenConversation(agent: agent("/tmp/fixtures/db.sqlite#session-example", source: .zcode), depth: 0)
        XCTAssertEqual(zcode.recordName, "session-example")
        let dsh = TokenConversation(agent: agent("/tmp/fixtures/\(uuid)/session.v1.jsonl.zstd", source: .deepseek), depth: 0)
        XCTAssertEqual(dsh.recordName, uuid)
    }

    func testMissingMetadataAndEmptySourceRemainExplicit() {
        var entry = agent("/tmp/fixtures/session.jsonl")
        entry.project = " "
        entry.model = nil
        let row = TokenConversation(agent: entry, depth: 0)
        XCTAssertEqual(row.project, "未标注项目")
        XCTAssertEqual(row.model, "模型未记录")
        XCTAssertTrue(TokenConversation.rows(in: [entry], source: .gemini).isEmpty)
    }
}
