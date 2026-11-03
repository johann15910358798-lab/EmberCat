import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusPanelState: ObservableObject {
    enum Page {
        case menu, sources

        var size: NSSize {
            switch self {
            case .menu: NSSize(width: 300, height: 556)
            case .sources: NSSize(width: 536, height: 402)
            }
        }
    }

    @Published var page: Page = .menu
    @Published var style: PetStyle
    @Published var showsTokenRate: Bool
    @Published var showsNotchFlame: Bool
    @Published var showsDockCat: Bool

    init(style: PetStyle, showsTokenRate: Bool, showsNotchFlame: Bool, showsDockCat: Bool) {
        self.style = style
        self.showsTokenRate = showsTokenRate
        self.showsNotchFlame = showsNotchFlame
        self.showsDockCat = showsDockCat
    }
}

@MainActor
struct StatusPanelView: View {
    @ObservedObject var viewModel: SpeedMonitorModel
    @ObservedObject var state: StatusPanelState
    @ObservedObject var dockSettings: DockOrbitSettings
    @ObservedObject var updates: AppUpdateController
    let onNavigate: (StatusPanelState.Page) -> Void
    let onSelectStyle: (PetStyle) -> Void
    let onSelectDisplay: (Bool) -> Void
    let onSelectFlame: (Bool) -> Void
    let onSelectDock: (Bool) -> Void
    let onCustomizePawColor: () -> Void
    let onPreview: () -> Void
    let onFlamePreview: () -> Void
    let onCheckForUpdates: () -> Void
    let onClose: () -> Void
    let onQuit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if state.page == .menu {
                menuPage
                    .frame(width: StatusPanelState.Page.menu.size.width, height: StatusPanelState.Page.menu.size.height)
                    .transition(pageTransition(offset: -12))
            } else {
                TokenSourcesView(viewModel: viewModel) { onNavigate(.menu) }
                    .frame(width: StatusPanelState.Page.sources.size.width, height: StatusPanelState.Page.sources.size.height)
                    .transition(pageTransition(offset: 16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onExitCommand(perform: onClose)
    }

    private func pageTransition(offset: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: offset))
    }

    private var menuPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                petImage(state.style)
                    .frame(width: 32, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("EmberCat")
                        .font(.system(size: 13, weight: .semibold))
                    Text(viewModel.snapshot.live.output > 0 ? "正在输出" : "等待输出")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%.1f", max(0, viewModel.snapshot.live.output)))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.snapshot.live.output)
                    Text("tok/s")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 17)
            .padding(.top, 15)
            .padding(.bottom, 13)

            Divider()
            PanelActionRow(title: "Token 来源", symbol: "square.stack.3d.up", subtitle: sourceSummary, showsChevron: true) {
                onNavigate(.sources)
            }
            .accessibilityIdentifier("open-token-sources")
            .padding(6)
            Divider().padding(.horizontal, 12)

