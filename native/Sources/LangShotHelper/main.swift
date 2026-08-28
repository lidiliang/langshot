import Foundation
import AppKit
import LangShotCore
import LangShotPlatform

final class ProtocolWriter: @unchecked Sendable {
    private let encoder = JSONEncoder()
    private let lock = NSLock()
    func write<T: Encodable>(_ value: T) {
        guard let data = try? encoder.encode(value), let line = String(data: data, encoding: .utf8) else { return }
        lock.lock(); defer { lock.unlock() }
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

final class HelperRuntime {
    private let writer: ProtocolWriter
    private let permissionService = PermissionService()
    private var overlay: SelectionOverlayController?
    private var engine: CaptureSessionEngine?
    private var sequence = 0
    private var activeSessionId: String?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var capturePaused = false

    init(writer: ProtocolWriter) {
        self.writer = writer
        _ = try? CaptureSessionEngine.cleanupExpiredResults()
    }

    @MainActor
    func handle(_ request: RequestEnvelope) {
        do {
            try request.validate()
            switch request.type {
            case "hello":
                respond(request, ["name": .string("langshot-helper"), "protocolVersion": .number(Double(langShotProtocolVersion))])
            case "permissions.get":
                let snapshot = permissionService.snapshot()
                respond(request, ["screenRecording": .bool(snapshot.screenRecording), "accessibility": .bool(snapshot.accessibility)])
            case "permissions.request":
                let kind = request.payload["kind"] == .string("accessibility") ? PermissionKind.accessibility : .screenRecording
                respond(request, ["granted": .bool(permissionService.request(kind))])
            case "permissions.openSettings":
                let kind: PermissionKind
                if request.payload["kind"] == .string("accessibility") {
                    kind = .accessibility
                } else if request.payload["kind"] == .string("screenRecording") {
                    kind = .screenRecording
                } else {
                    kind = request.payload["mode"] == .string("automatic") ? .accessibility : .screenRecording
                }
                permissionService.openSettings(kind)
                respond(request, [:])
            case "session.begin":
                beginSession(request)
            case "session.discard":
                discardSession(sessionId: activeSessionId)
                respond(request, [:])
            default:
                writer.write(ResponseEnvelope(requestId: request.requestId, error: ProtocolFailure(code: "UNIMPLEMENTED", message: "Request is not implemented yet: \(request.type)")))
            }
        } catch {
            writer.write(ResponseEnvelope(requestId: request.requestId, error: ProtocolFailure(code: "INVALID_REQUEST", message: "Malformed or incompatible request")))
        }
    }

    @MainActor
    private func beginSession(_ request: RequestEnvelope) {
        guard overlay == nil else {
            writer.write(ResponseEnvelope(requestId: request.requestId, error: ProtocolFailure(code: "SESSION_ACTIVE", message: "A capture session is already active")))
            return
        }
        guard permissionService.snapshot().screenRecording else {
            writer.write(ResponseEnvelope(requestId: request.requestId, error: ProtocolFailure(code: "SCREEN_PERMISSION_REQUIRED", message: "Screen recording permission is required")))
            return
        }
        guard let display = DisplayService().display(containing: NSEvent.mouseLocation) else {
            writer.write(ResponseEnvelope(requestId: request.requestId, error: ProtocolFailure(code: "NO_DISPLAY", message: "No display is available")))
            return
        }
        let sessionId = UUID().uuidString.lowercased()
        let preferredMode: CaptureMode
        switch request.payload["mode"] {
        case .string("automatic"): preferredMode = .automatic
        case .string("manual"): preferredMode = .manual
        default: preferredMode = .simple
        }
        let requestedDirection: ScrollDirection = request.payload["direction"] == .string("up") ? .up : .down
        activeSessionId = sessionId
        overlay = SelectionOverlayController(
            display: display,
            preferredMode: preferredMode,
            preferredDirection: requestedDirection,
            onConfirm: { [weak self] display, selection, windowID, mode, direction in
            guard let self else { return }
            let pixels = display.geometry.pixelRect(for: selection)
            self.emit("selection.confirmed", sessionId: sessionId, payload: [
                "displayId": .number(Double(display.geometry.id)),
                "x": .number(selection.origin.x), "y": .number(selection.origin.y),
                "width": .number(selection.size.width), "height": .number(selection.size.height),
                "pixelWidth": .number(Double(pixels?.width ?? 0)), "pixelHeight": .number(Double(pixels?.height ?? 0)),
                "overlayWindowId": .number(Double(windowID)),
                "mode": .string(mode.rawValue), "direction": .string(direction.rawValue)
            ])
            if mode == .automatic, !self.permissionService.snapshot().accessibility {
                self.overlay?.close()
                self.overlay = nil
                self.activeSessionId = nil
                self.emit("permission.required", sessionId: sessionId, payload: [
                    "mode": .string(mode.rawValue),
                    "permissions": .array([.string("accessibility")])
                ])
                return
            }
            if mode == .automatic {
                self.overlay?.requestAnchor { [weak self] anchor in
                    self?.startEngine(sessionId: sessionId, mode: mode, direction: direction, selection: selection, windowID: windowID, anchor: anchor)
                }
            } else {
                self.startEngine(sessionId: sessionId, mode: mode, direction: direction, selection: selection, windowID: windowID, anchor: nil)
            }
        },
            onCancel: { [weak self] in self?.discardSession(sessionId: sessionId) }
        )
        overlay?.show()
        respond(request, ["sessionId": .string(sessionId)])
    }

    @MainActor
    private func startEngine(sessionId: String, mode: CaptureMode, direction: ScrollDirection, selection: RectValue, windowID: CGWindowID, anchor: PointValue?) {
        installKeyMonitor(sessionId: sessionId)
        let targetPoint = anchor ?? PointValue(
            x: selection.origin.x + selection.size.width / 2,
            y: selection.origin.y + selection.size.height / 2
        )
        let targetPID = SelectionCandidateService().processIdentifier(at: CGPoint(x: targetPoint.x, y: targetPoint.y))
        engine = CaptureSessionEngine(
            sessionId: sessionId,
            mode: mode,
            requestedDirection: direction,
            selection: selection,
            overlayWindowId: windowID,
            anchor: anchor,
            targetProcessIdentifier: targetPID,
            progress: { [weak self] progress in
                guard let self else { return }
                let label = mode == .simple ? "正在截图…" : "长截图中… \(progress.height)px · \(progress.frames) 帧"
                self.overlay?.updateStatus(label, paused: self.capturePaused)
                self.emit("session.progress", sessionId: sessionId, payload: [
                    "height": .number(Double(progress.height)), "frames": .number(Double(progress.frames)), "confidence": .number(progress.confidence)
                ])
            },
            status: { [weak self] status in
                self?.handleEngineStatus(status, sessionId: sessionId, mode: mode)
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.engine = nil; self.removeKeyMonitor(); self.overlay?.close(); self.overlay = nil
                switch result {
                case let .success(result):
                    self.emit("session.completed", sessionId: sessionId, payload: [
                        "path": .string(result.url.path),
                        "warnings": .array(result.warnings.map { .string($0.rawValue) })
                    ])
                case let .failure(error): self.emit("error", sessionId: sessionId, payload: ["code": .string("CAPTURE_FAILED"), "message": .string(error.localizedDescription)])
                }
                self.activeSessionId = nil
            }
        )
        overlay?.beginCapturing(
            mode: mode,
            status: mode == .simple ? "正在截图…" : "长截图中… 0px · 0 帧",
            onTogglePause: { [weak self] in self?.togglePause(sessionId: sessionId) },
            onFinish: { [weak self] in self?.finishSession() },
            onCancel: { [weak self] in self?.discardSession(sessionId: sessionId) }
        )
        if let targetPID {
            NSRunningApplication(processIdentifier: targetPID)?.activate(options: [.activateIgnoringOtherApps])
        }
        overlay?.ensureCaptureUIVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.overlay?.ensureCaptureUIVisible()
        }
        engine?.start()
    }

    @MainActor
    private func installKeyMonitor(sessionId: String) {
        removeKeyMonitor()
        capturePaused = false
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleCaptureKey(event, sessionId: sessionId) ? nil : event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleCaptureKey(event, sessionId: sessionId)
        }
    }

