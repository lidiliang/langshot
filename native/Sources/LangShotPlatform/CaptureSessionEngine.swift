import AppKit
import CoreGraphics
import CoreServices
import ImageIO
import LangShotCore

public struct CaptureProgress: Sendable {
    public let height: Int
    public let frames: Int
    public let confidence: Double
}

public enum CaptureQualityWarning: String, Hashable, Sendable {
    case noMovementDetected
    case matchingSkipped
}

public struct CaptureResult: Sendable {
    public let url: URL
    public let warnings: [CaptureQualityWarning]
}

public enum CaptureEngineStatus: Sendable {
    case running
    case paused
    case finishing
}

enum UncertainMatchRecoveryAction: Equatable {
    case retryWithoutScrolling
    case resynchronize
}

enum AutomaticTickAction: Equatable {
    case wait
    case sample
    case scroll
}

@MainActor
public final class CaptureSessionEngine {
    public typealias ProgressHandler = @MainActor (CaptureProgress) -> Void
    public typealias CompletionHandler = @MainActor (Result<CaptureResult, Error>) -> Void
    public typealias StatusHandler = @MainActor (CaptureEngineStatus) -> Void

    private struct FrameRecord { let url: URL; let displacement: Int }
    private let sessionId: String
    private let mode: CaptureMode
    private let requestedDirection: ScrollDirection
    private let selection: RectValue
    private let overlayWindowId: CGWindowID
    private let anchor: PointValue?
    private let targetProcessIdentifier: pid_t?
    private let capture = ScreenCaptureService()
    private let automaticMatcher = OverlapMatcher(minimumDisplacement: 2, minimumOverlap: 24, minimumOverlapFraction: 0.35, confidenceThreshold: 0.68)
    private let manualMatcher = OverlapMatcher(minimumDisplacement: 2, minimumOverlap: 12, minimumOverlapFraction: 0.12, confidenceThreshold: 0.72)
    private let staticDetector = StaticBandDetector()
    private let policy = SessionPolicy()
    private let worker = DispatchQueue(label: "app.langshot.capture", qos: .userInitiated)
    private let progress: ProgressHandler
    private let completion: CompletionHandler
    private let status: StatusHandler
    private var timer: Timer?
    private var records: [FrameRecord] = []
    private var previousProbe: GrayFrame?
    private var direction: ScrollDirection?
    private var stationaryProbes = 0
    private var effectiveHeight = 0
    private var startedAt = Date()
    private var captureInFlight = false
    private var awaitingAutomaticSample = false
    private var automaticSampleNotBefore = Date.distantPast
    private var automaticStepLines: Int32 = 2
    private var automaticHighConfidenceStreak = 0
    private var automaticRecoveryNudges = 0
    private var acceptedProbeDisplacements: [Int] = []
    private var staticTop = 0
    private var staticBottom = 0
    private var isFinishing = false
    private var isCancelled = false
    private var hasObservedMovement = false
    private var resampleBeforeNextScroll = false
    private var consecutiveMatchFailures = 0
    private var qualityWarnings: Set<CaptureQualityWarning> = []

    public init(sessionId: String, mode: CaptureMode, requestedDirection: ScrollDirection, selection: RectValue, overlayWindowId: CGWindowID, anchor: PointValue?, targetProcessIdentifier: pid_t?, progress: @escaping ProgressHandler, status: @escaping StatusHandler, completion: @escaping CompletionHandler) {
        self.sessionId = sessionId; self.mode = mode; self.requestedDirection = requestedDirection
        self.selection = selection; self.overlayWindowId = overlayWindowId; self.anchor = anchor; self.targetProcessIdentifier = targetProcessIdentifier
        self.progress = progress; self.status = status; self.completion = completion
    }

