import AppKit
import CoreGraphics
import LangShotCore

@MainActor
public final class SelectionOverlayController: NSObject {
    public typealias Confirmation = (NativeDisplay, RectValue, CGWindowID, CaptureMode, ScrollDirection) -> Void

    private let display: NativeDisplay
    private let window: NSPanel
    private let overlayView: SelectionOverlayView
    private let candidateService = SelectionCandidateService()
    private let candidateQueue = DispatchQueue(label: "app.langshot.selection-candidate", qos: .userInteractive)
    private let onConfirm: Confirmation
    private let onCancel: () -> Void
    private var onAnchor: ((PointValue) -> Void)?
    private var captureControls: CaptureControlPanelController?
    private var candidateGeneration = 0
    private var candidateLookupInFlight = false
    private var pendingCandidatePoint: NSPoint?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var isActive = false
    private var selectionFrameOnScreen: NSRect?

    public init(display: NativeDisplay, frozenDisplayImage: CGImage? = nil, preferredMode: CaptureMode = .simple, preferredDirection: ScrollDirection = .down, onConfirm: @escaping Confirmation, onCancel: @escaping () -> Void) {
        self.display = display
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        window = NSPanel(
            contentRect: NSRect(origin: .zero, size: display.screen.frame.size),
            // Keep the target application active while the selection UI is
            // visible. Activating the helper dismisses transient UI such as
            // menus, popovers, and drop-down lists before it can be captured.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: display.screen
        )
        overlayView = SelectionOverlayView(
            frame: NSRect(origin: .zero, size: display.screen.frame.size),
            frozenDisplayImage: frozenDisplayImage,
            preferredMode: preferredMode,
            preferredDirection: preferredDirection
        )
        super.init()
        configureWindow()
    }

    public func show() {
        isActive = true
        installSelectionKeyMonitors()
        // A nonactivating panel can receive selection input without moving
        // application focus away from the content being captured.
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayView)
    }

    public func close() {
        isActive = false
        removeSelectionKeyMonitors()
        captureControls?.close()
        captureControls = nil
        window.orderOut(nil)
    }

    private func configureWindow() {
        window.level = .screenSaver
        window.setFrame(display.screen.frame, display: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.contentView = overlayView
        overlayView.onConfirm = { [weak self] localRect, mode, direction in
            guard let self else { return }
            let frame = self.display.geometry.pointBounds
            let global = RectValue(
                x: frame.minX + localRect.minX,
                y: frame.minY + localRect.minY,
                width: localRect.width,
                height: localRect.height
            )
            let screenFrame = self.display.screen.frame
            self.selectionFrameOnScreen = NSRect(
                x: screenFrame.minX + localRect.minX,
                y: screenFrame.maxY - localRect.maxY,
                width: localRect.width,
                height: localRect.height
            )
            self.onConfirm(self.display, global, CGWindowID(self.window.windowNumber), mode, direction)
        }
        overlayView.onCancel = { [weak self] in self?.cancelSelection() }
        overlayView.onHover = { [weak self] point in self?.resolveCandidate(at: point) }
        overlayView.onAnchor = { [weak self] localPoint in
            guard let self else { return }
            let frame = self.display.geometry.pointBounds
            self.onAnchor?(PointValue(x: frame.minX + localPoint.x, y: frame.minY + localPoint.y))
        }
    }

    private func resolveCandidate(at localPoint: NSPoint) {
        pendingCandidatePoint = localPoint
        startCandidateLookupIfNeeded()
    }

    private func startCandidateLookupIfNeeded() {
        guard !candidateLookupInFlight, let localPoint = pendingCandidatePoint else { return }
        pendingCandidatePoint = nil
        candidateLookupInFlight = true
        candidateGeneration += 1
        let generation = candidateGeneration
        let pointBounds = display.geometry.pointBounds
        let displayBounds = CGRect(
            x: pointBounds.origin.x,
            y: pointBounds.origin.y,
            width: pointBounds.size.width,
            height: pointBounds.size.height
        )
        let globalPoint = CGPoint(x: displayBounds.minX + localPoint.x, y: displayBounds.minY + localPoint.y)
        let service = candidateService
        candidateQueue.async { [weak self] in
            let candidate = service.candidate(at: globalPoint, inside: displayBounds)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.candidateLookupInFlight = false
                if generation == self.candidateGeneration, self.pendingCandidatePoint == nil {
                    let localRect = candidate.map {
                        NSRect(x: $0.rect.minX - displayBounds.minX, y: $0.rect.minY - displayBounds.minY, width: $0.rect.width, height: $0.rect.height)
                    }
                    self.overlayView.updateCandidate(localRect, source: candidate?.source)
                }
                self.startCandidateLookupIfNeeded()
            }
        }
    }

    public func requestAnchor(_ callback: @escaping (PointValue) -> Void) {
        onAnchor = callback
        overlayView.hideSelectionToolbar()
        overlayView.phase = .anchor
        overlayView.needsDisplay = true
    }

    public func beginCapturing(mode: CaptureMode, status: String, onTogglePause: @escaping () -> Void, onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        removeSelectionKeyMonitors()
        window.resignKey()
        overlayView.releaseFrozenDisplayImage()
        overlayView.phase = .capturing
        overlayView.hideSelectionToolbar()
        overlayView.status = status
        overlayView.needsDisplay = true
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        if mode == .simple {
            window.orderFrontRegardless()
            return
        }
        captureControls = CaptureControlPanelController(
            screen: display.screen,
            selectionFrame: selectionFrameOnScreen ?? display.screen.visibleFrame,
            onTogglePause: onTogglePause,
            onFinish: onFinish,
            onCancel: onCancel
        )
        captureControls?.update(status: status, paused: false)
        captureControls?.show()
        window.orderFrontRegardless()
    }

    public func ensureCaptureUIVisible() {
        guard overlayView.phase == .capturing else { return }
        window.orderFrontRegardless()
        captureControls?.show()
    }

    public func updateStatus(_ status: String, paused: Bool = false, finishing: Bool = false, recoveryExhausted: Bool = false) {
        overlayView.status = status
        overlayView.needsDisplay = true
        captureControls?.update(status: status, paused: paused, finishing: finishing, recoveryExhausted: recoveryExhausted)
    }

    private func installSelectionKeyMonitors() {
        removeSelectionKeyMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleSelectionKey(event) == true ? nil : event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleSelectionKey(event)
        }
    }

    private func handleSelectionKey(_ event: NSEvent) -> Bool {
        guard event.isARepeat == false else { return false }
        switch event.keyCode {
        case 36, 76:
            return overlayView.confirmCurrentSelection()
        case 53:
            cancelSelection()
            return true
        default:
            return false
        }
    }

    private func removeSelectionKeyMonitors() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor); self.localKeyMonitor = nil }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor); self.globalKeyMonitor = nil }
    }

    private func cancelSelection() {
        guard isActive else { return }
        isActive = false
        removeSelectionKeyMonitors()
        onCancel()
    }
}