    @MainActor
    private func handleCaptureKey(_ event: NSEvent, sessionId: String) -> Bool {
        guard !event.isARepeat else { return true }
        switch event.keyCode {
        case 53:
            if capturePaused { discardSession(sessionId: sessionId) }
            else { engine?.pause() }
            return true
        case 49 where capturePaused:
            engine?.resume()
            return true
        case 36, 76:
            finishSession()
            return true
        default:
            return false
        }
    }

    @MainActor
    private func togglePause(sessionId: String) {
        guard activeSessionId == sessionId else { return }
        if capturePaused { engine?.resume() }
        else { engine?.pause() }
    }

    @MainActor
    private func finishSession() { engine?.finishNow() }

    @MainActor
    private func discardSession(sessionId: String?) {
        guard let sessionId, activeSessionId == sessionId else { return }
        engine?.cancel(); engine = nil
        removeKeyMonitor()
        overlay?.close(); overlay = nil
        emit("session.cancelled", sessionId: sessionId)
        activeSessionId = nil
    }

    @MainActor
    private func handleEngineStatus(_ status: CaptureEngineStatus, sessionId: String, mode: CaptureMode) {
        switch status {
        case .running:
            let wasPaused = capturePaused
            capturePaused = false
            overlay?.updateStatus(mode == .simple ? "正在截图…" : "长截图中… · Esc 暂停 · Enter 完成", paused: false)
            if wasPaused { emit("session.resumed", sessionId: sessionId) }
        case .paused:
            let wasPaused = capturePaused
            capturePaused = true
            overlay?.updateStatus("已暂停", paused: true)
            if !wasPaused { emit("session.paused", sessionId: sessionId, payload: ["reason": .string("user")]) }
        case .finishing:
            capturePaused = true
            overlay?.updateStatus(mode == .simple ? "正在保存截图…" : "正在生成长图…", paused: true, finishing: true)
        }
    }

    @MainActor
    private func removeKeyMonitor() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor); self.localKeyMonitor = nil }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor); self.globalKeyMonitor = nil }
    }

    private func respond(_ request: RequestEnvelope, _ payload: [String: JSONValue]) { writer.write(ResponseEnvelope(requestId: request.requestId, payload: payload)) }
    private func emit(_ type: String, sessionId: String?, payload: [String: JSONValue] = [:]) {
        sequence += 1
        writer.write(EventEnvelope(type: type, sessionId: sessionId, sequence: sequence, payload: payload))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let writer = ProtocolWriter()
let runtime = HelperRuntime(writer: writer)
let decoder = JSONDecoder()

DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine() {
        do {
            let request = try decoder.decode(RequestEnvelope.self, from: Data(line.utf8))
            DispatchQueue.main.async { runtime.handle(request) }
        } catch {
            writer.write(ResponseEnvelope(requestId: "unknown", error: ProtocolFailure(code: "INVALID_REQUEST", message: "Malformed or incompatible request")))
        }
    }
    DispatchQueue.main.async { NSApp.terminate(nil) }
}

app.run()
