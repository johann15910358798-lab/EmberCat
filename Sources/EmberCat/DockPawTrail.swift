import AppKit
import QuartzCore

/// Foot contacts use the same phase offsets and registration as motion_rigs.py.
/// A mark keeps its landing position; only its opacity changes after touchdown.
struct DockPawTrail {
    struct Stamp: Equatable {
        enum Kind { case paw, roll }
        let id: Int
        let kind: Kind
        let orbitPhase: Double
        let tangentOffset: Double
        let near: Bool
        var age: TimeInterval

        var lifetime: TimeInterval { kind == .paw ? 3.4 : 1.25 }
        var opacity: Double {
            let strength = kind == .roll ? 0.65 : (near ? 0.95 : 0.68)
            return strength * pow(max(0, 1 - age / lifetime), 1.5)
        }

        func pose(on path: DockOrbitPath) -> DockOrbitPath.Pose {
            let body = path.pose(at: orbitPhase)
            return DockOrbitPath.Pose(
                center: CGPoint(x: body.center.x + tangentOffset * cos(body.angle)
                                + DockOrbitPath.groundOffset * sin(body.angle),
                                y: body.center.y + tangentOffset * sin(body.angle)
                                - DockOrbitPath.groundOffset * cos(body.angle)),
                angle: body.angle)
        }
    }

    private struct Footfall {
        let phase: Double
        let tangentOffset: Double
        let near: Bool
    }

    static let capacity = 96
    private static let walk = footfalls(stride: 44, offsets: [0.5, 0.25, 0, 0.75])
    private static let run = footfalls(stride: 85, offsets: [0.48, 0.03, 0.58, 0.13])
    private(set) var stamps: [Stamp] = []
    private var nextID = 0
    private var rollDistance = 0.0

    var needsTicks: Bool { !stamps.isEmpty }

    mutating func clear() {
        stamps.removeAll(keepingCapacity: true)
        rollDistance = 0
    }

    mutating func advance(by delta: TimeInterval, from before: CatMotion, to after: CatMotion,
                          orbitPhase: Double, travel: Double, pathLength: Double) {
        for index in stamps.indices { stamps[index].age += delta }
        stamps.removeAll { $0.age >= $0.lifetime }

        if before.gait == .roll, after.gait == .roll,
           before.transition == nil, after.transition == nil {
            // A tucked cat leaves a small contact streak, never floating paw prints.
            let spacing = 7.0
            var offset = spacing - rollDistance
            while offset <= travel {
                let fraction = travel > 0 ? offset / travel : 0
                append(kind: .roll, phase: orbitPhase + offset / pathLength,
                       tangentOffset: 0, near: true, age: delta * (1 - fraction))
                offset += spacing
            }
            rollDistance = (rollDistance + travel).truncatingRemainder(dividingBy: spacing)
            return
        }
        rollDistance = 0

        guard let gait = Self.contactGait(after), gait == Self.contactGait(before) else { return }
        let advanced = after.revolutions - before.revolutions
        guard advanced > 0, travel > 0 else { return }
        for foot in gait == .run ? Self.run : Self.walk {
            var untilLanding = foot.phase - before.phase
            if untilLanding <= 1e-10 { untilLanding += 1 }
            guard untilLanding <= advanced + 1e-10 else { continue }
            let fraction = min(1, untilLanding / advanced)
            append(kind: .paw, phase: orbitPhase + travel * fraction / pathLength,
                   tangentOffset: foot.tangentOffset, near: foot.near, age: delta * (1 - fraction))
        }
    }

    private mutating func append(kind: Stamp.Kind, phase: Double, tangentOffset: Double,
                                 near: Bool, age: TimeInterval) {
        stamps.append(Stamp(id: nextID, kind: kind, orbitPhase: phase - floor(phase),
                            tangentOffset: tangentOffset, near: near, age: age))
        nextID += 1
        if stamps.count > Self.capacity { stamps.removeFirst(stamps.count - Self.capacity) }
    }

