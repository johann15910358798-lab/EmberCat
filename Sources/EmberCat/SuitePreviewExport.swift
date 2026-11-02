import AppKit

/// Focused transition clips from the production renderer, with simulated rates.
/// Confirmation waits are excluded from these clips and remain in the live UI.
@MainActor
func exportSuitePreview(to folder: URL) throws {
    let speeds: [Double] = [0, 3, 12, 24, 36, 50, 67.6, 91, 125, 185]
    let pairs: [(SpeedTier, SpeedTier)] = [(.idle, .walk), (.walk, .brisk), (.brisk, .run),
        (.run, .rollers), (.rollers, .board), (.board, .bicycle), (.bicycle, .motorcycle),
        (.motorcycle, .roadster), (.roadster, .jetpack), (.walk, .bicycle), (.bicycle, .walk),
        (.walk, .jetpack), (.jetpack, .idle)]
    var scenes: [[String: Any]] = []
    for (from, to) in pairs {
        let name = "\(from.rawValue)_\(to.rawValue)"
        let destination = folder.appendingPathComponent(name)
        for size in ["detail", "actual"] {
            try FileManager.default.createDirectory(at: destination.appendingPathComponent(size), withIntermediateDirectories: true)
        }
        var director = MotionDirector()
        director.setSpeed(speeds[from.rank])
        for _ in 0..<720 { director.advance(by: 1.0/60) }
        director.setSpeed(speeds[to.rank])
        var previous: [MotionDirector] = []
        var states: [MotionDirector] = []
        var started = false
        var trailing = 0
        for _ in 0..<720 {
            director.advance(by: 1.0/60)
            if director.transition != nil {
                if !started { states = previous; started = true }
                states.append(director)
            } else if started {
                states.append(director)
                trailing += 1
                if trailing >= 12 { break }
            } else {
                previous.append(director)
                if previous.count > 12 { previous.removeFirst() }
            }
        }
        guard started, trailing == 12, director.mode == to else {
            throw NSError(domain: "EmberCat.SuitePreview", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Transition did not finish: \(name)"])
        }
        var trace: [[String: Any]] = []
        for (index, state) in states.enumerated() {
            let filename = String(format: "frame-%03d.png", index + 1)
            try autoreleasepool {
                let images: [(String, NSImage?, Int)] = [
                    ("detail", SpriteLibrary.shared.previewImage(for: .makima, director: state), 576),
                    ("actual", SpriteLibrary.shared.image(for: .makima, director: state), 72)]
                for (size, image, width) in images {
                    guard let rep = image?.representations.compactMap({ $0 as? NSBitmapImageRep })
                        .first(where: { $0.pixelsWide == width }),
                        let data = rep.representation(using: .png, properties: [:]) else {
                        throw NSError(domain: "EmberCat.SuitePreview", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Missing \(size) representation: \(name)"])
                    }
                    try data.write(to: destination.appendingPathComponent(size).appendingPathComponent(filename))
                }
            }
            var row: [String: Any] = ["file": filename, "time": Double(index)/60,
                "mode": state.mode.rawValue, "title": state.title]
            if let active = state.transition { row["progress"] = active.progress }
            trace.append(row)
        }
        scenes.append(["name": name, "from": from.rawValue, "to": to.rawValue,
            "title": "\(from.compactTitle) → \(to.compactTitle)", "frames": trace])
    }
    try JSONSerialization.data(withJSONObject: ["fps": 60, "source": "production renderer; simulated speeds; transition excerpts",
        "scenes": scenes], options: [.sortedKeys])
        .write(to: folder.appendingPathComponent("manifest.json"))
    print("Exported \(scenes.count) full-resolution production transition clips")
}
