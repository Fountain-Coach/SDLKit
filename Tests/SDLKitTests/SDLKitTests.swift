import XCTest
@testable import SDLKit

final class SDLKitTests: XCTestCase {
    func testConfigDefaults() {
        XCTAssertTrue(SDLKitConfig.guiEnabled)
        XCTAssertEqual(SDLKitConfig.presentPolicy, .explicit)
    }
}

