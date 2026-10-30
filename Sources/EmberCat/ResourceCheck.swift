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
    for style in PetStyle.allCases {
        let modes = style == .cat ? [SpeedTier.idle, .run] : SpeedTier.allCases
        for mode in modes {
            validate(SpriteLibrary.shared.frames(for: style, mode: mode),
                expected: style.frameCount(for: mode),
                label: "\(style.rawValue)/\(mode.rawValue)")
            let trimmed = SpriteLibrary.shared.menuBarFrames(for: style, mode: mode)
            let label = "\(style.rawValue)/\(mode.rawValue)"
            validateMenuBar(SpriteLibrary.shared.frames(for: style, mode: mode), trimmed, label: label)
            menuBarWidths[label] = trimmed.first?.size.width
            if style == .makima && (trimmed.first?.size.width ?? 36) >= 36 {
                failures.append("\(label): transparent side margins were not removed")
            }
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
            for _ in 0..<360 {
                director.advance(by: 1.0/30.0)
                guard let active = director.transition, active.progress >= 0.5 else { continue }
                if active.from != from || active.to != to {
                    failures.append("\(label): unexpected intermediate tier")
                }
                if let image = SpriteLibrary.shared.image(for: .makima, director: director) {
                    validate([image], expected: 1, label: "\(label) live composition")
                    if let trimmed = SpriteLibrary.shared.menuBarImage(for: .makima, director: director) {
                        validateMenuBar([image], [trimmed], label: "\(label) compact composition")
                    } else { failures.append("\(label): missing compact transition") }
                    renderedPairs += 1
                } else { failures.append("\(label): renderer produced no image") }
                rendered = true
                break
            }
            if !rendered { failures.append("\(label): no live transition reached") }
        }
    }
    // Compare production-selected images, not just mathematical clock phases.
    for style in PetStyle.allCases {
        let modes = style == .cat ? [SpeedTier.walk] : SpeedTier.allCases.filter { $0 != .idle }
        for mode in modes {
            var low = MotionDirector()
            low.setSpeed(speeds[mode.rank])
            for _ in 0..<360 { low.advance(by: 1.0/30.0) }
            var high = low
            let lower = SpeedTier.fallThreshold(at: mode.rank)
            let upper = mode == .jetpack ? 1000 : SpeedTier.riseThreshold(at: mode.rank+1)
            low.setSpeed(style == .cat ? 3 : lower+(upper-lower)*0.2)
            high.setSpeed(style == .cat ? 1000 : lower+(upper-lower)*0.8)
            for _ in 0..<600 {
                low.advance(by: 1.0/30.0)
                high.advance(by: 1.0/30.0)
                if style == .makima && (low.mode != mode || high.mode != mode
                    || low.transition != nil || high.transition != nil) {
                    failures.append("\(style)/\(mode): unexpected tier change in cadence check")
                    break
                }
                guard let a = SpriteLibrary.shared.image(for: style, director: low),
                      let b = SpriteLibrary.shared.image(for: style, director: high), a === b else {
                    failures.append("\(style)/\(mode): token rate changed the rendered frame")
                    break
                }
                cadenceComparisons += 1
            }
        }
    }
    let report: [String: Any] = ["pass": failures.isEmpty, "framesChecked": checked,
        "transitionKeyframes": transitions, "directedPairs": directedPairs, "renderedPairs": renderedPairs,
        "cadenceComparisons": cadenceComparisons,
        "menuBarFramesChecked": menuBarFramesChecked, "menuBarWidths": menuBarWidths,
        "template": true, "logicalSize": [36,20], "scales": [1,2], "failures": failures]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text) }
    return failures.isEmpty
}
