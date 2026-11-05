import AppKit
import ImageIO

@MainActor
func checkLightningTuning(renderer: NotchFlameRenderer) throws -> [String: Any] {
    func require(_ value: Bool, _ message: String) throws {
        guard value else { throw NSError(domain: "EmberCat.LightningTuning", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    func bytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
    let suite = "EmberCat.LightningTuning.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let oldValues: [String: Double] = ["thickness":1.12,"distance":6,"levitation":1.79,
        "jitter":1.1,"flow":1.21,"arcs":0.8]
    defaults.set(try JSONSerialization.data(withJSONObject:oldValues),forKey:"notchLightningConfiguration")
    let migrated = NotchFlameSettings(defaults:defaults).lightningConfiguration
    try require(migrated.thickness == 1.12 && migrated.distance == 6 && migrated.levitation == 1.79
        && migrated.jitter == 1.1 && migrated.flow == 1.21 && migrated.arcs == 0.8
        && migrated.hamsterScale == 1 && migrated.hamsterGap == 5 && migrated.hamsterSpeed == 1
        && migrated.motionEnabled,"Legacy six-field settings keep every saved value")
    defaults.removeObject(forKey:"notchLightningConfiguration")
    let settings = NotchFlameSettings(defaults: defaults)
    let custom = NotchLightningConfiguration(thickness: 1.22, distance: 24, levitation: 2.8,
        jitter: 1.4, flow: 1.8, arcs: 0.7, hamsterScale: 1.25, hamsterGap: 14,
        hamsterSpeed: 1.35, motionEnabled: false)
    try require(settings.lightningConfiguration == .standard && settings.setLightningConfiguration(custom)
        && NotchFlameSettings(defaults: defaults).lightningConfiguration == custom,
        "Hamster tuning, motion switch and legacy movement values persist together")
    for parameter in NotchLightningParameter.allCases {
        for value in [parameter.range.lowerBound - 0.01, parameter.range.upperBound + 0.01,
                      Double.nan, Double.infinity] {
            var invalid = custom
            invalid[keyPath: parameter.keyPath] = value
            try require(!settings.setLightningConfiguration(invalid)
                && settings.lightningConfiguration == custom
                && NotchFlameSettings(defaults: defaults).lightningConfiguration == custom,
                "Invalid \(parameter.rawValue) retains the last saved configuration")
        }
    }
    defaults.set(Data("invalid".utf8), forKey: "notchLightningConfiguration")
    try require(NotchFlameSettings(defaults: defaults).lightningConfiguration == .standard,
        "Unreadable saved tuning falls back to defaults")

    func geometry(_ configuration: NotchLightningConfiguration, width: CGFloat = 180) -> NotchFlameGeometry {
        .init(notchWidth: width, notchHeight: 32, effect: .lightning, lightningConfiguration: configuration)
    }
    func centroid(_ image: CGImage, geometry: NotchFlameGeometry) -> SIMD2<Double> {
        let pixels = bytes(image), scale = Double(image.width)/geometry.size.width
        var mass = 0.0, xSum = 0.0, ySum = 0.0
        for y in Int((geometry.notchHeight+3)*scale)..<image.height {
            for x in 0..<image.width {
                if abs(Double(x)/scale-geometry.notch.midX) > geometry.notchWidth*0.56 { continue }
                let alpha = Double(pixels[(y*image.width+x)*4+3])/255
                if alpha < 0.12 { continue }
                mass += alpha
                xSum += (Double(x)/scale-geometry.notch.midX)*alpha
                ySum += (Double(y)/scale-geometry.notchHeight)*alpha
            }
        }
        return SIMD2(xSum/max(1,mass), ySum/max(1,mass))
    }
    let levitating = NotchLightningConfiguration(levitation: 3, jitter: 0, arcs: 0)
    let shape = geometry(levitating)
    let a = try renderer.image(geometry: shape, time: 13, speed: 180, lightningMotionTime: 1.4)
    let b = try renderer.image(geometry: shape, time: 13, speed: 180, lightningMotionTime: 4.2)
    let shift = centroid(a,geometry: shape)-centroid(b,geometry: shape)
    try require(abs(shift.y) > 3.5, "Actual GPU tube position follows the levitation control")
    let frozenA = try renderer.image(geometry: shape, time: 13, speed: 180, lightningMotionTime: 1.4, reduceMotion: true)
    let frozenB = try renderer.image(geometry: shape, time: 99, speed: 180, lightningMotionTime: 4.2, reduceMotion: true)
    try require(bytes(frozenA) == bytes(frozenB), "Reduced motion disables suspension and recoil as well as flow")

    let still = NotchLightningConfiguration(levitation: 0, jitter: 0)
    let shaking = NotchLightningConfiguration(levitation: 0, jitter: 2)
    let stillShape = geometry(still), shakeShape = geometry(shaking)
    let recoilPhase = (0..<1_200).map { Double($0)/120 }.first { time in
        let events = NotchLightningDischarges.events(phase: time)
        return (0.025...0.045).contains(events[0].age) && events[0].power > 0.85
            && (events[1].age < 0 || events[1].age > 0.45)
    }!
    let stillImage = try renderer.image(geometry: stillShape, time: recoilPhase, speed: 180, lightningMotionTime: 0)
    let shakeImage = try renderer.image(geometry: shakeShape, time: recoilPhase, speed: 180, lightningMotionTime: 0)
    let recoil = centroid(shakeImage,geometry: shakeShape)-centroid(stillImage,geometry: stillShape)
    try require(abs(recoil.y) > 0.3, "The jitter control produces a small, real displacement at discharge")
    var fast = levitating
    fast.flow = 2.5
    try require(NotchLightningMotion.pose(elapsed: 3, phase: 13, heat: 1, configuration: fast)
        == NotchLightningMotion.pose(elapsed: 3, phase: 13, heat: 1, configuration: levitating),
        "Levitation is independent of the energy-flow multiplier")
    try require(NotchLightningMotion.pose(elapsed: 3, phase: 12.4, heat: 1, configuration: still) == .init(),
        "Both movement controls can be disabled")

    let extreme = NotchLightningConfiguration(thickness: 1.45, distance: 36, levitation: 4,
        jitter: 2, flow: 2.5, arcs: 2, hamsterScale: 1.5, hamsterGap: 24, hamsterSpeed: 2)
    let close = NotchLightningConfiguration(thickness: 1.45, distance: 6, levitation: 4,
        jitter: 2, flow: 2.5, arcs: 2, hamsterScale: 1.5, hamsterGap: 0, hamsterSpeed: 2)
    let thin = NotchLightningConfiguration(thickness: 0.65, distance: 36, levitation: 4,
        jitter: 2, flow: 0.25, arcs: 2, hamsterScale: 1.5, hamsterGap: 24)
    let tiny = NotchLightningConfiguration(thickness: 0.65, levitation: 4, jitter: 2,
        hamsterScale: 0.7, hamsterGap: 0, hamsterSpeed: 0.5)
    var checkedFrames = 0
    for width: CGFloat in [96, 180, 240] {
        for configuration in [NotchLightningConfiguration.standard, extreme, close, thin, tiny] {
            let shape = geometry(configuration, width: width)
            for time in [1.4, 4.2, 12.4] {
                let image = try renderer.image(geometry: shape, time: time, speed: 180, lightningMotionTime: time)
                let pixels = bytes(image)
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let i = (y*image.width+x)*4, alpha = Int(pixels[i+3])
                        try require(Int(max(pixels[i],pixels[i+1],pixels[i+2])) <= alpha+1,
                            "Tuning extremes preserve premultiplied alpha")
                        let notchCore = y < 60
                            && Double(x)/2 > shape.notch.minX+shape.cornerRadius
                            && Double(x)/2 < shape.notch.maxX-shape.cornerRadius
                        if x < 2 || x >= image.width-2 || y >= image.height-4 || notchCore {
                            try require(alpha == 0, "Tuning and movement remain inside their reserved display surface")
                        }
                    }
                }
                let pose = NotchLightningMotion.pose(elapsed: time, phase: time, heat: 1,
                    configuration: configuration, notchWidth: width)
                let rise = abs(sin(pose.angle))*width*1.18/2
                try require(configuration.distance+pose.offset.y-rise >= 2.49,
                    "Even maximum movement at the minimum gap cannot enter the notch")
                checkedFrames += 1
            }
        }
    }
    for effect in [NotchEffectStyle.flame, .matrix] {
        let shape = NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: effect)
        try require(bytes(try renderer.image(geometry: shape, time: 12.4, speed: 90))
            == bytes(try renderer.image(geometry: shape, time: 12.4, speed: 90, lightningConfiguration: extreme)),
            "Lightning tuning does not alter \(effect.rawValue)")
    }
    print("PASS: tuning persistence, validation, independent levitation, recoil, reduced motion and extreme display bounds")
    return ["sliderCount":NotchLightningParameter.visibleCases.count,"motionSwitch":true,
        "legacyMigrationPreserved":true,
        "levitationShiftPoints":[shift.x,shift.y],"recoilShiftPoints":[recoil.x,recoil.y],
        "extremeFramesChecked":checkedFrames,"savedConfigurationIsolated":true]
}

