enum PetStyle: String, CaseIterable {
    case cat = "Cat"
    case makima = "Makima"

    var displayName: String {
        switch self {
        case .cat: "胖黑猫"
        case .makima: "玛奇玛"
        }
    }
}
