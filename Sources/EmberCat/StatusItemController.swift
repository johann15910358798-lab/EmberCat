import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let viewModel: SpeedMonitorModel
    private let defaults: UserDefaults
    private let menu = NSMenu()
    private let speedMenuItem = NSMenuItem(title: "0.0 tok/s · 待机", action: nil, keyEquivalent: "")
    private let sourceMenuItem = NSMenuItem(title: "已发现来源 · 0", action: nil, keyEquivalent: "")
    private var styleMenuItems: [PetStyle: NSMenuItem] = [:]
    private var displayMenuItems: [NSMenuItem] = []
    private var showsTokenRate: Bool
    private var style: PetStyle
    private var director = MotionDirector()
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var lastTickUptime = ProcessInfo.processInfo.systemUptime
    private var displayedFrame: FrameKey?
    private var bag: Set<AnyCancellable> = []
    private var preview: MotionPreviewController?

    private struct FrameKey: Equatable {
        let style: PetStyle
        let mode: String
        let transition: String
        let index: Int
    }

    init(viewModel: SpeedMonitorModel, defaults: UserDefaults = .standard) {
        self.viewModel = viewModel
        self.defaults = defaults
        self.style = defaults.string(forKey: "petStyle").flatMap(PetStyle.init(rawValue:)) ?? .cat
        self.showsTokenRate = defaults.bool(forKey: "showsTokenRate")
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        configureMenu()
        observeViewModel()
        applyFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        timerInterval = nil
        bag.removeAll()
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.cell?.wraps = false
        button.cell?.usesSingleLineMode = true
        button.setAccessibilityLabel("EmberCat")
        button.target = self
        button.action = #selector(handleStatusClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateRateLabel()
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        let titleItem = NSMenuItem(title: "EmberCat", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        speedMenuItem.isEnabled = false
        menu.addItem(speedMenuItem)
        sourceMenuItem.isEnabled = false
        menu.addItem(sourceMenuItem)
        menu.addItem(.separator())

        let displayItem = NSMenuItem(title: "菜单栏显示", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu(title: "菜单栏显示")
        displayMenu.autoenablesItems = false
        for (title, showsRate) in [("人物 + 实时速度（tok/s）", true), ("仅人物（紧凑）", false)] {
            let item = NSMenuItem(title: title, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = showsRate ? 1 : 0
            item.state = showsRate == showsTokenRate ? .on : .off
            displayMenu.addItem(item)
            displayMenuItems.append(item)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        let stylesItem = NSMenuItem(title: "形象", action: nil, keyEquivalent: "")
        let stylesMenu = NSMenu(title: "形象")
        stylesMenu.autoenablesItems = false
        for pet in PetStyle.allCases {
            let item = NSMenuItem(title: pet.displayName, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.rawValue
            item.state = pet == style ? .on : .off
            stylesMenu.addItem(item)
            styleMenuItems[pet] = item
        }
        stylesItem.submenu = stylesMenu
        menu.addItem(stylesItem)

        let previewItem = NSMenuItem(title: "动作预览…", action: #selector(showPreview), keyEquivalent: "")
        previewItem.target = self
        menu.addItem(previewItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 EmberCat", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func observeViewModel() {
        Publishers.CombineLatest(viewModel.$speed, viewModel.$sourceCount)
            .sink { [weak self] speed, sourceCount in
                guard let self else { return }
                // Published values arrive before their stored properties change.
                updateSpeed(speed)
                updateMenuTitle()
                sourceMenuItem.title = "已发现来源 · \(sourceCount)"
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

    private func updateMenuTitle() {
        speedMenuItem.title = String(format: "%.1f tok/s · %@", director.rawSpeed, motionTitle)
    }

    private func updateTimer() {
        guard style == .cat ? director.cat.needsTicks : director.needsTicks else {
            timer?.invalidate()
            timer = nil
            timerInterval = nil
            return
        }

        // Also advances confirmation timers and hand-drawn transition frames.
        let interval = style == .cat ? 1.0 / 60.0 : 1.0 / 30.0
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

    @objc private func handleStatusClick(_ sender: Any?) {
        guard statusItem.menu == nil else { return }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
        statusItem.button?.highlight(false)
        statusItem.button?.state = .off
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        let selected = sender.tag == 1
        guard selected != showsTokenRate else { return }
        showsTokenRate = selected
        defaults.set(selected, forKey: "showsTokenRate")
        for item in displayMenuItems { item.state = (item.tag == 1) == selected ? .on : .off }
        updateRateLabel()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selected = PetStyle(rawValue: rawValue), selected != style else { return }
        advanceMotion()
        style = selected
        defaults.set(style.rawValue, forKey: "petStyle")
        for (pet, item) in styleMenuItems { item.state = pet == style ? .on : .off }
        updateTimer()
        updateMenuTitle()
        updateToolTip()
        applyFrame()
    }

    @objc private func showPreview() {
        if preview == nil { preview = MotionPreviewController(style: style) }
        preview?.showWindow(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func advanceMotion() {
        let now = ProcessInfo.processInfo.systemUptime
        director.advance(by: max(0, now - lastTickUptime))
        lastTickUptime = now
    }

    private func tick() {
        advanceMotion()
        updateTimer()
        updateMenuTitle()
        updateToolTip()
        applyFrame()
    }

    private func applyFrame() {
        let count = style == .cat ? director.cat.gait.frameCount : director.mode.frameCount
        let active = style == .makima ? director.transition : nil
        let transitionKey = active.map { "\($0.from.rawValue)_\($0.to.rawValue)_\(Int($0.progress * 30))" } ?? ""
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
