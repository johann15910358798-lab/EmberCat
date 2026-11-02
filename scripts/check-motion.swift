import Foundation

@main
struct MotionCheck {
    // Values inside each tier's overlapping rise/fall thresholds reach that
    // same tier from either direction, which is essential for all-pair checks.
    static let samples: [Double] = [0, 3, 12, 24, 36, 50, 67.6, 91, 125, 185]
    static let dt = 1.0 / 30.0

    static func drive(_ director: inout MotionDirector, speed: Double, seconds: Double) {
        director.setSpeed(speed)
        for _ in 0..<Int((seconds / dt).rounded(.up)) { director.advance(by: dt) }
    }

    static func settled(_ mode: SpeedTier) -> MotionDirector {
        var director = MotionDirector()
        drive(&director, speed: samples[mode.rank], seconds: 12)
        precondition(director.mode == mode && director.transition == nil, "Cannot settle in \(mode)")
        return director
    }

    static func main() throws {
        hysteresisPreventsBoundaryThrashing()
        transientSpikesDoNotStartTransitions()
        committedTransitionsDoNotRestartOrReverse()
        everyOrderedPairTransitionsDirectly()
        suddenThreeToSeventyAndBack()
        newSpeedDuringTransitionUsesLatestTarget()
        cooldownAndInvalidSamples()
        tokenRateNeverAcceleratesPlayback()
        try exportTrace()
        print("PASS: 8 motion-state checks; application-source traces exported")
    }

    static func hysteresisPreventsBoundaryThrashing() {
        for rank in 1..<SpeedTier.allCases.count {
            for start in [SpeedTier.allCases[rank-1], SpeedTier.allCases[rank]] {
                var director = settled(start)
                for tick in 0..<900 {
                    let nominal = SpeedTier.boundaries[rank]
                    director.setSpeed(nominal * (tick % 6 < 3 ? 0.94 : 1.06))
                    director.advance(by: dt)
                    precondition(director.transition == nil && director.mode == start,
                        "Threshold jitter switched \(start) at boundary \(nominal)")
                }
            }
        }
        print("PASS: 30 seconds of jitter from both sides of all 9 boundaries, zero transitions")
    }

    static func transientSpikesDoNotStartTransitions() {
        var director = settled(.run)
        drive(&director, speed: 220, seconds: 0.2)
        for _ in 0..<180 {
            director.setSpeed(24)
            director.advance(by: dt)
            precondition(director.transition == nil && director.mode == .run, "A short spike committed")
        }
        print("PASS: 200 ms speed spike is rejected")
    }

    static func committedTransitionsDoNotRestartOrReverse() {
        var director = settled(.run)
        director.setSpeed(36)
        for _ in 0..<180 {
            director.advance(by: dt)
            if director.transition != nil { break }
        }
        let initial = director.transition!
        precondition(initial.from == .run && initial.to == .rollers)
        var previous = initial.progress
        for tick in 0..<Int((MotionDirector.transitionDuration/dt).rounded(.up)) {
            director.setSpeed(tick % 2 == 0 ? 0 : 220)
            director.advance(by: dt)
            if let transition = director.transition {
                precondition(transition.from == initial.from && transition.to == initial.to)
                precondition(transition.progress > previous, "Transition was restarted")
                previous = transition.progress
            }
        }
        director.advance(by: dt)
        precondition(director.mode == .rollers && director.transition == nil)
        print("PASS: a committed transition survives alternating 0/220 tok/s without restarting")
    }

    static func assertDirect(_ director: inout MotionDirector, to target: SpeedTier,
        speed: Double, delta: Double = dt) {
        let source = director.mode
        var started = false
        var finished = false
        director.setSpeed(speed)
        for _ in 0..<Int(12 / delta) {
            director.advance(by: delta)
            if let transition = director.transition {
                precondition(transition.from == source && transition.to == target,
                    "Unexpected intermediate tier: \(source)→\(transition.to), expected \(target)")
                started = true
            } else if director.mode != source {
                precondition(director.mode == target && started, "Destination changed without a transition")
                finished = true
            }
        }
        precondition(started && finished && director.mode == target && director.transition == nil,
            "Direct transition \(source)→\(target) did not finish")
    }

    static func everyOrderedPairTransitionsDirectly() {
        var count = 0
        for from in SpeedTier.allCases {
            for to in SpeedTier.allCases where from != to {
                var director = settled(from)
                assertDirect(&director, to: to, speed: samples[to.rank])
                count += 1
            }
        }
        precondition(count == 90)
        print("PASS: all 90 ordered state pairs go directly to the confirmed target, no intermediate modes")
    }

    static func suddenThreeToSeventyAndBack() {
        for delta in [1.0/60, 1.0/30, 1.0/15, 0.25] {
            var director = settled(.walk)
            assertDirect(&director, to: .bicycle, speed: 70, delta: delta)
            assertDirect(&director, to: .walk, speed: 3, delta: delta)
            assertDirect(&director, to: .jetpack, speed: 220, delta: delta)
            assertDirect(&director, to: .idle, speed: 0, delta: delta)
            precondition(!director.needsTicks)
        }
        print("PASS: sudden 3→70→3→220→0 at 60/30/15/4 Hz, including filter crossings and return to idle")
    }

