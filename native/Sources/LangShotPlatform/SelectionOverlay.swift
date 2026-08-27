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
            contentRect: NSRect(origin: .zero, size: display.screen.frame.size),
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
        window.setFrame(display.screen.frame, display: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.contentView = overlayView
        overlayView.onConfirm = { [weak self] localRect in
            guard let self else { return }
            let frame = self.display.geometry.pointBounds
            let global = RectValue(
                x: frame.minX + localRect.minX,
                y: frame.minY + localRect.minY,
                width: localRect.width,
                height: localRect.height
            )
            self.onConfirm(self.display, global, CGWindowID(self.window.windowNumber))
        }
        overlayView.onCancel = { [weak self] in self?.onCancel() }
        overlayView.onAnchor = { [weak self] localPoint in
            guard let self else { return }
            let frame = self.display.geometry.pointBounds
            self.onAnchor?(PointValue(x: frame.minX + localPoint.x, y: frame.minY + localPoint.y))
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
    private enum Handle { case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight }
    private enum DragMode { case drawing, moving(NSRect), resizing(Handle, NSRect) }
    var onConfirm: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?
    var onAnchor: ((NSPoint) -> Void)?
    var phase: Phase = .selecting
    var status = ""
    private var dragStart: NSPoint?
    private var dragMode: DragMode?
    private var selection: NSRect?
    private let minimumSize: CGFloat = 24
    private let toolbar = NSStackView()
    private let confirmButton = NSButton(title: "确认选区", target: nil, action: nil)
    private let resetButton = NSButton(title: "重新框选", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.94).cgColor
        toolbar.layer?.cornerRadius = 10
        configureButton(confirmButton, action: #selector(confirmSelection), primary: true)
        configureButton(resetButton, action: #selector(resetSelection), primary: false)
        configureButton(cancelButton, action: #selector(cancelSelection), primary: false)
        toolbar.addArrangedSubview(confirmButton)
        toolbar.addArrangedSubview(resetButton)
        toolbar.addArrangedSubview(cancelButton)
        toolbar.isHidden = true
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if phase == .anchor {
            let point = convert(event.locationInWindow, from: nil)
            if selection?.contains(point) == true { onAnchor?(point) }
            return
        }
        guard phase == .selecting else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        if let selection, let handle = hitHandle(at: point, selection: selection) {
            dragMode = .resizing(handle, selection)
        } else if let selection, selection.contains(point) {
            dragMode = .moving(selection)
        } else {
            dragMode = .drawing
            selection = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard phase == .selecting else { return }
        guard let start = dragStart, let dragMode else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .drawing:
            selection = normalizedRect(from: start, to: point).intersection(bounds)
        case let .moving(original):
            selection = move(original, dx: point.x - start.x, dy: point.y - start.y)
        case let .resizing(handle, original):
            selection = resize(original, handle: handle, to: point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        dragStart = nil
        dragMode = nil
        updateToolbar()
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
            toolbar.isHidden = true
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
        case .selecting:
            updateToolbar()
            drawSelectionSize(selection)
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

    private func drawSelectionSize(_ rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height)) pt"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        let y = rect.minY > 28 ? rect.minY - 22 : min(bounds.maxY - 22, rect.maxY + 7)
        text.draw(at: NSPoint(x: rect.minX, y: y), withAttributes: attributes)
    }

    private func configureButton(_ button: NSButton, action: Selector, primary: Bool) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 12, weight: primary ? .semibold : .regular)
        if primary { button.contentTintColor = NSColor(calibratedRed: 0.24, green: 0.55, blue: 1, alpha: 1) }
    }

    private func updateToolbar() {
        guard phase == .selecting, let selection, selection.width >= minimumSize, selection.height >= minimumSize else {
            toolbar.isHidden = true
            return
        }
        toolbar.isHidden = false
        toolbar.layoutSubtreeIfNeeded()
        let size = toolbar.fittingSize
        let x = min(max(10, selection.maxX - size.width), bounds.maxX - size.width - 10)
        var y = selection.maxY + 10
        if y + size.height > bounds.maxY - 10 { y = max(10, selection.minY - size.height - 10) }
        toolbar.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    @objc private func confirmSelection() {
        guard let selection, selection.width >= minimumSize, selection.height >= minimumSize else { return }
        toolbar.isHidden = true
        onConfirm?(selection)
    }

    @objc private func resetSelection() {
        selection = nil
        toolbar.isHidden = true
        needsDisplay = true
    }

    @objc private func cancelSelection() { onCancel?() }

    private func hitHandle(at point: NSPoint, selection: NSRect) -> Handle? {
        let candidates: [(Handle, NSPoint)] = [
            (.topLeft, NSPoint(x: selection.minX, y: selection.minY)), (.top, NSPoint(x: selection.midX, y: selection.minY)),
            (.topRight, NSPoint(x: selection.maxX, y: selection.minY)), (.left, NSPoint(x: selection.minX, y: selection.midY)),
            (.right, NSPoint(x: selection.maxX, y: selection.midY)), (.bottomLeft, NSPoint(x: selection.minX, y: selection.maxY)),
            (.bottom, NSPoint(x: selection.midX, y: selection.maxY)), (.bottomRight, NSPoint(x: selection.maxX, y: selection.maxY))
        ]
        return candidates.first { abs($0.1.x - point.x) <= 10 && abs($0.1.y - point.y) <= 10 }?.0
    }

    private func move(_ original: NSRect, dx: CGFloat, dy: CGFloat) -> NSRect {
        let x = min(max(bounds.minX, original.minX + dx), bounds.maxX - original.width)
        let y = min(max(bounds.minY, original.minY + dy), bounds.maxY - original.height)
        return NSRect(x: x, y: y, width: original.width, height: original.height)
    }

    private func resize(_ original: NSRect, handle: Handle, to point: NSPoint) -> NSRect {
        var left = original.minX, right = original.maxX, top = original.minY, bottom = original.maxY
        switch handle {
        case .topLeft: left = point.x; top = point.y
        case .top: top = point.y
        case .topRight: right = point.x; top = point.y
        case .left: left = point.x
        case .right: right = point.x
        case .bottomLeft: left = point.x; bottom = point.y
        case .bottom: bottom = point.y
        case .bottomRight: right = point.x; bottom = point.y
        }
        left = min(max(bounds.minX, left), right - minimumSize)
        right = max(min(bounds.maxX, right), left + minimumSize)
        top = min(max(bounds.minY, top), bottom - minimumSize)
        bottom = max(min(bounds.maxY, bottom), top + minimumSize)
        return NSRect(x: left, y: top, width: right - left, height: bottom - top)
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
