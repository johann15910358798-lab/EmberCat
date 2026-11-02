import Foundation

@main
struct Check {
    static func main() {
        playbackUsesWallTime()
        idlePreservesPhase()
        fixedPeriodsAndFrameProgress()
        invalidInputsAndEmptyFrames()
        print("PASS: 4 fixed-cadence AnimationClock checks (actual application source)")
    }

    private static func near(_ actual: Double, _ expected: Double) {
        precondition(abs(actual - expected) <= 0.000_001, "Expected \(expected), got \(actual)")
    }

    private static func playbackUsesWallTime() {
        var clock = AnimationClock()
        clock.setPlaying(true)
        clock.advance(by: 0.4)
        near(clock.elapsed, 0.4)
        near(clock.phase, 1.0/6.0)
        clock.advance(by: 0.4)
        near(clock.phase, 1.0/3.0)
        print("PASS: fixed 2.4 s clock advances solely by elapsed wall time")
    }

    private static func idlePreservesPhase() {
        var clock = AnimationClock()
        clock.setPlaying(true)
        clock.advance(by: 0.2)
        let phase = clock.phase
        clock.setPlaying(false)
        clock.advance(by: 300)
        precondition(clock.isIdle && clock.phase == phase)
        clock.setPlaying(true)
        precondition(!clock.isIdle && clock.phase == phase)
        print("PASS: idle pause and resume preserve the current pose")
    }

    private static func fixedPeriodsAndFrameProgress() {
        var clock = AnimationClock()
        clock.setPlaying(true)
        clock.advance(by: 0.4)
        precondition(clock.frameIndex(frameCount: 72) == 12)
        precondition(clock.frameIndex(frameCount: 8, cycleDuration: 0.8) == 4)
        near(clock.phase(cycleDuration: 1.2), 1.0/3.0)
        clock.advance(by: 1.4)
        near(clock.phase, 0.75)
        precondition(clock.frameIndex(frameCount: 72) == 54)
        var sampled = AnimationClock()
        sampled.setPlaying(true)
        for tick in 0..<(72 * 20) {
            precondition(sampled.frameIndex(frameCount: 72) == tick % 72,
                "Uneven frame hold at 30 Hz tick \(tick)")
            sampled.advance(by: 1.0 / 30.0)
        }
        var boundary = AnimationClock()
        boundary.setPlaying(true)
        boundary.advance(by: 2.4 / 72 - 1e-7)
        precondition(boundary.frameIndex(frameCount: 72) == 0)
        boundary.advance(by: 1e-7)
        precondition(boundary.frameIndex(frameCount: 72) == 1)
        print("PASS: per-action periods, 72-frame progress and seamless wrapping")
    }

    private static func invalidInputsAndEmptyFrames() {
        var clock = AnimationClock()
        clock.setPlaying(true)
        for elapsed: Double in [-1, 0, .nan, .infinity, -.infinity] {
            clock.advance(by: elapsed)
            precondition(clock.elapsed == 0)
        }
        for period: Double in [-1, 0, .nan, .infinity] {
            precondition(clock.phase(cycleDuration: period) == 0)
        }
        precondition(clock.frameIndex(frameCount: 0) == 0)
        precondition(clock.frameIndex(frameCount: 1) == 0)
        print("PASS: invalid times, invalid periods and degenerate frame counts")
    }
}
