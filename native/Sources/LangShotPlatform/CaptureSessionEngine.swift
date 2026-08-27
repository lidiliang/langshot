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

@MainActor
public final class CaptureSessionEngine {
    public typealias ProgressHandler = @MainActor (CaptureProgress) -> Void
    public typealias CompletionHandler = @MainActor (Result<URL, Error>) -> Void

    private struct FrameRecord { let url: URL; let displacement: Int }
    private let sessionId: String
    private let mode: CaptureMode
    private let requestedDirection: ScrollDirection
    private let selection: RectValue
    private let overlayWindowId: CGWindowID
    private let anchor: PointValue?
    private let capture = ScreenCaptureService()
    private let matcher = OverlapMatcher(minimumDisplacement: 2, minimumOverlap: 24, confidenceThreshold: 0.68)
    private let policy = SessionPolicy()
    private let worker = DispatchQueue(label: "app.langshot.capture", qos: .userInitiated)
    private let progress: ProgressHandler
    private let completion: CompletionHandler
    private var timer: Timer?
    private var records: [FrameRecord] = []
    private var previousProbe: GrayFrame?
    private var direction: ScrollDirection?
    private var stationaryProbes = 0
    private var effectiveHeight = 0
    private var startedAt = Date()
    private var captureInFlight = false
    private var scrollTick = 0

    public init(sessionId: String, mode: CaptureMode, requestedDirection: ScrollDirection, selection: RectValue, overlayWindowId: CGWindowID, anchor: PointValue?, progress: @escaping ProgressHandler, completion: @escaping CompletionHandler) {
        self.sessionId = sessionId; self.mode = mode; self.requestedDirection = requestedDirection
        self.selection = selection; self.overlayWindowId = overlayWindowId; self.anchor = anchor
        self.progress = progress; self.completion = completion
    }

    public func start() {
        startedAt = Date()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    public func cancel() {
        timer?.invalidate(); timer = nil
        try? FileManager.default.removeItem(at: Self.sessionDirectory(sessionId))
    }

    public func pause() { timer?.invalidate(); timer = nil }

    public func resume() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    public func finishNow() { finish() }

    private func tick() {
        if mode == .automatic, let anchor {
            scrollTick += 1
            if scrollTick % 3 == 0 { postScroll(at: anchor, direction: requestedDirection) }
        }
        sample()
    }

    private func sample() {
        guard !captureInFlight else { return }
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
        do {
            if previousProbe == nil {
                let url = try persist(image: image, index: 0)
                records.append(FrameRecord(url: url, displacement: image.height))
                effectiveHeight = image.height
                previousProbe = probe
                progress(CaptureProgress(height: effectiveHeight, frames: 1, confidence: 1))
                return
            }
            guard let previousProbe else { return }
            let candidates = try [ScrollDirection.down, .up].map { ($0, try matcher.match(previous: previousProbe, current: probe, direction: $0)) }
            guard let best = candidates.max(by: { $0.1.confidence < $1.1.confidence }), best.1.accepted else {
                stationaryProbes += 1
                if records.count > 1, stationaryProbes >= 30 { finish() }
                return
            }
            if let direction, direction != best.0 { return }
            direction = best.0
            stationaryProbes = 0
            let additional = policy.acceptedAdditionalHeight(currentHeight: effectiveHeight, proposed: best.1.displacement)
            guard additional > 0 else { finish(); return }
            let url = try persist(image: image, index: records.count)
            records.append(FrameRecord(url: url, displacement: additional))
            effectiveHeight += additional
            self.previousProbe = probe
            progress(CaptureProgress(height: effectiveHeight, frames: records.count, confidence: best.1.confidence))
            let boundary = policy.boundary(mode: mode, elapsed: Date().timeIntervalSince(startedAt), currentHeight: effectiveHeight, proposedAdditionalHeight: 0, stationaryProbes: 0)
            if boundary == .heightLimit || boundary == .durationLimit { finish() }
        } catch { fail(error) }
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        guard !records.isEmpty else { return fail(ScreenCaptureError.captureFailed) }
        let records = self.records, direction = self.direction ?? requestedDirection, sessionId = self.sessionId, completion = self.completion
        worker.async {
            do { let url = try CaptureSessionEngine.compose(records: records, direction: direction, sessionId: sessionId); DispatchQueue.main.async { completion(.success(url)) } }
            catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }

    private func fail(_ error: Error) { timer?.invalidate(); timer = nil; completion(.failure(error)) }

    private func persist(image: CGImage, index: Int) throws -> URL {
        let directory = Self.sessionDirectory(sessionId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(String(format: "frame-%05d.png", index))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else { throw ScreenCaptureError.imageEncodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.imageEncodingFailed }
        return url
    }

    private nonisolated static func compose(records: [FrameRecord], direction: ScrollDirection, sessionId: String) throws -> URL {
        let ordered = direction == .down ? records : records.reversed()
        let images = try ordered.map { record -> (CGImage, Int) in
            guard let source = CGImageSourceCreateWithURL(record.url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ScreenCaptureError.captureFailed }
            return (image, record.displacement)
        }
        let width = images.map { $0.0.width }.max() ?? 1
        let height = min(60_000, images.first!.0.height + images.dropFirst().reduce(0) { $0 + $1.1 })
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScreenCaptureError.imageEncodingFailed }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        var y = 0
        context.draw(images[0].0, in: CGRect(x: 0, y: 0, width: images[0].0.width, height: images[0].0.height)); y += images[0].0.height
        for (image, displacement) in images.dropFirst() where y < height {
            let sliceHeight = min(displacement, height - y)
            guard let slice = image.cropping(to: CGRect(x: 0, y: image.height - sliceHeight, width: image.width, height: sliceHeight)) else { continue }
            context.draw(slice, in: CGRect(x: 0, y: y, width: slice.width, height: slice.height)); y += sliceHeight
        }
        guard let final = context.makeImage() else { throw ScreenCaptureError.imageEncodingFailed }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? sessionDirectory(sessionId)
        let output = desktop.appendingPathComponent("langShot-\(formatter.string(from: Date())).png")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, kUTTypePNG, 1, nil) else { throw ScreenCaptureError.imageEncodingFailed }
        CGImageDestinationAddImage(destination, final, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.imageEncodingFailed }
        return output
    }

    private nonisolated static func sessionDirectory(_ sessionId: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("app.langshot/sessions/\(sessionId)", isDirectory: true)
    }

    private func postScroll(at point: PointValue, direction: ScrollDirection) {
        let delta: Int32 = direction == .down ? -4 : 4
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
        event.location = CGPoint(x: point.x, y: point.y); event.post(tap: .cghidEventTap)
    }

    private nonisolated static func makeProbe(_ image: CGImage) throws -> GrayFrame {
        let width = min(256, image.width)
        let height = max(32, Int(Double(image.height) * Double(width) / Double(image.width)))
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ScreenCaptureError.imageEncodingFailed }
        context.interpolationQuality = .low; context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }
}
