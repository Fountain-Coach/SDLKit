import XCTest
@testable import SDLKit

extension SDLRenderer.RawScreenshot: @unchecked Sendable {}
extension SDLRenderer.PNGScreenshot: @unchecked Sendable {}

final class SDLKitScreenshotTests: XCTestCase {
    private struct RawReq: Codable { let window_id: Int }
    private struct PNGReq: Codable { let window_id: Int; let format: String }
    private struct ErrorEnvelope: Codable { struct Err: Codable { let code: String; let details: String? }; let error: Err }

    func testRawScreenshotJSONShape() async throws {
        let (raw, response) = try await MainActor.run { () -> (SDLRenderer.RawScreenshot, Data) in
            let raw = SDLRenderer.RawScreenshot(raw_base64: "QUJD", width: 4, height: 2, pitch: 16, format: "ABGR8888")
            let agent = SDLKitJSONAgent(agent: MockScreenshotAgent(raw: raw, png: .failure(.notImplemented)))
            let body = try JSONEncoder().encode(RawReq(window_id: 7))
            let response = agent.handle(path: SDLKitJSONAgent.Endpoint.screenshot.rawValue, body: body)
            return (raw, response)
        }
        let decoded = try JSONDecoder().decode(SDLRenderer.RawScreenshot.self, from: response)
        XCTAssertEqual(decoded.raw_base64, raw.raw_base64)
        XCTAssertEqual(decoded.width, raw.width)
        XCTAssertEqual(decoded.format, "ABGR8888")
    }

    func testPNGScreenshotJSONShape() async throws {
        let fallback = Self.fallbackRaw()
        let (png, response) = try await MainActor.run { () -> (SDLRenderer.PNGScreenshot, Data) in
            let png = SDLRenderer.PNGScreenshot(png_base64: "UE5H", width: 10, height: 5, format: "PNG")
            let agent = SDLKitJSONAgent(agent: MockScreenshotAgent(raw: fallback, png: .success(png)))
            let body = try JSONEncoder().encode(PNGReq(window_id: 3, format: "png"))
            let response = agent.handle(path: SDLKitJSONAgent.Endpoint.screenshot.rawValue, body: body)
            return (png, response)
        }
        let decoded = try JSONDecoder().decode(SDLRenderer.PNGScreenshot.self, from: response)
        XCTAssertEqual(decoded.png_base64, png.png_base64)
        XCTAssertEqual(decoded.height, png.height)
        XCTAssertEqual(decoded.format, "PNG")
    }

    func testPNGScreenshotNotImplementedErrorDetails() async throws {
        let fallback = Self.fallbackRaw()
        let response = try await MainActor.run { () -> Data in
            let agent = SDLKitJSONAgent(agent: MockScreenshotAgent(raw: fallback, png: .failure(.notImplemented)))
            let body = try JSONEncoder().encode(PNGReq(window_id: 1, format: "png"))
            return agent.handle(path: SDLKitJSONAgent.Endpoint.screenshot.rawValue, body: body)
        }
        let error = try JSONDecoder().decode(ErrorEnvelope.self, from: response)
        XCTAssertEqual(error.error.code, "not_implemented")
        XCTAssertEqual(error.error.details, "PNG screenshots require SDL_image; retry with format \"raw\".")
    }

    private static func fallbackRaw() -> SDLRenderer.RawScreenshot {
        SDLRenderer.RawScreenshot(raw_base64: "QUJDRA==", width: 2, height: 2, pitch: 8, format: "ABGR8888")
    }
}

@MainActor
private final class MockScreenshotAgent: SDLKitGUIAgent {
    private let raw: SDLRenderer.RawScreenshot
    private let png: Result<SDLRenderer.PNGScreenshot, AgentError>

    init(raw: SDLRenderer.RawScreenshot, png: Result<SDLRenderer.PNGScreenshot, AgentError>) {
        self.raw = raw
        self.png = png
        super.init()
    }

    override func screenshotRaw(windowId: Int) throws -> SDLRenderer.RawScreenshot {
        return raw
    }

    override func screenshotPNG(windowId: Int) throws -> SDLRenderer.PNGScreenshot {
        switch png {
        case .success(let shot):
            return shot
        case .failure(let error):
            throw error
        }
    }
}
