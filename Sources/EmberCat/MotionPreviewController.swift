import AppKit

private final class PixelImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image, let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide < $1.pixelsWide }), let mask = bitmap.cgImage,
            let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(bounds.width / CGFloat(mask.width), bounds.height / CGFloat(mask.height))
        let rect = CGRect(x: (bounds.width-CGFloat(mask.width)*scale)/2,
            y: (bounds.height-CGFloat(mask.height)*scale)/2,
            width: CGFloat(mask.width)*scale, height: CGFloat(mask.height)*scale)
        context.saveGState()
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
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
    private let enlarged = PixelImageView()
    private let stateLabel = NSTextField(labelWithString: "待机")
    private let speedLabel = NSTextField(labelWithString: "0.0 tok/s")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 220, target: nil, action: nil)
    private var timer: Timer?
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var demoStart: Double?
    private enum Demo { case all, jitter, jumps }
    private var demo: Demo = .all
    private let speeds: [Double] = [0, 3, 12, 24, 36, 50, 67.6, 91, 125, 185]

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 570),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "EmberCat · 动作预览"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        lastTime = ProcessInfo.processInfo.systemUptime
        if timer == nil {
            let timer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "速度突然变了，也能自然换个动作。")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "速度决定出行方式，每个动作保持固定节奏。预览使用模拟速度。")
        subtitle.textColor = .secondaryLabelColor
        let styles = NSSegmentedControl(labels: ["胖黑猫", "玛奇玛"], trackingMode: .selectOne,
            target: self, action: #selector(changeStyle(_:)))
        styles.selectedSegment = 1
        stateLabel.font = .systemFont(ofSize: 18, weight: .medium)
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        actual.imageScaling = .scaleNone
        actual.setContentHuggingPriority(.required, for: .horizontal)
        actual.translatesAutoresizingMaskIntoConstraints = false
        actual.widthAnchor.constraint(equalToConstant: 72).isActive = true
        enlarged.imageScaling = .scaleProportionallyUpOrDown
        enlarged.translatesAutoresizingMaskIntoConstraints = false
        enlarged.widthAnchor.constraint(equalToConstant: 288).isActive = true
        enlarged.heightAnchor.constraint(equalToConstant: 160).isActive = true
        let actualBox = NSStackView(views: [actual, NSTextField(labelWithString: "菜单栏实际尺寸")])
        let enlargedBox = NSStackView(views: [enlarged, NSTextField(labelWithString: "动作放大查看")])
        for box in [actualBox, enlargedBox] { box.orientation = .vertical; box.alignment = .centerX }
        actual.heightAnchor.constraint(equalToConstant: 160).isActive = true
        let images = NSStackView(views: [actualBox, enlargedBox])
        images.orientation = .horizontal
        images.alignment = .centerY
        images.spacing = 60
        slider.target = self
        slider.action = #selector(changeSpeed(_:))
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 700).isActive = true
        var rows: [NSStackView] = []
        for start in stride(from: 0, to: SpeedTier.allCases.count, by: 5) {
            let buttons = SpeedTier.allCases[start..<min(start+5, SpeedTier.allCases.count)].map { mode in
                let button = NSButton(title: mode.compactTitle, target: self, action: #selector(selectMode(_:)))
                button.tag = mode.rank
                button.widthAnchor.constraint(equalToConstant: 128).isActive = true
                return button
            }
            let row = NSStackView(views: buttons)
            row.spacing = 10
            rows.append(row)
        }
        let play = NSButton(title: "播放全套升降档", target: self, action: #selector(playAll))
        let shake = NSButton(title: "演示边界防抖", target: self, action: #selector(playJitter))
        let jump = NSButton(title: "演示 3 ↔ 70 跳速", target: self, action: #selector(playJumps))
        let stop = NSButton(title: "停止演示", target: self, action: #selector(stopDemo))
        let actions = NSStackView(views: [play, jump, shake, stop])
        actions.spacing = 16
        let hint = NSTextField(labelWithString: "升降档有防振区间、持续确认与最短停留；已开始的过渡会完整播放。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let views: [NSView] = [title, subtitle, styles, images, stateLabel,
            speedLabel, slider] + rows + [actions, hint]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22)])
        render()
    }

    @objc private func changeStyle(_ sender: NSSegmentedControl) {
        style = sender.selectedSegment == 0 ? .cat : .makima
        render()
    }

    @objc private func changeSpeed(_ sender: NSSlider) {
        demoStart = nil
        director.setSpeed(sender.doubleValue)
    }

    @objc private func selectMode(_ sender: NSButton) {
        demoStart = nil
        slider.doubleValue = speeds[sender.tag]
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
                slider.doubleValue = t < 8 ? 24 : t < 22 ? 30 + 2*sin(t*12)
                    : t < 30 ? 38 : t < 42 ? 30 + 2*sin(t*12) : 24
            case .all:
                let index = Int(elapsed/6).quotientAndRemainder(dividingBy: 18).remainder
                slider.doubleValue = speeds[index <= 9 ? index : 18-index]
            case .jumps:
                let t = elapsed.truncatingRemainder(dividingBy: 30)
                slider.doubleValue = t < 4 ? 3 : t < 9 ? 70 : t < 15 ? 3 : t < 21 ? 185 : 0
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
        enlarged.image = image
        actual.contentTintColor = .labelColor
        enlarged.contentTintColor = .labelColor
        speedLabel.stringValue = String(format: "%.1f tok/s", director.rawSpeed)
        let state = style == .cat ? (director.mode == .idle && director.transition == nil ? "待机" : "跑动") : director.title
        stateLabel.stringValue = "\(style.displayName) · \(state)" + (director.pending == nil ? "" : " · 确认中")
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
