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

    func frames(for mode: SpeedTier) -> [NSImage] {
        load("Makima/Modes/\(mode.rawValue)")
    }

    func catFrames(for gait: CatGait) -> [NSImage] {
        load("Cat/\(gait.rawValue)")
    }

    func catCurlFrames() -> [NSImage] { load("Cat/curl") }

    func catMenuBarFrames(for gait: CatGait) -> [NSImage] {
        let key = "Cat/\(gait.rawValue)"
        if let found = menuBarCache[key] { return found }
        let trimmed = catFrames(for: gait).map { crop($0, to: catMenuBarBounds(for: gait)) }
        menuBarCache[key] = trimmed
        return trimmed
    }

    func catMenuBarCurlFrames() -> [NSImage] {
        let key = "Cat/curl"
        if let found = menuBarCache[key] { return found }
        let frames = catCurlFrames()
        guard frames.count > 1 else { return frames }
        let source = catMenuBarBounds(for: .run)
        let target = catMenuBarBounds(for: .roll)
        var bounds = frames.enumerated().map { index, frame in
            let p = Double(index) / Double(frames.count - 1)
            let eased = p * p * (3 - 2 * p)
            let left = floor(source.minX + (target.minX - source.minX) * eased)
            let right = ceil(source.maxX + (target.maxX - source.maxX) * eased)
            return NSRect(x: left, y: 0, width: right - left, height: 20)
                .union(horizontalBounds(of: [frame]))
        }
        // Shrink the occupied width with the actual curl, never oscillating or
        // clipping a paw. Steady loops keep a constant width at both endpoints.
        for index in stride(from: bounds.count - 2, through: 0, by: -1) {
            bounds[index] = bounds[index].union(bounds[index + 1])
        }
        let trimmed = zip(frames, bounds).map { crop($0.0, to: $0.1) }
        menuBarCache[key] = trimmed
        return trimmed
    }

    private func catMenuBarBounds(for gait: CatGait) -> NSRect {
        let key = gait == .roll ? "Cat/roll-bounds" : "Cat/locomotion-bounds"
        if let found = menuBarBoundsCache[key] { return found }
        let gaits: [CatGait] = gait == .roll ? [.roll] : [.idle, .walk, .run]
        let bounds = horizontalBounds(of: gaits.flatMap { catFrames(for: $0) })
        menuBarBoundsCache[key] = bounds
        return bounds
    }

    func transitionFrames(from: SpeedTier, to: SpeedTier) -> [NSImage] {
        guard from != to else { return [] }
        let lower = from.rank < to.rank ? from : to
        let upper = from.rank < to.rank ? to : from
        let frames = load("Makima/Transitions/\(lower.rawValue)_\(upper.rawValue)")
        return from.rank < to.rank ? frames : Array(frames.reversed())
    }

    func image(for style: PetStyle, director: MotionDirector) -> NSImage? {
        if style == .cat { return catImage(director.cat) }
        guard let transition = director.transition else {
            return cycleFrame(mode: director.mode,
                phase: director.clock.phase(cycleDuration: director.mode.cycleDuration))
        }
        guard let from = cycleFrame(mode: transition.from, phase: transition.sourcePhase),
              let to = cycleFrame(mode: transition.to,
                phase: director.clock.phase(cycleDuration: transition.to.cycleDuration)) else { return nil }
        let keys = [from] + transitionFrames(from: transition.from, to: transition.to) + [to]
        let position = min(Double(keys.count - 1), transition.progress * Double(keys.count - 1))
        let index = min(keys.count - 2, Int(position))
        let amount = position - Double(index)
        let eased = amount * amount * (3 - 2 * amount)
        return blend(keys[index], keys[index + 1], amount: eased)
    }

    func menuBarFrames(for mode: SpeedTier) -> [NSImage] {
        let key = "Makima/\(mode.rawValue)"
        if let found = menuBarCache[key] { return found }
        let frames = frames(for: mode)
        let bounds = menuBarBounds(for: mode)
        let trimmed = frames.map { crop($0, to: bounds) }
        menuBarCache[key] = trimmed
        return trimmed
    }

    func menuBarImage(for style: PetStyle, director: MotionDirector) -> NSImage? {
        if style == .cat {
            let motion = director.cat
            if let active = motion.transition {
                if active.kind != .blend {
                    let frames = catMenuBarCurlFrames()
                    return curlFrame(frames, transition: active)
                }
                guard let image = catImage(motion) else { return nil }
                return crop(image, to: catMenuBarBounds(for: .run))
            }
            let frames = catMenuBarFrames(for: motion.gait)
            guard !frames.isEmpty else { return nil }
            return frames[AnimationClock.frameIndex(phase: motion.phase, frameCount: frames.count)]
        }
        guard let transition = director.transition else {
            let frames = menuBarFrames(for: director.mode)
            guard !frames.isEmpty else { return nil }
            let index = director.clock.frameIndex(frameCount: frames.count,
                cycleDuration: director.mode.cycleDuration)
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
                .union(menuBarBounds(for: lower))
                .union(menuBarBounds(for: upper))
            menuBarBoundsCache[key] = bounds
        }
        return crop(image, to: bounds)
    }

    private func menuBarBounds(for mode: SpeedTier) -> NSRect {
        let key = "Makima/\(mode.rawValue)"
        if let found = menuBarBoundsCache[key] { return found }
        let bounds = horizontalBounds(of: frames(for: mode))
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

    private func cycleFrame(mode: SpeedTier, phase: Double) -> NSImage? {
        let frames = frames(for: mode)
        guard !frames.isEmpty else { return nil }
        return frames[AnimationClock.frameIndex(phase: phase, frameCount: frames.count)]
    }

    private func catCycleFrame(_ gait: CatGait, phase: Double) -> NSImage? {
        let frames = catFrames(for: gait)
        guard !frames.isEmpty else { return nil }
        return frames[AnimationClock.frameIndex(phase: phase, frameCount: frames.count)]
    }

    private func catImage(_ motion: CatMotion) -> NSImage? {
        guard let transition = motion.transition else { return catCycleFrame(motion.gait, phase: motion.phase) }
        if transition.kind != .blend { return curlFrame(catCurlFrames(), transition: transition) }
        guard let from = catCycleFrame(transition.from, phase: motion.phase),
              let to = catCycleFrame(transition.to, phase: motion.phase) else { return nil }
        let p = transition.progress
        return blend(from, to, amount: p * p * (3 - 2 * p))
    }

    private func curlFrame(_ frames: [NSImage], transition: CatMotion.Transition) -> NSImage? {
        guard !frames.isEmpty else { return nil }
        let p = transition.kind == .curl ? transition.progress : 1 - transition.progress
        return frames[min(frames.count - 1, Int((p * Double(frames.count - 1)).rounded()))]
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
        AppResources.directory("MenuBarPets/\(relative)")
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
