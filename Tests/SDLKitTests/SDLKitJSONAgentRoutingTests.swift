import XCTest
@testable import SDLKit

@MainActor
final class FakeSDLKitGUIAgent: SDLKitGUIAgent {
    struct OpenCall: Equatable {
        let title: String
        let width: Int
        let height: Int
        let windowId: Int
    }

    struct DrawRectangleCall: Equatable {
        enum Color: Equatable { case int(UInt32), string(String) }
        let windowId: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let color: Color
    }

    struct TextureLoadCall: Equatable {
        let windowId: Int
        let id: String
        let path: String
    }

    struct TextureDrawCall: Equatable {
        let windowId: Int
        let id: String
        let x: Int
        let y: Int
        let width: Int?
        let height: Int?
    }

    private(set) var openCalls: [OpenCall] = []
    private(set) var closedWindowIds: [Int] = []
    private(set) var drawRectangleCalls: [DrawRectangleCall] = []
    private(set) var textureLoadCalls: [TextureLoadCall] = []
    private(set) var textureDrawCalls: [TextureDrawCall] = []
    private(set) var screenshotPNGWindowIds: [Int] = []

    private var nextIdentifier: Int = 1
    private var existingWindows: Set<Int> = []

    override func openWindow(title: String, width: Int, height: Int) throws -> Int {
        let id = nextIdentifier
        nextIdentifier += 1
        existingWindows.insert(id)
        openCalls.append(.init(title: title, width: width, height: height, windowId: id))
        return id
    }

    override func closeWindow(windowId: Int) {
        closedWindowIds.append(windowId)
        existingWindows.remove(windowId)
    }

    override func drawRectangle(windowId: Int, x: Int, y: Int, width: Int, height: Int, color: UInt32) throws {
        guard existingWindows.contains(windowId) else { throw AgentError.windowNotFound }
        drawRectangleCalls.append(.init(windowId: windowId, x: x, y: y, width: width, height: height, color: .int(color)))
    }

    override func drawRectangle(windowId: Int, x: Int, y: Int, width: Int, height: Int, color: String) throws {
        guard existingWindows.contains(windowId) else { throw AgentError.windowNotFound }
        drawRectangleCalls.append(.init(windowId: windowId, x: x, y: y, width: width, height: height, color: .string(color)))
    }

    override func textureLoad(windowId: Int, id: String, path: String) throws {
        guard existingWindows.contains(windowId) else { throw AgentError.windowNotFound }
        textureLoadCalls.append(.init(windowId: windowId, id: id, path: path))
    }

    override func textureDraw(windowId: Int, id: String, x: Int, y: Int, width: Int?, height: Int?) throws {
        guard existingWindows.contains(windowId) else { throw AgentError.windowNotFound }
        textureDrawCalls.append(.init(windowId: windowId, id: id, x: x, y: y, width: width, height: height))
    }

    override func screenshotPNG(windowId: Int) throws -> SDLRenderer.PNGScreenshot {
        screenshotPNGWindowIds.append(windowId)
        throw AgentError.notImplemented
    }
}

final class SDLKitJSONAgentRoutingTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @MainActor
    func testOpenAndCloseWindowRoutesThroughFakeAgent() async throws {
        let fake = FakeSDLKitGUIAgent()
        let jsonAgent = SDLKitJSONAgent(agent: fake)

        let openReq = try encoder.encode(OpenWindowRequest(title: "Test", width: 320, height: 240))
        let openResp: OpenWindowResponse = try decode(jsonAgent.handle(path: SDLKitJSONAgent.Endpoint.open.rawValue, body: openReq))
        XCTAssertEqual(1, openResp.window_id)
        XCTAssertEqual(fake.openCalls, [.init(title: "Test", width: 320, height: 240, windowId: 1)])

        let closeReq = try encoder.encode(WindowRequest(window_id: openResp.window_id))
        let closeResp: OkResponse = try decode(jsonAgent.handle(path: SDLKitJSONAgent.Endpoint.close.rawValue, body: closeReq))
        XCTAssertTrue(closeResp.ok)
        XCTAssertEqual(fake.closedWindowIds, [openResp.window_id])
    }

    @MainActor
    func testDrawRectangleWithStringColorDelegatesToFakeAgent() async throws {
        let fake = FakeSDLKitGUIAgent()
        let jsonAgent = SDLKitJSONAgent(agent: fake)
        let windowId = try openWindow(agent: jsonAgent)

        let drawReq = try encoder.encode(DrawRectangleRequest(window_id: windowId, x: 10, y: 20, width: 30, height: 40, color: "#336699"))
        let drawResp: OkResponse = try decode(jsonAgent.handle(path: SDLKitJSONAgent.Endpoint.drawRect.rawValue, body: drawReq))
        XCTAssertTrue(drawResp.ok)
        XCTAssertEqual(fake.drawRectangleCalls, [
            .init(windowId: windowId, x: 10, y: 20, width: 30, height: 40, color: .string("#336699"))
        ])
    }

    @MainActor
    func testTextureLoadAndDrawRouteThroughFakeAgent() async throws {
        let fake = FakeSDLKitGUIAgent()
        let jsonAgent = SDLKitJSONAgent(agent: fake)
        let windowId = try openWindow(agent: jsonAgent)

        let loadReq = try encoder.encode(TextureLoadRequest(window_id: windowId, id: "hero", path: "hero.png"))
        let loadResp: OkResponse = try decode(jsonAgent.handle(path: SDLKitJSONAgent.Endpoint.textureLoad.rawValue, body: loadReq))
        XCTAssertTrue(loadResp.ok)
        XCTAssertEqual(fake.textureLoadCalls, [.init(windowId: windowId, id: "hero", path: "hero.png")])

        let drawReq = try encoder.encode(TextureDrawRequest(window_id: windowId, id: "hero", x: 5, y: 6, width: nil, height: nil))
        let drawResp: OkResponse = try decode(jsonAgent.handle(path: SDLKitJSONAgent.Endpoint.textureDraw.rawValue, body: drawReq))
        XCTAssertTrue(drawResp.ok)
        XCTAssertEqual(fake.textureDrawCalls, [.init(windowId: windowId, id: "hero", x: 5, y: 6, width: nil, height: nil)])
    }

    @MainActor
    func testScreenshotPngErrorTranslatedToCanonicalJSON() async throws {
        let fake = FakeSDLKitGUIAgent()
        let jsonAgent = SDLKitJSONAgent(agent: fake)
        let windowId = try openWindow(agent: jsonAgent)

        let shotReq = try encoder.encode(ScreenshotRequest(window_id: windowId, format: "png"))
        let errorResp: ErrorResponse = try decode(jsonAgent.handle(path: SDLKitJSONAgent.Endpoint.screenshot.rawValue, body: shotReq))

        XCTAssertEqual("not_implemented", errorResp.error.code)
        XCTAssertEqual("PNG screenshots require SDL_image; retry with format \"raw\".", errorResp.error.details)
        XCTAssertEqual(fake.screenshotPNGWindowIds, [windowId])
    }

    @MainActor
    func testInvalidEndpointReturnsCanonicalError() async throws {
        let fake = FakeSDLKitGUIAgent()
        let jsonAgent = SDLKitJSONAgent(agent: fake)

        let resp: ErrorResponse = try decode(jsonAgent.handle(path: "/bogus", body: Data()))
        XCTAssertEqual("invalid_endpoint", resp.error.code)
        XCTAssertEqual("/bogus", resp.error.details)
    }

    @MainActor
    func testWindowNotFoundReturnsCanonicalError() async throws {
        let fake = FakeSDLKitGUIAgent()
        let jsonAgent = SDLKitJSONAgent(agent: fake)

        let drawReq = try encoder.encode(DrawRectangleRequest(window_id: 99, x: 0, y: 0, width: 1, height: 1, color: "#ffffff"))
        let resp: ErrorResponse = try decode(jsonAgent.handle(path: SDLKitJSONAgent.Endpoint.drawRect.rawValue, body: drawReq))

        XCTAssertEqual("window_not_found", resp.error.code)
        XCTAssertNil(resp.error.details)
        XCTAssertTrue(fake.drawRectangleCalls.isEmpty)
    }

    // MARK: - Helpers

    @MainActor
    private func openWindow(agent: SDLKitJSONAgent) throws -> Int {
        let openReq = try encoder.encode(OpenWindowRequest(title: "stub", width: 100, height: 100))
        let resp: OpenWindowResponse = try decode(agent.handle(path: SDLKitJSONAgent.Endpoint.open.rawValue, body: openReq))
        return resp.window_id
    }

    private func decode<T: Decodable>(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            XCTFail("Failed to decode \(T.self): \(error)", file: file, line: line)
            throw error
        }
    }

    private struct OpenWindowRequest: Encodable {
        let title: String
        let width: Int
        let height: Int
    }

    private struct OpenWindowResponse: Decodable { let window_id: Int }
    private struct WindowRequest: Encodable { let window_id: Int }
    private struct OkResponse: Decodable { let ok: Bool }
    private struct DrawRectangleRequest: Encodable {
        let window_id: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let color: String
    }
    private struct TextureLoadRequest: Encodable { let window_id: Int; let id: String; let path: String }
    private struct TextureDrawRequest: Encodable {
        let window_id: Int
        let id: String
        let x: Int
        let y: Int
        let width: Int?
        let height: Int?
    }
    private struct ScreenshotRequest: Encodable {
        let window_id: Int
        let format: String
    }
    private struct ErrorResponse: Decodable {
        struct ErrorBody: Decodable { let code: String; let details: String? }
        let error: ErrorBody
    }
}
