import Foundation
#if canImport(Yams)
import Yams
#endif

enum OpenAPIConverter {
    /// Attempts to convert OpenAPI YAML data to JSON data using Yams when available.
    /// Returns nil if conversion is not possible.
    static func yamlToJSON(_ data: Data) -> Data? {
        #if canImport(Yams)
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        do {
            let obj = try Yams.load(yaml: s)
            guard let jsonObj = obj, JSONSerialization.isValidJSONObject(jsonObj) else { return nil }
            return try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted])
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
