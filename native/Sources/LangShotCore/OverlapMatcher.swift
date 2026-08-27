import Foundation

public struct GrayFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0, pixels.count == width * height else { throw MatchError.invalidFrame }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

public struct OverlapResult: Equatable, Sendable {
    public let displacement: Int
    public let overlap: Int
    public let confidence: Double
    public let accepted: Bool
}

public enum MatchError: Error, Equatable { case invalidFrame, incompatibleFrames }

public struct OverlapMatcher: Sendable {
    public let minimumDisplacement: Int
    public let minimumOverlap: Int
    public let confidenceThreshold: Double

    public init(minimumDisplacement: Int = 1, minimumOverlap: Int = 8, confidenceThreshold: Double = 0.72) {
        self.minimumDisplacement = minimumDisplacement
        self.minimumOverlap = minimumOverlap
        self.confidenceThreshold = confidenceThreshold
    }

    public func match(previous: GrayFrame, current: GrayFrame, direction: ScrollDirection) throws -> OverlapResult {
        guard previous.width == current.width, previous.height == current.height else { throw MatchError.incompatibleFrames }
        let maximum = previous.height - minimumOverlap
        guard maximum >= minimumDisplacement else { throw MatchError.invalidFrame }

        var scored: [(offset: Int, score: Double)] = []
        for displacement in minimumDisplacement...maximum {
            scored.append((displacement, meanAbsoluteDifference(previous: previous, current: current, displacement: displacement, direction: direction)))
        }
        scored.sort { $0.score < $1.score }
        let best = scored[0]
        let second = scored.count > 1 ? scored[1].score : 255
        let similarity = max(0, 1 - best.score / 255)
        let separation = min(1, max(0, (second - best.score) / 24))
        let confidence = similarity * (0.78 + 0.22 * separation)
        return OverlapResult(
            displacement: best.offset,
            overlap: previous.height - best.offset,
            confidence: confidence,
            accepted: confidence >= confidenceThreshold
        )
    }

    private func meanAbsoluteDifference(previous: GrayFrame, current: GrayFrame, displacement: Int, direction: ScrollDirection) -> Double {
        let overlap = previous.height - displacement
        let stride = max(1, previous.width / 160)
        var total = 0
        var count = 0
        for row in 0..<overlap {
            let previousRow = direction == .down ? row + displacement : row
            let currentRow = direction == .down ? row : row + displacement
            for column in Swift.stride(from: 0, to: previous.width, by: stride) {
                let left = Int(previous.pixels[previousRow * previous.width + column])
                let right = Int(current.pixels[currentRow * current.width + column])
                total += abs(left - right)
                count += 1
            }
        }
        return count == 0 ? 255 : Double(total) / Double(count)
    }
}

public struct StaticBandDetector: Sendable {
    public init() {}

    public func unchangedEdgeBands(previous: GrayFrame, current: GrayFrame, maximumFraction: Double = 0.3, tolerance: UInt8 = 2) throws -> (top: Int, bottom: Int) {
        guard previous.width == current.width, previous.height == current.height else { throw MatchError.incompatibleFrames }
        let limit = max(0, min(previous.height / 2, Int(Double(previous.height) * maximumFraction)))
        var top = 0
        while top < limit, rowDifference(previous, current, row: top) <= Double(tolerance) { top += 1 }
        var bottom = 0
        while bottom < limit, rowDifference(previous, current, row: previous.height - 1 - bottom) <= Double(tolerance) { bottom += 1 }
        return (top, bottom)
    }

    private func rowDifference(_ lhs: GrayFrame, _ rhs: GrayFrame, row: Int) -> Double {
        var total = 0
        for x in 0..<lhs.width {
            total += abs(Int(lhs.pixels[row * lhs.width + x]) - Int(rhs.pixels[row * rhs.width + x]))
        }
        return Double(total) / Double(lhs.width)
    }
}

