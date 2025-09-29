import XCTest
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
}
