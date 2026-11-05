import AppKit

enum NotchEffectStyle: String, CaseIterable {
    case flame, matrix

    var title: String {
        switch self {
        case .flame: "流焰"
        case .matrix: "Matrix 代码雨"
        }
    }
}

struct NotchMatrixConfiguration: Codable, Equatable {
    static let standard = NotchMatrixConfiguration()
    var blackHoleSize: Double = 1.75
    var gravity: Double = 1.8
    var density: Double = 2
    var verticalOffset: Double = 0
    var rimWidth: Double = 1

    init(blackHoleSize: Double = 1.75, gravity: Double = 1.8, density: Double = 2,
         verticalOffset: Double = 0, rimWidth: Double = 1) {
        self.blackHoleSize = blackHoleSize
        self.gravity = gravity
        self.density = density
        self.verticalOffset = verticalOffset
        self.rimWidth = rimWidth
    }

    private enum CodingKeys: String, CodingKey {
        case blackHoleSize, gravity, density, verticalOffset, rimWidth
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(blackHoleSize: try values.decode(Double.self, forKey: .blackHoleSize),
            gravity: try values.decode(Double.self, forKey: .gravity),
            density: try values.decode(Double.self, forKey: .density),
            verticalOffset: try values.decodeIfPresent(Double.self, forKey: .verticalOffset) ?? 0,
            rimWidth: try values.decodeIfPresent(Double.self, forKey: .rimWidth) ?? 1)
    }

    var validationError: String? {
        for parameter in NotchMatrixParameter.allCases {
            let value = self[keyPath: parameter.keyPath]
            if !value.isFinite || !parameter.range.contains(value) {
                return "\(parameter.title)超出可调范围。"
            }
        }
        return nil
    }
}

enum NotchMatrixParameter: String, CaseIterable {
    case blackHoleSize, gravity, density, verticalOffset, rimWidth

    var title: String {
        switch self {
        case .blackHoleSize: "大小上限"
        case .gravity: "引力强度"
        case .density: "代码密度"
        case .verticalOffset: "与刘海距离"
        case .rimWidth: "吸积盘宽"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .blackHoleSize: 0.75...2.5
        case .gravity: 0.5...3
        case .density: 0.4...3
        case .verticalOffset: 0...64
        case .rimWidth: 0.4...1.8
        }
    }

    var keyPath: WritableKeyPath<NotchMatrixConfiguration, Double> {
        switch self {
        case .blackHoleSize: \.blackHoleSize
        case .gravity: \.gravity
        case .density: \.density
        case .verticalOffset: \.verticalOffset
        case .rimWidth: \.rimWidth
        }
    }

    func displayValue(_ value: Double) -> String {
        self == .verticalOffset
            ? (value == 0 ? "半嵌入" : String(format: "%.0f pt", value))
            : String(format: "%.0f%%", value * 100)
    }

    var help: String {
        switch self {
        case .blackHoleSize: "大小随 tok/s 自动变化；此项仅限制最大尺寸。"
        case .gravity: "越强越早汇聚吸入；远处保留竖直掉落。"
        case .density: "调节代码数量，仍随 tok/s 增减；不改变已有字符的路径。"
        case .verticalOffset: "0 为半嵌入；向下拉可完全脱离刘海，代码仍会吸入。"
        case .rimWidth: "收窄或放宽吸积盘与洞缘细光；不改变暗核大小。"
        }
    }
}

struct NotchFlameAppearance: Codable, Equatable {
    static let standard = NotchFlameAppearance()
    var brightness: Double = 1
    var core: Double = 0.5
    var transparency: Double = 0.4
    var length: Double = 1
    var turbulence: Double = 1
    var flow: Double = 1

    var validationError: String? {
        for parameter in NotchFlameParameter.allCases {
            let value = self[keyPath: parameter.keyPath]
            if !value.isFinite || !parameter.range.contains(value) {
                return "\(parameter.title)超出可调范围。"
            }
        }
        return nil
    }
}

enum NotchFlameParameter: String, CaseIterable {
    case brightness, core, transparency, length, turbulence, flow

    var title: String {
        switch self {
        case .brightness: "亮度"
        case .core: "亮芯范围"
        case .transparency: "通透度"
        case .length: "焰尾长度"
        case .turbulence: "扰动"
        case .flow: "流速"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .brightness: 0.4...1.8
        case .core, .transparency: 0...1
        case .length: 0.35...1.35
        case .turbulence: 0...2
        case .flow: 0.25...2.5
        }
    }

    var keyPath: WritableKeyPath<NotchFlameAppearance, Double> {
        switch self {
        case .brightness: \.brightness
        case .core: \.core
        case .transparency: \.transparency
        case .length: \.length
        case .turbulence: \.turbulence
        case .flow: \.flow
        }
    }

    var help: String {
        switch self {
        case .brightness: "调整火焰主体的明亮程度，描边保持清晰。"
        case .core: "向右增加高亮焰芯的面积，向左保留更多主色。"
        case .transparency: "向右让背景透过火焰，向左增加火焰厚度。"
        case .length: "缩短或拉长向下的焰尾，100% 为默认长度。"
        case .turbulence: "向右增加火焰卷曲和细节变化，向左让流动更平缓。"
        case .flow: "调整流动快慢，100% 为默认速度；仍随真实 tok/s 变化。"
        }
    }
}

struct NotchFlameBand: Codable, Equatable {
    var minimumSpeed: Double
    var hex: String

    var rgb: SIMD3<Float> {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return SIMD3(Float((value >> 16) & 255), Float((value >> 8) & 255), Float(value & 255)) / 255
    }

