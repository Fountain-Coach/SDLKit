import XCTest
@testable import SDLKit

final class SettingsStoreTests: XCTestCase {
    func testSetGetString() throws {
        SettingsStore.setString("unit.test.setting", "abc")
        XCTAssertEqual(SettingsStore.getString("unit.test.setting"), "abc")
    }

    func testSetGetBool() throws {
        SettingsStore.setBool("unit.test.bool", true)
        XCTAssertEqual(SettingsStore.getBool("unit.test.bool"), true)
        SettingsStore.setBool("unit.test.bool", false)
        XCTAssertEqual(SettingsStore.getBool("unit.test.bool"), false)
    }
}

