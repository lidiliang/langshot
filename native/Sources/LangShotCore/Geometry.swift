import Foundation

public struct PointValue: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct SizeValue: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct RectValue: Codable, Equatable, Sendable {
    public var origin: PointValue
    public var size: SizeValue
    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = PointValue(x: x, y: y)
        size = SizeValue(width: width, height: height)
    }
    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }

    public func intersection(_ other: RectValue) -> RectValue? {
        let x1 = max(minX, other.minX)
        let y1 = max(minY, other.minY)
        let x2 = min(maxX, other.maxX)
        let y2 = min(maxY, other.maxY)
        guard x2 > x1, y2 > y1 else { return nil }
        return RectValue(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }
}

public struct PixelRect: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct DisplayGeometry: Codable, Equatable, Sendable {
    public let id: UInt32
    public let pointBounds: RectValue
    public let pixelSize: PixelRect

    public init(id: UInt32, pointBounds: RectValue, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.pointBounds = pointBounds
        pixelSize = PixelRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    }

    public var scaleX: Double { Double(pixelSize.width) / pointBounds.size.width }
    public var scaleY: Double { Double(pixelSize.height) / pointBounds.size.height }

    public func pixelRect(for globalPointRect: RectValue) -> PixelRect? {
        guard let clipped = pointBounds.intersection(globalPointRect) else { return nil }
        let localX = clipped.minX - pointBounds.minX
        let localTop = pointBounds.maxY - clipped.maxY
        return PixelRect(
            x: Int((localX * scaleX).rounded()),
            y: Int((localTop * scaleY).rounded()),
            width: Int((clipped.size.width * scaleX).rounded()),
            height: Int((clipped.size.height * scaleY).rounded())
        )
    }
}

