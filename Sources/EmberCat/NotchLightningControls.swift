import AppKit

/// Like the other effect controls, edits a local draft until Save and Apply.
@MainActor
final class NotchLightningControls: NSStackView {
    private(set) var configuration = NotchLightningConfiguration.standard
    private var sliders: [NSSlider] = []
    private var values: [NSTextField] = []
    private let reset = NSButton(title: "恢复默认", target: nil, action: nil)
    private let motion = NSButton(checkboxWithTitle: "悬浮与放电微颤", target: nil, action: nil)
    var onChange: ((NotchLightningConfiguration) -> Void)?

    init(configuration: NotchLightningConfiguration = .standard) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 10
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 860).isActive = true
        setAccessibilityIdentifier("lightning-controls")
        let hint = NSTextField(labelWithString: "拖动即时预览；参数修改在保存前只影响此窗口。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        reset.target = self
        reset.action = #selector(resetConfiguration)
        reset.controlSize = .small
        reset.toolTip = "恢复能量条、仓鼠与整体运动的默认参数；保存后应用。"
        reset.setAccessibilityIdentifier("lightning-style-reset")
        let header = NSStackView(views: [hint, spacer, reset])
        header.widthAnchor.constraint(equalToConstant: 860).isActive = true
        addArrangedSubview(header)
        var cards: [NSView] = []
        for (index, parameter) in NotchLightningParameter.visibleCases.enumerated() {
            let label = NSTextField(labelWithString: parameter.title)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.widthAnchor.constraint(equalToConstant: 84).isActive = true
            let slider = NSSlider(value: configuration[keyPath: parameter.keyPath],
                minValue: parameter.range.lowerBound, maxValue: parameter.range.upperBound,
                target: self, action: #selector(change(_:)))
            slider.isContinuous = true
            slider.tag = index
            slider.widthAnchor.constraint(equalToConstant: 236).isActive = true
            slider.setAccessibilityLabel(parameter.title)
            slider.setAccessibilityIdentifier("lightning-style-\(parameter.rawValue)")
            slider.toolTip = parameter.help
            let value = NSTextField(labelWithString: "")
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 64).isActive = true
            value.setAccessibilityIdentifier("lightning-style-\(parameter.rawValue)-value")
            let input = NSStackView(views: [label, slider, value])
            input.spacing = 8
            let help = NSTextField(labelWithString: parameter.help)
            help.font = .systemFont(ofSize: 11)
            help.textColor = .secondaryLabelColor
            let card = NSStackView(views: [input, help])
            card.orientation = .vertical
            card.alignment = .leading
            card.spacing = 4
            card.widthAnchor.constraint(equalToConstant: 418).isActive = true
            cards.append(card)
            sliders.append(slider)
            values.append(value)
        }
        motion.target = self
        motion.action = #selector(changeMotion)
        motion.toolTip = "启用自动匹配的悬浮与微颤；不改变内流、闪电或仓鼠播放。"
        motion.setAccessibilityIdentifier("lightning-motion-enabled")
        let motionHint = NSTextField(labelWithString: "自动配好悬浮与回弹，关闭后主体保持稳定。")
        motionHint.font = .systemFont(ofSize: 11)
        motionHint.textColor = .secondaryLabelColor
        let motionCard = NSStackView(views: [motion, motionHint])
        motionCard.orientation = .vertical
        motionCard.alignment = .leading
        motionCard.spacing = 4
        motionCard.widthAnchor.constraint(equalToConstant: 418).isActive = true
        cards.append(motionCard)
        let groups = NSStackView()
        groups.spacing = 24
        groups.alignment = .top
        for (group, title) in ["能量条与位置", "仓鼠与动效"].enumerated() {
            let heading = NSTextField(labelWithString: title)
            heading.font = .systemFont(ofSize: 12, weight: .semibold)
            heading.textColor = .secondaryLabelColor
            let column = NSStackView(views: [heading] + Array(cards[(group*4)..<(group*4+4)]))
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 12
            column.widthAnchor.constraint(equalToConstant: 418).isActive = true
            groups.addArrangedSubview(column)
        }
        addArrangedSubview(groups)
        reload(configuration)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(_ configuration: NotchLightningConfiguration) {
        self.configuration = configuration
        for (index, parameter) in NotchLightningParameter.visibleCases.enumerated() {
            sliders[index].doubleValue = configuration[keyPath: parameter.keyPath]
            values[index].stringValue = parameter.displayValue(sliders[index].doubleValue)
        }
        motion.state = configuration.motionEnabled ? .on : .off
        reset.isEnabled = configuration != .standard
    }

    @objc private func change(_ sender: NSSlider) {
        guard NotchLightningParameter.visibleCases.indices.contains(sender.tag) else { return }
        let parameter = NotchLightningParameter.visibleCases[sender.tag]
        var draft = configuration
        draft[keyPath: parameter.keyPath] = min(parameter.range.upperBound, max(parameter.range.lowerBound,
            sender.doubleValue))
        reload(draft)
        onChange?(draft)
    }

    @objc private func changeMotion() {
        var draft = configuration
        draft.motionEnabled = motion.state == .on
        reload(draft)
        onChange?(draft)
    }

    @objc private func resetConfiguration() {
        reload(.standard)
        onChange?(configuration)
    }
}
