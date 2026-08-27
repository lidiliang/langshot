import Foundation

public enum CaptureMode: String, Codable, Sendable { case manual, automatic }
public enum ScrollDirection: String, Codable, Sendable { case up, down }

public enum SessionState: String, Codable, CaseIterable, Sendable {
    case selecting, ready, capturing, paused, finishing, completed, discarded, failed
}

public enum PauseReason: String, Codable, Sendable {
    case user, escape, reverseDirection, lowConfidence, suspectedEnd, durationLimit, heightLimit, focusLost
}

public struct SessionSnapshot: Equatable, Sendable {
    public var state: SessionState
    public var mode: CaptureMode
    public var direction: ScrollDirection?
    public var pauseReason: PauseReason?
    public var effectiveHeight: Int
    public var acceptedFrames: Int

    public init(state: SessionState = .selecting, mode: CaptureMode, direction: ScrollDirection? = nil, pauseReason: PauseReason? = nil, effectiveHeight: Int = 0, acceptedFrames: Int = 0) {
        self.state = state
        self.mode = mode
        self.direction = direction
        self.pauseReason = pauseReason
        self.effectiveHeight = effectiveHeight
        self.acceptedFrames = acceptedFrames
    }
}

public enum SessionAction: Equatable, Sendable {
    case selectionConfirmed
    case start
    case pause(PauseReason)
    case resume
    case finish
    case complete
    case discard
    case fail
    case escape
}

public enum SessionTransitionError: Error, Equatable { case invalid(SessionState, SessionAction) }

public struct SessionReducer: Sendable {
    public init() {}

    public func reduce(_ snapshot: SessionSnapshot, action: SessionAction) throws -> SessionSnapshot {
        var next = snapshot
        switch (snapshot.state, action) {
        case (.selecting, .selectionConfirmed): next.state = .ready
        case (.ready, .start), (.paused, .resume): next.state = .capturing; next.pauseReason = nil
        case (.capturing, let .pause(reason)): next.state = .paused; next.pauseReason = reason
        case (.capturing, .escape): next.state = .paused; next.pauseReason = .escape
        case (.paused, .escape), (_, .discard): next.state = .discarded; next.pauseReason = nil
        case (.capturing, .finish), (.paused, .finish): next.state = .finishing; next.pauseReason = nil
        case (.finishing, .complete): next.state = .completed
        case (_, .fail): next.state = .failed
        default: throw SessionTransitionError.invalid(snapshot.state, action)
        }
        return next
    }
}

