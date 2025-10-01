import XCTest
@testable import SecretStore

final class SecretStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = directory.appendingPathComponent("SecretStoreTests.json")
        let store = try FileKeystore(storeURL: url, password: "test", iterations: 1)
        try? store.deleteSecret(for: "example")

        let payload = Data("payload".utf8)
        try store.storeSecret(payload, for: "example")
        let loaded = try store.retrieveSecret(for: "example")
        XCTAssertEqual(loaded, payload)

        try store.deleteSecret(for: "example")
        XCTAssertNil(try store.retrieveSecret(for: "example"))
    }
}
