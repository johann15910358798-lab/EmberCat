import AppKit
@preconcurrency import ApplicationServices
import Combine

extension Notification.Name {
    static let emberCatDockSettingsChanged = Notification.Name("EmberCat.DockSettingsChanged")
    static let emberCatDockTrailColorChanged = Notification.Name("EmberCat.DockTrailColorChanged")
}

@MainActor
final class DockOrbitSettings: ObservableObject {
    enum Status { case disabled, following, waitingForDock, needsAccessibility }
    static let shared = DockOrbitSettings()
    static let trailPresets: [(name: String, hex: String)] = [
        ("荧光青", "#52FFE0"), ("电光蓝", "#57C7FF"), ("荧光紫", "#B49AFF"),
        ("荧光粉", "#FF79CE"), ("荧光绿", "#BFFF58"),
    ]
    private let defaults: UserDefaults
    @Published var status: Status = .disabled
    @Published private(set) var trailColorHex: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "dockPawColor")?.uppercased() ?? ""
        trailColorHex = Self.color(hex: saved) == nil ? Self.trailPresets[0].hex : saved
    }

    var trailColor: NSColor { Self.color(hex: trailColorHex)! }

    func setTrailColor(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return }
        let bytes = components.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        let hex = String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
        guard hex != trailColorHex else { return }
        trailColorHex = hex
        defaults.set(hex, forKey: "dockPawColor")
        NotificationCenter.default.post(name: .emberCatDockTrailColorChanged, object: self)
    }

    static func color(hex: String) -> NSColor? {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: "dockOrbitEnabled") }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: "dockOrbitEnabled")
            NotificationCenter.default.post(name: .emberCatDockSettingsChanged, object: self)
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
