import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusPanelState: ObservableObject {
    enum Page {
        case menu, sources

        var size: NSSize {
            switch self {
            case .menu: NSSize(width: 344, height: 488)
            case .sources: NSSize(width: 640, height: 500)
            }
        }
    }

    @Published var page: Page = .menu
    @Published var style: PetStyle
    @Published var showsTokenRate: Bool
    @Published var showsNotchFlame: Bool
    @Published var notchEffect: NotchEffectStyle
    @Published var showsDockCat: Bool

    init(style: PetStyle, showsTokenRate: Bool, showsNotchFlame: Bool, showsDockCat: Bool,
         notchEffect: NotchEffectStyle = .flame) {
        self.style = style
        self.showsTokenRate = showsTokenRate
        self.showsNotchFlame = showsNotchFlame
        self.showsDockCat = showsDockCat
        self.notchEffect = notchEffect
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
    let onSelectNotchEffect: (NotchEffectStyle) -> Void
    let onSelectDock: (Bool) -> Void
    let onCustomizePawColor: () -> Void
    let onPreview: () -> Void
    let onFlamePreview: () -> Void
    let onCheckForUpdates: () -> Void
    let onClose: () -> Void
    let onQuit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

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
        VStack(spacing: 10) {
            statusHeader
            sourcesButton
            appearanceCard
            effectsCard
            previewButtons
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var statusHeader: some View {
        HStack(spacing: 11) {
            petImage(state.style)
                .frame(width: 34, height: 28)
                .frame(width: 48, height: 48)
                .background(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.10),
                            in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text("EmberCat")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.snapshot.live.output > 0 ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text(viewModel.snapshot.live.output > 0 ? "正在输出" : "等待输出")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.1f", max(0, viewModel.snapshot.live.output)))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.snapshot.live.output)
                Text("tok/s")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 112, alignment: .trailing)
        }
        .frame(height: 56)
        .padding(.horizontal, 3)
    }

    private var sourcesButton: some View {
        Button { onNavigate(.sources) } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 11))
                Text("Token 来源")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                Text(sourceSummary)
                    .font(.system(size: 10))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .frame(height: 32)
        }
        .buttonStyle(PanelButtonStyle())
        .accessibilityIdentifier("open-token-sources")
    }

    private var appearanceCard: some View {
        PanelCard {
            PanelToggleRow(title: "菜单栏实时速度", symbol: "speedometer",
                isOn: Binding(get: { state.showsTokenRate }, set: { onSelectDisplay($0) }),
                identifier: "show-token-rate")
            panelDivider
            HStack(spacing: 8) {
                Image(systemName: "pawprint")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("形象")
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(PetStyle.allCases, id: \.rawValue) { style in
                        Button { onSelectStyle(style) } label: {
                            HStack(spacing: 5) {
                                petImage(style).frame(width: 25, height: 20)
                                Text(style.displayName).font(.system(size: 11))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                        }
                        .buttonStyle(PanelButtonStyle(selected: state.style == style))
                        .accessibilityAddTraits(state.style == style ? .isSelected : [])
                        .accessibilityIdentifier("pet-style-\(style.rawValue)")
                    }
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    private var effectsCard: some View {
        PanelCard {
            PanelToggleRow(title: "刘海特效", symbol: "sparkles",
                isOn: Binding(get: { state.showsNotchFlame }, set: { onSelectFlame($0) }),
                identifier: "show-notch-flame")
            HStack(spacing: 6) {
                ForEach(NotchEffectStyle.allCases, id: \.rawValue) { effect in
                    Button { onSelectNotchEffect(effect) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: effectSymbol(effect))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(effectColor(effect))
                            Text(effect.title)
                                .font(.system(size: 10, weight: state.notchEffect == effect ? .medium : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .overlay(alignment: .topTrailing) {
                            if state.notchEffect == effect {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(effectColor(effect))
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(PanelButtonStyle(selected: state.notchEffect == effect, tint: effectColor(effect)))
                    .accessibilityLabel(effect.title)
                    .accessibilityAddTraits(state.notchEffect == effect ? .isSelected : [])
                    .accessibilityIdentifier("notch-effect-\(effect.rawValue)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("特效样式")
            .accessibilityIdentifier("notch-effect-style")
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            panelDivider
            dockRow
            pawColors
        }
    }

    private var dockRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("绕 Dock 跑圈")
                    .font(.system(size: 12))
                HStack(spacing: 6) {
                    Text(dockSubtitle)
                        .foregroundStyle(.secondary)
                    if state.showsDockCat && dockSettings.status == .needsAccessibility {
                        Button("授权…") { dockSettings.requestAccessibility() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("allow-dock-access")
                    }
                }
                .font(.system(size: 9))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Toggle("绕 Dock 跑圈", isOn: Binding(get: { state.showsDockCat }, set: { onSelectDock($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityIdentifier("show-dock-cat")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var pawColors: some View {
        HStack(spacing: 7) {
            Text("脚印颜色")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(DockOrbitSettings.trailPresets, id: \.hex) { preset in
                    Button {
                        if let color = DockOrbitSettings.color(hex: preset.hex) { dockSettings.setTrailColor(color) }
                    } label: {
                        Circle()
                            .fill(Color(nsColor: DockOrbitSettings.color(hex: preset.hex)!))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.black.opacity(0.07), lineWidth: 0.5))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(dockSettings.trailColorHex == preset.hex
                                                          ? Color.primary.opacity(0.55) : .clear, lineWidth: 1.2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(dockSettings.trailColorHex == preset.hex ? .isSelected : [])
                }
            }
            Button(action: onCustomizePawColor) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PanelButtonStyle())
            .help("自定义脚印颜色")
            .accessibilityLabel("自定义脚印颜色")
            .accessibilityIdentifier("customize-paw-color")
        }
        .padding(.leading, 38)
        .padding(.trailing, 12)
        .padding(.top, 3)
        .padding(.bottom, 9)
    }

    private var previewButtons: some View {
        HStack(spacing: 8) {
            previewButton("动作预览", symbol: "play.rectangle", action: onPreview)
                .accessibilityIdentifier("open-motion-preview")
            previewButton("特效设置与预览", symbol: "slider.horizontal.3", action: onFlamePreview)
                .accessibilityIdentifier("open-effect-preview")
        }
    }

    private func previewButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(title)
            }
            .font(.system(size: 11))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .buttonStyle(PanelButtonStyle())
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(appVersion)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Button(action: onCheckForUpdates) {
                HStack(spacing: 4) {
                    if updates.availableVersion != nil {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    }
                    Text(updates.availableVersion.map { "更新至 \($0)…" } ?? "检查更新…")
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(updates.availableVersion == nil ? Color.secondary : Color.accentColor)
            .disabled(!updates.canCheckForUpdates)
            .accessibilityIdentifier("check-for-updates")
            Menu("更多") {
                Toggle("自动检查更新", isOn: Binding(get: { updates.automaticallyChecksForUpdates },
                    set: updates.setAutomaticChecks))
                    .accessibilityIdentifier("automatic-update-checks")
                Toggle("自动下载并安装", isOn: Binding(get: { updates.automaticallyDownloadsUpdates },
                    set: updates.setAutomaticDownloads))
                    .disabled(!updates.automaticallyChecksForUpdates)
                    .accessibilityIdentifier("automatic-update-downloads")
                Divider()
                Button("退出 EmberCat", systemImage: "power", action: onQuit)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.mini)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("自动更新设置与退出")
            .accessibilityIdentifier("more-settings")
        }
        .font(.system(size: 10))
        .frame(height: 24)
        .padding(.horizontal, 4)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .map { "v\($0)" } ?? "EmberCat"
    }

    private func effectSymbol(_ effect: NotchEffectStyle) -> String {
        switch effect {
        case .flame: "flame.fill"
        case .matrix: "chevron.left.forwardslash.chevron.right"
        case .lightning: "bolt.fill"
        }
    }

    private func effectColor(_ effect: NotchEffectStyle) -> Color {
        switch effect {
        case .flame: .orange
        case .matrix: colorScheme == .dark ? .mint : Color(red: 0.12, green: 0.52, blue: 0.36)
        case .lightning: colorScheme == .dark ? .yellow : Color(red: 0.68, green: 0.43, blue: 0.08)
        }
    }

    private var sourceSummary: String {
        let sources = viewModel.snapshot.sources.filter { $0.enabled && $0.available }
        return sources.isEmpty ? "正在发现来源" : "\(sources.count) 个来源"
    }

    private var dockSubtitle: String {
        guard state.showsDockCat else { return "黑猫沿 Dock 边缘跑动" }
        switch dockSettings.status {
        case .needsAccessibility: return "需要辅助功能权限"
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

private struct PanelToggleRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    let identifier: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 4)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityIdentifier(identifier)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 36)
    }
}

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.62),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5))
    }
}

private struct PanelButtonStyle: ButtonStyle {
    var selected = false
    var tint: Color = .accentColor
    @PanelHoverState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(selected ? tint.opacity(configuration.isPressed ? 0.20 : 0.11)
                        : Color.primary.opacity(configuration.isPressed ? 0.09 : (hovering ? 0.065 : 0.035)),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? tint.opacity(0.30) : .clear, lineWidth: 0.7))
            .onHover { hovering = $0 }
    }
}
