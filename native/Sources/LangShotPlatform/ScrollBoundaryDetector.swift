import ApplicationServices
import CoreGraphics
import LangShotCore

/// Reads the vertical scrollbar exposed by the target application. A `nil`
/// result means that the application does not expose usable scroll geometry,
/// so callers can fall back to visual stationary-frame detection.
final class ScrollBoundaryDetector {
    func isAtBoundary(
        at point: CGPoint,
        processIdentifier: pid_t,
        direction: ScrollDirection
    ) -> Bool? {
        guard AXIsProcessTrusted() else { return nil }

        let application = AXUIElementCreateApplication(processIdentifier)
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            application,
            Float(point.x),
            Float(point.y),
            &hitElement
        ) == .success, var element = hitElement else { return nil }

        var boundaryStates: [Bool] = []
        for _ in 0..<20 {
            if let scrollBar = verticalScrollBar(for: element),
               let value = numberAttribute(scrollBar, kAXValueAttribute as CFString) {
                let minimum = numberAttribute(scrollBar, kAXMinValueAttribute as CFString) ?? 0
                let maximum = numberAttribute(scrollBar, kAXMaxValueAttribute as CFString) ?? 1
                if maximum > minimum {
                    boundaryStates.append(Self.isAtBoundary(
                        value: value,
                        minimum: minimum,
                        maximum: maximum,
                        direction: direction
                    ))
                }
            }
            guard let parent = elementAttribute(element, kAXParentAttribute as CFString) else { break }
            element = parent
        }
        // Wheel input can bubble from a nested scroll area to an ancestor.
        // Only report the end when every exposed vertical scroll container on
        // that path has reached the requested boundary.
        return boundaryStates.isEmpty ? nil : boundaryStates.allSatisfy { $0 }
    }

    nonisolated static func isAtBoundary(
        value: Double,
        minimum: Double,
        maximum: Double,
        direction: ScrollDirection
    ) -> Bool {
        guard value.isFinite, minimum.isFinite, maximum.isFinite, maximum > minimum else { return false }
        let tolerance = max(0.0001, (maximum - minimum) * 0.002)
        switch direction {
        case .down:
            return value >= maximum - tolerance
        case .up:
            return value <= minimum + tolerance
        }
    }

    private func verticalScrollBar(for element: AXUIElement) -> AXUIElement? {
        if stringAttribute(element, kAXRoleAttribute as CFString) == (kAXScrollBarRole as String),
           stringAttribute(element, kAXOrientationAttribute as CFString) != (kAXHorizontalOrientationValue as String) {
            return element
        }
        return elementAttribute(element, kAXVerticalScrollBarAttribute as CFString)
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func numberAttribute(_ element: AXUIElement, _ attribute: CFString) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return number.doubleValue
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