@MainActor
func checkLightningDischarges(renderer: NotchFlameRenderer) throws -> [String: Any] {
    func require(_ value: Bool, _ message: String) throws {
        guard value else { throw NSError(domain: "EmberCat.LightningDischarges", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    var strikes = Array(repeating: [Double: NotchLightningDischarge](), count: 6)
    for tick in 0..<5_760 {
        let phase = Double(tick)/120
        let events = NotchLightningDischarges.events(phase: phase)
        for (index, event) in events.enumerated() where event.envelope > 0.1 {
            strikes[index][event.birth] = event
            let next = NotchLightningDischarges.events(phase: phase+1/240)[index]
            try require(next.birth == event.birth && next.position == event.position
                && next.length == event.length && next.slant == event.slant,
                "A live strike keeps its root and shape through frame and scheduling boundaries")
        }
    }
    var distribution = [[String: Any]]()
    for (index, channel) in strikes.enumerated() {
        let ordered = channel.values.sorted { $0.birth < $1.birth }
        let intervals = zip(ordered.dropFirst(),ordered).map { $0.birth-$1.birth }
        let roots = ordered.map(\.position), lengths = ordered.map(\.length)
        try require(ordered.count > 12 && intervals.max()! > intervals.min()!*1.6
            && roots.max()!-roots.min()! > 0.40 && lengths.max()!-lengths.min()! > 0.30,
            "Channel \(index) varies strike spacing, position and reach across 48 seconds")
        distribution.append(["channel":index,"strikes":ordered.count,
            "intervalRange":[intervals.min()!,intervals.max()!],
            "rootRange":[roots.min()!,roots.max()!],"lengthRange":[lengths.min()!,lengths.max()!]])
    }

    let configuration = NotchLightningConfiguration(levitation: 0, jitter: 0)
    let shape = NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: .lightning,
        lightningConfiguration: configuration)
    let selected = strikes[0].values.sorted { $0.birth < $1.birth }.prefix(10)
    var centers = [Double]()
    for strike in selected {
        let phase = strike.birth+0.04
        let rendered = try renderer.image(geometry: shape, time: phase, speed: 180)
        let pixels = Array(rendered.dataProvider!.data! as Data)
        var mass = 0.0, weightedX = 0.0
        let belowShell = Int((shape.notchHeight+configuration.distance+NotchLightningMotion.diameter(heat: 1)+4)*2)
        for y in belowShell..<rendered.height {
            for x in 0..<rendered.width {
                if abs(Double(x)/2-shape.notch.midX) > shape.notchWidth*1.18*0.48 { continue }
                let alpha = Double(pixels[(y*rendered.width+x)*4+3])
                if alpha < 12 { continue }
                mass += alpha
                weightedX += (Double(x)/2-shape.notch.midX)*alpha
            }
        }
        try require(mass > 1_000, "Each sampled random strike produces real GPU leakage")
        centers.append(weightedX/mass)
    }
    try require(centers.max()!-centers.min()! > 40,
        "Rendered leakage actually moves along the tube, rather than only changing its trigger time")

    let phase = selected.first!.birth+0.04
    let a = try renderer.image(geometry: shape, time: phase, speed: 180)
    let repeatImage = try renderer.image(geometry: shape, time: phase, speed: 180)
    let other = try NotchFlameRenderer(lightningSeed: NotchLightningDischarges.previewSeed ^ 0x7F31_DA28)
    let b = try other.image(geometry: shape, time: phase, speed: 180)
    let aBytes = a.dataProvider!.data! as Data, bBytes = b.dataProvider!.data! as Data
    try require(aBytes == repeatImage.dataProvider!.data! as Data
        && zip(aBytes,bBytes).filter { $0 != $1 }.count > 150,
        "One seed is stable, while a new session seed changes the actual rendered discharges")
    print("PASS: irregular strike timing, moving roots, varied reach, stable attachments and independent session seeds")
    return ["sampledPhaseSeconds":48,"channels":distribution,"renderedLeakCentersPoints":centers,
        "stableAttachments":true,"seededReplay":true,"differentSeedsChangePixels":true]
}

@MainActor
func checkLightningHamsters(renderer: NotchFlameRenderer) throws -> [String: Any] {
    func require(_ value: Bool, _ message: String) throws {
        guard value else { throw NSError(domain: "EmberCat.LightningHamstersCheck", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let folder = root.appendingPathComponent("Sources/EmberCat/Resources/NotchLightning")
    let manifest = try NotchLightningHamsterManifest.load(from: folder)
    let configuration = NotchLightningConfiguration(levitation: 0, jitter: 0, arcs: 0)
    let geometry = NotchFlameGeometry(notchWidth: 180, notchHeight: 32, effect: .lightning,
        lightningConfiguration: configuration)
    var results = [[String: Any]]()
    for (index, clip) in manifest.clips.enumerated() {
        let source = root.appendingPathComponent("Artwork/NotchLightning/Hamsters/\(clip.name).gif")
        guard let gif = CGImageSourceCreateWithURL(source as CFURL,nil) else {
            try require(false,"Original hamster GIF is readable")
            continue
        }
        try require(CGImageSourceGetCount(gif) == clip.frameDurations.count,
            "Every original \(clip.name) GIF frame is retained")
        var elapsed = 0.0
        for (frame, duration) in clip.frameDurations.enumerated() {
            let properties = CGImageSourceCopyPropertiesAtIndex(gif,frame,nil) as! [CFString: Any]
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as! [CFString: Any]
            let original = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime]
                ?? gifProperties[kCGImagePropertyGIFDelayTime]) as! Double
            try require(abs(original-duration) < 1e-8
                && clip.frame(at: elapsed+duration/2) == clip.firstFrame+frame,
                "\(clip.name) preserves source playback timing and frame order")
            elapsed += duration
        }
        try require(clip.frame(at: elapsed) == clip.firstFrame,"Each animation loops without a held last frame")

        let speed = [20.0,90,180][index]
        let heat = NotchFlameAnimation.heat(for: speed)
        let halfLength = geometry.notchWidth*(0.88+0.30*heat)/2
        func render(_ motionTime: Double, phase: Double = 12.4) throws -> CGImage {
            try renderer.image(geometry: geometry,time: phase,speed: speed,lightningMotionTime: motionTime)
        }
        let a = try render(0), b = try render(0.12), loop = try render(elapsed)
        let aBytes = Array(a.dataProvider!.data! as Data)
        let bBytes = Array(b.dataProvider!.data! as Data)
        let flowing = Array(try render(0,phase: 12.65).dataProvider!.data! as Data)
        var left = 0, right = 0, middle = 0, energyMotion = 0, petMotionFromFlow = 0
        for y in 0..<a.height {
            for x in 0..<a.width {
                let offset = (y*a.width+x)*4
                let position = Double(x)/2-geometry.notch.midX
                let change = (0..<4).map { abs(Int(aBytes[offset+$0])-Int(bBytes[offset+$0])) }.max()!
                let flowChange = (0..<4).map { abs(Int(aBytes[offset+$0])-Int(flowing[offset+$0])) }.max()!
                if position < -halfLength-3 {
                    if change > 2 { left += 1 }
                    if flowChange > 2 { petMotionFromFlow += 1 }
                } else if position > halfLength+3 {
                    if change > 2 { right += 1 }
                    if flowChange > 2 { petMotionFromFlow += 1 }
                } else if abs(position) < halfLength-8 {
                    if change > 2 { middle += 1 }
                    if flowChange > 2 { energyMotion += 1 }
                }
            }
        }
        try require(left > 150 && right > 150 && middle == 0,
            "Both \(clip.name) pets animate independently from a held energy-flow clock")
        try require(energyMotion > 500 && petMotionFromFlow == 0,
            "Energy visibly flows while GIF timing stays independent of the energy phase")
        try require(aBytes == Array(loop.dataProvider!.data! as Data),
            "The \(clip.name) GPU loop matches the original GIF duration")
        results.append(["clip":clip.name,"originalFrames":clip.frameDurations.count,
            "loopSeconds":elapsed,"movingLeftPixels":left,"movingRightPixels":right,
            "movingEnergyPixels":energyMotion])
    }
    print("PASS: all 72 source GIF frames, original timing, both animated sides, three speed tiers and independent energy flow")
    let controls = try checkHamsterControls(renderer: renderer, manifest: manifest)
    return ["sourceFrames":manifest.frameCount,"clips":results,"mirroredRightSide":true,
        "originalTimingPreserved":true,"energyFlowIndependent":true,"controls":controls]
}

@MainActor
private func checkHamsterControls(renderer: NotchFlameRenderer,
                                  manifest: NotchLightningHamsterManifest) throws -> [String: Any] {
    func require(_ value: Bool, _ message: String) throws {
        guard value else { throw NSError(domain:"EmberCat.HamsterControlsCheck",code:1,
            userInfo:[NSLocalizedDescriptionKey:message]) }
    }
    let base = NotchLightningConfiguration(arcs: 0, motionEnabled: false)
    func image(_ configuration: NotchLightningConfiguration, speed: Double = 90,
               clock: Double = 0, fixedGIFClock: Double? = nil) throws -> (CGImage, NotchFlameGeometry) {
        let geometry = NotchFlameGeometry(notchWidth:180,notchHeight:32,effect:.lightning,
            lightningConfiguration:configuration)
        let image = try renderer.image(geometry:geometry,time:12.4,speed:speed,
            lightningMotionTime:clock,hamsterAnimationTime:fixedGIFClock)
        return (image,geometry)
    }
    func statistics(_ configuration: NotchLightningConfiguration) throws -> (pixels: Int, distance: Double) {
        let (rendered, geometry) = try image(configuration)
        let bytes = Array(rendered.dataProvider!.data! as Data)
        let halfLength = geometry.notchWidth*(0.88+0.30*NotchFlameAnimation.heat(for:90))/2
        var pixels = 0, mass = 0.0, distance = 0.0
        for y in 0..<rendered.height {
            for x in 0..<rendered.width {
                let dx = abs(Double(x)/2-geometry.notch.midX)
                let alpha = Double(bytes[(y*rendered.width+x)*4+3])
                if dx <= halfLength+2 || alpha < 64 { continue }
                pixels += 1
                mass += alpha
                distance += dx*alpha
            }
        }
        return (pixels,distance/max(1,mass))
    }
    var small = base, large = base, close = base, far = base
    small.hamsterScale = 0.7
    large.hamsterScale = 1.5
    close.hamsterGap = 0
    far.hamsterGap = 24
    let a = try statistics(small), b = try statistics(large)
    let near = try statistics(close), away = try statistics(far)
    try require(b.pixels > a.pixels*3,"Hamster size visibly scales both rendered companions")
    try require(away.distance-near.distance > 18,"Both companions move outward with the gap control")

    for (index,clip) in manifest.clips.enumerated() {
        for multiplier in [0.5,2.0] {
            var configuration = base
            configuration.hamsterSpeed = multiplier
            let start = try image(configuration,speed:[20.0,90,180][index]).0
            let end = try image(configuration,speed:[20.0,90,180][index],clock:clip.duration/multiplier).0
            try require(start.dataProvider!.data! as Data == end.dataProvider!.data! as Data,
                "\(clip.name) honors the requested \(multiplier)x GIF playback speed")
        }
    }
    let stillA = try image(base,clock:1.4,fixedGIFClock:0).0
    let stillB = try image(base,clock:4.2,fixedGIFClock:0).0
    try require(stillA.dataProvider!.data! as Data == stillB.dataProvider!.data! as Data,
        "The motion switch stops floating and recoil without disabling the artwork")
    print("PASS: real GPU hamster size, gap, playback multiplier and independent motion switch")
    return ["sizePixelRatio":Double(b.pixels)/Double(a.pixels),
        "gapShiftPoints":away.distance-near.distance,"playbackMultipliers":[0.5,2.0],"motionSwitch":true]
}
