import AppKit
import ApplicationServices
import CoreGraphics

public struct PermissionSnapshot: Equatable, Sendable {
    public let screenRecording: Bool
    public let accessibility: Bool
    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }
}

public enum PermissionKind: String, Sendable { case screenRecording, accessibility }

public struct PermissionService: Sendable {
    public init() {}

    public func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            screenRecording: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted()
        )
    }

    @discardableResult
    public func request(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .screenRecording:
            return CGRequestScreenCaptureAccess()
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    @MainActor
    public func openSettings(_ kind: PermissionKind) {
        let anchor = kind == .screenRecording ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

