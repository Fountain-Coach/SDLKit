import XCTest
#if canImport(CSDL3)
import CSDL3
#endif
@testable import SDLKit

final class SDLKitTests: XCTestCase {
    func testConfigDefaultsAndEnvOverrides() {
        // Present policy defaults to explicit
        XCTAssertEqual(SDLKitConfig.presentPolicy, .explicit)

        // If SDLKIT_GUI_ENABLED is set, guiEnabled should reflect it.
        let env = ProcessInfo.processInfo.environment["SDLKIT_GUI_ENABLED"]?.lowercased()
        if let env {
            let expected = !(env == "0" || env == "false")
            XCTAssertEqual(SDLKitConfig.guiEnabled, expected)
        } else {
            // If not set, we only assert that guiEnabled returns a Bool (no crash)
            _ = SDLKitConfig.guiEnabled
        }

        let key = "SDLKIT_MAX_WINDOWS"
        let prior = getenv(key).map { String(cString: $0) }
        setenv(key, "12", 1)
        XCTAssertEqual(SDLKitConfig.maxWindows, 12)
        setenv(key, "0", 1)
        XCTAssertEqual(SDLKitConfig.maxWindows, 8)
        setenv(key, "not-a-number", 1)
        XCTAssertEqual(SDLKitConfig.maxWindows, 8)
        if let prior {
            setenv(key, prior, 1)
        } else {
            unsetenv(key)
        }
    }

    func testColorParsing() throws {
        // Hex without alpha -> opaque
        XCTAssertEqual(try SDLColor.parse("#FF0000"), 0xFFFF0000)
        XCTAssertEqual(try SDLColor.parse("0x00FF00"), 0xFF00FF00)
        XCTAssertEqual(try SDLColor.parse("0000FF"), 0xFF0000FF)
        // With alpha
        XCTAssertEqual(try SDLColor.parse("#80FF0000"), 0x80FF0000)
        // Named colors
        XCTAssertEqual(try SDLColor.parse("red"), 0xFFFF0000)
        XCTAssertEqual(try SDLColor.parse("white"), 0xFFFFFFFF)
        // CSS names
        XCTAssertEqual(try SDLColor.parse("aliceblue"), 0xFFF0F8FF)
        XCTAssertEqual(try SDLColor.parse("rebeccapurple"), 0xFF663399)
        // Invalid
        XCTAssertThrowsError(try SDLColor.parse("#XYZ"))
        XCTAssertThrowsError(try SDLColor.parse("#12345"))
    }

    func testVersionReflectsExternalSpec() async throws {
        // /version should reflect the version from the external YAML present in the repo
        let res = await MainActor.run { () -> Data in
            let agent = SDLKitJSONAgent()
            return agent.handle(path: "/version", body: Data())
        }
        struct V: Codable { let agent: String; let openapi: String }
        let v = try JSONDecoder().decode(V.self, from: res)
        XCTAssertEqual(v.agent, "sdlkit.gui.v1")
        XCTAssertEqual(v.openapi, "1.1.0")
    }

    func testCloseWindowInvokesRendererShutdown() async throws {
        #if canImport(CSDL3)
        guard SDLKitStub_IsActive() != 0 else {
            throw XCTSkip("Requires stubbed SDLKit shim")
        }
        SDLKitStub_ResetCallCounts()
        await MainActor.run {
            let agent = SDLKitGUIAgent()
            agent._testingPopulateWindows(count: 1)
            guard let renderer = agent._testingRenderer(for: 1) else {
                XCTFail("Expected renderer for test window")
                return
            }
            let rendererPtr = UnsafeMutablePointer<SDL_Renderer>.allocate(capacity: 1)
            defer { rendererPtr.deallocate() }
            let texturePtr = UnsafeMutablePointer<SDL_Texture>.allocate(capacity: 1)
            defer { texturePtr.deallocate() }
            SDLCore._testingSetInitialized(true)
            renderer.handle = rendererPtr
            renderer.textures["dummy"] = texturePtr
            XCTAssertFalse(renderer.didShutdown)
            agent.closeWindow(windowId: 1)
            XCTAssertTrue(renderer.didShutdown)
            XCTAssertTrue(renderer.textures.isEmpty)
        }
        XCTAssertEqual(SDLKitStub_DestroyRendererCallCount(), 1)
        XCTAssertEqual(SDLKitStub_QuitCallCount(), 1)
        XCTAssertEqual(SDLKitStub_TTFQuitCallCount(), 0)
        SDLKitStub_ResetCallCounts()
        #else
        throw XCTSkip("CSDL3 not available")
        #endif
    }
}
