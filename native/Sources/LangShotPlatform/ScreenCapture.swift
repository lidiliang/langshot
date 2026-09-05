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

    public func captureDisplay(_ display: DisplayGeometry) throws -> CGImage {
        guard let image = CGDisplayCreateImage(CGDirectDisplayID(display.id)),
              image.width == display.pixelSize.width,
              image.height == display.pixelSize.height else {
            throw ScreenCaptureError.captureFailed
        }
        return image
    }

    public func cropDisplayImage(_ image: CGImage, display: DisplayGeometry, selection: RectValue) throws -> CGImage {
        guard let pixels = display.pixelRect(for: selection), pixels.width > 0, pixels.height > 0 else {
            throw ScreenCaptureError.invalidSelection
        }
        guard image.width == display.pixelSize.width,
              image.height == display.pixelSize.height,
              pixels.x >= 0,
              pixels.y >= 0,
              pixels.x + pixels.width <= image.width,
              pixels.y + pixels.height <= image.height,
              let cropped = image.cropping(to: CGRect(
                  x: pixels.x,
                  y: pixels.y,
                  width: pixels.width,
                  height: pixels.height
              )) else {
            throw ScreenCaptureError.captureFailed
        }
        return cropped
    }

    public func capture(selection: RectValue, belowWindow windowID: CGWindowID) throws -> CGImage {
        guard selection.size.width > 0, selection.size.height > 0 else { throw ScreenCaptureError.invalidSelection }
        let bounds = CGRect(x: selection.origin.x, y: selection.origin.y, width: selection.size.width, height: selection.size.height)
        let image = CGWindowListCreateImage(bounds, .optionOnScreenBelowWindow, windowID, [.bestResolution])
        guard let image else { throw ScreenCaptureError.captureFailed }
        return image
    }
}
