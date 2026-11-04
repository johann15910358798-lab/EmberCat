import AppKit

@main
struct MatrixCheck {
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
                throw NSError(domain: "EmberCat.MatrixCheck", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func bytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
        func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        for name in [NSAppearance.Name.aqua,.vibrantLight,.accessibilityHighContrastAqua] {
            try require(NotchMatrixColorScheme(appearance:NSAppearance(named:name)!) == .light,
                "macOS light appearances select the ink palette")
        }
        for name in [NSAppearance.Name.darkAqua,.vibrantDark,.accessibilityHighContrastDarkAqua] {
            try require(NotchMatrixColorScheme(appearance:NSAppearance(named:name)!) == .dark,
                "macOS dark appearances retain the luminous palette")
        }
        let suite = "EmberCat.MatrixCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NotchFlameSettings(defaults: defaults)
        try require(settings.effect == .flame, "Existing installations retain the flame style")
        let savedPalette = NotchFlamePalette(bands: [.init(minimumSpeed: 0, hex: "#B34DFF")])
        var savedAppearance = NotchFlameAppearance.standard
        savedAppearance.flow = 2.5
        settings.setConfiguration(palette: savedPalette, appearance: savedAppearance)
        settings.effect = .matrix
        let restored = NotchFlameSettings(defaults: defaults)
        try require(restored.effect == .matrix && restored.palette == savedPalette
            && restored.appearance == savedAppearance, "Persist effect selection independently of flame controls")
        defaults.set("unknown", forKey: "notchEffectStyle")
        try require(settings.effect == .flame, "Unknown effect falls back to flame")
        settings.effect = .matrix
        try require(settings.matrixConfiguration == .standard,
            "Preferences without saved Matrix values receive the current defaults")
        try require(settings.matrixConfiguration == .init(blackHoleSize:1.75,gravity:1.8,density:2,verticalOffset:0),
            "The preferred size, gravity and density are the defaults, with a half-immersed hole")
        for parameter in [NotchMatrixParameter.blackHoleSize,.gravity,.density] {
            let preferred = settings.matrixConfiguration[keyPath:parameter.keyPath]
            try require(parameter.range.lowerBound < preferred && preferred < parameter.range.upperBound,
                "Every preferred parameter can be adjusted both below and above its default")
        }
        let legacy = Data(#"{"blackHoleSize":1.25,"gravity":1,"density":1}"#.utf8)
        let migrated = try JSONDecoder().decode(NotchMatrixConfiguration.self,from:legacy)
        defaults.set(legacy,forKey:"notchMatrixConfiguration")
        try require(migrated == .init(blackHoleSize:1.25,gravity:1,density:1,verticalOffset:0)
            && NotchFlameSettings(defaults:defaults).matrixConfiguration == migrated,
            "Adding the distance slider preserves all three previously saved values")
        let tunedConfiguration = NotchMatrixConfiguration(blackHoleSize:1.5,gravity:1.4,density:1.7,verticalOffset:32)
        let paletteData = defaults.data(forKey:"notchFlamePalette")
        let appearanceData = defaults.data(forKey:"notchFlameAppearance")
        try require(settings.setMatrixConfiguration(tunedConfiguration)
            && NotchFlameSettings(defaults:defaults).matrixConfiguration == tunedConfiguration,
            "Matrix parameters survive saving and reopening")
        let configurationData = defaults.data(forKey:"notchMatrixConfiguration")
        for parameter in NotchMatrixParameter.allCases {
            for invalid in [Double.nan,.infinity,-.infinity,parameter.range.lowerBound-0.01,
                            parameter.range.upperBound+0.01] {
                var configuration = tunedConfiguration
                configuration[keyPath:parameter.keyPath] = invalid
                try require(!settings.setMatrixConfiguration(configuration)
                    && settings.matrixConfiguration == tunedConfiguration
                    && defaults.data(forKey:"notchMatrixConfiguration") == configurationData,
                    "Invalid Matrix parameters cannot replace a valid saved configuration")
            }
        }
        try require(defaults.data(forKey:"notchFlamePalette") == paletteData
            && defaults.data(forKey:"notchFlameAppearance") == appearanceData
            && settings.effect == .matrix,
            "Saving Matrix parameters does not contaminate flame preferences or effect selection")
        defaults.set(Data("{invalid}".utf8),forKey:"notchMatrixConfiguration")
        try require(NotchFlameSettings(defaults:defaults).matrixConfiguration == .standard,
            "Unreadable Matrix preferences fall back to valid defaults")
        settings.setMatrixConfiguration(.standard)

        func distance(_ point: SIMD2<Float>) -> Float { sqrt(point.x*point.x+point.y*point.y) }
        func median(_ values: [Float]) -> Float {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[sorted.count/2]
        }
        func spread(_ values: [Float]) -> Float { (values.max() ?? 0)-(values.min() ?? 0) }
        func glyphs(_ frame: MatrixFlowFrame) -> [UInt64:MatrixPulseSample] {
            Dictionary(uniqueKeysWithValues: frame.pulses.flatMap(\.samples).map { ($0.id,$0) })
        }
        func glyphExtent(_ sample:MatrixPulseSample,_ aperture:SIMD4<Float>) -> Float {
            let offset = sample.center-SIMD2(aperture.x,aperture.y)
            return [-1.0,1.0].flatMap { x in
                [-1.0,1.0].map { y in
                    distance(offset+SIMD2(Float(x)*sample.width*0.68,Float(y)*sample.width*0.76))
                }
            }.max()!
        }
        let seed = MatrixCodeFlow.previewSeed
        let geometry = NotchFlameGeometry(notchWidth:180,notchHeight:32,effect:.matrix)
        let heat = Float(NotchFlameAnimation.heat(for:90))
        let renderer = try NotchFlameRenderer(matrixSeed:seed)
        let hole = MatrixCodeFlow.horizon(geometry:geometry)
        func isVisible(_ sample: MatrixPulseSample) -> Bool {
            let point = MatrixCodeFlow.diskPoint(sample.center,geometry:geometry)
            let physicalDistance = distance(sample.center-SIMD2(hole.x,hole.y))
            let foreground = point.y > 1 && distance(point) > max(5,hole.z*0.28)+2.8
            return sample.opacity > 0.03 && sample.center.y > Float(geometry.notchHeight)+2
                && (physicalDistance > hole.z+1 || (sample.stage != .background && foreground))
        }
        let exposedDepth = hole.y+hole.z-Float(geometry.notchHeight)
        try require(abs(exposedDepth-hole.z) < 0.001,
            "The default position immerses exactly half of the black hole")
        try require(MemoryLayout<MatrixPulseVertex>.stride*MatrixCodeFlow.maximumInlineVertices <= 4096
            && MatrixCodeFlow.maximumInlineVertices.isMultiple(of:3),
            "Each inline Metal upload fits the buffer and keeps whole triangles")
        struct Trace {
            var firstFalling: Double?
            var firstGathering: Double?
            var firstOrbit: Double?
            var lastOrbit: Double?
            var codeSeed: Float?
            var lastStage: MatrixFlowPass?
            var endedInsideShadow = false
            var nearSpeeds: [Float] = []
            var farSpeeds: [Float] = []
        }
        var peakVertices = 0,immediateAttractionSamples = 0,orbitalMotionSamples = 0
        var completeCaptures = 0,orbitArrivals = 0,terminalSamples = 0
        var maximumTerminalExtent: Float = 0
        var portalSamples = 0,visibleResidueFrames = 0,wallFrames = 0,totalFrames = 0
        var maximumTravel: Float = 0,minimumWidth = Float.infinity,maximumWidth: Float = 0
        var speedRatios: [Float] = [],residenceTimes: [Float] = [],bundleSpreads = [[String:Any]]()
        var nearAngles: [Float] = [],farInitialAngles: [Float] = [],farLaterAngles: [Float] = []
        var nearBendDrops: [Float] = [],farBendDrops: [Float] = []
        var backgroundMotionSamples = 0,backgroundExitSamples = 0
        var inwardGatherSamples = 0,leftRearEntrySamples = 0,rightFrontEntrySamples = 0
        for testSeed in [seed,seed ^ 0x7821_B97D,seed ^ 0xD13F_A056] {
            var traces: [UInt64:Trace] = [:]
            var sourceXs = [[Float]](repeating:[],count:4)
            var capturedXs = [[Float]](repeating:[],count:4)
            for phase in stride(from:0.0,through:48,by:0.2) {
                let frame = MatrixCodeFlow.frame(geometry:geometry,time:phase,heat:heat,seed:testSeed)
                let vertices = frame.vertices
                peakVertices = max(peakVertices,vertices.count)
                try require(frame.pulses.count <= MatrixCodeFlow.maximumPulses
                    && frame.ports.count <= MatrixCodeFlow.maximumPorts
                    && vertices.count <= MatrixCodeFlow.maximumVertices,"The continuous wall remains bounded")
                let allSamples = frame.pulses.flatMap(\.samples)
                try require(Set(allSamples.map(\.id)).count == allSamples.count,
                    "Every live character has a distinct persistent identity")
                try require(zip(frame.pulses,frame.pulses.dropFirst()).allSatisfy { $0.depth <= $1.depth },
                    "Source layers draw from far to near")
                for vertex in vertices {
                    try require((0..<4).allSatisfy {
                        vertex.positionAndUV[$0].isFinite && vertex.material[$0].isFinite
                    },"No invalid vertex reaches Metal")
                }
                for index in stride(from:0,to:vertices.count,by:6) {
                    let a = vertices[index].positionAndUV,b = vertices[index+1].positionAndUV
                    let c = vertices[index+2].positionAndUV
                    try require(a.x < b.x && a.y == b.y && a.x == c.x && c.y > a.y,
                        "Characters are separate upright quads, without strip geometry")
                }
                for port in frame.ports {
                    try require(port.x.isFinite && port.intensity > 0 && port.intensity <= 1
                        && port.x > Float(geometry.notch.minX) && port.x < Float(geometry.notch.maxX),
                        "Contact light stays on the notch")
                    portalSamples += 1
                }
                let following = glyphs(MatrixCodeFlow.frame(geometry:geometry,time:phase+1/60,
                    heat:heat,seed:testSeed))
                var wallColumns = Set<UInt64>(),residueCount = 0
                for pulse in frame.pulses {
                    try require(abs(pulse.sourceX-hole.x) > hole.z+0.5,
                        "No falling code originates inside the black-hole opening")
                    sourceXs[pulse.bundle].append(pulse.sourceX)
                    for sample in pulse.samples {
                        minimumWidth = min(minimumWidth,sample.width)
                        maximumWidth = max(maximumWidth,sample.width)
                        try require(sample.width > 1 && sample.width < 4.5
                            && sample.center.x.isFinite && sample.center.y.isFinite
                            && sample.center.y <= Float(geometry.notchHeight)+(sample.stage == .background ? 112 : 52),
                            "Code remains narrow and confined to the gravity field")
                        if sample.stage == .orbiting
                            && distance(sample.center-SIMD2(hole.x,hole.y)) > hole.z+1 {
                            try require(sample.center.y > Float(geometry.notchHeight)+1,
                                "Returning code must not disappear behind the notch outside the actual black hole")
                        }
                        if sample.stage == .falling {
                            try require(abs(sample.center.x-pulse.sourceX) < 0.001,
                                "The rain stays vertical until capture; no lateral swimming columns")
                        }
                        if sample.stage == .orbiting {
                            try require(distance(MatrixCodeFlow.diskPoint(sample.center,geometry:geometry)) < hole.z*1.08,
                                "Rotating residue stays local to the opening rather than a wide lateral disk")
                        }
                        if isVisible(sample) {
                            if sample.stage == .falling || sample.stage == .background { wallColumns.insert(pulse.id) }
                            if sample.stage == .orbiting { residueCount += 1 }
                        }
                        var trace = traces[sample.id] ?? Trace()
                        if let code = trace.codeSeed {
                            try require(code == sample.codeSeed,"Characters keep their code through capture and residue")
                        }
                        trace.codeSeed = sample.codeSeed
                        if sample.stage == .falling { trace.firstFalling = trace.firstFalling ?? phase }
                        if sample.stage == .gathering {
                            if trace.firstGathering == nil && trace.firstFalling != nil {
                                let drop = sample.center.y-Float(geometry.notchHeight)
                                let sourceDistance = abs(pulse.sourceX-hole.x)
                                if sourceDistance < hole.z*2.3 { nearBendDrops.append(drop) }
                                if sourceDistance > Float(geometry.notchWidth)*0.38 { farBendDrops.append(drop) }
                            }
                            trace.firstGathering = trace.firstGathering ?? phase
                        }
                        if sample.stage == .orbiting {
                            if trace.lastStage == .gathering { capturedXs[pulse.bundle].append(sample.center.x) }
                            trace.firstOrbit = trace.firstOrbit ?? phase
                            trace.lastOrbit = phase
                        }
                        if let next = following[sample.id] {
                            let travel = distance(next.center-sample.center)
                            maximumTravel = max(maximumTravel,travel)
                            if sample.stage == .background {
                                try require(next.stage == .background && next.center.x == sample.center.x
                                    && next.center.y > sample.center.y && next.clockRate == 1,
                                    "Background rain stays vertical and never switches into capture or orbital slowdown")
                                backgroundMotionSamples += 1
                            }
                            let drop = sample.center.y-Float(geometry.notchHeight)
                            let sourceDistance = abs(pulse.sourceX-hole.x)
                            let inward = (next.center.x-sample.center.x)*(pulse.sourceX < hole.x ? 1 : -1)
                            let downward = next.center.y-sample.center.y
                            if sample.stage == .gathering && next.stage == .gathering {
                                try require(inward >= -0.001,
                                    "Incoming code must not hook outward before joining the sink")
                                inwardGatherSamples += 1
                            }
                            if sample.stage == .gathering && next.stage == .orbiting {
                                let entry = MatrixCodeFlow.diskPoint(next.center,geometry:geometry)
                                if pulse.sourceX < hole.x {
                                    try require(entry.y < 0,
                                        "The left inlet joins behind the shadow rather than curving over its front")
                                    leftRearEntrySamples += 1
                                } else {
                                    try require(entry.y > 0,
                                        "The right inlet remains on the near side of the same rotating sink")
                                    rightFrontEntrySamples += 1
                                }
                            }
                            if sample.stage == .falling && next.stage == .falling && drop > 0.5 && drop < 7 {
                                try require(inward >= 0 && downward > 0,
                                    "Falling characters never drift away from the attracting center")
                                immediateAttractionSamples += 1
                            }
                            if sample.stage != .orbiting && next.stage != .orbiting && downward > 0.001 {
                                let angle = atan2(inward,downward)
                                if sourceDistance < hole.z*2.3 && drop > 0.5 && drop < 5 {
                                    nearAngles.append(angle)
                                }
                                if sourceDistance > Float(geometry.notchWidth)*0.38 {
                                    if drop > 0.5 && drop < 5 { farInitialAngles.append(angle) }
                                    if drop > 10 && drop < 18 { farLaterAngles.append(angle) }
                                }
                            }
                            if sample.stage == .orbiting && next.stage == .orbiting {
                                let a = MatrixCodeFlow.diskPoint(sample.center,geometry:geometry)
                                let b = MatrixCodeFlow.diskPoint(next.center,geometry:geometry)
                                let cross = (a.x*b.y-a.y*b.x)/max(1,distance(a)*distance(b))
                                try require(cross >= -0.0001 && distance(b) <= distance(a)+0.01,
                                    "Residual code rotates in one direction while draining inward")
                                orbitalMotionSamples += 1
                            }
                            if isVisible(sample) && travel > 0.001 {
                                if sample.stage == .orbiting && sample.clockRate < 0.38 {
                                    trace.nearSpeeds.append(travel*60)
                                }
                                if sample.stage != .orbiting && sample.clockRate > 0.70 {
                                    trace.farSpeeds.append(travel*60)
                                }
                            }
                        } else {
                            if sample.stage == .background {
                                try require(sample.opacity < 0.001,
                                    "Uncaptured background rain fades completely before leaving the scene")
                                backgroundExitSamples += 1
                                continue
                            }
                            let offset = sample.center-SIMD2(hole.x,hole.y)
                            let extent = [-1.0,1.0].flatMap { x in
                                [-1.0,1.0].map { y in
                                    distance(offset+SIMD2(Float(x)*sample.width*0.68,Float(y)*sample.width*0.76))
                                }
                            }.max()!
                            maximumTerminalExtent = max(maximumTerminalExtent,extent/hole.z)
                            try require(sample.stage == .orbiting && extent < hole.z*0.90,
                                "Every retiring character must fit completely inside the actual shadow; opacity cannot excuse an early disappearance")
                            trace.endedInsideShadow = true
                            terminalSamples += 1
                        }
                        trace.lastStage = sample.stage
                        traces[sample.id] = trace
                    }
                }
                if wallColumns.count >= 8 { wallFrames += 1 }
                if residueCount >= 8 { visibleResidueFrames += 1 }
                totalFrames += 1
            }
            for trace in traces.values {
                if let fall = trace.firstFalling,let gather = trace.firstGathering,let orbit = trace.firstOrbit {
                    try require(fall <= gather && gather <= orbit,"A character falls, gathers and orbits in order")
                    orbitArrivals += 1
                    if trace.endedInsideShadow { completeCaptures += 1 }
                }
                if let first = trace.firstOrbit,let last = trace.lastOrbit,last-first > 1 {
                    residenceTimes.append(Float(last-first))
                }
                if trace.nearSpeeds.count > 1 && trace.farSpeeds.count > 1 {
                    speedRatios.append(median(trace.nearSpeeds)/median(trace.farSpeeds))
                }
            }
            for bundle in 0..<4 {
                let sourceWidth = spread(sourceXs[bundle]),captureWidth = spread(capturedXs[bundle])
                try require(capturedXs[bundle].count > 10 && captureWidth < sourceWidth*0.65,
                    "Wide source columns visibly converge into four narrow streams")
                bundleSpreads.append(["bundle":bundle,"sourceWidth":sourceWidth,"captureWidth":captureWidth])
            }
        }
        print("Distance angles (degrees): near \(median(nearAngles)*180/Float.pi), far start \(median(farInitialAngles)*180/Float.pi), far later \(median(farLaterAngles)*180/Float.pi); samples \(nearAngles.count)/\(farInitialAngles.count)/\(farLaterAngles.count)")
        print("Near/far vertical fall before capture: \(median(nearBendDrops))/\(median(farBendDrops)) pt")
        try require(nearBendDrops.count > 100 && farBendDrops.count > 100
            && median(farInitialAngles) < 0.01 && median(farBendDrops) > 18
            && median(nearBendDrops)+8 < median(farBendDrops),
            "Nearby rain reaches capture sooner while distant rain keeps a visible vertical run")
        try require(maximumTravel < 3 && peakVertices > MatrixCodeFlow.maximumInlineVertices,
            "Continuous glyph motion exercises batching without frame jumps")
        try require(immediateAttractionSamples > 100 && completeCaptures > 100 && terminalSamples > 100
            && portalSamples > 20,
            "The sample covers distance-graded gravity, complete absorption inside the shadow and notch contacts")
        try require(inwardGatherSamples > 1000 && leftRearEntrySamples > 20 && rightFrontEntrySamples > 20,
            "The sample covers inward capture with distinct rear-left and front-right inlets")
        try require(wallFrames > totalFrames*9/10 && visibleResidueFrames > totalFrames*9/10
            && residenceTimes.count > 20 && median(residenceTimes) > 1.2,
            "The wall feeds continuously while undigested code remains in orbit")
        try require(speedRatios.count > 20 && median(speedRatios) < 0.65,
            "Actual visible characters slow down near the hole")
        let repeated = MatrixCodeFlow.frame(geometry:geometry,time:12.4,heat:heat,seed:seed).pulses
        try require(repeated == MatrixCodeFlow.frame(geometry:geometry,time:12.4,heat:heat,seed:seed).pulses,
            "A fixed seed produces repeatable review frames")
        try require(repeated != MatrixCodeFlow.frame(geometry:geometry,time:12.4,heat:heat,seed:seed ^ 1).pulses,
            "Sessions vary their timing and column details")
        for invalid in [Double.nan,.infinity,-.infinity] {
            try require(MatrixCodeFlow.frame(geometry:geometry,time:invalid,heat:heat).pulses.isEmpty,
                "Invalid time emits no geometry")
        }

        let densityLevels = [0.4,1.0,2.0,3.0]
        var parameterDensity = [Int](repeating:0,count:densityLevels.count),stableDensityGlyphs = 0
        for phase in stride(from:0.0,through:16,by:0.4) {
            let frames = densityLevels.map { level in
                MatrixCodeFlow.frame(geometry:geometry,time:phase,heat:heat,
                    configuration:.init(density:level),seed:seed)
            }
            let abundant = glyphs(frames.last!)
            for (index,frame) in frames.enumerated() {
                for sample in frame.pulses.flatMap(\.samples) {
                    if isVisible(sample) { parameterDensity[index] += 1 }
                    guard index < frames.count-1 else { continue }
                    guard let retained = abundant[sample.id] else {
                        try require(false,"Increasing density retains every existing character")
                        continue
                    }
                    try require(sample.center == retained.center && sample.width == retained.width
                        && sample.codeSeed == retained.codeSeed && sample.stage == retained.stage
                        && sample.clockRate == retained.clockRate,
                        "Density adds characters without moving, changing or replacing existing ones")
                    stableDensityGlyphs += 1
                }
            }
        }
        try require(parameterDensity[1] > parameterDensity[0]*3/2
            && parameterDensity[2] > parameterDensity[1]*3/2
            && parameterDensity[3] > parameterDensity[2]*5/4 && stableDensityGlyphs > 1000,
            "The density slider changes actual visible character quantity throughout its range")

        var independentBackgroundSamples = 0
        var backgroundCount = 0,foregroundCount = 0
        for phase in stride(from:0.0,through:16,by:0.2) {
            let frame = MatrixCodeFlow.frame(geometry:geometry,time:phase,heat:heat,
                configuration:.init(blackHoleSize:1.75,gravity:1.8,density:2),seed:seed)
            let moved = glyphs(MatrixCodeFlow.frame(geometry:geometry,time:phase,heat:heat,
                configuration:.init(blackHoleSize:0.75,gravity:0.5,density:2,verticalOffset:64),seed:seed))
            let vertices = frame.vertices
            if let firstForeground = vertices.firstIndex(where: { $0.material.z >= 0 }) {
                try require(vertices[firstForeground...].allSatisfy { $0.material.z >= 0 },
                    "Background glyphs composite before every foreground glyph")
            }
            for sample in frame.pulses.flatMap(\.samples) where sample.opacity > 0.01 {
                if sample.stage == .background {
                    try require(moved[sample.id] == sample && sample.opacity <= 0.24,
                        "Background positions, speed, density and dimness are independent of hole size, gravity and distance")
                    independentBackgroundSamples += 1
                    backgroundCount += 1
                } else { foregroundCount += 1 }
            }
        }
        let backgroundShare = Double(backgroundCount)/Double(backgroundCount+foregroundCount)
        try require(independentBackgroundSamples > 500 && backgroundMotionSamples > 500
            && backgroundExitSamples > 20 && backgroundShare > 0.15 && backgroundShare < 0.50,
            "A restrained portion of the existing rain remains an independent background layer")

        var gravityAngles = [[Float]](repeating:[],count:2)
        var gravityTurnDrops = [[Float]](repeating:[],count:2)
        var gravityMaximumDrops = [Float](repeating:0,count:2)
        let gravityLevels = [NotchMatrixParameter.gravity.range.lowerBound,NotchMatrixParameter.gravity.range.upperBound]
        for (index,gravity) in gravityLevels.enumerated() {
            let configuration = NotchMatrixConfiguration(gravity:gravity)
            for phase in stride(from:0.0,through:16,by:0.2) {
                let frame = MatrixCodeFlow.frame(geometry:geometry,time:phase,heat:heat,
                    configuration:configuration,seed:seed)
                let next = glyphs(MatrixCodeFlow.frame(geometry:geometry,time:phase+1/60,heat:heat,
                    configuration:configuration,seed:seed))
                for pulse in frame.pulses {
                    for sample in pulse.samples where sample.stage == .falling || sample.stage == .gathering {
                        let drop = sample.center.y-Float(geometry.notchHeight)
                        gravityMaximumDrops[index] = max(gravityMaximumDrops[index],drop)
                        if abs(pulse.sourceX-hole.x) > Float(geometry.notchWidth)*0.38,
                           sample.stage == .falling, next[sample.id]?.stage == .gathering {
                            gravityTurnDrops[index].append(drop)
                        }
                        guard abs(pulse.sourceX-hole.x) > Float(geometry.notchWidth)*0.38,
                              drop > 0.5,drop < 5,let following = next[sample.id] else { continue }
                        let inward = (following.center.x-sample.center.x)*(pulse.sourceX < hole.x ? 1 : -1)
                        let downward = following.center.y-sample.center.y
                        if downward > 0.001 { gravityAngles[index].append(atan2(inward,downward)) }
                    }
                }
            }
        }
        print("Gravity response: initial angles \(gravityAngles.map { median($0)*180/Float.pi }); fall depths \(gravityMaximumDrops)")
        try require(gravityTurnDrops.allSatisfy { $0.count > 10 }
            && median(gravityTurnDrops[1])+8 < median(gravityTurnDrops[0])
            && gravityMaximumDrops[1] < gravityMaximumDrops[0]*0.85,
            "Stronger gravity shortens the vertical run and captures distant rain at a shallower depth")

        var parameterSweep = [[String:Any]]()
        var parameterTerminalSamples = 0,parameterPeakVertices = 0
        var parameterMaximumTerminalExtent: Float = 0
        func sweepValues(_ parameter:NotchMatrixParameter) -> [Double] {
            [parameter.range.lowerBound,NotchMatrixConfiguration.standard[keyPath:parameter.keyPath],
             parameter.range.upperBound]
        }
        for (width,height): (CGFloat,CGFloat) in [(128,25.6),(180,32),(255,40)] {
            let shape = NotchFlameGeometry(notchWidth:width,notchHeight:height,effect:.matrix)
            for size in sweepValues(.blackHoleSize) {
                let baseHole = MatrixCodeFlow.horizon(geometry:shape,configuration:.init(blackHoleSize:size))
                try require(abs(baseHole.y-Float(height)) < 0.001,
                    "Every size begins half immersed")
                for offset in [0.0,Double(baseHole.z)+2,64] {
                    for gravity in sweepValues(.gravity) {
                        for density in sweepValues(.density) {
                            let configuration = NotchMatrixConfiguration(blackHoleSize:size,gravity:gravity,
                                density:density,verticalOffset:offset)
                            let aperture = MatrixCodeFlow.horizon(geometry:shape,configuration:configuration)
                            let mouth = sqrt(max(0,aperture.z*aperture.z-Float(offset*offset)))
                            try require(abs(aperture.y-Float(height+offset)) < 0.001,
                                "The physical sink follows the distance control")
                            var terminals = 0,checkedReturns = 0
                            var largestExtent: Float = 0
                            // Fewer foreground births need a longer observation window
                            // to retain the same complete-capture coverage per combination.
                            for phase in stride(from:0.0,through:36,by:0.4) {
                                let frame = MatrixCodeFlow.frame(geometry:shape,time:phase,heat:1,
                                    configuration:configuration,seed:seed)
                                let next = glyphs(MatrixCodeFlow.frame(geometry:shape,time:phase+1/60,heat:1,
                                    configuration:configuration,seed:seed))
                                let vertices = frame.vertices
                                let identifiers = frame.pulses.flatMap(\.samples).map(\.id)
                                parameterPeakVertices = max(parameterPeakVertices,vertices.count)
                                try require(vertices.count <= MatrixCodeFlow.maximumVertices
                                    && frame.pulses.count <= MatrixCodeFlow.maximumPulses
                                    && identifiers.count == Set(identifiers).count,
                                    "Parameter extremes keep geometry within the renderer's capacity")
                                let sourceXs = frame.pulses.map(\.sourceX)
                                try require(sourceXs.min()! < Float(shape.notch.minX)+1.5
                                    && sourceXs.max()! > Float(shape.notch.maxX)-1.5,
                                    "Both rounded ends emit rain without fixed side gaps")
                                if offset > Double(aperture.z) {
                                    try require(sourceXs.contains { abs($0-aperture.x) < 5 },
                                        "Detaching the hole restores emission from the middle of the notch")
                                }
                                for pulse in frame.pulses {
                                    try require(abs(pulse.sourceX-aperture.x) > mouth,
                                        "Only the actual intersection blocks rain sources")
                                    for sample in pulse.samples {
                                        try require(sample.center.x.isFinite && sample.center.y.isFinite
                                            && sample.width.isFinite && sample.opacity.isFinite
                                            && sample.center.x > Float(shape.notch.minX)
                                            && sample.center.x < Float(shape.notch.maxX)
                                            && sample.center.y < Float(height+NotchFlameGeometry.maximumMatrixDepth)-6,
                                            "The movable sink retains finite paths inside the available canvas")
                                        let delta = sample.center-SIMD2(aperture.x,aperture.y)
                                        if offset == 0 && sample.stage == .gathering,
                                           let following = next[sample.id],following.stage == .gathering {
                                            let inward = (following.center.x-sample.center.x)*(pulse.sourceX < aperture.x ? 1 : -1)
                                            try require(inward >= -0.001,
                                                "Half-immersed capture never reverses outward at any parameter extreme")
                                        }
                                        if (sample.stage == .gathering || sample.stage == .orbiting) && distance(delta) > aperture.z+1 {
                                            try require(sample.center.y > Float(height),
                                                "Capture crosses notch: width=\(width), size=\(size), gravity=\(gravity), offset=\(offset), stage=\(sample.stage), point=\(sample.center), distance=\(distance(delta)), radius=\(aperture.z)")
                                            checkedReturns += 1
                                        }
                                        if sample.stage == .orbiting {
                                            let orbit = MatrixCodeFlow.diskPoint(sample.center,geometry:shape,
                                                configuration:configuration)
                                            try require(distance(orbit) <= aperture.z*1.08,
                                                "Residue follows the moved hole without a lateral excursion")
                                        }
                                        if next[sample.id] == nil {
                                            if sample.stage == .background {
                                                try require(sample.opacity < 0.001,
                                                    "Background retirement is an offscreen fade, not foreground absorption")
                                                continue
                                            }
                                            let extent = glyphExtent(sample,aperture)/aperture.z
                                            largestExtent = max(largestExtent,extent)
                                            try require(sample.stage == .orbiting && extent < 0.90,
                                                "Every glyph finishes inside the moved hole: width=\(width), offset=\(offset), extent=\(extent)")
                                            terminals += 1
                                        }
                                    }
                                }
                            }
                            try require(terminals > 30 && checkedReturns > 100,
                                "Capture coverage: width=\(width), size=\(size), gravity=\(gravity), density=\(density), offset=\(offset), terminals=\(terminals), returns=\(checkedReturns)")
                            parameterTerminalSamples += terminals
                            parameterMaximumTerminalExtent = max(parameterMaximumTerminalExtent,largestExtent)
                            parameterSweep.append(["width":width,"height":height,"blackHoleSize":size,
                                "gravity":gravity,"density":density,"verticalOffset":offset,
                                "terminalSamples":terminals,"returningSamples":checkedReturns,
                                "maximumTerminalExtentOverRadius":largestExtent])
                        }
                    }
                }
            }
        }

        let loadRates = [20.0,90,180]
        let loadHeats = loadRates.map { Float(NotchFlameAnimation.heat(for:$0)) }
        var phaseSteps: [Double] = []
        for rate in loadRates {
            var animation = NotchFlameAnimation()
            animation.setSpeed(rate)
            for _ in 0..<240 {
                animation.advance(by:1/60,flow:MatrixCodeFlow.motionMultiplier(heat:animation.heat))
            }
            let previous = animation.phase
            animation.advance(by:1/60,flow:MatrixCodeFlow.motionMultiplier(heat:animation.heat))
            phaseSteps.append(animation.phase-previous)
        }
        var density = [Float](repeating:0,count:loadRates.count)
        var glyphCounts = [Int](repeating:0,count:loadRates.count)
        var loadSamples = 0,stableLoadPaths = 0
        var loadTravelRatios: [Float] = []
        for phase in stride(from:0.0,through:24,by:0.4) {
            let frames = loadHeats.map { MatrixCodeFlow.frame(geometry:geometry,time:phase,heat:$0,seed:seed) }
            for (index,frame) in frames.enumerated() {
                peakVertices = max(peakVertices,frame.vertices.count)
                for pulse in frame.pulses {
                    let visible = pulse.samples.filter(isVisible)
                    density[index] += visible.reduce(0) { $0+$1.opacity*pulse.opacity }
                    glyphCounts[index] += visible.count
                }
            }
            let high = Dictionary(uniqueKeysWithValues:frames[2].pulses.map { ($0.id,$0) })
            let lowNext = glyphs(MatrixCodeFlow.frame(geometry:geometry,time:phase+phaseSteps[0],
                heat:loadHeats[0],seed:seed))
            let highNext = glyphs(MatrixCodeFlow.frame(geometry:geometry,time:phase+phaseSteps[2],
                heat:loadHeats[2],seed:seed))
            for pulse in frames[0].pulses {
                try require(high[pulse.id]?.samples == pulse.samples,
                    "Changing load preserves existing characters, paths and positions")
                stableLoadPaths += 1
                for sample in pulse.samples where isVisible(sample) {
                    if let slow = lowNext[sample.id],let fast = highNext[sample.id] {
                        let a = distance(slow.center-sample.center),b = distance(fast.center-sample.center)
                        if a > 0.001 && b > 0.001 { loadTravelRatios.append(b/a) }
                    }
                }
            }
            loadSamples += 1
        }
        try require(density[1] > density[0]*1.4 && density[2] > density[1]*1.25
            && glyphCounts[0] < glyphCounts[1] && glyphCounts[1] < glyphCounts[2],
            "Higher tok/s increases the visible wall and code density")
        try require(phaseSteps[0] < phaseSteps[1] && phaseSteps[1] < phaseSteps[2]
            && loadTravelRatios.count > 50 && median(loadTravelRatios) > 2,
            "Native phase integration moves existing characters faster at higher tok/s")
        var transition = NotchFlameAnimation()
        var transitionTravel: Float = 0
        for rate in [20.0,90,180,20] {
            let previousPhase = transition.phase
            transition.setSpeed(rate)
            try require(transition.phase == previousPhase,"Rate changes never reset the phase")
            for _ in 0..<150 {
                let previous = glyphs(MatrixCodeFlow.frame(geometry:geometry,time:transition.phase,
                    heat:Float(transition.heat),seed:seed))
                transition.advance(by:1/60,flow:MatrixCodeFlow.motionMultiplier(heat:transition.heat))
                let next = glyphs(MatrixCodeFlow.frame(geometry:geometry,time:transition.phase,
                    heat:Float(transition.heat),seed:seed))
                for (id,sample) in previous {
                    if let following = next[id] {
                        transitionTravel = max(transitionTravel,distance(following.center-sample.center))
                    }
                }
            }
        }
        try require(transitionTravel > 0 && transitionTravel < 6,"Load transitions keep every existing glyph continuous")
        let frozenPhase = transition.phase
        transition.setSpeed(180)
        transition.advance(by:1/60,reduceMotion:true,flow:MatrixCodeFlow.motionMultiplier(heat:transition.heat))
        try require(transition.phase == frozenPhase,"Reduced motion freezes the load-driven phase")
        transition.setSpeed(0)
        for _ in 0..<360 { transition.advance(by:1/60,flow:MatrixCodeFlow.motionMultiplier(heat:transition.heat)) }
        try require(transition.isHidden && !transition.needsFrames(reduceMotion:false),
            "Zero load fades out and stops requesting frames")

        let baseline = bytes(try renderer.image(geometry: geometry,time: 12.4,speed: 90))
        let changed = bytes(try renderer.image(geometry: geometry,time: 12.8,speed: 90))
        let changedBytes = zip(baseline,changed).filter { $0 != $1 }.count
        try require(changedBytes > 500,"Motion changes actual GPU pixels")
        try require(baseline == bytes(try renderer.image(geometry: geometry,time: 12.4,speed: 90)),
            "Actual Metal renders are reproducible")
        let reducedA = bytes(try renderer.image(geometry: geometry,time: 1,speed: 90,reduceMotion: true))
        let reducedB = bytes(try renderer.image(geometry: geometry,time: 20,speed: 90,reduceMotion: true))
        try require(reducedA == reducedB,"Reduced motion freezes the entire effect")
        for speed in [0.0,-1,.nan,.infinity] {
            try require(bytes(try renderer.image(geometry: geometry,time: 12.4,speed: speed,
                drawsAnchor: true)).allSatisfy { $0 == 0 },"Idle and invalid rates leave no effect")
        }
        try require(bytes(try renderer.image(geometry: geometry,time: 12.4,speed: 90,
            active: false,drawsAnchor: true)).allSatisfy { $0 == 0 },"Disabled effect is transparent")
        try require(baseline == bytes(try renderer.image(geometry: geometry,time: 12.4,speed: 90,
            palette: savedPalette,appearance: savedAppearance)),"Flame controls cannot alter Matrix")
        let alternate = try NotchFlameRenderer(matrixSeed: seed ^ 1)
        let flameGeometry = NotchFlameGeometry(notchWidth: 180,notchHeight: 32)
        let flame = bytes(try renderer.image(geometry: flameGeometry,time: 12.4,speed: 90))
        try require(flame.contains { $0 > 0 } && flame == bytes(try alternate.image(
            geometry: flameGeometry,time: 12.4,speed: 90)),"Matrix changes leave the flame pipeline independent")
        let lightPixels = bytes(try renderer.image(geometry:geometry,time:12.4,speed:90,matrixColorScheme:.light))
        try require(lightPixels != baseline && flame == bytes(try renderer.image(
            geometry:flameGeometry,time:12.4,speed:90,matrixColorScheme:.light)),
            "The light palette changes Matrix output without affecting flame output")
        func contrastOnWhite(_ pixels:[UInt8],at offset:Int) -> Float {
            let alpha = Float(pixels[offset+3])/255
            let channels = (0..<3).map { channel -> Float in
                let component = min(1,Float(pixels[offset+channel])/255+1-alpha)
                return component <= 0.04045 ? component/12.92 : pow((component+0.055)/1.055,2.4)
            }
            return 1.05/(0.0722*channels[0]+0.7152*channels[1]+0.2126*channels[2]+0.05)
        }
        var themeContrast = [[String:Any]]()
        for flowPass in [MatrixFlowPass.falling,.background] {
            let darkCode = bytes(try renderer.image(geometry:geometry,time:12.4,speed:90,
                scale:4,matrixColorScheme:.dark,matrixPass:flowPass))
            let lightCode = bytes(try renderer.image(geometry:geometry,time:12.4,speed:90,
                scale:4,matrixColorScheme:.light,matrixPass:flowPass))
            var previousContrast:[Float] = [],newContrast:[Float] = []
            let imageWidth = Int(geometry.size.width*4)
            for offset in stride(from:0,to:darkCode.count,by:4) {
                let x = (Float((offset/4)%imageWidth)+0.5)/4
                let y = (Float((offset/4)/imageWidth)+0.5)/4
                guard y > Float(geometry.notchHeight)+4,
                      distance(SIMD2(x-hole.x,y-hole.y)) > hole.z+8,
                      darkCode[offset+3] > (flowPass == .background ? 18 : 90) else { continue }
                previousContrast.append(contrastOnWhite(darkCode,at:offset))
                newContrast.append(contrastOnWhite(lightCode,at:offset))
            }
            print("White-background contrast \(flowPass): \(median(previousContrast)) → \(median(newContrast)); samples \(newContrast.count)")
            try require(newContrast.count > 100 && median(newContrast) > median(previousContrast)*1.5,
                "Both falling code and background rain gain contrast on a white desktop")
            themeContrast.append(["pass":flowPass.rawValue,"pixels":newContrast.count,
                "previousMedianContrast":median(previousContrast),"lightMedianContrast":median(newContrast)])
        }
        var preservedCorePixels = 0
        let themeImageWidth = Int(geometry.size.width*2)
        for offset in stride(from:0,to:baseline.count,by:4) {
            let point = SIMD2((Float((offset/4)%themeImageWidth)+0.5)/2-hole.x,
                (Float((offset/4)/themeImageWidth)+0.5)/2-hole.y)
            if distance(point) < hole.z-1 {
                try require(lightPixels[offset...offset+3] == baseline[offset...offset+3],
                    "The black core and near-side luminous code keep their contrast in light mode")
                preservedCorePixels += 1
            }
            try require(lightPixels[offset...offset+2].allSatisfy { Int($0) <= Int(lightPixels[offset+3])+1 },
                "Light colors retain premultiplied alpha for transparent compositing")
        }
        var parameterPixelChecks = [[String:Any]]()
        for parameter in NotchMatrixParameter.allCases {
            for value in [parameter.range.lowerBound,parameter.range.upperBound] {
                var configuration = NotchMatrixConfiguration.standard
                configuration[keyPath:parameter.keyPath] = value
                let tuned = bytes(try renderer.image(geometry:geometry,time:12.4,speed:90,
                    matrixConfiguration:configuration))
                let differences = zip(baseline,tuned).filter { $0 != $1 }.count
                try require(configuration == .standard ? differences == 0 : differences > 100,
                    "Every Matrix slider changes actual rendered pixels: \(parameter.rawValue)=\(value)")
                try require(flame == bytes(try renderer.image(geometry:flameGeometry,time:12.4,speed:90,
                    matrixConfiguration:configuration)),
                    "Matrix tuning cannot change the flame effect")
                parameterPixelChecks.append(["parameter":parameter.rawValue,"value":value,
                    "changedBytes":differences])
            }
        }
        var imageChecks = [[String: Any]]()
        for (width,height,scale): (CGFloat,CGFloat,CGFloat) in [(128,25.6,2),(180,32,1),(180,32,2),(255,40,2)] {
            let shape = NotchFlameGeometry(notchWidth: width,notchHeight: height,effect: .matrix)
            for phase in [8.73,12.4,18,250_000] {
                let image = try renderer.image(geometry: shape,time: phase,speed: 90,scale: scale)
                let pixels = bytes(image)
                var codePixels = 0,opaqueDarkPixelsOutsideHorizon = 0
                let aperture = MatrixCodeFlow.horizon(geometry: shape)
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let offset = (y*image.width+x)*4,alpha = Int(pixels[offset+3])
                        try require(pixels[offset...offset+2].allSatisfy { Int($0) <= alpha+1 },
                            "Output remains premultiplied for transparent desktop compositing")
                        if x == 0 || x == image.width-1 || y == image.height-1 {
                            try require(alpha == 0,"No hard rectangular edge at the canvas boundary")
                        }
                        let px = (CGFloat(x)+0.5)/scale,py = (CGFloat(y)+0.5)/scale
                        if py > height+4 {
                            if px < shape.notch.minX || px >= shape.notch.maxX {
                                try require(alpha == 0,"Code remains within the notch footprint")
                            }
                            if alpha > 15 && pixels[offset+1] > pixels[offset+2] { codePixels += 1 }
                            if alpha > 215 && pixels[offset+1] < 20 {
                                let delta = SIMD2(Float(px)-aperture.x,Float(py)-aperture.y)
                                if distance(delta) > aperture.z+1 { opaqueDarkPixelsOutsideHorizon += 1 }
                            }
                        }
                    }
                }
                let camera = (Int(10*scale)*image.width+image.width/2)*4+3
                try require(pixels[camera] == 0,"The physical camera region is untouched")
                try require(opaqueDarkPixelsOutsideHorizon == 0,
                    "Dark coverage is limited to the embedded shadow, with no floating body below it")
                imageChecks.append(["width":width,"height":height,"scale":scale,"phase":phase,
                    "codePixels":codePixels,"opaqueDarkPixelsOutsideHorizon":opaqueDarkPixelsOutsideHorizon])
            }
        }
        try require(imageChecks.contains { ($0["codePixels"] as? Int ?? 0) > 100 },
            "Character-only pulses remain visible in actual GPU output")
        var emissionChecks = [[String:Any]]()
        for (width,height): (CGFloat,CGFloat) in [(128,25.6),(180,32),(255,40)] {
            let shape = NotchFlameGeometry(notchWidth:width,notchHeight:height,effect:.matrix)
            var configuration = NotchMatrixConfiguration(blackHoleSize:1.75,gravity:1.8,density:2)
            let radius = MatrixCodeFlow.horizon(geometry:shape,configuration:configuration).z
            let interior = CGPath(roundedRect:CGRect(x:shape.notch.minX+1,y:-10,
                width:width-2,height:height+9),cornerWidth:shape.cornerRadius-1,
                cornerHeight:shape.cornerRadius-1,transform:nil)
            for offset in [0.0,Double(radius)+2,64] {
                configuration.verticalOffset = offset
                var edgePixels = [0,0]
                for phase in stride(from:8.0,to:10.4,by:0.2) {
                    let image = try renderer.image(geometry:shape,time:phase,speed:90,scale:2,
                        matrixConfiguration:configuration,matrixPass:.falling)
                    let pixels = bytes(image)
                    for y in 0..<Int((height+16)*2) {
                        for x in Int(shape.notch.minX*2)..<Int(shape.notch.maxX*2) {
                            let point = CGPoint(x:(Double(x)+0.5)/2,y:(Double(y)+0.5)/2)
                            let p = (y*image.width+x)*4
                            if interior.contains(point) {
                                try require(pixels[p+3] == 0,
                                    "Rounded-edge emission never paints inside the physical notch")
                            }
                            if point.y > height+5 && point.y < height+15 && pixels[p+3] > 8
                                && pixels[p+1] > pixels[p] && pixels[p+1] > pixels[p+2] {
                                if point.x < shape.notch.minX+5 { edgePixels[0] += 1 }
                                if point.x > shape.notch.maxX-5 { edgePixels[1] += 1 }
                            }
                        }
                    }
                }
                try require(edgePixels.allSatisfy { $0 > 20 },
                    "Actual upright glyphs fill both outer edges: width=\(width), offset=\(offset), pixels=\(edgePixels)")
                if offset > Double(radius) {
                    let image = try renderer.image(geometry:shape,time:12.4,speed:90,scale:2,
                        matrixConfiguration:configuration,matrixPass:.aperture)
                    let pixels = bytes(image)
                    let hole = MatrixCodeFlow.horizon(geometry:shape,configuration:configuration)
                    let p = (Int(hole.y*2)*image.width+Int(hole.x*2))*4
                    try require(pixels[p+3] > 240 && pixels[p+1] < 10,
                        "The dark core renders at the detached sink's actual position")
                }
                emissionChecks.append(["width":width,"verticalOffset":offset,
                    "leftGlyphPixels":edgePixels[0],"rightGlyphPixels":edgePixels[1]])
            }
        }
        let apertureImage = try renderer.image(geometry: geometry,time: 12.4,speed: 90,
            scale: 2,matrixPass: .aperture)
        let aperturePixels = bytes(apertureImage)
        var microGlowPixels = 0,maximumMicroGlowAlpha = 0,unrelatedSurfacePixels = 0
        var illuminatedShadowPixels = 0
        for y in Int((geometry.notchHeight+5)*2)..<apertureImage.height {
            for x in 0..<apertureImage.width {
                let point = SIMD2((Float(x)+0.5)/2-hole.x,(Float(y)+0.5)/2-hole.y)
                let offset = (y*apertureImage.width+x)*4
                let radius = distance(point),alpha = Int(aperturePixels[offset+3])
                if radius > hole.z+1 && alpha > 0 {
                    microGlowPixels += 1
                    maximumMicroGlowAlpha = max(maximumMicroGlowAlpha,alpha)
                    if radius > hole.z+6 { unrelatedSurfacePixels += 1 }
                }
                if radius < hole.z-0.5 && aperturePixels[offset+1] > 10 {
                    try require(Int(aperturePixels[offset+1]) > Int(aperturePixels[offset])*2
                        && Int(aperturePixels[offset+1]) > Int(aperturePixels[offset+2])*2,
                        "The shadow emits a green tint rather than a grey or white surface")
                    illuminatedShadowPixels += 1
                }
            }
        }
        try require(microGlowPixels > 10 && maximumMicroGlowAlpha <= 20
            && illuminatedShadowPixels > 10 && unrelatedSurfacePixels == 0,
            "The requested microglow stays faint and local; it cannot become an opaque disk or backing")
        let backgroundImage = try renderer.image(geometry:geometry,time:12.4,speed:90,
            scale:2,matrixPass:.background)
        let backgroundPixels = bytes(backgroundImage)
        var independentRainPixels = 0
        for y in 0..<backgroundImage.height {
            for x in 0..<backgroundImage.width {
                let p = (y*backgroundImage.width+x)*4
                let offset = SIMD2((Float(x)+0.5)/2-hole.x,(Float(y)+0.5)/2-hole.y)
                if distance(offset) < hole.z-1 {
                    try require(backgroundPixels[p...p+3] == aperturePixels[p...p+3],
                        "The background passes behind the black hole and never paints across its dark core")
                }
                if Float(y)/2 > Float(geometry.notchHeight)+50 && backgroundPixels[p+3] > 4 {
                    independentRainPixels += 1
                }
            }
        }
        try require(independentRainPixels > 30,
            "Dim vertical background rain remains visible below the capture zone in actual GPU output")
        let orbitImage = try renderer.image(geometry:geometry,time:12.4,speed:90,scale:2,matrixPass:.orbiting)
        let orbitPixels = bytes(orbitImage)
        let laterOrbit = bytes(try renderer.image(geometry:geometry,time:13.4,speed:90,scale:2,matrixPass:.orbiting))
        var rotatingDiskPixels = 0
        for y in Int((geometry.notchHeight+3)*2)..<Int((geometry.notchHeight+24)*2) {
            for x in Int((hole.x-hole.z*3.2)*2)..<Int((hole.x+hole.z*3.2)*2) {
                let offset = (y*orbitImage.width+x)*4
                let change = (0..<3).reduce(0) { $0+abs(Int(orbitPixels[offset+$1])-Int(laterOrbit[offset+$1])) }
                if change > 12 { rotatingDiskPixels += 1 }
            }
        }
        try require(rotatingDiskPixels > 40,"Residual code moves in the actual GPU output")
        let loadResponse: [[String:Any]] = loadRates.indices.map { index in
            ["tokPerSecond":loadRates[index],"averageVisibleGlyphs":Double(glyphCounts[index])/Double(loadSamples),
             "averageOpacityWeightedGlyphs":density[index]/Float(loadSamples),"phasePerSecond":phaseSteps[index]*60]
        }
        var report: [String:Any] = ["passed":true,"input":"isolated synthetic tok/s; temporary preferences",
            "scope":"offscreen native Metal preview; no app packaging or installation",
            "exposedCoreDepth":exposedDepth,"completeCaptures":completeCaptures,
            "orbitArrivals":orbitArrivals,"terminalSamples":terminalSamples,
            "maximumTerminalExtentOverRadius":maximumTerminalExtent,
            "inwardMotionSamples":immediateAttractionSamples,"bundleSpreads":bundleSpreads,
            "nearInitialAngleDegrees":median(nearAngles)*180/Float.pi,
            "nearFarVerticalRunPoints":[median(nearBendDrops),median(farBendDrops)],
            "farInitialAngleDegrees":median(farInitialAngles)*180/Float.pi,
            "farLaterAngleDegrees":median(farLaterAngles)*180/Float.pi,
            "wallFrameRatio":Double(wallFrames)/Double(totalFrames),
            "visibleResidueFrameRatio":Double(visibleResidueFrames)/Double(totalFrames),
            "medianOrbitalResidence":median(residenceTimes),"orbitalMotionSamples":orbitalMotionSamples,
            "medianNearToFarSpeedRatio":median(speedRatios),"measuredGlyphTraces":speedRatios.count,
            "maximumFrameTravel":maximumTravel,"glyphWidthRange":[minimumWidth,maximumWidth],
            "peakVertices":peakVertices,"inlineUploadBytes":MemoryLayout<MatrixPulseVertex>.stride*MatrixCodeFlow.maximumInlineVertices,
            "loadResponse":loadResponse,"stableLoadPaths":stableLoadPaths,
            "medianHighToLowTravelRatio":median(loadTravelRatios),"maximumLoadTransitionTravel":transitionTravel,
            "matrixParameters":["defaults":["blackHoleSize":NotchMatrixConfiguration.standard.blackHoleSize,
                    "gravity":NotchMatrixConfiguration.standard.gravity,"density":NotchMatrixConfiguration.standard.density,
                    "verticalOffset":NotchMatrixConfiguration.standard.verticalOffset],
                "ranges":NotchMatrixParameter.allCases.map { ["parameter":$0.rawValue,
                    "minimum":$0.range.lowerBound,"maximum":$0.range.upperBound] as [String:Any] },
                "visibleGlyphTotalsByDensity":parameterDensity,"densityLevels":densityLevels,
                "stableDensityGlyphs":stableDensityGlyphs,
                "weakStrongGravityLevels":gravityLevels,
                "weakStrongGravityAngleDegrees":gravityAngles.map { median($0)*180/Float.pi },
                "weakStrongGravityFallDepths":gravityMaximumDrops,
                "weakStrongGravityVerticalRunPoints":gravityTurnDrops.map { median($0) },
                "terminalSamples":parameterTerminalSamples,"peakVertices":parameterPeakVertices,
                "maximumTerminalExtentOverRadius":parameterMaximumTerminalExtent,
                "geometryCombinations":parameterSweep,"pixelChecks":parameterPixelChecks],
            "captureRouting":["inwardGatherSamples":inwardGatherSamples,
                "leftRearEntrySamples":leftRearEntrySamples,"rightFrontEntrySamples":rightFrontEntrySamples],
            "appearanceContrast":["whiteBackground":themeContrast,"preservedCorePixels":preservedCorePixels,
                "macOSAppearanceMapping":true,"flameUnchanged":true],
            "rotatingDiskPixels":rotatingDiskPixels,
            "microGlow":["pixelsOutsideShadow":microGlowPixels,
                "maximumOuterAlphaByte":maximumMicroGlowAlpha,"illuminatedShadowPixels":illuminatedShadowPixels,
                "unrelatedSurfacePixels":unrelatedSurfacePixels],
            "edgeEmissionAndDetachedCore":emissionChecks,
            "legacyConfigurationMigration":true,
            "backgroundRain":["visibleShareAtSelectedParameters":backgroundShare,
                "unchangedByHoleControls":independentBackgroundSamples,
                "verticalMotionSamples":backgroundMotionSamples,"fadeExitSamples":backgroundExitSamples,
                "pixelsBelowCapture":independentRainPixels,"compositedBehindForeground":true],
            "changedGPUBytes":changedBytes,"samples":imageChecks,"nativeLifecycleRun":false]
        // Native overlay lifecycle checks are opt-in; design iterations stay offscreen by default.
        if CommandLine.arguments.contains("--native") {
            let controller = NotchFlameController(settings: settings)
            defer { controller.shutdown() }
            controller.update(speed: 90)
            pump(1)
            guard let panel = NSApp.windows.first(where: { $0.title == "EmberCat · Matrix 代码雨" }),
                  let view = panel.contentView as? NotchFlameMetalView,
                  let profile = NotchDisplayProfile.current() else {
                try require(false, "Create the native Matrix overlay; enabled=\(settings.isEnabled), effect=\(settings.effect), "
                    + "screens=\(NotchScreenSnapshot.connected()), windows=\(NSApp.windows.map(\.title))")
                return
            }
            try require(panel.isVisible && panel.ignoresMouseEvents && !panel.canBecomeKey,
                "The live effect remains noninteractive")
            try require(panel.frame == profile.panelFrame(for: .matrix), "Matrix uses its own taller display geometry")
            try require(view.matrixColorSchemeOverride == nil,
                "The real desktop overlay inherits macOS appearance without a preview override")
            let inheritedAppearance = panel.appearance
            for scheme in NotchMatrixColorScheme.allCases {
                panel.appearance = NSAppearance(named:scheme == .dark ? .darkAqua : .aqua)
                pump(0.2)
                try require(view.matrixColorScheme == scheme,
                    "The live overlay follows native light and dark appearance changes")
            }
            panel.appearance = inheritedAppearance
            let frames = view.renderedFrameCount
            pump(0.3)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                try require(view.renderedFrameCount > frames, "The Matrix overlay submits fresh frames")
            }
            settings.effect = .flame
            pump(0.2)
            try require(panel.contentView === view && view.effect == .flame && panel.frame == profile.panelFrame,
                "Switch to flame without creating a second surface")
            settings.effect = .matrix
            pump(0.2)
            try require(view.effect == .matrix && panel.frame == profile.panelFrame(for: .matrix),
                "Switch back to Matrix and restore its extent")
            controller.update(speed: 0)
            pump(4.3)
            try require(!panel.isVisible && !view.isRendering, "Zero output fades out and stops Matrix rendering")
            controller.update(speed: 90)
            pump(0.3)
            try require(panel.isVisible, "Fresh output resumes Matrix")
            settings.isEnabled = false
            try require(!panel.isVisible && !view.isRendering, "The off switch stops Matrix immediately")
            settings.isEnabled = true
            pump(0.2)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            try require(!panel.isVisible && !view.isRendering, "Display sleep stops Matrix")
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            pump(0.1)
            try require(!panel.isVisible, "Wake does not replay an old speed")
            controller.update(speed: 90)
            pump(0.3)
            try require(panel.isVisible, "New output resumes after wake")

            controller.shutdown()
            try require(!view.isRendering && !panel.isVisible,"Shutdown releases the Matrix surface")
            report["nativeLifecycleRun"] = true
        }
        if let index = CommandLine.arguments.firstIndex(of: "--report"),CommandLine.arguments.count > index+1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index+1])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: url)
        }
        print("PASS: continuous code wall, adjustable size/gravity/density, complete parameter-range capture, four-stream convergence, rotating residue, tok/s response, GPU transparency and flame independence")
        print("Captures: \(completeCaptures); median near/far speed: \(median(speedRatios)); vertex peak: \(peakVertices)")
    }
}
