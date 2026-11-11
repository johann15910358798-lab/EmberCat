import AppKit
import ImageIO
import Metal

struct NotchLightningHamsterClip: Decodable {
    let name: String
    let firstFrame: Int
    let frameDurations: [Double]

    var duration: Double { frameDurations.reduce(0, +) }

    func frame(at elapsed: Double, offset: Double = 0) -> Int {
        Int(framePosition(at: elapsed, offset: offset))
    }

    func framePosition(at elapsed: Double, offset: Double = 0) -> Double {
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        var position = ((time+1e-9).truncatingRemainder(dividingBy: duration) + offset*duration)
            .truncatingRemainder(dividingBy: duration)
        for (index, duration) in frameDurations.enumerated() {
            if position < duration {
                // Keep Float conversion inside this cell, including the final
                // frame whose next sample wraps to this clip's first frame.
                return Double(firstFrame+index)+min(0.9999,position/duration)
            }
            position -= duration
        }
        return Double(firstFrame+frameDurations.count-1)
    }
}

struct NotchLightningHamsterManifest: Decodable {
    let cellSize: Int
    let columns: Int
    let rows: Int
    let frameCount: Int
    let wheelAnchor: [Double]
    let clips: [NotchLightningHamsterClip]

    var isValid: Bool {
        guard cellSize == 224, columns == 8, rows == 9, frameCount == 72,
              wheelAnchor.count == 2, wheelAnchor.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              clips.map(\.name) == ["slow", "fast", "turbo"] else { return false }
        return clips.enumerated().allSatisfy { index, clip in
            clip.firstFrame == index*24 && clip.frameDurations.count == 24
                && clip.frameDurations.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 1 }
        }
    }

    func frameIndices(at elapsed: Double, offset: Double = 0, size: Double = 0,
                      interpolation: Double = 0) -> SIMD4<Float> {
        let blend = interpolation.isFinite ? min(1,max(0,interpolation)) : 0
        func index(_ clip: NotchLightningHamsterClip) -> Float {
            let position = clip.framePosition(at: elapsed, offset: offset)
            let current = floor(position)
            return Float(current+(position-current)*blend)
        }
        return SIMD4(index(clips[0]),index(clips[1]),index(clips[2]),Float(size))
    }

    static func load(from folder: URL) throws -> Self {
        let value = try JSONDecoder().decode(Self.self,
            from: Data(contentsOf: folder.appendingPathComponent("hamster-manifest.json")))
        guard value.isValid else { throw NSError(domain: "EmberCat.LightningHamsters", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid hamster animation manifest"]) }
        return value
    }
}

/// User-supplied GIF frames and the original discharge masks are uploaded once,
/// in premultiplied RGBA, for the shared live, preview and export renderer.
@MainActor
final class NotchLightningMaterial {
    let hamsters: MTLTexture
    let energy: MTLTexture
    let hamsterManifest: NotchLightningHamsterManifest
    let leaks: MTLTexture

    init(device: MTLDevice) throws {
        // Standalone check executables can read the same checked-in resources.
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources/NotchLightning")
        let folder = AppResources.directory("NotchLightning") ?? source
        hamsterManifest = try NotchLightningHamsterManifest.load(from: folder)
        hamsters = try Self.texture(folder.appendingPathComponent("hamster-atlas.png"),
            width: hamsterManifest.cellSize*hamsterManifest.columns,
            height: hamsterManifest.cellSize*hamsterManifest.rows, device: device)
        energy = try Self.texture(folder.appendingPathComponent("tube-atlas.png"),
            width: 1024, height: 1536, device: device)
        leaks = try Self.texture(folder.appendingPathComponent("leak-atlas.png"),
            width: 1024, height: 1536, device: device)
    }

    private static func texture(_ url: URL, width: Int, height: Int, device: MTLDevice) throws -> MTLTexture {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width, image.height == height,
              let context = CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw error("Invalid lightning atlas: \(url.lastPathComponent)") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: image.width, height: image.height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor), let data = context.data else {
            throw error("Could not upload lightning atlas")
        }
        texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
            withBytes: data, bytesPerRow: image.width * 4)
        return texture
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "EmberCat.LightningMaterial", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
    }
}
