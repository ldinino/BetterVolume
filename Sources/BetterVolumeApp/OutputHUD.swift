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
    private let fadeIn: TimeInterval = 0.12
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeIn
            panel.animator().alphaValue = 1
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
            guard let self, generation == shown else { return }
            panel.orderOut(nil)
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
        return HUDPlacement.frame(size: size, in: screen.frame)    }

    private lazy var contentView: NSView = {
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setContentCompressionResistancePriority(.required, for: .vertical)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        // Without a ceiling a long alias stretches the panel across the screen; with one the
        // name truncates instead.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        return stack
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
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true

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
}
