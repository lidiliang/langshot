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
    private var keyMonitor: Any?
    private var escapePaused = false

    init(writer: ProtocolWriter) { self.writer = writer }

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
                let mode = request.payload["mode"] == .string("automatic") ? PermissionKind.accessibility : .screenRecording
                permissionService.openSettings(mode)
                respond(request, [:])
            case "session.begin":
                beginSession(request)
            case "session.discard":
                engine?.cancel(); engine = nil
                removeKeyMonitor()
                overlay?.close(); overlay = nil
                emit("session.cancelled", sessionId: activeSessionId)
                activeSessionId = nil
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
        let mode: CaptureMode = request.payload["mode"] == .string("automatic") ? .automatic : .manual
        let requestedDirection: ScrollDirection = request.payload["direction"] == .string("up") ? .up : .down
        activeSessionId = sessionId
        overlay = SelectionOverlayController(display: display, onConfirm: { [weak self] display, selection, windowID in
            guard let self else { return }
            let pixels = display.geometry.pixelRect(for: selection)
            self.emit("selection.confirmed", sessionId: sessionId, payload: [
                "displayId": .number(Double(display.geometry.id)),
                "x": .number(selection.origin.x), "y": .number(selection.origin.y),
                "width": .number(selection.size.width), "height": .number(selection.size.height),
                "pixelWidth": .number(Double(pixels?.width ?? 0)), "pixelHeight": .number(Double(pixels?.height ?? 0)),
                "overlayWindowId": .number(Double(windowID))
            ])
            if mode == .automatic {
                self.overlay?.requestAnchor { [weak self] anchor in
                    self?.startEngine(sessionId: sessionId, mode: mode, direction: requestedDirection, selection: selection, windowID: windowID, anchor: anchor)
                }
            } else {
                self.startEngine(sessionId: sessionId, mode: mode, direction: requestedDirection, selection: selection, windowID: windowID, anchor: nil)
            }
        }, onCancel: { [weak self] in
            self?.engine?.cancel(); self?.engine = nil
            self?.removeKeyMonitor()
            self?.overlay?.close(); self?.overlay = nil
            self?.emit("session.cancelled", sessionId: sessionId)
            self?.activeSessionId = nil
        })
        overlay?.show()
        respond(request, ["sessionId": .string(sessionId)])
    }

    @MainActor
    private func startEngine(sessionId: String, mode: CaptureMode, direction: ScrollDirection, selection: RectValue, windowID: CGWindowID, anchor: PointValue?) {
        overlay?.beginCapturing(status: "长截图中… 0px · 0 帧")
        installKeyMonitor(sessionId: sessionId)
        engine = CaptureSessionEngine(
            sessionId: sessionId,
            mode: mode,
            requestedDirection: direction,
            selection: selection,
            overlayWindowId: windowID,
            anchor: anchor,
            progress: { [weak self] progress in
                self?.overlay?.updateStatus("长截图中… \(progress.height)px · \(progress.frames) 帧")
                self?.emit("session.progress", sessionId: sessionId, payload: [
                    "height": .number(Double(progress.height)), "frames": .number(Double(progress.frames)), "confidence": .number(progress.confidence)
                ])
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.engine = nil; self.removeKeyMonitor(); self.overlay?.close(); self.overlay = nil
                switch result {
                case let .success(url): self.emit("session.completed", sessionId: sessionId, payload: ["path": .string(url.path)])
                case let .failure(error): self.emit("error", sessionId: sessionId, payload: ["code": .string("CAPTURE_FAILED"), "message": .string(error.localizedDescription)])
                }
                self.activeSessionId = nil
            }
        )
        engine?.start()
    }

    @MainActor
    private func installKeyMonitor(sessionId: String) {
        removeKeyMonitor()
        escapePaused = false
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                if self.escapePaused {
                    self.engine?.cancel(); self.engine = nil; self.removeKeyMonitor()
                    self.overlay?.close(); self.overlay = nil
                    self.emit("session.cancelled", sessionId: sessionId); self.activeSessionId = nil
                } else {
                    self.escapePaused = true; self.engine?.pause()
                    self.overlay?.updateStatus("已暂停 · 空格继续 · ⌘↵ 完成 · Esc 丢弃")
                    self.emit("session.paused", sessionId: sessionId, payload: ["reason": .string("escape")])
                }
                return nil
            }
            if self.escapePaused, event.keyCode == 49 {
                self.escapePaused = false; self.engine?.resume()
                self.overlay?.updateStatus("长截图中… · ⌘↵ 完成 · Esc 暂停")
                self.emit("session.resumed", sessionId: sessionId)
                return nil
            }
            if event.keyCode == 36, event.modifierFlags.contains(.command) {
                self.engine?.finishNow(); return nil
            }
            return event
        }
    }

    @MainActor
    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
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
