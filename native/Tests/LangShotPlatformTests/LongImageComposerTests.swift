import AppKit
import CoreGraphics
import Testing
import LangShotCore
@testable import LangShotPlatform

@Test func simpleCaptureFinishesImmediatelyAfterItsFirstFrame() {
    #expect(CaptureSessionEngine.shouldFinishAfterFirstFrame(mode: .simple))
    #expect(!CaptureSessionEngine.shouldFinishAfterFirstFrame(mode: .manual))
    #expect(!CaptureSessionEngine.shouldFinishAfterFirstFrame(mode: .automatic))
}

@Test func longImageCompositionPreservesVerticalPixelOrientation() throws {
    let source = try makeStripedImage()
    let result = try CaptureSessionEngine.renderLongImage(images: [(source, source.height)], staticTop: 0, staticBottom: 0)

    #expect(result.width == source.width)
    #expect(result.height == source.height)
    let sourceBitmap = NSBitmapImageRep(cgImage: source)
    let resultBitmap = NSBitmapImageRep(cgImage: result)
    for y in 0..<source.height {
        let sourceColor = try #require(sourceBitmap.colorAt(x: 0, y: y))
        let resultColor = try #require(resultBitmap.colorAt(x: 0, y: y))
        #expect(abs(sourceColor.redComponent - resultColor.redComponent) < 0.01)
        #expect(abs(sourceColor.greenComponent - resultColor.greenComponent) < 0.01)
        #expect(abs(sourceColor.blueComponent - resultColor.blueComponent) < 0.01)
    }
}

@Test func overlappingFramesAppendOnlyNewRows() throws {
    let source = try makeRowGradientImage(height: 8)
    let first = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 2, height: 6)))
    let second = try #require(source.cropping(to: CGRect(x: 0, y: 2, width: 2, height: 6)))
    let result = try CaptureSessionEngine.renderLongImage(images: [(first, first.height), (second, 2)], staticTop: 0, staticBottom: 0)

    #expect(result.height == source.height)
    let sourceBitmap = NSBitmapImageRep(cgImage: source)
    let resultBitmap = NSBitmapImageRep(cgImage: result)
    for y in 0..<source.height {
        let expected = try #require(sourceBitmap.colorAt(x: 0, y: y))
        let actual = try #require(resultBitmap.colorAt(x: 0, y: y))
        #expect(abs(expected.redComponent - actual.redComponent) < 0.01)
    }
}

@Test func severalOverlappingFramesPreserveEverySourceRowExactlyOnce() throws {
    let source = try makeRowGradientImage(height: 14)
    let first = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 2, height: 8)))
    let second = try #require(source.cropping(to: CGRect(x: 0, y: 3, width: 2, height: 8)))
    let third = try #require(source.cropping(to: CGRect(x: 0, y: 6, width: 2, height: 8)))
    let result = try CaptureSessionEngine.renderLongImage(
        images: [(first, first.height), (second, 3), (third, 3)],
        staticTop: 0,
        staticBottom: 0
    )

    #expect(result.height == source.height)
    let sourceBitmap = NSBitmapImageRep(cgImage: source)
    let resultBitmap = NSBitmapImageRep(cgImage: result)
    for y in 0..<source.height {
        let expected = try #require(sourceBitmap.colorAt(x: 0, y: y))
        let actual = try #require(resultBitmap.colorAt(x: 0, y: y))
        #expect(abs(expected.redComponent - actual.redComponent) < 0.01)
    }
}

@Test func repeatedFloatingOverlayIsReplacedFromTheNextOverlappingFrame() throws {
    let source = try makeRowGradientImage(width: 4, height: 12)
    let firstBase = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 4, height: 8)))
    let secondBase = try #require(source.cropping(to: CGRect(x: 0, y: 2, width: 4, height: 8)))
    let thirdBase = try #require(source.cropping(to: CGRect(x: 0, y: 4, width: 4, height: 8)))
    let overlay = CGRect(x: 1, y: 6, width: 2, height: 1)
    let first = try addRedOverlay(to: firstBase, topOriginRect: overlay)
    let second = try addRedOverlay(to: secondBase, topOriginRect: overlay)
    let third = try addRedOverlay(to: thirdBase, topOriginRect: overlay)

    let result = try CaptureSessionEngine.renderLongImage(
        images: [(first, first.height), (second, 2), (third, 2)],
        staticTop: 0,
        staticBottom: 0,
        floatingOverlays: [overlay]
    )
    let bitmap = NSBitmapImageRep(cgImage: result)
    var redPixels = 0
    for y in 0..<result.height {
        for x in 0..<result.width {
            let color = try #require(bitmap.colorAt(x: x, y: y))
            if color.redComponent > 0.9, color.greenComponent < 0.4, color.blueComponent < 0.4 {
                redPixels += 1
            }
        }
    }
    // The last frame has no later view of the obscured content, so one real
    // overlay is preserved instead of inventing pixels. Earlier copies vanish.
    #expect(redPixels == 2)
}