    private static func contactGait(_ cat: CatMotion) -> CatGait? {
        let gait: CatGait
        if let transition = cat.transition {
            guard transition.kind == .blend else { return nil }
            gait = transition.progress < 0.5 ? transition.from : transition.to
        } else { gait = cat.gait }
        return gait == .walk || gait == .run ? gait : nil
    }

    private static func footfalls(stride: Double, offsets: [Double]) -> [Footfall] {
        // Artwork/derivation.json: center x=497, source scale=0.034292..., Dock scale=1.5.
        // The rounded paw extends from ankle.x-23 to ankle.x+41, so its center is +9.
        let hips = [347.0, 733.0, 311.0, 693.0]
        let scale = 0.034292035398230086 * 1.5
        return hips.indices.map { index in
            Footfall(phase: (1 - offsets[index]).truncatingRemainder(dividingBy: 1),
                     tangentOffset: (hips[index] + stride + 9 - 497) * scale, near: index >= 2)
        }
    }
}

@MainActor
final class DockPawTrailLayer {
    let layer = CALayer()
    private var marks: [Int: CAShapeLayer] = [:]
    private var color: NSColor?
    private static let pawPath: CGPath = {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -3, y: -1.5, width: 3.4, height: 3))
        for (x, y) in [(0.0, -1.9), (1.45, -0.8), (1.45, 0.8), (0.0, 1.9)] {
            path.addEllipse(in: CGRect(x: x - 0.7, y: y - 0.62, width: 1.4, height: 1.24))
        }
        return path
    }()
    private static let rollPath = CGPath(ellipseIn: CGRect(x: -3.6, y: -0.65, width: 7.2, height: 1.3), transform: nil)

    init() {
        layer.name = "dock-paw-trail"
        layer.masksToBounds = false
    }

    func clear() {
        marks.values.forEach { $0.removeFromSuperlayer() }
        marks.removeAll(keepingCapacity: true)
    }

    /// Called inside the cat view's disabled-actions transaction.
    func present(_ trail: DockPawTrail, path: DockOrbitPath, color: NSColor, scale: CGFloat) {
        let liveIDs = Set(trail.stamps.map(\.id))
        for id in Array(marks.keys) where !liveIDs.contains(id) {
            marks.removeValue(forKey: id)?.removeFromSuperlayer()
        }
        let colorChanged = self.color != color
        self.color = color
        for stamp in trail.stamps {
            let mark: CAShapeLayer
            let isNew = marks[stamp.id] == nil
            if let existing = marks[stamp.id] { mark = existing }
            else {
                mark = CAShapeLayer()
                mark.name = stamp.kind == .paw ? "paw-contact" : "roll-contact"
                mark.bounds = CGRect(x: -6, y: -5, width: 12, height: 10)
                mark.path = stamp.kind == .paw ? Self.pawPath : Self.rollPath
                mark.shadowPath = mark.path
                mark.shadowOffset = .zero
                mark.shadowRadius = stamp.kind == .paw ? 3.2 : 2.4
                mark.shadowOpacity = 1
                mark.allowsEdgeAntialiasing = true
                layer.addSublayer(mark)
                marks[stamp.id] = mark
            }
            if isNew || colorChanged {
                mark.fillColor = (color.blended(withFraction: 0.32, of: .white) ?? color).cgColor
                mark.shadowColor = color.cgColor
            }
            let pose = stamp.pose(on: path)
            mark.position = CGPoint(x: pose.center.x - path.canvasFrame.minX,
                                    y: pose.center.y - path.canvasFrame.minY)
            let size = stamp.near ? 1.0 : 0.82
            mark.transform = CATransform3DScale(CATransform3DMakeRotation(pose.angle, 0, 0, 1), size, size, 1)
            mark.contentsScale = scale
            mark.opacity = Float(stamp.opacity)
        }
    }
}
