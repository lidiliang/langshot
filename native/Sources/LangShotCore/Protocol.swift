import Foundation

public let langShotProtocolVersion = 1

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct RequestEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let type: String
    public let requestId: String
    public let payload: [String: JSONValue]

    public init(protocolVersion: Int = langShotProtocolVersion, type: String, requestId: String, payload: [String: JSONValue] = [:]) {
        self.protocolVersion = protocolVersion
        self.type = type
        self.requestId = requestId
        self.payload = payload
    }

    public func validate() throws {
        guard protocolVersion == langShotProtocolVersion else { throw ProtocolError.incompatibleVersion(protocolVersion) }
        guard !type.isEmpty, !requestId.isEmpty else { throw ProtocolError.missingField }
    }
}

public struct ProtocolFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
}

public struct ResponseEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let type: String
    public let requestId: String
    public let ok: Bool
    public let payload: [String: JSONValue]?
    public let error: ProtocolFailure?

    public init(requestId: String, payload: [String: JSONValue]) {
        protocolVersion = langShotProtocolVersion
        type = "response"
        self.requestId = requestId
        ok = true
        self.payload = payload
        error = nil
    }

    public init(requestId: String, error: ProtocolFailure) {
        protocolVersion = langShotProtocolVersion
        type = "response"
        self.requestId = requestId
        ok = false
        payload = nil
        self.error = error
    }
}

public struct EventEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let type: String
    public let sessionId: String?
    public let sequence: Int
    public let payload: [String: JSONValue]

    public init(type: String, sessionId: String? = nil, sequence: Int, payload: [String: JSONValue] = [:]) {
        protocolVersion = langShotProtocolVersion
        self.type = type
        self.sessionId = sessionId
        self.sequence = sequence
        self.payload = payload
    }
}

public enum ProtocolError: Error, Equatable {
    case incompatibleVersion(Int)
    case missingField
    case unsupportedRequest(String)
}
