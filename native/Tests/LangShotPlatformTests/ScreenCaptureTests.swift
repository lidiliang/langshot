import AppKit
import CoreGraphics
import Testing
import LangShotCore
@testable import LangShotPlatform

@Test func frozenDisplayImageIsCroppedWithRetinaCoordinatesAndTopLeftOrigin() throws {
    let display = DisplayGeometry(
        id: 1,
        pointBounds: RectValue(x: 100, y: 200, width: 4, height: 4),
        pixelWidth: 8,
        pixelHeight: 8
    )
    let source = try makeCoordinateImage(width: 8, height: 8)
    let selection = RectValue(x: 101, y: 201, width: 2, height: 1)

    let cropped = try ScreenCaptureService().cropDisplayImage(source, display: display, selection: selection)

    #expect(cropped.width == 4)
    #expect(cropped.height == 2)
    let sourceBitmap = NSBitmapImageRep(cgImage: source)
    let croppedBitmap = NSBitmapImageRep(cgImage: cropped)
    let expected = try #require(sourceBitmap.colorAt(x: 2, y: 2))
    let actual = try #require(croppedBitmap.colorAt(x: 0, y: 0))
    #expect(abs(expected.redComponent - actual.redComponent) < 0.01)
    #expect(abs(expected.greenComponent - actual.greenComponent) < 0.01)
}

@Test func frozenDisplayCropRejectsAnUnexpectedBackingResolution() throws {
    let display = DisplayGeometry(
        id: 1,
        pointBounds: RectValue(x: 0, y: 0, width: 4, height: 4),
        pixelWidth: 8,
        pixelHeight: 8
    )
    let lowResolutionImage = try makeCoordinateImage(width: 4, height: 4)

    #expect(throws: ScreenCaptureError.self) {
        try ScreenCaptureService().cropDisplayImage(
            lowResolutionImage,
            display: display,
            selection: RectValue(x: 0, y: 0, width: 2, height: 2)
        )
    }
}

private func makeCoordinateImage(width: Int, height: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw ScreenCaptureError.captureFailed }

    for y in 0..<height {
        for x in 0..<width {
            context.setFillColor(
                red: CGFloat(x + 1) / CGFloat(width + 1),
                green: CGFloat(y + 1) / CGFloat(height + 1),
                blue: 0,
                alpha: 1
            )
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    guard let image = context.makeImage() else { throw ScreenCaptureError.captureFailed }
    return image
}