@Test func uncertainAutomaticMatchesNeverSkipWhileManualEventuallyResynchronizes() {
    #expect(CaptureSessionEngine.uncertainMatchRecoveryAction(isAutomatic: true, consecutiveFailures: 1) == .retryWithoutScrolling)
    #expect(CaptureSessionEngine.uncertainMatchRecoveryAction(isAutomatic: true, consecutiveFailures: 100) == .retryWithoutScrolling)
    #expect(CaptureSessionEngine.uncertainMatchRecoveryAction(isAutomatic: false, consecutiveFailures: 4) == .retryWithoutScrolling)
    #expect(CaptureSessionEngine.uncertainMatchRecoveryAction(isAutomatic: false, consecutiveFailures: 5) == .resynchronize)
}

@Test func automaticScrollWaitsUntilThePreviousStepHasBeenCaptured() {
    #expect(CaptureSessionEngine.automaticTickAction(
        captureInFlight: true,
        awaitingSample: true,
        retryingMatch: false,
        settleDelayElapsed: true
    ) == .wait)
    #expect(CaptureSessionEngine.automaticTickAction(
        captureInFlight: false,
        awaitingSample: true,
        retryingMatch: false,
        settleDelayElapsed: false
    ) == .wait)
    #expect(CaptureSessionEngine.automaticTickAction(
        captureInFlight: false,
        awaitingSample: true,
        retryingMatch: false,
        settleDelayElapsed: true
    ) == .sample)
    #expect(CaptureSessionEngine.automaticTickAction(
        captureInFlight: false,
        awaitingSample: false,
        retryingMatch: false,
        settleDelayElapsed: true
    ) == .scroll)
}

@Test func automaticModeSuppressesUserScrollingButAllowsItsOwnMarkedEvents() {
    #expect(ScrollInputBlocker.shouldSuppress(type: .scrollWheel, sourceUserData: 0))
    #expect(!ScrollInputBlocker.shouldSuppress(
        type: .scrollWheel,
        sourceUserData: ScrollInputBlocker.syntheticEventMarker
    ))
    #expect(!ScrollInputBlocker.shouldSuppress(type: .keyDown, sourceUserData: 0))
}

@Test func displacementHistoryCanRecoverAWeakButConsistentMatch() {
    let consistent = OverlapResult(displacement: 21, overlap: 79, confidence: 0.62, accepted: false)
    let jump = OverlapResult(displacement: 55, overlap: 45, confidence: 0.62, accepted: false)
    let ambiguous = OverlapResult(displacement: 21, overlap: 79, confidence: 0.55, accepted: false)
    #expect(CaptureSessionEngine.predictedMatchIsAcceptable(
        result: consistent,
        recentDisplacements: [19, 20, 21, 20],
        unchangedDifference: 14,
        probeHeight: 100
    ))
    #expect(!CaptureSessionEngine.predictedMatchIsAcceptable(
        result: jump,
        recentDisplacements: [19, 20, 21, 20],
        unchangedDifference: 14,
        probeHeight: 100
    ))
    #expect(!CaptureSessionEngine.predictedMatchIsAcceptable(
        result: ambiguous,
        recentDisplacements: [19, 20, 21, 20],
        unchangedDifference: 14,
        probeHeight: 100
    ))
}

