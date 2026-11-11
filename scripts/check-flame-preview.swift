import AppKit

@main
struct FlamePreviewCheck {
    @MainActor static func main() {
        do { try run() }
        catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            guard value else {
                throw NSError(domain: "EmberCat.FlamePreviewCheck", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func pump(_ seconds: TimeInterval = 0.25) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants($0) }
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let suite = "EmberCat.FlamePreviewCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NotchFlameSettings(defaults: defaults)
        let preview = try NotchFlamePreviewController(settings: settings)
        defer { preview.close() }
        preview.showWindow(nil)
        let window = preview.window!
        let content = window.contentView!
        func control<T: NSView>(_ identifier: String, as type: T.Type) throws -> T {
            guard let view = descendants(content).first(where: { $0.accessibilityIdentifier() == identifier }) as? T else {
                throw NSError(domain: "EmberCat.FlamePreviewCheck", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing control \(identifier)"])
            }
            return view
        }
        func act(_ control: NSControl) {
            if let action = control.action { NSApp.sendAction(action, to: control.target, from: control) }
            content.layoutSubtreeIfNeeded()
            pump()
        }
        func edit(_ field: NSTextField, _ value: String) {
            field.stringValue = value
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            content.layoutSubtreeIfNeeded()
            pump()
        }
        let flames = descendants(content).compactMap { $0 as? NotchFlameMetalView }
        let slider = try control("flame-preview-speed", as: NSSlider.self)
        var observations = [[String: Any]]()
        func check(_ step: String, lit: Bool = true) throws {
            content.layoutSubtreeIfNeeded()
            let frameCounts = flames.map(\.renderedFrameCount)
            pump()
            try require(window.isVisible && flames.count == 3, "\(step): retain all three preview scenes")
            for (index, flame) in flames.enumerated() {
                try require(!flame.isHiddenOrHasHiddenAncestor && flame.visibleRect.width > 0 && flame.visibleRect.height > 0,
                    "\(step): preview remains in the visible layout; frame=\(flame.frame), visible=\(flame.visibleRect)")
                try require(flame.drawableSize.width > 0 && flame.drawableSize.height > 0,
                    "\(step): retain a nonempty Metal surface")
                if lit && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    try require(flame.isRendering, "\(step): a nonzero preview speed must keep rendering")
                    try require(flame.renderedFrameCount > frameCounts[index],
                        "\(step): Metal must submit new frames, not just report an unpaused view")
                }
            }
            observations.append(["step": step, "simulatedSpeed": slider.doubleValue,
                "frames": flames.map { NSStringFromRect($0.frame) },
                "visibleRects": flames.map { NSStringFromRect($0.visibleRect) },
                "rendering": flames.map(\.isRendering), "renderedFrames": flames.map(\.renderedFrameCount)])
            print("PASS: \(step)")
            fflush(stdout)
        }
        pump(1)
        try check("initial preview")
        let section = try control("flame-settings-section", as: NSSegmentedControl.self)
        section.selectedSegment = 1
        act(section)
        try check("switch to speed and colors")
        edit(try control("flame-band-1-minimum", as: NSTextField.self), "45")
        edit(try control("flame-band-2-minimum", as: NSTextField.self), "80")
        try check("reported regression: thresholds 45 and 80")
        try control("flame-palette-save", as: NSButton.self).performClick(nil)
        pump()
        try require(settings.palette.bands.map(\.minimumSpeed) == [0, 45, 80], "Save the reported thresholds")
        try check("reported regression: save thresholds 45 and 80")
        edit(try control("flame-band-1-minimum", as: NSTextField.self), "75")
        try check("edit a speed threshold")
        edit(try control("flame-band-2-minimum", as: NSTextField.self), "220")
        try check("extend the preview speed range")
        let save = try control("flame-palette-save", as: NSButton.self)
        save.performClick(nil)
        pump()
        try require(settings.palette.bands.map(\.minimumSpeed) == [0, 75, 220], "Save the edited thresholds")
        try check("save speed settings")
        for rate in [20.0, 100, 250, 0, 90] {
            slider.doubleValue = rate
            act(slider)
            if rate == 0 { pump(4.3) }
            try check("set simulated speed \(rate)", lit: rate > 0)
        }
        edit(try control("flame-band-2-minimum", as: NSTextField.self), "")
        try require(!save.isEnabled, "Invalid edits cannot be saved")
        try check("incomplete speed input retains the last valid preview")
        edit(try control("flame-band-2-minimum", as: NSTextField.self), "240")
        try check("complete the speed input")
        for _ in 0..<5 { try control("flame-palette-add", as: NSButton.self).performClick(nil) }
        try check("eight color bands")
        section.selectedSegment = 0
        act(section)
        let flow = try control("flame-style-flow", as: NSSlider.self)
        for value in [0.25, 2.5, 1.0] {
            flow.doubleValue = value
            act(flow)
            try check("set flow speed \(value)")
        }
        let effect = try control("notch-preview-effect", as: NSSegmentedControl.self)
        effect.selectedSegment = 1
        act(effect)
        try check("preview Matrix code rain")
        try require(settings.effect == .flame && flames.allSatisfy { $0.effect == .matrix },
            "Preview switches all three shaders without applying the effect to production")
        try require(descendants(content).allSatisfy { $0.accessibilityIdentifier() != "matrix-style-heartSize" },
            "The removed center lamp has no remaining slider in the product")
        try require(flames.map(\.matrixColorSchemeOverride) == [.dark,.light,nil],
            "Dark and white samples preview their respective palettes; multicolor follows macOS")
        let inheritedAppearance = window.appearance
        let themeConfiguration = flames.map(\.matrixConfiguration)
        var themeObservations = [[String:Any]]()
        for scheme in NotchMatrixColorScheme.allCases {
            let before = flames.map(\.animationPhase)
            window.appearance = NSAppearance(named:scheme == .dark ? .darkAqua : .aqua)
            pump()
            try require(flames[2].matrixColorScheme == scheme
                && flames[0].matrixColorScheme == .dark && flames[1].matrixColorScheme == .light,
                "An inherited macOS appearance change updates the automatic palette without overriding fixed samples")
            try require(flames.map(\.matrixConfiguration) == themeConfiguration
                && zip(flames,before).allSatisfy { $0.animationPhase >= $1 && $0.animationPhase-$1 < 2 },
                "Appearance changes keep Matrix parameters and animation phase continuous")
            try check("macOS appearance \(scheme.rawValue)")
            themeObservations.append(["macOSAppearance":scheme.rawValue,
                "scenePalettes":flames.map { $0.matrixColorScheme.rawValue }])
        }
        window.appearance = inheritedAppearance
        let apply = try control("notch-preview-apply-effect", as: NSButton.self)
        try require(content.bounds.contains(apply.convert(apply.bounds, to: content)),
            "Matrix apply button remains within the window")
        let savedMatrix = settings.matrixConfiguration
        let savedMatrixData = defaults.data(forKey: "notchMatrixConfiguration")
        let matrixSliders = try NotchMatrixParameter.allCases.map {
            try control("matrix-style-\($0.rawValue)", as: NSSlider.self)
        }
        var matrixDraft = savedMatrix
        let matrixSpeed = slider.doubleValue
        var liveSizeResponse = [[String:Any]]()
        for rate in [20.0,90,180] {
            slider.doubleValue = rate
            act(slider)
            pump(1.8)
            liveSizeResponse.append(["tokPerSecond":rate,"radiusPoints":flames[0].matrixHorizon.z])
        }
        let liveRadii = liveSizeResponse.map { $0["radiusPoints"] as! Float }
        try require(liveRadii[1] > liveRadii[0]*1.15 && liveRadii[2] > liveRadii[1]*1.12,
            "All preview controls drive the live automatic body size at slow, medium and fast tok/s")
        slider.doubleValue = matrixSpeed
        act(slider)
        for (index, parameter) in NotchMatrixParameter.allCases.enumerated() {
            let knob = matrixSliders[index]
            try require(!knob.isHiddenOrHasHiddenAncestor
                && content.bounds.contains(knob.convert(knob.bounds, to: content))
                && knob.minValue == parameter.range.lowerBound && knob.maxValue == parameter.range.upperBound
                && knob.doubleValue == savedMatrix[keyPath:parameter.keyPath],
                "\(parameter.title) stays visible in the Matrix layout")
            for value in [parameter.range.lowerBound, parameter.range.upperBound] {
                let phases = flames.map(\.animationPhase)
                knob.doubleValue = value
                act(knob)
                matrixDraft[keyPath: parameter.keyPath] = value
                try require(flames.allSatisfy { $0.matrixConfiguration == matrixDraft },
                    "\(parameter.title) reaches all three actual Metal views")
                try require(settings.matrixConfiguration == savedMatrix
                    && defaults.data(forKey: "notchMatrixConfiguration") == savedMatrixData
                    && NotchFlameSettings(defaults: defaults).matrixConfiguration == savedMatrix,
                    "Unsaved \(parameter.title) changes remain a preview draft")
                try require(slider.doubleValue == matrixSpeed
                    && zip(flames, phases).allSatisfy { $0.animationPhase >= $1 && $0.animationPhase-$1 < 2 },
                    "\(parameter.title) edits preserve simulated speed and continuous animation phase")
                try require(apply.isEnabled, "A changed Matrix parameter re-enables save")
                try check("live Matrix \(parameter.rawValue) \(value)")
            }
        }
        apply.performClick(nil)
        pump()
        try require(settings.effect == .matrix && !apply.isEnabled
            && settings.matrixConfiguration == matrixDraft
            && NotchFlameSettings(defaults: defaults).matrixConfiguration == matrixDraft,
            "An explicit apply persists the selected effect and Matrix draft together")
        preview.close()
        preview.showWindow(nil)
        pump(1)
        try require(flames.allSatisfy { $0.matrixConfiguration == matrixDraft }
            && zip(matrixSliders, NotchMatrixParameter.allCases).allSatisfy {
                $0.doubleValue == matrixDraft[keyPath: $1.keyPath]
            }, "Reopening reloads the saved Matrix controls and all backgrounds")
        try check("reopen saved Matrix parameters")
        settings.effect = .flame
        try require(apply.isEnabled && preview.selectedEffect == .matrix,
            "A menu style change refreshes the apply button without discarding the preview")
        apply.performClick(nil)
        let resetMatrix = try control("matrix-style-reset", as: NSButton.self)
        resetMatrix.performClick(nil)
        pump()
        try require(flames.allSatisfy { $0.matrixConfiguration == .standard }
            && settings.matrixConfiguration == matrixDraft && apply.isEnabled && !resetMatrix.isEnabled
            && zip(matrixSliders,NotchMatrixParameter.allCases).allSatisfy {
                $0.doubleValue == NotchMatrixConfiguration.standard[keyPath:$1.keyPath]
            },
            "Restore defaults updates all previews but waits for explicit save")
        apply.performClick(nil)
        pump()
        try require(settings.matrixConfiguration == .standard && !apply.isEnabled,
            "Saving restored defaults persists the complete Matrix configuration")
        try check("restore and save Matrix defaults")
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            content.layoutSubtreeIfNeeded()
            if let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: image)
                try image.representation(using: .png, properties: [:])!.write(to: url)
            }
        }
        for rate in [20.0, 180, 0, 90] {
            slider.doubleValue = rate
            act(slider)
            if rate == 0 { pump(4.3) }
            try check("Matrix simulated speed \(rate)")
            if rate == 0 {
                let idlePreset = try control("flame-preview-band-0",as:NSButton.self)
                try require(idlePreset.title == "0 · 慢速待机", "The zero-rate Matrix preset describes its idle animation")
            }
        }
        let densitySlider = try control("matrix-style-density", as: NSSlider.self)
        densitySlider.doubleValue = 1.37
        act(densitySlider)
        let retainedMatrixDraft = flames[0].matrixConfiguration
        let retainedPalette = settings.palette, retainedAppearance = settings.appearance
        effect.selectedSegment = 0
        act(effect)
        try check("return from Matrix to flame settings")
        try require(content.bounds.contains(apply.convert(apply.bounds, to: content)),
            "Flame apply button remains within the window")
        try require(flames.allSatisfy { $0.effect == .flame } && settings.palette.bands.map(\.minimumSpeed) == [0,75,220],
            "Switching effects retains saved flame colors and thresholds")
        try require(matrixSliders.allSatisfy(\.isHiddenOrHasHiddenAncestor)
            && settings.palette == retainedPalette && settings.appearance == retainedAppearance,
            "Matrix controls hide in flame mode without modifying flame configuration")
        effect.selectedSegment = 1
        act(effect)
        try require(flames.allSatisfy { $0.matrixConfiguration == retainedMatrixDraft }
            && densitySlider.doubleValue == 1.37 && settings.matrixConfiguration == .standard,
            "Switching back retains the unsaved Matrix draft without persisting it")
        preview.close()
        try require(flames.allSatisfy { !$0.isRendering }, "Close pauses every renderer")
        preview.showWindow(nil)
        pump(1)
        try check("reopen after saving speed settings")
        try require(flames.allSatisfy { $0.matrixConfiguration == .standard }
            && densitySlider.doubleValue == NotchMatrixConfiguration.standard.density,
            "Closing an unsaved draft and reopening restores saved Matrix values")

        let isolatedSuite = "EmberCat.MatrixDraftCheck.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: isolatedSuite)!
        defer { isolatedDefaults.removePersistentDomain(forName: isolatedSuite) }
        let isolatedSettings = NotchFlameSettings(defaults: isolatedDefaults)
        let isolated = try NotchFlamePreviewController(settings: isolatedSettings,
            effect: .matrix, isIsolatedDraft: true)
        defer { isolated.close() }
        isolated.showWindow(nil)
        pump(1)
        let isolatedContent = isolated.window!.contentView!
        let isolatedViews = descendants(isolatedContent)
        let isolatedFlames = isolatedViews.compactMap { $0 as? NotchFlameMetalView }
        let isolatedSize = isolatedViews.first { $0.accessibilityIdentifier() == "matrix-style-blackHoleSize" } as! NSSlider
        let isolatedSave = isolatedViews.first { $0.accessibilityIdentifier() == "notch-preview-apply-effect" } as! NSButton
        let isolatedHint = isolatedViews.first { $0.accessibilityIdentifier() == "notch-preview-scope" } as! NSTextField
        try require(isolatedSave.title == "保存草稿参数" && isolatedHint.stringValue.contains("不更改已安装应用"),
            "The isolated window clearly describes simulated input and its draft-only save")
        isolatedSize.doubleValue = 1.6
        NSApp.sendAction(isolatedSize.action!, to: isolatedSize.target, from: isolatedSize)
        pump()
        try require(isolatedFlames.count == 3 && isolatedFlames.allSatisfy { $0.matrixConfiguration.blackHoleSize == 1.6 }
            && isolatedSettings.matrixConfiguration == .standard,
            "The isolated window edits three previews without saving")
        isolatedSave.performClick(nil)
        pump()
        try require(isolatedSave.title == "草稿参数已保存"
            && NotchFlameSettings(defaults: isolatedDefaults).matrixConfiguration.blackHoleSize == 1.6
            && settings.matrixConfiguration == .standard,
            "Isolated save reaches only its own settings domain")
        let savedIsolatedData = isolatedDefaults.data(forKey:"notchMatrixConfiguration")
        let requestedDraft = NotchMatrixConfiguration(blackHoleSize:1.75,gravity:1.8,density:2)
        isolated.setMatrixDraftConfiguration(requestedDraft)
        let distanceValue = isolatedViews.first {
            $0.accessibilityIdentifier() == "matrix-style-verticalOffset-value"
        } as! NSTextField
        try require(isolatedFlames.allSatisfy { $0.matrixConfiguration == requestedDraft }
            && isolatedSize.doubleValue == 1.75 && distanceValue.stringValue == "半嵌入"
            && isolatedSave.isEnabled
            && isolatedDefaults.data(forKey:"notchMatrixConfiguration") == savedIsolatedData,
            "Launching with the requested preview values updates all controls without overwriting saved settings")
        isolated.close()
        try require(isolatedFlames.allSatisfy { !$0.isRendering }, "Closing the isolated draft stops every renderer")
        let report: [String: Any] = ["passed": true,
            "input": "isolated synthetic tok/s and temporary preferences; no production settings changed",
            "matrixControls": ["threeBackgrounds": true, "phasePreserved": true,
                "unsavedDraftIsolated": true, "saveReloadReset": true, "modeSwitchPreservesDraft": true],
            "macOSAppearance":themeObservations,
            "automaticBodySize":liveSizeResponse,
            "isolatedInteractiveWindow": ["saveLabel": isolatedSave.title,
                "separatePreferences": true, "launchConfigurationIsolated":true,
                "distanceDefaultLabel":distanceValue.stringValue,"closeStopsRendering": true],
            "steps": observations]
        if let index = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > index + 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        }
        if CommandLine.arguments.contains("--hold") { pump(45) }
    }
}
