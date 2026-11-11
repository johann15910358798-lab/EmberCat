import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FlamePreviewBackground: CaseIterable {
    case dark, white, multicolor
    var matrixColorScheme: NotchMatrixColorScheme? {
        switch self {
        case .dark: .dark
        case .white: .light
        case .multicolor: nil
        }
    }
    var title: String {
        switch self {
        case .dark: "深色背景"
        case .white: "纯白背景"
        case .multicolor: "多色背景"
        }
    }
    @MainActor func draw(in rect: CGRect) {
        switch self {
        case .dark:
            NSColor(srgbRed: 0.045, green: 0.055, blue: 0.08, alpha: 1).setFill()
            rect.fill()
        case .white:
            NSColor.white.setFill()
            rect.fill()
        case .multicolor:
            let colors: [NSColor] = [
                NSColor(srgbRed: 0.90, green: 0.75, blue: 0.37, alpha: 1),
                NSColor(srgbRed: 0.16, green: 0.32, blue: 0.48, alpha: 1),
                NSColor(srgbRed: 0.44, green: 0.78, blue: 0.70, alpha: 1),
                NSColor(srgbRed: 0.76, green: 0.32, blue: 0.42, alpha: 1),
            ]
            for row in 0...Int(rect.height / 24) {
                for column in 0...Int(rect.width / 32) {
                    colors[(row + column) % colors.count].setFill()
                    CGRect(x: rect.minX + CGFloat(column * 32), y: rect.minY + CGFloat(row * 24),
                        width: 32, height: 24).intersection(rect).fill()
                }
            }
        }
    }
}

@MainActor
private final class FlamePreviewScene: NSView {
    let flame: NotchFlameMetalView
    let background: FlamePreviewBackground
    override var isFlipped: Bool { true }

