enum PetStyle: String, CaseIterable {
    case cat = "Cat"
    case makima = "Makima"

    func cycleDuration(for mode: SpeedTier) -> Double {
        self == .cat ? AnimationClock.catCycleDuration : mode.cycleDuration
    }

    func frameCount(for mode: SpeedTier) -> Int {
        mode == .idle ? 1 : (self == .cat ? AnimationClock.catFrameCount : mode.frameCount)
    }

    var displayName: String {
        switch self {
        case .cat: "胖黑猫"
        case .makima: "玛奇玛"
        }
    }
}
