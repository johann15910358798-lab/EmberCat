import Foundation

enum CatGait: String, CaseIterable {
    case idle, walk, run, roll

    var rank: Int { Self.allCases.firstIndex(of: self)! }
    var frameCount: Int { self == .idle ? 1 : 96 }
    var title: String {
        switch self {
        case .idle: "站立"
        case .walk: "行走"
        case .run: "跑动"
        case .roll: "滚动"
        }
    }

    static func target(for speed: Double, from current: Self) -> Self {
        let rise = [0.0, 0.9, 22, 90]
        let fall = [0.0, 0.25, 16, 70]
        var rank = current.rank
        while rank < 3, speed >= rise[rank + 1] { rank += 1 }
        while rank > 0, speed <= fall[rank] { rank -= 1 }
        return allCases[rank]
    }
}

/// Continuous cadence belongs to the cat; Makima keeps her art-directed clock.
/// Phase is integrated from speed, never recomputed from elapsed / new period.
struct CatMotion {
    struct Transition {
        enum Kind: String { case blend, curl, uncurl }
        let kind: Kind
        let from: CatGait
        let to: CatGait
        let duration: Double
        var elapsed: Double = 0
        var progress: Double { min(1, elapsed / duration) }
    }

    static let curlFrameCount = 40
    private(set) var gait: CatGait = .idle
    private(set) var transition: Transition?
    private(set) var aligningTo: CatGait?
    private(set) var rawSpeed = 0.0
    private(set) var filteredSpeed = 0.0
    private(set) var cyclesPerSecond = 0.0
    private(set) var phase = 0.0
    private(set) var revolutions = 0.0
    private var pending: CatGait?
    private var pendingElapsed = 0.0
    private var dwellRemaining = 0.0

    var needsTicks: Bool {
        gait != .idle || transition != nil || aligningTo != nil
            || rawSpeed >= 0.9 || filteredSpeed >= 0.9 || cyclesPerSecond > 0.001
    }

    var title: String {
        guard let transition else { return gait.title }
        switch transition.kind {
        case .curl: return "蜷成球"
        case .uncurl: return "展开落地"
        case .blend: return "\(transition.from.title) → \(transition.to.title)"
        }
    }

    var frameKey: String {
        let index = AnimationClock.frameIndex(phase: phase, frameCount: 96)
        guard let transition else { return "\(gait.rawValue)/\(gait == .idle ? 0 : index)" }
        return "\(transition.kind.rawValue)/\(transition.from)/\(transition.to)/\(index)/\(Int(transition.progress * 120))"
    }

    mutating func setSpeed(_ speed: Double) {
        rawSpeed = speed.isFinite ? min(10_000, max(0, speed)) : 0
    }

    mutating func advance(by elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        // Bound wake-up catch-up; small integration steps make 30/60 Hz agree.
        var remaining = min(0.25, elapsed)
        while remaining > 1e-10 {
            let delta = min(1.0 / 120.0, remaining)
            step(delta)
            remaining -= delta
        }
    }

    private mutating func step(_ delta: Double) {
        let tau = rawSpeed > filteredSpeed ? 0.32 : 0.6
        filteredSpeed += (rawSpeed - filteredSpeed) * (1 - exp(-delta / tau))
        if filteredSpeed < 0.001 { filteredSpeed = 0 }
        let moving = gait != .idle || transition != nil
        let baseCadence = moving ? 0.38 + 2.2 * filteredSpeed / (filteredSpeed + 65) : 0
        let desiredCadence = max(baseCadence, gait == .roll && rawSpeed <= 70 ? 0.85 : 0)
        let before = cyclesPerSecond
        let change = (desiredCadence - before) * (1 - exp(-delta / 0.24))
        cyclesPerSecond += min(2.0 * delta, max(-1.5 * delta, change))
        if cyclesPerSecond < 0.001 { cyclesPerSecond = 0 }

        if var active = transition {
            if active.kind == .blend { _ = advancePhase(delta * (before + cyclesPerSecond) / 2) }
            active.elapsed += delta
            if active.progress < 1 {
                transition = active
            } else {
                gait = active.to
                transition = nil
                if active.kind != .blend { phase = 0 }
                dwellRemaining = 0.3
            }
            return
        }

        if let target = aligningTo {
            // Until the physical curl starts, a changed input can cancel it.
            let wanted = nextGait(for: rawSpeed)
            if wanted != target {
                aligningTo = nil
                clearPending()
            } else {
                // A stopped ball still completes its revolution before unfolding.
                let cadence = (before + cyclesPerSecond) / 2
                if advancePhase(delta * cadence) {
                    phase = 0
                    begin(target == .roll ? .curl : .uncurl, to: target, duration: 0.65)
                    aligningTo = nil
                }
                return
            }
        }

        if gait != .idle { _ = advancePhase(delta * (before + cyclesPerSecond) / 2) }
        if dwellRemaining > 0 {
            dwellRemaining = max(0, dwellRemaining - delta)
            clearPending()
            return
        }
        let candidate = nextGait(for: filteredSpeed)
        guard candidate != gait, nextGait(for: rawSpeed) == candidate else {
            clearPending()
            return
        }
        if pending != candidate { pending = candidate; pendingElapsed = 0 }
        pendingElapsed += delta
        let confirmation = candidate == .idle ? 0.65 : (candidate.rank > gait.rank ? 0.22 : 0.38)
        guard pendingElapsed + 1e-9 >= confirmation else { return }
        clearPending()
        if candidate == .roll || gait == .roll {
            aligningTo = candidate
            if phase < 1e-9 {
                begin(candidate == .roll ? .curl : .uncurl, to: candidate, duration: 0.65)
                aligningTo = nil
            }
        } else {
            begin(.blend, to: candidate, duration: candidate == .idle ? 0.36 : 0.28)
        }
    }

    private func nextGait(for speed: Double) -> CatGait {
        let target = CatGait.target(for: speed, from: gait)
        let direction = target.rank == gait.rank ? 0 : (target.rank > gait.rank ? 1 : -1)
        return CatGait.allCases[gait.rank + direction]
    }

    @discardableResult
    private mutating func advancePhase(_ amount: Double) -> Bool {
        let next = phase + amount
        phase = next.truncatingRemainder(dividingBy: 1)
        revolutions += amount
        return next >= 1
    }

    private mutating func begin(_ kind: Transition.Kind, to: CatGait, duration: Double) {
        transition = Transition(kind: kind, from: gait, to: to, duration: duration)
    }

    private mutating func clearPending() {
        pending = nil
        pendingElapsed = 0
    }
}
