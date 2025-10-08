import XCTest
@testable import SDLKit
// Import guard mirrors library flag
#if OPENAPI_USE_YAMS
import Yams
#endif

final class OpenAPIConversionTests: XCTestCase {
    func testOpenAPIYAMLServedMatchesFile() async throws {
        let path = "Sources/SDLKitAPI/openapi.yaml"
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("OpenAPI spec not present at \(path)")
        }
        let fileData = try Data(contentsOf: fileURL)
        let served = await MainActor.run { () -> Data in
            let agent = SDLKitJSONAgent()
            return agent.handle(path: "/openapi.yaml", body: Data())
        }
        XCTAssertEqual(served, fileData, "Served YAML should match root spec file exactly")
    }

    func testOpenAPIJSONMatchesYAMLConversionDeep() async throws {
        #if OPENAPI_USE_YAMS
        let yamlPath = "Sources/SDLKitAPI/openapi.yaml"
        let yamlURL = URL(fileURLWithPath: yamlPath)
        guard FileManager.default.fileExists(atPath: yamlURL.path) else {
            throw XCTSkip("OpenAPI spec not present at \(yamlPath)")
        }
        let yamlData = try Data(contentsOf: yamlURL)
        // Convert via our converter
        guard let converted = OpenAPIConverter.yamlToJSON(yamlData) else {
            XCTFail("Converter returned nil")
            return
        }
        // Get agent-served JSON
        let served = await MainActor.run { () -> Data in
            let agent = SDLKitJSONAgent()
            return agent.handle(path: "/openapi.json", body: Data())
        }

        // Parse both into top-level objects
        let cObj = try JSONSerialization.jsonObject(with: converted)
        let sObj = try JSONSerialization.jsonObject(with: served)

        // Deep compare recursively
        XCTAssertTrue(deepEqualJSON(cObj, sObj), "Converted YAML JSON and served JSON must be deeply equal")

        // Canonicalize with sorted keys and re-compare bytes for stability
        let cCan = try JSONSerialization.data(withJSONObject: cObj, options: [.sortedKeys])
        let sCan = try JSONSerialization.data(withJSONObject: sObj, options: [.sortedKeys])
        XCTAssertEqual(cCan, sCan, "Canonical JSON (sorted keys) should match byte-for-byte")
        #else
        throw XCTSkip("Yams disabled; skipping conversion test")
        #endif
    }

    func testOpenAPIJSONConversionCachesBetweenCalls() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SDLKitOpenAPICacheTest-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let yamlURL = tmpDir.appendingPathComponent("spec.yaml")
        let yaml = """
        openapi: 3.1.0
        info:
          title: Cache Test
          version: 1.0.0
        paths: {}
        """
        try yaml.write(to: yamlURL, atomically: true, encoding: .utf8)

        setenv("SDLKIT_OPENAPI_PATH", yamlURL.path, 1)
        defer { unsetenv("SDLKIT_OPENAPI_PATH") }

        var conversions = 0
        await MainActor.run {
            SDLKitJSONAgent.resetOpenAPICacheForTesting()
            SDLKitJSONAgent._openAPIConversionObserver = { conversions += 1 }
        }

        await MainActor.run {
            let agent = SDLKitJSONAgent()
            for _ in 0..<3 {
                let data = agent.handle(path: "/openapi.json", body: Data())
                XCTAssertFalse(data.isEmpty)
            }
        }

        XCTAssertEqual(conversions, 1, "YAML to JSON conversion should run only once for repeated requests")

        await MainActor.run {
            SDLKitJSONAgent._openAPIConversionObserver = nil
            SDLKitJSONAgent.resetOpenAPICacheForTesting()
        }
    }
}

// MARK: - Helpers
private func deepEqualJSON(_ a: Any, _ b: Any) -> Bool {
    switch (a, b) {
    case let (da as [String: Any], db as [String: Any]):
        if da.count != db.count { return false }
        let aKeys = Set(da.keys)
        let bKeys = Set(db.keys)
        if aKeys != bKeys { return false }
        for k in aKeys { if !deepEqualJSON(da[k]!, db[k]!) { return false } }
        return true
    case let (aa as [Any], ab as [Any]):
        if aa.count != ab.count { return false }
        for i in 0..<aa.count { if !deepEqualJSON(aa[i], ab[i]) { return false } }
        return true
    case let (ba as Bool, bb as Bool):
        return ba == bb
    case let (na as NSNumber, nb as NSNumber):
        // Treat numbers numerically (avoid bools which were already handled above)
        return na == nb
    case let (sa as String, sb as String):
        return sa == sb
    case (_ as NSNull, _ as NSNull):
        return true
    default:
        return false
    }
}
