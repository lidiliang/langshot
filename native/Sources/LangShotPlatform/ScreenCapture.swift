import AppKit
import CoreGraphics
import LangShotCore

public enum ScreenCaptureError: LocalizedError {
    case invalidSelection
    case captureFailed
    case imageEncodingFailed
    case inputProtectionUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidSelection: return "截图区域无效"
        case .captureFailed: return "屏幕截图失败"
        case .imageEncodingFailed: return "图片编码失败"
        case .inputProtectionUnavailable: return "无法锁定滚动输入，请确认已授予辅助功能权限后重试"
        }
    }
}

public struct ScreenCaptureService: Sendable {
    public init() {}

    public func capture(selection: RectValue, belowWindow windowID: CGWindowID) throws -> CGImage {
        guard selection.size.width > 0, selection.size.height > 0 else { throw ScreenCaptureError.invalidSelection }
        let bounds = CGRect(x: selection.origin.x, y: selection.origin.y, width: selection.size.width, height: selection.size.height)
        let image = CGWindowListCreateImage(bounds, .optionOnScreenBelowWindow, windowID, [.bestResolution])
        guard let image else { throw ScreenCaptureError.captureFailed }
        return image
    }
}
