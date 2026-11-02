import AgentSpeedCore
import AppKit
import SwiftUI

extension SourceKind {
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .claudeDesktop: "Claude Desktop"
        case .deepseek: "DeepSeek"
        case .opencode: "OpenCode"
        case .gemini: "Gemini CLI"
        case .omp: "oh-my-pi"
        case .antigravity: "Antigravity"
        case .workbuddy: "WorkBuddy"
        case .workbuddyAi: "WorkBuddy AI"
        case .zcode: "ZCode"
        case .kimi: "Kimi Code"
        case .grokBuild: "Grok Build"
        }
    }

    fileprivate var desktopBundleID: String? {
        switch self {
        case .codex: "com.openai.codex"
        case .claudeDesktop: "com.anthropic.claudefordesktop"
        case .antigravity: "com.google.antigravity"
        default: nil
        }
    }

    fileprivate var iconName: String { self == .workbuddyAi ? "workbuddy" : rawValue }
}

@MainActor
final class SourceIconLibrary {
    static let shared = SourceIconLibrary()
    private var cache: [SourceKind: NSImage] = [:]
    private let resourceDirectory: URL?
    private let usesInstalledApplications: Bool

    init(resourceDirectory: URL? = AppResources.directory("SourceIcons"),
         usesInstalledApplications: Bool = true) {
        self.resourceDirectory = resourceDirectory
        self.usesInstalledApplications = usesInstalledApplications
    }

    func image(for source: SourceKind) -> NSImage {
        if let image = cache[source] { return image }
        let image = load(source)
        cache[source] = image
        return image
    }

    func bundledImage(for source: SourceKind) -> NSImage? {
        guard let url = resourceDirectory?.appendingPathComponent(source.iconName + ".png"),
              let image = NSImage(contentsOf: url), image.isValid else { return nil }
        image.isTemplate = source == .opencode || source == .grokBuild
        return image
    }

    private func load(_ source: SourceKind) -> NSImage {
        if usesInstalledApplications, let bundleID = source.desktopBundleID,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: app.path)
        }
        if let image = bundledImage(for: source) { return image }
        let appNames = source == .zcode ? ["ZCode", "Zcode"] : [source.displayName]
        for name in usesInstalledApplications ? appNames : [] {
            for root in [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
                let url = root.appendingPathComponent(name + ".app")
                if FileManager.default.fileExists(atPath: url.path) {
                    return NSWorkspace.shared.icon(forFile: url.path)
                }
            }
        }
        return NSImage(systemSymbolName: "terminal", accessibilityDescription: source.displayName) ?? NSImage()
    }
}

@MainActor
struct SourceIconView: View {
    let source: SourceKind
    var size: CGFloat = 26

    var body: some View {
        Image(nsImage: SourceIconLibrary.shared.image(for: source))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
