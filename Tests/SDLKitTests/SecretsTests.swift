import XCTest
@testable import SDLKit

final class SecretsTests: XCTestCase {
    func testFileBackendRoundTrip() throws {
        // Force file backend to avoid platform-specific keychains in CI
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("sdlkit-secrets-test.json")
        let backend = Secrets.Backend.file(url: tmp, password: "test-pass", iterations: 100_000)
        let key = "unit.test.key"
        let value = "s3cr3t"

        try? Secrets.delete(key: key, backend: backend)
        try Secrets.store(key: key, data: Data(value.utf8), backend: backend)
        let retrieved = try Secrets.retrieve(key: key, backend: backend)
        XCTAssertEqual(String(data: retrieved ?? Data(), encoding: .utf8), value)
        try Secrets.delete(key: key, backend: backend)
        let afterDelete = try Secrets.retrieve(key: key, backend: backend)
        XCTAssertNil(afterDelete)
    }
}

