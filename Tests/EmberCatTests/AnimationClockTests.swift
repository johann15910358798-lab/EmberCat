import XCTest
@testable import EmberCat

final class AnimationClockTests: XCTestCase {
    func testPlaybackUsesWallTime() {
        var clock = AnimationClock()
        clock.setPlaying(true)
        clock.advance(by: 0.4)
        XCTAssertEqual(clock.elapsed, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(clock.phase, 1.0/6.0, accuracy: 0.000_001)
        clock.advance(by: 0.4)
        XCTAssertEqual(clock.phase, 1.0/3.0, accuracy: 0.000_001)
    }

    func testIdlePauseAndResumePreservePhase() {
        var clock = AnimationClock()
        clock.setPlaying(true)
        clock.advance(by: 0.2)
        let phase = clock.phase
        clock.setPlaying(false)
        clock.advance(by: 300)
        XCTAssertTrue(clock.isIdle)
        XCTAssertEqual(clock.phase, phase)
        clock.setPlaying(true)
        XCTAssertFalse(clock.isIdle)
        XCTAssertEqual(clock.phase, phase)
    }

    func testFixedPeriodsAndFrameProgress() {
        var clock = AnimationClock()
        clock.setPlaying(true)
        clock.advance(by: 0.4)
        XCTAssertEqual(clock.frameIndex(frameCount: 72), 12)
        XCTAssertEqual(clock.frameIndex(frameCount: 8, cycleDuration: 0.8), 4)
        XCTAssertEqual(clock.phase(cycleDuration: 1.2), 1.0/3.0, accuracy: 0.000_001)
        clock.advance(by: 1.4)
        XCTAssertEqual(clock.phase, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(clock.frameIndex(frameCount: 72), 54)
        var sampled = AnimationClock()
        sampled.setPlaying(true)
        for tick in 0..<(72 * 20) {
            XCTAssertEqual(sampled.frameIndex(frameCount: 72), tick % 72)
            sampled.advance(by: 1.0 / 30.0)
        }
        var boundary = AnimationClock()
        boundary.setPlaying(true)
        boundary.advance(by: 2.4 / 72 - 1e-7)
        XCTAssertEqual(boundary.frameIndex(frameCount: 72), 0)
        boundary.advance(by: 1e-7)
        XCTAssertEqual(boundary.frameIndex(frameCount: 72), 1)
    }

    func testInvalidInputsAndEmptyFrames() {
        var clock = AnimationClock()
        clock.setPlaying(true)
        for elapsed: Double in [-1, 0, .nan, .infinity, -.infinity] {
            clock.advance(by: elapsed)
            XCTAssertEqual(clock.elapsed, 0)
        }
        for period: Double in [-1, 0, .nan, .infinity] {
            XCTAssertEqual(clock.phase(cycleDuration: period), 0)
        }
        XCTAssertEqual(clock.frameIndex(frameCount: 0), 0)
        XCTAssertEqual(clock.frameIndex(frameCount: 1), 0)
    }
}
