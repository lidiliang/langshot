import AppKit
import CoreGraphics
import CoreServices
import ImageIO
import Testing
import LangShotCore
@testable import LangShotPlatform

@Test func annotationPayloadParsesArrowAndTextOperations() throws {
    let annotations = try AnnotationRenderer.parse(.array([
        .object([
            "type": .string("arrow"),
            "startX": .number(10), "startY": .number(12),
            "endX": .number(80), "endY": .number(70),
            "lineWidth": .number(4), "color": .string("#ff4d67")
        ]),
        .object([
            "type": .string("text"), "x": .number(20), "y": .number(30),
            "text": .string("重点"), "fontSize": .number(18), "color": .string("#ff4d67")
        ])
    ]))
    #expect(annotations.count == 2)
}

@Test func arrowAnnotationIsRenderedIntoTheOriginalPixels() throws {
    let source = try whiteImage(width: 100, height: 100)
    let result = try AnnotationRenderer.render(
        image: source,
        annotations: [.arrow(
            start: AnnotationPoint(x: 10, y: 20),
            end: AnnotationPoint(x: 85, y: 20),
            lineWidth: 5,
            color: "#ff0000"
        )]
    )
    let bitmap = NSBitmapImageRep(cgImage: result)
    let linePixel = try #require(bitmap.colorAt(x: 45, y: 20))
    #expect(linePixel.redComponent > 0.8)
    #expect(linePixel.greenComponent < 0.3)
}

@Test func textAnnotationIsRenderedNearItsTopLeftOrigin() throws {
    let source = try whiteImage(width: 160, height: 80)
    let result = try AnnotationRenderer.render(
        image: source,
        annotations: [.text(
            origin: AnnotationPoint(x: 12, y: 10),
            text: "A",
            fontSize: 30,
            color: "#ff0000"
        )]
    )
    let bitmap = NSBitmapImageRep(cgImage: result)
    var foundRed = false
    for y in 8..<48 {
        for x in 8..<52 {
            if let color = bitmap.colorAt(x: x, y: y), color.redComponent > 0.75, color.greenComponent < 0.5 {
                foundRed = true
            }
        }
    }
    #expect(foundRed)
}

@Test func editedAnnotationsAreExportedAsANewPngBesideTheSource() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory.appendingPathComponent("langshot-editor-test-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }
    let source = directory.appendingPathComponent("langShot-source.png")
    let image = try whiteImage(width: 80, height: 60)
    guard let destination = CGImageDestinationCreateWithURL(source as CFURL, kUTTypePNG, 1, nil) else {
        throw AnnotationTestError.image
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw AnnotationTestError.image }

    let output = try AnnotationRenderer.export(
        sourcePath: source.path,
        annotations: [.arrow(
            start: AnnotationPoint(x: 5, y: 10),
            end: AnnotationPoint(x: 60, y: 10),
            lineWidth: 4,
            color: "#ff0000"
        )],
        allowedDirectory: directory
    )

    #expect(output != source)
    #expect(output.lastPathComponent.hasPrefix("langShot-source-edited-"))
    #expect(fileManager.fileExists(atPath: output.path))
}

private func whiteImage(width: Int, height: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw AnnotationTestError.context }
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { throw AnnotationTestError.image }
    return image
}

private enum AnnotationTestError: Error { case context, image }
