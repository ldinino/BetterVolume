import AppKit
import AudioRouting

/// The brief "you're now on this output" panel, modelled on the system volume HUD: a blurred
/// rounded rectangle in the lower third that fades in, holds, and fades out.
///
/// It is a non-activating panel above the screen-saver level so it shows over full-screen apps —
/// the whole point when the switch came from the global shortcut inside a game.
@MainActor
final class OutputHUD {
    private let visibleDuration: TimeInterval = 1.1
    private let fadeIn: TimeInterval = 0.18
    private let fadeOut: TimeInterval = 0.35

    private lazy var panel = makePanel()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?
    /// Bumped on every show so a fade-out that is already running can't hide a newer one.
    private var generation = 0

    func show(symbolName: String, title: String) {
        generation += 1
        let shown = generation
        hideTask?.cancel()

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 40, weight: .regular))
        iconView.contentTintColor = .labelColor
        label.stringValue = title
        panel.setFrame(frame(), display: false)

        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        // One run-loop pass before animating: a window that has not yet drawn skips its first
        // alpha animation and snaps straight to the end value.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == shown else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = self.fadeIn
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 1
            }
        }

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.visibleDuration ?? 1.1))
            guard !Task.isCancelled else { return }
            self?.hide(ifStill: shown)
        }
    }

    // MARK: - Internals

    private func hide(ifStill shown: Int) {
        guard generation == shown else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeOut
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // The completion handler is not isolated, but AppKit only ever runs it on the main
            // thread, so hopping would just add a frame of delay before the panel goes away.
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    /// Shown on whichever screen the pointer is on, which is the one the user is looking at.
    private func frame() -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return .zero }

        // Measure after the new name is in place, or the panel is sized for the previous one.
        contentView.layoutSubtreeIfNeeded()
        let content = contentView.fittingSize
        let size = NSSize(width: min(max(content.width, 180), screen.frame.width - 40),
                          height: content.height)
        return HUDPlacement.frame(size: size, in: screen.frame)
    }

    private lazy var contentView: NSView = {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        // High rather than required: the panel grows to fit the name, but a long alias yields to
        // the 300pt cap below and truncates instead of stretching across the screen.
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // Explicit constraints rather than an NSStackView, and a fixed icon box rather than the
        // image's own size. `fittingSize` compresses whatever it is allowed to, and an
        // NSImageView resists only weakly, so the panel came out 25pt shorter than its contents
        // and the icon overlapped the name. The fixed box also keeps the panel one size for
        // every device: SF Symbols vary from 40 to 53pt tall at the same point size.
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 46),
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor,
                                              constant: 24),

            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor,
                                           constant: 24),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
        return container
    }()

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
                                    .ignoresCycle]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        // A layer corner radius does not round the *backdrop*: the window server still blurs
        // and composites the full rectangle, which shows up as square patches at the corners
        // over a light background. `maskImage` is the shape the effect view actually honours,
        // and the window shadow follows it too.
        blur.maskImage = Self.roundedMask(radius: 18)

        let content = contentView
        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])

        panel.contentView = blur
        return panel
    }

    /// A stretchable rounded rectangle: only the corners are drawn, the middle is tiled.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
