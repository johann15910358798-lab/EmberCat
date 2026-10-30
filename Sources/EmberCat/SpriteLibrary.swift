import AppKit

/// Keep the source canvas intact; trim only the menu-bar presentation.
@MainActor
final class SpriteLibrary {
    static let shared = SpriteLibrary()
    static let imageSize = NSSize(width: 36, height: 20)
    private var cache: [String: [NSImage]] = [:]
    private var menuBarCache: [String: [NSImage]] = [:]
    private var menuBarBoundsCache: [String: NSRect] = [:]

    private init() {}

    func frames(for style: PetStyle, mode: SpeedTier) -> [NSImage] {
        let relative = style == .cat
            ? "Cat/\(mode == .idle ? "idle" : "run")"
            : "Makima/Modes/\(mode.rawValue)"
        return load(relative)
    }

    func transitionFrames(from: SpeedTier, to: SpeedTier) -> [NSImage] {
        guard from != to else { return [] }
        let lower = from.rank < to.rank ? from : to
        let upper = from.rank < to.rank ? to : from
        let frames = load("Makima/Transitions/\(lower.rawValue)_\(upper.rawValue)")
        return from.rank < to.rank ? frames : Array(frames.reversed())
    }

    func image(for style: PetStyle, director: MotionDirector) -> NSImage? {
        guard style == .makima, let transition = director.transition else {
            return cycleFrame(style: style, mode: director.mode,
                phase: director.clock.phase(cycleDuration: style.cycleDuration(for: director.mode)))
        }
        guard let from = cycleFrame(style: style, mode: transition.from, phase: transition.sourcePhase),
              let to = cycleFrame(style: style, mode: transition.to,
                phase: director.clock.phase(cycleDuration: style.cycleDuration(for: transition.to))) else { return nil }
        let keys = [from] + transitionFrames(from: transition.from, to: transition.to) + [to]
        let position = min(Double(keys.count - 1), transition.progress * Double(keys.count - 1))
        let index = min(keys.count - 2, Int(position))
        let amount = position - Double(index)
        let eased = amount * amount * (3 - 2 * amount)
        return blend(keys[index], keys[index + 1], amount: eased)
    }

    func menuBarFrames(for style: PetStyle, mode: SpeedTier) -> [NSImage] {
        let key = menuBarKey(for: style, mode: mode)
        if let found = menuBarCache[key] { return found }
        let frames = frames(for: style, mode: mode)
        let bounds = menuBarBounds(for: style, mode: mode)
        let trimmed = frames.map { crop($0, to: bounds) }
        menuBarCache[key] = trimmed
        return trimmed
    }

    func menuBarImage(for style: PetStyle, director: MotionDirector) -> NSImage? {
        guard style == .makima, let transition = director.transition else {
            let frames = menuBarFrames(for: style, mode: director.mode)
            guard !frames.isEmpty else { return nil }
            let index = director.clock.frameIndex(frameCount: frames.count,
                cycleDuration: style.cycleDuration(for: director.mode))
            return frames[index]
        }
        guard let image = image(for: style, director: director) else { return nil }
        let lower = transition.from.rank < transition.to.rank ? transition.from : transition.to
        let upper = transition.from.rank < transition.to.rank ? transition.to : transition.from
        let key = "Makima/Transitions/\(lower.rawValue)_\(upper.rawValue)"
        let bounds: NSRect
        if let found = menuBarBoundsCache[key] {
            bounds = found
        } else {
            // One envelope for the entire transition, including both endpoint cycles.
            // Width never changes between frames or clips a vehicle entering the scene.
            bounds = horizontalBounds(of: transitionFrames(from: lower, to: upper))
                .union(menuBarBounds(for: style, mode: lower))
                .union(menuBarBounds(for: style, mode: upper))
            menuBarBoundsCache[key] = bounds
        }
        return crop(image, to: bounds)
    }

    private func menuBarKey(for style: PetStyle, mode: SpeedTier) -> String {
        "\(style.rawValue)/\(style == .cat ? (mode == .idle ? "idle" : "run") : mode.rawValue)"
    }

