import AppKit

private final class DetailImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image, let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide < $1.pixelsWide }), let mask = bitmap.cgImage,
            let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(bounds.width / CGFloat(mask.width), bounds.height / CGFloat(mask.height))
        let rect = CGRect(x: (bounds.width-CGFloat(mask.width)*scale)/2,
            y: (bounds.height-CGFloat(mask.height)*scale)/2,
            width: CGFloat(mask.width)*scale, height: CGFloat(mask.height)*scale)
        context.saveGState()
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.clip(to: rect, mask: mask)
        context.setFillColor(NSColor.labelColor.cgColor)
        context.fill(rect)
        context.restoreGState()
    }
}

/// A controllable preview of the production director and sprite renderer.
@MainActor
final class MotionPreviewController: NSWindowController {
    private var director = MotionDirector()
    private var style: PetStyle = .makima
    private let actual = NSImageView()
    private let enlarged = DetailImageView()
    private let stateLabel = NSTextField(labelWithString: "待机")
    private let speedLabel = NSTextField(labelWithString: "0.0 tok/s")
    private let subtitle = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let catButtons = NSStackView()
    private let makimaButtons = NSStackView()
    private let playButton = NSButton(title: "播放平滑加减速", target: nil, action: nil)
    private let jumpButton = NSButton(title: "演示突然跳速", target: nil, action: nil)
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 220, target: nil, action: nil)
    private var timer: Timer?
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var demoStart: Double?
    private enum Demo { case all, jitter, jumps }
    private var demo: Demo = .all
    private let speeds: [Double] = [0, 3, 12, 24, 36, 50, 67.6, 91, 125, 185]
    private let catSpeeds: [Double] = [0, 8, 45, 140]

    init(style: PetStyle? = nil) {
        let walkStudy = CommandLine.arguments.contains("--preview-pixelfx-walk")
            || Bundle.main.object(forInfoDictionaryKey: "EmberCatPixelFXWalkPreview") as? Bool == true
        let vehicleStudy = CommandLine.arguments.contains("--preview-pixelfx-vehicles")
            || Bundle.main.object(forInfoDictionaryKey: "EmberCatPixelFXVehiclePreview") as? Bool == true
        let suiteStudy = CommandLine.arguments.contains("--preview-pixelfx-suite")
            || Bundle.main.object(forInfoDictionaryKey: "EmberCatPixelFXSuitePreview") as? Bool == true
        self.style = style ?? (walkStudy || vehicleStudy || suiteStudy ? .makima
            : UserDefaults.standard.string(forKey: "petStyle").flatMap(PetStyle.init(rawValue:)) ?? .cat)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 640),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "EmberCat · 动作预览"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        buildContent()
        if walkStudy || vehicleStudy || suiteStudy {
            window.title = suiteStudy ? "EmberCat · 玛奇玛整套动作预览"
                : vehicleStudy ? "EmberCat · 玛奇玛车辆试作" : "EmberCat · 玛奇玛走路试作"
            slider.doubleValue = vehicleStudy ? 91 : 3
            director.setSpeed(slider.doubleValue)
            for _ in 0..<360 { director.advance(by: 1.0/60) }
            render()
            if suiteStudy { demo = .all; demoStart = ProcessInfo.processInfo.systemUptime }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        lastTime = ProcessInfo.processInfo.systemUptime
        if timer == nil {
            let timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "动作与速度")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        subtitle.textColor = .secondaryLabelColor
        let styles = NSSegmentedControl(labels: ["胖黑猫", "玛奇玛"], trackingMode: .selectOne,
            target: self, action: #selector(changeStyle(_:)))
        styles.selectedSegment = style == .cat ? 0 : 1
        stateLabel.font = .systemFont(ofSize: 18, weight: .medium)
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        actual.imageScaling = .scaleNone
        actual.setContentHuggingPriority(.required, for: .horizontal)
        actual.translatesAutoresizingMaskIntoConstraints = false
        actual.widthAnchor.constraint(equalToConstant: 72).isActive = true
        enlarged.imageScaling = .scaleProportionallyUpOrDown
        enlarged.translatesAutoresizingMaskIntoConstraints = false
        enlarged.widthAnchor.constraint(equalToConstant: 252).isActive = true
        enlarged.heightAnchor.constraint(equalToConstant: 140).isActive = true
        let actualBox = NSStackView(views: [actual, NSTextField(labelWithString: "菜单栏实际尺寸")])
        let enlargedBox = NSStackView(views: [enlarged, NSTextField(labelWithString: "动作放大查看")])
        for box in [actualBox, enlargedBox] { box.orientation = .vertical; box.alignment = .centerX }
        actual.heightAnchor.constraint(equalToConstant: 140).isActive = true
        let images = NSStackView(views: [actualBox, enlargedBox])
        images.orientation = .horizontal
        images.alignment = .centerY
        images.spacing = 60
        slider.target = self
        slider.action = #selector(changeSpeed(_:))
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 700).isActive = true
        catButtons.spacing = 12
        for gait in CatGait.allCases {
            let button = NSButton(title: gait.title, target: self, action: #selector(selectMode(_:)))
            button.tag = gait.rank
            button.widthAnchor.constraint(equalToConstant: 140).isActive = true
            catButtons.addArrangedSubview(button)
        }
        makimaButtons.orientation = .vertical
        makimaButtons.spacing = 10
        for start in stride(from: 0, to: SpeedTier.allCases.count, by: 5) {
            let buttons = SpeedTier.allCases[start..<min(start+5, SpeedTier.allCases.count)].map { mode in
                let button = NSButton(title: mode.compactTitle, target: self, action: #selector(selectMode(_:)))
                button.tag = mode.rank
                button.widthAnchor.constraint(equalToConstant: 128).isActive = true
                return button
            }
            let row = NSStackView(views: buttons)
            row.spacing = 10
            makimaButtons.addArrangedSubview(row)
        }
        playButton.target = self
        playButton.action = #selector(playAll)
        let shake = NSButton(title: "演示边界防抖", target: self, action: #selector(playJitter))
        jumpButton.target = self
        jumpButton.action = #selector(playJumps)
        let stop = NSButton(title: "停止演示", target: self, action: #selector(stopDemo))
        let actions = NSStackView(views: [playButton, jumpButton, shake, stop])
        actions.spacing = 16
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let views: [NSView] = [title, subtitle, styles, images, stateLabel,
            speedLabel, slider, catButtons, makimaButtons, actions, hint]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22)])
        updateStyleControls()
        render()
    }

    @objc private func changeStyle(_ sender: NSSegmentedControl) {
        style = sender.selectedSegment == 0 ? .cat : .makima
        demoStart = nil
        updateStyleControls()
        render()
    }

    private func updateStyleControls() {
        catButtons.isHidden = style != .cat
        makimaButtons.isHidden = style != .makima
        subtitle.stringValue = style == .cat
            ? "站立、行走、跑动、蜷成球滚动；随 tok/s 平滑加减速。预览使用模拟速度。"
            : "九种连续动作，补齐蹬地、踩踏、转轮、扬尘与喷流。预览使用模拟速度。"
        hint.stringValue = style == .cat
            ? "蜷起后整圈翻滚；减速时转正、展开落地。菜单栏继续使用真实速度。"
            : "升降档有防振区间、持续确认与最短停留；已开始的过渡会完整播放。"
        playButton.title = style == .cat ? "播放平滑加减速" : "播放全套升降档"
        jumpButton.title = style == .cat ? "演示 3 → 140 → 0" : "演示 3 ↔ 70 跳速"
    }

    @objc private func changeSpeed(_ sender: NSSlider) {
        demoStart = nil
        director.setSpeed(sender.doubleValue)
    }

    @objc private func selectMode(_ sender: NSButton) {
        demoStart = nil
        slider.doubleValue = (style == .cat ? catSpeeds : speeds)[sender.tag]
        director.setSpeed(slider.doubleValue)
    }

    @objc private func playAll() { demo = .all; demoStart = ProcessInfo.processInfo.systemUptime }
    @objc private func playJitter() { demo = .jitter; demoStart = ProcessInfo.processInfo.systemUptime }
    @objc private func playJumps() {
        director = MotionDirector()
        demo = .jumps
        demoStart = ProcessInfo.processInfo.systemUptime
    }
    @objc private func stopDemo() { demoStart = nil; slider.doubleValue = 0; director.setSpeed(0) }

    private func tick() {
        guard window?.isVisible == true else { timer?.invalidate(); timer = nil; return }
        let now = ProcessInfo.processInfo.systemUptime
        if let start = demoStart {
            let elapsed = now - start
            switch demo {
            case .jitter:
                let t = elapsed.truncatingRemainder(dividingBy: 48)
                if style == .cat {
                    slider.doubleValue = t < 8 ? 45 : t < 22 ? 80 + 4*sin(t*12)
                        : t < 30 ? 140 : t < 42 ? 80 + 4*sin(t*12) : 45
                } else {
                    slider.doubleValue = t < 8 ? 24 : t < 22 ? 30 + 2*sin(t*12)
                        : t < 30 ? 38 : t < 42 ? 30 + 2*sin(t*12) : 24
                }
            case .all:
                if style == .cat {
                    let t = elapsed.truncatingRemainder(dividingBy: 36)
                    slider.doubleValue = t < 2 ? 0 : t < 16 ? (t-2)/14*160
                        : t < 22 ? 160 : t < 30 ? (30-t)/8*160 : 0
                } else {
                    let index = Int(elapsed/6).quotientAndRemainder(dividingBy: 18).remainder
                    slider.doubleValue = speeds[index <= 9 ? index : 18-index]
                }
            case .jumps:
                let t = elapsed.truncatingRemainder(dividingBy: 30)
                slider.doubleValue = style == .cat
                    ? (t < 5 ? 3 : t < 17 ? 140 : 0)
                    : (t < 4 ? 3 : t < 9 ? 70 : t < 15 ? 3 : t < 21 ? 185 : 0)
            }
            director.setSpeed(slider.doubleValue)
        }
        director.advance(by: max(0, now-lastTime))
        lastTime = now
        render()
    }

    private func render() {
        let image = SpriteLibrary.shared.image(for: style, director: director)
        actual.image = image
        enlarged.image = SpriteLibrary.shared.previewImage(for: style, director: director)
        actual.contentTintColor = .labelColor
        enlarged.contentTintColor = .labelColor
        speedLabel.stringValue = String(format: "%.1f tok/s", director.rawSpeed)
        let state = style == .cat ? director.cat.title : director.title
        stateLabel.stringValue = "\(style.displayName) · \(state)"
            + (style == .makima && director.pending != nil ? " · 确认中" : "")
    }
}

@MainActor
final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var preview: MotionPreviewController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        preview = MotionPreviewController()
        preview?.showWindow(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
