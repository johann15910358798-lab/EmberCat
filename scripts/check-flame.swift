import AppKit
import Foundation

@MainActor
private final class FlameCheckDisplay {
    var profile: NotchDisplayProfile?
    init(_ profile: NotchDisplayProfile?) { self.profile = profile }
}

@main
struct FlameCheck {
    @MainActor static func main() {
        do { try run() }
        catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition {
                throw NSError(domain: "EmberCat.FlameCheck", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func bytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
        func pump(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let suite = "EmberCat.FlameCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NotchFlameSettings(defaults: defaults)
        try require(settings.isEnabled, "Enable the new flame by default")
        settings.isEnabled = false
        try require(!NotchFlameSettings(defaults: defaults).isEnabled, "Persist explicit opt-out")
        settings.isEnabled = true

        try require(settings.palette == .standard, "Default palette is available without migrating other preferences")
        let custom = NotchFlamePalette(bands: [
            NotchFlameBand(minimumSpeed: 0, hex: "#4DEB66"),
            NotchFlameBand(minimumSpeed: 42, hex: "#B34DFF"),
            NotchFlameBand(minimumSpeed: 99.5, hex: "#FFFFFF"),
        ])
        try require(settings.setPalette(custom) && NotchFlameSettings(defaults: defaults).palette == custom,
            "Persist custom thresholds and colors together")
        try require(custom.color(for: 41.999) == custom.bands[0].rgb
            && custom.color(for: 42) == custom.bands[1].rgb
            && custom.color(for: 99.499) == custom.bands[1].rgb
            && custom.color(for: 99.5) == custom.bands[2].rgb
            && custom.color(for: 1_000_000) == custom.bands[2].rgb,
            "Band endpoints are unambiguous and the last range is open-ended")
        for invalid in [
            NotchFlamePalette(bands: []),
            NotchFlamePalette(bands: [.init(minimumSpeed: 2, hex: "#FF0000")]),
            NotchFlamePalette(bands: [.init(minimumSpeed: 0, hex: "#GG0000")]),
            NotchFlamePalette(bands: [.init(minimumSpeed: 0, hex: "FF0000")]),
            NotchFlamePalette(bands: [.init(minimumSpeed: 0, hex: "#FF0000"), .init(minimumSpeed: 0, hex: "#FFFFFF")]),
            NotchFlamePalette(bands: [.init(minimumSpeed: 0, hex: "#FF0000"), .init(minimumSpeed: .nan, hex: "#FFFFFF")]),
            NotchFlamePalette(bands: [.init(minimumSpeed: 0, hex: "#FF0000"), .init(minimumSpeed: .infinity, hex: "#FFFFFF")]),
            NotchFlamePalette(bands: (0..<9).map { .init(minimumSpeed: Double($0), hex: "#FFFFFF") }),
        ] {
            try require(!settings.setPalette(invalid) && settings.palette == custom,
                "Reject malformed palettes atomically, retaining the saved settings")
        }
        defaults.set(Data("invalid JSON".utf8), forKey: "notchFlamePalette")
        try require(NotchFlameSettings(defaults: defaults).palette == .standard,
            "Recover a malformed saved palette without breaking startup")
        settings.setPalette(.standard)

        let customAppearance = NotchFlameAppearance(brightness: 1.35, core: 0.82,
            transparency: 0.65, length: 1.23, turbulence: 1.7, flow: 1.6)
        try require(settings.appearance == .standard && settings.setAppearance(customAppearance)
            && NotchFlameSettings(defaults: defaults).appearance == customAppearance,
            "All six material sliders persist without changing the color bands")
        for parameter in NotchFlameParameter.allCases {
            for value in [parameter.range.lowerBound - 0.01, parameter.range.upperBound + 0.01,
                          Double.nan, Double.infinity] {
                var invalid = customAppearance
                invalid[keyPath: parameter.keyPath] = value
                try require(!settings.setConfiguration(palette: custom, appearance: invalid)
                    && settings.palette == .standard && settings.appearance == customAppearance
                    && NotchFlameSettings(defaults: defaults).appearance == customAppearance,
                    "Reject invalid slider \(parameter.rawValue) without partially saving either page")
            }
        }
        defaults.set(Data("invalid JSON".utf8), forKey: "notchFlameAppearance")
        try require(NotchFlameSettings(defaults: defaults).appearance == .standard,
            "Corrupt material settings recover to defaults")
        settings.setAppearance(.standard)

        let displayChecks = try NotchDisplayChecks.run()

        let physical = NotchDisplayProfile(screenName: "Retina fixture",
            screenFrame: CGRect(x: 1440, y: 120, width: 1728, height: 1117),
            notchFrame: CGRect(x: 2220, y: 1205, width: 168, height: 32), scale: 2)
        try require(physical.geometry.notchWidth == 168 && physical.geometry.notchHeight == 32,
            "Use the physical notch dimensions")
        try require(physical.panelFrame.midX == physical.anchorFrame.midX
            && physical.panelFrame.maxY == physical.screenFrame.maxY, "Respect secondary-screen origin")
        let external = NotchDisplayProfile(screenName: "External fixture",
            screenFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1080),
            notchFrame: nil, scale: 1)
        try require(external.anchorFrame.midX == external.screenFrame.midX
            && external.panelFrame.maxY == external.screenFrame.maxY, "Center the external-display island")
        try require(external.anchorFrame.size == CGSize(width: 180, height: 32),
            "Keep the approved virtual island size")

        for value: Double in [0, -20, .nan, .infinity, -.infinity] {
            try require(NotchFlameAnimation.heat(for: value) == 0, "Reject invalid or idle rates")
        }
        var lastHeat: Double = 0
        for rate in stride(from: 0.0, through: 240.0, by: 0.1) {
            let heat = NotchFlameAnimation.heat(for: rate)
            try require(heat >= lastHeat && heat - lastHeat < 0.01, "Continuous monotonic heat")
            lastHeat = heat
        }
        try require(NotchFlameAnimation.heat(for: 180) == 1, "180 tok/s reaches full flame intensity")
        var animation = NotchFlameAnimation()
        animation.setSpeed(180)
        let initialPhase = animation.phase
        for _ in 0..<300 { animation.advance(by: 1.0 / 60) }
        try require(animation.heat == 1 && animation.visibility == 1, "Settle at measured heat")
        try require(animation.phase > initialPhase + 7, "High speed increases the flow rate")
        let flowingPhase = animation.phase
        var slow = NotchFlameAnimation()
        slow.setSpeed(20)
        for _ in 0..<300 { slow.advance(by: 1.0 / 60) }
        let slowTravel = slow.phase - initialPhase
        let fastTravel = flowingPhase - initialPhase
        try require(fastTravel > slowTravel * 3, "High and low tok/s produce distinct flow speeds")
        var fasterFlow = NotchFlameAnimation()
        fasterFlow.setSpeed(180)
        for _ in 0..<300 { fasterFlow.advance(by: 1.0 / 60, flow: 2) }
        try require(abs((fasterFlow.phase - initialPhase) - fastTravel * 2) < 0.00001
            && fasterFlow.heat == animation.heat,
            "Flow slider changes phase speed without changing measured heat")
        let priorPhase = fasterFlow.phase
        fasterFlow.advance(by: 1.0 / 60, flow: 0.25)
        try require(fasterFlow.phase > priorPhase && fasterFlow.phase - priorPhase < 0.01,
            "Changing flow preserves phase rather than jumping to a new animation")
        animation.setSpeed(20)
        try require(animation.phase == flowingPhase, "Rate changes preserve phase")
        animation.advance(by: 1.0 / 60)
        try require(animation.heat < 1 && animation.heat > 0.9, "Cool without a hard color step")
        animation.setSpeed(0)
        for _ in 0..<300 { animation.advance(by: 1.0 / 60) }
        try require(animation.isHidden && !animation.needsFrames(reduceMotion: false),
            "Fully extinguish and stop drawing at zero")
        for effect in [NotchEffectStyle.matrix, .lightning] {
            var idle = NotchFlameAnimation()
            let start = idle.phase
            idle.setSpeed(0, effect: effect)
            try require(idle.needsFrames(reduceMotion: false), "Idle \(effect.rawValue) starts from a hidden state")
            for _ in 0..<300 { idle.advance(by: 1.0 / 60) }
            let idleTravel = idle.phase-start
            try require(idle.heat == 0 && idle.targetHeat == 0 && idle.visibility == 1
                && idle.needsFrames(reduceMotion: false) && idleTravel > slowTravel*0.4 && idleTravel < slowTravel*0.7,
                "Idle \(effect.rawValue) keeps a visible slow clock instead of compounding the slowdown")
            idle.setSpeed(20, effect: effect)
            for _ in 0..<300 { idle.advance(by: 1.0 / 60) }
            try require(idle.motionScale == 1 && idle.heat == NotchFlameAnimation.heat(for: 20),
                "Fresh output smoothly restores the regular \(effect.rawValue) clock")
            idle.setSpeed(0, active: false, effect: effect)
            for _ in 0..<300 { idle.advance(by: 1.0 / 60) }
            try require(idle.isHidden && !idle.needsFrames(reduceMotion: false),
                "An explicit off still stops idle \(effect.rawValue)")
            idle.setSpeed(0, effect: effect)
            let reducedPhase = idle.phase
            for _ in 0..<300 { idle.advance(by: 1.0 / 60, reduceMotion: true) }
            try require(idle.heat == 0 && idle.visibility == 1 && idle.phase == reducedPhase
                && !idle.needsFrames(reduceMotion: true),
                "Reduced motion retains a static idle \(effect.rawValue) without a frame loop")
            idle.reset()
            try require(idle.isHidden && !idle.needsFrames(reduceMotion: false),
                "Stopping \(effect.rawValue) clears the idle visibility target")
        }
        animation.setSpeed(180)
        let stillPhase = animation.phase
        for _ in 0..<300 { animation.advance(by: 1.0 / 60, reduceMotion: true) }
        try require(animation.phase == stillPhase && !animation.needsFrames(reduceMotion: true),
            "Reduced motion settles without an animation loop")
        animation.reset()
        try require(animation.isHidden, "Immediate off resets all visible state")
        animation.setSpeed(40, color: custom.color(for: 40))
        for _ in 0..<180 { animation.advance(by: 1.0 / 60) }
        let originalColor = animation.color
        animation.setSpeed(42, color: custom.color(for: 42))
        animation.advance(by: 1.0 / 60, reduceMotion: true)
        try require(animation.color != originalColor && animation.color != custom.color(for: 42),
            "Crossing a color boundary blends smoothly rather than flashing")
        for _ in 0..<240 { animation.advance(by: 1.0 / 60, reduceMotion: true) }
        try require(animation.color == custom.color(for: 42) && !animation.needsFrames(reduceMotion: true),
            "Reduced motion redraws a color change, then stops")

        let renderer = try NotchFlameRenderer()
        let geometry = NotchFlameGeometry(notchWidth: 180, notchHeight: 32)
        let bottomInterior = Int((geometry.notch.minX + 12) * 2)..<Int((geometry.notch.maxX - 12) * 2)
        func channels(_ rate: Double, palette: NotchFlamePalette = .standard) throws -> [Double] {
            let data = bytes(try renderer.image(geometry: geometry, time: 8.73, speed: rate, palette: palette))
            var rgb = [0.0, 0.0, 0.0]
            for offset in stride(from: 0, to: data.count, by: 4) {
                rgb[0] += Double(data[offset + 2])
                rgb[1] += Double(data[offset + 1])
                rgb[2] += Double(data[offset])
            }
            return rgb
        }
        let gold = try channels(20), red = try channels(90), blue = try channels(180)
        try require(gold[1] > gold[0] * 0.5 && gold[0] > gold[2] * 2,
            "Low speed is gold with a bright core: \(gold)")
        try require(red[0] > red[1] * 2 && red[1] / red[0] < gold[1] / gold[0] * 0.7,
            "Medium speed becomes red after yellow")
        try require(blue[2] > blue[0] * 1.4, "High speed is blue-white")
        let green = try channels(20, palette: custom), purple = try channels(90, palette: custom)
        try require(green[1] > green[0] * 1.5 && green[1] > green[2] * 1.5,
            "Custom green replaces the default yellow in GPU output")
        try require(purple[2] > purple[1] * 1.5 && purple[0] > purple[1] * 1.2,
            "Custom purple replaces the default red in GPU output")
        var contrastChecks = [[String: Any]]()
        for rate: Double in [1,20,90,180] {
            for time: Double in [8.73,9.13,10.1] {
                let image = try renderer.image(geometry: geometry, time: time, speed: rate, scale: 2)
                let data = bytes(image)
                var whiteDelta = 0.0, darkLuminance = 0.0, count = 0
                // Composite premultiplied pixels over white / black in the six-point band below the rim.
                for y in 64..<76 {
                    for x in bottomInterior {
                        let offset = (y*image.width+x)*4
                        let alpha = Double(data[offset+3])/255
                        let luminance = (Double(data[offset+2]) * 0.2126 + Double(data[offset+1]) * 0.7152
                            + Double(data[offset]) * 0.0722)/255
                        whiteDelta += alpha-luminance
                        darkLuminance += luminance
                        count += 1
                    }
                }
                whiteDelta /= Double(count)
                darkLuminance /= Double(count)
                try require(whiteDelta > 0.18,
                    "White-background contrast at \(rate) tok/s, phase \(time): \(whiteDelta)")
                try require(darkLuminance > 0.12,
                    "Dark-background luminance at \(rate) tok/s, phase \(time): \(darkLuminance)")
                contrastChecks.append(["simulatedRate": rate, "phase": time,
                    "meanWhiteLuminanceDifference": whiteDelta, "meanBlackLuminance": darkLuminance])
            }
        }
        var customContrast = [[String:Any]]()
        for hex in ["#4DEB66", "#B34DFF", "#FFFFFF", "#000000"] {
            let palette = NotchFlamePalette(bands: [.init(minimumSpeed:0,hex:hex)])
            let image = try renderer.image(geometry:geometry,time:8.73,speed:180,palette:palette)
            let data = bytes(image)
            var whiteDelta = 0.0, blackLuminance = 0.0, count = 0.0
            for y in 64..<76 {
                for x in bottomInterior {
                    let offset = (y*image.width+x)*4
                    let alpha = Double(data[offset+3])/255
                    let luminance = (Double(data[offset+2]) * 0.2126 + Double(data[offset+1]) * 0.7152
                        + Double(data[offset]) * 0.0722) / 255
                    whiteDelta += alpha-luminance
                    blackLuminance += luminance
                    count += 1
                }
            }
            whiteDelta /= count
            blackLuminance /= count
            try require(whiteDelta > 0.09 && blackLuminance > 0.075,
                "Extreme custom color \(hex) stays legible on black and white: \(whiteDelta), \(blackLuminance)")
            customContrast.append(["hex":hex,"meanWhiteLuminanceDifference":whiteDelta,
                "meanBlackLuminance":blackLuminance])
        }
        var silhouetteChecks = [[String: Any]]()
        for time: Double in [8.73,9.13,10.1,11.2] {
            let image = try renderer.image(geometry: geometry, time: time, speed: 180)
            let data = bytes(image)
            var thirds = [0, 0, 0]
            var deepest = 0
            for x in bottomInterior {
                try require(data[(65 * image.width + x) * 4 + 3] >= 240,
                    "Continuous opaque bottom outline at every phase")
            }
            for y in 100..<image.height {
                let start = Int(geometry.notch.minX * 2), end = Int(geometry.notch.maxX * 2)
                for x in start..<end where data[(y * image.width + x) * 4 + 3] > 180 {
                    thirds[min(2,(x - start) / ((end - start) / 3))] += 1
                    deepest = max(deepest, y)
                }
            }
            try require(thirds.allSatisfy { $0 > 60 } && deepest >= 130,
                "Distinct downward tongues extend at least 33 points across left, middle and right")
            silhouetteChecks.append(["phase":time,"opaquePixelsByThird":thirds,
                "visibleDepthPoints":Double(deepest) / 2 - 32])
        }
        var materialChecks = [[String: Any]]()
        for parameter in NotchFlameParameter.allCases where parameter != .flow {
            var low = NotchFlameAppearance.standard, high = NotchFlameAppearance.standard
            low[keyPath: parameter.keyPath] = parameter.range.lowerBound
            high[keyPath: parameter.keyPath] = parameter.range.upperBound
            let a = bytes(try renderer.image(geometry: geometry, time: 8.73, speed: 180, appearance: low))
            let b = bytes(try renderer.image(geometry: geometry, time: 8.73, speed: 180, appearance: high))
            let differences = zip(a,b).filter { $0 != $1 }.count
            try require(differences > 1000, "Slider \(parameter.rawValue) changes actual GPU output")
            func energy(_ data: [UInt8]) -> Int {
                stride(from: 0, to: data.count, by: 4).reduce(0) {
                    $0 + Int(data[$1]) + Int(data[$1 + 1]) + Int(data[$1 + 2])
                }
            }
            func alpha(_ data: [UInt8]) -> Int {
                stride(from: 3, to: data.count, by: 4).reduce(0) { $0 + Int(data[$1]) }
            }
            if parameter == .brightness || parameter == .core {
                try require(energy(b) > energy(a), "Increasing \(parameter.rawValue) increases emitted light")
            }
            if parameter == .transparency {
                try require(alpha(b) < alpha(a), "Increasing transparency reveals more of the background")
            }
            if parameter == .length {
                try require(alpha(b) > alpha(a), "Longer tails cover more of the canvas")
            }
            materialChecks.append(["parameter": parameter.rawValue, "changedBytes": differences])
        }
        var smallest = NotchFlameAppearance.standard, largest = NotchFlameAppearance.standard
        for parameter in NotchFlameParameter.allCases {
            smallest[keyPath: parameter.keyPath] = parameter.range.lowerBound
            largest[keyPath: parameter.keyPath] = parameter.range.upperBound
        }
        for (width, height, scale): (CGFloat, CGFloat, CGFloat) in [
            (168, 32, 2), (204, 38, 2), (180, 32, 1),
            (128, 25.6, 2), (225, 40, 2), (230, 40, 2), (255, 40, 2)
        ] {
            let geometry = NotchFlameGeometry(notchWidth: width, notchHeight: height)
            for appearance in [NotchFlameAppearance.standard, smallest, largest] {
            let image = try renderer.image(geometry: geometry, time: 8.73, speed: 180, scale: scale,
                appearance: appearance)
            let data = bytes(image)
            try require(data[(Int(10 * scale) * image.width + image.width / 2) * 4 + 3] == 0,
                "Do not paint inside a physical notch")
            for x in 0..<image.width {
                try require(data[((image.height - 1) * image.width + x) * 4 + 3] == 0,
                    "No lower clipping line")
            }
            for y in 0..<image.height {
                try require(data[y * image.width * 4 + 3] == 0
                    && data[(y * image.width + image.width - 1) * 4 + 3] == 0, "No side clipping lines")
                if CGFloat(y) / scale >= geometry.notchHeight + 5 {
                    for x in 0..<image.width {
                        let pointX = (CGFloat(x) + 0.5) / scale
                        if pointX < geometry.notch.minX || pointX >= geometry.notch.maxX {
                            try require(data[(y * image.width + x) * 4 + 3] == 0,
                                "Flames and embers cannot extend sideways beyond the notch")
                        }
                    }
                }
            }
            let rimY = Int(10 * scale)
            for pointX in [geometry.notch.minX - 1, geometry.notch.maxX + 0.5] {
                let x = Int(pointX * scale)
                try require(data[(rimY * image.width + x) * 4 + 3] >= 220,
                    "Preserve the bright outer rim on both sides")
            }
            for offset in stride(from: 0, to: data.count, by: 4) {
                try require(data[offset] <= data[offset + 3] && data[offset + 1] <= data[offset + 3]
                    && data[offset + 2] <= data[offset + 3], "Premultiplied alpha for light desktops")
            }
            }
        }
        let idle = bytes(try renderer.image(geometry: geometry, time: 8.73, speed: 0))
        try require(idle.allSatisfy { $0 == 0 }, "No visible fire at zero tok/s")
        let idleAnchor = bytes(try renderer.image(geometry: geometry, time: 8.73, speed: 0, drawsAnchor: true))
        try require(idleAnchor.allSatisfy { $0 == 0 }, "Zero speed also removes the preview island")
        for effect in [NotchEffectStyle.matrix, .lightning] {
            let idleGeometry = NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: effect)
            let idlePixels = bytes(try renderer.image(geometry: idleGeometry, time: 8.73, speed: 0))
            let offPixels = bytes(try renderer.image(geometry: idleGeometry, time: 8.73, speed: 0, active: false))
            try require(idlePixels.contains { $0 > 0 } && offPixels.allSatisfy { $0 == 0 },
                "The GPU keeps zero-rate \(effect.rawValue) visible while respecting an explicit off")
        }
        let off = bytes(try renderer.image(geometry: geometry, time: 8.73, speed: 180,
            active: false, drawsAnchor: true))
        try require(off.allSatisfy { $0 == 0 }, "Disabling also removes the virtual island")
        let anchorImage = try renderer.image(geometry: geometry, time: 8.73, speed: 180, drawsAnchor: true)
        try require(bytes(anchorImage)[(20 * anchorImage.width + anchorImage.width / 2) * 4 + 3] == 255,
            "External display has a solid black anchor")
        let first = bytes(try renderer.image(geometry: geometry, time: 8.73, speed: 180))
        let second = bytes(try renderer.image(geometry: geometry, time: 9.13, speed: 180))
        var flowingRimChanges = 0
        var rimAlphaChanges = 0
        let imageWidth = Int(geometry.size.width * 2)
        for y in 4..<Int((geometry.notchHeight - geometry.cornerRadius - 2) * 2) {
            for x in Int((geometry.notch.minX - 3.5) * 2)..<Int(geometry.notch.minX * 2) {
                let offset = (y * imageWidth + x) * 4
                if first[offset..<(offset + 4)] != second[offset..<(offset + 4)] {
                    flowingRimChanges += 1
                }
                if first[offset + 3] != second[offset + 3] { rimAlphaChanges += 1 }
            }
        }
        try require(flowingRimChanges > 100,
            "The light on the outer rim must flow, even where the flame body is masked")
        try require(rimAlphaChanges == 0, "The outer rim keeps its shape and width while its light moves")
        let differences = zip(first, second).filter { $0 != $1 }.count
        try require(differences > 1000, "The native density field evolves")
        let stillA = bytes(try renderer.image(geometry: geometry, time: 1, speed: 180, reduceMotion: true))
        let stillB = bytes(try renderer.image(geometry: geometry, time: 8, speed: 180, reduceMotion: true))
        try require(stillA == stillB, "Reduced-motion GPU output is stable")

        let selectedDisplay = FlameCheckDisplay(NotchDisplayProfile.current())
        let controller = NotchFlameController(settings: settings, currentDisplay: { selectedDisplay.profile })
        defer { controller.shutdown() }
        controller.update(speed: 180)
        pump(2)
        guard let panel = NSApp.windows.first(where: { $0.title == "EmberCat · 灵动岛火焰" }),
              let view = panel.contentView as? NotchFlameMetalView else {
            try require(false, "Create a native overlay")
            return
        }
        try require(panel.isVisible && panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain,
            "Visible overlay must pass clicks and never take focus")
        try require(panel.frame == NotchDisplayProfile.current()?.panelFrame, "Align with the current display")
        try require(panel.collectionBehavior.contains(.canJoinAllSpaces)
            && panel.collectionBehavior.contains(.fullScreenAuxiliary), "Follow Spaces and fullscreen")
        try require(view.drawableSize == CGSize(width: ceil(view.bounds.width * panel.backingScaleFactor),
            height: ceil(view.bounds.height * panel.backingScaleFactor)), "Use native backing pixels")
        settings.setPalette(custom)
        try require(view.palette == custom && panel.isVisible,
            "Saving a palette updates the existing live surface immediately")
        settings.setPalette(.standard)
        settings.setAppearance(customAppearance)
        try require(view.flameAppearance == customAppearance && panel.isVisible,
            "Saving material sliders updates the existing live surface")
        settings.setAppearance(.standard)
        let originalDisplay = selectedDisplay.profile
        if let originalDisplay {
            let screen = originalDisplay.screenFrame
            let replacement = NotchDisplayProfile(screenName: "Synthetic notch on current screen",
                screenFrame: screen, notchFrame: CGRect(x: screen.midX - 102,
                    y: screen.maxY - 40, width: 204, height: 40),
                scale: originalDisplay.scale, maximumFramesPerSecond: 120)
            selectedDisplay.profile = replacement
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            pump(0.2)
            try require(panel.isVisible && panel.frame == replacement.panelFrame
                && panel.contentView === view, "Resize and reposition the existing surface after a display change")
            try require(!view.drawsAnchor && view.geometry.notchWidth == 204
                && view.geometry.notchHeight == 40, "Use the replacement notch without drawing another island")
            try require(view.preferredFramesPerSecond == 120, "Request ProMotion cadence on capable displays")
            selectedDisplay.profile = nil
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try require(!panel.isVisible && !view.isRendering, "Suspend while no valid display is available")
            selectedDisplay.profile = originalDisplay
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            pump(0.2)
            try require(panel.isVisible && panel.frame == originalDisplay.panelFrame,
                "Recover the same surface when a valid display returns")
            try require(view.drawsAnchor == (originalDisplay.notchFrame == nil)
                && view.preferredFramesPerSecond == originalDisplay.preferredFramesPerSecond,
                "Restore the correct anchor and cadence on the fallback display")
        }
        settings.isEnabled = false
        try require(!panel.isVisible && !view.isRendering, "Switch off hides and pauses immediately")
        settings.isEnabled = true
        pump(0.2)
        try require(panel.isVisible, "Switch on resumes the current measured rate")
        controller.update(speed: 0)
        pump(4.3)
        try require(!panel.isVisible && !view.isRendering, "Zero rate fades out then releases the frame loop")
        controller.update(speed: 90)
        pump(0.2)
        try require(panel.isVisible, "New output wakes the same surface")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        controller.update(speed: 180)
        try require(!panel.isVisible && !view.isRendering, "Screen sleep suspends rendering")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        pump(0.1)
        try require(!panel.isVisible, "Do not replay the pre-sleep rate")
        controller.update(speed: 30)
        pump(0.2)
        try require(panel.isVisible, "Fresh output resumes after wake")
        let profile = NotchDisplayProfile.current()
        let report: [String: Any] = [
            "passed": true,
            "renderer": "native Metal / downward fire with continuous rim",
            "input": "isolated synthetic tok/s; no monitor or token records",
            "checks": ["persisted enable", "atomic palette validation and persistence", "custom threshold boundaries",
                "physical and external display geometry", "continuous heat phase and color",
                "idle stop", "reduced motion", "GPU yellow red blue-white palette", "premultiplied alpha",
                "continuous outline", "downward tongues", "custom and extreme color contrast",
                "six persisted material sliders", "slider GPU response", "parameter extremes", "continuous flow adjustment",
                "transparent bounds", "flames constrained to notch width", "outer flowing rim preserved",
                "flowing light on a fixed outline independent of flame body",
                "single noninteractive window", "toggle", "sleep and wake"],
            "device": profile?.summary ?? "unknown", "changedBytes": differences,
            "redRGB": red, "goldRGB": gold, "blueRGB": blue, "customGreenRGB": green, "customPurpleRGB": purple,
            "maximumFlameDepth": NotchFlameGeometry.maximumFlameDepth,
            "flowingRimChangedPixels": flowingRimChanges,
            "rimAlphaChangedPixels": rimAlphaChanges,
            "silhouette":silhouetteChecks,
            "displayCompatibility": displayChecks,
            "hardwareValidation": profile?.notchFrame == nil ? "flat external display only; no physical notch tested" : "current notch display",
            "actualDisplay": ["screen": profile.map { NSStringFromRect($0.screenFrame) } ?? "none",
                "scale": profile?.scale ?? 0, "requestedFPS": profile?.preferredFramesPerSecond ?? 0,
                "drawableWidth": view.drawableSize.width, "drawableHeight": view.drawableSize.height],
            "desktopContrast": contrastChecks,
            "materialSliders": materialChecks,
            "customColorContrast":customContrast,
            "flowTravelOverFiveSeconds": ["20tok": slowTravel, "180tok": fastTravel],
            "windowID": panel.windowNumber, "panelFrame": NSStringFromRect(panel.frame)
        ]
        if let output = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) {
            let url = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        }
        if CommandLine.arguments.contains("--hold-preview") {
            panel.title = "EmberCat · 火焰验收（模拟 180 tok/s）"
            controller.update(speed: 180)
            print("PREVIEW: isolated 180 tok/s; window \(panel.windowNumber); 45 seconds")
            fflush(stdout)
            pump(45)
        }
        controller.shutdown()
        try require(!panel.isVisible && !view.isRendering, "Shutdown removes the surface and stops rendering")
        print("PASS: six material sliders, customizable palette and ranges, continuous rim, downward flames, contrast, alpha, motion and lifecycle")
    }
}
