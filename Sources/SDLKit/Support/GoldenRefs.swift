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
        SettingsStore.setString("golden.last.key", key)
        #else
        // No-op in fallback mode
        _ = (value, key)
        #endif
    }
}

#if canImport(FountainStore)
import FountainStore

// Document stored in FountainStore for golden references
private struct GoldenDoc: Codable, Identifiable {
    let id: String
    let hash: String
}

// Bridge using FountainStore package (async store with collections)
private enum FSBridge {
    static func storePath() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(".fountain/sdlkit", isDirectory: true)
    }
    static func getString(forKey key: String) -> String? {
        runBlocking {
            let path = storePath()
            let store = try await FountainStore.open(.init(path: path))
            let coll = await store.collection("goldens", of: GoldenDoc.self)
            if let doc = try await coll.get(id: key) { return doc.hash }
            return nil
        }
    }
    static func setString(_ value: String, forKey key: String) {
        _ = runBlocking {
            let path = storePath()
            let store = try await FountainStore.open(.init(path: path))
            let coll = await store.collection("goldens", of: GoldenDoc.self)
            try await coll.put(GoldenDoc(id: key, hash: value))
            return true
        }
    }
    private static func runBlocking<T: Sendable>(_ body: @escaping @Sendable () async throws -> T?) -> T? {
        let sem = DispatchSemaphore(value: 0)
        var result: T?
        Task {
            defer { sem.signal() }
            do {
                result = try await body()
            } catch {
                result = nil
            }
        }
        sem.wait()
        return result
    }
}
#endif
