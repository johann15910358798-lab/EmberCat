import AppKit

@MainActor
private final class LightningDraftDelegate: NSObject, NSApplicationDelegate {
    private var preview: NotchFlamePreviewController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let defaults = UserDefaults(suiteName: "EmberCat.LightningInteractiveDraft")!
            preview = try NotchFlamePreviewController(settings: NotchFlameSettings(defaults: defaults),
                effect: .lightning, isIsolatedDraft: true)
            preview?.showWindow(nil)
        } catch {
            fputs("Could not open lightning draft: \(error.localizedDescription)\n", stderr)
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
private final class LightningNativeCheckDelegate: NSObject, NSApplicationDelegate {
    let action: @MainActor () throws -> Void
    init(action: @escaping @MainActor () throws -> Void) { self.action = action }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Native control actions need AppKit's running application lifecycle,
        // not only a Foundation run loop used for offscreen rendering checks.
        DispatchQueue.main.async {
            do { try self.action(); exit(0) }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
}

@main
struct LightningCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        if CommandLine.arguments.contains("--interactive") {
            NSApp.setActivationPolicy(.regular)
            let delegate = LightningDraftDelegate()
            NSApp.delegate = delegate
            withExtendedLifetime(delegate) { NSApp.run() }
            return
        }
        if CommandLine.arguments.contains("--native") && !CommandLine.arguments.contains("--export") {
            NSApp.setActivationPolicy(.regular)
            let delegate = LightningNativeCheckDelegate { try run() }
            NSApp.delegate = delegate
            withExtendedLifetime(delegate) { NSApp.run() }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        do {
            if let index = CommandLine.arguments.firstIndex(of: "--export"),
               CommandLine.arguments.count > index+1 {
                try exportLightningPreview(to: URL(fileURLWithPath: CommandLine.arguments[index+1], isDirectory: true))
            } else {
                try run()
            }
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else {
                throw NSError(domain: "EmberCat.LightningCheck", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func bytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
        func pump(_ seconds: TimeInterval = 0.3) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        let renderer = try NotchFlameRenderer(matrixSeed: MatrixCodeFlow.previewSeed,
            lightningSeed: NotchLightningDischarges.previewSeed)
        let tuningReport = try checkLightningTuning(renderer: renderer)
        let randomReport = try checkLightningDischarges(renderer: renderer)
        let hamsterReport = try checkLightningHamsters(renderer: renderer)
        let geometry = NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: .lightning)
        let rates = [20.0, 90, 180]
        var observations = [[String: Any]]()
        var areas = [Double](), depths = [Double](), widths = [Double](), thicknesses = [Double]()
        for rate in rates {
            var area = 0.0, depth = 0.0, width = 0.0, thickness = 0.0
            var red = 0.0, green = 0.0, blue = 0.0
            var hueRed = 0.0, hueGreen = 0.0, hueBlue = 0.0
            var redAccents = 0, visiblePixels = 0
            for frame in 0..<12 {
                let time = 8.73+Double(frame)*0.17
                let heat = NotchFlameAnimation.heat(for: rate)
                let diameter = NotchLightningMotion.diameter(heat: heat)
                let length = geometry.notchWidth*(0.88+0.30*heat)
                let pose = NotchLightningMotion.pose(elapsed: time, phase: time, heat: heat)
                let image = try renderer.image(geometry: geometry, time: time, speed: rate)
                let pixels = bytes(image)
                var minX = image.width, maxX = 0, minY = image.height, maxY = 0, count = 0
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let i = (y*image.width+x)*4
                        let b = Int(pixels[i]), g = Int(pixels[i+1]), r = Int(pixels[i+2]), a = Int(pixels[i+3])
                        try require(max(r,g,b) <= a+1, "Lightning uses premultiplied transparent pixels")
                        if x < 2 || x >= image.width-2 || y >= image.height-4 {
                            try require(a == 0, "The corona has transparent canvas margins")
                        }
                        if y < Int(geometry.notchHeight*2)-2,
                           Double(x)/2 > geometry.notch.minX+geometry.cornerRadius,
                           Double(x)/2 < geometry.notch.maxX-geometry.cornerRadius {
                            try require(a == 0, "Physical notch area stays transparent")
                        }
                        let dx = Double(x)/2-geometry.notch.midX-pose.offset.x
                        let dy = Double(y)/2 - (geometry.notchHeight + geometry.lightningConfiguration.distance + diameter/2 + pose.offset.y)
                        let localX = dx*cos(pose.angle)+dy*sin(pose.angle)
                        let localY = -dx*sin(pose.angle)+dy*cos(pose.angle)
                        if abs(localX) < length/2+0.5, abs(localY) < diameter/2+0.5, a > 64 {
                            minX = min(minX,x); maxX = max(maxX,x)
                            minY = min(minY,y); maxY = max(maxY,y); count += 1
                        }
                        // Measure the energy window, not the warm-colored pets
                        // and yellow end caps surrounding it.
                        if abs(localX) < length*0.33, abs(localY) < diameter*0.23, a > 64 {
                            visiblePixels += 1
                            if r > b+5 && r > g+10 { redAccents += 1 }
                            red += Double(r); green += Double(g); blue += Double(b)
                            if max(r,g,b)-min(r,g,b) > a/6 {
                                hueRed += Double(r); hueGreen += Double(g); hueBlue += Double(b)
                            }
                        }
                    }
                }
                area += Double(count)/4
                depth += max(0,Double(maxY)/2-Double(geometry.notchHeight))
                width += Double(maxX-minX)/2
                thickness += Double(maxY-minY)/2
                try require(maxX-minX > (maxY-minY)*2, "Every discharge is horizontal")
            }
            area /= 12; depth /= 12; width /= 12; thickness /= 12
            areas.append(area); depths.append(depth); widths.append(width); thicknesses.append(thickness)
            observations.append(["simulatedTokPerSecond": rate, "meanAreaPoints": area,
                "meanDepthPoints": depth, "meanWidthPoints": width, "meanThicknessPoints": thickness,
                "redToBlue": red/blue, "greenToBlue": green/blue,
                "reddishAccentFraction": Double(redAccents)/Double(max(1,visiblePixels)),
                "sheathRedToBlue": hueRed/max(1,hueBlue), "sheathGreenToBlue": hueGreen/max(1,hueBlue)])
            if rate == 20 {
                try require(red/blue > 0.72 && green/blue > 0.83, "Low output is cool white")
            } else if rate == 90 {
                try require(hueBlue > 0 && hueRed/hueBlue < 0.60 && hueGreen/hueBlue < 0.80,
                    "Medium output has a distinctly blue sheath around its white-hot core")
            } else {
                try require(hueBlue > 0 && hueRed/hueBlue > 0.50 && hueGreen/hueBlue < 0.65,
                    "Strong output has a distinctly purple sheath around its white-hot core")
                try require(Double(redAccents)/Double(max(1,visiblePixels)) > 0.003
                    && Double(redAccents)/Double(max(1,visiblePixels)) < 0.30,
                    "The strongest purple stage has restrained red accents, not a solid red body")
            }
            if rate < 180 { try require(redAccents == 0, "White and blue stages do not acquire red accents") }
        }
        try require(areas[1] > areas[0]*1.4 && areas[2] > areas[1]*1.25,
            "Real rendered discharge area grows across all three stages")
        try require(widths[1] > widths[0]+8 && widths[2] > widths[1]+8,
            "Higher output extends the horizontal column")
        try require(thicknesses[1] > thicknesses[0]*1.25 && thicknesses[2] > thicknesses[1]*1.20,
            "Higher output thickens and branches the horizontal column")
        print("PASS: GPU white / blue / purple progression, increasing area, length, width and transparent margins")

        let baseline = bytes(try renderer.image(geometry: geometry, time: 12.4, speed: 90))
        let changed = bytes(try renderer.image(geometry: geometry, time: 12.65, speed: 90))
        try require(zip(baseline,changed).filter { $0 != $1 }.count > 500, "The electricity moves between frames")
        let fixedConfiguration = NotchLightningConfiguration(levitation: 0, jitter: 0)
        let fixedGeometry = NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: .lightning,
            lightningConfiguration: fixedConfiguration)
        let samples = (0..<2_400).map { Double($0)/120 }
        let burstTime = samples.first { time in
            let events = NotchLightningDischarges.events(phase: time)
            return events[0].envelope > 0.70 && events.dropFirst(2).contains { $0.envelope > 0.40 }
        }!
        let quietTime = samples.first { time in
            NotchLightningDischarges.events(phase: time).allSatisfy {
                $0.power == 0 || $0.age < -0.055 || $0.age > $0.duration+0.02
            }
        }!
        let burstImage = try renderer.image(geometry: fixedGeometry, time: burstTime, speed: 180)
        let quietImage = try renderer.image(geometry: fixedGeometry, time: quietTime, speed: 180)
        let burst = bytes(burstImage), quiet = bytes(quietImage)
        var noArcs = fixedConfiguration
        noArcs.arcs = 0
        let shellA = bytes(try renderer.image(geometry: fixedGeometry, time: burstTime,
            speed: 180, lightningConfiguration: noArcs))
        let shellB = bytes(try renderer.image(geometry: fixedGeometry, time: quietTime,
            speed: 180, lightningConfiguration: noArcs))
        var movingInterior = 0, stableShell = 0, changedShell = 0
        var burstLeakPixels = 0, quietLeakPixels = 0
        var gapArcPixels = 0, upperContacts = 0, animatedGapPixels = 0
        let centerX = Double(fixedGeometry.notch.midX)
        let diameter = NotchLightningMotion.diameter(heat: 1)
        let centerY = Double(geometry.notchHeight)+fixedConfiguration.distance+diameter/2
        for y in 0..<burstImage.height {
            for x in 0..<burstImage.width {
                let i = (y*burstImage.width+x)*4
                let nx = (Double(x)/2-centerX)/(Double(geometry.notchWidth)*1.18)
                let ny = (Double(y)/2-centerY)/diameter
                let delta = (0..<4).map { abs(Int(burst[i+$0])-Int(quiet[i+$0])) }.max()!
                let shellDelta = (0..<4).map { abs(Int(shellA[i+$0])-Int(shellB[i+$0])) }.max()!
                if abs(nx) < 0.24 && abs(ny) < 0.25 && shellDelta > 3 { movingInterior += 1 }
                if abs(nx) < 0.15 && (0.47...0.54).contains(ny) && shellA[i+3] > 20 {
                    stableShell += 1
                    if shellDelta > 1 { changedShell += 1 }
                }
                if ny > 0.80 && abs(nx) < 0.48 {
                    if burst[i+3] > 12 { burstLeakPixels += 1 }
                    if quiet[i+3] > 12 { quietLeakPixels += 1 }
                }
                let below = Double(y)/2-Double(geometry.notchHeight)
                if (0.5...(fixedConfiguration.distance-0.5)).contains(below), burst[i+3] > 12,
                   abs(nx) < 0.40 {
                    gapArcPixels += 1
                    if below < 2.5 { upperContacts += 1 }
                    if delta > 2 { animatedGapPixels += 1 }
                }
            }
        }
        try require(movingInterior > 500, "Energy flows inside the pipe")
        try require(stableShell > 80 && changedShell < max(3,stableShell/20),
            "Internal motion preserves the solid outer shell")
        try require(burstLeakPixels > 50 && quietLeakPixels < burstLeakPixels/5,
            "Leakage bursts locally and fades while the tube stays present")
        try require(gapArcPixels > 40 && upperContacts > 4 && animatedGapPixels > 12,
            "Animated traction arcs attach to the notch edge across the gap")
        let layerMotion: [String:Any] = ["movingInteriorPixels":movingInterior,
            "shellPixels":stableShell,"changedShellPixels":changedShell,
            "burstLeakPixels":burstLeakPixels,"quietLeakPixels":quietLeakPixels,
            "gapArcPixels":gapArcPixels,"notchContactPixels":upperContacts,"animatedGapPixels":animatedGapPixels,
            "burstPhase":burstTime,"quietPhase":quietTime]
        print("PASS: stable tube shell, independently flowing energy and intermittent local leakage")
        let reduced = bytes(try renderer.image(geometry: geometry, time: 1, speed: 180, reduceMotion: true))
        try require(reduced == bytes(try renderer.image(geometry: geometry, time: 100, speed: 180, reduceMotion: true)),
            "Reduced motion freezes every lightning layer")
        for rate in [0.0, -20, Double.nan, Double.infinity] {
            try require(bytes(try renderer.image(geometry: geometry, time: 12.4, speed: rate,
                drawsAnchor: true)).allSatisfy { $0 == 0 }, "Idle and invalid speeds leave no lightning or anchor")
        }
        try require(bytes(try renderer.image(geometry: geometry, time: 12.4, speed: 180,
            active: false, drawsAnchor: true)).allSatisfy { $0 == 0 }, "Disabled lightning is transparent")
        try require(bytes(try renderer.image(geometry: geometry, time: 12.4, speed: 180))
            == bytes(try renderer.image(geometry: geometry, time: 12.4, speed: 1_000_000)),
            "Extreme rates stay within the maximum column strength")
        let customPalette = NotchFlamePalette(bands: [.init(minimumSpeed: 0, hex: "#FF5522")])
        let customAppearance = NotchFlameAppearance(brightness: 1.8, core: 1, transparency: 0,
            length: 1.35, turbulence: 2, flow: 2.5)
        try require(baseline == bytes(try renderer.image(geometry: geometry, time: 12.4, speed: 90,
            palette: customPalette, appearance: customAppearance,
            matrixConfiguration: .init(blackHoleSize: 2.5, gravity: 3, density: 3, verticalOffset: 64))),
            "Flame and Matrix tuning cannot change the lightning material")
        let light = bytes(try renderer.image(geometry: geometry, time: 12.4, speed: 90, matrixColorScheme: .light))
        try require(light != baseline, "Light appearance adds local edge contrast")
        for scale: CGFloat in [1,2,3] {
            for notchWidth: CGFloat in [96,180,240] {
                let shape = NotchFlameGeometry(notchWidth: notchWidth, notchHeight: 40, effect: .lightning)
                let image = try renderer.image(geometry: shape, time: 12.4, speed: 180, scale: scale)
                let pixels = bytes(image)
                try require(pixels.contains { $0 != 0 }, "Every display size produces visible discharge")
                for x in 0..<image.width {
                    try require(pixels[((image.height-1)*image.width+x)*4+3] == 0,
                        "External and Retina display bounds contain the tail")
                }
            }
        }
        print("PASS: motion, reduced motion, off state, extreme inputs, material isolation and display sizes")

        let suite = "EmberCat.LightningCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NotchFlameSettings(defaults: defaults)
        settings.setConfiguration(palette: customPalette, appearance: customAppearance)
        settings.effect = .lightning
        try require(NotchFlameSettings(defaults: defaults).effect == .lightning
            && settings.palette == customPalette && settings.appearance == customAppearance,
            "The new effect persists without changing prior configuration")
        var native = false
        var controlReport: [String:Any] = [:]
        var hoverReport: [String:Any] = [:]
        if CommandLine.arguments.contains("--native") {
            let controller = NotchFlameController(settings: settings)
            defer { controller.shutdown() }
            controller.update(speed: 90)
            pump(0.6)
            guard let panel = NSApp.windows.first(where: { $0.title == "EmberCat · \(NotchEffectStyle.lightning.title)" }),
                  let view = panel.contentView as? NotchFlameMetalView else {
                try require(false, "The native lightning overlay is created")
                return
            }
            try require(panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain,
                "Lightning remains a noninteractive overlay")
            try require(panel.frame == NotchDisplayProfile.current()?.panelFrame(for: .lightning),
                "The horizontal lightning overlay follows the display: actual=\(panel.frame), expected=\(String(describing:NotchDisplayProfile.current()?.panelFrame(for:.lightning)))")
            let count = view.renderedFrameCount
            pump()
            try require(view.renderedFrameCount > count || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "The live lightning view submits fresh GPU frames")
            settings.effect = .matrix
            pump()
            try require(view.effect == .matrix, "Existing Matrix mode still renders when selected")
            settings.effect = .lightning
            pump()
            try require(view.effect == .lightning && panel.frame == NotchDisplayProfile.current()?.panelFrame(for: .lightning),
                "Switching back restores lightning geometry")
            controller.update(speed: 0)
            pump(4.5)
            try require(!panel.isVisible && !view.isRendering, "Zero output fades away and stops rendering")
            controller.update(speed: 180)
            pump()
            try require(panel.isVisible, "Fresh output resumes lightning")
            settings.isEnabled = false
            pump()
            try require(!panel.isVisible && !view.isRendering, "Turning off the effect immediately stops frames")
            settings.isEnabled = true
            controller.update(speed: 90)
            pump()
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            try require(!panel.isVisible && !view.isRendering, "Display sleep releases rendering")
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            pump()
            try require(!panel.isVisible, "Waking waits for a fresh measured speed")
            controller.update(speed: 90)
            pump()
            try require(panel.isVisible, "A fresh post-wake rate resumes the column")
            let appliedTuning = NotchLightningConfiguration(thickness: 1.4, distance: 30,
                levitation: 3.5, jitter: 1.8, flow: 1.4, arcs: 1.6)
            let livePhase = view.animationPhase, liveSuspension = view.lightningElapsed
            settings.setLightningConfiguration(appliedTuning)
            pump()
            try require(view.lightningConfiguration == appliedTuning
                && panel.frame == NotchDisplayProfile.current()?.panelFrame(for: .lightning,
                    lightningConfiguration: appliedTuning)
                && view.animationPhase >= livePhase && view.lightningElapsed >= liveSuspension,
                "Applying tuning updates the live geometry without resetting either animation clock")
            settings.setLightningConfiguration(.standard)
            pump()
            controller.shutdown()
            hoverReport = try checkLightningHover(renderer: renderer)

            func descendants(_ node: NSView) -> [NSView] { [node]+node.subviews.flatMap(descendants) }
            let preview = try NotchFlamePreviewController(settings: settings, effect: .lightning)
            defer { preview.close() }
            preview.showWindow(nil)
            pump()
            let content = preview.window!.contentView!
            content.layoutSubtreeIfNeeded()
            let nodes = descendants(content)
            let scenes = nodes.compactMap { $0 as? NotchFlameMetalView }
            let selector = nodes.first { $0.accessibilityIdentifier() == "notch-preview-effect" } as! NSSegmentedControl
            let slider = nodes.first { $0.accessibilityIdentifier() == "flame-preview-speed" } as! NSSlider
            let apply = nodes.first { $0.accessibilityIdentifier() == "notch-preview-apply-effect" } as! NSButton
            let controls = nodes.compactMap { $0 as? NotchLightningControls }.first!
            try require(selector.selectedSegment == 2 && scenes.count == 3
                && selector.label(forSegment: 2) == "仓鼠发电机"
                && scenes.allSatisfy { $0.effect == .lightning && !$0.isHiddenOrHasHiddenAncestor },
                "The third segment selects all three native lightning samples")
            try require(slider.maxValue == 180 && content.bounds.contains(apply.convert(apply.bounds,to: content)),
                "Lightning presets and apply button fit the window")
            try require(nodes.compactMap { $0 as? NotchFlamePaletteEditor }.allSatisfy(\.isHidden)
                && nodes.compactMap { $0 as? NotchMatrixControls }.allSatisfy(\.isHidden),
                "Only controls belonging to the selected effect are visible")
            let savedPalette = settings.palette, savedAppearance = settings.appearance
            for (index, rate) in rates.enumerated() {
                let preset = nodes.first { $0.accessibilityIdentifier() == "flame-preview-band-\(index+1)" } as! NSButton
                preset.performClick(nil)
                pump()
                try require(slider.doubleValue == rate && settings.palette == savedPalette
                    && settings.appearance == savedAppearance, "Each preset only changes the simulated preview speed")
            }
            let tuningSliders = try NotchLightningParameter.visibleCases.map { parameter -> NSSlider in
                guard let result = nodes.first(where: {
                    $0.accessibilityIdentifier() == "lightning-style-\(parameter.rawValue)"
                }) as? NSSlider else {
                    try require(false,"Missing \(parameter.title) control")
                    fatalError()
                }
                return result
            }
            func change(_ control: NSControl) {
                if let action = control.action { NSApp.sendAction(action, to: control.target, from: control) }
                content.layoutSubtreeIfNeeded()
                pump(0.18)
            }
            let fixedWindowFrame = preview.window!.frame
            let fixedSceneSizes = scenes.map { $0.superview!.bounds.size }
            func checkFixedLayout(_ step: String) throws {
                try require(preview.window!.frame == fixedWindowFrame,
                    "\(step): parameter edits keep the settings window fixed; before=\(fixedWindowFrame), after=\(preview.window!.frame)")
                for (index, scene) in scenes.enumerated() {
                    let container = scene.superview!
                    try require(container.bounds.size == fixedSceneSizes[index]
                        && container.bounds.insetBy(dx: -0.5, dy: -0.5).contains(scene.frame),
                        "\(step): the entire effect fits inside its fixed preview card")
                }
                try require(([apply] as [NSView] + tuningSliders).allSatisfy {
                    content.bounds.contains($0.convert($0.bounds, to: content))
                }, "\(step): all controls and Save and Apply remain reachable")
            }
            for (index, parameter) in NotchLightningParameter.visibleCases.enumerated() {
                let control = tuningSliders[index]
                let saved = control.doubleValue
                for value in [parameter.range.lowerBound, parameter.range.upperBound] {
                    control.doubleValue = value
                    change(control)
                    try checkFixedLayout("\(parameter.title) at \(value)")
                }
                control.doubleValue = saved
                change(control)
            }
            for (index, control) in tuningSliders.enumerated() {
                let previous = control.doubleValue
                let parameter = NotchLightningParameter.visibleCases[index]
                let fineValue = previous + 0.001
                control.doubleValue = fineValue
                change(control)
                try require(control.doubleValue == fineValue
                    && scenes.allSatisfy { $0.lightningConfiguration[keyPath:parameter.keyPath] == fineValue },
                    "\(parameter.title) preserves fine slider changes without rounding them away")
                try checkFixedLayout("Fine \(parameter.title) edit")
                control.doubleValue = previous
                change(control)
            }
            let savedTuning = settings.lightningConfiguration
            let desiredTuning = NotchLightningConfiguration(thickness: 1.23, distance: 28,
                levitation: savedTuning.levitation, jitter: savedTuning.jitter, flow: 1.75, arcs: 0.6,
                hamsterScale: 1.25, hamsterGap: 16, hamsterSpeed: 1.4, motionEnabled: false)
            var draft = savedTuning
            for (index, parameter) in NotchLightningParameter.visibleCases.enumerated() {
                let oldPhase = scenes.map(\.animationPhase)
                let oldSuspension = scenes.map(\.lightningElapsed)
                let oldHamsters = scenes.map(\.hamsterElapsed)
                tuningSliders[index].doubleValue = desiredTuning[keyPath:parameter.keyPath]
                change(tuningSliders[index])
                draft[keyPath:parameter.keyPath] = desiredTuning[keyPath:parameter.keyPath]
                try require(controls.configuration == draft
                    && scenes.allSatisfy { $0.lightningConfiguration == draft }
                    && settings.lightningConfiguration == savedTuning,
                    "\(parameter.title) updates all previews without saving the draft")
                try require(zip(scenes,oldPhase).allSatisfy { $0.animationPhase >= $1 && $0.animationPhase-$1 < 3 }
                    && zip(scenes,oldSuspension).allSatisfy { $0.lightningElapsed >= $1 && $0.lightningElapsed-$1 < 1 }
                    && zip(scenes,oldHamsters).allSatisfy { $0.hamsterElapsed >= $1 && $0.hamsterElapsed-$1 < 1 },
                    "\(parameter.title) preserves all three running clocks")
                try checkFixedLayout("Combined \(parameter.title) edit")
            }
            let motionSwitch = nodes.first { $0.accessibilityIdentifier() == "lightning-motion-enabled" } as! NSButton
            motionSwitch.performClick(nil)
            pump(0.18)
            try require(!controls.isHidden && tuningSliders.count == 7 && motionSwitch.state == .off
                && controls.configuration == desiredTuning
                && scenes.allSatisfy { !$0.lightningConfiguration.motionEnabled }
                && settings.lightningConfiguration == savedTuning,
                "Seven sliders and the motion switch update only the preview draft")
            var cadence: [String:Double] = [:]
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let flowSlider = tuningSliders[NotchLightningParameter.visibleCases.firstIndex(of:.flow)!]
                for (name, value) in [("slow",0.25),("fast",2.5)] {
                    flowSlider.doubleValue = value
                    change(flowSlider)
                    let start = ProcessInfo.processInfo.systemUptime
                    let phase = scenes[0].animationPhase, suspension = scenes[0].lightningElapsed
                    let hamster = scenes[0].hamsterElapsed
                    pump(0.55)
                    let elapsed = ProcessInfo.processInfo.systemUptime-start
                    cadence[name+"Flow"] = (scenes[0].animationPhase-phase)/elapsed
                    cadence[name+"Suspension"] = (scenes[0].lightningElapsed-suspension)/elapsed
                    cadence[name+"Hamster"] = (scenes[0].hamsterElapsed-hamster)/elapsed
                }
                try require(cadence["fastFlow"]! > cadence["slowFlow"]!*5
                    && abs(cadence["fastSuspension"]!-cadence["slowSuspension"]!) < 0.20
                    && abs(cadence["fastHamster"]!-cadence["slowHamster"]!) < 0.20,
                    "Energy speed changes without changing levitation or GIF cadence")
                flowSlider.doubleValue = desiredTuning.flow
                change(flowSlider)
                let petSlider = tuningSliders[NotchLightningParameter.visibleCases.firstIndex(of:.hamsterSpeed)!]
                for (name,value) in [("slowPet",0.5),("fastPet",2.0)] {
                    petSlider.doubleValue = value
                    change(petSlider)
                    let start = ProcessInfo.processInfo.systemUptime
                    let phase = scenes[0].animationPhase, suspension = scenes[0].lightningElapsed
                    let hamster = scenes[0].hamsterElapsed
                    pump(0.55)
                    let elapsed = ProcessInfo.processInfo.systemUptime-start
                    cadence[name+"Flow"] = (scenes[0].animationPhase-phase)/elapsed
                    cadence[name+"Suspension"] = (scenes[0].lightningElapsed-suspension)/elapsed
                    cadence[name+"Hamster"] = (scenes[0].hamsterElapsed-hamster)/elapsed
                }
                try require(cadence["fastPetHamster"]! > cadence["slowPetHamster"]!*3
                    && abs(cadence["fastPetFlow"]!-cadence["slowPetFlow"]!) < 0.25
                    && abs(cadence["fastPetSuspension"]!-cadence["slowPetSuspension"]!) < 0.20,
                    "GIF speed changes independently without resetting energy or levitation")
                petSlider.doubleValue = desiredTuning.hamsterSpeed
                change(petSlider)
            }
            preview.selectEffect(.matrix)
            pump()
            try require(controls.isHidden,"Energy controls hide when another effect is selected")
            preview.selectEffect(.lightning)
            pump()
            try require(controls.configuration == desiredTuning
                && scenes.allSatisfy { $0.lightningConfiguration == desiredTuning },
                "Switching effects preserves the unsaved energy draft")
            apply.performClick(nil)
            pump()
            try require(NotchFlameSettings(defaults:defaults).lightningConfiguration == desiredTuning,
                "Save and Apply persists the seven sliders and motion switch")
            preview.close()
            preview.showWindow(nil)
            pump()
            try require(controls.configuration == desiredTuning
                && scenes.allSatisfy { $0.lightningConfiguration == desiredTuning },
                "Reopening reloads saved energy parameters")
            let reset = nodes.first { $0.accessibilityIdentifier() == "lightning-style-reset" } as! NSButton
            reset.performClick(nil)
            pump()
            try require(controls.configuration == .standard && settings.lightningConfiguration == desiredTuning
                && apply.isEnabled,"Restore Defaults remains an unsaved preview until applied")
            apply.performClick(nil)
            pump()
            try require(settings.lightningConfiguration == .standard
                && settings.palette == savedPalette && settings.appearance == savedAppearance,
                "Saving defaults preserves the other effects' settings")
            controlReport = ["sliders":7,"motionSwitch":true,"draftIsolation":true,"modeSwitchKeepsDraft":true,
                "saveReloadReset":true,"liveGeometryUpdated":true,"fineSliderChanges":true,"cadence":cadence,
                "fixedWindowAcrossParameterExtremes":true,"fixedPreviewCards":true,
                "settingsWindowFrame":NSStringFromRect(fixedWindowFrame)]
            preview.selectEffect(.flame)
            pump()
            try require(scenes.allSatisfy { $0.effect == .flame }, "Preview returns to the original flame")
            preview.selectEffect(.lightning)
            settings.effect = .flame
            pump()
            try require(settings.effect == .flame, "Preview selection stays unapplied until requested")
            apply.performClick(nil)
            pump()
            try require(NotchFlameSettings(defaults: defaults).effect == .lightning,
                "Save and apply persists lightning selection")
            preview.close()
            try require(scenes.allSatisfy { !$0.isRendering }, "Closing preview stops all three renderers")
            preview.showWindow(nil)
            pump()
            try require(scenes.allSatisfy { $0.effect == .lightning }, "Reopening preserves the selected effect")
            native = true
            print("PASS: native overlay, mode switching, idle, off, sleep/wake, three previews, presets and persistence")
        }
        let report: [String: Any] = ["passed": true, "nativeChecks": native,
            "input": "isolated synthetic tok/s and temporary preferences; no production measurements changed",
            "stages": observations, "layerMotion": layerMotion, "tuning":tuningReport,"controls":controlReport,
            "hover":hoverReport,
            "randomDischarges":randomReport,
            "hamsters":hamsterReport,
            "reduceMotion": true, "transparentMargins": true,
            "displayScales": [1,2,3], "otherEffectSettingsPreserved": true]
        if let index = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > index+1 {
            let file = URL(fileURLWithPath: CommandLine.arguments[index+1])
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: file)
        }
    }
}

