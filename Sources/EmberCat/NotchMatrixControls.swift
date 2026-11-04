import AppKit

/// Edits a preview draft. Persistence belongs to the preview controller's explicit save action.
@MainActor
final class NotchMatrixControls: NSStackView {
    private(set) var configuration = NotchMatrixConfiguration.standard
    private var sliders: [NSSlider] = []
    private var values: [NSTextField] = []
    private let reset = NSButton(title: "恢复默认", target: nil, action: nil)
    var onChange: ((NotchMatrixConfiguration) -> Void)?

    init(configuration: NotchMatrixConfiguration = .standard) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 8
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 860).isActive = true
        let hint = NSTextField(labelWithString: "拖动即时预览；参数修改在保存前只影响此窗口。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        reset.target = self
        reset.action = #selector(resetConfiguration)
        reset.controlSize = .small
        reset.toolTip = "恢复全部默认值；保存前只影响预览。"
        reset.setAccessibilityIdentifier("matrix-style-reset")
        let header = NSStackView(views: [hint, spacer, reset])
        header.spacing = 10
        header.widthAnchor.constraint(equalToConstant: 860).isActive = true
        addArrangedSubview(header)

        for (index, parameter) in NotchMatrixParameter.allCases.enumerated() {
            let label = NSTextField(labelWithString: parameter.title)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.widthAnchor.constraint(equalToConstant: 84).isActive = true
            let slider = NSSlider(value: configuration[keyPath: parameter.keyPath],
                minValue: parameter.range.lowerBound, maxValue: parameter.range.upperBound,
                target: self, action: #selector(change(_:)))
            slider.isContinuous = true
            slider.tag = index
            slider.widthAnchor.constraint(equalToConstant: 340).isActive = true
            slider.setAccessibilityLabel(parameter.title)
            slider.setAccessibilityIdentifier("matrix-style-\(parameter.rawValue)")
            slider.toolTip = parameter.help
            let value = NSTextField(labelWithString: "")
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 54).isActive = true
            value.setAccessibilityIdentifier("matrix-style-\(parameter.rawValue)-value")
            let help = NSTextField(wrappingLabelWithString: parameter.help)
            help.font = .systemFont(ofSize: 11)
            help.textColor = .secondaryLabelColor
            help.maximumNumberOfLines = 2
            help.widthAnchor.constraint(equalToConstant: 346).isActive = true
            let row = NSStackView(views: [label, slider, value, help])
            row.alignment = .centerY
            row.spacing = 12
            row.heightAnchor.constraint(equalToConstant: 38).isActive = true
            addArrangedSubview(row)
            sliders.append(slider)
            values.append(value)
        }
        reload(configuration)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(_ configuration: NotchMatrixConfiguration) {
        self.configuration = configuration
        for (index, parameter) in NotchMatrixParameter.allCases.enumerated() {
            sliders[index].doubleValue = configuration[keyPath: parameter.keyPath]
            values[index].stringValue = parameter.displayValue(sliders[index].doubleValue)
        }
        reset.isEnabled = configuration != .standard
    }

    @objc private func change(_ sender: NSSlider) {
        guard NotchMatrixParameter.allCases.indices.contains(sender.tag) else { return }
        let parameter = NotchMatrixParameter.allCases[sender.tag]
        let precision = parameter == .verticalOffset ? 1.0 : 100.0
        let rounded = (sender.doubleValue * precision).rounded() / precision
        var draft = configuration
        draft[keyPath: parameter.keyPath] = min(parameter.range.upperBound,
            max(parameter.range.lowerBound, rounded))
        reload(draft)
        onChange?(draft)
    }

    @objc private func resetConfiguration() {
        reload(.standard)
        onChange?(configuration)
    }
}
