import AppKit
import Testing
@testable import LangShotCore
@testable import LangShotPlatform

@Test func capturePanelPrefersTheSpaceImmediatelyBelowTheSelection() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let selection = NSRect(x: 200, y: 300, width: 800, height: 400)
    let frame = CaptureControlPanelController.panelFrame(
        near: selection,
        panelSize: NSSize(width: 330, height: 126),
        visibleFrame: visible
    )

    #expect(frame.maxY == selection.minY - 10)
    #expect(frame.maxX == selection.maxX)
}

@Test func capturePanelMovesAboveAndStaysInsideTheVisibleScreen() {
    let visible = NSRect(x: 100, y: 40, width: 900, height: 600)
    let selection = NSRect(x: 120, y: 60, width: 300, height: 200)
    let frame = CaptureControlPanelController.panelFrame(
        near: selection,
        panelSize: NSSize(width: 330, height: 126),
        visibleFrame: visible
    )

    #expect(frame.minY == selection.maxY + 10)
    #expect(frame.minX >= visible.minX + 10)
    #expect(frame.maxX <= visible.maxX - 10)
}