@Test func strongPixelAlignmentAndMotionHistoryRecoverAnAmbiguousMatch() {
    let guided = OverlapResult(
        displacement: 20,
        overlap: 80,
        confidence: 0.55,
        accepted: false,
        alignmentDifference: 2
    )
    let visuallyDifferent = OverlapResult(
        displacement: 20,
        overlap: 80,
        confidence: 0.55,
        accepted: false,
        alignmentDifference: 24
    )
    #expect(CaptureSessionEngine.predictedMatchIsAcceptable(
        result: guided,
        recentDisplacements: [19, 20, 20, 21],
        unchangedDifference: 12,
        probeHeight: 100
    ))
    #expect(!CaptureSessionEngine.predictedMatchIsAcceptable(
        result: visuallyDifferent,
        recentDisplacements: [19, 20, 20, 21],
        unchangedDifference: 12,
        probeHeight: 100
    ))
}

@Test func bootstrapWeakMatchAndStrictRecoveryProtectContinuity() {
    let smallBootstrap = OverlapResult(displacement: 18, overlap: 82, confidence: 0.61, accepted: false)
    let unsafeJump = OverlapResult(displacement: 40, overlap: 60, confidence: 0.61, accepted: false)
    #expect(CaptureSessionEngine.predictedMatchIsAcceptable(
        result: smallBootstrap,
        recentDisplacements: [],
        unchangedDifference: 12,
        probeHeight: 100
    ))
    #expect(!CaptureSessionEngine.predictedMatchIsAcceptable(
        result: unsafeJump,
        recentDisplacements: [],
        unchangedDifference: 12,
        probeHeight: 100
    ))
    #expect(CaptureSessionEngine.automaticRecoveryRetryDelay(consecutiveFailures: 1) == 0.20)
    #expect(CaptureSessionEngine.automaticRecoveryRetryDelay(consecutiveFailures: 100) == 0.5)
    #expect(!CaptureSessionEngine.automaticRecoveryIsExhausted(consecutiveFailures: 14))
    #expect(CaptureSessionEngine.automaticRecoveryIsExhausted(consecutiveFailures: 15))
    #expect(CaptureSessionEngine.automaticRecoveryIsExhausted(consecutiveFailures: 16))
    #expect(CaptureSessionEngine.automaticTickAction(
        captureInFlight: false,
        awaitingSample: true,
        retryingMatch: true,
        settleDelayElapsed: true
    ) == .sample)
}

@Test func automaticEndDetectionFinishesAtAConfirmedStationaryBoundary() {
    #expect(!CaptureSessionEngine.shouldFinishAutomatically(at: .none))
    #expect(CaptureSessionEngine.shouldFinishAutomatically(at: .suspectedEnd))
    #expect(CaptureSessionEngine.shouldFinishAutomatically(at: .heightLimit))
    #expect(CaptureSessionEngine.shouldFinishAutomatically(at: .durationLimit))
}

@Test func accessibilityScrollGeometryRecognizesBothEnds() {
    #expect(ScrollBoundaryDetector.isAtBoundary(
        value: 1,
        minimum: 0,
        maximum: 1,
        direction: .down
    ))
    #expect(ScrollBoundaryDetector.isAtBoundary(
        value: 0.001,
        minimum: 0,
        maximum: 1,
        direction: .up
    ))
    #expect(!ScrollBoundaryDetector.isAtBoundary(
        value: 0.5,
        minimum: 0,
        maximum: 1,
        direction: .down
    ))
    #expect(!ScrollBoundaryDetector.isAtBoundary(
        value: 0,
        minimum: 0,
        maximum: 0,
        direction: .up
    ))
}

@Test func aRejectedFrameOnlyConfirmsTheEndAfterRealMovement() {
    #expect(CaptureSessionEngine.rejectedAutomaticFrameConfirmsBoundary(
        hasObservedMovement: true,
        boundaryBeforeScroll: true
    ))
    #expect(!CaptureSessionEngine.rejectedAutomaticFrameConfirmsBoundary(
        hasObservedMovement: false,
        boundaryBeforeScroll: true
    ))
    #expect(!CaptureSessionEngine.rejectedAutomaticFrameConfirmsBoundary(
        hasObservedMovement: true,
        boundaryBeforeScroll: false
    ))
    #expect(!CaptureSessionEngine.rejectedAutomaticFrameConfirmsBoundary(
        hasObservedMovement: true,
        boundaryBeforeScroll: nil
    ))
}

