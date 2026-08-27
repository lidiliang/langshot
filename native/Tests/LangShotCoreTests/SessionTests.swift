import Testing
@testable import LangShotCore

@Test func escapePausesThenDiscardsWithoutLosingIntermediateState() throws {
    let reducer = SessionReducer()
    var snapshot = SessionSnapshot(state: .capturing, mode: .manual, effectiveHeight: 3200, acceptedFrames: 5)
    snapshot = try reducer.reduce(snapshot, action: .escape)
    #expect(snapshot.state == .paused)
    #expect(snapshot.pauseReason == .escape)
    #expect(snapshot.effectiveHeight == 3200)
    #expect(snapshot.acceptedFrames == 5)

    snapshot = try reducer.reduce(snapshot, action: .escape)
    #expect(snapshot.state == .discarded)
}

@Test func invalidResumeDoesNotProduceAnotherState() {
    let reducer = SessionReducer()
    let snapshot = SessionSnapshot(state: .finishing, mode: .automatic)
    #expect(throws: SessionTransitionError.invalid(.finishing, .resume)) {
        try reducer.reduce(snapshot, action: .resume)
    }
}
