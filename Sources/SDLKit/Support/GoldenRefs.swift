import Foundation

// Abstraction around persistence for golden references.
// Uses FountainStore where available, with an env fallback for CI.
public enum GoldenRefs {
    public static func key(backend: String, width: Int, height: Int, material: String = "basic_lit") -> String {
        return "sdlkit.golden.\(backend).\(width)x\(height).\(material)"
    }

    public static func getExpected(for key: String) -> String? {
        #if canImport(FountainStore)
        if let value = FSBridge.getString(forKey: key) { return value }
        #endif
        // Fallback to environment variable for CI/local usage
        return ProcessInfo.processInfo.environment["SDLKIT_GOLDEN_REF"]
    }

    public static func setExpected(_ value: String, for key: String) {
        #if canImport(FountainStore)
        FSBridge.setString(value, forKey: key)
        #else
        // No-op in fallback mode
        _ = (value, key)
        #endif
    }
}

#if canImport(FountainStore)
import FountainStore

// Bridge using the local FountainStore package.
private enum FSBridge {
    static func getString(forKey key: String) -> String? {
        if let ns = try? FountainStore.open(namespace: "SDLKit") {
            return ns.keyValue().getString(forKey: key)
        }
        return nil
    }
    static func setString(_ value: String, forKey key: String) {
        if let ns = try? FountainStore.open(namespace: "SDLKit") {
            ns.keyValue().setString(value, forKey: key)
        }
    }
}
#endif
