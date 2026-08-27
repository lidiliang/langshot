import AppKit
import CoreGraphics
import LangShotCore

public enum ScreenCaptureError: Error { case invalidSelection, captureFailed, imageEncodingFailed }

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

