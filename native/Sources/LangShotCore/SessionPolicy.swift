import Foundation

public enum SessionBoundary: Equatable, Sendable { case none, suspectedEnd, durationLimit, heightLimit }

public struct SessionPolicy: Sendable {
    public let maximumHeight: Int
    public let maximumAutomaticDuration: TimeInterval
    public let stationaryProbeLimit: Int

    public init(maximumHeight: Int = 60_000, maximumAutomaticDuration: TimeInterval = 600, stationaryProbeLimit: Int = 4) {
        self.maximumHeight = maximumHeight
        self.maximumAutomaticDuration = maximumAutomaticDuration
        self.stationaryProbeLimit = stationaryProbeLimit
    }

    public func boundary(mode: CaptureMode, elapsed: TimeInterval, currentHeight: Int, proposedAdditionalHeight: Int, stationaryProbes: Int, hasObservedMovement: Bool = true) -> SessionBoundary {
        if currentHeight + max(0, proposedAdditionalHeight) >= maximumHeight { return .heightLimit }
        if mode == .automatic && elapsed >= maximumAutomaticDuration { return .durationLimit }
        if hasObservedMovement && stationaryProbes >= stationaryProbeLimit { return .suspectedEnd }
        return .none
    }

    public func acceptedAdditionalHeight(currentHeight: Int, proposed: Int) -> Int {
        max(0, min(proposed, maximumHeight - currentHeight))
    }
}