    var color: NSColor {
        NSColor(srgbRed: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
    }

    static func hex(for color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return nil }
        let bytes = components.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}

/// Left-closed, right-open speed bands. The final band has no upper limit.
struct NotchFlamePalette: Codable, Equatable {
    static let maximumBands = 8
    static let standard = NotchFlamePalette(bands: [
        NotchFlameBand(minimumSpeed: 0, hex: "#FFB52E"),
        NotchFlameBand(minimumSpeed: 60, hex: "#FF492E"),
        NotchFlameBand(minimumSpeed: 140, hex: "#4DADFF"),
    ])
    var bands: [NotchFlameBand]

    var validationError: String? {
        guard (1...Self.maximumBands).contains(bands.count) else { return "请保留 1–8 个颜色区间。" }
        guard bands.first?.minimumSpeed == 0 else { return "第一个区间必须从 0 开始。" }
        for (index, band) in bands.enumerated() {
            guard band.minimumSpeed.isFinite, (0...100_000).contains(band.minimumSpeed) else {
                return "第 \(index + 1) 档的起点需为 0–100000 之间的数字。"
            }
            if index > 0, band.minimumSpeed <= bands[index - 1].minimumSpeed {
                return "第 \(index + 1) 档的起点必须大于上一档；区间按起点递增。"
            }
            guard band.hex.count == 7, band.hex.first == "#",
                  band.hex.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                return "第 \(index + 1) 档的颜色需为 #RRGGBB，例如 #FF492E。"
            }
        }
        return nil
    }

    func color(for speed: Double) -> SIMD3<Float> {
        let rate = speed.isFinite ? max(0, speed) : 0
        return (bands.last(where: { rate >= $0.minimumSpeed }) ?? Self.standard.bands[0]).rgb
    }

    var previewMaximum: Double { max(180, (bands.last?.minimumSpeed ?? 0) * 1.25 + 20) }

    var sampleRates: [Double] {
        [0] + bands.indices.map { index in
            let start = bands[index].minimumSpeed
            let end = index + 1 < bands.count ? bands[index + 1].minimumSpeed : previewMaximum
            return (start + end) / 2
        }
    }
}

extension Notification.Name {
    static let emberCatFlameSettingsChanged = Notification.Name("EmberCat.FlameSettingsChanged")
}

@MainActor
final class NotchFlameSettings {
    static let shared = NotchFlameSettings()
    private let defaults: UserDefaults
    private(set) var palette: NotchFlamePalette
    private(set) var appearance: NotchFlameAppearance
    private(set) var matrixConfiguration: NotchMatrixConfiguration

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "notchFlamePalette"),
           let saved = try? JSONDecoder().decode(NotchFlamePalette.self, from: data),
           saved.validationError == nil {
            palette = saved
        } else {
            palette = .standard
        }
        if let data = defaults.data(forKey: "notchFlameAppearance"),
           let saved = try? JSONDecoder().decode(NotchFlameAppearance.self, from: data),
           saved.validationError == nil {
            appearance = saved
        } else {
            appearance = .standard
        }
        if let data = defaults.data(forKey: "notchMatrixConfiguration"),
           let saved = try? JSONDecoder().decode(NotchMatrixConfiguration.self, from: data),
           saved.validationError == nil {
            matrixConfiguration = saved
        } else {
            matrixConfiguration = .standard
        }
    }

    @discardableResult
    func setMatrixConfiguration(_ configuration: NotchMatrixConfiguration) -> Bool {
        guard configuration.validationError == nil,
              let data = try? JSONEncoder().encode(configuration) else { return false }
        guard configuration != matrixConfiguration else { return true }
        matrixConfiguration = configuration
        defaults.set(data, forKey: "notchMatrixConfiguration")
        NotificationCenter.default.post(name: .emberCatFlameSettingsChanged, object: self)
        return true
    }

    @discardableResult
    func setPalette(_ palette: NotchFlamePalette) -> Bool {
        setConfiguration(palette: palette, appearance: appearance)
    }

    @discardableResult
    func setAppearance(_ appearance: NotchFlameAppearance) -> Bool {
        setConfiguration(palette: palette, appearance: appearance)
    }

    @discardableResult
    func setConfiguration(palette: NotchFlamePalette, appearance: NotchFlameAppearance) -> Bool {
        guard palette.validationError == nil, appearance.validationError == nil else { return false }
        let canonical = NotchFlamePalette(bands: palette.bands.map {
            NotchFlameBand(minimumSpeed: $0.minimumSpeed, hex: $0.hex.uppercased())
        })
        guard let data = try? JSONEncoder().encode(canonical),
              let appearanceData = try? JSONEncoder().encode(appearance) else { return false }
        guard canonical != self.palette || appearance != self.appearance else { return true }
        self.palette = canonical
        self.appearance = appearance
        defaults.set(data, forKey: "notchFlamePalette")
        defaults.set(appearanceData, forKey: "notchFlameAppearance")
        NotificationCenter.default.post(name: .emberCatFlameSettingsChanged, object: self)
        return true
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "notchFlamesEnabled") as? Bool ?? true }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: "notchFlamesEnabled")
            NotificationCenter.default.post(name: .emberCatFlameSettingsChanged, object: self)
        }
    }

    var effect: NotchEffectStyle {
        get { defaults.string(forKey: "notchEffectStyle").flatMap(NotchEffectStyle.init(rawValue:)) ?? .flame }
        set {
            guard newValue != effect else { return }
            defaults.set(newValue.rawValue, forKey: "notchEffectStyle")
            NotificationCenter.default.post(name: .emberCatFlameSettingsChanged, object: self)
        }
    }
}
