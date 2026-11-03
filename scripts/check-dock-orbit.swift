import AppKit
import QuartzCore

@MainActor private final class DockFixture {
    var lookup: DockLookup
    var reduced = false
    var queries = 0
    init(_ placement: DockPlacement) { lookup = .found(placement) }
}

@main
struct DockOrbitCheck {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "EmberCat.DockOrbitCheck", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor static func main() {
        do {
            let args = CommandLine.arguments
            let report: [String: Any]
            if args.contains("--preview") {
                report = try livePreview()
            } else {
                report = try checks(native: args.contains("--native"))
            }
            if let index = args.firstIndex(of: "--report"), args.count > index + 1 {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: args[index + 1]))
            }
            print("PASS: \(report["summary"] ?? "Dock orbit checks")")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor static func checks(native: Bool) throws -> [String: Any] {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let fixtures: [(CGRect, CGRect)] = [
            (CGRect(x: 343, y: 10, width: 1234, height: 84), screen),
            (CGRect(x: 5, y: 6, width: 1910, height: 60), screen),
            (CGRect(x: 5, y: 120, width: 84, height: 780), screen),
            (CGRect(x: 1830, y: 90, width: 84, height: 850), screen),
            (CGRect(x: 600, y: 4, width: 180, height: 24), screen),
            (CGRect(x: 150, y: 1086, width: 1140, height: 80), CGRect(x: 0, y: 1080, width: 1440, height: 900)),
            (CGRect(x: -1660, y: -194, width: 1592, height: 88), CGRect(x: -1728, y: -200, width: 1728, height: 1117)),
            (CGRect(x: 100, y: 4, width: 1312, height: 68), CGRect(x: 0, y: 0, width: 1512, height: 982)),
        ]
        var maxTangentError = 0.0
        var maxFootContourError = 0.0
        for (dock, screen) in fixtures {
            guard let path = DockOrbitPath(dockFrame: dock, screenFrame: screen) else {
                throw NSError(domain: "Path fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No path for \(dock)"])
            }
            var sides = Set<Int>()
            for step in 0..<4096 {
                let phase = Double(step) / 4096
                let pose = path.pose(at: phase)
                let before = path.pose(at: phase - 0.000_001)
                let after = path.pose(at: phase + 0.000_001)
                let tangent = atan2(after.center.y - before.center.y, after.center.x - before.center.x)
                let angleError = abs(atan2(sin(pose.angle - tangent), cos(pose.angle - tangent)))
                maxTangentError = max(maxTangentError, angleError)
                try require(angleError < 0.001, "Discontinuous corner heading")
                let foot = CGPoint(x: pose.center.x + DockOrbitPath.groundOffset * sin(pose.angle),
                                   y: pose.center.y - DockOrbitPath.groundOffset * cos(pose.angle))
                let inner = dock.insetBy(dx: path.dockRadius, dy: path.dockRadius)
                let nearest = CGPoint(x: min(inner.maxX, max(inner.minX, foot.x)),
                                      y: min(inner.maxY, max(inner.minY, foot.y)))
                let error = abs(hypot(foot.x - nearest.x, foot.y - nearest.y) - path.dockRadius)
                maxFootContourError = max(maxFootContourError, error)
                try require(error < 0.000_001, "Paws left the visible Dock contour at \(phase)")
                if abs(pose.center.y - path.bounds.maxY) < 0.1 { sides.insert(0) }
                if abs(pose.center.x - path.bounds.maxX) < 0.1 { sides.insert(1) }
                if abs(pose.center.y - path.bounds.minY) < 0.1 { sides.insert(2) }
                if abs(pose.center.x - path.bounds.minX) < 0.1 { sides.insert(3) }
            }
            try require(sides.count == 4, "Path omitted a side")
            try require(path.pose(at: 0).center == path.pose(at: 1).center, "Lap endpoint is not closed")
            try require(abs(path.bounds.minY + DockOrbitPath.groundOffset - dock.minY) < 0.000_001,
                        "Screen-edge avoidance pushed the bottom route through the Dock")
            try require(abs(path.bounds.minX + DockOrbitPath.groundOffset - dock.minX) < 0.000_001,
                        "Screen-edge avoidance pushed the left route through the Dock")
            try require(abs(path.bounds.maxX - DockOrbitPath.groundOffset - dock.maxX) < 0.000_001,
                        "Screen-edge avoidance pushed the right route through the Dock")
            try require(path.idleFrame.midX == dock.midX
                        && abs(path.idleFrame.minY + DockOrbitPath.idleGroundInset - dock.maxY) < 0.000_001,
                        "Idle artwork is not centered with its feet on the Dock")
            let departure = path.pose(at: path.idlePhase)
            try require(abs(departure.center.x - dock.midX) < 0.000_001 && departure.angle == 0,
                        "Running does not resume from the seated cat's Dock contact")
            try require(path.canvasFrame.contains(path.idleFrame.intersection(screen)),
                        "The orbit window clips the seated artwork")
        }
        let bottomAX = CGRect(x: 343, y: 10, width: 1234, height: 84)
        let visibleScreen = CGRect(x: 0, y: 90, width: 1920, height: 960)
        let aligned = DockLocator.alignToVisibleEdge(bottomAX, screenFrame: screen, visibleFrame: visibleScreen)
        try require(aligned == CGRect(x: 343, y: 6, width: 1234, height: 84), "AX item strip did not align to the visible Dock edge")
        try require(DockLocator.alignToVisibleEdge(bottomAX, screenFrame: screen, visibleFrame: screen) == bottomAX,
                    "An auto-hidden Dock used the screen edge as its glass border")
        let leftAX = CGRect(x: -1910, y: 150, width: 84, height: 700)
        let leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let leftVisible = CGRect(x: -1830, y: 0, width: 1830, height: 1050)
        try require(DockLocator.alignToVisibleEdge(leftAX, screenFrame: leftScreen, visibleFrame: leftVisible).maxX == -1830,
                    "Side Dock correction used the wrong display origin")
        let rightAX = CGRect(x: 1826, y: 150, width: 84, height: 700)
        try require(DockLocator.alignToVisibleEdge(rightAX, screenFrame: screen,
                                                 visibleFrame: CGRect(x: 0, y: 0, width: 1830, height: 1050)).minX == 1830,
                    "Right Dock correction missed its visible edge")
        let converted = DockOrbitPath.appKitFrame(from: CGRect(x: -1000, y: -400, width: 800, height: 70), primaryTop: 1080)
        try require(converted == CGRect(x: -1000, y: 1410, width: 800, height: 70), "Multi-screen coordinate conversion")
        try require(DockOrbitPath(dockFrame: .zero, screenFrame: screen) == nil, "Empty Dock must be rejected")
        try require(DockOrbitPath(dockFrame: CGRect(x: CGFloat.infinity, y: 0, width: 400, height: 80), screenFrame: screen) == nil,
                    "Invalid geometry must be rejected")
        print("PASS: \(fixtures.count) layouts × 4096 poses; full perimeter, tangent continuity and paw contact without inward drift")