@Test func localizedAnimationAtTheScrollBoundaryIsTreatedAsNoMovement() {
    #expect(CaptureSessionEngine.automaticFrameAppearsStationary(
        unchangedDifference: 9,
        unchangedPixelFraction: 0.96,
        bestDisplacedDifference: 10,
    ))
    #expect(!CaptureSessionEngine.automaticFrameAppearsStationary(
        unchangedDifference: 9,
        unchangedPixelFraction: 0.80,
        bestDisplacedDifference: 10,
    ))
    #expect(!CaptureSessionEngine.automaticFrameAppearsStationary(
        unchangedDifference: 15,
        unchangedPixelFraction: 0.97,
        bestDisplacedDifference: 4,
    ))
}

@Test func completedImagesUseTheUserManagedLangshotsDirectory() {
    let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("langshots", isDirectory: true)
    #expect(CaptureSessionEngine.resultDirectory.standardizedFileURL == expected.standardizedFileURL)
}

@Test func startupCleanupDeletesOnlyExpiredLangShotImages() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory.appendingPathComponent("langshot-cleanup-test-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }

    let expired = directory.appendingPathComponent("langShot-expired.png")
    let recent = directory.appendingPathComponent("langShot-recent.png")
    let unrelated = directory.appendingPathComponent("family-photo.png")
    let unsupported = directory.appendingPathComponent("langShot-not-an-image.txt")
    for file in [expired, recent, unrelated, unsupported] {
        #expect(fileManager.createFile(atPath: file.path, contents: Data([1, 2, 3])))
    }

    let now = Date(timeIntervalSince1970: 2_000_000_000)
    try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-(8 * 24 * 60 * 60))], ofItemAtPath: expired.path)
    try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-(6 * 24 * 60 * 60))], ofItemAtPath: recent.path)
    try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-(30 * 24 * 60 * 60))], ofItemAtPath: unrelated.path)
    try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-(30 * 24 * 60 * 60))], ofItemAtPath: unsupported.path)

    let removed = try CaptureSessionEngine.cleanupExpiredResults(in: directory, now: now)
    #expect(removed == 1)
    #expect(!fileManager.fileExists(atPath: expired.path))
    #expect(fileManager.fileExists(atPath: recent.path))
    #expect(fileManager.fileExists(atPath: unrelated.path))
    #expect(fileManager.fileExists(atPath: unsupported.path))
}

@Test func startupCleanupDoesNotFollowASymlinkedResultsDirectory() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("langshot-symlink-test-\(UUID().uuidString)", isDirectory: true)
    let target = root.appendingPathComponent("target", isDirectory: true)
    let link = root.appendingPathComponent("langshots", isDirectory: true)
    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    let protectedFile = target.appendingPathComponent("langShot-protected.png")
    #expect(fileManager.createFile(atPath: protectedFile.path, contents: Data([1])))
    try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

    let removed = try CaptureSessionEngine.cleanupExpiredResults(
        in: link,
        now: Date(timeIntervalSince1970: 2_000_000_000),
        retentionInterval: 0
    )
    #expect(removed == 0)
    #expect(fileManager.fileExists(atPath: protectedFile.path))
}

private func makeStripedImage() throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: 2,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 8,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw TestImageError.context }

    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    context.setFillColor(NSColor.systemRed.cgColor)
    context.fill(CGRect(x: 0, y: 2, width: 2, height: 2))
    guard let image = context.makeImage() else { throw TestImageError.image }
    return image
}

private func makeRowGradientImage(width: Int = 2, height: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw TestImageError.context }
    for row in 0..<height {
        let value = CGFloat(row + 1) / CGFloat(height + 1)
        context.setFillColor(red: value, green: value, blue: value, alpha: 1)
        context.fill(CGRect(x: 0, y: row, width: width, height: 1))
    }
    guard let image = context.makeImage() else { throw TestImageError.image }
    return image
}

private func addRedOverlay(to image: CGImage, topOriginRect: CGRect) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw TestImageError.context }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.setFillColor(NSColor.systemRed.cgColor)
    context.fill(CGRect(
        x: topOriginRect.minX,
        y: CGFloat(image.height) - topOriginRect.maxY,
        width: topOriginRect.width,
        height: topOriginRect.height
    ))
    guard let result = context.makeImage() else { throw TestImageError.image }
    return result
}

private enum TestImageError: Error { case context, image }
