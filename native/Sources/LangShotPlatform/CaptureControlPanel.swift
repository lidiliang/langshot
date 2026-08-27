import AppKit

@MainActor
public final class CaptureControlPanelController: NSObject {
    private let window: NSPanel
    private let statusLabel = NSTextField(labelWithString: "长截图中…")
    private let shortcutLabel = NSTextField(labelWithString: "Esc 暂停 · Enter 完成")
    private let toggleButton = NSButton(title: "暂停", target: nil, action: nil)
    private let finishButton = NSButton(title: "完成", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let onTogglePause: () -> Void
    private let onFinish: () -> Void
    private let onCancel: () -> Void

    public init(screen: NSScreen, onTogglePause: @escaping () -> Void, onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onTogglePause = onTogglePause
        self.onFinish = onFinish
        self.onCancel = onCancel
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 126),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init()
        configureWindow(on: screen)
        configureContent()
    }

    public func show() {
        window.orderFrontRegardless()
    }

    public func update(status: String, paused: Bool, finishing: Bool = false) {
        statusLabel.stringValue = status
        toggleButton.title = paused ? "继续" : "暂停"
        toggleButton.isEnabled = !finishing
        finishButton.isEnabled = !finishing
        cancelButton.isEnabled = !finishing
        shortcutLabel.stringValue = finishing ? "正在生成图片，请稍候…" : (paused ? "Space 继续 · Enter 完成 · Esc 取消" : "Esc 暂停 · Enter 完成")
    }

    public func close() { window.orderOut(nil) }

    private func configureWindow(on screen: NSScreen) {
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.96)
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.maxX - window.frame.width - 18, y: visible.maxY - window.frame.height - 18))
    }

    private func configureContent() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 126))
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor(calibratedRed: 0.24, green: 0.55, blue: 1, alpha: 0.45).cgColor

        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.lineBreakMode = .byTruncatingTail
        shortcutLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = NSColor(calibratedWhite: 0.72, alpha: 1)

        configureButton(toggleButton, action: #selector(togglePause), emphasized: false)
        configureButton(finishButton, action: #selector(finish), emphasized: true)
        configureButton(cancelButton, action: #selector(cancel), emphasized: false)

        let textStack = NSStackView(views: [statusLabel, shortcutLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        let buttonStack = NSStackView(views: [toggleButton, finishButton, cancelButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        let root = NSStackView(views: [textStack, buttonStack])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -14)
        ])
        window.contentView = content
    }

    private func configureButton(_ button: NSButton, action: Selector, emphasized: Bool) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 12, weight: emphasized ? .semibold : .regular)
        if emphasized { button.contentTintColor = NSColor(calibratedRed: 0.24, green: 0.55, blue: 1, alpha: 1) }
    }

    @objc private func togglePause() { onTogglePause() }
    @objc private func finish() { onFinish() }
    @objc private func cancel() { onCancel() }
}
