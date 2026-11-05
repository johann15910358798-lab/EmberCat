import AppKit
import MetalKit

enum NotchMatrixColorScheme: String, CaseIterable {
    case dark, light

    @MainActor init(appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}

struct NotchFlameGeometry {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var effect: NotchEffectStyle = .flame
    var lightningConfiguration: NotchLightningConfiguration = .standard
    // The two animated generators need room beside the energy bar.
    // Flame and Matrix keep their original narrow rim padding.
    var padding: CGFloat {
        effect == .lightning
            ? ceil(notchWidth * 0.09 + CGFloat(NotchLightningMotion.hamsterSize(notchWidth: notchWidth,
                    scale: lightningConfiguration.hamsterScale)) + CGFloat(lightningConfiguration.hamsterGap) + 7
                + CGFloat(lightningConfiguration.levitation * 0.5 + lightningConfiguration.jitter * 0.6))
            : 5
    }
    static let maximumFlameDepth: CGFloat = 80
    static let maximumMatrixDepth: CGFloat = 112
    static let maximumLightningDepth: CGFloat = 108

    var maximumDepth: CGFloat {
        switch effect {
        case .flame: Self.maximumFlameDepth
        case .matrix: Self.maximumMatrixDepth
        case .lightning: CGFloat(NotchLightningMotion.maximumDepth(configuration: lightningConfiguration))
        }
    }

    var size: CGSize {
        CGSize(width: notchWidth + padding * 2,
            height: notchHeight + maximumDepth + 12)
    }
    var notch: CGRect { CGRect(x: padding, y: 0, width: notchWidth, height: notchHeight) }
    var cornerRadius: CGFloat { min(notchWidth / 2, notchHeight * 9 / 32) }
}

private struct FlameUniforms {
    var viewport: SIMD2<Float>
    var notchOrigin: SIMD2<Float>
    var notchSize: SIMD2<Float>
    var pixelScale: Float
    var time: Float
    var heat: Float
    var visibility: Float
    var drawsAnchor: Float
    var cornerRadius: Float
    var flameColor: SIMD4<Float>
    var style: SIMD4<Float>
    var motion: SIMD4<Float>
    var matrixInteraction: SIMD4<Float>
}

private struct LightningUniforms {
    var shape: SIMD4<Float>
    var pose: SIMD4<Float>
    var hamsterLeft: SIMD4<Float>
    var hamsterRight: SIMD4<Float>
    var hamsterAtlas: SIMD4<Float>
}

/// The live overlay, native previews and exports share the same GPU composition.
@MainActor
final class NotchFlameRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let lightningPipeline: MTLRenderPipelineState
    private let matrixPipeline: MTLRenderPipelineState
    private let matrixPulsePipeline: MTLRenderPipelineState
    private let matrixMatterPipeline: MTLRenderPipelineState
    private let matrixOrbitPipeline: MTLRenderPipelineState
    private let noise: MTLTexture
    private let glyphs: MTLTexture
    private let matrixMatter: MTLTexture
    private let matrixSeed: UInt64
    private let lightningSeed: UInt64
    private var lightningMaterial: NotchLightningMaterial?