    static func newSpeedDuringTransitionUsesLatestTarget() {
        for latest in [3.0, 220.0] {
            var director = settled(.walk)
            director.setSpeed(70)
            for _ in 0..<180 {
                director.advance(by: dt)
                if director.transition != nil { break }
            }
            let original = director.transition!
            precondition(original.from == .walk && original.to == .bicycle)
            director.setSpeed(220) // New samples cannot interrupt or restart this bridge.
            var previous = original.progress
            for tick in 0..<30 {
                if tick == 3 { director.setSpeed(latest) }
                director.advance(by: dt)
                guard let transition = director.transition else { break }
                precondition(transition.from == .walk && transition.to == .bicycle)
                precondition(transition.progress > previous, "Direct transition was restarted")
                previous = transition.progress
            }
            precondition(director.mode == .bicycle && director.transition == nil)
            // The next target is determined after the same minimum dwell and
            // confirmation as ordinary input, never from a stale queued route.
            for _ in 0..<45 {
                director.advance(by: dt)
                precondition(director.mode == .bicycle && director.transition == nil)
            }
            assertDirect(&director, to: latest == 3 ? .walk : .jetpack, speed: latest)
        }
        print("PASS: 3→70 bridge finishes once; later 3 or 220 uses the latest target after dwell")
    }

    static func cooldownAndInvalidSamples() {
        var director = settled(.run)
        director.setSpeed(36)
        for _ in 0..<240 {
            director.advance(by: dt)
            if director.mode == .rollers && director.transition == nil { break }
        }
        director.setSpeed(220)
        for _ in 0..<45 {
            director.advance(by: dt)
            precondition(director.mode == .rollers && director.transition == nil, "Minimum dwell violated")
        }
        for value: Double in [.nan, .infinity, -.infinity, -20] {
            director.setSpeed(value)
            precondition(director.rawSpeed == 0)
        }
        let phase = director.clock.phase
        director.advance(by: .nan)
        director.advance(by: -.infinity)
        precondition(director.clock.phase == phase)
        var fresh = MotionDirector()
        fresh.setSpeed(200)
        fresh.advance(by: 3600)
        precondition(fresh.transition == nil, "Sleep counted as confirmation time")
        print("PASS: 1.6 s minimum dwell; invalid samples and long sleep are safe")
    }

    static func tokenRateNeverAcceleratesPlayback() {
        for mode in SpeedTier.allCases where mode != .idle {
            let lower = SpeedTier.fallThreshold(at: mode.rank)
            let upper = mode == .jetpack ? 1000 : SpeedTier.riseThreshold(at: mode.rank+1)
            var slow = settled(mode)
            var fast = slow
            slow.setSpeed(lower + (upper-lower)*0.2)
            fast.setSpeed(lower + (upper-lower)*0.8)
            for _ in 0..<180 {
                slow.advance(by: dt)
                fast.advance(by: dt)
                precondition(slow.mode == mode && fast.mode == mode)
                precondition(slow.transition == nil && fast.transition == nil)
                precondition(slow.clock.phase(cycleDuration: mode.cycleDuration)
                    == fast.clock.phase(cycleDuration: mode.cycleDuration),
                    "Token rate changed the playback cadence of \(mode)")
            }
        }
        print("PASS: all 9 Makima actions keep identical cadence at different token rates")
    }

    static func exportTrace() throws {
        let normal: [(Double, Double)] = [(0,2),(3,5),(12,5),(24,5),(36,5),(50,5),(67.6,5),(91,5),(125,5),(185,6),
            (151,1),(147,1),(153,1),(149,1),(151,1),(147,1),(153,1),(149,1),(0,12)]
        let jumps: [(Double, Double)] = [(3,4),(70,5),(3,6),(185,6),(0,9)]
        for (index, schedule) in [normal, jumps].enumerated() {
            if CommandLine.arguments.count > index + 1 {
                try writeTrace(schedule: schedule, path: CommandLine.arguments[index+1])
            }
        }
    }

    static func writeTrace(schedule: [(Double, Double)], path: String) throws {
        var director = MotionDirector()
        var trace: [[String: Any]] = []
        var tick = 0
        for (speed, duration) in schedule {
            director.setSpeed(speed)
            for _ in 0..<Int(duration/dt) {
                director.advance(by: dt)
                var row: [String: Any] = ["time":Double(tick)*dt,"rawSpeed":director.rawSpeed,
                    "filteredSpeed":director.filteredSpeed,"mode":director.mode.rawValue,
                    "phase":director.clock.phase(cycleDuration:director.mode.cycleDuration),
                    "catPhase":director.cat.phase,"title":director.title]
                if let transition = director.transition {
                    row["transition"] = ["from":transition.from.rawValue,"to":transition.to.rawValue,
                        "progress":transition.progress,"sourcePhase":transition.sourcePhase]
                }
                trace.append(row)
                tick += 1
            }
        }
        let data = try JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }
}
