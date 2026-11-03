import Foundation

/// Travel and paws share the existing cat cadence, with continuous acceleration.
struct DockOrbitMotion {
    private(set) var director = MotionDirector()
    private(set) var phase = 0.0
    private(set) var velocity = 0.0
    private(set) var distance = 0.0
    private(set) var trail = DockPawTrail()

    var isResting: Bool { !director.cat.needsTicks && velocity == 0 }
    var needsTicks: Bool { !isResting || trail.needsTicks }

    mutating func setSpeed(_ speed: Double) { director.setSpeed(speed) }

    mutating func pause() {
        let speed = director.cat.rawSpeed
        director = MotionDirector()
        director.setSpeed(speed)
        velocity = 0
        trail.clear()
    }

    mutating func clearTrail() { trail.clear() }

    /// The next run starts at the same Dock contact as the seated artwork.
    mutating func park(at phase: Double) {
        guard phase.isFinite else { return }
        self.phase = phase - floor(phase)
    }

    mutating func advance(by elapsed: TimeInterval, pathLength: Double) {
        guard elapsed.isFinite, elapsed > 0, pathLength.isFinite, pathLength > 0 else { return }
        var remaining = min(0.25, elapsed)
        while remaining > 1e-10 {
            let delta = min(1.0 / 120.0, remaining)
            let previousCat = director.cat
            director.advance(by: delta)
            let cat = director.cat
            let stride = 62 + 54 * cat.filteredSpeed / (cat.filteredSpeed + 70)
            let desired = cat.gait == .idle && cat.transition == nil ? 0 : cat.cyclesPerSecond * stride
            let before = velocity
            let change = (desired - before) * (1 - exp(-delta / 0.28))
            velocity += min(220 * delta, max(-180 * delta, change))
            if desired == 0, velocity < 0.02 { velocity = 0 }
            let travel = (before + velocity) * delta / 2
            trail.advance(by: delta, from: previousCat, to: cat,
                          orbitPhase: phase, travel: travel, pathLength: pathLength)
            distance += travel
            phase = (phase + travel / pathLength).truncatingRemainder(dividingBy: 1)
            remaining -= delta
        }
    }
}
