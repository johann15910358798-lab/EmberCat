import AppKit

/// One transparent surface follows the real notch, including its bottom edge.
@MainActor
final class NotchFlameController {
    private var panel: NSPanel?
    private var flameView: NotchFlameMetalView?
    private var screenObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var isActive = false
    private var lastSpeed: Double = 0
    private var hasDisplay = false

    init() {
        buildPanelIfNeeded()
        positionPanel()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionPanel() }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .emberCatFlameSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionPanel() }
        }
    }

    private func buildPanelIfNeeded() {
        guard panel == nil,
              let geometry = NotchDisplayProfile.current()?.geometry(settings: .shared) else { return }
        do {
            let view = try NotchFlameMetalView(geometry: geometry)
            let panel = NSPanel(contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.contentView = view
            view.onFadeOut = { [weak panel] in panel?.orderOut(nil) }
            self.panel = panel
            flameView = view
        } catch {
            NSLog("EmberCat flame renderer: %@", error.localizedDescription)
        }
    }

    func update(speed: Double, generating: Int) {
        let active = speed > 0.7 || generating > 0
        let wasActive = isActive
        lastSpeed = speed
        isActive = active
        if active && !wasActive { positionPanel() }
        flameView?.setSpeed(speed, active: active && hasDisplay)
    }

    func shutdown() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        screenObserver = nil
        settingsObserver = nil
        flameView?.isPaused = true
        flameView?.onFadeOut = nil
        panel?.orderOut(nil)
        panel = nil
        flameView = nil
    }

    private func positionPanel() {
        guard let profile = NotchDisplayProfile.current() else {
            hasDisplay = false
            flameView?.isPaused = true
            panel?.orderOut(nil)
            return
        }
        hasDisplay = true
        let notch = profile.anchorFrame
        let geometry = profile.geometry(settings: .shared)
        buildPanelIfNeeded()
        guard let panel, let flameView else { return }
        flameView.geometry = geometry
        panel.setFrame(CGRect(x: notch.midX - geometry.size.width/2,
            y: profile.screenFrame.maxY - geometry.size.height,
            width: geometry.size.width, height: geometry.size.height), display: true)
        if isActive {
            panel.orderFrontRegardless()
            flameView.setSpeed(lastSpeed)
        }
    }
}
