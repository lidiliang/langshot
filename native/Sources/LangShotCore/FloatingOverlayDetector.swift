import Foundation

public struct FloatingOverlayDetector: Sendable {
    public init() {}

    public func detect(
        frames: [GrayFrame],
        searchStartFraction: Double = 0.55,
        stabilityTolerance: UInt8 = 6
    ) throws -> [PixelRect] {
        guard frames.count >= 3, let first = frames.first else { return [] }
        guard frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw MatchError.incompatibleFrames
        }
        guard first.width >= 3, first.height >= 3 else { return [] }

        let width = first.width
        let height = first.height
        let startY = min(height - 1, max(0, Int(Double(height) * searchStartFraction)))
        let requiredStableSamples = max(3, Int((Double(frames.count) * 0.7).rounded(.up)))
        var medianPixels = [UInt8](repeating: 255, count: width * height)
        var stable = [Bool](repeating: false, count: width * height)

        for y in startY..<height {
            for x in 0..<width {
                let index = y * width + x
                let values = frames.map { $0.pixels[index] }.sorted()
                let median = values[values.count / 2]
                medianPixels[index] = median
                let stableSamples = values.reduce(into: 0) { count, value in
                    if abs(Int(value) - Int(median)) <= Int(stabilityTolerance) { count += 1 }
                }
                // A fixed overlay contributes stable visible strokes. Plain
                // white background is intentionally excluded from the seed.
                stable[index] = stableSamples >= requiredStableSamples && median < 220
            }
        }

        var seeds = [Bool](repeating: false, count: stable.count)
        for y in max(startY, 1)..<max(startY + 1, height - 1) {
            for x in 1..<(width - 1) where stable[y * width + x] {
                let index = y * width + x
                let center = Int(medianPixels[index])
                let neighbors = [
                    Int(medianPixels[index - 1]), Int(medianPixels[index + 1]),
                    Int(medianPixels[index - width]), Int(medianPixels[index + width])
                ]
                if neighbors.contains(where: { abs($0 - center) >= 10 }) || center < 150 {
                    seeds[index] = true
                }
            }
        }

        let dilationRadius = 2
        var expanded = [Bool](repeating: false, count: seeds.count)
        for y in startY..<height {
            for x in 0..<width where seeds[y * width + x] {
                for dy in -dilationRadius...dilationRadius {
                    for dx in -dilationRadius...dilationRadius {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, nx < width, ny >= startY, ny < height {
                            expanded[ny * width + nx] = true
                        }
                    }
                }
            }
        }

        var visited = [Bool](repeating: false, count: expanded.count)
        var results: [PixelRect] = []
        let maximumWidth = max(12, width / 5)
        let maximumHeight = max(12, height / 5)
        let horizontalMargin = max(2, width / 20)

        for y in startY..<height {
            for x in horizontalMargin..<(width - horizontalMargin) {
                let root = y * width + x
                guard expanded[root], !visited[root] else { continue }
                var queue = [(x, y)]
                visited[root] = true
                var cursor = 0
                var minX = x, maxX = x, minY = y, maxY = y
                var seedCount = 0
                while cursor < queue.count {
                    let (cx, cy) = queue[cursor]
                    cursor += 1
                    minX = min(minX, cx); maxX = max(maxX, cx)
                    minY = min(minY, cy); maxY = max(maxY, cy)
                    if seeds[cy * width + cx] { seedCount += 1 }
                    for ny in max(startY, cy - 1)...min(height - 1, cy + 1) {
                        for nx in max(0, cx - 1)...min(width - 1, cx + 1) {
                            let next = ny * width + nx
                            if expanded[next], !visited[next] {
                                visited[next] = true
                                queue.append((nx, ny))
                            }
                        }
                    }
                }
                let componentWidth = maxX - minX + 1
                let componentHeight = maxY - minY + 1
                guard seedCount >= 2,
                      componentWidth <= maximumWidth,
                      componentHeight <= maximumHeight else { continue }
                let padding = 2
                let paddedMinX = max(0, minX - padding)
                let paddedMinY = max(startY, minY - padding)
                let paddedMaxX = min(width - 1, maxX + padding)
                let paddedMaxY = min(height - 1, maxY + padding)
                results.append(PixelRect(
                    x: paddedMinX,
                    y: paddedMinY,
                    width: paddedMaxX - paddedMinX + 1,
                    height: paddedMaxY - paddedMinY + 1
                ))
            }
        }
        return mergeNearby(results, width: width, height: height)
    }

    private func mergeNearby(_ rects: [PixelRect], width: Int, height: Int) -> [PixelRect] {
        var merged: [PixelRect] = []
        for rect in rects {
            var candidate = rect
            var index = 0
            while index < merged.count {
                let existing = merged[index]
                let gap = 4
                let intersects = candidate.x <= existing.x + existing.width + gap &&
                    existing.x <= candidate.x + candidate.width + gap &&
                    candidate.y <= existing.y + existing.height + gap &&
                    existing.y <= candidate.y + candidate.height + gap
                if intersects {
                    let minX = min(candidate.x, existing.x)
                    let minY = min(candidate.y, existing.y)
                    let maxX = max(candidate.x + candidate.width, existing.x + existing.width)
                    let maxY = max(candidate.y + candidate.height, existing.y + existing.height)
                    candidate = PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    merged.remove(at: index)
                    index = 0
                } else {
                    index += 1
                }
            }
            if candidate.width <= max(12, width / 5), candidate.height <= max(12, height / 5) {
                merged.append(candidate)
            }
        }
        return merged
    }
}