    init(matrixSeed: UInt64 = MatrixCodeFlow.sessionSeed,
         lightningSeed: UInt64 = NotchLightningDischarges.sessionSeed) throws {
        self.matrixSeed = matrixSeed
        self.lightningSeed = lightningSeed
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Self.error("Metal is unavailable")
        }
        self.device = device
        self.queue = queue
        let texture = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 128, height: 128, mipmapped: false)
        texture.storageMode = .shared
        texture.usage = .shaderRead
        guard let noise = device.makeTexture(descriptor: texture) else {
            throw Self.error("Could not allocate flame noise")
        }
        self.noise = noise
        var seed: UInt32 = 0x6c3e2d71
        var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<2 {
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                bytes[offset + channel] = UInt8(seed >> 24)
            }
            bytes[offset + 3] = 255
        }
        bytes.withUnsafeBytes {
            noise.replace(region: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 128 * 4)
        }
        glyphs = try Self.makeGlyphAtlas(device: device)
        let matterDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,
            width:1024,height:256,mipmapped:false)
        matterDescriptor.usage = [.renderTarget,.shaderRead]
        matterDescriptor.storageMode = .private
        guard let matrixMatter = device.makeTexture(descriptor:matterDescriptor) else {
            throw Self.error("Could not allocate captured code texture")
        }
        self.matrixMatter = matrixMatter
        let library = try device.makeLibrary(
            source: NotchFlameShader.source + NotchMatrixShader.source + NotchLightningShader.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "flameVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "flameFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "lightningFragment")
        lightningPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "matrixFragment")
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        matrixPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.vertexFunction = library.makeFunction(name: "matrixPulseVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "matrixPulseFragment")
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        matrixPulsePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name:"matrixOrbitGlyphFragment")
        matrixOrbitPipeline = try device.makeRenderPipelineState(descriptor:descriptor)
        descriptor.vertexFunction = library.makeFunction(name:"matrixMatterVertex")
        descriptor.fragmentFunction = library.makeFunction(name:"matrixMatterFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        matrixMatterPipeline = try device.makeRenderPipelineState(descriptor:descriptor)
    }

    func draw(texture: MTLTexture, geometry: NotchFlameGeometry, time: Double,
              heat: Float, visibility: Float = 1, drawsAnchor: Bool = false,
              color: SIMD3<Float> = NotchFlamePalette.standard.color(for: 180),
              appearance: NotchFlameAppearance = .standard,
              matrixConfiguration: NotchMatrixConfiguration = .standard,
              matrixColorScheme: NotchMatrixColorScheme = .dark,
              matrixHover: Double = 0, matrixBreathingTime: Double? = nil,
              lightningMotionTime: Double? = nil,
              hamsterAnimationTime: Double? = nil,
              reduceMotion: Bool = false, drawable: CAMetalDrawable? = nil,
              wait: Bool = false, matrixPass: MatrixFlowPass = .composed) throws {
        if geometry.effect == .lightning, lightningMaterial == nil {
            lightningMaterial = try NotchLightningMaterial(device: device)
        }
        guard let command = queue.makeCommandBuffer() else { throw Self.error("No command buffer") }
        let effectiveTime = reduceMotion ? 8.73 : time
        let hover = matrixHover.isFinite ? min(1,max(0,matrixHover)) : 0
        let radiusScale = MatrixHoleInteraction.radiusScale(heat:Double(heat),
            time:matrixBreathingTime ?? time,reduceMotion:reduceMotion)
        let matrixFrame = geometry.effect == .matrix && visibility > 0.0001 && heat > 0.0001
            ? MatrixCodeFlow.frame(geometry: geometry, time: effectiveTime,
                heat: heat, configuration: matrixConfiguration,radiusScale:radiusScale,pass: matrixPass, seed: matrixSeed)
            : MatrixFlowFrame()
        var uniforms = FlameUniforms(
            viewport: SIMD2(Float(geometry.size.width), Float(geometry.size.height)),
            notchOrigin: SIMD2(Float(geometry.notch.minX), Float(geometry.notch.minY)),
            notchSize: SIMD2(Float(geometry.notchWidth), Float(geometry.notchHeight)),
            pixelScale: Float(texture.width) / Float(geometry.size.width),
            time: Float(effectiveTime),
            heat: heat, visibility: visibility, drawsAnchor: drawsAnchor ? 1 : 0,
            cornerRadius: Float(geometry.cornerRadius),
            flameColor: SIMD4(color.x, color.y, color.z, 1),
            style: SIMD4(Float(appearance.brightness), Float(appearance.core),
                Float(appearance.transparency), Float(appearance.length)),
            motion: SIMD4(Float(appearance.turbulence), Float(matrixFrame.ports.count),
                matrixColorScheme == .light ? 1 : 0,Float(matrixFrame.flashes.count)),
            matrixInteraction: SIMD4(Float(hover),0,0,Float(matrixConfiguration.rimWidth)))
        if geometry.effect == .matrix {
            try encodeMatrixMatter(command:command,frame:matrixFrame,configuration:matrixConfiguration)
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor:pass) else {
            throw Self.error("No render encoder")
        }
        switch geometry.effect {
        case .flame: encoder.setRenderPipelineState(pipeline)
        case .matrix: encoder.setRenderPipelineState(matrixPipeline)
        case .lightning: encoder.setRenderPipelineState(lightningPipeline)
        }
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlameUniforms>.stride, index: 0)
        if geometry.effect == .matrix {
            var horizon = MatrixCodeFlow.horizon(geometry: geometry, configuration: matrixConfiguration,radiusScale:radiusScale)
            encoder.setFragmentBytes(&horizon, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            let flashes = matrixFrame.flashes.isEmpty ? [SIMD4<Float>.zero] : matrixFrame.flashes.map(\.uniform)
            flashes.withUnsafeBufferPointer { buffer in
                encoder.setFragmentBytes(buffer.baseAddress!,length:buffer.count*MemoryLayout<SIMD4<Float>>.stride,index:3)
            }
            let ports = matrixFrame.ports.isEmpty ? [SIMD4<Float>.zero] : matrixFrame.ports.map(\.uniform)
            ports.withUnsafeBufferPointer { buffer in
                encoder.setFragmentBytes(buffer.baseAddress!,
                    length: buffer.count * MemoryLayout<SIMD4<Float>>.stride, index: 1)
            }
        }
        encoder.setFragmentTexture(noise, index: 0)
        encoder.setFragmentTexture(glyphs, index: 1)
        encoder.setFragmentTexture(matrixMatter,index:2)
        if geometry.effect == .lightning {
            let configuration = geometry.lightningConfiguration
            let manifest = lightningMaterial!.hamsterManifest
            let hamsterTime = reduceMotion ? 0 : hamsterAnimationTime
                ?? (lightningMotionTime ?? time)*configuration.hamsterSpeed
            let hamsterSize = NotchLightningMotion.hamsterSize(notchWidth: geometry.notchWidth,
                scale: configuration.hamsterScale)
            let discharges = NotchLightningDischarges.events(phase: effectiveTime, seed: lightningSeed)
            let pose = NotchLightningMotion.pose(elapsed: lightningMotionTime ?? time,
                phase: effectiveTime, heat: Double(heat), configuration: configuration,
                notchWidth: Double(geometry.notchWidth), reduceMotion: reduceMotion, discharges: discharges)
            var lightning = LightningUniforms(
                shape: SIMD4(Float(configuration.thickness), Float(configuration.distance),
                    Float(configuration.arcs), Float(configuration.hamsterGap)), pose: pose.uniform,
                hamsterLeft: manifest.frameIndices(at: hamsterTime, size: hamsterSize),
                hamsterRight: manifest.frameIndices(at: hamsterTime, offset: reduceMotion ? 0 : 0.23),
                hamsterAtlas: SIMD4(Float(manifest.columns), Float(manifest.rows),
                    Float(manifest.wheelAnchor[0]), Float(manifest.wheelAnchor[1])))
            encoder.setFragmentBytes(&lightning, length: MemoryLayout<LightningUniforms>.stride, index: 1)
            discharges.map(\.uniform).withUnsafeBufferPointer { buffer in
                encoder.setFragmentBytes(buffer.baseAddress!,
                    length: buffer.count * MemoryLayout<NotchLightningDischargeUniform>.stride, index: 2)
            }
            encoder.setFragmentTexture(lightningMaterial?.hamsters, index: 3)
            encoder.setFragmentTexture(lightningMaterial?.leaks, index: 4)
            encoder.setFragmentTexture(lightningMaterial?.energy, index: 5)
        }
        if geometry.effect != .matrix {
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if geometry.effect == .matrix, visibility > 0.0001, heat > 0.0001 {
            let vertices = matrixFrame.vertices
            if !vertices.isEmpty {
                encoder.setRenderPipelineState(matrixPulsePipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<FlameUniforms>.stride, index: 0)
                vertices.withUnsafeBufferPointer { buffer in
                    for start in stride(from: 0, to: buffer.count, by: MatrixCodeFlow.maximumInlineVertices) {
                        let count = min(MatrixCodeFlow.maximumInlineVertices, buffer.count - start)
                        encoder.setVertexBytes(buffer.baseAddress!.advanced(by: start),
                            length: count * MemoryLayout<MatrixPulseVertex>.stride, index: 1)
                        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
                    }
                }
            }
        }
        if geometry.effect == .matrix {
            // The luminous disk covers approaching code at its actual crossings.
            // Capture masks still hide glyphs when hover makes the core transparent.
            encoder.setRenderPipelineState(matrixPipeline)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            let diskGlyphs = matrixFrame.diskMatter.flatMap(\.glyphVertices)
            if !diskGlyphs.isEmpty {
                encoder.setRenderPipelineState(matrixOrbitPipeline)
                encoder.setVertexBytes(&uniforms,length:MemoryLayout<FlameUniforms>.stride,index:0)
                diskGlyphs.withUnsafeBufferPointer { buffer in
                    for start in stride(from:0,to:buffer.count,by:MatrixCodeFlow.maximumInlineVertices) {
                        let count = min(MatrixCodeFlow.maximumInlineVertices,buffer.count-start)
                        encoder.setVertexBytes(buffer.baseAddress!.advanced(by:start),
                            length:count*MemoryLayout<MatrixPulseVertex>.stride,index:1)
                        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:count)
                    }
                }
            }
        }
        encoder.endEncoding()
        if let drawable { command.present(drawable) }
        command.commit()
        if wait {
            command.waitUntilCompleted()
            if let error = command.error { throw error }
        }
    }

    private func encodeMatrixMatter(command:MTLCommandBuffer,frame:MatrixFlowFrame,
                                    configuration:NotchMatrixConfiguration) throws {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = matrixMatter
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor:pass) else {
            throw Self.error("No captured code encoder")
        }
        encoder.setRenderPipelineState(matrixMatterPipeline)
        encoder.setFragmentTexture(glyphs,index:1)
        let outer = MatrixAccretionGeometry.outer(width:configuration.rimWidth)
        let vertices = frame.diskMatter.flatMap { $0.vertices(outer:outer) }
        if !vertices.isEmpty {
            vertices.withUnsafeBufferPointer { buffer in
                for start in stride(from:0,to:buffer.count,by:MatrixCodeFlow.maximumInlineVertices) {
                    let count = min(MatrixCodeFlow.maximumInlineVertices,buffer.count-start)
                    encoder.setVertexBytes(buffer.baseAddress!.advanced(by:start),
                        length:count*MemoryLayout<MatrixPulseVertex>.stride,index:1)
                    encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:count)
                }
            }
        }
        encoder.endEncoding()
    }

    func image(geometry: NotchFlameGeometry, time: Double, speed: Double,
               scale: CGFloat = 2, active: Bool = true, drawsAnchor: Bool = false,
               palette: NotchFlamePalette = .standard,
               color: SIMD3<Float>? = nil, appearance: NotchFlameAppearance = .standard,
               matrixConfiguration: NotchMatrixConfiguration = .standard,
               matrixColorScheme: NotchMatrixColorScheme = .dark,
               matrixHover: Double = 0, matrixBreathingTime: Double? = nil,
               lightningConfiguration: NotchLightningConfiguration? = nil,
               lightningMotionTime: Double? = nil,
               hamsterAnimationTime: Double? = nil,
               visibility: Float = 1,
               reduceMotion: Bool = false, matrixPass: MatrixFlowPass = .composed) throws -> CGImage {
        var geometry = geometry
        if let lightningConfiguration, lightningConfiguration.validationError == nil {
            geometry.lightningConfiguration = lightningConfiguration
        }
        let width = Int((geometry.size.width * scale).rounded())
        let height = Int((geometry.size.height * scale).rounded())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Self.error("Could not allocate preview texture")
        }
        let heat = Float(NotchFlameAnimation.heat(for: speed))
        try draw(texture: texture, geometry: geometry, time: time,
            heat: heat, visibility: active && heat > 0 ? visibility : 0,
            drawsAnchor: drawsAnchor, color: color ?? palette.color(for: speed),
            appearance: appearance, matrixConfiguration: matrixConfiguration, matrixColorScheme: matrixColorScheme,
            matrixHover:matrixHover, matrixBreathingTime:matrixBreathingTime,
            lightningMotionTime: lightningMotionTime,
            hamsterAnimationTime: hamsterAnimationTime,
            reduceMotion: reduceMotion, wait: true, matrixPass: matrixPass)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                    .union(.byteOrder32Little), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw Self.error("Could not encode preview image") }
        return image
    }

    private static func error(_ description: String) -> NSError {
        NSError(domain: "EmberCat.Flame", code: 1,
            userInfo: [NSLocalizedDescriptionKey: description])
    }

    /// Rasterize once at startup; every rain layer samples the same antialiased glyph atlas.
    private static func makeGlyphAtlas(device: MTLDevice) throws -> MTLTexture {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフ")
        let cell = 32, side = cell * 8
        guard let context = CGContext(data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw error("Could not allocate code rain glyph atlas")
        }
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for (index, character) in characters.prefix(64).enumerated() {
            let font = index < 36 ? NSFont.monospacedSystemFont(ofSize: 26, weight: .medium)
                : NSFont(name: "HiraginoSans-W5", size: 25) ?? NSFont.systemFont(ofSize: 25)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let text = String(character) as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: CGFloat(index % 8 * cell) + (CGFloat(cell) - size.width) / 2,
                y: CGFloat(index / 8 * cell) + (CGFloat(cell) - size.height) / 2), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: side, height: side, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor), let data = context.data else {
            throw error("Could not upload code rain glyph atlas")
        }
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
            withBytes: data, bytesPerRow: side * 4)
        return texture
    }
}

