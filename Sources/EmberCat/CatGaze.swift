import Foundation
import CoreGraphics

/// A shared, bounded look direction for both eyes. Coordinates are AppKit's (Y up).
struct CatGaze {
    private(set) var direction = CGVector.zero

    static func target(for mouse: CGPoint, in rect: CGRect) -> CGVector {
        guard rect.width > 0, rect.height > 0,
              mouse.x.isFinite, mouse.y.isFinite else { return .zero }
        // Midpoint of the eyes in the supplied portrait, rather than the cat's belly.
        let origin = CGPoint(x: rect.minX + rect.width * 0.57, y: rect.minY + rect.height * 0.63)
        let dx = (mouse.x - origin.x) / (rect.width * 0.45)
        let dy = (mouse.y - origin.y) / (rect.height * 0.45)
        let distance = hypot(dx, dy)
        let divisor = max(1, distance)
        return CGVector(dx: dx / divisor, dy: dy / divisor)
    }

    mutating func advance(toward target: CGVector, by elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0, target.dx.isFinite, target.dy.isFinite else { return }
        let amount = 1 - exp(-min(elapsed, 0.1) / 0.085)
        direction.dx += (target.dx - direction.dx) * amount
        direction.dy += (target.dy - direction.dy) * amount
    }

    mutating func reset() { direction = .zero }
}
