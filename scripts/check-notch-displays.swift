import AppKit

enum NotchDisplayChecks {
    static func run() throws -> [String: Any] {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else {
                throw NSError(domain: "EmberCat.NotchDisplayCheck", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.00001 }
        func notched(_ name: String, frame: CGRect, width: CGFloat, height: CGFloat,
                     fps: Int = 60) -> NotchScreenSnapshot {
            let x = frame.midX - width / 2, y = frame.maxY - height
            return NotchScreenSnapshot(name: name, frame: frame, safeAreaTop: height,
                leftArea: CGRect(x: frame.minX, y: y, width: x - frame.minX, height: height),
                rightArea: CGRect(x: x + width, y: y, width: frame.maxX - x - width, height: height),
                isBuiltIn: true, maximumFramesPerSecond: fps)
        }

        // All notch measurements and scale presets below are synthetic, not device measurements.
        // The four reference panel resolutions cover current Air / XDR Pro size classes.
        let families: [(String, CGFloat, CGFloat, CGFloat, Int)] = [
            ("Air 13-inch size class", 2560, 1664, 160, 60),
            ("Air 15-inch size class", 2880, 1864, 180, 60),
            ("XDR Pro 14-inch size class", 3024, 1964, 184, 120),
            ("XDR Pro 16-inch size class", 3456, 2234, 204, 120)
        ]
        let origins: [CGPoint] = [.zero, CGPoint(x: -2400, y: 180),
            CGPoint(x: 1920, y: -350), CGPoint(x: 150, y: 1440)]
        var cases = [[String: Any]]()
        for (name, pixelsWide, pixelsHigh, notchWidth, fps) in families {
            for logicalScale: CGFloat in [0.8, 1, 1.25] {
                for origin in origins {
                    let screen = CGRect(origin: origin,
                        size: CGSize(width: pixelsWide / 2 * logicalScale, height: pixelsHigh / 2 * logicalScale))
                    let width = notchWidth * logicalScale, height = 32 * logicalScale
                    let fixture = notched(name, frame: screen, width: width, height: height, fps: fps)
                    guard let profile = fixture.profile, let notch = profile.notchFrame else {
                        try require(false, "Resolve synthetic \(name) geometry")
                        continue
                    }
                    try require(near(notch.width, width) && near(notch.height, height), "Preserve logical notch dimensions")
                    try require(near(profile.geometry.cornerRadius, 9*logicalScale),
                        "The lower-corner curve scales with the notch")
                    try require(near(notch.midX, screen.midX) && near(notch.maxY, screen.maxY),
                        "Use global auxiliary-area coordinates exactly once")
                    try require(near(profile.panelFrame.maxY, screen.maxY)
                        && near(profile.panelFrame.midX, notch.midX), "Attach fire to the top-band notch")
                    try require(near(profile.panelFrame.minX, notch.minX - profile.geometry.padding)
                        && near(profile.panelFrame.maxX, notch.maxX + profile.geometry.padding)
                        && profile.geometry.padding == 5,
                        "Reserve only a narrow margin for the existing outer rim")
                    try require(screen.insetBy(dx: -0.001, dy: -0.001).contains(profile.panelFrame),
                        "Keep all flame padding on the selected screen")
                    var singleScale = fixture
                    singleScale.scale = 1
                    try require(singleScale.profile?.panelFrame == profile.panelFrame,
                        "Backing scale must not multiply AppKit placement")
                    try require(profile.preferredFramesPerSecond == fps, "Follow 60 / 120 Hz screen capability")
                    cases.append(["family": name, "syntheticLogicalScale": logicalScale,
                        "screen": NSStringFromRect(screen), "notch": NSStringFromRect(notch),
                        "panel": NSStringFromRect(profile.panelFrame), "requestedFPS": fps])
                }
            }
        }

        let external = NotchScreenSnapshot(name: "External primary",
            frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080), scale: 1)
        let laptop = notched("Built-in notch",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), width: 184, height: 32, fps: 120)
        try require(NotchDisplayProfile.select(from: [external, laptop])?.screenName == laptop.name,
            "Prefer the laptop notch while the external display is primary")
        try require(NotchDisplayProfile.select(from: [laptop, external])?.screenName == laptop.name,
            "Changing the primary display does not move fire away from the notch")
        var closed = laptop
        closed.isActive = false
        try require(NotchDisplayProfile.select(from: [external, closed])?.screenName == external.name,
            "An inactive closed-lid screen cannot retain the overlay")
        try require(NotchDisplayProfile.select(from: [external])?.screenName == external.name,
            "Use the remaining active display after disconnect")
        try require(NotchDisplayProfile.select(from: [external, laptop])?.screenName == laptop.name,
            "Reopening the laptop restores the physical notch")
        var otherNotch = laptop
        otherNotch.name = "External notch fixture"
        otherNotch.isBuiltIn = false
        try require(NotchDisplayProfile.select(from: [otherNotch, laptop])?.screenName == laptop.name,
            "Prefer a built-in notch over another reported top obstruction")
        try require(NotchDisplayProfile.select(from: []) == nil, "No display means no overlay")
        try require(external.profile?.anchorFrame.size == CGSize(width: 180, height: 32),
            "Retain the approved virtual island on flat displays")

