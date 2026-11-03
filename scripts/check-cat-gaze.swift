import Foundation
import CoreGraphics

@main
struct CatGazeCheck {
    static func close(_ actual: Double, _ expected: Double) {
        precondition(abs(actual - expected) < 1e-10, "Expected \(expected), received \(actual)")
    }

    static func main() {
        boundedDirections()
        scaledCoordinates()
        smoothTiming()
        neutralState()
        print("PASS: 4 gaze checks using the production model")
    }

    static func boundedDirections() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 320)
        let right = CatGaze.target(for: CGPoint(x: 100_000, y: 201.6), in: rect)
        let left = CatGaze.target(for: CGPoint(x: -100_000, y: 201.6), in: rect)
        let up = CatGaze.target(for: CGPoint(x: 182.4, y: 100_000), in: rect)
        let down = CatGaze.target(for: CGPoint(x: 182.4, y: -100_000), in: rect)
        close(right.dx, 1)
        close(left.dx, -1)
        close(up.dy, 1)
        close(down.dy, -1)
        let diagonal = CatGaze.target(for: CGPoint(x: -100_000, y: 100_000), in: rect)
        precondition(hypot(diagonal.dx, diagonal.dy) <= 1.000000001)
        precondition(diagonal.dx < 0 && diagonal.dy > 0)
        print("PASS: up/down/left/right and distant diagonal targets stay inside the gaze limit")
    }

    static func scaledCoordinates() {
        let dock = CatGaze.target(for: CGPoint(x: 56, y: 16), in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let preview = CatGaze.target(for: CGPoint(x: 280 - 900, y: 80 + 300),
            in: CGRect(x: -900, y: 300, width: 320, height: 320))
        close(dock.dx, preview.dx)
        close(dock.dy, preview.dy)
        print("PASS: Dock and enlarged artwork agree at different scales and screen origins")
    }

    static func smoothTiming() {
        let target = CGVector(dx: 0.8, dy: -0.6)
        var sixty = CatGaze()
        var oneTwenty = CatGaze()
        for _ in 0..<30 { sixty.advance(toward: target, by: 1.0 / 60) }
        for _ in 0..<60 { oneTwenty.advance(toward: target, by: 1.0 / 120) }
        close(sixty.direction.dx, oneTwenty.direction.dx)
        close(sixty.direction.dy, oneTwenty.direction.dy)
        precondition(sixty.direction.dx > 0.79 && sixty.direction.dx < target.dx)
        let previous = sixty.direction
        sixty.advance(toward: CGVector(dx: -1, dy: 0), by: 1.0 / 60)
        precondition(sixty.direction.dx < previous.dx && sixty.direction.dx > 0)
        print("PASS: 60/120 Hz converge equally and reversing direction does not snap")
    }

    static func neutralState() {
        precondition(CatGaze.target(for: CGPoint(x: 4, y: 4), in: .zero) == .zero)
        precondition(CatGaze.target(for: CGPoint(x: CGFloat.nan, y: 4),
            in: CGRect(x: 0, y: 0, width: 40, height: 40)) == .zero)
        var gaze = CatGaze()
        gaze.advance(toward: CGVector(dx: 1, dy: 1), by: .nan)
        precondition(gaze.direction == .zero)
        gaze.advance(toward: CGVector(dx: 1, dy: 0), by: 0.1)
        gaze.reset()
        precondition(gaze.direction == .zero)
        print("PASS: missing geometry, invalid input and resetting preserve the neutral pose")
    }
}
