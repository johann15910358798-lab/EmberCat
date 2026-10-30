import AppKit
import Darwin

extension Notification.Name {
    static let emberCatFlameSettingsChanged = Notification.Name("EmberCat.FlameSettingsChanged")
}

@MainActor
final class NotchFlameSettings {
    static let shared = NotchFlameSettings()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var widthScale: CGFloat { read("flameWidthScale", range: 0.6...1.5) }
    var heightScale: CGFloat { read("flameHeightScale", range: 0.5...1.8) }

    func set(width: CGFloat, height: CGFloat) {
        defaults.set(Double(clamp(width, range: 0.6...1.5)), forKey: "flameWidthScale")
        defaults.set(Double(clamp(height, range: 0.5...1.8)), forKey: "flameHeightScale")
        NotificationCenter.default.post(name: .emberCatFlameSettingsChanged, object: self)
    }

    func reset() {
        defaults.removeObject(forKey: "flameWidthScale")
        defaults.removeObject(forKey: "flameHeightScale")
        NotificationCenter.default.post(name: .emberCatFlameSettingsChanged, object: self)
    }

    private func read(_ key: String, range: ClosedRange<CGFloat>) -> CGFloat {
        guard defaults.object(forKey: key) != nil else { return 1 }
        return clamp(CGFloat(defaults.double(forKey: key)), range: range)
    }

    private func clamp(_ value: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : 1
    }
}

struct NotchDisplayProfile {
    let model: String
    let screenName: String
    let screenFrame: CGRect
    let notchFrame: CGRect?
    let scale: CGFloat
    let menuBarHeight: CGFloat

    @MainActor static func current() -> NotchDisplayProfile? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        else { return nil }
        let notch: CGRect?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0, right.minX > left.maxX {
            notch = CGRect(x: left.maxX, y: screen.frame.maxY-screen.safeAreaInsets.top,
                width: right.minX-left.maxX, height: screen.safeAreaInsets.top)
        } else {
            notch = nil
        }
        return NotchDisplayProfile(model: modelIdentifier, screenName: screen.localizedName,
            screenFrame: screen.frame, notchFrame: notch, scale: screen.backingScaleFactor,
            menuBarHeight: NSStatusBar.system.thickness)
    }

    var anchorFrame: CGRect {
        if let notchFrame { return notchFrame }
        // On an external display, derive a centered reference from its menu bar.
        // The user's existing flame toggle remains the only visibility preference.
        let width = min(screenFrame.width*0.2,menuBarHeight*7.5)
        return CGRect(x:screenFrame.midX-width/2,y:screenFrame.maxY-menuBarHeight,
            width:width,height:menuBarHeight)
    }

    @MainActor func geometry(settings: NotchFlameSettings) -> NotchFlameGeometry {
        return NotchFlameGeometry(notchWidth: anchorFrame.width, notchHeight: anchorFrame.height,
            widthScale: settings.widthScale, heightScale: settings.heightScale)
    }

    var summary: String {
        let device = "\(model) · \(screenName)"
        guard let notchFrame else { return "\(device) · 无物理刘海 · 按菜单栏尺寸居中显示" }
        return String(format: "%@ · 系统刘海 %.0f × %.0f pt · %.0f× 屏幕", device,
            Double(notchFrame.width), Double(notchFrame.height), Double(scale))
    }

    private static var modelIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
