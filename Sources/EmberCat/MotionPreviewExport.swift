import AppKit

/// Offline review frames from the exact director and renderer used by the app.
@MainActor
func exportMotionPreview(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // Every mode gets enough time after settling for at least two full loops.
    // Keep the final jumps in this same continuous recording so no transition
    // or confirmation delay is hidden by editing.
    let schedule: [(Double, Double)] = [(0,3),(3,6),(12,6),(24,6),(36,8),
        (50,8),(70,8),(91,8),(125,8),(185,8),(0,10),
        (3,6),(70,8),(3,8),(185,8),(0,10)]
    let delta = 1.0 / 30.0
    var director = MotionDirector()
    var trace: [[String: Any]] = []
    var tick = 0
    for (speed, duration) in schedule {
        director.setSpeed(speed)
        for _ in 0..<Int((duration / delta).rounded()) {
            director.advance(by: delta)
            let filename = String(format: "frame-%04d.png", tick)
            try writePreviewImage(style: .makima, director: director,
                to: folder.appendingPathComponent(filename))
            var row: [String: Any] = ["file": filename, "time": Double(tick)*delta,
                "rawSpeed": director.rawSpeed, "filteredSpeed": director.filteredSpeed,
                "mode": director.mode.rawValue,
                "phase": director.clock.phase(cycleDuration: director.mode.cycleDuration),
                "catPhase": director.cat.phase, "title": director.title]
            if let transition = director.transition {
                row["transition"] = ["from": transition.from.rawValue, "to": transition.to.rawValue,
                    "progress": transition.progress, "sourcePhase": transition.sourcePhase]
            }
            trace.append(row)
            tick += 1
        }
    }
    let data = try JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys])
    try data.write(to: folder.appendingPathComponent("trace.json"))
    var start = 0.0
    let chapters: [[String: Any]] = schedule.map { speed, duration in
        defer { start += duration }
        return ["start": start, "duration": duration, "speed": speed,
            "target": SpeedTier.forSpeed(speed).rawValue]
    }
    let manifest: [String: Any] = ["fps": 30, "duration": Double(tick)*delta,
        "chapters": chapters, "allModes": SpeedTier.allCases.map(\.rawValue)]
    try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        .write(to: folder.appendingPathComponent("manifest.json"))
    print("Exported \(tick) production-rendered frames and trace to \(folder.path)")
    try exportCadencePreview(to: folder.appendingPathComponent("cadence", isDirectory: true))
}

@MainActor
private func writePreviewImage(style: PetStyle, director: MotionDirector, to file: URL) throws {
    guard let image = SpriteLibrary.shared.image(for: style, director: director),
          let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep })
            .first(where: { $0.pixelsWide == 72 }),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "EmberCat.Preview", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not render \(file.lastPathComponent)"])
    }
    try data.write(to: file)
}

/// Paired inputs share the same starting clock; their production-rendered
/// Makima frames must remain synchronized within each art-directed action.
@MainActor
private func exportCadencePreview(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let speeds: [Double] = [0, 3, 12, 24, 36, 50, 67.6, 91, 125, 185]
    let scenes = SpeedTier.allCases.map { (PetStyle.makima, $0) }
    var report: [[String: Any]] = []
    for (style, mode) in scenes {
        let name = mode.rawValue
        let sceneFolder = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: sceneFolder, withIntermediateDirectories: true)
        var low = MotionDirector()
        low.setSpeed(speeds[mode.rank])
        for _ in 0..<360 { low.advance(by: 1.0/30.0) }
        var high = low
        let lower = SpeedTier.fallThreshold(at: mode.rank)
        let upper = mode == .jetpack ? 1000 : SpeedTier.riseThreshold(at: mode.rank+1)
        low.setSpeed(mode == .idle ? 0 : lower+(upper-lower)*0.2)
        high.setSpeed(mode == .idle ? 0 : lower+(upper-lower)*0.8)
        for _ in 0..<120 {
            low.advance(by: 1.0/30.0)
            high.advance(by: 1.0/30.0)
        }
        var frames: [[String: Any]] = []
        for tick in 0..<288 {
            low.advance(by: 1.0/30.0)
            high.advance(by: 1.0/30.0)
            let lowFile = String(format: "low-%04d.png", tick)
            let highFile = String(format: "high-%04d.png", tick)
            try writePreviewImage(style: style, director: low, to: sceneFolder.appendingPathComponent(lowFile))
            try writePreviewImage(style: style, director: high, to: sceneFolder.appendingPathComponent(highFile))
            frames.append(["tick": tick, "low": lowFile, "high": highFile,
                "phase": low.clock.phase(cycleDuration: mode.cycleDuration)])
        }
        report.append(["name": name, "style": style.rawValue,
            "title": mode.compactTitle,
            "lowSpeed": low.rawSpeed, "highSpeed": high.rawSpeed,
            "cycleDuration": mode.cycleDuration, "frames": frames])
    }
    let data = try JSONSerialization.data(withJSONObject: ["fps": 30, "duration": 9.6, "scenes": report],
        options: [.sortedKeys])
    try data.write(to: folder.appendingPathComponent("trace.json"))
    print("Exported all 10 Makima modes at fixed playback cadence")
}

