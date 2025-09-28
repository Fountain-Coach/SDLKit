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
        // Invalid
        XCTAssertThrowsError(try SDLColor.parse("#XYZ"))
        XCTAssertThrowsError(try SDLColor.parse("#12345"))
    }
}
