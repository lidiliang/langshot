import Testing
@testable import LangShotCore

@Test func heightLimitWinsAndClampsLastSegment() {
    let policy = SessionPolicy()
    #expect(policy.boundary(mode: .manual, elapsed: 2, currentHeight: 59_800, proposedAdditionalHeight: 300, stationaryProbes: 0) == .heightLimit)
    #expect(policy.acceptedAdditionalHeight(currentHeight: 59_800, proposed: 300) == 200)
}

@Test func automaticDurationAndSuspectedEndAreRecoverableBoundaries() {
    let policy = SessionPolicy()
    #expect(policy.boundary(mode: .automatic, elapsed: 600, currentHeight: 2000, proposedAdditionalHeight: 0, stationaryProbes: 0) == .durationLimit)
    #expect(policy.boundary(mode: .manual, elapsed: 900, currentHeight: 2000, proposedAdditionalHeight: 0, stationaryProbes: 4) == .suspectedEnd)
}

@Test func stationaryFramesCannotMeanEndBeforeTheFirstRealMovement() {
    let policy = SessionPolicy()
    #expect(policy.boundary(
        mode: .automatic,
        elapsed: 5,
        currentHeight: 1200,
        proposedAdditionalHeight: 0,
        stationaryProbes: 100,
        hasObservedMovement: false
    ) == .none)
}