@MainActor
private final class SelectionOverlayView: NSView {
    enum Phase { case selecting, anchor, capturing }
    private enum Handle { case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight }
    private enum DragMode { case drawing, moving(NSRect), resizing(Handle, NSRect) }
    var onConfirm: ((NSRect, CaptureMode, ScrollDirection) -> Void)?
    var onCancel: (() -> Void)?
    var onAnchor: ((NSPoint) -> Void)?
    var onHover: ((NSPoint) -> Void)?
    var phase: Phase = .selecting
    var status = ""
    private var dragStart: NSPoint?
    private var dragMode: DragMode?
    private var selection: NSRect?
    private var hoverCandidate: NSRect?
    private var hoverSource: SelectionCandidate.Source?
    private var clickCandidate: NSRect?
    private var selectedMode: CaptureMode
    private var selectedDirection: ScrollDirection
    private var frozenDisplayImage: NSImage?
    private let minimumSize: CGFloat = 24
    private let toolbar = NSStackView()
    private let simpleModeButton = NSButton(title: "立即截图", target: nil, action: nil)
    private let automaticModeButton = NSButton(title: "自动滚动截图", target: nil, action: nil)
    private let manualModeButton = NSButton(title: "手动滚动截图", target: nil, action: nil)
    private let downButton = NSButton(title: "向下", target: nil, action: nil)
    private let upButton = NSButton(title: "向上", target: nil, action: nil)
    private let resetButton = NSButton(title: "重新框选", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    init(frame frameRect: NSRect, frozenDisplayImage: CGImage?, preferredMode: CaptureMode, preferredDirection: ScrollDirection) {
        selectedMode = preferredMode
        selectedDirection = preferredDirection
        self.frozenDisplayImage = frozenDisplayImage.map { NSImage(cgImage: $0, size: frameRect.size) }
        super.init(frame: frameRect)
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.94).cgColor
        toolbar.layer?.cornerRadius = 10
        configureChoiceButton(simpleModeButton, action: #selector(startSimpleCapture), minimumWidth: 72)
        configureChoiceButton(automaticModeButton, action: #selector(startAutomaticCapture), minimumWidth: 96)
        configureChoiceButton(manualModeButton, action: #selector(startManualCapture), minimumWidth: 96)
        configureChoiceButton(downButton, action: #selector(selectDownDirection), minimumWidth: 44)
        configureChoiceButton(upButton, action: #selector(selectUpDirection), minimumWidth: 44)
        configureButton(resetButton, action: #selector(resetSelection), primary: false)
        configureButton(cancelButton, action: #selector(cancelSelection), primary: false)
        for button in [simpleModeButton, automaticModeButton, manualModeButton, downButton, upButton, resetButton, cancelButton] {
            toolbar.addArrangedSubview(button)
        }
        refreshButtonStyles()
        toolbar.isHidden = true
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        guard phase == .selecting, selection == nil, dragMode == nil else { return }
        onHover?(convert(event.locationInWindow, from: nil))
    }

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
            clickCandidate = selection == nil ? hoverCandidate : nil
            if selection != nil { selection = nil }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard phase == .selecting else { return }
        guard let start = dragStart, let dragMode else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .drawing:
            let rect = normalizedRect(from: start, to: point).intersection(bounds)
            if rect.width >= 3 || rect.height >= 3 {
                hoverCandidate = nil
                hoverSource = nil
                selection = rect
            }
        case let .moving(original):
            selection = move(original, dx: point.x - start.x, dy: point.y - start.y)
        case let .resizing(handle, original):
            selection = resize(original, handle: handle, to: point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        let endPoint = convert(event.locationInWindow, from: nil)
        let movedEnough = dragStart.map { hypot(endPoint.x - $0.x, endPoint.y - $0.y) >= 3 } ?? false
        var shouldAutoConfirm = false
        if case .drawing = dragMode {
            if movedEnough, let selection, selection.width >= minimumSize, selection.height >= minimumSize {
                hoverCandidate = nil
                hoverSource = nil
                shouldAutoConfirm = true
            } else if let clickCandidate, clickCandidate.contains(endPoint) {
                selection = clickCandidate
                hoverCandidate = nil
                hoverSource = nil
            } else {
                selection = nil
            }
        } else if movedEnough, let selection, selection.width >= minimumSize, selection.height >= minimumSize {
            shouldAutoConfirm = true
        }
        dragStart = nil
        dragMode = nil
        clickCandidate = nil
        if shouldAutoConfirm { hoverCandidate = nil; hoverSource = nil }
        updateToolbar()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard phase == .selecting else {
            if event.keyCode == 53 { onCancel?() }
            return
        }
        switch event.keyCode {
        case 36, 76:
            confirmSelection()
        case 53:
            onCancel?()
        case 123, 124, 125, 126:
            nudgeSelection(keyCode: event.keyCode, resize: event.modifierFlags.contains(.shift))
        default:
            super.keyDown(with: event)
        }
    }

    func confirmCurrentSelection() -> Bool {
        guard phase == .selecting,
              let selection,
              selection.width >= minimumSize,
              selection.height >= minimumSize else { return false }
        confirmSelection()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawFrozenDisplayImage()
        NSColor(calibratedWhite: 0.02, alpha: 0.58).setFill()
        bounds.fill()
        guard let visibleRect = selection ?? hoverCandidate else {
            toolbar.isHidden = true
            drawHint("移动鼠标智能选择 · 拖拽自由框选 · Esc 取消")
            return
        }
        if frozenDisplayImage != nil {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: visibleRect).addClip()
            drawFrozenDisplayImage()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSColor.clear.setFill()
            visibleRect.fill(using: .copy)
            NSGraphicsContext.restoreGraphicsState()
        }
        let border = NSBezierPath(roundedRect: visibleRect, xRadius: 2, yRadius: 2)
        border.lineWidth = 2
        NSColor(calibratedRed: 0.24, green: 0.55, blue: 1, alpha: 1).setStroke()
        border.stroke()
        if selection != nil { drawHandles(visibleRect) }
        switch phase {
        case .selecting:
            if selection != nil {
                updateToolbar()
                drawSelectionSize(visibleRect)
            } else {
                toolbar.isHidden = true
                let kind = hoverSource == .accessibilityElement ? "元素" : "窗口"
                drawHint("已推荐\(kind) · 单击锁定 · 拖拽自由框选")
            }
        case .anchor: drawHint("点击选区内需要滚动的位置", near: visibleRect)
        case .capturing: break
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

    private func drawHint(_ text: String, near selection: NSRect? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(calibratedWhite: 0.05, alpha: 0.82)
        ]
        let size = text.size(withAttributes: attributes)
        let width = size.width + 20
        let height = size.height + 10
        let x = selection.map { min(max(10, $0.midX - width / 2), bounds.maxX - width - 10) } ?? (bounds.midX - width / 2)
        var y: CGFloat = 24
        if let selection {
            y = selection.minY - height - 10
            if y < 10 { y = min(bounds.maxY - height - 10, selection.maxY + 10) }
        }
        let rect = NSRect(x: x, y: y, width: width, height: height)
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
        button.isBordered = false
        button.controlSize = .regular
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.borderWidth = 1
        button.layer?.backgroundColor = (primary
            ? NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.98, alpha: 1)
            : NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.24, alpha: 1)).cgColor
        button.layer?.borderColor = (primary
            ? NSColor(calibratedRed: 0.38, green: 0.65, blue: 1, alpha: 1)
            : NSColor(calibratedRed: 0.30, green: 0.38, blue: 0.52, alpha: 0.72)).cgColor
        button.contentTintColor = primary ? .white : NSColor(calibratedRed: 0.82, green: 0.87, blue: 0.96, alpha: 1)
        button.font = NSFont.systemFont(ofSize: 12, weight: primary ? .semibold : .regular)
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func configureChoiceButton(_ button: NSButton, action: Selector, minimumWidth: CGFloat) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.controlSize = .regular
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.borderWidth = 1
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth).isActive = true
    }

    private func refreshButtonStyles() {
        styleChoiceButton(simpleModeButton, selected: selectedMode == .simple)
        styleChoiceButton(automaticModeButton, selected: selectedMode == .automatic)
        styleChoiceButton(manualModeButton, selected: selectedMode == .manual)
        styleChoiceButton(downButton, selected: selectedDirection == .down)
        styleChoiceButton(upButton, selected: selectedDirection == .up)
    }

    private func styleChoiceButton(_ button: NSButton, selected: Bool) {
        button.layer?.backgroundColor = (selected
            ? NSColor(calibratedRed: 0.18, green: 0.47, blue: 0.98, alpha: 1)
            : NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.24, alpha: 1)).cgColor
        button.layer?.borderColor = (selected
            ? NSColor(calibratedRed: 0.48, green: 0.72, blue: 1, alpha: 1)
            : NSColor(calibratedRed: 0.27, green: 0.36, blue: 0.50, alpha: 0.72)).cgColor
        button.contentTintColor = selected ? .white : NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.92, alpha: 1)
        button.font = NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .medium)
    }

    private func updateToolbar() {
        guard phase == .selecting, let selection, selection.width >= minimumSize, selection.height >= minimumSize else {
            toolbar.isHidden = true
            return
        }
        toolbar.isHidden = false
        refreshButtonStyles()
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
        onConfirm?(selection, selectedMode, selectedDirection)
    }

    @objc private func startSimpleCapture() { startCapture(mode: .simple) }
    @objc private func startAutomaticCapture() { startCapture(mode: .automatic) }
    @objc private func startManualCapture() { startCapture(mode: .manual) }

    private func startCapture(mode: CaptureMode) {
        selectedMode = mode
        refreshButtonStyles()
        confirmSelection()
    }

    @objc private func selectDownDirection() { changeDirection(to: .down) }
    @objc private func selectUpDirection() { changeDirection(to: .up) }

    private func changeDirection(to direction: ScrollDirection) {
        selectedDirection = direction
        refreshButtonStyles()
    }

    func hideSelectionToolbar() { toolbar.isHidden = true }

    func releaseFrozenDisplayImage() {
        frozenDisplayImage = nil
        needsDisplay = true
    }

    private func drawFrozenDisplayImage() {
        frozenDisplayImage?.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    @objc private func resetSelection() {
        selection = nil
        hoverCandidate = nil
        hoverSource = nil
        toolbar.isHidden = true
        if let window {
            onHover?(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
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

    func updateCandidate(_ rect: NSRect?, source: SelectionCandidate.Source?) {
        guard phase == .selecting, selection == nil, dragMode == nil else { return }
        hoverCandidate = rect?.intersection(bounds)
        hoverSource = source
        needsDisplay = true
    }
}