@MainActor
final class NotchFlameMetalView: MTKView, MTKViewDelegate {
    var geometry: NotchFlameGeometry
    var drawsAnchor = false
    var onFadeOut: (() -> Void)?
    var onRenderFailure: (() -> Void)?
    private let renderer: NotchFlameRenderer
    private var animation = NotchFlameAnimation()
    private var holeInteraction = MatrixHoleInteraction()
    private(set) var lightningElapsed: Double = 0
    private(set) var hamsterElapsed: Double = 0
    var matrixHoverAmount: Double { holeInteraction.hover }
    var matrixBreathingElapsed: Double { holeInteraction.elapsed }
    var matrixRadiusScale: Double {
        MatrixHoleInteraction.radiusScale(heat:animation.heat,time:holeInteraction.elapsed,reduceMotion:reduceMotion())
    }
    var matrixHorizon: SIMD4<Float> {
        MatrixCodeFlow.horizon(geometry:geometry,configuration:matrixConfiguration,radiusScale:matrixRadiusScale)
    }
    private let mouseLocation: @MainActor () -> CGPoint
    private let reduceMotion: @MainActor () -> Bool
    private var reducedPointerTimer: Timer?
    var isTrackingMatrixPointer: Bool { effect == .matrix && (isRendering || reducedPointerTimer != nil) }
    var animationPhase: Double { animation.phase }
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var accessibilityObserver: NSObjectProtocol?
    private(set) var palette: NotchFlamePalette = .standard
    private(set) var flameAppearance: NotchFlameAppearance = .standard
    private(set) var matrixConfiguration: NotchMatrixConfiguration = .standard
    private(set) var lightningConfiguration: NotchLightningConfiguration = .standard
    // The live overlay inherits macOS appearance. Only fixed preview backgrounds override it.
    var matrixColorSchemeOverride: NotchMatrixColorScheme? {
        didSet {
            if oldValue != matrixColorSchemeOverride { redrawAppearanceIfNeeded() }
        }
    }
    var matrixColorScheme: NotchMatrixColorScheme {
        matrixColorSchemeOverride ?? NotchMatrixColorScheme(appearance: effectiveAppearance)
    }
    var effect: NotchEffectStyle { geometry.effect }
    private var lastSpeed: Double = 0
    private var lastActive = true
    private(set) var renderedFrameCount: UInt64 = 0
    private var frameLink: CADisplayLink?
    var isRendering: Bool { frameLink != nil }

