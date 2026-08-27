import Testing
import Foundation
@testable import LangShotCore

@Test func requestRoundTripAndValidation() throws {
    let request = RequestEnvelope(type: "session.begin", requestId: "request-1", payload: ["mode": .string("manual")])
    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)
    #expect(decoded == request)
    try decoded.validate()
}

@Test func incompatibleVersionIsRejected() {
    let request = RequestEnvelope(protocolVersion: 2, type: "hello", requestId: "request-1")
    #expect(throws: ProtocolError.incompatibleVersion(2)) {
        try request.validate()
    }
}
