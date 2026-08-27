import ApplicationServices
import CoreGraphics
import Foundation

public struct SelectionCandidate: Equatable, Sendable {
    public enum Source: String, Sendable { case accessibilityElement, window }

    public let rect: CGRect
    public let source: Source

    public init(rect: CGRect, source: Source) {
        self.rect = rect
        self.source = source
    }
}

public final class SelectionCandidateService: @unchecked Sendable {
    private struct TargetWindow {
        let rect: CGRect
        let ownerPID: pid_t
    }

    private let minimumSize = CGSize(width: 24, height: 24)

    public init() {}

    public func processIdentifier(at point: CGPoint) -> pid_t? {
        targetWindow(at: point)?.ownerPID
    }

    public func candidate(at point: CGPoint, inside displayBounds: CGRect) -> SelectionCandidate? {
        guard let window = targetWindow(at: point) else { return nil }

        if AXIsProcessTrusted(),
           let elementRect = accessibilityCandidate(
               at: point,
               ownerPID: window.ownerPID,
               windowRect: window.rect,
               displayBounds: displayBounds
           ) {
            return SelectionCandidate(rect: elementRect, source: .accessibilityElement)
        }

        let clippedWindow = window.rect.intersection(displayBounds)
        guard isUsable(clippedWindow, containing: point) else { return nil }
        return SelectionCandidate(rect: clippedWindow, source: .window)
    }

    private func targetWindow(at point: CGPoint) -> TargetWindow? {
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let ownPID = getpid()
        for info in rawWindows {
            guard let layer = info[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value != ownPID,
                  let bounds = info[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  rect.contains(point) else { continue }

            if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0.01 { continue }
            return TargetWindow(rect: rect, ownerPID: owner.int32Value)
        }
        return nil
    }

    private func accessibilityCandidate(
        at point: CGPoint,
        ownerPID: pid_t,
        windowRect: CGRect,
        displayBounds: CGRect
    ) -> CGRect? {
        let application = AXUIElementCreateApplication(ownerPID)
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hitElement) == .success,
              var element = hitElement else { return nil }

        var fallback: CGRect?
        for depth in 0..<14 {
            if let frame = frame(of: element) {
                let clipped = frame.intersection(windowRect).intersection(displayBounds)
                if isUsable(clipped, containing: point) {
                    if isPreferred(role(of: element), rect: clipped, depth: depth) { return clipped }
                    if fallback == nil { fallback = clipped }
                }
            }
            guard let parent = parent(of: element) else { break }
            element = parent
        }
        return fallback
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              position.x.isFinite, position.y.isFinite,
              size.width.isFinite, size.height.isFinite else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func isPreferred(_ role: String?, rect: CGRect, depth: Int) -> Bool {
        guard let role else { return false }
        let structuralRoles: Set<String> = [
            kAXScrollAreaRole as String,
            kAXGroupRole as String,
            kAXSplitGroupRole as String,
            kAXListRole as String,
            kAXTableRole as String,
            kAXOutlineRole as String,
            kAXBrowserRole as String,
            kAXSheetRole as String,
            kAXWindowRole as String
        ]
        if structuralRoles.contains(role) { return true }

        let interactiveRoles: Set<String> = [
            kAXButtonRole as String,
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXImageRole as String
        ]
        return depth <= 2 && interactiveRoles.contains(role) && rect.width >= 40 && rect.height >= 24
    }

    private func isUsable(_ rect: CGRect, containing point: CGPoint) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.contains(point) &&
            rect.width >= minimumSize.width && rect.height >= minimumSize.height
    }
}
