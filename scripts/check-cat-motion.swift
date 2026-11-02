import Foundation

@main
struct CatMotionCheck {
    static let dt = 1.0 / 60.0
    static let speeds = [0.0, 8, 45, 140]

    static func drive(_ motion: inout CatMotion, speed: Double, seconds: Double, delta: Double = dt) {
        motion.setSpeed(speed)
        for _ in 0..<Int((seconds / delta).rounded()) { motion.advance(by: delta) }
    }

    static func settled(_ gait: CatGait) -> CatMotion {
        var motion = CatMotion()
        drive(&motion, speed: speeds[gait.rank], seconds: 12)
        precondition(motion.gait == gait && motion.transition == nil && motion.aligningTo == nil)
        return motion
    }

    static func main() {
        continuousCadence()
        boundedAcceleration()
        frameRateIndependence()
        boundaryJitter()
        curlAndUprightLanding()
        latestInputDuringCurl()
        allGaitsAndIdle()
        invalidInputsAndSleep()
        print("PASS: 8 cat motion checks using the production controller")
    }

    static func continuousCadence() {
        var motion = settled(.walk)
        drive(&motion, speed: 3, seconds: 6)
        let slow = motion.cyclesPerSecond
        let before = motion.phase
        motion.setSpeed(14)
        precondition(motion.phase == before, "Speed input reset the phase")
        for _ in 0..<360 {
            let old = motion.phase
            motion.advance(by: dt)
            let delta = (motion.phase - old + 1).truncatingRemainder(dividingBy: 1)
            precondition(delta > 0 && delta < 0.03, "Cadence change jumped the pose")
            precondition(motion.gait == .walk && motion.transition == nil)
        }
        precondition(motion.cyclesPerSecond > slow * 1.6, "Walking did not speed up")
        print("PASS: 3→14 tok/s accelerates the same walk without resetting or jumping phase")
    }

    static func boundedAcceleration() {
        var motion = CatMotion()
        for speed in [8.0, 220, 0, 140, 3, 10_000, 0] {
            motion.setSpeed(speed)
            for _ in 0..<720 {
                let before = motion.cyclesPerSecond
                motion.advance(by: dt)
                precondition(motion.cyclesPerSecond >= 0 && motion.cyclesPerSecond <= 2.58)
                precondition(motion.cyclesPerSecond - before <= 2 * dt + 0.0011)
                precondition(before - motion.cyclesPerSecond <= 1.5 * dt + 0.0011)
            }
        }
        print("PASS: acceleration/deceleration remain bounded through large speed jumps")
    }

    static func frameRateIndependence() {
        let schedule = [(8.0, 5.0), (140.0, 7.0), (45.0, 5.0), (0.0, 12.0)]
        var baseline = CatMotion()
        for (speed, duration) in schedule { drive(&baseline, speed: speed, seconds: duration, delta: 1.0/120) }
        for delta in [1.0/60, 1.0/30, 1.0/15, 0.25] {
            var candidate = CatMotion()
            for (speed, duration) in schedule { drive(&candidate, speed: speed, seconds: duration, delta: delta) }
            precondition(abs(candidate.revolutions - baseline.revolutions) < 0.000_001)
            precondition(candidate.gait == baseline.gait && !candidate.needsTicks)
        }
        print("PASS: 120/60/30/15/4 Hz produce matching integrated motion")
    }

    static func boundaryJitter() {
        for (lower, upper, center, amplitude) in [(CatGait.idle, CatGait.walk, 0.6, 0.1),
            (.walk, .run, 19.0, 1.0), (.run, .roll, 80.0, 4.0)] {
            for start in [lower, upper] {
                var motion = settled(start)
                for tick in 0..<1200 {
                    motion.setSpeed(center + (tick % 12 < 6 ? -amplitude : amplitude))
                    motion.advance(by: dt)
                    precondition(motion.gait == start && motion.transition == nil && motion.aligningTo == nil)
                }
            }
        }
        print("PASS: 20 seconds of boundary jitter from both sides never switches gait")
    }

    static func curlAndUprightLanding() {
        var motion = settled(.run)
        motion.setSpeed(140)
        var curled = false
        for _ in 0..<600 {
            motion.advance(by: dt)
            if let transition = motion.transition, transition.kind == .curl {
                precondition(motion.phase == 0 && transition.from == .run && transition.to == .roll)
                curled = true
            }
            if motion.gait == .roll { break }
        }
        precondition(curled && motion.gait == .roll, "Roll began without the curl")
        drive(&motion, speed: 140, seconds: 0.8)
        motion.setSpeed(0)
        var unfolded = false
        for _ in 0..<720 {
            motion.advance(by: dt)
            if let transition = motion.transition, transition.kind == .uncurl {
                precondition(motion.phase == 0 && transition.from == .roll && transition.to == .run,
                    "Ball unfolded while upside down")
                unfolded = true
            }
        }
        precondition(unfolded && motion.gait == .idle && !motion.needsTicks)
        print("PASS: run→curl→ball; stopped ball turns upright before unfolding and settling")
    }

    static func latestInputDuringCurl() {
        for latest in [0.0, 8.0] {
            var motion = settled(.run)
            motion.setSpeed(140)
            for _ in 0..<600 {
                motion.advance(by: dt)
                if motion.transition?.kind == .curl { break }
            }
            precondition(motion.transition?.kind == .curl)
            motion.setSpeed(220)
            motion.advance(by: dt)
            motion.setSpeed(latest)
            var previous = motion.transition!.progress
            while let active = motion.transition, active.kind == .curl {
                precondition(active.progress >= previous)
                previous = active.progress
                motion.advance(by: dt)
            }
            drive(&motion, speed: latest, seconds: 12)
            precondition(motion.gait == (latest == 0 ? .idle : .walk) && motion.transition == nil)
        }
        print("PASS: a curl finishes once and then follows the latest speed, without a stale queue")
    }

    static func allGaitsAndIdle() {
        for from in CatGait.allCases {
            for to in CatGait.allCases {
                var motion = settled(from)
                drive(&motion, speed: speeds[to.rank], seconds: 12)
                precondition(motion.gait == to && motion.transition == nil && motion.aligningTo == nil)
                if to == .idle { precondition(!motion.needsTicks) }
            }
        }
        print("PASS: all 16 state pairs settle correctly; standing releases the animation timer")
    }

    static func invalidInputsAndSleep() {
        var motion = settled(.run)
        for speed: Double in [.nan, .infinity, -.infinity, -50] {
            motion.setSpeed(speed)
            precondition(motion.rawSpeed == 0)
        }
        let before = motion.phase
        for delta: Double in [.nan, .infinity, -.infinity, -1, 0] { motion.advance(by: delta) }
        precondition(motion.phase == before)
        var fresh = CatMotion()
        fresh.setSpeed(140)
        fresh.advance(by: 3600)
        precondition(fresh.gait == .idle && fresh.revolutions < 0.1)
        print("PASS: invalid input is rejected and a long wake-up never fast-forwards to rolling")
    }
}
