import Testing
import Foundation
@testable import LangShotCore

@Test func manifestAndTileRoundTripIsLossless() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SessionStore(root: root)
    var manifest = SessionManifest(sessionId: "session-1", mode: .manual)
    try store.create(manifest)
    let tile = try store.writeTile(sessionId: manifest.sessionId, tileId: "tile-1", y: 0, height: 2, data: Data([1, 2, 3, 4]))
    manifest.tiles.append(tile)
    manifest.effectiveHeight = 2
    try store.save(manifest)
    #expect(try store.load(sessionId: "session-1") == manifest)
}

@Test func unsafeSessionIdentifiersAreRejected() throws {
    let store = SessionStore(root: FileManager.default.temporaryDirectory)
    #expect(throws: SessionStoreError.invalidSessionId) {
        try store.create(SessionManifest(sessionId: "../escape", mode: .manual))
    }
}

