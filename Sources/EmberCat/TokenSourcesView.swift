import AgentSpeedCore
import AppKit
import SwiftUI

// Select the macOS 14-compatible property wrapper when the SDK also exports a State macro.
private typealias SourceSelectionState = SwiftUI.State<SourceKind?>

private struct TokenSourceDetails: Identifiable {
    let source: SourceStatus
    let toolsCount: Int
    let monitorState: MonitorState
    let unsupported: Bool

    var id: SourceKind { source.kind }
    var speed: Double { max(0, source.live.output) }
    var estimatedSpeed: Double { min(speed, max(0, source.liveEstimated.output)) }
    var contributing: Bool { speed > 0 }
    var busy: Bool { contributing || source.activeAgents > 0 || toolsCount > 0 }

    var status: String {
        if case .starting = monitorState { return "正在扫描" }
        if unsupported { return "格式暂不支持" }
        if !source.available { return "读取位置不可用" }
        if source.activeAgents > 0 { return "正在生成" }
        if toolsCount > 0 { return "工具执行中" }
        if contributing { return "最近输出" }
        return source.sessionCount > 0 ? "待机" : "今日暂无会话"
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return source.rootPath.replacingOccurrences(of: home + "/", with: "~/")
    }

    static func all(in snapshot: SpeedSnapshot) -> [Self] {
        // Use the engine's per-source rates. Its visible agent list can omit older responses
        // that still contribute to the current window, so summing that list would lose tokens.
        snapshot.sources.compactMap { source in
            let tools = snapshot.agents.filter { $0.source == source.kind && $0.phase == .tools }.count
            guard source.enabled,
                  source.available || source.producedToday || source.activeAgents > 0 || tools > 0 else { return nil }
            return Self(source: source, toolsCount: tools, monitorState: snapshot.state,
                        unsupported: snapshot.warnings.contains(.unsupportedFormat(source.kind)))
        }
    }
}

@MainActor
struct TokenSourcesView: View {
    @ObservedObject var viewModel: SpeedMonitorModel
    let onBack: () -> Void
    @SourceSelectionState private var selection: SourceKind? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sources: [TokenSourceDetails] { TokenSourceDetails.all(in: viewModel.snapshot) }

    private var selectedSource: TokenSourceDetails? {
        sources.first { $0.id == selection }
            ?? sources.first { $0.contributing }
            ?? sources.first { $0.busy }
            ?? sources.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sourceList
                    .frame(width: 176)
                Divider()
                ZStack(alignment: .topLeading) {
                    if let source = selectedSource {
                        sourceDetail(source)
                            .id(source.id)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
                    } else {
                        emptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { selection = selectedSource?.id }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回菜单")
            .accessibilityIdentifier("back-to-menu")
            .help("返回菜单")
            VStack(alignment: .leading, spacing: 4) {
                Text("Token 来源")
                    .font(.system(size: 14, weight: .semibold))
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(rate(viewModel.snapshot.live.output))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.snapshot.live.output)
                Text("当前总输出")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
    }

    private var summary: String {
        if case .starting(let progress) = viewModel.snapshot.state {
            return "正在扫描本地会话 · \(Int((progress * 100).rounded()))%"
        }
        let count = sources.filter(\.contributing).count
        return count > 0 ? "\(count) 个来源正在贡献输出" : "当前没有输出"
    }

    private var sourceList: some View {
        ScrollView {
            VStack(spacing: 3) {
                if sources.isEmpty {
                    Text("暂无来源")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
                ForEach(sources) { source in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.20)) {
                            selection = source.id
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 9) {
                            SourceIconView(source: source.id)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(source.id.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
                                Text(rate(source.speed))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: source.speed)
                            }
                            Spacer(minLength: 0)
                            Circle()
                                .fill(source.busy ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 5, height: 5)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                        .background(selectedSource?.id == source.id ? Color.accentColor.opacity(0.12) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(source.id.displayName)，\(rate(source.speed))，\(source.status)")
                    .accessibilityAddTraits(selectedSource?.id == source.id ? .isSelected : [])
                    .accessibilityIdentifier("token-source-\(source.id.rawValue)")
                }
            }
            .padding(8)
        }
    }

    private func sourceDetail(_ source: TokenSourceDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                SourceIconView(source: source.id, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.id.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(source.status)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(rate(source.speed))
                        .font(.system(size: 23, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: source.speed)
                    Text("当前来源输出")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 24) {
                metric("今日输出", value: "\(source.source.today.output.formatted()) tok")
                metric("今日会话", value: source.source.sessionCount.formatted())
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("生成中 \(source.source.activeAgents) · 工具中 \(source.toolsCount)")
                        .font(.system(size: 10))
                    if source.estimatedSpeed > 0 {
                        Text("估算 \(rate(source.estimatedSpeed)) · \(Int((source.estimatedSpeed / source.speed * 100).rounded()))%")
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Divider()
            TokenConversationListView(agents: viewModel.snapshot.agents, source: source.id)
                .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 8) {
                Text("读取位置")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text(source.displayPath.isEmpty ? "尚未发现本地记录" : source.displayPath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(source.source.rootPath)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.secondary)
            Text(viewModel.snapshot.state == .noSources ? "还没有发现本地会话" : "正在查找本地会话")
                .font(.system(size: 13, weight: .medium))
            Text("来源出现后会自动显示在这里")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("读取本地记录 · 估算部分单独标注")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Text("约 3 秒窗口")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func rate(_ value: Double) -> String {
        String(format: "%.1f tok/s", max(0, value))
    }
}