    private func menuBarBounds(for style: PetStyle, mode: SpeedTier) -> NSRect {
        let key = menuBarKey(for: style, mode: mode)
        if let found = menuBarBoundsCache[key] { return found }
        let bounds = horizontalBounds(of: frames(for: style, mode: mode))
        menuBarBoundsCache[key] = bounds
        return bounds
    }

    private func horizontalBounds(of frames: [NSImage]) -> NSRect {
        var left = Self.imageSize.width
        var right: CGFloat = 0
        for image in frames {
            for rep in image.representations.compactMap({ $0 as? NSBitmapImageRep }) {
                let pointWidth = image.size.width / CGFloat(rep.pixelsWide)
                for x in 0..<rep.pixelsWide {
                    for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
                        left = min(left, CGFloat(x) * pointWidth)
                        right = max(right, CGFloat(x + 1) * pointWidth)
                        break
                    }
                }
            }
        }
        guard right > left else { return NSRect(origin: .zero, size: Self.imageSize) }
        return NSRect(x: floor(left), y: 0, width: ceil(right) - floor(left), height: Self.imageSize.height)
    }

    private func crop(_ image: NSImage, to bounds: NSRect) -> NSImage {
        let result = NSImage(size: bounds.size)
        for rep in image.representations.compactMap({ $0 as? NSBitmapImageRep }) {
            let scale = CGFloat(rep.pixelsWide) / image.size.width
            let pixels = NSRect(x: bounds.minX * scale, y: 0,
                width: bounds.width * scale, height: bounds.height * scale)
            guard let cgImage = rep.cgImage?.cropping(to: pixels) else { return image }
            let trimmed = NSBitmapImageRep(cgImage: cgImage)
            trimmed.size = bounds.size
            result.addRepresentation(trimmed)
        }
        result.isTemplate = image.isTemplate
        return result
    }

    private func cycleFrame(style: PetStyle, mode: SpeedTier, phase: Double) -> NSImage? {
        let frames = frames(for: style, mode: mode)
        guard !frames.isEmpty else { return nil }
        return frames[AnimationClock.frameIndex(phase: phase, frameCount: frames.count)]
    }

    private func load(_ relative: String) -> [NSImage] {
        if let found = cache[relative] { return found }
        guard let folder = resourceFolder(relative) else { return [] }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("frame-") && $0.hasSuffix(".png") && !$0.contains("@") }
            .sorted().map { String($0.dropLast(4)) }
        let frames = names.compactMap { name -> NSImage? in
            let image = NSImage(size: Self.imageSize)
            for density in [1, 2] {
                let suffix = density == 2 ? "@2x" : ""
                let url = folder.appendingPathComponent("\(name)\(suffix).png")
                guard let data = try? Data(contentsOf: url),
                      let rep = NSBitmapImageRep(data: data),
                      rep.pixelsWide == 36 * density, rep.pixelsHigh == 20 * density else { return nil }
                rep.size = Self.imageSize
                image.addRepresentation(rep)
            }
            image.isTemplate = true
            return image
        }
        cache[relative] = frames
        return frames
    }

    private func resourceFolder(_ relative: String) -> URL? {
        let subpath = "MenuBarPets/\(relative)"
        if let folder = Bundle.main.resourceURL?.appendingPathComponent(subpath),
           FileManager.default.fileExists(atPath: folder.path) { return folder }
        // The standalone app has no SwiftPM resource bundle: check its resources first.
        guard let folder = Bundle.module.resourceURL?.appendingPathComponent(subpath),
              FileManager.default.fileExists(atPath: folder.path) else { return nil }
        return folder
    }

    private func blend(_ from: NSImage, _ to: NSImage, amount: Double) -> NSImage {
        let result = NSImage(size: Self.imageSize)
        for density in [1, 2] {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36 * density,
                pixelsHigh: 20 * density, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(density), y: CGFloat(density))
            let rect = NSRect(origin: .zero, size: Self.imageSize)
            from.draw(in: rect, from: .zero, operation: .copy, fraction: 1 - amount)
            // Add premultiplied masks to avoid an opacity dip halfway through a blend.
            to.draw(in: rect, from: .zero, operation: .plusLighter, fraction: amount)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            rep.size = Self.imageSize
            result.addRepresentation(rep)
        }
        result.isTemplate = true
        return result
    }
}