@MainActor
private final class LightningPointerFixture {
    var location = CGPoint(x: -100_000, y: -100_000)
    var reduced = false
}

@MainActor
private func checkLightningHover(renderer: NotchFlameRenderer) throws -> [String:Any] {
    func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(domain: "EmberCat.LightningHoverCheck", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    let pointer = LightningPointerFixture()
    let geometry = NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: .lightning)
    let view = try NotchFlameMetalView(geometry: geometry, renderer: renderer,
        mouseLocation: { pointer.location }, reduceMotion: { pointer.reduced })
    let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 120, y: 160), size: geometry.size),
        styleMask: .borderless, backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true
    panel.contentView = view
    panel.orderFrontRegardless()
    defer { view.stop(); panel.close() }
    func screenPoint(_ point: CGPoint) -> CGPoint {
        let local = CGPoint(x: view.bounds.minX+point.x/view.geometry.size.width*view.bounds.width,
            y: view.isFlipped ? view.bounds.minY+point.y/view.geometry.size.height*view.bounds.height
                : view.bounds.maxY-point.y/view.geometry.size.height*view.bounds.height)
        return panel.convertPoint(toScreen: view.convert(local, to: nil))
    }
    view.setSpeed(180)
    pump(2)
    var hitChecks = 0
    for scale in [0.65, 1.0, 1.5] {
        for configuration in [NotchLightningConfiguration.standard,
            .init(thickness: 0.65, distance: 6, hamsterScale: 0.7, hamsterGap: 0),
            .init(thickness: 1.45, distance: 36, levitation: 4, jitter: 2, hamsterScale: 1.5, hamsterGap: 24)] {
            let shape = NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: .lightning,
                lightningConfiguration: configuration)
            view.geometry = shape
            view.setLightningConfiguration(configuration)
            panel.setContentSize(NSSize(width: shape.size.width*scale, height: shape.size.height*scale))
            let center = CGPoint(x: shape.notch.midX, y: shape.notchHeight+configuration.distance+18*configuration.thickness)
            let sprite = NotchLightningMotion.hamsterSize(notchWidth: 180, scale: configuration.hamsterScale)
            let halfLength = 180*1.18/2
            for point in [center,
                CGPoint(x: center.x-halfLength-configuration.hamsterGap-sprite/2, y: center.y),
                CGPoint(x: center.x+halfLength+configuration.hamsterGap+sprite/2, y: center.y)] {
                try require(view.lightningContainsPointer(at: screenPoint(point)),
                    "The energy bar and both hamsters respond across preview scales and parameter extremes")
                hitChecks += 1
            }
            for point in [CGPoint(x: center.x, y: shape.notchHeight/2),
                CGPoint(x: center.x, y: shape.size.height-2),
                CGPoint(x: shape.size.width+10, y: center.y)] {
                try require(!view.lightningContainsPointer(at: screenPoint(point)),
                    "The camera and empty canvas do not hide the generator")
                hitChecks += 1
            }
        }
    }
    view.geometry = geometry
    view.setLightningConfiguration(.standard)
    panel.setContentSize(geometry.size)
    let inside = screenPoint(CGPoint(x: geometry.notch.midX, y: geometry.notchHeight+24))
    let outside = CGPoint(x: -100_000, y: -100_000)
    let phase = view.animationPhase, suspension = view.lightningElapsed, hamster = view.hamsterElapsed
    pointer.location = inside
    pump(0.07)
    try require(view.lightningVisibility > 0 && view.lightningVisibility < 1,
        "Hover fades smoothly instead of removing the view immediately")
    pump(0.75)
    try require(view.lightningVisibility == 0 && view.isTrackingLightningPointer
        && panel.isVisible && panel.ignoresMouseEvents && !view.isHiddenOrHasHiddenAncestor,
        "A completely transparent generator keeps tracking through its click-through panel")
    pump(0.25)
    try require(view.lightningVisibility == 0 && view.animationPhase > phase
        && view.lightningElapsed > suspension && view.hamsterElapsed > hamster,
        "Staying over the generator does not flicker or reset any animation clock")
    pointer.location = outside
    pump(1.1)
    try require(view.lightningVisibility == 1 && panel.isVisible,
        "Leaving restores the fully visible generator without a new speed update")

    pointer.reduced = true
    view.setSpeed(180)
    pump(0.3)
    let frozen = [view.animationPhase, view.lightningElapsed, view.hamsterElapsed]
    pointer.location = inside
    pump(0.3)
    try require(view.lightningVisibility == 0 && !view.isRendering && view.isTrackingLightningPointer
        && [view.animationPhase, view.lightningElapsed, view.hamsterElapsed] == frozen,
        "Reduced motion still hides on hover without restarting the animation")
    let frames = view.renderedFrameCount
    pump(0.3)
    try require(view.renderedFrameCount == frames,
        "A stationary pointer causes no repeated redraws in reduced motion")
    pointer.location = outside
    pump(0.3)
    try require(view.lightningVisibility == 1 && !view.isRendering,
        "Reduced-motion exit restores the generator even after rendering has paused")
    pointer.location = inside
    pump(0.3)
    view.geometry.effect = .matrix
    view.setSpeed(180)
    pump(0.3)
    // A frozen surface also needs a frame when changing the selected shader.
    view.draw()
    try require(view.lightningVisibility == 1 && !view.isTrackingLightningPointer,
        "Switching effects clears the generator's hover fade")
    view.geometry.effect = .lightning
    pointer.location = outside
    view.setSpeed(180)
    view.draw()
    pump(0.2)
    try require(view.lightningVisibility == 1 && view.isTrackingLightningPointer,
        "Switching back does not inherit a stale hidden state")
    view.stop()
    let stoppedFrames = view.renderedFrameCount
    pump(0.2)
    try require(!view.isTrackingLightningPointer && view.lightningVisibility == 1
        && view.lightningElapsed == 0 && view.hamsterElapsed == 0 && view.renderedFrameCount == stoppedFrames,
        "Stopping clears pointer tracking and animation state without leaving a timer")
    print("PASS: generator hover fade, click-through, scaled hit regions, reduced motion, exit recovery and cleanup")
    return ["hitChecks":hitChecks,"smoothFade":true,"clickThrough":true,"exitRestores":true,
        "hiddenAnimationClocksContinue":true,"reducedMotionResponsive":true,
        "stationaryReducedSurfaceDoesNotRedraw":true,"effectSwitchClearsFade":true,"stopCleansUp":true]
}