    init(geometry: NotchFlameGeometry, renderer: NotchFlameRenderer, background: FlamePreviewBackground) throws {
        self.background = background
        flame = try NotchFlameMetalView(geometry: geometry, renderer: renderer)
        flame.matrixColorSchemeOverride = background.matrixColorScheme
        super.init(frame: CGRect(x: 0, y: 0, width: 280, height: 168))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(flame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 280).isActive = true
        heightAnchor.constraint(equalToConstant: 168).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(geometry: NotchFlameGeometry) {
        flame.geometry = geometry
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let size = flame.geometry.size
        let scale = min(1,(bounds.width-24)/size.width,(bounds.height-12)/size.height)
        flame.frame = CGRect(x: (bounds.width-size.width*scale)/2, y: 0,
            width: size.width*scale, height: size.height*scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        background.draw(in: bounds)
        let geometry = flame.geometry
        let scale = flame.frame.width/geometry.size.width
        let notch = CGRect(x: flame.frame.minX+geometry.notch.minX*scale, y: -8,
            width: geometry.notchWidth*scale, height: geometry.notchHeight*scale+8)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: notch, xRadius: geometry.cornerRadius*scale,
            yRadius: geometry.cornerRadius*scale).fill()
    }
}

@MainActor
final class NotchFlamePreviewController: NSWindowController, NSWindowDelegate {
    private let speed = NSSlider(value: 180, minValue: 0, maxValue: 180, target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")
    private let deviceLabel = NSTextField(labelWithString: "")
    private var scenes: [FlamePreviewScene] = []
    private var screenObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var rates: [Double] = []
    private let presets = NSStackView()
    private let settings: NotchFlameSettings
    private let isIsolatedDraft: Bool
    private var paletteEditor: NotchFlamePaletteEditor?
    private var matrixControls: NotchMatrixControls?
    private var matrixDraft: NotchMatrixConfiguration
    private var lightningControls: NotchLightningControls?
    private var contentStack: NSStackView?
    private var lightningDraft: NotchLightningConfiguration
    private var previewPalette: NotchFlamePalette?
    private(set) var selectedEffect: NotchEffectStyle
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let effectControl = NSSegmentedControl(labels: NotchEffectStyle.allCases.map(\.title),
        trackingMode: .selectOne, target: nil, action: nil)
    private let applyEffectButton = NSButton(title: "", target: nil, action: nil)

    init(settings: NotchFlameSettings = .shared, renderer: NotchFlameRenderer? = nil,
         effect: NotchEffectStyle? = nil, isIsolatedDraft: Bool = false) throws {
        self.settings = settings
        self.isIsolatedDraft = isIsolatedDraft
        matrixDraft = settings.matrixConfiguration
        lightningDraft = settings.lightningConfiguration
        selectedEffect = effect ?? settings.effect
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 730),
            styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = isIsolatedDraft ? "EmberCat · \(selectedEffect.title)交互草稿" : "EmberCat · 特效设置与预览"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        if isIsolatedDraft && selectedEffect != .lightning { speed.doubleValue = 90 }
        try buildContent(renderer: renderer ?? NotchFlameRenderer())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        super.showWindow(sender)
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGeometry() }
            }
        }
        if settingsObserver == nil {
            settingsObserver = NotificationCenter.default.addObserver(
                forName: .emberCatFlameSettingsChanged, object: settings, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateApplyButton() }
            }
        }
        refreshGeometry()
        if !wasVisible {
            paletteEditor?.reload()
            matrixControls?.reload(settings.matrixConfiguration)
            previewMatrixConfiguration(settings.matrixConfiguration)
            lightningControls?.reload(settings.lightningConfiguration)
            previewLightningConfiguration(settings.lightningConfiguration)
        }
        updateEffectControls()
        changeSpeed()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        for scene in scenes { scene.flame.stop() }
        paletteEditor?.deactivateColors()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
    }

    func deactivateColorWells() { paletteEditor?.deactivateColors() }

    private var geometry: NotchFlameGeometry {
        NotchDisplayProfile.current()?.geometry(for: selectedEffect, lightningConfiguration: lightningDraft)
            ?? NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: selectedEffect,
                lightningConfiguration: lightningDraft)
    }

    private func buildContent(renderer: NotchFlameRenderer) throws {
        guard let content = window?.contentView else { return }
        titleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        subtitleLabel.textColor = .secondaryLabelColor
        effectControl.target = self
        effectControl.action = #selector(changeEffect)
        effectControl.setAccessibilityIdentifier("notch-preview-effect")
        applyEffectButton.target = self
        applyEffectButton.action = #selector(applyEffect)
        applyEffectButton.setAccessibilityIdentifier("notch-preview-apply-effect")
        deviceLabel.font = .systemFont(ofSize: 12)
        deviceLabel.textColor = .secondaryLabelColor
        scenes = try FlamePreviewBackground.allCases.map {
            try FlamePreviewScene(geometry: geometry, renderer: renderer, background: $0)
        }
        let boxes = scenes.map { scene -> NSStackView in
            let caption = NSTextField(labelWithString: scene.background.title)
            caption.font = .systemFont(ofSize: 12)
            caption.textColor = .secondaryLabelColor
            let box = NSStackView(views: [scene,caption])
            box.orientation = .vertical
            box.spacing = 8
            return box
        }
        let samples = NSStackView(views: boxes)
        samples.spacing = 12
        speed.target = self
        speed.isContinuous = true
        speed.action = #selector(changeSpeed)
        speed.setAccessibilityIdentifier("flame-preview-speed")
        speed.setAccessibilityLabel("模拟输出速度")
        speed.widthAnchor.constraint(equalToConstant: 610).isActive = true
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let speedRow = NSStackView(views: [speedLabel,speed])
        speedRow.spacing = 20
        presets.spacing = 8
        let editor = NotchFlamePaletteEditor(settings: settings)
        paletteEditor = editor
        editor.onPreviewChange = { [weak self] in self?.previewConfiguration(palette: $0, appearance: $1) }
        let matrix = NotchMatrixControls(configuration: matrixDraft)
        matrixControls = matrix
        matrix.onChange = { [weak self] in self?.previewMatrixConfiguration($0) }
        let lightning = NotchLightningControls(configuration: lightningDraft)
        lightningControls = lightning
        lightning.onChange = { [weak self] in self?.previewLightningConfiguration($0) }
        let hint = NSTextField(labelWithString: isIsolatedDraft
            ? "模拟 tok/s · 参数仅保存在这份草稿中，不更改已安装应用。"
            : "此窗口使用模拟 tok/s；顶部特效和菜单栏继续读取真实输出。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.setAccessibilityIdentifier("notch-preview-scope")
        let stack = NSStackView(views: [titleLabel,subtitleLabel,effectControl,deviceLabel,samples,
            speedRow,presets,editor,matrix,lightning,applyEffectButton,hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentStack = stack
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.widthAnchor.constraint(equalToConstant: 880),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor,constant: 20)])
        previewConfiguration(palette: settings.palette, appearance: settings.appearance)
        previewMatrixConfiguration(matrixDraft)
        previewLightningConfiguration(lightningDraft)
        updateEffectControls()
        refreshGeometry()
    }

    @objc private func changeSpeed() {
        speedLabel.stringValue = String(format: "预览 · %.0f tok/s",speed.doubleValue)
        for scene in scenes { scene.flame.setSpeed(speed.doubleValue) }
    }

    @objc private func selectRate(_ sender: NSButton) {
        guard rates.indices.contains(sender.tag) else { return }
        speed.doubleValue = rates[sender.tag]
        changeSpeed()
    }

    private func previewConfiguration(palette: NotchFlamePalette, appearance: NotchFlameAppearance) {
        for scene in scenes {
            scene.flame.setPalette(palette)
            scene.flame.setAppearance(appearance)
        }
        guard palette != previewPalette else { return }
        previewPalette = palette
        rebuildPresets()
    }

    private func previewMatrixConfiguration(_ configuration: NotchMatrixConfiguration) {
        matrixDraft = configuration
        for scene in scenes { scene.flame.setMatrixConfiguration(configuration) }
        updateApplyButton()
    }

    func setMatrixDraftConfiguration(_ configuration: NotchMatrixConfiguration) {
        guard configuration.validationError == nil else { return }
        matrixControls?.reload(configuration)
        previewMatrixConfiguration(configuration)
    }

    private func previewLightningConfiguration(_ configuration: NotchLightningConfiguration) {
        lightningDraft = configuration
        for scene in scenes { scene.flame.setLightningConfiguration(configuration) }
        refreshGeometry()
        updateApplyButton()
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func setLightningDraftConfiguration(_ configuration: NotchLightningConfiguration) {
        guard configuration.validationError == nil else { return }
        lightningControls?.reload(configuration)
        previewLightningConfiguration(configuration)
    }

    private func rebuildPresets() {
        let palette = previewPalette ?? settings.palette
        speed.maxValue = selectedEffect == .flame ? palette.previewMaximum : 180
        speed.doubleValue = min(speed.doubleValue, speed.maxValue)
        rates = selectedEffect == .flame ? palette.sampleRates : [0, 20, 90, 180]
        for view in presets.arrangedSubviews { presets.removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, rate) in rates.enumerated() {
            let title: String
            if index == 0 {
                title = selectedEffect.hasIdleAnimation ? "0 · 慢速待机" : "0 · 熄灭"
            } else {
                switch selectedEffect {
                case .flame: title = "第 \(index) 档 · \(Int(rate.rounded()))"
                case .matrix: title = "\(["", "慢流", "穿梭", "高速"][index]) · \(Int(rate))"
                case .lightning: title = "\(["", "慢速仓鼠", "高速仓鼠", "极速仓鼠"][index]) · \(Int(rate))"
                }
            }
            let button = NSButton(title: title, target: self, action: #selector(selectRate(_:)))
            button.tag = index
            button.controlSize = .small
            button.widthAnchor.constraint(equalToConstant: min(180, 820 / CGFloat(rates.count))).isActive = true
            button.setAccessibilityIdentifier("flame-preview-band-\(index)")
            presets.addArrangedSubview(button)
        }
        changeSpeed()
    }

    func selectEffect(_ effect: NotchEffectStyle) {
        selectedEffect = effect
        paletteEditor?.deactivateColors()
        refreshGeometry()
        updateEffectControls()
        rebuildPresets()
    }

    @objc private func changeEffect() {
        guard NotchEffectStyle.allCases.indices.contains(effectControl.selectedSegment) else { return }
        selectEffect(NotchEffectStyle.allCases[effectControl.selectedSegment])
    }

    @objc private func applyEffect() {
        if selectedEffect == .matrix {
            guard settings.setMatrixConfiguration(matrixDraft) else { return }
        }
        if selectedEffect == .lightning {
            guard settings.setLightningConfiguration(lightningDraft) else { return }
        }
        settings.effect = selectedEffect
        settings.isEnabled = true
        updateEffectControls()
    }

    private func updateEffectControls() {
        effectControl.selectedSegment = NotchEffectStyle.allCases.firstIndex(of: selectedEffect) ?? 0
        var height: CGFloat
        switch selectedEffect {
        case .flame:
            titleLabel.stringValue = "刘海流焰"
            subtitleLabel.stringValue = "滑动调整火焰质感，为不同速度设定自己的颜色。"
            height = 716
        case .matrix:
            titleLabel.stringValue = "Matrix · 代码雨"
            subtitleLabel.stringValue = "黑洞大小随 tok/s 变化，代码密度保持设定；无输出时慢速待机，鼠标经过虚化。"
            height = 754
        case .lightning:
            titleLabel.stringValue = selectedEffect.title
            subtitleLabel.stringValue = "仓鼠随速度换挡，无输出时慢速待机；鼠标经过时隐藏，移开恢复。"
            height = 704
        }
        paletteEditor?.isHidden = selectedEffect != .flame
        matrixControls?.isHidden = selectedEffect != .matrix
        lightningControls?.isHidden = selectedEffect != .lightning
        updateApplyButton()
        if let window {
            if selectedEffect == .lightning {
                window.contentView?.layoutSubtreeIfNeeded()
                height = max(height,(contentStack?.fittingSize.height ?? 0)+40)
            }
            let top = window.frame.maxY
            window.setContentSize(NSSize(width: 920, height: height))
            var origin = CGPoint(x: window.frame.minX, y: top-window.frame.height)
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                origin.x = min(max(visible.minX,origin.x),max(visible.minX,visible.maxX-window.frame.width))
                origin.y = min(max(visible.minY,origin.y),max(visible.minY,visible.maxY-window.frame.height))
            }
            window.setFrameOrigin(origin)
        }
    }

    private func updateApplyButton() {
        let applied = settings.effect == selectedEffect && settings.isEnabled
            && (selectedEffect != .matrix || matrixDraft == settings.matrixConfiguration)
            && (selectedEffect != .lightning || lightningDraft == settings.lightningConfiguration)
        if isIsolatedDraft {
            applyEffectButton.title = applied ? "草稿参数已保存" : "保存草稿参数"
        } else {
            applyEffectButton.title = applied ? "已应用 · \(selectedEffect.title)" : "保存并应用 · \(selectedEffect.title)"
        }
        applyEffectButton.isEnabled = !applied
    }

    private func refreshGeometry() {
        let geometry = self.geometry
        let profile = NotchDisplayProfile.current()
        deviceLabel.stringValue = (profile?.summary ?? "未检测到显示器")
            + (profile == nil ? " · 以下为示例预览" : " · 自动适配")
        for scene in scenes { scene.update(geometry: geometry) }
        if window?.isVisible == true { changeSpeed() }
    }
}

