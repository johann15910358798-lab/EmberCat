import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let viewModel: SpeedMonitorModel
    private let updates: AppUpdateController
    private let defaults: UserDefaults
    private let flameSettings: NotchFlameSettings
    private let dockSettings: DockOrbitSettings
    private let panelState: StatusPanelState
    private var showsTokenRate: Bool { panelState.showsTokenRate }
    private var style: PetStyle { panelState.style }
    private var director = MotionDirector()
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var lastTickUptime = ProcessInfo.processInfo.systemUptime
    private var displayedFrame: FrameKey?
    private var bag: Set<AnyCancellable> = []
    private var preview: MotionPreviewController?
    private var flamePreview: NotchFlamePreviewController?
    private var menuPopover: NSPopover?
    private var pawColorPanel: NSColorPanel?

    private struct FrameKey: Equatable {
        let style: PetStyle
        let mode: String
        let transition: String
        let index: Int
    }

    init(viewModel: SpeedMonitorModel, updates: AppUpdateController, defaults: UserDefaults = .standard,
         flameSettings: NotchFlameSettings = .shared, dockSettings: DockOrbitSettings = .shared) {
        self.viewModel = viewModel
        self.updates = updates
        self.defaults = defaults
        self.flameSettings = flameSettings
        self.dockSettings = dockSettings
        self.panelState = StatusPanelState(
            style: defaults.string(forKey: "petStyle").flatMap(PetStyle.init(rawValue:)) ?? .cat,
            showsTokenRate: defaults.bool(forKey: "showsTokenRate"),
            showsNotchFlame: flameSettings.isEnabled,
            showsDockCat: dockSettings.isEnabled, notchEffect: flameSettings.effect)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        observeViewModel()
        applyFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        timerInterval = nil
        bag.removeAll()
        menuPopover?.close()
        menuPopover = nil
        flamePreview?.close()
        flamePreview = nil
        pawColorPanel?.close()
        pawColorPanel?.setTarget(nil)
        pawColorPanel?.setAction(nil)
        pawColorPanel = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        (button.cell as? NSButtonCell)?.highlightsBy = []
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.cell?.wraps = false
        button.cell?.usesSingleLineMode = true
        button.setAccessibilityLabel("EmberCat")
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateRateLabel()
    }

    private func observeViewModel() {
        viewModel.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                updateSpeed(max(0, snapshot.live.output))
                updateToolTip()
            }
            .store(in: &bag)
    }

    private func updateSpeed(_ speed: Double) {
        advanceMotion()
        director.setSpeed(speed)
        updateRateLabel()
        updateTimer()
        applyFrame()
    }

    private func updateRateLabel() {
        guard let button = statusItem.button else { return }
        button.title = showsTokenRate ? String(format: "%.1f tok/s", director.rawSpeed) : ""
        button.imagePosition = showsTokenRate ? .imageLeading : .imageOnly
        updateStatusItemWidth()
    }

    private func updateStatusItemWidth() {
        guard let button = statusItem.button else { return }
        let imageWidth = button.image?.size.width ?? 18
        let titleWidth = showsTokenRate
            ? ceil((button.title as NSString).size(withAttributes: [.font: button.font!]).width) : 0
        // AppKit's automatic status-item width adds more padding than this compact layout needs.
        statusItem.length = imageWidth + (showsTokenRate ? titleWidth + 4 : 0) + 8
    }

    private func updateToolTip() {
        statusItem.button?.toolTip = String(format: "EmberCat · %@ · %.1f tok/s · %@", style.displayName, director.rawSpeed, motionTitle)
    }

    private var motionTitle: String {
        style == .cat ? director.cat.title : director.title
    }

    private func updateTimer() {
        guard style == .cat ? director.cat.needsTicks : director.needsTicks else {
            timer?.invalidate()
            timer = nil
            timerInterval = nil
            return
        }

        // Also advances confirmation timers and hand-drawn transition frames.
        let interval = 1.0 / 60.0
        guard timer == nil || timerInterval != interval else { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        timerInterval = interval
    }

    @objc private func togglePanel(_ sender: Any?) {
        if menuPopover?.isShown == true {
            menuPopover?.close()
            return
        }
        showMenu()
    }

    func showMenu() {
        guard menuPopover?.isShown != true else { return }
        guard let button = statusItem.button else { return }
        if menuPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.delegate = self
            let host = NSHostingController(rootView: StatusPanelView(
                viewModel: viewModel, state: panelState, dockSettings: dockSettings, updates: updates,
                onNavigate: { [weak self] in self?.navigate(to: $0) },
                onSelectStyle: { [weak self] in self?.selectStyle($0) },
                onSelectDisplay: { [weak self] in self?.selectDisplayMode($0) },
                onSelectFlame: { [weak self] in self?.selectFlame($0) },
                onSelectNotchEffect: { [weak self] in self?.selectNotchEffect($0) },
                onSelectDock: { [weak self] in self?.selectDock($0) },
                onCustomizePawColor: { [weak self] in self?.showPawColorPicker() },
                onPreview: { [weak self] in self?.showPreview() },
                onFlamePreview: { [weak self] in self?.showFlamePreview() },
                onCheckForUpdates: { [weak self] in
                    self?.menuPopover?.close()
                    self?.updates.checkForUpdates()
                },
                onClose: { [weak self] in self?.menuPopover?.close() },
                onQuit: { NSApplication.shared.terminate(nil) }))
            // One popover owns both pages. Its native size animation keeps the
            // anchor and surface continuous while SwiftUI transitions the content.
            host.sizingOptions = []
            host.view.frame = NSRect(origin: .zero, size: StatusPanelState.Page.menu.size)
            popover.contentViewController = host
            menuPopover = popover
        }
        panelState.page = .menu
        panelState.notchEffect = flameSettings.effect
        panelState.showsNotchFlame = flameSettings.isEnabled
        menuPopover?.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        menuPopover?.contentSize = StatusPanelState.Page.menu.size
        button.highlight(false)
        NSApp.activate()
        menuPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        menuPopover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    private func navigate(to page: StatusPanelState.Page) {
        guard page != panelState.page else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        menuPopover?.animates = !reduceMotion
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
            panelState.page = page
        }
        menuPopover?.contentSize = page.size
    }

    func popoverDidClose(_ notification: Notification) {
        panelState.page = .menu
        statusItem.button?.highlight(false)
        statusItem.button?.state = .off
    }

    private func selectDisplayMode(_ selected: Bool) {
        guard selected != showsTokenRate else { return }
        panelState.showsTokenRate = selected
        defaults.set(selected, forKey: "showsTokenRate")
        updateRateLabel()
    }

    private func selectStyle(_ selected: PetStyle) {
        guard selected != style else { return }
        advanceMotion()
        panelState.style = selected
        defaults.set(style.rawValue, forKey: "petStyle")
        updateTimer()
        updateToolTip()
        applyFrame()
    }

    @objc private func showPreview() {
        menuPopover?.close()
        if preview == nil { preview = MotionPreviewController(style: style) }
        preview?.showWindow(nil)
    }

    private func selectFlame(_ enabled: Bool) {
        panelState.showsNotchFlame = enabled
        flameSettings.isEnabled = enabled
    }

    private func selectNotchEffect(_ effect: NotchEffectStyle) {
        panelState.notchEffect = effect
        flameSettings.effect = effect
    }

    private func showFlamePreview() {
        menuPopover?.close()
        pawColorPanel?.orderOut(nil)
        pawColorPanel?.setTarget(nil)
        pawColorPanel?.setAction(nil)
        pawColorPanel = nil
        do {
            if flamePreview == nil { flamePreview = try NotchFlamePreviewController(settings: flameSettings) }
            flamePreview?.selectEffect(flameSettings.effect)
            flamePreview?.showWindow(nil)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func selectDock(_ enabled: Bool) {
        panelState.showsDockCat = enabled
        dockSettings.isEnabled = enabled
    }

    private func showPawColorPicker() {
        menuPopover?.close()
        flamePreview?.deactivateColorWells()
        let panel = NSColorPanel.shared
        panel.title = "脚印荧光色"
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = dockSettings.trailColor
        panel.setTarget(self)
        panel.setAction(#selector(changePawColor(_:)))
        pawColorPanel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changePawColor(_ panel: NSColorPanel) {
        dockSettings.setTrailColor(panel.color)
    }

    private func advanceMotion() {
        let now = ProcessInfo.processInfo.systemUptime
        director.advance(by: max(0, now - lastTickUptime))
        lastTickUptime = now
    }

    private func tick() {
        advanceMotion()
        updateTimer()
        updateToolTip()
        applyFrame()
    }

    private func applyFrame() {
        let count = style == .cat ? director.cat.gait.frameCount : director.mode.frameCount
        let active = style == .makima ? director.transition : nil
        let transitionKey = active.map { "\($0.from.rawValue)_\($0.to.rawValue)_\(Int($0.elapsed * 60 + 1e-9))" } ?? ""
        let index = director.clock.frameIndex(frameCount: count, cycleDuration: director.mode.cycleDuration)
        let key = style == .cat
            ? FrameKey(style: style, mode: director.cat.frameKey, transition: "", index: 0)
            : FrameKey(style: style, mode: director.mode.rawValue, transition: transitionKey, index: index)
        guard key != displayedFrame else { return }
        displayedFrame = key
        guard let image = SpriteLibrary.shared.menuBarImage(for: style, director: director) else {
            statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "EmberCat")
            updateStatusItemWidth()
            return
        }
        statusItem.button?.image = image
        updateStatusItemWidth()
    }
}
