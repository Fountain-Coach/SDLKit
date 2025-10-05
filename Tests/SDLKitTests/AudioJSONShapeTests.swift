import XCTest
@testable import SDLKit

final class AudioJSONShapeTests: XCTestCase {
    func testA2MTestEndpointShape() throws {
        let agent = SDLKitJSONAgent()
        let bands = 8, frames = 4
        // Create mel with one active band
        var mel: [Float] = Array(repeating: 0, count: bands * frames)
        for i in 0..<frames { mel[i*bands + 3] = 0.5 }
        let data = mel.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
        struct Req: Codable { let mel_bands: Int; let frames: Int; let mel_base64: String }
        let req = Req(mel_bands: bands, frames: frames, mel_base64: data)
        let body = try JSONEncoder().encode(req)
        let resData = agent.handle(path: "/agent/audio/a2m/test", body: body)
        struct Res: Codable { let events: [Evt] }
        struct Evt: Codable { let kind: String; let note: Int; let velocity: Int; let frameIndex: Int }
        let res = try JSONDecoder().decode(Res.self, from: resData)
        XCTAssertFalse(res.events.isEmpty)
        XCTAssertTrue(res.events.contains(where: { $0.kind == "note_on" }))
    }
}