    init(geometry: NotchFlameGeometry, renderer: NotchFlameRenderer? = nil,
         mouseLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
         reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) throws {
        self.geometry = geometry
        self.lightningConfiguration = geometry.lightningConfiguration
        self.mouseLocation = mouseLocation
        self.reduceMotion = reduceMotion
        let renderer = try renderer ?? NotchFlameRenderer()
        self.renderer = renderer
        super.init(frame: CGRect(origin: .zero, size: geometry.size), device: renderer.device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = false
        preferredFramesPerSecond = 60
        autoResizeDrawable = false
        enableSetNeedsDisplay = false
        isPaused = true
        delegate = self
        refreshDisplay()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshDisplay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pauseFrames()
        stopReducedPointerTracking()
        refreshDisplay()
        if window != nil { resumeIfNeeded() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshDisplay()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redrawAppearanceIfNeeded()
    }

    private func redrawAppearanceIfNeeded() {
        // A frozen reduced-motion preview still changes palette immediately.
        if effect != .flame, !isRendering, !animation.isHidden { draw() }
    }

    func refreshDisplay(maximumFramesPerSecond: Int? = nil) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let size = CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
        if drawableSize != size { drawableSize = size }
        preferredFramesPerSecond = NotchDisplayProfile.frameRate(
            for: maximumFramesPerSecond ?? window?.screen?.maximumFramesPerSecond ?? 60)
        updateFrameRate()
        // A paused reduced-motion surface still needs one redraw after a resize or display change.
        if !isRendering, !animation.isHidden { draw() }
    }

    func setSpeed(_ speed: Double, active: Bool = true) {
        lastSpeed = speed
        lastActive = active
        animation.setSpeed(speed, active: active, color: palette.color(for: speed))
        if accessibilityObserver == nil {
            accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeIfNeeded() }
            }
        }
        resumeIfNeeded()
    }

    func setPalette(_ palette: NotchFlamePalette) {
        guard palette != self.palette, palette.validationError == nil else { return }
        self.palette = palette
        setSpeed(lastSpeed, active: lastActive)
    }

    func setAppearance(_ appearance: NotchFlameAppearance) {
        guard appearance != flameAppearance, appearance.validationError == nil else { return }
        flameAppearance = appearance
        // Reduced motion still updates an edited material once without starting a loop.
        if !isRendering, !animation.isHidden { draw() }
    }

    func setMatrixConfiguration(_ configuration: NotchMatrixConfiguration) {
        guard configuration != matrixConfiguration, configuration.validationError == nil else { return }
        matrixConfiguration = configuration
        // Tuning keeps the running phase; reduced motion redraws just once.
        if !isRendering, !animation.isHidden { draw() }
    }

    func setLightningConfiguration(_ configuration: NotchLightningConfiguration) {
        guard configuration != lightningConfiguration, configuration.validationError == nil else { return }
        lightningConfiguration = configuration
        geometry.lightningConfiguration = configuration
        // Tuning preserves the independent energy, suspension and GIF clocks.
        if !isRendering, !animation.isHidden { draw() }
    }

    private func resumeIfNeeded() {
        let reduced = reduceMotion()
        updateReducedPointerTracking()
        guard animation.needsFrames(reduceMotion: reduced) else { pauseFrames(); return }
        guard frameLink == nil, window != nil else { return }
        lastTime = ProcessInfo.processInfo.systemUptime
        // MTKView's internal loop can remain stopped after a preview window closes.
        // Own the display link so editing, tracking and reopening share one lifecycle.
        frameLink = displayLink(target: self, selector: #selector(displayFrame(_:)))
        updateFrameRate()
        frameLink?.add(to: .main, forMode: .common)
    }

    private func updateFrameRate() {
        let fps = Float(preferredFramesPerSecond)
        frameLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, fps), maximum: fps, preferred: fps)
    }

    @objc private func displayFrame(_ link: CADisplayLink) {
        draw()
    }

    private func pauseFrames() {
        frameLink?.invalidate()
        frameLink = nil
    }

    /// Screen coordinates use a lower-left origin; the shader uses top-down points.
    func matrixContainsPointer(at screenPoint: CGPoint) -> Bool {
        guard effect == .matrix,let window,window.isVisible,!isHiddenOrHasHiddenAncestor,
              bounds.width > 0,bounds.height > 0,screenPoint.x.isFinite,screenPoint.y.isFinite else { return false }
        let local = convert(window.convertPoint(fromScreen:screenPoint),from:nil)
        let x = (local.x-bounds.minX)*geometry.size.width/bounds.width
        let y = (isFlipped ? local.y-bounds.minY : bounds.maxY-local.y)*geometry.size.height/bounds.height
        let hole = matrixHorizon
        let dx = Double(x)-Double(hole.x),dy = Double(y)-Double(hole.y)
        guard y >= geometry.notchHeight else { return false }
        let radius = Double(hole.z)
        if dx*dx+dy*dy <= pow(radius+2,2) { return true }
        // Include the exposed disk as well as the core. Match its tilt and
        // width control without observing any mouse events outside this view.
        let width = min(1,max(0,(matrixConfiguration.rimWidth-0.4)/1.4))
        let outer = (5.6+1.65*width)/2.5980762
        let diskX = (0.995*dx+0.100*dy)/(radius*outer+2)
        let diskY = (-0.100*dx+0.995*dy)/(radius*(1.55+0.15*width)+2)
        return diskX*diskX+diskY*diskY <= 1
    }

    private func stopReducedPointerTracking() {
        reducedPointerTimer?.invalidate()
        reducedPointerTimer = nil
    }

    private func updateReducedPointerTracking() {
        guard effect == .matrix,window?.isVisible == true,!animation.isHidden,
              reduceMotion() else {
            stopReducedPointerTracking()
            return
        }
        guard reducedPointerTimer == nil else { return }
        // Cursor polling works through a click-through panel without global event
        // monitors. A reduced-motion surface redraws only when the hit result changes.
        let timer = Timer(timeInterval:1.0/12,repeats:true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                let target = self.matrixContainsPointer(at:self.mouseLocation()) ? 1.0 : 0.0
                if target != self.holeInteraction.hover { self.draw() }
            }
        }
        reducedPointerTimer = timer
        RunLoop.main.add(timer,forMode:.common)
    }

    func stop() {
        pauseFrames()
        stopReducedPointerTracking()
        holeInteraction.reset()
        lightningElapsed = 0
        hamsterElapsed = 0
        animation.reset()
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = ProcessInfo.processInfo.systemUptime
        let reduced = reduceMotion()
        let delta = now-lastTime
        let flow: Double
        switch effect {
        case .flame: flow = flameAppearance.flow
        case .matrix: flow = MatrixCodeFlow.motionMultiplier(heat: animation.heat)
        case .lightning: flow = lightningConfiguration.flow
        }
        animation.advance(by: delta, reduceMotion: reduced, flow: flow)
        if effect == .matrix {
            holeInteraction.advance(by:delta,hovered:matrixContainsPointer(at:mouseLocation()),
                reduceMotion:reduced)
        } else { holeInteraction.reset() }
        if effect == .lightning {
            if !reduced, delta.isFinite {
                let step = min(0.1, max(0, delta))
                lightningElapsed += step
                hamsterElapsed += step*lightningConfiguration.hamsterSpeed
            }
        } else {
            lightningElapsed = 0
            hamsterElapsed = 0
        }
        lastTime = now
        guard let drawable = currentDrawable else {
            if animation.isHidden {
                pauseFrames()
                stopReducedPointerTracking()
                onFadeOut?()
            }
            return
        }
        do {
            try renderer.draw(texture: drawable.texture, geometry: geometry,
                time: animation.phase, heat: Float(animation.heat),
                visibility: Float(animation.visibility), drawsAnchor: drawsAnchor,
                color: animation.color, appearance: flameAppearance, matrixConfiguration: matrixConfiguration,
                matrixColorScheme: matrixColorScheme,
                matrixHover:holeInteraction.hover,matrixBreathingTime:holeInteraction.elapsed,
                lightningMotionTime: lightningElapsed,
                hamsterAnimationTime: hamsterElapsed,
                reduceMotion: reduced, drawable: drawable)
            renderedFrameCount &+= 1
        } catch {
            NSLog("EmberCat flame frame: %@", error.localizedDescription)
            stop()
            onRenderFailure?()
            return
        }
        if !animation.needsFrames(reduceMotion: reduced) {
            pauseFrames()
            if animation.isHidden { onFadeOut?() }
        }
        updateReducedPointerTracking()
    }
}