    public func start() {
        startedAt = Date()
        status(.running)
        sample()
        scheduleSamplingTimer()
    }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        invalidateTimers()
        try? FileManager.default.removeItem(at: Self.sessionDirectory(sessionId))
    }

    public func pause() {
        guard !isCancelled, !isFinishing else { return }
        invalidateTimers()
        status(.paused)
    }

    public func resume() {
        guard !isCancelled, !isFinishing, timer == nil else { return }
        stationaryProbes = 0
        awaitingAutomaticSample = mode == .automatic && previousProbe != nil
        resampleBeforeNextScroll = awaitingAutomaticSample
        automaticSampleNotBefore = Date().addingTimeInterval(0.12)
        status(.running)
        scheduleSamplingTimer()
    }

    public func finishNow() { finish() }

    private func tick() {
        guard !isCancelled, !isFinishing else { return }
        if mode == .automatic, let anchor {
            let action = Self.automaticTickAction(
                captureInFlight: captureInFlight,
                awaitingSample: awaitingAutomaticSample,
                retryingMatch: resampleBeforeNextScroll,
                settleDelayElapsed: Date() >= automaticSampleNotBefore
            )
            switch action {
            case .wait:
                return
            case .sample:
                resampleBeforeNextScroll = false
                sample()
                return
            case .scroll:
                postScroll(at: anchor, direction: requestedDirection, lines: automaticStepLines)
                awaitingAutomaticSample = true
                automaticSampleNotBefore = Date().addingTimeInterval(automaticStepLines == 1 ? 0.18 : 0.22)
                return
            }
        }
        guard !captureInFlight else { return }
        sample()
    }

    private func sample() {
        guard !captureInFlight, !isCancelled, !isFinishing else { return }
        captureInFlight = true
        let selection = self.selection, windowID = overlayWindowId
        worker.async { [weak self] in
            guard let self else { return }
            do {
                let image = try self.capture.capture(selection: selection, belowWindow: windowID)
                let probe = try Self.makeProbe(image)
                DispatchQueue.main.async { self.accept(image: image, probe: probe) }
            } catch {
                DispatchQueue.main.async { self.fail(error) }
            }
        }
    }

    private func accept(image: CGImage, probe: GrayFrame) {
        defer { captureInFlight = false }
        guard !isCancelled, !isFinishing else { return }
        do {
            if previousProbe == nil {
                let url = try persist(image: image, index: 0)
                records.append(FrameRecord(url: url, displacement: image.height))
                effectiveHeight = image.height
                previousProbe = probe
                awaitingAutomaticSample = false
                progress(CaptureProgress(height: effectiveHeight, frames: 1, confidence: 1))
                return
            }
            guard let previousProbe else { return }
            let bands = try staticDetector.unchangedEdgeBands(previous: previousProbe, current: probe, maximumFraction: 0.25)
            let contentPrevious = try Self.cropProbe(previousProbe, top: bands.top, bottom: bands.bottom)
            let contentCurrent = try Self.cropProbe(probe, top: bands.top, bottom: bands.bottom)
            let sides = try staticDetector.unchangedSideBands(previous: contentPrevious, current: contentCurrent, maximumFraction: 0.3)
            let matchingPrevious = try Self.cropProbe(contentPrevious, left: sides.left, right: sides.right)
            let matchingCurrent = try Self.cropProbe(contentCurrent, left: sides.left, right: sides.right)
            let matcher = mode == .automatic ? automaticMatcher : manualMatcher
            let directions: [ScrollDirection] = mode == .automatic ? [requestedDirection] : [.down, .up]
            let candidates = try directions.map { ($0, try matcher.match(previous: matchingPrevious, current: matchingCurrent, direction: $0)) }
            guard let best = candidates.max(by: { $0.1.confidence < $1.1.confidence }) else { throw MatchError.invalidFrame }
            let unchangedDifference = try matcher.differenceWithoutMovement(previous: matchingPrevious, current: matchingCurrent)
            let acceptedByPrediction = Self.predictedMatchIsAcceptable(
                result: best.1,
                recentDisplacements: acceptedProbeDisplacements,
                unchangedDifference: unchangedDifference,
                probeHeight: matchingPrevious.height
            )
            guard best.1.accepted || acceptedByPrediction else {
                if unchangedDifference > 6 {
                    handleUncertainMatch(byResynchronizingTo: probe)
                    return
                }
                stationaryProbes += 1
                if mode == .automatic {
                    awaitingAutomaticSample = false
                    resampleBeforeNextScroll = false
                    if !hasObservedMovement {
                        return
                    }
                    let boundary = policy.boundary(
                        mode: mode,
                        elapsed: Date().timeIntervalSince(startedAt),
                        currentHeight: effectiveHeight,
                        proposedAdditionalHeight: 0,
                        stationaryProbes: stationaryProbes
                    )
                    if Self.shouldFinishAutomatically(at: boundary) { finish() }
                }
                return
            }
            if let direction, direction != best.0 { return }
            direction = best.0
            hasObservedMovement = true
            stationaryProbes = 0
            consecutiveMatchFailures = 0
            automaticRecoveryNudges = 0
            resampleBeforeNextScroll = false
            awaitingAutomaticSample = false
            acceptedProbeDisplacements.append(best.1.displacement)
            if acceptedProbeDisplacements.count > 6 { acceptedProbeDisplacements.removeFirst() }
            if mode == .automatic {
                if best.1.confidence >= 0.82 {
                    automaticHighConfidenceStreak += 1
                    if automaticHighConfidenceStreak >= 6 { automaticStepLines = 2 }
                } else {
                    automaticHighConfidenceStreak = 0
                }
            }
            let scale = Double(image.height) / Double(probe.height)
            staticTop = max(staticTop, Int((Double(bands.top) * scale).rounded()))
            staticBottom = max(staticBottom, Int((Double(bands.bottom) * scale).rounded()))
            let physicalDisplacement = max(1, Int((Double(best.1.displacement) * scale).rounded()))
            let additional = policy.acceptedAdditionalHeight(currentHeight: effectiveHeight, proposed: physicalDisplacement)
            guard additional > 0 else { finish(); return }
            let url = try persist(image: image, index: records.count)
            records.append(FrameRecord(url: url, displacement: additional))
            effectiveHeight += additional
            self.previousProbe = probe
            progress(CaptureProgress(height: effectiveHeight, frames: records.count, confidence: best.1.confidence))
            let boundary = policy.boundary(mode: mode, elapsed: Date().timeIntervalSince(startedAt), currentHeight: effectiveHeight, proposedAdditionalHeight: 0, stationaryProbes: 0)
            if Self.shouldFinishAutomatically(at: boundary) { finish() }
        } catch { fail(error) }
    }

    private func finish() {
        guard !isCancelled, !isFinishing else { return }
        isFinishing = true
        invalidateTimers()
        status(.finishing)
        guard !records.isEmpty else { return fail(ScreenCaptureError.captureFailed) }
        let records = self.records, direction = self.direction ?? requestedDirection, completion = self.completion
        let staticTop = self.staticTop, staticBottom = self.staticBottom
        var warnings = qualityWarnings
        if mode == .automatic, !hasObservedMovement { warnings.insert(.noMovementDetected) }
        if consecutiveMatchFailures > 0 { warnings.insert(.matchingSkipped) }
        let orderedWarnings = warnings.sorted { $0.rawValue < $1.rawValue }
        worker.async {
            do {
                let url = try CaptureSessionEngine.compose(records: records, direction: direction, staticTop: staticTop, staticBottom: staticBottom)
                let result = CaptureResult(url: url, warnings: orderedWarnings)
                DispatchQueue.main.async { completion(.success(result)) }
            }
            catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }

    private func fail(_ error: Error) {
        guard !isCancelled else { return }
        invalidateTimers()
        completion(.failure(error))
    }

    private func scheduleSamplingTimer() {
        let interval = mode == .manual ? 0.06 : 0.05
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func handleUncertainMatch(byResynchronizingTo probe: GrayFrame) {
        consecutiveMatchFailures += 1
        if Self.uncertainMatchRecoveryAction(isAutomatic: mode == .automatic, consecutiveFailures: consecutiveMatchFailures) == .retryWithoutScrolling {
            if mode == .automatic {
                automaticStepLines = 1
                automaticHighConfidenceStreak = 0
                if Self.shouldNudgeAutomaticRecovery(
                    consecutiveFailures: consecutiveMatchFailures,
                    recoveryNudges: automaticRecoveryNudges
                ) {
                    automaticRecoveryNudges += 1
                    awaitingAutomaticSample = false
                    resampleBeforeNextScroll = false
                    automaticSampleNotBefore = .distantPast
                } else {
                    awaitingAutomaticSample = true
                    resampleBeforeNextScroll = true
                    automaticSampleNotBefore = Date().addingTimeInterval(0.12)
                }
            }
            return
        }
        qualityWarnings.insert(.matchingSkipped)
        previousProbe = probe
        consecutiveMatchFailures = 0
        stationaryProbes = 0
        resampleBeforeNextScroll = false
    }

    nonisolated static func uncertainMatchRecoveryAction(isAutomatic: Bool, consecutiveFailures: Int) -> UncertainMatchRecoveryAction {
        if isAutomatic { return .retryWithoutScrolling }
        return consecutiveFailures <= 4 ? .retryWithoutScrolling : .resynchronize
    }

    nonisolated static func automaticTickAction(
        captureInFlight: Bool,
        awaitingSample: Bool,
        retryingMatch: Bool,
        settleDelayElapsed: Bool
    ) -> AutomaticTickAction {
        if captureInFlight { return .wait }
        if awaitingSample || retryingMatch { return settleDelayElapsed ? .sample : .wait }
        return .scroll
    }

    nonisolated static func shouldNudgeAutomaticRecovery(
        consecutiveFailures: Int,
        recoveryNudges: Int
    ) -> Bool {
        consecutiveFailures > 0 && consecutiveFailures % 6 == 0 && recoveryNudges < 6
    }

    nonisolated static func predictedMatchIsAcceptable(
        result: OverlapResult,
        recentDisplacements: [Int],
        unchangedDifference: Double,
        probeHeight: Int
    ) -> Bool {
        guard !result.accepted,
              result.confidence >= 0.58,
              unchangedDifference > 6 else { return false }
        guard !recentDisplacements.isEmpty else {
            let maximumBootstrapDisplacement = max(6, probeHeight / 4)
            return result.displacement <= maximumBootstrapDisplacement
        }
        let ordered = recentDisplacements.sorted()
        let expected = ordered[ordered.count / 2]
        let tolerance = max(3, Int((Double(expected) * 0.65).rounded(.up)))
        return abs(result.displacement - expected) <= tolerance
    }

    nonisolated static func shouldFinishAutomatically(at boundary: SessionBoundary) -> Bool {
        boundary == .heightLimit || boundary == .durationLimit
    }

    private func invalidateTimers() {
        timer?.invalidate(); timer = nil
    }

    private func persist(image: CGImage, index: Int) throws -> URL {
        let directory = Self.sessionDirectory(sessionId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(String(format: "frame-%05d.png", index))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else { throw ScreenCaptureError.imageEncodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.imageEncodingFailed }
        return url
    }

    private nonisolated static func compose(records: [FrameRecord], direction: ScrollDirection, staticTop: Int, staticBottom: Int) throws -> URL {
        let ordered = direction == .down ? records : records.reversed()
        let images = try ordered.map { record -> (CGImage, Int) in
            guard let source = CGImageSourceCreateWithURL(record.url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ScreenCaptureError.captureFailed }
            return (image, record.displacement)
        }
        let final = try renderLongImage(images: images, staticTop: staticTop, staticBottom: staticBottom)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let resultDirectory = Self.resultDirectory
        try FileManager.default.createDirectory(at: resultDirectory, withIntermediateDirectories: true)
        let output = resultDirectory.appendingPathComponent("langShot-\(formatter.string(from: Date())).png")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, kUTTypePNG, 1, nil) else { throw ScreenCaptureError.imageEncodingFailed }
        CGImageDestinationAddImage(destination, final, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.imageEncodingFailed }
        return output
    }

    nonisolated static var resultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("langshots", isDirectory: true)
    }

    @discardableResult
    public nonisolated static func cleanupExpiredResults(
        in requestedDirectory: URL? = nil,
        now: Date = Date(),
        retentionInterval: TimeInterval = 7 * 24 * 60 * 60
    ) throws -> Int {
        let directory = requestedDirectory ?? resultDirectory
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { return 0 }

        let cutoff = now.addingTimeInterval(-retentionInterval)
        let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]
        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var removed = 0
        for file in candidates {
            guard file.lastPathComponent.hasPrefix("langShot-"),
                  supportedExtensions.contains(file.pathExtension.lowercased()) else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff else { continue }
            try fileManager.removeItem(at: file)
            removed += 1
        }
        return removed
    }

    nonisolated static func renderLongImage(images: [(CGImage, Int)], staticTop: Int, staticBottom: Int) throws -> CGImage {
        guard let firstImage = images.first?.0 else { throw ScreenCaptureError.captureFailed }
        let width = images.map { $0.0.width }.max() ?? 1
        let height = min(60_000, firstImage.height + images.dropFirst().reduce(0) { $0 + $1.1 })
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScreenCaptureError.imageEncodingFailed }
        let firstContentHeight = max(1, images[0].0.height - staticBottom)
        var top = 0
        if let first = images[0].0.cropping(to: CGRect(x: 0, y: 0, width: images[0].0.width, height: firstContentHeight)) {
            let destinationY = height - top - first.height
            context.draw(first, in: CGRect(x: 0, y: destinationY, width: first.width, height: first.height))
            top += first.height
        }
        for (image, displacement) in images.dropFirst() where top < height {
            let availableBottom = max(staticTop, image.height - staticBottom)
            let sliceHeight = min(displacement, min(height - top, max(0, availableBottom - staticTop)))
            guard sliceHeight > 0, let slice = image.cropping(to: CGRect(x: 0, y: availableBottom - sliceHeight, width: image.width, height: sliceHeight)) else { continue }
            let destinationY = height - top - slice.height
            context.draw(slice, in: CGRect(x: 0, y: destinationY, width: slice.width, height: slice.height))
            top += sliceHeight
        }
        if staticBottom > 0, top < height, let last = images.last?.0 {
            let footerHeight = min(staticBottom, height - top)
            if let footer = last.cropping(to: CGRect(x: 0, y: last.height - footerHeight, width: last.width, height: footerHeight)) {
                let destinationY = height - top - footer.height
                context.draw(footer, in: CGRect(x: 0, y: destinationY, width: footer.width, height: footer.height))
            }
        }
        guard let final = context.makeImage() else { throw ScreenCaptureError.imageEncodingFailed }
        return final
    }

    private nonisolated static func sessionDirectory(_ sessionId: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("app.langshot/sessions/\(sessionId)", isDirectory: true)
    }

    private func postScroll(at point: PointValue, direction: ScrollDirection, lines: Int32) {
        let magnitude = max(1, min(2, lines))
        let delta: Int32 = direction == .down ? -magnitude : magnitude
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
        event.location = CGPoint(x: point.x, y: point.y)
        event.post(tap: .cghidEventTap)
    }

    private nonisolated static func makeProbe(_ image: CGImage) throws -> GrayFrame {
        let width = min(256, image.width)
        let height = max(32, Int(Double(image.height) * Double(width) / Double(image.width)))
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ScreenCaptureError.imageEncodingFailed }
        context.interpolationQuality = .low; context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }

    private nonisolated static func cropProbe(_ frame: GrayFrame, top: Int, bottom: Int) throws -> GrayFrame {
        let start = min(max(0, top), frame.height - 1)
        let end = max(start + 1, frame.height - max(0, bottom))
        let pixels = Array(frame.pixels[(start * frame.width)..<(end * frame.width)])
        return try GrayFrame(width: frame.width, height: end - start, pixels: pixels)
    }

    private nonisolated static func cropProbe(_ frame: GrayFrame, left: Int, right: Int) throws -> GrayFrame {
        let start = min(max(0, left), frame.width - 1)
        let end = max(start + 1, frame.width - max(0, right))
        var pixels: [UInt8] = []
        pixels.reserveCapacity((end - start) * frame.height)
        for row in 0..<frame.height {
            let rowStart = row * frame.width
            pixels.append(contentsOf: frame.pixels[(rowStart + start)..<(rowStart + end)])
        }
        return try GrayFrame(width: end - start, height: frame.height, pixels: pixels)
    }
}
