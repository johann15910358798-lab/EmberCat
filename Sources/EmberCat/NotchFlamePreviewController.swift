import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class FlamePreviewScene: NSView {
    let flame: NotchFlameMetalView
    let light: Bool
    override var isFlipped: Bool { true }

    init(geometry: NotchFlameGeometry, renderer: NotchFlameRenderer, light: Bool) throws {
        self.light = light
        flame = try NotchFlameMetalView(geometry: geometry, renderer: renderer)
        super.init(frame: CGRect(x: 0, y: 0, width: 420, height: 178))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(flame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 420).isActive = true
        heightAnchor.constraint(equalToConstant: 178).isActive = true
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
        let colors: [NSColor] = light
            ? [NSColor(srgbRed: 0.91, green: 0.92, blue: 0.94, alpha: 1),
               NSColor(srgbRed: 0.76, green: 0.80, blue: 0.85, alpha: 1)]
            : [NSColor(srgbRed: 0.07, green: 0.085, blue: 0.11, alpha: 1),
               NSColor(srgbRed: 0.16, green: 0.20, blue: 0.26, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: bounds, angle: 75)
        let geometry = flame.geometry
        let scale = flame.frame.width/geometry.size.width
        let notch = CGRect(x: flame.frame.minX+geometry.notch.minX*scale, y: -8,
            width: geometry.notchWidth*scale, height: geometry.notchHeight*scale+8)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: notch, xRadius: 8*scale, yRadius: 8*scale).fill()
    }
}

@MainActor
final class NotchFlamePreviewController: NSWindowController, NSWindowDelegate {
    private let settings: NotchFlameSettings
    private let speed = NSSlider(value: 45, minValue: 0, maxValue: 220, target: nil, action: nil)
    private let width = NSSlider(value: 1, minValue: 0.6, maxValue: 1.5, target: nil, action: nil)
    private let height = NSSlider(value: 1, minValue: 0.5, maxValue: 1.8, target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")
    private let widthLabel = NSTextField(labelWithString: "")
    private let heightLabel = NSTextField(labelWithString: "")
    private let deviceLabel = NSTextField(labelWithString: "")
    private var scenes: [FlamePreviewScene] = []
    private var screenObserver: NSObjectProtocol?
    private let rates: [Double] = [3,18,45,90,180]

    init(settings: NotchFlameSettings = .shared) throws {
        self.settings = settings
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 610),
            styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "EmberCat · 火焰设置与预览"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        try buildContent()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshGeometry()
        changeSpeed()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        for scene in scenes { scene.flame.isPaused = true }
    }

    private var geometry: NotchFlameGeometry {
        NotchDisplayProfile.current()?.geometry(settings: settings)
            ?? NotchFlameGeometry(notchWidth: 180, notchHeight: 32,
                widthScale: settings.widthScale, heightScale: settings.heightScale)
    }

