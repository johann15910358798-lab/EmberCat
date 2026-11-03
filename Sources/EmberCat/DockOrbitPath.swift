import Foundation

/// A clockwise, arc-length-parameterized loop in global AppKit coordinates.
struct DockOrbitPath {
    struct Pose {
        let center: CGPoint
        let angle: Double
    }

    static let spriteSize = CGSize(width: 54, height: 30)
    // The source cat's shared ground line is y = 19 on its 36 × 20 canvas.
    // Keep the paws on the contour instead of aligning the transparent canvas.
    static let groundInset: CGFloat = 1.5
    static let groundOffset = spriteSize.height / 2 - groundInset
    static let idleSize: CGFloat = 64
    // CatIdleBase.png's feet end at row 887 on its 1024px transparent canvas.
    static let idleGroundInset = idleSize * 137 / 1024
    let dockFrame: CGRect
    let dockRadius: CGFloat
    let bounds: CGRect
    let radius: CGFloat
    let screenFrame: CGRect
    let length: Double

    init?(dockFrame: CGRect, screenFrame: CGRect) {
        guard Self.isFinite(dockFrame), Self.isFinite(screenFrame),
              dockFrame.width >= 24, dockFrame.height >= 24,
              screenFrame.width >= 200, screenFrame.height >= 200,
              screenFrame.intersects(dockFrame) else { return nil }
        let dockRadius = min(32, min(dockFrame.width, dockFrame.height) * 0.4)
        // The body follows a parallel curve outside the foot contour. Expanding
        // both the bounds and radius by the same amount preserves corner contact.
        // Screen clipping belongs to the window; it must never move this route
        // inward through the Dock's icons.
        let bounds = dockFrame.insetBy(dx: -Self.groundOffset, dy: -Self.groundOffset)
        let radius = dockRadius + Self.groundOffset
        self.dockFrame = dockFrame
        self.dockRadius = dockRadius
        self.bounds = bounds
        self.radius = radius
        self.screenFrame = screenFrame
        length = 2 * (bounds.width + bounds.height - 4 * radius) + 2 * .pi * radius
    }

    var canvasFrame: CGRect {
        bounds.insetBy(dx: -36, dy: -36).union(idleFrame).intersection(screenFrame).integral
    }

    var idleFrame: CGRect {
        CGRect(x: dockFrame.midX - Self.idleSize / 2,
               y: dockFrame.maxY - Self.idleGroundInset,
               width: Self.idleSize, height: Self.idleSize)
    }

    var idlePhase: Double {
        (bounds.width - 2 * radius) / (2 * length)
    }

    func pose(at phase: Double) -> Pose {
        let phase = phase.isFinite ? phase - floor(phase) : 0
        var distance = phase * length
        let horizontal = bounds.width - 2 * radius
        let vertical = bounds.height - 2 * radius
        let arc = .pi * radius / 2
        let lengths = [horizontal, arc, vertical, arc, horizontal, arc, vertical, arc]
        for (segment, count) in lengths.enumerated() {
            if distance <= count || segment == 7 {
                let d = min(count, max(0, distance))
                switch segment {
                case 0: return Pose(center: CGPoint(x: bounds.minX + radius + d, y: bounds.maxY), angle: 0)
                case 2: return Pose(center: CGPoint(x: bounds.maxX, y: bounds.maxY - radius - d), angle: -.pi / 2)
                case 4: return Pose(center: CGPoint(x: bounds.maxX - radius - d, y: bounds.minY), angle: -.pi)
                case 6: return Pose(center: CGPoint(x: bounds.minX, y: bounds.minY + radius + d), angle: -.pi * 1.5)
                default:
                    let corner = segment / 2
                    let centers = [
                        CGPoint(x: bounds.maxX - radius, y: bounds.maxY - radius),
                        CGPoint(x: bounds.maxX - radius, y: bounds.minY + radius),
                        CGPoint(x: bounds.minX + radius, y: bounds.minY + radius),
                        CGPoint(x: bounds.minX + radius, y: bounds.maxY - radius),
                    ]
                    let theta = .pi / 2 - Double(corner) * .pi / 2 - d / radius
                    return Pose(center: CGPoint(x: centers[corner].x + radius * cos(theta),
                                                y: centers[corner].y + radius * sin(theta)),
                                angle: theta - .pi / 2)
                }
            }
            distance -= count
        }
        preconditionFailure("The closed path always has eight segments")
    }

    /// Quartz and AX use the primary display's upper-left origin, even on other screens.
    static func appKitFrame(from screenFrame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX, y: primaryTop - screenFrame.maxY,
               width: screenFrame.width, height: screenFrame.height)
    }

    static func isFinite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
            && !rect.isNull && !rect.isInfinite
    }
}
