import AppKit
import MetalKit

struct NotchFlameGeometry {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let widthScale: CGFloat
    let heightScale: CGFloat
    let padding: CGFloat = 18
    var tail: CGFloat { 66 * heightScale + 8 }

    init(notchWidth: CGFloat, notchHeight: CGFloat, widthScale: CGFloat = 1, heightScale: CGFloat = 1) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.widthScale = widthScale
        self.heightScale = heightScale
    }

    var size: CGSize { CGSize(width: max(notchWidth, flameWidth) + padding * 2, height: notchHeight + tail) }
    var flameWidth: CGFloat { notchWidth * widthScale }
    var notch: CGRect { CGRect(x: (size.width-notchWidth)/2, y: 0, width: notchWidth, height: notchHeight) }

    /// A continuous visual temperature, with useful range at ordinary token rates.
    static func heat(for speed: Double) -> Float {
        guard speed.isFinite else { return 0 }
        return Float(min(1, log1p(max(0, speed) / 10) / log(19)))
    }
}

private struct FlameUniforms {
    var viewport: SIMD2<Float>
    var notchOrigin: SIMD2<Float>
    var notchSize: SIMD2<Float>
    var flameSize: SIMD2<Float>
    var atlas: SIMD4<Float>
    var time: Float
    var heat: Float
    var visibility: Float
    var reduceMotion: Float
}

struct FlameSequence: Decodable {
    let name: String
    let license: String
    let frameWidth: Int
    let frameHeight: Int
    let gridColumns: Int
    let gridRows: Int
    let frameCount: Int
    let framesPerSecond: Double
}

/// The overlay, preview and export sample the same CC0 Houdini-rendered sequence.
@MainActor
final class NotchFlameRenderer {
    let device: MTLDevice
    let sequence: FlameSequence
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let atlas: MTLTexture

