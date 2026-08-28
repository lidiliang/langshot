import CoreGraphics
import CoreFoundation

final class ScrollInputBlocker: @unchecked Sendable {
    static let syntheticEventMarker: Int64 = 0x4C_53_48_4F_54

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    deinit { stop() }

    func start() -> Bool {
        guard eventTap == nil else { return true }
        let eventMask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let blocker = Unmanaged<ScrollInputBlocker>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = blocker.eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                let marker = event.getIntegerValueField(.eventSourceUserData)
                return ScrollInputBlocker.shouldSuppress(type: type, sourceUserData: marker) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
    }

    nonisolated static func shouldSuppress(type: CGEventType, sourceUserData: Int64) -> Bool {
        type == .scrollWheel && sourceUserData != syntheticEventMarker
    }
}
