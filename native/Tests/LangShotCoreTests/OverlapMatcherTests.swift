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