@MainActor
final class FlamePreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var preview: NotchFlamePreviewController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let effect: NotchEffectStyle = CommandLine.arguments.contains("--preview-lightning") ? .lightning
                : CommandLine.arguments.contains("--preview-matrix") ? .matrix : .flame
            preview = try NotchFlamePreviewController(effect: effect)
            preview?.showWindow(nil)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Fixed-rate and changing-rate samples use the live renderer and animation clock.
@MainActor
func exportLightningPreview(to folder: URL, configuration: NotchLightningConfiguration = .standard) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let renderer = try NotchFlameRenderer(lightningSeed: NotchLightningDischarges.previewSeed)
    let geometry = NotchDisplayProfile.current()?.geometry(for: .lightning, lightningConfiguration: configuration)
        ?? NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: .lightning,
            lightningConfiguration: configuration)
    let rates = [20.0, 90, 180]
    let labels = ["慢速仓鼠", "高速仓鼠", "极速仓鼠"]
    let column = max(280, Int(geometry.size.width)+44)
    let row = Int(geometry.size.height)+40
    let sheet = try flameReviewImage(width: column*3, height: row*2+64, scale: 2) { context in
        flameText("仓鼠发电机", at: CGPoint(x: 24, y: 16), size: 20, color: .white)
        for (index, rate) in rates.enumerated() {
            for (backgroundIndex, background) in [FlamePreviewBackground.dark, .white].enumerated() {
                let rendered = try renderer.image(geometry: geometry, time: 12.4, speed: rate, scale: 3,
                    matrixColorScheme: background.matrixColorScheme!)
                drawFlameSample(context: context, image: rendered, geometry: geometry,
                    rect: CGRect(x: index*column+12, y: 64+backgroundIndex*row, width: column-24, height: row-12),
                    background: background, caption: "\(labels[index]) · 模拟 \(Int(rate)) tok/s")
            }
        }
    }
    try NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("lightning-stages.png"))

    let fps = 25.0
    for transition in [false, true] {
        let frames = transition ? 250 : 150
        let name = transition ? "lightning-transition.gif" : "lightning-motion.gif"
        guard let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL,
            UTType.gif.identifier as CFString, frames, nil) else {
            throw NSError(domain: "EmberCat.LightningPreview", code: 1)
        }
        CGImageDestinationSetProperties(destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var animations = rates.map { rate -> NotchFlameAnimation in
            var animation = NotchFlameAnimation()
            animation.setSpeed(transition ? 0 : rate, effect: .lightning)
            for _ in 0..<300 { animation.advance(by: 1/60, flow: configuration.flow) }
            return animation
        }
        var motionClocks = [Double](repeating: 0, count: animations.count)
        for frame in 0..<frames {
            let seconds = Double(frame)/fps
            let input = seconds < 2.5 ? 20.0 : seconds < 5 ? 90 : seconds < 7.5 ? 180 : 0
            let count = transition ? 1 : rates.count
            for index in 0..<count {
                animations[index].setSpeed(transition ? input : rates[index], effect: .lightning)
                animations[index].advance(by: 1/fps, flow: configuration.flow)
                motionClocks[index] += 1/fps*animations[index].motionScale
            }
            let image = try flameReviewImage(width: column*count, height: row+52, scale: 1) { context in
                flameText(transition ? "仓鼠发电机 · 连续换挡" : "仓鼠发电机 · 三档动效", at: CGPoint(x: 16, y: 14),
                    size: 16, color: .white)
                for index in 0..<count {
                    let animation = animations[index]
                    let displaySpeed = pow(animation.heat, 1/0.8)*180
                    let rendered = try renderer.image(geometry: geometry, time: animation.phase,
                        speed: displaySpeed, scale: 2, lightningMotionTime: motionClocks[index],
                        hamsterAnimationTime: motionClocks[index]*configuration.hamsterSpeed,
                        visibility: Float(animation.visibility))
                    drawFlameSample(context: context, image: rendered, geometry: geometry,
                        rect: CGRect(x: index*column+8, y: 48, width: column-16, height: row-8), background: .dark,
                        caption: transition ? "模拟输入 \(Int(input)) tok/s · 平滑过渡"
                            : "\(labels[index]) · 模拟 \(Int(rates[index])) tok/s")
                }
            }
            CGImageDestinationAddImage(destination, image,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1/fps]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "EmberCat.LightningPreview", code: 2)
        }
    }
    print("Exported native lightning preview to \(folder.path)")
}

