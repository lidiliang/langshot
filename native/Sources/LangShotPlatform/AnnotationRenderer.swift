import AppKit
import CoreGraphics
import CoreText
import CoreServices
import ImageIO
import LangShotCore

public struct AnnotationPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum ImageAnnotation: Equatable, Sendable {
    case arrow(start: AnnotationPoint, end: AnnotationPoint, lineWidth: Double, color: String)
    case text(origin: AnnotationPoint, text: String, fontSize: Double, color: String)

    public init(json: JSONValue) throws {
        guard case let .object(value) = json,
              case let .string(type)? = value["type"] else { throw AnnotationRendererError.invalidAnnotation }
        switch type {
        case "arrow":
            let start = try AnnotationPoint(x: value.number("startX"), y: value.number("startY"))
            let end = try AnnotationPoint(x: value.number("endX"), y: value.number("endY"))
            let lineWidth = try value.number("lineWidth")
            guard (1...200).contains(lineWidth) else { throw AnnotationRendererError.invalidAnnotation }
            self = .arrow(start: start, end: end, lineWidth: lineWidth, color: value.string("color") ?? "#ff4d67")
        case "text":
            let origin = try AnnotationPoint(x: value.number("x"), y: value.number("y"))
            guard case let .string(text)? = value["text"], !text.isEmpty, text.count <= 500 else {
                throw AnnotationRendererError.invalidAnnotation
            }
            let fontSize = try value.number("fontSize")
            guard (6...500).contains(fontSize) else { throw AnnotationRendererError.invalidAnnotation }
            self = .text(origin: origin, text: text, fontSize: fontSize, color: value.string("color") ?? "#ff4d67")
        default:
            throw AnnotationRendererError.invalidAnnotation
        }
    }
}

public enum AnnotationRendererError: LocalizedError {
    case invalidSource
    case invalidAnnotation
    case tooManyAnnotations
    case imageDecodingFailed
    case imageEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidSource: return "只能编辑 langShot 截图目录中的 PNG 文件"
        case .invalidAnnotation: return "标注数据无效"
        case .tooManyAnnotations: return "单张图片最多支持 200 个标注"
        case .imageDecodingFailed: return "无法读取待编辑的截图"
        case .imageEncodingFailed: return "无法保存编辑后的截图"
        }
    }
}

public enum AnnotationRenderer {
    public static func parse(_ value: JSONValue) throws -> [ImageAnnotation] {
        guard case let .array(items) = value, items.count <= 200 else {
            throw AnnotationRendererError.tooManyAnnotations
        }
        return try items.map(ImageAnnotation.init(json:))
    }

    public static func export(
        sourcePath: String,
        annotations: [ImageAnnotation],
        allowedDirectory: URL? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        let requestedDirectory = allowedDirectory ?? CaptureSessionEngine.resultDirectory
        try fileManager.createDirectory(at: requestedDirectory, withIntermediateDirectories: true)
        let directory = requestedDirectory.standardizedFileURL
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
            throw AnnotationRendererError.invalidSource
        }

        let source = URL(fileURLWithPath: sourcePath).standardizedFileURL
        guard source.deletingLastPathComponent() == directory,
              source.lastPathComponent.hasPrefix("langShot-"),
              source.pathExtension.lowercased() == "png" else { throw AnnotationRendererError.invalidSource }
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
            throw AnnotationRendererError.invalidSource
        }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw AnnotationRendererError.imageDecodingFailed
        }

        let rendered = try render(image: image, annotations: annotations)
        let stem = source.deletingPathExtension().lastPathComponent
        let suffix = UUID().uuidString.lowercased().prefix(8)
        let output = directory.appendingPathComponent("\(stem)-edited-\(suffix).png")
        let staging = directory.appendingPathComponent(".\(output.lastPathComponent).staging")
        defer { try? fileManager.removeItem(at: staging) }
        guard let destination = CGImageDestinationCreateWithURL(staging as CFURL, kUTTypePNG, 1, nil) else {
            throw AnnotationRendererError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { throw AnnotationRendererError.imageEncodingFailed }
        try fileManager.moveItem(at: staging, to: output)
        return output
    }

    public static func render(image: CGImage, annotations: [ImageAnnotation]) throws -> CGImage {
        guard annotations.count <= 200 else { throw AnnotationRendererError.tooManyAnnotations }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw AnnotationRendererError.imageEncodingFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for annotation in annotations {
            switch annotation {
            case let .arrow(start, end, lineWidth, color):
                drawArrow(start: start, end: end, lineWidth: lineWidth, color: color, imageHeight: image.height, in: context)
            case let .text(origin, text, fontSize, color):
                drawText(text, origin: origin, fontSize: fontSize, color: color, imageHeight: image.height, in: context)
            }
        }
        guard let result = context.makeImage() else { throw AnnotationRendererError.imageEncodingFailed }
        return result
    }

    private static func drawArrow(start: AnnotationPoint, end: AnnotationPoint, lineWidth: Double, color: String, imageHeight: Int, in context: CGContext) {
        let startPoint = CGPoint(x: start.x, y: Double(imageHeight) - start.y)
        let endPoint = CGPoint(x: end.x, y: Double(imageHeight) - end.y)
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let distance = hypot(dx, dy)
        guard distance >= 2 else { return }
        let stroke = cgColor(hex: color)
        let width = CGFloat(lineWidth)
        context.setStrokeColor(stroke)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()

        let angle = atan2(dy, dx)
        let headLength = max(width * 3.5, min(CGFloat(distance) * 0.28, width * 6))
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: endPoint.x - headLength * cos(angle - spread), y: endPoint.y - headLength * sin(angle - spread))
        let right = CGPoint(x: endPoint.x - headLength * cos(angle + spread), y: endPoint.y - headLength * sin(angle + spread))
        context.move(to: left)
        context.addLine(to: endPoint)
        context.addLine(to: right)
        context.strokePath()
    }

    private static func drawText(_ text: String, origin: AnnotationPoint, fontSize: Double, color: String, imageHeight: Int, in context: CGContext) {
        let size = CGFloat(fontSize)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: nsColor(hex: color)
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: origin.x, y: Double(imageHeight) - origin.y - fontSize)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func nsColor(hex: String) -> NSColor {
        let components = colorComponents(hex: hex)
        return NSColor(red: components.0, green: components.1, blue: components.2, alpha: 1)
    }

    private static func cgColor(hex: String) -> CGColor { nsColor(hex: hex).cgColor }

    private static func colorComponents(hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, let number = Int(value, radix: 16) else { return (1, 0.30, 0.40) }
        return (
            CGFloat((number >> 16) & 0xff) / 255,
            CGFloat((number >> 8) & 0xff) / 255,
            CGFloat(number & 0xff) / 255
        )
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func number(_ key: String) throws -> Double {
        guard case let .number(value)? = self[key], value.isFinite else { throw AnnotationRendererError.invalidAnnotation }
        return value
    }

    func string(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }
}