/// Cat demos use isolated synthetic rates and the exact production state/render path.
@MainActor
func exportCatPreview(to folder: URL) throws {
    let schedule: [(Double, Double)] = [(0,1.5), (8,5.5), (45,5), (140,6), (45,4), (8,4), (0,7)]
    let duration = schedule.reduce(0) { $0 + $1.1 }
    try exportCatScene(to: folder.appendingPathComponent("sequence"), duration: duration) { time in
        var end = 0.0
        for (speed, length) in schedule {
            end += length
            if time < end { return speed }
        }
        return 0
    }
    try exportCatScene(to: folder.appendingPathComponent("ramp"), duration: 36) { t in
        t < 2 ? 0 : t < 16 ? (t-2)/14*160 : t < 22 ? 160 : t < 30 ? (30-t)/8*160 : 0
    }
    for (gait, speed) in zip(CatGait.allCases, [0.0, 8, 45, 140]) {
        try exportCatScene(to: folder.appendingPathComponent("actions/\(gait.rawValue)"),
            duration: 4, warmUpSpeed: speed) { _ in speed }
    }
    print("Exported four cat actions, continuous acceleration and physical curl/unfurl to \(folder.path)")
}

@MainActor
private func exportCatScene(to folder: URL, duration: Double, warmUpSpeed: Double = 0,
    speedAtTime: (Double) -> Double) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var director = MotionDirector()
    director.setSpeed(warmUpSpeed)
    for _ in 0..<720 { director.advance(by: 1.0/60) }
    var trace: [[String: Any]] = []
    for tick in 0..<Int((duration * 60).rounded()) {
        let time = Double(tick) / 60
        director.setSpeed(speedAtTime(time))
        director.advance(by: 1.0/60)
        let filename = String(format: "frame-%04d.png", tick)
        try writePreviewImage(style: .cat, director: director, to: folder.appendingPathComponent(filename))
        let motion = director.cat
        var row: [String: Any] = ["file": filename, "time": time, "rawSpeed": director.rawSpeed,
            "filteredSpeed": motion.filteredSpeed, "gait": motion.gait.rawValue,
            "phase": motion.phase, "cyclesPerSecond": motion.cyclesPerSecond,
            "title": motion.title, "revolutions": motion.revolutions,
            "compactWidth": SpriteLibrary.shared.menuBarImage(for: .cat, director: director)?.size.width ?? 0]
        if let active = motion.transition {
            row["transition"] = ["kind": active.kind.rawValue, "from": active.from.rawValue,
                "to": active.to.rawValue, "progress": active.progress]
        }
        if let target = motion.aligningTo { row["aligningTo"] = target.rawValue }
        trace.append(row)
    }
    try JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys])
        .write(to: folder.appendingPathComponent("trace.json"))
    try JSONSerialization.data(withJSONObject: ["fps": 60, "duration": duration,
        "source": "production renderer with isolated synthetic speed input"], options: [.sortedKeys])
        .write(to: folder.appendingPathComponent("manifest.json"))
}
