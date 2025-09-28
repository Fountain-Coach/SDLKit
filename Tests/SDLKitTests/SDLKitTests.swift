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
}
