import Foundation

struct NotchLightningDischargeUniform {
    var timing: SIMD4<Float> // age, lifetime, power, random variation
    var shape: SIMD4<Float>  // horizontal root, length, mirror, slant
}

struct NotchLightningDischarge: Equatable {
    let birth: Double
    let age: Double
    let duration: Double
    let power: Double
    let position: Double
    let length: Double
    let mirror: Double
    let slant: Double
    let variation: Double

    var envelope: Double {
        func smooth(_ a: Double, _ b: Double, _ value: Double) -> Double {
            let t = min(1, max(0, (value-a)/(b-a)))
            return t*t*(3-2*t)
        }
        return power * smooth(0, 0.018, age)
            * (1-smooth(duration*0.24, duration, age))
    }

    var uniform: NotchLightningDischargeUniform {
        .init(timing: SIMD4(Float(age), Float(duration), Float(power), Float(variation)),
            shape: SIMD4(Float(position), Float(length), Float(mirror), Float(slant)))
    }
}

/// Randomize whole strikes, not individual frames. A seeded, time-addressable
/// schedule keeps the GPU, recoil and previews in sync without replaying history.
enum NotchLightningDischarges {
    static let sessionSeed = UInt64.random(in: .min ... .max)
    static let previewSeed: UInt64 = 0x6DA9_24E8_71CB_503F

    static func events(phase: Double, seed: UInt64 = previewSeed) -> [NotchLightningDischarge] {
        let time = phase.isFinite ? min(1_000_000_000, max(0, phase)) : 0
        return [1.45, 1.93, 0.76, 0.93, 1.11, 1.37].enumerated().map { channel, window in
            let cycle = UInt64(floor(time/window))
            let current = event(time: time, channel: channel, cycle: cycle, window: window, seed: seed)
            if cycle > 0, current.age < -0.055 {
                let previous = event(time: time, channel: channel, cycle: cycle-1, window: window, seed: seed)
                // A strike may cross a scheduling boundary. Keep its root and
                // shape until the discharge (and its mechanical recoil) ends.
                if previous.age < (channel < 2 ? 0.45 : previous.duration) { return previous }
            }
            return current
        }
    }

    private static func event(time: Double, channel: Int, cycle: UInt64, window: Double,
                              seed: UInt64) -> NotchLightningDischarge {
        func random(_ lane: UInt64) -> Double {
            var value = seed &+ cycle &* 0x9E37_79B9_7F4A_7C15
                &+ UInt64(channel+1) &* 0xD1B5_4A32_D192_ED03 &+ lane &* 0x94D0_49BB_1331_11EB
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return Double(value >> 11) / 9_007_199_254_740_992
        }
        let leak = channel < 2
        let birth = (Double(cycle)+0.08+0.58*random(0))*window
        let duration = leak ? 0.20+0.20*random(1) : 0.16+0.13*random(1)
        let power = random(2) < (leak ? 0.12 : 0.04) ? 0 : 0.72+0.28*random(3)
        return .init(birth: birth, age: time-birth, duration: duration, power: power,
            position: (random(4)-0.5)*(leak ? 0.56 : 0.72),
            length: 0.62+0.50*random(5), mirror: random(6) < 0.5 ? -1 : 1,
            slant: (random(7)-0.5)*0.70, variation: random(8)*1_000)
    }
}

struct NotchLightningPose: Equatable {
    var offset: SIMD2<Double> = .zero
    var angle: Double = 0

    var uniform: SIMD4<Float> {
        SIMD4(Float(offset.x), Float(offset.y), Float(angle), 0)
    }
}

/// Levitation uses elapsed seconds, independently of token rate and energy flow.
/// A brief, damped recoil follows the same random strikes sent to the GPU.
enum NotchLightningMotion {
    static func hamsterSize(notchWidth: Double, scale: Double = 1) -> Double {
        min(72, max(50, notchWidth/3))*scale
    }
    static func diameter(heat: Double, thickness: Double = 1) -> Double { (18+18*heat)*thickness }

    static func pose(elapsed: Double, phase: Double, heat: Double,
                     configuration: NotchLightningConfiguration = .standard,
                     notchWidth: Double = 180,
                     reduceMotion: Bool = false,
                     discharges: [NotchLightningDischarge]? = nil) -> NotchLightningPose {
        guard configuration.motionEnabled, !reduceMotion,
              elapsed.isFinite, phase.isFinite, heat.isFinite else { return .init() }
        let h = min(1, max(0, heat))
        let t = max(0, elapsed)
        let amplitude = configuration.levitation
        let tau = Double.pi * 2
        var x = amplitude * 0.38 * (0.65 * sin(t * tau / 7.3) + 0.35 * sin(t * tau / 4.2))
        var y = amplitude * (0.72 * sin(t * tau / 5.6) + 0.28 * sin(t * tau / 9.4))
        var angle = amplitude * 0.0014 * (sin(t * 0.65) + 0.25 * sin(t * 1.07))
        let events = discharges ?? NotchLightningDischarges.events(phase: phase)
        for (index, event) in events.prefix(2).enumerated() {
            let age = event.age
            guard age >= 0, age < 0.45, event.power > 0 else { continue }
            let attack = min(1, age / 0.02)
            let envelope = attack * attack * (3 - 2 * attack) * exp(-age / 0.095)
            let amount = configuration.jitter * min(1.5, configuration.arcs)
                * (0.14 + 0.44 * h) * (index == 0 ? 1 : 0.72) * event.power
            let side = event.position < 0 ? -1.0 : 1.0
            x += side * sin(age * 67) * envelope * amount
            y += sin(age * 49) * envelope * amount * 0.64
            angle += side * sin(age * 54) * envelope * amount * 0.0015
        }
        let tipRise = abs(sin(angle)) * notchWidth * (0.88 + 0.30 * h) / 2
        y = max(y, 2.5 + tipRise - configuration.distance)
        return NotchLightningPose(offset: SIMD2(x, y), angle: angle)
    }

    static func maximumDepth(configuration: NotchLightningConfiguration) -> Double {
        max(108, ceil(configuration.distance + 2.9 * 36 * configuration.thickness
            + configuration.levitation * 1.35 + configuration.jitter * 1.5 + 8))
    }
}
