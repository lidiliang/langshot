import AppKit
import CoreGraphics
import LangShotCore

public struct NativeDisplay: @unchecked Sendable {
    public let screen: NSScreen
    public let geometry: DisplayGeometry

    public init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = CGDirectDisplayID(number.uint32Value)
        self.screen = screen
        geometry = DisplayGeometry(
            id: id,
            pointBounds: RectValue(x: screen.frame.origin.x, y: screen.frame.origin.y, width: screen.frame.width, height: screen.frame.height),
            pixelWidth: CGDisplayPixelsWide(id),
            pixelHeight: CGDisplayPixelsHigh(id)
        )
    }
}

@MainActor
public struct DisplayService {
    public init() {}
    public func displays() -> [NativeDisplay] { NSScreen.screens.compactMap(NativeDisplay.init) }

    public func display(containing globalPoint: NSPoint) -> NativeDisplay? {
        displays().first { $0.screen.frame.contains(globalPoint) } ?? displays().first
    }
}