        var invalid = [(String, NotchScreenSnapshot)]()
        var sample = laptop
        sample.leftArea = nil
        invalid.append(("missing left area", sample))
        sample = laptop
        sample.rightArea = nil
        invalid.append(("missing right area", sample))
        sample = laptop
        sample.safeAreaTop = .nan
        invalid.append(("nonfinite safe area", sample))
        sample = laptop
        sample.safeAreaTop = -1
        invalid.append(("negative safe area", sample))
        sample = laptop
        sample.safeAreaTop = sample.frame.height
        invalid.append(("safe area consumes screen", sample))
        sample = laptop
        sample.rightArea = sample.leftArea
        invalid.append(("overlapping auxiliary areas", sample))
        sample = laptop
        sample.leftArea!.origin.y -= 32
        invalid.append(("auxiliary area below top band", sample))
        sample = laptop
        sample.frame.origin.x = 1920
        invalid.append(("stale or screen-local auxiliary coordinates", sample))
        sample = laptop
        sample.scale = 0
        invalid.append(("invalid backing scale", sample))
        sample = laptop
        sample.frame.size.width = .infinity
        invalid.append(("incomplete screen bounds", sample))
        sample = laptop
        sample.safeAreaTop = 0
        invalid.append(("inconsistent top-band data", sample))
        for (name, fixture) in invalid {
            try require(fixture.profile == nil, "Reject \(name) without inventing a notch")
            try require(NotchDisplayProfile.select(from: [fixture, external])?.screenName == external.name,
                "Use valid fallback for \(name)")
        }
        try require(NotchDisplayProfile.frameRate(for: 144) == 120
            && NotchDisplayProfile.frameRate(for: 0) == 60, "Bound display cadence with a default")

        // The same tok/s must cover the same distance on Air's 60 Hz and ProMotion's 120 Hz.
        func motion(_ fps: Int) -> NotchFlameAnimation {
            var value = NotchFlameAnimation()
            value.setSpeed(90)
            for _ in 0..<(fps * 5) { value.advance(by: 1 / Double(fps)) }
            return value
        }
        let sixty = motion(60), oneTwenty = motion(120)
        try require(abs(sixty.phase - oneTwenty.phase) < 0.02 && sixty.heat == oneTwenty.heat,
            "Higher refresh rate improves smoothness without doubling flame speed")
        return ["fixtureType": "synthetic geometry only; notch sizes and scaling presets are not device measurements",
            "geometryCaseCount": cases.count, "geometryCases": cases,
            "invalidCaseCount": invalid.count, "invalidCases": invalid.map(\.0),
            "selectionChecks": ["external primary", "primary change", "lid closed", "disconnected",
                "lid reopened", "built-in preference", "no displays", "invalid data fallback"],
            "cadence": ["60HzPhase": sixty.phase, "120HzPhase": oneTwenty.phase]]
    }
}
