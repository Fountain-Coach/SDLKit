import XCTest
@testable import SDLKit
// Import guard mirrors library flag
#if OPENAPI_USE_YAMS
import Yams
#endif

final class OpenAPIConversionTests: XCTestCase {
    @MainActor
    func testOpenAPIYAMLServedMatchesFile() throws {
        let path = "sdlkit.gui.v1.yaml"
        let fileData = try Data(contentsOf: URL(fileURLWithPath: path))
        let agent = SDLKitJSONAgent()
        let served = agent.handle(path: "/openapi.yaml", body: Data())
        XCTAssertEqual(served, fileData, "Served YAML should match root spec file exactly")
    }

    @MainActor
    func testOpenAPIJSONMatchesYAMLConversionDeep() throws {
        #if OPENAPI_USE_YAMS
        let yamlPath = "sdlkit.gui.v1.yaml"
        let yamlData = try Data(contentsOf: URL(fileURLWithPath: yamlPath))
        // Convert via our converter
        guard let converted = OpenAPIConverter.yamlToJSON(yamlData) else {
            XCTFail("Converter returned nil")
            return
        }
        // Get agent-served JSON
        let agent = SDLKitJSONAgent()
        let served = agent.handle(path: "/openapi.json", body: Data())

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
