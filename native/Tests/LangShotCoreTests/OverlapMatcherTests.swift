import Testing
@testable import LangShotCore

@Test func downwardFramesReturnKnownDisplacement() throws {
    let source = (0..<18).flatMap { row in (0..<8).map { column in UInt8((row * 11 + column * 3) % 251) } }
    let previous = try GrayFrame(width: 8, height: 12, pixels: Array(source[0..<(8 * 12)]))
    let current = try GrayFrame(width: 8, height: 12, pixels: Array(source[(4 * 8)..<(16 * 8)]))
    let result = try OverlapMatcher(minimumOverlap: 4).match(previous: previous, current: current, direction: .down)
    #expect(result.displacement == 4)
    #expect(result.overlap == 8)
    #expect(result.accepted)
}

@Test func unchangedTopAndBottomBandsAreDetected() throws {
    let previousRows: [[UInt8]] = [[10,10], [10,10], [20,30], [40,50], [8,8]]
    let currentRows: [[UInt8]] = [[10,10], [10,10], [80,90], [70,60], [8,8]]
    let previous = try GrayFrame(width: 2, height: 5, pixels: previousRows.flatMap { $0 })
    let current = try GrayFrame(width: 2, height: 5, pixels: currentRows.flatMap { $0 })
    let bands = try StaticBandDetector().unchangedEdgeBands(previous: previous, current: current, maximumFraction: 0.5)
    #expect(bands.top == 2)
    #expect(bands.bottom == 1)
}

@Test func unchangedLeftAndRightBandsAreDetected() throws {
    let previousRows: [[UInt8]] = [
        [9, 10, 20, 8, 8],
        [9, 30, 40, 8, 8],
        [9, 50, 60, 8, 8]
    ]
    let currentRows: [[UInt8]] = [
        [9, 70, 80, 8, 8],
        [9, 90, 100, 8, 8],
        [9, 110, 120, 8, 8]
    ]
    let previous = try GrayFrame(width: 5, height: 3, pixels: previousRows.flatMap { $0 })
    let current = try GrayFrame(width: 5, height: 3, pixels: currentRows.flatMap { $0 })
    let bands = try StaticBandDetector().unchangedSideBands(previous: previous, current: current, maximumFraction: 0.5)
    #expect(bands.left == 1)
    #expect(bands.right == 2)
}

@Test func reducedOverlapRequirementRecoversFastManualScroll() throws {
    var source: [UInt8] = []
    source.reserveCapacity(28 * 12)
    for row in 0..<28 {
        for column in 0..<12 {
            source.append(UInt8((row * 37 + column * 17 + row * column * 3) % 251))
        }
    }
    let previous = try GrayFrame(width: 12, height: 16, pixels: Array(source[0..<(12 * 16)]))
    let current = try GrayFrame(width: 12, height: 16, pixels: Array(source[(12 * 12)..<(28 * 12)]))
    let result = try OverlapMatcher(
        minimumDisplacement: 2,
        minimumOverlap: 3,
        minimumOverlapFraction: 0.12,
        confidenceThreshold: 0.65
    ).match(previous: previous, current: current, direction: .down)
    #expect(result.displacement == 12)
    #expect(result.overlap == 4)
    #expect(result.accepted)
}

@Test func periodicContentWithSeveralEqualOffsetsIsRejectedAsAmbiguous() throws {
    var rows: [UInt8] = []
    for row in 0..<20 {
        for column in 0..<8 {
            rows.append(UInt8(((row % 4) * 47 + column * 5) % 251))
        }
    }
    let frame = try GrayFrame(width: 8, height: 20, pixels: rows)
    let result = try OverlapMatcher(minimumOverlap: 4).match(previous: frame, current: frame, direction: .down)
    #expect(result.displacement == 4)
    #expect(!result.accepted)
    #expect(result.confidence < 0.72)
}

@Test func motionHistoryDisambiguatesPeriodicContentWithoutOverridingImageEvidence() throws {
    var source: [UInt8] = []
    for row in 0..<28 {
        for column in 0..<8 {
            source.append(UInt8(((row % 4) * 47 + column * 5) % 251))
        }
    }
    let previous = try GrayFrame(width: 8, height: 20, pixels: Array(source[0..<(20 * 8)]))
    let current = try GrayFrame(width: 8, height: 20, pixels: Array(source[(8 * 8)..<(28 * 8)]))
    let result = try OverlapMatcher(minimumOverlap: 4).match(
        previous: previous,
        current: current,
        direction: .down,
        preferredDisplacement: 8,
        preferenceTolerance: 2
    )
    #expect(result.displacement == 8)
    #expect(result.alignmentDifference == 0)
    #expect(!result.accepted)
}

@Test func stationaryDifferenceSeparatesChangedContentFromNoMovement() throws {
    let first = try GrayFrame(width: 2, height: 3, pixels: [10, 10, 20, 20, 30, 30])
    let same = try GrayFrame(width: 2, height: 3, pixels: [10, 10, 20, 20, 30, 30])
    let changed = try GrayFrame(width: 2, height: 3, pixels: [40, 40, 50, 50, 60, 60])
    let matcher = OverlapMatcher()
    #expect(try matcher.differenceWithoutMovement(previous: first, current: same) == 0)
    #expect(try matcher.differenceWithoutMovement(previous: first, current: changed) == 30)
}
