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
        preview.close()
        try require(flames.allSatisfy { !$0.isRendering }, "Close pauses every renderer")
        preview.showWindow(nil)
        pump(1)
        try check("reopen after saving speed settings")
        let report: [String: Any] = ["passed": true,
            "input": "isolated synthetic tok/s and temporary preferences; no production settings changed",
            "steps": observations]
        if let index = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > index + 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        }
        if CommandLine.arguments.contains("--hold") { pump(45) }
    }
}