            VStack(spacing: 12) {
                HStack {
                    Text("显示实时速度").font(.system(size: 12))
                    Spacer()
                    Toggle("显示实时速度", isOn: Binding(get: { state.showsTokenRate }, set: { onSelectDisplay($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityIdentifier("show-token-rate")
                }
                HStack {
                    Text("灵动岛火焰").font(.system(size: 12))
                    Spacer()
                    Toggle("灵动岛火焰", isOn: Binding(get: { state.showsNotchFlame }, set: { onSelectFlame($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityIdentifier("show-notch-flame")
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("绕 Dock 跑圈").font(.system(size: 12))
                        Text(dockSubtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if state.showsDockCat && dockSettings.status == .needsAccessibility {
                        Button("允许…") { dockSettings.requestAccessibility() }
                            .font(.system(size: 10))
                            .accessibilityIdentifier("allow-dock-access")
                    }
                    Toggle("绕 Dock 跑圈", isOn: Binding(get: { state.showsDockCat }, set: { onSelectDock($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityIdentifier("show-dock-cat")
                }
                HStack(spacing: 10) {
                    Text("脚印荧光色").font(.system(size: 12))
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        ForEach(DockOrbitSettings.trailPresets, id: \.hex) { preset in
                            Button {
                                if let color = DockOrbitSettings.color(hex: preset.hex) { dockSettings.setTrailColor(color) }
                            } label: {
                                Circle()
                                    .fill(Color(nsColor: DockOrbitSettings.color(hex: preset.hex)!))
                                    .frame(width: 12, height: 12)
                                    .shadow(color: Color(nsColor: DockOrbitSettings.color(hex: preset.hex)!).opacity(0.45), radius: 2)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(dockSettings.trailColorHex == preset.hex
                                                                  ? Color.primary.opacity(0.55) : .clear, lineWidth: 1))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                            .accessibilityLabel(preset.name)
                            .accessibilityAddTraits(dockSettings.trailColorHex == preset.hex ? .isSelected : [])
                        }
                    }
                    Button("自定义…", action: onCustomizePawColor)
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("customize-paw-color")
                }
                HStack(spacing: 10) {
                    Text("形象")
                        .font(.system(size: 12))
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        ForEach(PetStyle.allCases, id: \.rawValue) { style in
                            Button { onSelectStyle(style) } label: {
                                HStack(spacing: 4) {
                                    petImage(style).frame(width: 24, height: 18)
                                    Text(style.displayName).font(.system(size: 11))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(state.style == style ? Color.accentColor.opacity(0.13) : .clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(state.style == style ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Divider().padding(.horizontal, 12)

            VStack(spacing: 1) {
                PanelActionRow(title: "动作预览…", symbol: "play.rectangle", action: onPreview)
                PanelActionRow(title: "火焰设置与预览…", symbol: "flame", action: onFlamePreview)
                PanelActionRow(title: updates.availableVersion.map { "更新至 \($0)…" } ?? "检查更新…",
                    symbol: "arrow.down.circle", action: onCheckForUpdates)
                    .disabled(!updates.canCheckForUpdates)
                    .accessibilityIdentifier("check-for-updates")
                HStack {
                    Text("自动检查更新").font(.system(size: 11))
                    Spacer()
                    Toggle("自动检查更新", isOn: Binding(get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticChecks($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .accessibilityIdentifier("automatic-update-checks")
                }.padding(.horizontal, 10).padding(.vertical, 4)
                HStack {
                    Text("自动下载并安装").font(.system(size: 11))
                    Spacer()
                    Toggle("自动下载并安装", isOn: Binding(get: { updates.automaticallyDownloadsUpdates },
                        set: { updates.setAutomaticDownloads($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .disabled(!updates.automaticallyChecksForUpdates)
                        .accessibilityIdentifier("automatic-update-downloads")
                }.padding(.horizontal, 10).padding(.vertical, 4)
                PanelActionRow(title: "退出 EmberCat", symbol: "power", action: onQuit)
            }
            .padding(6)
            Spacer(minLength: 0)
        }
    }

    private var sourceSummary: String {
        let sources = viewModel.snapshot.sources.filter { $0.enabled && $0.available }
        return sources.isEmpty ? "正在发现本地来源" : "\(sources.count) 个来源 · 查看各自速度"
    }

    private var dockSubtitle: String {
        guard state.showsDockCat else { return "黑猫沿 Dock 四边跑动" }
        switch dockSettings.status {
        case .needsAccessibility: return "需辅助功能权限定位 Dock"
        case .waitingForDock: return "Dock 显示后继续跑圈"
        case .following, .disabled: return "圆角转身 · 随 tok/s 加速"
        }
    }

    @ViewBuilder private func petImage(_ style: PetStyle) -> some View {
        if let image = style == .cat
            ? SpriteLibrary.shared.catMenuBarFrames(for: .idle).first
            : SpriteLibrary.shared.menuBarFrames(for: .idle).first {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .accessibilityHidden(true)
        }
    }
}

private typealias PanelHoverState = SwiftUI.State<Bool>

private struct PanelActionRow: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    var showsChevron = false
    let action: () -> Void
    @PanelHoverState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, subtitle == nil ? 8 : 9)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.065) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
