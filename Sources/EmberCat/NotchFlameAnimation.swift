import Foundation

/// Measured heat stays at zero during idle; decorative effects can keep moving slowly.
struct NotchFlameAnimation {
    static let idleMotionScale = 0.45
    private(set) var heat: Double = 0
    private(set) var visibility: Double = 0
    private(set) var phase: Double = 8.73
    private(set) var targetHeat: Double = 0
    private var targetVisibility: Double = 0
    private(set) var color = NotchFlamePalette.standard.color(for: 0)
    private var targetColor = NotchFlamePalette.standard.color(for: 0)
    private var effect: NotchEffectStyle = .flame

    static func heat(for speed: Double) -> Double {
        guard speed.isFinite else { return 0 }
        return pow(min(1, max(0, speed / 180)), 0.80)
    }

    static func motionScale(heat: Double, effect: NotchEffectStyle) -> Double {
        guard effect.hasIdleAnimation else { return 1 }
        let progress = heat.isFinite ? min(1, max(0, heat / Self.heat(for: 20))) : 0
        return idleMotionScale + (1 - idleMotionScale) * progress * progress * (3 - 2 * progress)
    }

    var motionScale: Double { Self.motionScale(heat: heat, effect: effect) }

    mutating func setSpeed(_ speed: Double, active: Bool = true, effect: NotchEffectStyle = .flame,
                           color: SIMD3<Float>? = nil) {
        self.effect = effect
        if let color {
            targetColor = color
            if isHidden { self.color = color }
        }
        targetHeat = active ? Self.heat(for: speed) : 0
        targetVisibility = active && (targetHeat > 0 || effect.hasIdleAnimation) ? 1 : 0
    }

    mutating func advance(by elapsed: TimeInterval, reduceMotion: Bool = false, flow: Double = 1) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        let delta = min(0.1, elapsed)
        let heatTime = targetHeat < heat ? 0.48 : 0.36
        heat += (targetHeat - heat) * (1 - exp(-delta / heatTime))
        visibility += (targetVisibility - visibility)
            * (1 - exp(-delta / (targetVisibility > visibility ? 0.16 : 0.48)))
        if abs(targetHeat - heat) < 0.0004 { heat = targetHeat }
        if abs(targetVisibility - visibility) < 0.0004 { visibility = targetVisibility }
        color += (targetColor - color) * Float(1 - exp(-delta / 0.22))
        if colorDistance < 0.0004 { color = targetColor }
        if !reduceMotion {
            let multiplier = flow.isFinite ? min(2.5, max(0.25, flow)) : 1
            // Heat already slows the energy and code clocks. Applying the GIF
            // slowdown again makes idle motion nearly imperceptible.
            phase += delta * (0.22 + heat + 0.50 * heat * heat) * multiplier
        }
    }

    var isHidden: Bool { heat == 0 && visibility == 0 }

    func needsFrames(reduceMotion: Bool) -> Bool {
        guard !isHidden || targetVisibility > 0 else { return false }
        return !reduceMotion || heat != targetHeat || visibility != targetVisibility || color != targetColor
    }

    private var colorDistance: Float {
        max(abs(color.x - targetColor.x), abs(color.y - targetColor.y), abs(color.z - targetColor.z))
    }

    mutating func reset() {
        heat = 0
        targetHeat = 0
        visibility = 0
        targetVisibility = 0
        color = targetColor
    }
}
