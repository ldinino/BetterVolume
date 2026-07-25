import AppKit
import AudioHAL

/// The volume row at the top of the menu.
///
/// When the current device has no volume control the slider is shown maxed and disabled, which
/// is exactly what macOS's own Sound menu does for USB and HDMI outputs.
@MainActor
final class VolumeMenuItemView: NSView {
    private let slider = NSSlider()
    private let iconView = NSImageView()
    private let onChange: (Float) -> Void

    init(control: VolumeControl?, onChange: @escaping (Float) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 30))

        iconView.frame = NSRect(x: 14, y: 7, width: 16, height: 16)
        iconView.image = DeviceSymbol.image(named: control == nil ? "speaker.slash" : "speaker.wave.2.fill",
                                            description: "Volume",
                                            pointSize: 12)
        iconView.contentTintColor = .secondaryLabelColor
        addSubview(iconView)

        slider.frame = NSRect(x: 38, y: 5, width: 188, height: 20)
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = Double(control?.value ?? 1)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isEnabled = control != nil
        if control == nil {
            toolTip = "This output has no volume control — macOS can't change its level either."
        }
        addSubview(slider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func sliderChanged(_ sender: NSSlider) {
        onChange(Float(sender.doubleValue))
    }
}
