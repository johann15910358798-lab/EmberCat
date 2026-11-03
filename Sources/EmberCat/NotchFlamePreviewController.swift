import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FlamePreviewBackground: CaseIterable {
    case dark, white, multicolor
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
        super.init(frame: CGRect(x: 0, y: 0, width: 280, height: 132))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(flame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 280).isActive = true
        heightAnchor.constraint(equalToConstant: 132).isActive = true
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
    private var rates: [Double] = []
    private let presets = NSStackView()
    private let settings: NotchFlameSettings
    private var paletteEditor: NotchFlamePaletteEditor?
    private var previewPalette: NotchFlamePalette?

    init(settings: NotchFlameSettings = .shared, renderer: NotchFlameRenderer? = nil) throws {
        self.settings = settings
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "EmberCat · 火焰设置与预览"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
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
        refreshGeometry()
        if !wasVisible { paletteEditor?.reload() }
        changeSpeed()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        for scene in scenes { scene.flame.stop() }
        paletteEditor?.deactivateColors()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    func deactivateColorWells() { paletteEditor?.deactivateColors() }

    private var geometry: NotchFlameGeometry {
        NotchDisplayProfile.current()?.geometry ?? NotchFlameGeometry(notchWidth: 180, notchHeight: 32)
    }

    private func buildContent(renderer: NotchFlameRenderer) throws {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "刘海流焰")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "滑动调整火焰质感，为不同速度设定自己的颜色。")
        subtitle.textColor = .secondaryLabelColor
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
        let hint = NSTextField(labelWithString: "此窗口使用模拟 tok/s；顶部火焰和菜单栏继续读取真实输出。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title,subtitle,deviceLabel,samples,speedRow,presets,editor,hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor,constant: 20)])
        previewConfiguration(palette: settings.palette, appearance: settings.appearance)
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
        speed.maxValue = palette.previewMaximum
        speed.doubleValue = min(speed.doubleValue, speed.maxValue)
        rates = palette.sampleRates
        for view in presets.arrangedSubviews { presets.removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, rate) in rates.enumerated() {
            let title = index == 0 ? "0 · 熄灭" : "第 \(index) 档 · \(Int(rate.rounded()))"
            let button = NSButton(title: title, target: self, action: #selector(selectRate(_:)))
            button.tag = index
            button.controlSize = .small
            button.widthAnchor.constraint(equalToConstant: min(180, 820 / CGFloat(rates.count))).isActive = true
            button.setAccessibilityIdentifier("flame-preview-band-\(index)")
            presets.addArrangedSubview(button)
        }
        changeSpeed()
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
            preview = try NotchFlamePreviewController()
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