    private func buildContent() throws {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "从余烬，到炽焰。")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "暗红 → 橙金 → 明黄 → 炽白 → 蓝白，随输出速度连续升温。")
        subtitle.textColor = .secondaryLabelColor
        deviceLabel.font = .systemFont(ofSize: 12)
        deviceLabel.textColor = .secondaryLabelColor
        let renderer = try NotchFlameRenderer()
        scenes = try [false,true].map { try FlamePreviewScene(geometry: geometry, renderer: renderer, light: $0) }
        let boxes = zip(scenes,["深色背景 · 实际尺寸", "浅色背景 · 实际尺寸"]).map { scene,label -> NSStackView in
            let caption = NSTextField(labelWithString: label)
            caption.font = .systemFont(ofSize: 12)
            caption.textColor = .secondaryLabelColor
            let box = NSStackView(views: [scene,caption])
            box.orientation = .vertical
            box.spacing = 8
            return box
        }
        let samples = NSStackView(views: boxes)
        samples.spacing = 20
        for slider in [speed,width,height] {
            slider.target = self
            slider.isContinuous = true
        }
        speed.action = #selector(changeSpeed)
        width.action = #selector(changeSize)
        height.action = #selector(changeSize)
        speed.widthAnchor.constraint(equalToConstant: 610).isActive = true
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let speedRow = NSStackView(views: [speedLabel,speed])
        speedRow.spacing = 20
        let labels = ["3 · 暗红", "18 · 橙金", "45 · 明黄", "90 · 炽白", "180 · 蓝白"]
        let presets = NSStackView(views: labels.enumerated().map { index,label in
            let button = NSButton(title: label, target: self, action: #selector(selectRate(_:)))
            button.tag = index
            button.widthAnchor.constraint(equalToConstant: 143).isActive = true
            return button
        })
        presets.spacing = 12
        let widthRow = sizeRow(title: "火焰宽度", slider: width, value: widthLabel)
        let heightRow = sizeRow(title: "火焰高度", slider: height, value: heightLabel)
        let reset = NSButton(title: "恢复自动适配", target: self, action: #selector(resetSize))
        let hint = NSTextField(labelWithString: "尺寸调节会保存并立即应用。预览速度为模拟输入。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [hint,reset])
        footer.spacing = 26
        let stack = NSStackView(views: [title,subtitle,deviceLabel,samples,speedRow,presets,widthRow,heightRow,footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 17
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor,constant: 24)])
        refreshGeometry()
    }

    private func sizeRow(title: String, slider: NSSlider, value: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 80).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 580).isActive = true
        value.widthAnchor.constraint(equalToConstant: 130).isActive = true
        value.font = .monospacedDigitSystemFont(ofSize: 12,weight: .regular)
        let row = NSStackView(views: [label,slider,value])
        row.spacing = 16
        return row
    }

    @objc private func changeSpeed() {
        speedLabel.stringValue = String(format: "预览 · %.0f tok/s",speed.doubleValue)
        for scene in scenes { scene.flame.setSpeed(speed.doubleValue, active: speed.doubleValue>0.7) }
    }

    @objc private func selectRate(_ sender: NSButton) {
        speed.doubleValue = rates[sender.tag]
        changeSpeed()
    }

    @objc private func changeSize() {
        settings.set(width: CGFloat(width.doubleValue),height: CGFloat(height.doubleValue))
        refreshGeometry()
    }

    @objc private func resetSize() { settings.reset(); refreshGeometry() }

    private func refreshGeometry() {
        width.doubleValue = Double(settings.widthScale)
        height.doubleValue = Double(settings.heightScale)
        let geometry = self.geometry
        widthLabel.stringValue = String(format: "%.0f%% · %.0f pt",width.doubleValue*100,Double(geometry.flameWidth))
        heightLabel.stringValue = String(format: "%.0f%%",height.doubleValue*100)
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
func exportFlamePreview(to folder: URL, resourceDirectory: URL? = nil) throws {
    try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
    let renderer = try NotchFlameRenderer(resourceDirectory: resourceDirectory)
    let profile = NotchDisplayProfile.current()
    let geometry = profile?.geometry(settings: .shared) ?? NotchFlameGeometry(notchWidth: 180,notchHeight: 32)
    let rates: [Double] = [3,18,45,90,180]
    let names = ["DARK RED", "AMBER", "GOLD", "WHITE HEAT", "BLUE WHITE"]
    let column = max(350,Int(geometry.size.width)+52)
    let row = max(138,Int(geometry.size.height)+38)
    let sheet = try flameReviewImage(width: column*2,height: row*5+64,scale: 2) { context in
        flameText("EMBERCAT / HEAT STUDY",at: CGPoint(x:24,y:16),size:20,color:.white)
        for (index,rate) in rates.enumerated() {
            let image = try renderer.image(geometry: geometry,time: 3.75,speed: rate,scale:4)
            for light in [false,true] {
                let rect = CGRect(x: (light ? column : 0)+12,y: 64+index*row,
                    width: column-24,height: row-12)
                drawFlameSample(context: context,image: image,geometry: geometry,rect: rect,light: light,
                    caption: "\(Int(rate)) tok/s  /  \(names[index])")
            }
        }
    }
    try NSBitmapImageRep(cgImage: sheet).representation(using: .png,properties: [:])!
        .write(to: folder.appendingPathComponent("flame-palette.png"))
    let detailWidth=max(740,Int(geometry.size.width*3)+80)
    let detailHeight=Int(geometry.size.height*3)+96
    let detail = try flameReviewImage(width:detailWidth,height:detailHeight,scale:2) { context in
        flameText("UNITY LABS / FLAME DETAIL",at:CGPoint(x:24,y:14),size:18,color:.white)
        let flame = try renderer.image(geometry:geometry,time:3.75,speed:90,scale:6)
        drawFlameSample(context:context,image:flame,geometry:geometry,
            rect:CGRect(x:18,y:52,width:detailWidth-36,height:detailHeight-64),light:false,
            caption:"3X DETAIL / CC0 SOURCE SEQUENCE",zoom:3)
    }
    try NSBitmapImageRep(cgImage:detail).representation(using:.png,properties:[:])!
        .write(to:folder.appendingPathComponent("flame-detail.png"))
    let count = 150
    let gifURL = folder.appendingPathComponent("flame-heat.gif")
    guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL,UTType.gif.identifier as CFString,count,nil)
    else { throw NSError(domain:"EmberCat.FlamePreview",code:1) }
    CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    for tick in 0..<count {
        let time = Double(tick)/15
        let heat = 0.5-0.5*cos(Double(tick)/Double(count)*2*Double.pi)
        let rate = 10*(exp(heat*log(19))-1)
        let image = try renderer.image(geometry: geometry,time: time,speed: rate,active: rate>0.7)
        let frame = try flameReviewImage(width: column*2,height: row+74,scale:1) { context in
            flameText(String(format:"EMBERCAT / %.0f tok/s",rate),at:CGPoint(x:24,y:16),size:20,color:.white)
            flameText("CONTINUOUS HEAT / SIMULATED SPEED",at:CGPoint(x:24,y:43),size:10,color:.lightGray)
            for light in [false,true] {
                drawFlameSample(context:context,image:image,geometry:geometry,
                    rect:CGRect(x:(light ? column:0)+12,y:74,width:column-24,height:row-12),light:light,
                    caption:light ? "LIGHT BACKGROUND" : "DARK BACKGROUND")
            }
        }
        CGImageDestinationAddImage(gif,frame,[kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFDelayTime:1.0/15.0]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(gif) else { throw NSError(domain:"EmberCat.FlamePreview",code:2) }
    let report: [String:Any] = ["renderer":"Unity Labs Flame03-hollow sequence / Metal compositor",
        "sequenceFrames":renderer.sequence.frameCount,"assetLicense":renderer.sequence.license,"fps":15,"frames":count,
        "rates":rates,"device":profile?.summary ?? "preview fixture",
        "anchorPoints":[geometry.notchWidth,geometry.notchHeight],
        "physicalNotch":profile?.notchFrame != nil,
        "widthScale":geometry.widthScale,"heightScale":geometry.heightScale]
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
    rect:CGRect,light:Bool,caption:String,zoom:CGFloat = 1) {
    context.saveGState()
    defer { context.restoreGState() }
    context.addPath(CGPath(roundedRect:rect,cornerWidth:10,cornerHeight:10,transform:nil))
    context.clip()
    context.setFillColor((light ? NSColor(srgbRed:0.87,green:0.89,blue:0.92,alpha:1)
        : NSColor(srgbRed:0.085,green:0.105,blue:0.14,alpha:1)).cgColor)
    context.fill(rect)
    let origin = CGPoint(x:rect.midX-geometry.size.width*zoom/2,y:rect.minY)
    let notch = CGRect(x:origin.x+geometry.notch.minX*zoom,y:origin.y-8,
        width:geometry.notchWidth*zoom,height:geometry.notchHeight*zoom+8)
    context.setFillColor(NSColor.black.cgColor)
    context.addPath(CGPath(roundedRect:notch,cornerWidth:8*zoom,cornerHeight:8*zoom,transform:nil))
    context.fillPath()
    context.saveGState()
    context.translateBy(x:origin.x,y:origin.y+geometry.size.height*zoom)
    context.scaleBy(x:1,y:-1)
    context.draw(image,in:CGRect(x:0,y:0,width:geometry.size.width*zoom,height:geometry.size.height*zoom))
    context.restoreGState()
    flameText(caption,at:CGPoint(x:rect.minX+15,y:rect.maxY-24),size:11,
        color:light ? .darkGray : .lightGray)
}
