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
        selectedEffect = effect ?? settings.effect
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 730),
            styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = isIsolatedDraft ? "EmberCat · Matrix 交互草稿" : "EmberCat · 特效设置与预览"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        if isIsolatedDraft { speed.doubleValue = 90 }
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
        NotchDisplayProfile.current()?.geometry(for: selectedEffect)
            ?? NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: selectedEffect)
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
        let hint = NSTextField(labelWithString: isIsolatedDraft
            ? "模拟 tok/s · 参数仅保存在这份草稿中，不更改已安装应用。"
            : "此窗口使用模拟 tok/s；顶部特效和菜单栏继续读取真实输出。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.setAccessibilityIdentifier("notch-preview-scope")
        let stack = NSStackView(views: [titleLabel,subtitleLabel,effectControl,deviceLabel,samples,
            speedRow,presets,editor,matrix,applyEffectButton,hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor,constant: 20)])
        previewConfiguration(palette: settings.palette, appearance: settings.appearance)
        previewMatrixConfiguration(matrixDraft)
        updateEffectControls()
        refreshGeometry()
    }

    @objc private func changeSpeed() {
        speedLabel.stringValue = String(format: "预览 · %.0f tok/s",speed.doubleValue)
        for scene in scenes { scene.flame.setSpeed(speed.doubleValue, active: speed.doubleValue>0) }
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

    private func rebuildPresets() {
        let palette = previewPalette ?? settings.palette
        speed.maxValue = selectedEffect == .matrix ? 180 : palette.previewMaximum
        speed.doubleValue = min(speed.doubleValue, speed.maxValue)
        rates = selectedEffect == .matrix ? [0, 20, 90, 180] : palette.sampleRates
        for view in presets.arrangedSubviews { presets.removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, rate) in rates.enumerated() {
            let title = index == 0 ? "0 · 熄灭" : selectedEffect == .matrix
                ? "\(["", "慢流", "穿梭", "高速"][index]) · \(Int(rate))"
                : "第 \(index) 档 · \(Int(rate.rounded()))"
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
        updateEffectControls()
        refreshGeometry()
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
        settings.effect = selectedEffect
        settings.isEnabled = true
        updateEffectControls()
    }

    private func updateEffectControls() {
        let matrix = selectedEffect == .matrix
        effectControl.selectedSegment = matrix ? 1 : 0
        titleLabel.stringValue = matrix ? "Matrix · 代码雨" : "刘海流焰"
        subtitleLabel.stringValue = matrix
            ? "配色跟随 macOS：深色荧光绿，浅色墨青绿；下方同时预览两套配色。"
            : "滑动调整火焰质感，为不同速度设定自己的颜色。"
        paletteEditor?.isHidden = matrix
        matrixControls?.isHidden = !matrix
        updateApplyButton()
        if let window {
            let top = window.frame.maxY
            window.setContentSize(NSSize(width: 920, height: matrix ? 708 : 716))
            window.setFrameOrigin(CGPoint(x: window.frame.minX, y: top-window.frame.height))
        }
    }

    private func updateApplyButton() {
        let applied = settings.effect == selectedEffect && settings.isEnabled
            && (selectedEffect != .matrix || matrixDraft == settings.matrixConfiguration)
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
            preview = try NotchFlamePreviewController(effect:
                CommandLine.arguments.contains("--preview-matrix") ? .matrix : .flame)
            preview?.showWindow(nil)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
               visibility: Float = 1, pass: MatrixFlowPass = .composed) throws -> CGImage {
        let rendered = try renderer.image(geometry: geometry, time: time, speed: speed,
            scale: 6, matrixConfiguration: configuration, visibility: visibility, matrixPass: pass)
        return try flameReviewImage(width: width, height: height, scale: scale) { context in
            flameText(pass == .aperture ? "暗核遮挡 · 诊断帧" : pass == .background ? "背景雨 · 不参与吸入"
                : inputSpeed == nil ? "竖直代码雨 · 黑洞吸入草稿" : "代码密度与流速 · tok/s 联动",
                at: CGPoint(x: 24, y: 16), size: 22, color: .white)
            flameText(String(format: "3× 放大 · %.0f tok/s 模拟输入 · 未定稿", inputSpeed ?? speed),
                at: CGPoint(x: 24, y: 46), size: 11, color: .lightGray)
            drawFlameSample(context: context, image: rendered, geometry: geometry,
                rect: CGRect(x: 18, y: 76, width: width - 36, height: height - 88), background: .dark,
                caption: pass == .background ? "独立背景  /  保持竖直  /  不参与引力  /  下方淡出"
                    : "背景直落  /  前景吸入  /  洞口残留  /  黑洞位置可调", zoom: 3)
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
    let radius = Double(MatrixCodeFlow.horizon(geometry: geometry,configuration: configuration).z)
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
    animation.setSpeed(90)
    for _ in 0..<240 {
        animation.advance(by: 1.0 / 60, flow: MatrixCodeFlow.motionMultiplier(heat: animation.heat))
    }
    for _ in 0..<count {
        animation.advance(by: 1 / fps, flow: MatrixCodeFlow.motionMultiplier(heat: animation.heat))
        let renderedSpeed = 180 * pow(animation.heat, 1 / 0.80)
        CGImageDestinationAddImage(destination, try frame(time: animation.phase, scale: 1,
            speed: renderedSpeed, visibility: Float(animation.visibility)),
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
    loadAnimation.setSpeed(responseRates[0])
    for _ in 0..<240 {
        loadAnimation.advance(by: 1.0 / 60,
            flow: MatrixCodeFlow.motionMultiplier(heat: loadAnimation.heat))
    }
    for rate in responseRates {
        loadAnimation.setSpeed(rate)
        for _ in 0..<framesPerStage {
            loadAnimation.advance(by: 1 / fps,
                flow: MatrixCodeFlow.motionMultiplier(heat: loadAnimation.heat))
            let renderedSpeed = 180 * pow(loadAnimation.heat, 1 / 0.80)
            CGImageDestinationAddImage(response, try frame(time: loadAnimation.phase, scale: 1,
                speed: renderedSpeed, inputSpeed: rate, visibility: Float(loadAnimation.visibility)),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
        }
    }
    guard CGImageDestinationFinalize(response) else {
        throw NSError(domain: "EmberCat.MatrixPreview", code: 4)
    }
    let plane = MatrixCodeFlow.diskPlane(geometry: geometry,configuration:configuration)
    let previewHole = MatrixCodeFlow.horizon(geometry:geometry,configuration:configuration)
    let report: [String: Any] = ["renderer": "native Metal / vertical code rain and a movable central sink",
        "status": "design draft; awaiting visual approval; no packaging or installation",
        "input": "isolated synthetic tok/s; no monitor or token records",
        "fps": fps, "frames": count, "simulatedSpeed": 90, "rates": rates,
        "previewConfiguration": ["blackHoleSize":configuration.blackHoleSize,"gravity":configuration.gravity,
            "density":configuration.density,"verticalOffset":configuration.verticalOffset],
        "parameters": NotchMatrixParameter.allCases.map { parameter -> [String: Any] in
            ["key": parameter.rawValue, "title": parameter.title,
                "minimum": parameter.range.lowerBound, "maximum": parameter.range.upperBound,
                "default": NotchMatrixConfiguration.standard[keyPath: parameter.keyPath]]
        },
        "parameterComparison": "matrix-parameters.png; same seed, phase and simulated speed; other parameters at their defaults",
        "appearance": "live overlay follows effective macOS appearance without a separate preference; dark uses fluorescent green, light uses crisp deep teal-green outside the shadow; the black core retains luminous code",
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
        "absorption": "foreground characters drain fully inside the actual shadow before retirement, without lifetime fading; only the independent background rain fades lower down",
        "backgroundRain": "30 percent of existing emissions are reassigned to dimmer, smaller, slower vertical rain; their trajectories ignore hole controls, composite behind captured glyphs and the dark core, and fade lower down",
        "shadowLight": "faint fluorescent-green self-emission on the exposed shadow edge, soft within 6 points outside it; the center remains dark; the notch rim meets the two sides of the opening",
        "foregroundCode": "incoming near-side characters remain visible in front of the shadow until the whole glyph reaches the central drain",
        "loadBehavior": "smoothed tok/s fades extra wall columns in place and advances continuous motion faster; existing characters and paths do not relocate",
        "pulseAppearance": "separate upright characters and character-shaped glow only; no twisting strip mesh, backing, rails or plasma surface",
        "diskPlane": [plane.x,plane.y,plane.z,plane.w],
        "shadowDiagnostic": "matrix-shadow-diagnostic.png deliberately excludes all code to verify no hidden disk surface remains",
        "motionModel": "artistic field; not a relativistic simulation",
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
