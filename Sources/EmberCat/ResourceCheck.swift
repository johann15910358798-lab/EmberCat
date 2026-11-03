import AgentSpeedCore
import AppKit

/// Loads the same steady and transition resources as the running app.
@MainActor
func checkMenuBarResources() -> Bool {
    var checked = 0
    var transitions = 0
    var directedPairs = 0
    var renderedPairs = 0
    var cadenceComparisons = 0
    var menuBarFramesChecked = 0
    var menuBarWidths: [String: CGFloat] = [:]
    var failures: [String] = []
    let portrait = AppResources.dockIdleCat
    let portraitRep = portrait?.representations.compactMap { $0 as? NSBitmapImageRep }.first
    let dockIdleArtworkChecked = portrait?.isValid == true && portrait?.isTemplate == false
        && portraitRep?.pixelsWide == 256 && portraitRep?.pixelsHigh == 256
        && portraitRep?.hasAlpha == true
    if !dockIdleArtworkChecked { failures.append("DockIdleCat: missing or invalid transparent artwork") }
    let portraitLayers = DockIdleCatArtwork.shared
    let dockIdleEyeLayersChecked = portraitLayers.isComplete
        && portraitLayers.eyeMask?.width == 1024 && portraitLayers.eyeMask?.height == 1024
        && ([portraitLayers.base].compactMap { $0 } + portraitLayers.pupils).allSatisfy { image in
            !image.isTemplate && image.representations.contains { rep in
                rep.pixelsWide == 1024 && rep.pixelsHigh == 1024
            }
        }
    if !dockIdleEyeLayersChecked { failures.append("DockIdleCat: missing or invalid gaze layers") }
    var sourceIconsChecked: [String] = []
    var sourceIconFallbacksChecked = 0
    var unreadableSourceIconFallbackChecked = false
    var previewDetailFrames = 0
    var transitionDetailFrames = 0
    var liveTransitionSamples = 0
    let detailModes: [(PetStyle, SpeedTier)] = [(.cat, .walk)]
        + SpeedTier.allCases.map { (.makima, $0) }
    for (style, mode) in detailModes {
        let frames = SpriteLibrary.shared.previewFrames(for: style, mode: mode)
        if frames.count != mode.frameCount { failures.append("PetPreview/\(style)/\(mode): missing detail images") }
        for image in frames {
            let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
            guard image.isTemplate, image.size == SpriteLibrary.imageSize, reps.count == 1,
                  reps[0].pixelsWide == 576, reps[0].pixelsHigh == 320, reps[0].hasAlpha else {
                failures.append("PetPreview/\(style): invalid high-resolution detail image")
                continue
            }
            previewDetailFrames += 1
        }
    }
    let missingIcons = SourceIconLibrary(resourceDirectory: nil, usesInstalledApplications: false)
    // Check bundled logos even when the corresponding desktop app is installed.
    // This exercises the same resource lookup in SwiftPM and packaged releases.
    for source in SourceKind.allCases {
        guard let image = SourceIconLibrary.shared.bundledImage(for: source),
              image.isValid, image.size.width > 0, image.size.height > 0 else {
            failures.append("SourceIcons/\(source.rawValue): missing or unreadable logo")
            continue
        }
        sourceIconsChecked.append(source.rawValue)
        if !SourceIconLibrary.shared.image(for: source).isValid {
            failures.append("SourceIcons/\(source.rawValue): invalid displayed logo")
        }
        if missingIcons.image(for: source).isValid {
            sourceIconFallbacksChecked += 1
        } else {
            failures.append("SourceIcons/\(source.rawValue): missing-resource fallback failed")
        }
    }
    let unreadableIcons = FileManager.default.temporaryDirectory.appendingPathComponent("embercat-icons-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: unreadableIcons, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unreadableIcons) }
        try Data("not an image".utf8).write(to: unreadableIcons.appendingPathComponent("claudeCode.png"))
        let library = SourceIconLibrary(resourceDirectory: unreadableIcons, usesInstalledApplications: false)
        unreadableSourceIconFallbackChecked = library.bundledImage(for: .claudeCode) == nil
            && library.image(for: .claudeCode).isValid
        if !unreadableSourceIconFallbackChecked { failures.append("SourceIcons: unreadable-logo fallback failed") }
    } catch {
        failures.append("SourceIcons: could not prepare unreadable-logo check: \(error.localizedDescription)")
    }
    func validate(_ frames: [NSImage], expected: Int, label: String) {
        if frames.count != expected { failures.append("\(label): \(frames.count)/\(expected) frames") }
        for frame in frames {
            checked += 1
            let reps = frame.representations.compactMap { $0 as? NSBitmapImageRep }
            if !frame.isTemplate || frame.size != SpriteLibrary.imageSize || reps.count != 2
                || reps.map(\.pixelsWide).sorted() != [36, 72]
                || reps.map(\.pixelsHigh).sorted() != [20, 40] || !reps.allSatisfy(\.hasAlpha) {
                failures.append("\(label): invalid template, size or Retina representation")
            }
        }
    }
    func alphaSum(_ rep: NSBitmapImageRep) -> Int {
        var total = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                total += Int(((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded())
            }
        }
        return total
    }
    func validateMenuBar(_ originals: [NSImage], _ trimmed: [NSImage], label: String) {
        guard originals.count == trimmed.count, let first = trimmed.first else {
            failures.append("\(label): missing compact frames")
            return
        }
        for (original, image) in zip(originals, trimmed) {
            menuBarFramesChecked += 1
            let sourceReps = original.representations.compactMap { $0 as? NSBitmapImageRep }
                .sorted { $0.pixelsHigh < $1.pixelsHigh }
            let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
                .sorted { $0.pixelsHigh < $1.pixelsHigh }
            guard image.isTemplate, image.size.height == 20,
                  image.size.width > 0, image.size.width <= 36,
                  image.size == first.size, reps.count == 2, sourceReps.count == 2 else {
                failures.append("\(label): invalid compact canvas or unstable cycle width")
                continue
            }
            for (source, rep) in zip(sourceReps, reps) {
                let density = rep.pixelsHigh / 20
                if rep.pixelsHigh != source.pixelsHigh || rep.pixelsWide != Int(image.size.width) * density
                    || rep.size != image.size || !rep.hasAlpha || alphaSum(source) != alphaSum(rep) {
                    failures.append("\(label): trimming clipped artwork or lost a Retina representation")
                }
            }
        }
    }
    for gait in CatGait.allCases {
        let label = "Cat/\(gait.rawValue)"
        let frames = SpriteLibrary.shared.catFrames(for: gait)
        let trimmed = SpriteLibrary.shared.catMenuBarFrames(for: gait)
        validate(frames, expected: gait.frameCount, label: label)
        validateMenuBar(frames, trimmed, label: label)
        menuBarWidths[label] = trimmed.first?.size.width
        if (trimmed.first?.size.width ?? 36) >= 36 {
            failures.append("\(label): transparent side margins were not removed")
        }
    }
    let curl = SpriteLibrary.shared.catCurlFrames()
    let trimmedCurl = SpriteLibrary.shared.catMenuBarCurlFrames()
    validate(curl, expected: CatMotion.curlFrameCount, label: "Cat/curl")
    if trimmedCurl.count != curl.count { failures.append("Cat/curl: missing compact frames") }
    for (index, pair) in zip(curl, trimmedCurl).enumerated() {
        validateMenuBar([pair.0], [pair.1], label: "Cat/curl/\(index)")
        if index > 0 && pair.1.size.width > trimmedCurl[index - 1].size.width {
            failures.append("Cat/curl: occupied width expands while curling")
        }
    }
    if trimmedCurl.first?.size != SpriteLibrary.shared.catMenuBarFrames(for: .run).first?.size
        || trimmedCurl.last?.size != SpriteLibrary.shared.catMenuBarFrames(for: .roll).first?.size {
        failures.append("Cat/curl: compact width jumps at a transition endpoint")
    }
    for mode in SpeedTier.allCases {
        let label = "Makima/\(mode.rawValue)"
        validate(SpriteLibrary.shared.frames(for: mode), expected: mode.frameCount, label: label)
        let trimmed = SpriteLibrary.shared.menuBarFrames(for: mode)
        validateMenuBar(SpriteLibrary.shared.frames(for: mode), trimmed, label: label)
        menuBarWidths[label] = trimmed.first?.size.width
        if (trimmed.first?.size.width ?? 36) >= 36 {
            failures.append("\(label): transparent side margins were not removed")
        }
    }
    for from in SpeedTier.allCases {
        for to in SpeedTier.allCases where from.rank < to.rank {
            let forward = SpriteLibrary.shared.transitionFrames(from: from, to: to)
            let backward = SpriteLibrary.shared.transitionFrames(from: to, to: from)
            validate(forward, expected: 4, label: "\(from.rawValue)→\(to.rawValue)")
            transitions += forward.count
            if backward.count != 4 || !zip(forward, backward.reversed()).allSatisfy({ $0 === $1 }) {
                failures.append("\(to.rawValue)→\(from.rawValue): invalid reverse transition")
            }
            let details = SpriteLibrary.shared.transitionFrames(from: from, to: to, detail: true)
            let reverseDetails = SpriteLibrary.shared.transitionFrames(from: to, to: from, detail: true)
            if details.count != 4 || !zip(details, reverseDetails.reversed()).allSatisfy({ $0 === $1 }) {
                failures.append("\(from)→\(to): missing or incorrect reverse detail transition")
            }
            for image in details {
                let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
                if reps.count != 1 || reps[0].pixelsWide != 576 || reps[0].pixelsHigh != 320 {
                    failures.append("\(from)→\(to): low-resolution transition key")
                }
                transitionDetailFrames += 1
            }
            directedPairs += 2
        }
    }
    let speeds: [Double] = [0, 3, 12, 24, 36, 50, 67.6, 91, 125, 185]
    for from in SpeedTier.allCases {
        for to in SpeedTier.allCases where from != to {
            let label = "\(from.rawValue)→\(to.rawValue)"
            var director = MotionDirector()
            director.setSpeed(speeds[from.rank])
            for _ in 0..<360 { director.advance(by: 1.0/30.0) }
            director.setSpeed(speeds[to.rank])
            var rendered = false
            for _ in 0..<720 {
                director.advance(by: 1.0/60.0)
                guard let active = director.transition else {
                    if rendered { break }
                    continue
                }
                if active.from != from || active.to != to {
                    failures.append("\(label): unexpected intermediate tier")
                }
                autoreleasepool {
                    if let image = SpriteLibrary.shared.image(for: .makima, director: director) {
                        validate([image], expected: 1, label: "\(label) live composition")
                        if let trimmed = SpriteLibrary.shared.menuBarImage(for: .makima, director: director) {
                            validateMenuBar([image], [trimmed], label: "\(label) compact composition")
                        } else { failures.append("\(label): missing compact transition") }
                        if !rendered { renderedPairs += 1 }
                    } else { failures.append("\(label): renderer produced no image") }
                    if let detail = SpriteLibrary.shared.previewImage(for: .makima, director: director),
                       let rep = detail.representations.first as? NSBitmapImageRep,
                       rep.pixelsWide == 576, rep.pixelsHigh == 320 {
                        liveTransitionSamples += 1
                    } else { failures.append("\(label): live transition fell back to a small image") }
                    rendered = true
                }
            }
            if !rendered { failures.append("\(label): no live transition reached") }
        }
    }
    // Compare production-selected images, not just mathematical clock phases.
    for mode in SpeedTier.allCases where mode != .idle {
            var low = MotionDirector()
            low.setSpeed(speeds[mode.rank])
            for _ in 0..<360 { low.advance(by: 1.0/30.0) }
            var high = low
            let lower = SpeedTier.fallThreshold(at: mode.rank)
            let upper = mode == .jetpack ? 1000 : SpeedTier.riseThreshold(at: mode.rank+1)
            low.setSpeed(lower+(upper-lower)*0.2)
            high.setSpeed(lower+(upper-lower)*0.8)
            for _ in 0..<600 {
                low.advance(by: 1.0/30.0)
                high.advance(by: 1.0/30.0)
                if low.mode != mode || high.mode != mode || low.transition != nil || high.transition != nil {
                    failures.append("Makima/\(mode): unexpected tier change in cadence check")
                    break
                }
                guard let a = SpriteLibrary.shared.image(for: .makima, director: low),
                      let b = SpriteLibrary.shared.image(for: .makima, director: high), a === b else {
                    failures.append("Makima/\(mode): token rate changed the rendered frame")
                    break
                }
                cadenceComparisons += 1
            }
    }
    // Verify production playback and detail preview both traverse the entire loop.
    // Storing 144 PNGs alone must not pass if selection repeats the old eight.
    var continuousFrameCounts: [String: Int] = [:]
    for mode in SpeedTier.allCases where mode != .idle {
        var motion = MotionDirector()
        motion.setSpeed(speeds[mode.rank])
        for _ in 0..<360 { motion.advance(by: 1.0/60) }
        let firstFrame = SpriteLibrary.shared.image(for: .makima, director: motion)
        var selected = Set<ObjectIdentifier>()
        var selectedDetails = Set<ObjectIdentifier>()
        for _ in 0..<mode.frameCount {
            if let image = SpriteLibrary.shared.image(for: .makima, director: motion) {
                selected.insert(ObjectIdentifier(image))
            }
            if let image = SpriteLibrary.shared.previewImage(for: .makima, director: motion) {
                selectedDetails.insert(ObjectIdentifier(image))
            }
            motion.advance(by: 1.0/60)
        }
        continuousFrameCounts[mode.rawValue] = selected.count
        if motion.mode != mode || motion.transition != nil || selected.count != mode.frameCount
            || selectedDetails.count != mode.frameCount
            || SpriteLibrary.shared.image(for: .makima, director: motion) !== firstFrame {
            failures.append("Makima/\(mode): expected \(mode.frameCount) distinct frames and a closed 60 Hz loop")
        }
    }
    var lowCat = MotionDirector()
    lowCat.setSpeed(3)
    var highCat = MotionDirector()
    highCat.setSpeed(14)
    for _ in 0..<720 { lowCat.advance(by: 1.0/60); highCat.advance(by: 1.0/60) }
    var differentCatFrames = 0
    for _ in 0..<240 {
        lowCat.advance(by: 1.0/60); highCat.advance(by: 1.0/60)
        guard let a = SpriteLibrary.shared.image(for: .cat, director: lowCat),
              let b = SpriteLibrary.shared.image(for: .cat, director: highCat) else {
            failures.append("Cat: missing cadence comparison image"); break
        }
        if a !== b { differentCatFrames += 1 }
    }
    if differentCatFrames < 200 || highCat.cat.cyclesPerSecond <= lowCat.cat.cyclesPerSecond {
        failures.append("Cat: higher token rate did not accelerate the same walking action")
    }
    var catDirector = MotionDirector()
    var catTransitions = Set<String>()
    for speed in [8.0, 45, 140, 0] {
        catDirector.setSpeed(speed)
        for _ in 0..<720 {
            catDirector.advance(by: 1.0/60)
            guard let active = catDirector.cat.transition, active.progress >= 0.5 else { continue }
            let key = "\(active.from.rawValue)-\(active.to.rawValue)"
            guard !catTransitions.contains(key) else { continue }
            catTransitions.insert(key)
            if let image = SpriteLibrary.shared.image(for: .cat, director: catDirector),
               let trimmed = SpriteLibrary.shared.menuBarImage(for: .cat, director: catDirector) {
                validate([image], expected: 1, label: "Cat/\(key) composition")
                validateMenuBar([image], [trimmed], label: "Cat/\(key) compact composition")
            } else { failures.append("Cat/\(key): missing live composition") }
        }
    }
    if catTransitions.count != 6 { failures.append("Cat: did not render all six gait transitions") }
    let report: [String: Any] = ["pass": failures.isEmpty, "framesChecked": checked,
        "transitionKeyframes": transitions, "directedPairs": directedPairs, "renderedPairs": renderedPairs,
        "cadenceComparisons": cadenceComparisons, "pixelfxDistinctFrames": continuousFrameCounts,
        "previewDetailFrames": previewDetailFrames,
        "transitionDetailFrames": transitionDetailFrames, "liveTransitionSamples": liveTransitionSamples,
        "catVariableCadenceFrames": differentCatFrames, "catTransitionsRendered": catTransitions.sorted(),
        "menuBarFramesChecked": menuBarFramesChecked, "menuBarWidths": menuBarWidths,
        "sourceIconsChecked": sourceIconsChecked,
        "dockIdleArtworkChecked": dockIdleArtworkChecked,
        "dockIdleEyeLayersChecked": dockIdleEyeLayersChecked,
        "sourceIconFallbacksChecked": sourceIconFallbacksChecked,
        "unreadableSourceIconFallbackChecked": unreadableSourceIconFallbackChecked,
        "template": true, "logicalSize": [36,20], "scales": [1,2], "failures": failures]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text) }
    return failures.isEmpty
}
