import Testing
@testable import LangShotCore

@Test func retinaCoordinatesUsePhysicalPixelsAndTopLeftOrigin() {
    let display = DisplayGeometry(id: 7, pointBounds: RectValue(x: 100, y: 50, width: 1440, height: 900), pixelWidth: 2880, pixelHeight: 1800)
    let result = display.pixelRect(for: RectValue(x: 200, y: 100, width: 720, height: 200))
    #expect(result == PixelRect(x: 200, y: 100, width: 1440, height: 400))
}

@Test func selectionIsClippedToOneDisplay() {
    let display = DisplayGeometry(id: 1, pointBounds: RectValue(x: 0, y: 0, width: 100, height: 80), pixelWidth: 100, pixelHeight: 80)
    #expect(display.pixelRect(for: RectValue(x: 90, y: 60, width: 30, height: 40)) == PixelRect(x: 90, y: 60, width: 10, height: 20))
}
