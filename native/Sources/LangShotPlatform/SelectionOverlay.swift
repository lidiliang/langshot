import AppKit
import CoreGraphics
import LangShotCore

@MainActor
public final class SelectionOverlayController: NSObject {
    public typealias Confirmation = (NativeDisplay, RectValue, CGWindowID) -> Void

    private let display: NativeDisplay
    private let window: NSPanel
    private let overlayView: SelectionOverlayView
    private let onConfirm: Confirmation
    private let onCancel: () -> Void
    private var onAnchor: ((PointValue) -> Void)?

    public init(display: NativeDisplay, onConfirm: @escaping Confirmation, onCancel: @escaping () -> Void) {
        self.display = display
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        window = NSPanel(
            contentRect: display.screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: display.screen
        )
        overlayView = SelectionOverlayView(frame: NSRect(origin: .zero, size: display.screen.frame.size))
        super.init()
        configureWindow()
    }

    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeFirstResponder(overlayView)
    }

    public func close() { window.orderOut(nil) }

    private func configureWindow() {
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.contentView = overlayView
        overlayView.onConfirm = { [weak self] localRect in
            guard let self else { return }
            let frame = self.display.screen.frame
            let global = RectValue(
                x: frame.minX + localRect.minX,
                y: frame.maxY - localRect.maxY,
                width: localRect.width,
                height: localRect.height
            )
            self.onConfirm(self.display, global, CGWindowID(self.window.windowNumber))
        }
        overlayView.onCancel = { [weak self] in self?.onCancel() }
        overlayView.onAnchor = { [weak self] localPoint in
            guard let self else { return }
            let frame = self.display.screen.frame
            self.onAnchor?(PointValue(x: frame.minX + localPoint.x, y: frame.maxY - localPoint.y))
        }
    }

    public func requestAnchor(_ callback: @escaping (PointValue) -> Void) {
        onAnchor = callback
        overlayView.phase = .anchor
        overlayView.needsDisplay = true
    }

    public func beginCapturing(status: String) {
        overlayView.phase = .capturing
        overlayView.status = status
        overlayView.needsDisplay = true
        window.ignoresMouseEvents = true
    }

    public func updateStatus(_ status: String) {
        overlayView.status = status
        overlayView.needsDisplay = true
    }
}

@MainActor
private final class SelectionOverlayView: NSView {
    enum Phase { case selecting, anchor, capturing }
    var onConfirm: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?
    var onAnchor: ((NSPoint) -> Void)?
    var phase: Phase = .selecting
    var status = ""
    private var dragStart: NSPoint?
    private var selection: NSRect?
    private let minimumSize: CGFloat = 24

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if phase == .anchor {
            let point = convert(event.locationInWindow, from: nil)
            if selection?.contains(point) == true { onAnchor?(point) }
            return
        }
        guard phase == .selecting else { return }
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard phase == .selecting else { return }
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = normalizedRect(from: start, to: point).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        dragStart = nil
    }

    override func keyDown(with event: NSEvent) {
        guard phase == .selecting else {
            if event.keyCode == 53 { onCancel?() }
            return
        }
        switch event.keyCode {
        case 36, 76:
            if let selection, selection.width >= minimumSize, selection.height >= minimumSize { onConfirm?(selection) }
        case 53:
            onCancel?()
        case 123, 124, 125, 126:
            nudgeSelection(keyCode: event.keyCode, resize: event.modifierFlags.contains(.shift))
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.02, alpha: 0.58).setFill()
        bounds.fill()
        guard let selection else {
            drawHint("拖拽选择截图区域 · Esc 取消")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSGraphicsContext.restoreGraphicsState()
        let border = NSBezierPath(roundedRect: selection, xRadius: 2, yRadius: 2)
        border.lineWidth = 2
        NSColor(calibratedRed: 0.24, green: 0.55, blue: 1, alpha: 1).setStroke()
        border.stroke()
        drawHandles(selection)
        switch phase {
        case .selecting: drawHint("\(Int(selection.width)) × \(Int(selection.height)) pt · Enter 确认 · 方向键微调")
        case .anchor: drawHint("点击选区内需要滚动的位置")
        case .capturing: drawHint(status.isEmpty ? "长截图中…" : status)
        }
    }

    private func drawHandles(_ rect: NSRect) {
        NSColor.white.setFill()
        let points = [
            NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.midX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.midY), NSPoint(x: rect.maxX, y: rect.midY),
            NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.midX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)
        ]
        for point in points { NSBezierPath(ovalIn: NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill() }
    }

    private func drawHint(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(calibratedWhite: 0.05, alpha: 0.82)
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(x: bounds.midX - size.width / 2 - 10, y: 24, width: size.width + 20, height: size.height + 10)
        NSColor(calibratedWhite: 0.05, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: NSPoint(x: rect.minX + 10, y: rect.minY + 5), withAttributes: attributes)
    }

    private func nudgeSelection(keyCode: UInt16, resize: Bool) {
        guard var rect = selection else { return }
        let delta: CGFloat = 1
        if resize {
            if keyCode == 123 { rect.size.width -= delta }
            if keyCode == 124 { rect.size.width += delta }
            if keyCode == 125 { rect.size.height += delta }
            if keyCode == 126 { rect.size.height -= delta }
        } else {
            if keyCode == 123 { rect.origin.x -= delta }
            if keyCode == 124 { rect.origin.x += delta }
            if keyCode == 125 { rect.origin.y += delta }
            if keyCode == 126 { rect.origin.y -= delta }
        }
        rect = rect.intersection(bounds)
        if rect.width >= minimumSize, rect.height >= minimumSize { selection = rect; needsDisplay = true }
    }

    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}
