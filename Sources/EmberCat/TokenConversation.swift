import AgentSpeedCore
import Foundation

/// One transcript remains one row, even when several conversations share a project or model.
struct TokenConversation: Identifiable {
    let agent: AgentStatus
    let depth: Int

    var id: String { agent.id }
    var project: String {
        agent.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未标注项目" : agent.project
    }
    var model: String { agent.model.flatMap { $0.isEmpty ? nil : $0 } ?? "模型未记录" }
    var shortModel: String { model.split(separator: "/").last.map(String.init) ?? model }
    var speed: Double { max(0, agent.live.output) }

    var status: String {
        switch agent.phase {
        case .generating: "生成中"
        case .tools: "工具执行中"
        case .idle: speed > 0 ? "最近输出" : "待机"
        }
    }

    /// A readable fragment of the record identity, not an invented conversation title.
    var shortID: String {
        let value = recordName
        guard value.count > 20 else { return value }
        return "\(value.prefix(10))…\(value.suffix(6))"
    }

    var recordName: String {
        if agent.source == .opencode, id.hasPrefix("opencode:") {
            return String(id.dropFirst("opencode:".count))
        }
        if agent.source == .zcode, let separator = id.lastIndex(of: "#") {
            return String(id[id.index(after: separator)...])
        }
        // Codex's rollout filename prefixes a UUID with a timestamp. Other sources
        // may put the UUID in a parent folder and use a generic session filename.
        let pattern = "[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}"
        if let range = id.range(of: pattern, options: [.regularExpression, .backwards]) {
            return String(id[range])
        }
        var name = (id as NSString).lastPathComponent
        for suffix in [".jsonl.zstd", ".jsonl.zst", ".jsonl", ".json", ".sqlite", ".db"] {
            if name.hasSuffix(suffix) {
                name.removeLast(suffix.count)
                break
            }
        }
        if name == "session" || name.hasPrefix("session.v") {
            let folder = ((id as NSString).deletingLastPathComponent as NSString).lastPathComponent
            return folder.isEmpty ? name : "\(folder)/\(name)"
        }
        return name.isEmpty ? id : name
    }

    var recordLocation: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
        return id.hasPrefix(home) ? "~/" + id.dropFirst(home.count) : id
    }

    static func rows(in agents: [AgentStatus], source: SourceKind) -> [Self] {
        var depths: [String: Int] = [:]
        // The core already orders complete parent groups (METRICS 6.7). Keep that
        // order and its inactive ancestors; filtering again by activity would split them.
        return agents.filter { $0.source == source }.map { agent in
            let depth = agent.parentId.flatMap { depths[$0] }.map { $0 + 1 } ?? 0
            depths[agent.id] = depth
            return Self(agent: agent, depth: depth)
        }
    }
}