        let schedule = [(8.0, 4.0), (65.0, 6.0), (180.0, 8.0), (0.0, 16.0)]
        var distances: [Double] = []
        for fps in [120.0, 60.0, 30.0, 15.0] {
            var motion = DockOrbitMotion()
            for (speed, seconds) in schedule {
                let phase = motion.phase
                motion.setSpeed(speed)
                try require(motion.phase == phase, "Rate input reset the path phase")
                for _ in 0..<Int(fps * seconds) {
                    let velocity = motion.velocity
                    motion.advance(by: 1 / fps, pathLength: 2600)
                    try require(motion.velocity >= 0 && motion.velocity - velocity <= 220 / fps + 0.001,
                                "Unbounded acceleration")
                    try require(velocity - motion.velocity <= 180 / fps + 0.03, "Unbounded deceleration")
                }
            }
            try require(!motion.needsTicks && motion.velocity == 0, "Zero speed does not stop the animation")
            distances.append(motion.distance)
        }
        try require(distances.allSatisfy { abs($0 - distances[0]) < 0.000_001 }, "Refresh rate changed travel")
        var slow = DockOrbitMotion(), fast = DockOrbitMotion()
        slow.setSpeed(8); fast.setSpeed(180)
        for _ in 0..<1200 {
            slow.advance(by: 1 / 60, pathLength: 2600)
            fast.advance(by: 1 / 60, pathLength: 2600)
        }
        try require(fast.velocity > slow.velocity * 3, "Travel does not follow token rate")
        let phase = fast.phase, distance = fast.distance
        fast.pause()
        try require(fast.phase == phase && fast.velocity == 0, "Hide/sleep reset the route position")
        fast.advance(by: 5000, pathLength: 2600)
        try require(fast.distance - distance < 60, "Wake-up jumped through the path")
        for speed in [Double.nan, .infinity, -20] {
            fast.setSpeed(speed)
            try require(fast.director.cat.rawSpeed == 0, "Invalid rate was accepted")
        }
        print("PASS: speed changes, idle, pause and 120/60/30/15 Hz travel consistency")
        try footprintChecks()
        if native { try nativeChecks() }
        return ["summary": "Dock geometry, motion\(native ? " and native lifecycle" : "")",
                "geometryConfigurations": fixtures.count, "posesPerConfiguration": 4096,
                "maxTangentErrorRadians": maxTangentError, "maxFootContourErrorPoints": maxFootContourError,
                "travelAtRefreshRates": distances,
                "footprints": "phase-aligned contacts, fixed positions, fading, bounded count and persistent color",
                "nativeLifecycle": native, "syntheticInputs": true, "tokenRecordWrites": 0]
    }

    @MainActor static func footprintChecks() throws {
        var reference: [DockPawTrail.Stamp] = []
        for fps in [120.0, 60.0, 30.0, 15.0] {
            var motion = DockOrbitMotion()
            motion.setSpeed(8)
            for _ in 0..<Int(fps * 10) { motion.advance(by: 1 / fps, pathLength: 2600) }
            let marks = motion.trail.stamps
            try require(marks.count >= 6 && marks.allSatisfy { $0.kind == .paw }, "Walking did not leave paw contacts")
            try require(Set(marks.map { Int(($0.tangentOffset * 1000).rounded()) }).count == 4,
                        "Foot contacts did not follow all four rigged paws")
            let saved = marks.last!
            motion.advance(by: 0.1, pathLength: 2600)
            let aged = motion.trail.stamps.first { $0.id == saved.id }!
            try require(saved.orbitPhase == aged.orbitPhase && saved.tangentOffset == aged.tangentOffset
                        && aged.opacity < saved.opacity, "An old footprint moved or did not fade")
            if reference.isEmpty { reference = marks }
            else {
                try require(marks.count == reference.count && zip(marks, reference).allSatisfy {
                    $0.id == $1.id && abs($0.orbitPhase - $1.orbitPhase) < 1e-8 && abs($0.age - $1.age) < 1e-8
                }, "Foot contacts depend on display refresh rate")
            }
            motion.setSpeed(180)
            for _ in 0..<Int(fps * 12) {
                motion.advance(by: 1 / fps, pathLength: 2600)
                try require(motion.trail.stamps.count <= DockPawTrail.capacity, "Unbounded trail retention")
            }
            try require(!motion.trail.stamps.isEmpty && motion.trail.stamps.allSatisfy { $0.kind == .roll },
                        "A tucked rolling cat emitted paws")
            motion.setSpeed(0)
            for _ in 0..<Int(fps * 18) { motion.advance(by: 1 / fps, pathLength: 2600) }
            try require(motion.trail.stamps.isEmpty && !motion.needsTicks, "A faded trail kept idle animation alive")
        }
        let suite = "EmberCat.PawColorCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("broken-color", forKey: "dockPawColor")
        let settings = DockOrbitSettings(defaults: defaults)
        try require(settings.trailColorHex == "#52FFE0", "Invalid saved color did not fall back")
        settings.setTrailColor(NSColor(srgbRed: 0.8, green: 0.2, blue: 1, alpha: 0.1))
        let restored = DockOrbitSettings(defaults: defaults)
        try require(restored.trailColorHex == "#CC33FF" && restored.trailColor.alphaComponent == 1,
                    "Custom color did not survive settings reload as opaque sRGB")
        print("PASS: rigged footfalls, stationary fade, refresh-rate consistency, rolling, idle cleanup and custom color persistence")
    }

    @MainActor static func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let event = NSApp.nextEvent(matching: .any, until: min(end, Date().addingTimeInterval(0.01)),
                                          inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            NSApp.updateWindows()
        }
    }

    @MainActor static func nativeChecks() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        guard let screen = NSScreen.screens.first else { throw NSError(domain: "No graphics session", code: 1) }
        let placement = DockPlacement(dockFrame: CGRect(x: screen.frame.midX - 350, y: screen.frame.minY + 10, width: 700, height: 84),
                                      screenFrame: screen.frame, displayID: 1, scale: screen.backingScaleFactor, framesPerSecond: 60)
        let fixture = DockFixture(placement)
        let suite = "EmberCat.DockOrbitCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DockOrbitSettings(defaults: defaults)
        let title = "EmberCat · Dock 测试（模拟速率）"
        let controller = DockOrbitController(settings: settings, locate: {
            fixture.queries += 1
            return fixture.lookup
        }, reduceMotion: { fixture.reduced }, windowTitle: title)
        defer { controller.shutdown() }
        try require(!settings.isEnabled && fixture.queries == 0, "Disabled mode polled Dock")
        settings.isEnabled = true
        pump(0.15)
        guard let panel = NSApp.windows.first(where: { $0.title == title }) else { throw NSError(domain: "Missing cat window", code: 1) }
        try require(panel.isVisible && panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain,
                    "Overlay intercepts input or is not visible")
        try require(!panel.isOpaque && panel.backgroundColor.alphaComponent == 0 && !panel.hasShadow,
                    "Dock overlay added a background or window shadow")
        try require(!controller.isAnimating, "Idle mode still has a display link")
        guard let sprite = panel.contentView?.layer?.sublayers?.first(where: { $0.name == "dock-cat-sprite" }),
              let trail = panel.contentView?.layer?.sublayers?.first(where: { $0.name == "dock-paw-trail" }) else {
            throw NSError(domain: "Missing sprite or footprint layer", code: 1)
        }
        try require(sprite.contents != nil, "Sprite image is missing")
        guard let idle = panel.contentView?.subviews.first as? DockIdleCatView else {
            throw NSError(domain: "Missing Dock idle artwork", code: 1)
        }
        let gazeAllowed = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        try require(!idle.isHidden && sprite.isHidden && !idle.isOpaque,
                    "Idle mode did not show only the transparent seated cat")
        try require(abs(panel.frame.minX + idle.frame.midX - placement.dockFrame.midX) < 0.001
                    && abs(panel.frame.minY + idle.frame.minY + DockOrbitPath.idleGroundInset - placement.dockFrame.maxY) < 0.001,
                    "Native idle cat is not centered or grounded")
        pump(0.3)
        try require(idle.isTracking == gazeAllowed,
                    "Idle cat did not track the pointer (window visible: \(panel.isVisible), occlusion: \(panel.occlusionState.rawValue))")
        controller.update(speed: 65)
        pump(2)
        try require(controller.isAnimating, "Measured speed did not start the display link")
        try require(idle.isHidden && !idle.isTracking && !sprite.isHidden,
                    "Running kept the seated cat or its gaze timer active")
        try require(trail.sublayers?.isEmpty == false, "Native footprint layer is empty")
        settings.setTrailColor(DockOrbitSettings.color(hex: "#CC33FF")!)
        try require(trail.sublayers!.allSatisfy { $0.shadowColor == settings.trailColor.cgColor },
                    "Existing footprints did not recolor immediately")
        let position = sprite.position
        pump(0.3)
        try require(position != sprite.position, "Native layer did not move")
        controller.update(speed: 0)
        pump(13)
        try require(!controller.isAnimating && trail.sublayers?.isEmpty != false, "Native footprints did not expire and stop")
        try require(!idle.isHidden && sprite.isHidden && idle.isTracking == gazeAllowed,
                    "Stopping did not return to mouse-following idle artwork")
        try require(abs(panel.frame.minX + sprite.position.x - placement.dockFrame.midX) < 0.001,
                    "Next run is not parked at the Dock midpoint")
        controller.update(speed: 65)
        pump(1.5)
        fixture.reduced = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try require(!controller.isAnimating && panel.isVisible && trail.sublayers?.isEmpty != false,
                    "Reduce Motion did not stop movement and clear the trail")
        try require(!idle.isHidden && !idle.isTracking && idle.gaze.direction == .zero,
                    "Reduce Motion did not leave a neutral seated cat")
        fixture.reduced = false
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        controller.update(speed: 0)
        pump(0.6)
        try require(!controller.isAnimating && panel.isVisible, "Idle did not settle and stop the display link")
        settings.isEnabled = false
        let queries = fixture.queries
        pump(0.6)
        try require(!panel.isVisible && fixture.queries == queries, "Disabled mode kept a timer or window")
        try require(!idle.isTracking, "Disabled Dock kept the gaze timer")
        settings.isEnabled = true
        try require(NSApp.windows.filter { $0.title == title }.count == 1 && panel.isVisible, "Toggling created duplicate windows")
        let oldFrame = panel.frame
        fixture.lookup = .found(DockPlacement(dockFrame: placement.dockFrame.insetBy(dx: 100, dy: 0),
                                              screenFrame: placement.screenFrame, displayID: 1, scale: placement.scale, framesPerSecond: 60))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        pump(1.8)
        try require(panel.frame != oldFrame && !controller.isAnimating, "Dock resize did not settle")
        if case .found(let resized) = fixture.lookup {
            try require(abs(panel.frame.minX + idle.frame.midX - resized.dockFrame.midX) < 0.1,
                        "Resized Dock left the idle artwork off center")
        }
        fixture.lookup = .hidden
        pump(0.6)
        try require(!panel.isVisible && !controller.isAnimating, "Auto-hidden Dock left an overlay")
        try require(!idle.isTracking, "Auto-hidden Dock kept the gaze timer")
        fixture.lookup = .needsAccessibility
        pump(0.6)
        try require(settings.status == .needsAccessibility && !panel.isVisible, "Missing access guessed a Dock position")
        fixture.lookup = .found(placement)
        pump(0.6)
        controller.update(speed: 180)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try require(!controller.isAnimating && !panel.isVisible, "Sleep left animation running")
        try require(!idle.isTracking, "Sleep kept the gaze timer")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try require(!controller.isAnimating && panel.isVisible, "Wake replayed stale speed")
        controller.update(speed: 65)
        try require(controller.isAnimating, "Fresh post-wake speed did not resume")
        controller.shutdown()
        try require(!panel.isVisible && !controller.isAnimating, "Shutdown leaked the overlay")
        try require(!idle.isTracking, "Shutdown leaked the gaze timer")
        print("PASS: transparent centered idle artwork, gaze/run switching, click-through, resize, hide, sleep and shutdown")
    }

    @MainActor static func livePreview() throws -> [String: Any] {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let locator = DockLocator()
        guard case .found(let placement) = locator.locate() else {
            throw NSError(domain: "Dock preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Dock geometry unavailable; no permission is requested by this test"])
        }
        let suite = "EmberCat.DockOrbitPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DockOrbitSettings(defaults: defaults)
        settings.isEnabled = true
        let title = "EmberCat · Dock 跑圈预览（模拟 65 tok/s）"
        let controller = DockOrbitController(settings: settings, locate: { locator.locate() }, windowTitle: title)
        defer { controller.shutdown() }
        let caption = NSPanel(contentRect: CGRect(x: placement.dockFrame.midX - 190, y: placement.dockFrame.maxY + 62, width: 380, height: 30),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        caption.isOpaque = false
        caption.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        caption.ignoresMouseEvents = true
        caption.level = .floating
        caption.isReleasedWhenClosed = false
        caption.hidesOnDeactivate = false
        let label = NSTextField(labelWithString: "Dock 跑圈预览 · 模拟 65 tok/s · 40 秒后关闭")
        label.alignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 12)
        label.frame = CGRect(x: 6, y: 7, width: 368, height: 18)
        caption.contentView?.addSubview(label)
        caption.orderFrontRegardless()
        defer { caption.close() }
        controller.update(speed: 65)
        print("PREVIEW_READY: synthetic 65 tok/s; \(placement.dockFrame)")
        fflush(nil)
        let started = ProcessInfo.processInfo.systemUptime
        var trace: [[String: Double]] = []
        while ProcessInfo.processInfo.systemUptime - started < 40 {
            pump(0.1)
            if let window = NSApp.windows.first(where: { $0.title == title }),
               let sprite = window.contentView?.layer?.sublayers?.first(where: { $0.name == "dock-cat-sprite" }) {
                trace.append(["seconds": ProcessInfo.processInfo.systemUptime - started,
                              "x": window.frame.minX + sprite.position.x, "y": window.frame.minY + sprite.position.y,
                              "angle": atan2(sprite.transform.m12, sprite.transform.m11)])
            }
        }
        let path = DockOrbitPath(dockFrame: placement.dockFrame, screenFrame: placement.screenFrame)!
        let top = trace.filter { abs($0["y"]! - path.bounds.maxY) < 1 }
        let bottom = trace.filter { abs($0["y"]! - path.bounds.minY) < 1 }
        try require(!top.isEmpty && !bottom.isEmpty && trace.contains { $0["x"]! > path.bounds.maxX - 2 }
                    && trace.contains { $0["x"]! < path.bounds.minX + 2 }, "Live preview did not cover all four sides")
        let turn = zip(trace, trace.dropFirst()).reduce(0.0) { result, pair in
            let delta = pair.1["angle"]! - pair.0["angle"]!
            return result + atan2(sin(delta), cos(delta))
        }
        try require(turn <= -2 * .pi + 0.001, "Live preview did not complete a full loop")
        return ["summary": "40-second native preview around the actual Dock", "simulatedTokensPerSecond": 65,
                "tokenRecordWrites": 0, "verifiedClockwiseLaps": -turn / (2 * .pi), "trace": trace]
    }
}
