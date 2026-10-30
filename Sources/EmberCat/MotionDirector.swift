import Foundation

/// Speed selection is deliberately independent of rendering, timers and AppKit.
/// A committed transition goes directly to its target and always finishes.
struct MotionDirector {
    struct Transition {
        let from: SpeedTier
        let to: SpeedTier
        let sourcePhase: Double
        var elapsed: Double = 0
        var progress: Double { min(1, elapsed / MotionDirector.transitionDuration) }
    }

    static let transitionDuration = 0.8
    static let minimumDwell = 1.6
    static let riseConfirmation = 0.65
    static let fallConfirmation = 1.1
    static let idleConfirmation = 1.3

    private(set) var mode: SpeedTier = .idle
    private(set) var transition: Transition?
    private(set) var rawSpeed: Double = 0
    private(set) var filteredSpeed: Double = 0
    private(set) var clock = AnimationClock()
    private(set) var pending: SpeedTier?
    private var pendingElapsed: Double = 0
    private var dwellRemaining: Double = 0

    var needsTicks: Bool {
        transition != nil || mode != .idle || rawSpeed >= 0.8 || filteredSpeed >= 0.3
    }

    var title: String {
        if let transition {
            return "\(transition.from.compactTitle) → \(transition.to.compactTitle)"
        }
        return mode.compactTitle
    }

    mutating func setSpeed(_ value: Double) {
        rawSpeed = value.isFinite ? max(0, value) : 0
    }

    mutating func advance(by elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        // A long sleep is not evidence that a newly received speed held steady.
        let delta = min(elapsed, 0.25)
        let tau = rawSpeed > filteredSpeed ? 0.35 : 0.7
        filteredSpeed += (rawSpeed - filteredSpeed) * (1 - exp(-delta / tau))
        if filteredSpeed < 0.001 { filteredSpeed = 0 }
        clock.setPlaying(mode != .idle || transition != nil)
        clock.advance(by: delta)

        if var active = transition {
            active.elapsed += delta
            if active.progress < 1 {
                transition = active
                return
            }
            mode = active.to
            transition = nil
            dwellRemaining = Self.minimumDwell
            return
        }

        if dwellRemaining > 0 {
            dwellRemaining = max(0, dwellRemaining - delta)
            clearPending()
            return
        }
        let candidate = SpeedTier.target(for: filteredSpeed, from: mode)
        guard candidate != mode else {
            clearPending()
            return
        }
        // Both inputs must agree on the destination. On a large step the filter
        // crosses intermediate tiers; none of those are the requested target.
        // This also rejects residual filtering after a short raw spike ends.
        let rawCandidate = SpeedTier.target(for: rawSpeed, from: mode)
        guard rawCandidate == candidate else {
            clearPending()
            return
        }
        if pending != candidate {
            pending = candidate
            pendingElapsed = 0
        }
        pendingElapsed += delta
        let required = candidate == .idle ? Self.idleConfirmation
            : (candidate.rank > mode.rank ? Self.riseConfirmation : Self.fallConfirmation)
        guard pendingElapsed >= required else { return }
        clearPending()
        transition = Transition(from: mode, to: candidate,
            sourcePhase: clock.phase(cycleDuration: mode.cycleDuration))
    }

    private mutating func clearPending() {
        pending = nil
        pendingElapsed = 0
    }
}