/// Review artifacts contain actual shader output, with explicitly simulated token rates.
@MainActor
func exportFlamePreview(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
    let renderer = try NotchFlameRenderer()
    let profile = NotchDisplayProfile.current()
    let geometry = profile?.geometry ?? NotchFlameGeometry(notchWidth: 180,notchHeight: 32)
    let rates: [Double] = [0,20,90,180]
    let names = ["OFF", "GOLD", "RED", "BLUE"]
    let column = max(300,Int(geometry.size.width)+52)
    let row = max(138,Int(geometry.size.height)+38)
    let sheet = try flameReviewImage(width: column*3,height: row*rates.count+64,scale: 2) { context in
        flameText("EMBERCAT / NOTCH FIRE",at: CGPoint(x:24,y:16),size:20,color:.white)
        for (index,rate) in rates.enumerated() {
            let image = try renderer.image(geometry: geometry,time: 8.73,speed: rate,scale:4)
            for (backgroundIndex, background) in FlamePreviewBackground.allCases.enumerated() {
                let rect = CGRect(x: backgroundIndex*column+12,y: 64+index*row,
                    width: column-24,height: row-12)
                drawFlameSample(context: context,image: image,geometry: geometry,rect: rect,background: background,
                    caption: "\(Int(rate)) tok/s  /  \(names[index])")
            }
        }
    }
    try NSBitmapImageRep(cgImage: sheet).representation(using: .png,properties: [:])!
        .write(to: folder.appendingPathComponent("flame-palette.png"))
    let customColors = ["#4DEB66", "#B34DFF", "#FFFFFF", "#000000"]
    let customSheet = try flameReviewImage(width: column*3, height: row*customColors.count+64, scale: 2) { context in
        flameText("EMBERCAT / CUSTOM COLORS", at: CGPoint(x:24,y:16), size:20, color:.white)
        for (index, hex) in customColors.enumerated() {
            let palette = NotchFlamePalette(bands: [.init(minimumSpeed:0,hex:hex)])
            let image = try renderer.image(geometry:geometry,time:8.73,speed:180,scale:4,palette:palette)
            for (columnIndex,background) in FlamePreviewBackground.allCases.enumerated() {
                drawFlameSample(context:context,image:image,geometry:geometry,
                    rect:CGRect(x:columnIndex*column+12,y:64+index*row,width:column-24,height:row-12),
                    background:background,caption:"180 tok/s / \(hex)")
            }
        }
    }
    try NSBitmapImageRep(cgImage:customSheet).representation(using:.png,properties:[:])!
        .write(to:folder.appendingPathComponent("flame-custom-colors.png"))
    let detailWidth=max(740,Int(geometry.size.width*3)+80)
    let detailHeight=Int(geometry.size.height*3)+96
    let detail = try flameReviewImage(width:detailWidth,height:detailHeight,scale:2) { context in
        flameText("EMBERCAT / DOWNWARD FLAME + CONTINUOUS RIM",at:CGPoint(x:24,y:14),size:18,color:.white)
        let flame = try renderer.image(geometry:geometry,time:8.73,speed:180,scale:6)
        drawFlameSample(context:context,image:flame,geometry:geometry,
            rect:CGRect(x:18,y:52,width:detailWidth-36,height:detailHeight-64),background:.dark,
            caption:"3X DETAIL / NATIVE METAL",zoom:3)
    }
    try NSBitmapImageRep(cgImage:detail).representation(using:.png,properties:[:])!
        .write(to:folder.appendingPathComponent("flame-detail.png"))
    let count = 150
    let gifURL = folder.appendingPathComponent("flame-heat.gif")
    guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL,UTType.gif.identifier as CFString,count,nil)
    else { throw NSError(domain:"EmberCat.FlamePreview",code:1) }
    CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    var animation = NotchFlameAnimation()
    for tick in 0..<count {
        let heat = 0.5-0.5*cos(Double(tick)/Double(count)*2*Double.pi)
        let rate = 180*pow(heat,1/0.80)
        animation.setSpeed(rate, color: NotchFlamePalette.standard.color(for: rate))
        animation.advance(by: 1.0/15)
        let renderedRate = 180*pow(animation.heat,1/0.80)
        let image = try renderer.image(geometry: geometry,time: animation.phase,
            speed: renderedRate,active: !animation.isHidden, color: animation.color,
            visibility: Float(animation.visibility))
        let frame = try flameReviewImage(width: column*3,height: row+74,scale:1) { context in
            flameText(String(format:"EMBERCAT / %.0f tok/s",rate),at:CGPoint(x:24,y:16),size:20,color:.white)
            flameText("CONTINUOUS HEAT / SIMULATED SPEED",at:CGPoint(x:24,y:43),size:10,color:.lightGray)
            for (backgroundIndex, background) in FlamePreviewBackground.allCases.enumerated() {
                drawFlameSample(context:context,image:image,geometry:geometry,
                    rect:CGRect(x:backgroundIndex*column+12,y:74,width:column-24,height:row-12),background:background,
                    caption:["DARK BACKGROUND", "WHITE BACKGROUND", "BUSY BACKGROUND"][backgroundIndex])
            }
        }
        CGImageDestinationAddImage(gif,frame,[kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFDelayTime:1.0/15.0]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(gif) else { throw NSError(domain:"EmberCat.FlamePreview",code:2) }
    let tuningURL = folder.appendingPathComponent("flame-tuning.gif")
    let steps = 30
    let parameters = NotchFlameParameter.allCases
    let labels = ["BRIGHTNESS", "BRIGHT CORE", "TRANSPARENCY", "TAIL LENGTH", "TURBULENCE", "FLOW SPEED"]
    guard let tuning = CGImageDestinationCreateWithURL(tuningURL as CFURL, UTType.gif.identifier as CFString,
        steps * parameters.count, nil) else { throw NSError(domain: "EmberCat.FlamePreview", code: 3) }
    CGImageDestinationSetProperties(tuning, [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    var tuningAnimation = NotchFlameAnimation()
    tuningAnimation.setSpeed(180)
    for _ in 0..<180 { tuningAnimation.advance(by: 1.0/60) }
    for (index, parameter) in parameters.enumerated() {
        for step in 0..<steps {
            let progress = 0.5 - 0.5 * cos(Double(step) / Double(steps-1) * .pi)
            let value = parameter.range.lowerBound
                + (parameter.range.upperBound-parameter.range.lowerBound) * progress
            var appearance = NotchFlameAppearance.standard
            appearance[keyPath: parameter.keyPath] = value
            tuningAnimation.advance(by: 1.0/15, flow: appearance.flow)
            let image = try renderer.image(geometry: geometry, time: tuningAnimation.phase,
                speed: 180, appearance: appearance)
            let frame = try flameReviewImage(width: column*3, height: row+74, scale: 1) { context in
                flameText(String(format: "EMBERCAT / %@ %.0f%%", labels[index], value*100),
                    at: CGPoint(x:24,y:16), size:20, color:.white)
                flameText("180 TOK/S SIMULATED / ONE SLIDER AT A TIME",
                    at: CGPoint(x:24,y:43), size:10, color:.lightGray)
                for (backgroundIndex,background) in FlamePreviewBackground.allCases.enumerated() {
                    drawFlameSample(context:context,image:image,geometry:geometry,
                        rect:CGRect(x:backgroundIndex*column+12,y:74,width:column-24,height:row-12),
                        background:background,
                        caption:["DARK BACKGROUND", "WHITE BACKGROUND", "BUSY BACKGROUND"][backgroundIndex])
                }
            }
            CGImageDestinationAddImage(tuning, frame, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime:1.0/15]] as CFDictionary)
        }
    }
    guard CGImageDestinationFinalize(tuning) else { throw NSError(domain: "EmberCat.FlamePreview", code: 4) }
    let report: [String:Any] = ["renderer":"Downward fire with a continuous rim / native Metal",
        "maximumFlameDepth":NotchFlameGeometry.maximumFlameDepth,"fps":15,"frames":count,
        "palette":NotchFlamePalette.standard.bands.map { ["minimumSpeed":$0.minimumSpeed,"hex":$0.hex] as [String:Any] },
        "customColors":customColors,
        "materialParameters":parameters.map {
            ["parameter":$0.rawValue, "default":NotchFlameAppearance.standard[keyPath:$0.keyPath],
                "minimum":$0.range.lowerBound, "maximum":$0.range.upperBound] as [String:Any]
        },
        "tuningAnimation":["fps":15,"frames":steps*parameters.count,"simulatedSpeed":180],
        "input":"isolated simulated output rates; default palette",
        "rates":rates,"device":profile?.summary ?? "preview fixture",
        "anchorPoints":[geometry.notchWidth,geometry.notchHeight],
        "physicalNotch":profile?.notchFrame != nil]
    try JSONSerialization.data(withJSONObject: report,options:[.prettyPrinted,.sortedKeys])
        .write(to:folder.appendingPathComponent("manifest.json"))
    print("Exported production flame palette and continuous heat animation to \(folder.path)")
}

@MainActor
func exportMatrixPreview(to folder: URL, configuration: NotchMatrixConfiguration = .standard) throws {
    _ = NSApplication.shared
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let renderer = try NotchFlameRenderer(matrixSeed: MatrixCodeFlow.previewSeed)
    let profile = NotchDisplayProfile.current()
    let geometry = profile?.geometry(for: .matrix)
        ?? NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: .matrix)
    let column = max(300, Int(geometry.size.width) + 52)
    let row = Int(geometry.size.height) + 42
    let rates = [0.0, 20, 90, 180]
    let sheet = try flameReviewImage(width: column * 3, height: row * rates.count + 64, scale: 2) { context in
        flameText("EMBERCAT / MATRIX GRAVITY WALL", at: CGPoint(x: 24, y: 16), size: 20, color: .white)
        for (index, rate) in rates.enumerated() {
            for (backgroundIndex, background) in FlamePreviewBackground.allCases.enumerated() {
                let rendered = try renderer.image(geometry: geometry, time: 12.4, speed: rate, scale: 4,
                    matrixConfiguration: configuration,
                    matrixColorScheme: background.matrixColorScheme ?? NotchMatrixColorScheme(appearance: NSApp.effectiveAppearance))
                drawFlameSample(context: context, image: rendered, geometry: geometry,
                    rect: CGRect(x: backgroundIndex * column + 12, y: 64 + index * row,
                        width: column - 24, height: row - 12), background: background,
                    caption: "SIMULATED \(Int(rate)) TOK/S")
            }
        }
    }
    try NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("matrix-backgrounds.png"))
    let width = max(740, Int(geometry.size.width * 3) + 80)
    let height = Int(geometry.size.height * 3) + 116
    func frame(time: Double, scale: CGFloat, speed: Double = 90, inputSpeed: Double? = nil,
               visibility: Float = 1, breathingTime: Double? = nil, pass: MatrixFlowPass = .composed) throws -> CGImage {
        let rendered = try renderer.image(geometry: geometry, time: time, speed: speed,
            scale: 6, matrixConfiguration: configuration,matrixBreathingTime:breathingTime,
            visibility: visibility, matrixPass: pass)
        return try flameReviewImage(width: width, height: height, scale: scale) { context in
            flameText(pass == .aperture ? "代码盘面 · 诊断帧" : pass == .background ? "背景雨 · 不参与吸入"
                : inputSpeed == nil ? "竖直代码雨 · 黑洞吸入草稿" : "代码密度与流速 · tok/s 联动",
                at: CGPoint(x: 24, y: 16), size: 22, color: .white)
            flameText(String(format: "3× 放大 · %.0f tok/s 模拟输入 · 未定稿", inputSpeed ?? speed),
                at: CGPoint(x: 24, y: 46), size: 11, color: .lightGray)
            drawFlameSample(context: context, image: rendered, geometry: geometry,
                rect: CGRect(x: 18, y: 76, width: width - 36, height: height - 88), background: .dark,
                caption: pass == .background ? "独立背景  /  保持竖直  /  不参与引力  /  下方淡出"
                    : "背景直落  /  代码入盘  /  字形碎裂  /  鼠标经过虚化", zoom: 3)
        }
    }
    let detail = try frame(time: 12.4, scale: 2)
    try NSBitmapImageRep(cgImage: detail).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("matrix-detail.png"))
    let aperture = try frame(time: 12.4, scale: 2, pass: .aperture)
    try NSBitmapImageRep(cgImage: aperture).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("matrix-shadow-diagnostic.png"))
    let backgroundRain = try frame(time:12.4,scale:2,pass:.background)
    try NSBitmapImageRep(cgImage:backgroundRain).representation(using:.png,properties:[:])!
        .write(to:folder.appendingPathComponent("matrix-background-rain.png"))
    let actualSize = try flameReviewImage(width: 740, height: 216, scale: 1) { context in
        flameText("1× 原尺寸布局 · 90 tok/s 模拟输入 · 未定稿", at: CGPoint(x: 24, y: 16),
            size: 13, color: .lightGray)
        for (index, background) in [FlamePreviewBackground.dark, .white].enumerated() {
            let actualImage = try renderer.image(geometry: geometry, time: 12.4, speed: 90, scale: 2,
                matrixConfiguration: configuration, matrixColorScheme: background.matrixColorScheme!)
            drawFlameSample(context: context, image: actualImage, geometry: geometry,
                rect: CGRect(x: 18 + index * 370, y: 50, width: 334, height: 150),
                background: background, caption: index == 0 ? "深色桌面" : "浅色桌面")
        }
    }
    try NSBitmapImageRep(cgImage: actualSize).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("matrix-actual-size.png"))
    let seeds = [MatrixCodeFlow.previewSeed, MatrixCodeFlow.previewSeed ^ 0x7821_B97D,
        MatrixCodeFlow.previewSeed ^ 0xD13F_A056]
    let sampleWidth = max(440, Int(geometry.size.width * 2) + 48)
    let sampleHeight = Int(geometry.size.height * 2) + 42
    var floatingConfiguration = configuration
    floatingConfiguration.verticalOffset = max(configuration.verticalOffset,
        Double(MatrixCodeFlow.horizon(geometry:geometry,configuration:configuration).z)+8)
    floatingConfiguration.verticalOffset = min(64,floatingConfiguration.verticalOffset)
    let floatingHole = MatrixCodeFlow.horizon(geometry:geometry,configuration:floatingConfiguration)
    func interactionFrame(seconds:Double,hover:Double,breathingClock:Double,scale:CGFloat) throws -> CGImage {
        try flameReviewImage(width:sampleWidth*2,height:sampleHeight+64,scale:scale) { context in
            flameText("黑洞 · 本体呼吸与鼠标虚化",at:CGPoint(x:24,y:12),size:18,color:.white)
            flameText("90 tok/s 模拟 · 悬空展示 · 悬停为导出模拟；交互窗口支持真实鼠标",
                at:CGPoint(x:24,y:38),size:10,color:.lightGray)
            for (index,background) in [FlamePreviewBackground.dark,.white].enumerated() {
                let image = try renderer.image(geometry:geometry,time:12.4+seconds*0.8,speed:90,scale:4,
                    matrixConfiguration:floatingConfiguration,matrixColorScheme:background.matrixColorScheme!,
                    matrixHover:hover,matrixBreathingTime:breathingClock)
                let rect = CGRect(x:index*sampleWidth+12,y:64,width:sampleWidth-24,height:sampleHeight-12)
                let label = hover > 0.5 ? "鼠标经过 · 黑洞虚化" : hover > 0.01 ? "移开后柔和恢复" : "本体呼吸 · 进入后微光湮灭"
                drawFlameSample(context:context,image:image,geometry:geometry,rect:rect,
                    background:background,caption:label,zoom:2)
                if hover > 0.5 {
                    let origin = CGPoint(x:rect.midX-geometry.size.width,y:rect.minY)
                    let x = origin.x+CGFloat(floatingHole.x)*2+3,y = origin.y+CGFloat(floatingHole.y)*2+2
                    let cursor = NSBezierPath()
                    cursor.move(to:CGPoint(x:x,y:y))
                    cursor.line(to:CGPoint(x:x+3,y:y+17))
                    cursor.line(to:CGPoint(x:x+7,y:y+12))
                    cursor.line(to:CGPoint(x:x+13,y:y+12))
                    cursor.close()
                    NSColor.white.setStroke();NSColor.black.setFill()
                    cursor.lineWidth = 1.5;cursor.fill();cursor.stroke()
                }
            }
        }
    }
    let interactionComparison = try flameReviewImage(width:sampleWidth*2,height:(sampleHeight+64)*2,scale:2) { context in
        for (index,hover) in [0.0,1.0].enumerated() {
            let breathingClock = 0.73
            let image = try interactionFrame(seconds:0.73,hover:hover,breathingClock:breathingClock,scale:2)
            context.saveGState()
            context.translateBy(x:0,y:CGFloat((sampleHeight+64)*(index+1)))
            context.scaleBy(x:1,y:-1)
            context.draw(image,in:CGRect(x:0,y:0,width:sampleWidth*2,height:sampleHeight+64))
            context.restoreGState()
        }
    }
    try NSBitmapImageRep(cgImage:interactionComparison).representation(using:.png,properties:[:])!
        .write(to:folder.appendingPathComponent("matrix-interaction-comparison.png"))
    let interactionFrames = 420,interactionFPS = 50.0
    let interactionDestination = CGImageDestinationCreateWithURL(
        folder.appendingPathComponent("matrix-interaction.gif") as CFURL,UTType.gif.identifier as CFString,
        interactionFrames,nil)!
    CGImageDestinationSetProperties(interactionDestination,[kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    var pointerFeedback = MatrixHoleInteraction()
    for index in 0..<interactionFrames {
        let seconds = Double(index)/interactionFPS
        pointerFeedback.advance(by:1/interactionFPS,hovered:seconds >= 2.4 && seconds < 4.7,
            reduceMotion:false)
        CGImageDestinationAddImage(interactionDestination,
            try interactionFrame(seconds:seconds,hover:pointerFeedback.hover,breathingClock:pointerFeedback.elapsed,scale:1),
            [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1/interactionFPS]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(interactionDestination) else {
        throw NSError(domain:"EmberCat.MatrixPreview",code:5)
    }
    let bodyRates = [20.0,90,180]
    let bodyFrames = 400
    let bodyDestination = CGImageDestinationCreateWithURL(
        folder.appendingPathComponent("matrix-body-response.gif") as CFURL,
        UTType.gif.identifier as CFString,bodyFrames,nil)!
    CGImageDestinationSetProperties(bodyDestination,[kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    var breathingClocks = [MatrixHoleInteraction](repeating:MatrixHoleInteraction(),count:3)
    var rainClocks = [NotchFlameAnimation](repeating:NotchFlameAnimation(),count:3)
    for i in 0..<3 {
        rainClocks[i].setSpeed(bodyRates[i],effect:.matrix)
        for _ in 0..<240 {
            rainClocks[i].advance(by:1/60,flow:MatrixCodeFlow.motionMultiplier(heat:rainClocks[i].heat))
        }
    }
    for _ in 0..<bodyFrames {
        let response = try flameReviewImage(width:sampleWidth*3,height:sampleHeight+64,scale:1) { context in
            flameText("tok/s 越快，黑洞越大；本体轻微呼吸",at:CGPoint(x:24,y:12),size:19,color:.white)
            flameText("独立模拟输入 · 洞内荧光随实际代码进入短暂亮起",at:CGPoint(x:24,y:39),size:10,color:.lightGray)
            for i in 0..<3 {
                rainClocks[i].advance(by:1/50,flow:MatrixCodeFlow.motionMultiplier(heat:rainClocks[i].heat))
                breathingClocks[i].advance(by:1/50,hovered:false,reduceMotion:false,motionScale:rainClocks[i].motionScale)
                let image = try renderer.image(geometry:geometry,time:rainClocks[i].phase,speed:bodyRates[i],scale:4,
                    matrixConfiguration:floatingConfiguration,matrixBreathingTime:breathingClocks[i].elapsed)
                let bodyScale = MatrixHoleInteraction.radiusScale(heat:rainClocks[i].heat,time:breathingClocks[i].elapsed)
                drawFlameSample(context:context,image:image,geometry:geometry,
                    rect:CGRect(x:i*sampleWidth+12,y:64,width:sampleWidth-24,height:sampleHeight-12),
                    background:.dark,caption:String(format:"%.0f tok/s · 上限的 %.0f%%",bodyRates[i],bodyScale*100),zoom:2)
            }
        }
        CGImageDestinationAddImage(bodyDestination,response,
            [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/50]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(bodyDestination) else { throw NSError(domain:"EmberCat.MatrixPreview",code:6) }
    let colorComparison = try flameReviewImage(width: sampleWidth*3,height: sampleHeight+64,scale:2) { context in
        flameText("Matrix · 浅色对比与系统配色",at:CGPoint(x:24,y:16),size:20,color:.white)
        let comparisons: [(FlamePreviewBackground,NotchMatrixColorScheme,String)] = [
            (.white,.dark,"上一稿 · 浅底荧光绿"),(.white,.light,"macOS 浅色 · 墨青绿"),(.dark,.dark,"macOS 深色 · 荧光绿")]
        for (index,comparison) in comparisons.enumerated() {
            let image = try renderer.image(geometry:geometry,time:12.4,speed:90,scale:4,
                matrixConfiguration:configuration,matrixColorScheme:comparison.1)
            drawFlameSample(context:context,image:image,geometry:geometry,
                rect:CGRect(x:index*sampleWidth+12,y:64,width:sampleWidth-24,height:sampleHeight-12),
                background:comparison.0,caption:comparison.2,zoom:2)
        }
    }
    try NSBitmapImageRep(cgImage:colorComparison).representation(using:.png,properties:[:])!
        .write(to:folder.appendingPathComponent("matrix-appearance-comparison.png"))
    let variations = try flameReviewImage(width: sampleWidth * 3, height: sampleHeight + 64, scale: 2) { context in
        flameText("EMBERCAT / RANDOM VARIATIONS", at: CGPoint(x: 24, y: 16), size: 20, color: .white)
        for (index, seed) in seeds.enumerated() {
            let variation = try NotchFlameRenderer(matrixSeed: seed)
            let image = try variation.image(geometry: geometry, time: 12.4, speed: 90, scale: 4,
                matrixConfiguration: configuration)
            drawFlameSample(context: context, image: image, geometry: geometry,
                rect: CGRect(x: index * sampleWidth + 12, y: 64, width: sampleWidth - 24, height: sampleHeight - 12),
                background: .dark, caption: "VARIATION \(index + 1) / SAME MOMENT / 90 TOK/S", zoom: 2)
        }
    }
    try NSBitmapImageRep(cgImage: variations).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("matrix-variations.png"))
    let phases = [8.73, 10.5, 12.4, 15.0, 18.0, 21.0]
    let timeline = try flameReviewImage(width: sampleWidth * 3, height: sampleHeight * 2 + 64, scale: 2) { context in
        flameText("EMBERCAT / CAPTURE AND RESIDUE", at: CGPoint(x: 24, y: 16), size: 20, color: .white)
        for (index, phase) in phases.enumerated() {
            let image = try renderer.image(geometry: geometry, time: phase, speed: 90, scale: 4,
                matrixConfiguration: configuration)
            drawFlameSample(context: context, image: image, geometry: geometry,
                rect: CGRect(x: index % 3 * sampleWidth + 12, y: 64 + index / 3 * sampleHeight,
                    width: sampleWidth - 24, height: sampleHeight - 12), background: .dark,
                caption: String(format: "COMPOSED / PHASE %.2f / 90 TOK/S", phase), zoom: 2)
        }
    }
    try NSBitmapImageRep(cgImage: timeline).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("matrix-timeline.png"))
    let comparisonHeight = sampleHeight
    let parameterComparison = try flameReviewImage(width: sampleWidth * 3,
        height: comparisonHeight * NotchMatrixParameter.allCases.count + 64, scale: 2) { context in
        flameText("Matrix · 参数对比（同一时刻）", at: CGPoint(x: 24, y: 16), size: 20, color: .white)
        for (rowIndex, parameter) in NotchMatrixParameter.allCases.enumerated() {
            let values = [parameter.range.lowerBound,
                NotchMatrixConfiguration.standard[keyPath: parameter.keyPath], parameter.range.upperBound]
            for (columnIndex, value) in values.enumerated() {
                var configuration = NotchMatrixConfiguration.standard
                configuration[keyPath: parameter.keyPath] = value
                let image = try renderer.image(geometry: geometry, time: 12.4, speed: 90,
                    scale: 4, matrixConfiguration: configuration)
                drawFlameSample(context: context, image: image, geometry: geometry,
                    rect: CGRect(x: columnIndex * sampleWidth + 12, y: 64 + rowIndex * comparisonHeight,
                        width: sampleWidth - 24, height: comparisonHeight - 12), background: .dark,
                    caption: "\(parameter.title) · \(parameter.displayValue(value))\(columnIndex == 1 ? "（默认）" : "") · 90 tok/s", zoom: 2)
            }
        }
    }
    try NSBitmapImageRep(cgImage: parameterComparison).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("matrix-parameters.png"))
    let radius = Double(MatrixCodeFlow.horizon(geometry: geometry,configuration: configuration,
        radiusScale:MatrixHoleInteraction.radiusScale(heat:NotchFlameAnimation.heat(for:90),time:12.4)).z)
    let offsets = [0.0,radius+2,64]
    let positions = try flameReviewImage(width: sampleWidth*3,height: sampleHeight+64,scale: 2) { context in
        flameText("竖直代码雨 · 黑洞位置对比",at: CGPoint(x:24,y:16),size:20,color:.white)
        for (index,offset) in offsets.enumerated() {
            var moved = configuration
            moved.verticalOffset = offset
            let image = try renderer.image(geometry:geometry,time:12.4,speed:90,scale:4,matrixConfiguration:moved)
            drawFlameSample(context:context,image:image,geometry:geometry,
                rect:CGRect(x:index*sampleWidth+12,y:64,width:sampleWidth-24,height:sampleHeight-12),
                background:.dark,caption:["半嵌入","刚好脱离","向下离开刘海 64 pt"][index],zoom:2)
        }
    }
    try NSBitmapImageRep(cgImage:positions).representation(using:.png,properties:[:])!
        .write(to:folder.appendingPathComponent("matrix-distance-comparison.png"))
    let count = 600, fps = 50.0
    guard let destination = CGImageDestinationCreateWithURL(
        folder.appendingPathComponent("matrix-motion.gif") as CFURL,
        UTType.gif.identifier as CFString, count, nil) else {
        throw NSError(domain: "EmberCat.MatrixPreview", code: 1)
    }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    var animation = NotchFlameAnimation()
    animation.setSpeed(90,effect:.matrix)
    for _ in 0..<240 {
        animation.advance(by: 1.0 / 60, flow: MatrixCodeFlow.motionMultiplier(heat: animation.heat))
    }
    var constantBody = MatrixHoleInteraction()
    for _ in 0..<count {
        animation.advance(by: 1 / fps, flow: MatrixCodeFlow.motionMultiplier(heat: animation.heat))
        constantBody.advance(by:1/fps,hovered:false,reduceMotion:false)
        let renderedSpeed = 180 * pow(animation.heat, 1 / 0.80)
        CGImageDestinationAddImage(destination, try frame(time: animation.phase, scale: 1,
            speed: renderedSpeed, visibility: Float(animation.visibility),breathingTime:constantBody.elapsed),
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "EmberCat.MatrixPreview", code: 2)
    }
    let responseRates = [20.0, 90, 180, 20]
    let framesPerStage = 250
    guard let response = CGImageDestinationCreateWithURL(
        folder.appendingPathComponent("matrix-load-response.gif") as CFURL,
        UTType.gif.identifier as CFString, responseRates.count * framesPerStage, nil) else {
        throw NSError(domain: "EmberCat.MatrixPreview", code: 3)
    }
    CGImageDestinationSetProperties(response, [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    var loadAnimation = NotchFlameAnimation()
    loadAnimation.setSpeed(responseRates[0],effect:.matrix)
    for _ in 0..<240 {
        loadAnimation.advance(by: 1.0 / 60,
            flow: MatrixCodeFlow.motionMultiplier(heat: loadAnimation.heat))
    }
    var responseBody = MatrixHoleInteraction()
    for rate in responseRates {
        loadAnimation.setSpeed(rate,effect:.matrix)
        for _ in 0..<framesPerStage {
            loadAnimation.advance(by: 1 / fps,
                flow: MatrixCodeFlow.motionMultiplier(heat: loadAnimation.heat))
            responseBody.advance(by:1/fps,hovered:false,reduceMotion:false)
            let renderedSpeed = 180 * pow(loadAnimation.heat, 1 / 0.80)
            CGImageDestinationAddImage(response, try frame(time: loadAnimation.phase, scale: 1,
                speed: renderedSpeed, inputSpeed: rate, visibility: Float(loadAnimation.visibility),breathingTime:responseBody.elapsed),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
        }
    }
    guard CGImageDestinationFinalize(response) else {
        throw NSError(domain: "EmberCat.MatrixPreview", code: 4)
    }
    let previewScale = MatrixHoleInteraction.radiusScale(heat:NotchFlameAnimation.heat(for:90),time:12.4)
    let plane = MatrixCodeFlow.diskPlane(geometry: geometry,configuration:configuration,radiusScale:previewScale)
    let previewHole = MatrixCodeFlow.horizon(geometry:geometry,configuration:configuration,radiusScale:previewScale)
    let report: [String: Any] = ["renderer": "native Metal / rain-derived code accretion and a movable shadow",
        "status": "isolated design preview; visual acceptance and local installation are recorded separately",
        "input": "isolated synthetic tok/s; no monitor or token records",
        "fps": fps, "frames": count, "simulatedSpeed": 90, "rates": rates,
        "previewConfiguration": ["blackHoleSize":configuration.blackHoleSize,"gravity":configuration.gravity,
            "density":configuration.density,"verticalOffset":configuration.verticalOffset,
            "rimWidth":configuration.rimWidth],
        "parameters": NotchMatrixParameter.allCases.map { parameter -> [String: Any] in
            ["key": parameter.rawValue, "title": parameter.title,
                "minimum": parameter.range.lowerBound, "maximum": parameter.range.upperBound,
                "default": NotchMatrixConfiguration.standard[keyPath: parameter.keyPath]]
        },
        "parameterComparison": "matrix-parameters.png; same seed, phase and simulated speed; other parameters at their defaults",
        "appearance": "live overlay follows effective macOS appearance; dark uses fluorescent green and cool-white disk highlights, light uses deep teal-green ink; the core remains unlit and has no surface glyphs",
        "appearanceComparison": "matrix-appearance-comparison.png; previous green on white, new light palette on white, and unchanged dark palette at the same phase",
        "interactiveDraft": "bash scripts/export-matrix-draft.sh --interactive; isolated EmberCat.MatrixInteractiveDraft preferences",
        "loadResponse": ["file": "matrix-load-response.gif", "simulatedRates": responseRates,
            "secondsPerStage": Double(framesPerStage) / fps, "frames": responseRates.count * framesPerStage,
            "phase": "continuous across rate changes; native heat smoothing and Matrix flow multiplier"],
        "device": profile?.summary ?? "preview fixture", "depth": "upright code wall, compact capture streams, front/back orbital occlusion",
        "seed": String(MatrixCodeFlow.previewSeed, radix: 16),
        "variationSeeds": seeds.map { String($0, radix: 16) }, "timelinePhases": phases,
        "liveRandomness": "new process seed each launch; continuous staggered character births in fixed wall columns, bounded bundle spread and stable character identities",
        "notchInteraction": "upright rain starts at the real rounded edge; only the actual hole intersection excludes sources; four inward capture streams follow the movable center, without independent lateral flows",
        "holePosition": "0 pt places the center on the notch bottom for half immersion; up to 64 pt downward; source coverage, attraction, local residue, glow and final capture follow the hole",
        "positionComparison": "matrix-distance-comparison.png; selected preview size, gravity and density at half immersion, just detached and 64 pt downward",
        "absorption": "foreground rain hands the same id and glyph to the disk, where it orbits and dissolves into light; the dark core stays free of glyphs; independent background rain fades lower down",
        "diskMaterial": ["source":"same foreground rain id and codeSeed; shared glyph atlas",
            "lifetimeFlowSeconds":[3.2,4.2],"entryBlendFlowSeconds":0.65,
            "readableGlyphs":"artistic screen-space arc placement and size compensation; emitted light follows the disk-plane lens",
            "backgroundRainCaptured":false],
        "holeFeedback": ["surfaceCodeHidden":true,"darkCoreGlyphsHidden":true,"diskCodeVisible":true,
            "bodyBreathingPeriodSeconds":MatrixHoleInteraction.breathingPeriod,
            "bodyBreathing":"3.8-second gentle physical expansion/contraction, four percent peak-to-peak; no center light; frozen with reduced motion",
            "sizeComparison":"matrix-body-response.gif; automatic growth with 20, 90 and 180 tok/s; 8 seconds at 50 fps",
            "captureLight":"glyph-linked fluorescence during final disk dissolution or direct capture; 0.20 phase seconds; bounded to 12 dim spots",
            "hover":"pointer polling through click-through panels; local soft fade in and out; no global event monitors",
            "preview":"matrix-interaction.gif; simulated hover at 2.4–4.7 seconds; hole detached to reveal body breathing",
            "frames":interactionFrames,"fps":interactionFPS],
        "backgroundRain": "30 percent of existing emissions are reassigned to dimmer, smaller, slower vertical rain; their trajectories ignore hole controls, composite behind captured glyphs and the dark core, and fade lower down",
        "shadowLight": "captured glyphs emit lensed light into the rear arch and thin foreground blade; ordinary smooth gas is dimmed; a fine photon rim and dark core remain",
        "foregroundCode": "code stays outside the hole; no front-layer exception draws on its surface or reveals captured code on hover",
        "loadBehavior": "smoothed tok/s fades extra wall columns in place and advances continuous motion faster; character identities remain stable; the field moves smoothly with the current radius",
        "pulseAppearance": "upright rain bends into capture; readable disk characters follow curved paths and fracture into glyph-shaped light",
        "capturePathPlane": [plane.x,plane.y,plane.z,plane.w],
        "accretionPlane": ["inclinationRadians":1.52,"rollRadians":0.10,
            "inner":MatrixAccretionGeometry.inner,"outer":MatrixAccretionGeometry.outer(width:configuration.rimWidth)],
        "shadowDiagnostic": "matrix-shadow-diagnostic.png isolates the code-powered disk, shadow and photon rim while hiding incoming and background rain",
        "motionModel": "artistic code trajectories and readable-glyph compensation; compact Schwarzschild light integration adapted from s0xDk/ghostty-blackhole under MIT",
        "maximumPulses": MatrixCodeFlow.maximumPulses,
        "sourceColumns": MatrixCodeFlow.sourceColumns,
        "gatheringBundles": MatrixCodeFlow.gatheringBundles,
        "horizonRadius": previewHole.z,
        "exposedCoreDepth": previewHole.y+previewHole.z-Float(geometry.notchHeight),
        "maximumDepth": NotchFlameGeometry.maximumMatrixDepth,
        "anchorPoints": [geometry.notchWidth, geometry.notchHeight]]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: folder.appendingPathComponent("manifest.json"))
    print("Exported native Matrix gravity wall draft to \(folder.path)")
}

@MainActor
private func flameReviewImage(width:Int,height:Int,scale:CGFloat,
    draw:(CGContext)throws->Void) throws -> CGImage {
    let context = CGContext(data:nil,width:Int(CGFloat(width)*scale),height:Int(CGFloat(height)*scale),
        bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),
        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x:0,y:CGFloat(height)*scale)
    context.scaleBy(x:scale,y:-scale)
    context.setFillColor(NSColor(srgbRed:0.035,green:0.045,blue:0.06,alpha:1).cgColor)
    context.interpolationQuality = .high
    context.fill(CGRect(x:0,y:0,width:width,height:height))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:true)
    defer { NSGraphicsContext.restoreGraphicsState() }
    try draw(context)
    return context.makeImage()!
}

@MainActor
private func flameText(_ text:String,at point:CGPoint,size:CGFloat,color:NSColor) {
    (text as NSString).draw(at:point,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:size,weight:.medium),
        .foregroundColor:color])
}

@MainActor
private func drawFlameSample(context:CGContext,image:CGImage,geometry:NotchFlameGeometry,
    rect:CGRect,background:FlamePreviewBackground,caption:String,zoom:CGFloat = 1) {
    context.saveGState()
    defer { context.restoreGState() }
    context.addPath(CGPath(roundedRect:rect,cornerWidth:10,cornerHeight:10,transform:nil))
    context.clip()
    background.draw(in: rect)
    let origin = CGPoint(x:rect.midX-geometry.size.width*zoom/2,y:rect.minY)
    let notch = CGRect(x:origin.x+geometry.notch.minX*zoom,y:origin.y-8,
        width:geometry.notchWidth*zoom,height:geometry.notchHeight*zoom+8)
    context.setFillColor(NSColor.black.cgColor)
    context.addPath(CGPath(roundedRect:notch,cornerWidth:geometry.cornerRadius*zoom,
        cornerHeight:geometry.cornerRadius*zoom,transform:nil))
    context.fillPath()
    context.saveGState()
    context.translateBy(x:origin.x,y:origin.y+geometry.size.height*zoom)
    context.scaleBy(x:1,y:-1)
    context.draw(image,in:CGRect(x:0,y:0,width:geometry.size.width*zoom,height:geometry.size.height*zoom))
    context.restoreGState()
    if background == .multicolor {
        context.setFillColor(NSColor(srgbRed:0.04,green:0.05,blue:0.07,alpha:1).cgColor)
        context.fill(CGRect(x:rect.minX,y:rect.maxY-30,width:rect.width,height:30))
    }
    flameText(caption,at:CGPoint(x:rect.minX+15,y:rect.maxY-24),size:11,
        color:background == .white ? .darkGray : .lightGray)
}
