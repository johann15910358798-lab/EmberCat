import AgentSpeedCore
import AppKit
import SwiftUI

private typealias ConversationSelectionState = SwiftUI.State<String?>

struct TokenConversationListView: View {
    let agents: [AgentStatus]
    let source: SourceKind
    @ConversationSelectionState private var expandedID: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [TokenConversation] { TokenConversation.rows(in: agents, source: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("对话与子 Agent")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(countSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 22, weight: .light))
                    Text("最近还没有对话活动")
                        .font(.system(size: 12, weight: .medium))
                    Text("有新活动的对话会自动出现在这里")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("empty-token-conversations")
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(rows) { row in
                            TokenConversationRowView(row: row, expanded: expandedID == row.id) {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                                    expandedID = expandedID == row.id ? nil : row.id
                                }
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
                .accessibilityIdentifier("token-conversation-list")
            }
            Text("近 10 分钟活动或正在生成的对话，保留关联的父对话")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .onChange(of: source) { _, _ in expandedID = nil }
        .onChange(of: agents.map(\.id)) { _, ids in
            if let expandedID, !ids.contains(expandedID) { self.expandedID = nil }
        }
    }

    private var countSummary: String {
        let conversations = rows.filter { !$0.agent.isSubagent }.count
        let children = rows.count - conversations
        return children > 0 ? "\(conversations) 个对话 · \(children) 个子 Agent" : "\(conversations) 个对话"
    }
}

private struct TokenConversationRowView: View {
    let row: TokenConversation
    let expanded: Bool
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if row.depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                    .padding(.top, 18)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                Button(action: onSelect) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Text(row.project)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if row.agent.isSubagent {
                                    Text("子 Agent")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                }
                            }
                            HStack(spacing: 4) {
                                Text(row.shortID)
                                    .font(.system(size: 9, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("·")
                                Text(row.shortModel)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(rate(row.speed))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: row.speed)
                            Text(row.status)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.project)，\(row.agent.isSubagent ? "子 Agent" : "对话")，\(row.shortID)，\(row.model)")
                .accessibilityValue("\(row.status)，\(rate(row.speed))，\(expanded ? "已展开" : "已收起")")
                .accessibilityIdentifier("token-conversation-\(row.id)")
                if expanded { details }
            }
            .background(Color.primary.opacity(expanded ? 0.055 : 0.03), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(expanded ? Color.accentColor.opacity(0.22) : .clear, lineWidth: 0.7))
        }
        .padding(.leading, CGFloat(min(row.depth, 3)) * 9)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            detail("模型", value: row.model)
            detail("最近活动", value: row.agent.lastActivity.formatted(date: .abbreviated, time: .standard))
            if let recentSpeed = row.agent.recentSpeed {
                detail("最近响应均速", value: rate(max(0, recentSpeed)))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("记录标识")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(row.id, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("复制此对话的完整记录标识")
                }
                Text(row.recordLocation)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(row.id)
            }
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }

    private func detail(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var statusColor: Color {
        switch row.agent.phase {
        case .generating: .green
        case .tools: .orange
        case .idle: row.speed > 0 ? .accentColor : .secondary.opacity(0.4)
        }
    }

    private func rate(_ value: Double) -> String { String(format: "%.1f tok/s", value) }
}
