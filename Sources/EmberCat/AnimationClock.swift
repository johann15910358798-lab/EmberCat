import Foundation

/// Fixed wall-clock playback for Makima's original hand-drawn action loops.
struct AnimationClock {
    static let defaultCycleDuration = 2.4
    private(set) var elapsed: TimeInterval = 0
    private(set) var isPlaying = false

    var isIdle: Bool { !isPlaying }
    var phase: Double { phase(cycleDuration: Self.defaultCycleDuration) }

    func phase(cycleDuration: TimeInterval) -> Double {
        guard cycleDuration.isFinite, cycleDuration > 0 else { return 0 }
        return (elapsed / cycleDuration).truncatingRemainder(dividingBy: 1)
    }

    mutating func setPlaying(_ value: Bool) {
        isPlaying = value
    }

    mutating func advance(by elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0, !isIdle else { return }
        self.elapsed += elapsed
    }

    func frameIndex(frameCount: Int, cycleDuration: TimeInterval = Self.defaultCycleDuration) -> Int {
        Self.frameIndex(phase: phase(cycleDuration: cycleDuration), frameCount: frameCount)
    }

    static func frameIndex(phase: Double, frameCount: Int) -> Int {
        guard frameCount > 1, phase.isFinite, phase >= 0 else { return 0 }
        // Elapsed-time accumulation can land a few ULPs below an exact frame
        // boundary. Snap sub-nanoframe error so regular ticks keep even holds.
        let position = phase.truncatingRemainder(dividingBy: 1) * Double(frameCount)
        return Int((position + 1e-9).rounded(.down)) % frameCount
    }
}