    init(resourceDirectory: URL? = nil) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Self.error("Metal is unavailable")
        }
        self.device = device
        self.queue = queue
        let folder = try resourceDirectory ?? Self.resourceDirectory()
        sequence = try JSONDecoder().decode(FlameSequence.self,
            from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        guard sequence.frameCount > 1, sequence.gridColumns > 0, sequence.gridRows > 0,
              sequence.frameCount <= sequence.gridColumns * sequence.gridRows,
              sequence.framesPerSecond > 0 else { throw Self.error("Invalid flame sequence metadata") }
        atlas = try MTKTextureLoader(device: device).newTexture(
            URL: folder.appendingPathComponent("fire-atlas.png"), options: [
                .SRGB: false, .origin: MTKTextureLoader.Origin.topLeft,
                .generateMipmaps: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue
            ])
        guard atlas.width == sequence.frameWidth * sequence.gridColumns,
              atlas.height == sequence.frameHeight * sequence.gridRows else {
            throw Self.error("Flame atlas dimensions do not match its metadata")
        }
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "flameVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "flameFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func draw(texture: MTLTexture, geometry: NotchFlameGeometry, time: Double,
              heat: Float, visibility: Float = 1, reduceMotion: Bool = false,
              drawable: CAMetalDrawable? = nil, wait: Bool = false) throws {
        guard let command = queue.makeCommandBuffer() else { throw Self.error("No command buffer") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw Self.error("No render encoder")
        }
        var uniforms = FlameUniforms(
            viewport: SIMD2(Float(geometry.size.width), Float(geometry.size.height)),
            notchOrigin: SIMD2(Float(geometry.notch.minX), Float(geometry.notch.minY)),
            notchSize: SIMD2(Float(geometry.notchWidth), Float(geometry.notchHeight)),
            flameSize: SIMD2(Float(geometry.flameWidth), Float(geometry.heightScale)),
            atlas: SIMD4(Float(sequence.gridColumns), Float(sequence.gridRows),
                Float(sequence.frameCount), Float(sequence.framesPerSecond)),
            time: Float(reduceMotion ? 4.25 : time), heat: heat,
            visibility: visibility, reduceMotion: reduceMotion ? 1 : 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlameUniforms>.stride, index: 0)
        encoder.setFragmentTexture(atlas, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable { command.present(drawable) }
        command.commit()
        if wait {
            command.waitUntilCompleted()
            if let error = command.error { throw error }
        }
    }

    func image(geometry: NotchFlameGeometry, time: Double, speed: Double,
               scale: CGFloat = 2, active: Bool = true, reduceMotion: Bool = false) throws -> CGImage {
        let width = Int((geometry.size.width * scale).rounded())
        let height = Int((geometry.size.height * scale).rounded())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Self.error("Could not allocate preview texture")
        }
        try draw(texture: texture, geometry: geometry, time: time,
            heat: NotchFlameGeometry.heat(for: speed), visibility: active ? 1 : 0,
            reduceMotion: reduceMotion, wait: true)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
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

    private static func resourceDirectory() throws -> URL {
        var roots = [Bundle.main.resourceURL]
        #if SWIFT_PACKAGE
        roots.append(Bundle.module.resourceURL)
        #endif
        for root in roots.compactMap({ $0 }) {
            let folder = root.appendingPathComponent("NotchFlame", isDirectory: true)
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) {
                return folder
            }
        }
        throw error("Bundled flame sequence is missing")
    }

    // Premultiplied output is essential: no black rectangle or dark fringe on a light desktop.
    private static let shader = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 viewport;
        float2 notchOrigin;
        float2 notchSize;
        float2 flameSize;
        float4 atlas;
        float time;
        float heat;
        float visibility;
        float reduceMotion;
    };
    struct Vertex { float4 position [[position]]; float2 uv; };

    vertex Vertex flameVertex(uint id [[vertex_id]]) {
        float2 p = id == 0 ? float2(-1,-1) : id == 1 ? float2(3,-1) : float2(-1,3);
        return { float4(p,0,1), float2((p.x+1)*0.5, (1-p.y)*0.5) };
    }

    float3 thermal(float heat, float3 a, float3 b, float3 c, float3 d, float3 e) {
        float t=clamp(heat,0.0,1.0)*4.0;
        if(t<1.0) return mix(a,b,smoothstep(0.0,1.0,t));
        if(t<2.0) return mix(b,c,smoothstep(0.0,1.0,t-1.0));
        if(t<3.0) return mix(c,d,smoothstep(0.0,1.0,t-2.0));
        return mix(d,e,smoothstep(0.0,1.0,t-3.0));
    }

    float roundedBox(float2 p,float2 center,float2 halfSize,float radius) {
        float2 q=abs(p-center)-halfSize+radius;
        return length(max(q,0.0))+min(max(q.x,q.y),0.0)-radius;
    }

    float3 sequenceFrame(texture2d<float> atlas, float2 uv, float frame, float4 layout) {
        constexpr sampler linearSampler(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 size=float2(atlas.get_width(),atlas.get_height());
        float2 cellSize=size/layout.xy;
        float2 cell=float2(fmod(frame,layout.x),floor(frame/layout.x));
        // Half-texel bounds prevent another frame leaking into the flame edge.
        float2 point=(cell*cellSize+0.5+uv*(cellSize-1.0))/size;
        return atlas.sample(linearSampler,point).rgb;
    }

    fragment float4 flameFragment(Vertex in [[stage_in]], constant Uniforms &u [[buffer(0)]],
                                  texture2d<float> atlas [[texture(0)]]) {
        float2 p=in.uv*u.viewport;
        float2 center=u.notchOrigin+u.notchSize*0.5;
        if(u.visibility<0.001 || roundedBox(p,center,u.notchSize*0.5,8.0)<0.0) return float4(0);
        float h=clamp(u.heat,0.0,1.0);
        float x=p.x-center.x;
        float y=p.y-(u.notchOrigin.y+u.notchSize.y);
        const float positions[7]={-0.43,-0.29,-0.14,0.02,0.18,0.33,0.44};
        const float widths[7]={0.20,0.23,0.22,0.25,0.19,0.22,0.18};
        const float heights[7]={0.70,0.90,0.85,1.0,0.78,0.86,0.62};
        const float rates[7]={0.83,0.91,0.75,0.87,0.79,0.94,0.81};
        float3 color=float3(0);
        float alpha=0.0;
        for(int i=0;i<7;++i) {
            float width=u.flameSize.x*widths[i];
            float height=(22.0+54.0*h)*u.flameSize.y*heights[i];
            float2 uv=float2((x-u.flameSize.x*positions[i])/width+0.5,
                1.0-(y+5.0*u.flameSize.y)/height);
            if(any(uv<0.0) || any(uv>1.0)) continue;
            if(i==1 || i==4) uv.x=1.0-uv.x;
            float frame=fmod(u.time*u.atlas.w*rates[i]+float(i)*31.7,u.atlas.z);
            float3 source=mix(sequenceFrame(atlas,uv,floor(frame),u.atlas),
                sequenceFrame(atlas,uv,fmod(floor(frame)+1.0,u.atlas.z),u.atlas),fract(frame));
            float signal=max(source.r,max(source.g,source.b));
            if(signal<0.002) continue;
            // Keep the original rendered luminance and internal folds. Only the
            // temperature palette changes with tok/s; no procedural flame shape.
            float3 dark=source*float3(0.80,0.25,0.10);
            float3 amber=source*float3(1.0,0.80,0.70);
            float3 gold=source*float3(1.0,1.15,1.35);
            float3 white=mix(source,float3(source.r),float3(0,0.42,0.55));
            float3 blue=float3(source.b*0.55+source.r*0.30,source.g*0.65+source.r*0.33,source.r);
            float3 emission=clamp(thermal(h,dark,amber,gold,white,blue),0.0,1.0)*0.95;
            float a=max(emission.r,max(emission.g,emission.b));
            color+=(1.0-alpha)*emission;
            alpha+=(1.0-alpha)*a;
        }
        float edge=1.0-smoothstep(u.flameSize.x*0.47,u.flameSize.x*0.55,abs(x));
        float boundsFade=smoothstep(0.0,4.0,p.x)*smoothstep(0.0,4.0,u.viewport.x-p.x)
            *smoothstep(0.0,6.0,u.viewport.y-p.y);
        float opacity=edge*boundsFade*u.visibility;
        return float4(color*opacity,alpha*opacity);
    }
    """#
}

@MainActor
final class NotchFlameMetalView: MTKView, MTKViewDelegate {
    var geometry: NotchFlameGeometry
    var onFadeOut: (() -> Void)?
    private let renderer: NotchFlameRenderer
    private let startTime = ProcessInfo.processInfo.systemUptime
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var heat: Float = 0
    private var targetHeat: Float = 0
    private var visibility: Float = 0
    private var targetVisibility: Float = 0

    init(geometry: NotchFlameGeometry, renderer: NotchFlameRenderer? = nil) throws {
        self.geometry = geometry
        let renderer = try renderer ?? NotchFlameRenderer()
        self.renderer = renderer
        super.init(frame: CGRect(origin: .zero, size: geometry.size), device: renderer.device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0,0,0,0)
        layer?.isOpaque = false
        preferredFramesPerSecond = 30
        autoResizeDrawable = false
        enableSetNeedsDisplay = false
        isPaused = true
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = max(2,window?.backingScaleFactor ?? 2)
        drawableSize = CGSize(width:ceil(bounds.width*scale),height:ceil(bounds.height*scale))
    }

    func setSpeed(_ speed: Double, active: Bool = true) {
        targetHeat = NotchFlameGeometry.heat(for: speed)
        targetVisibility = active ? 1 : 0
        if !active && visibility == 0 { isPaused = true; return }
        if isPaused {
            lastTime = ProcessInfo.processInfo.systemUptime
            isPaused = false
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(0.1,max(0,now-lastTime))
        lastTime = now
        heat += (targetHeat-heat)*Float(1-exp(-delta/0.48))
        visibility += (targetVisibility-visibility)*Float(1-exp(-delta/0.12))
        let settled = targetVisibility == 0 && visibility < 0.004
        if settled { visibility = 0 }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let drawable = currentDrawable else { return }
        do {
            try renderer.draw(texture: drawable.texture, geometry: geometry,
                time: now-startTime, heat: heat, visibility: visibility,
                reduceMotion: reduced, drawable: drawable)
        } catch {
            NSLog("EmberCat flame frame: %@", error.localizedDescription)
        }
        if settled {
            isPaused = true
            onFadeOut?()
        } else if reduced && abs(targetHeat-heat)<0.001 && abs(targetVisibility-visibility)<0.001 {
            isPaused = true
        }
    }
}
