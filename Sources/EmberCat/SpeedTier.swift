enum SpeedTier: String, CaseIterable, Identifiable {
    case idle = "00-idle"
    case walk = "01-walk"
    case brisk = "02-brisk"
    case run = "03-run"
    case rollers = "04-rollers"
    case board = "05-board"
    case bicycle = "06-bicycle"
    case motorcycle = "07-motorcycle"
    case roadster = "08-roadster"
    case jetpack = "09-jetpack"

    var id: String { rawValue }
    var rank: Int { Self.allCases.firstIndex(of: self)! }

    /// Nominal boundaries; MotionDirector adds hysteresis and confirmation time.
    static let boundaries: [Double] = [0, 0.8, 8, 18, 30, 44, 60, 80, 110, 150]

    /// Art-directed loop periods, independent of measured or filtered tok/s.
    var cycleDuration: Double {
        switch self {
        case .idle: 2.4
        case .walk: 1.6
        case .brisk: 1.4
        case .run: 1.2
        case .rollers, .board, .bicycle, .motorcycle, .roadster, .jetpack: 2.4
        }
    }

    var frameCount: Int {
        switch self {
        case .idle: 1
        case .walk: 96
        default: 8
        }
    }

    var compactTitle: String {
        switch self {
        case .idle: "待机"
        case .walk: "走路"
        case .brisk: "快走"
        case .run: "跑步"
        case .rollers: "轮滑"
        case .board: "滑板"
        case .bicycle: "自行车"
        case .motorcycle: "摩托车"
        case .roadster: "敞篷跑车"
        case .jetpack: "飞行背包"
        }
    }

    static func forSpeed(_ speed: Double) -> SpeedTier {
        guard speed.isFinite else { return .idle }
        return allCases.last(where: { speed >= boundaries[$0.rank] }) ?? .idle
    }

    static func riseThreshold(at rank: Int) -> Double {
        rank == 1 ? 1.0 : boundaries[rank] * 1.12
    }

    static func fallThreshold(at rank: Int) -> Double {
        rank == 1 ? 0.25 : boundaries[rank] * 0.85
    }

    static func target(for speed: Double, from current: SpeedTier) -> SpeedTier {
        var rank = current.rank
        while rank + 1 < allCases.count, speed >= riseThreshold(at: rank + 1) { rank += 1 }
        while rank > 0, speed <= fallThreshold(at: rank) { rank -= 1 }
        return allCases[rank]
    }
}
