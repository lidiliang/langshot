import Foundation

public struct TileRecord: Codable, Equatable, Sendable {
    public let id: String
    public let relativePath: String
    public let y: Int
    public let height: Int
    public let checksum: UInt64
}

public struct SessionManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sessionId: String
    public var mode: CaptureMode
    public var state: SessionState
    public var effectiveHeight: Int
    public var tiles: [TileRecord]

    public init(sessionId: String, mode: CaptureMode, state: SessionState = .selecting, effectiveHeight: Int = 0, tiles: [TileRecord] = []) {
        schemaVersion = 1
        self.sessionId = sessionId
        self.mode = mode
        self.state = state
        self.effectiveHeight = effectiveHeight
        self.tiles = tiles
    }
}

public enum SessionStoreError: Error, Equatable { case invalidSessionId, missingManifest, checksumMismatch }

public final class SessionStore: @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public func create(_ manifest: SessionManifest) throws {
        let directory = try sessionDirectory(manifest.sessionId)
        try fileManager.createDirectory(at: directory.appendingPathComponent("tiles"), withIntermediateDirectories: true)
        try save(manifest)
    }

    public func save(_ manifest: SessionManifest) throws {
        let directory = try sessionDirectory(manifest.sessionId)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    public func load(sessionId: String) throws -> SessionManifest {
        let url = try sessionDirectory(sessionId).appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else { throw SessionStoreError.missingManifest }
        let manifest = try decoder.decode(SessionManifest.self, from: Data(contentsOf: url))
        for tile in manifest.tiles {
            let data = try Data(contentsOf: try sessionDirectory(sessionId).appendingPathComponent(tile.relativePath))
            guard checksum(data) == tile.checksum else { throw SessionStoreError.checksumMismatch }
        }
        return manifest
    }

    public func writeTile(sessionId: String, tileId: String, y: Int, height: Int, data: Data) throws -> TileRecord {
        let directory = try sessionDirectory(sessionId).appendingPathComponent("tiles")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let relativePath = "tiles/\(tileId).rgba"
        try data.write(to: try sessionDirectory(sessionId).appendingPathComponent(relativePath), options: .atomic)
        return TileRecord(id: tileId, relativePath: relativePath, y: y, height: height, checksum: checksum(data))
    }

    public func discard(sessionId: String) throws {
        let directory = try sessionDirectory(sessionId)
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
    }

    private func sessionDirectory(_ sessionId: String) throws -> URL {
        guard !sessionId.isEmpty, sessionId.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
            throw SessionStoreError.invalidSessionId
        }
        return root.appendingPathComponent(sessionId, isDirectory: true)
    }

    private func checksum(_ data: Data) -> UInt64 {
        data.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}

