import AppKit

/// A tiny floating loading indicator shown near the mouse cursor while processing.
@MainActor
final class StatusHUD {
    static let shared = StatusHUD()

    private var window: NSPanel?
    private var spinnerView: RingSpinnerView?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func showLoading() {
        dismissTask?.cancel()
        dismissTask = nil

        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            window = panel
        }

        guard let panel = window else { return }

        let size: CGFloat = 14
        if spinnerView == nil {
            spinnerView = RingSpinnerView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        }

        guard let spinnerView else { return }
        spinnerView.startAnimating()

        panel.contentView = spinnerView
        panel.setContentSize(NSSize(width: size, height: size))

        // Position just above mouse cursor
        let mouse = NSEvent.mouseLocation
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let x = round((mouse.x - size / 2) * scale) / scale
        let y = round((mouse.y + 8) * scale) / scale
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)

        // Safety auto-dismiss in case flow is interrupted.
        let delay: UInt64 = 10_000_000_000
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.hide() }
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        window?.orderOut(nil)
    }
}

private final class RingSpinnerView: NSView {
    private let ringLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor(red: 0.06, green: 0.52, blue: 0.98, alpha: 1.0).cgColor
        ringLayer.lineWidth = 2.6
        ringLayer.lineCap = .round
        ringLayer.strokeStart = 0.0
        ringLayer.strokeEnd = 0.46
        ringLayer.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "frame": NSNull()]
        layer?.addSublayer(ringLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        ringLayer.frame = bounds
        let inset = ringLayer.lineWidth / 2 + 0.3
        let circleRect = bounds.insetBy(dx: inset, dy: inset)
        ringLayer.path = CGPath(ellipseIn: circleRect, transform: nil)
    }

    func startAnimating() {
        if ringLayer.animation(forKey: "ring.spin") != nil { return }

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 0.85
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        ringLayer.add(spin, forKey: "ring.spin")
    }
}
