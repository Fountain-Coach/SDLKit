import Foundation

public protocol KeyValueStore {
    func getString(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
}

public protocol FountainStoreNamespace {
    func keyValue() -> KeyValueStore
}

public enum FountainStoreError: Error {
    case openFailed
}

public enum FountainStore {
    public static func open(namespace: String) throws -> FountainStoreNamespace {
        let root = Self.defaultRoot()
        let nsRoot = root.appendingPathComponent(namespace, isDirectory: true)
        return try FileNamespace(root: nsRoot)
    }

    public static func inMemory(namespace: String) throws -> FountainStoreNamespace {
        return MemoryNamespace()
    }

    private static func defaultRoot() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(".fountain", isDirectory: true)
    }
}

// MARK: - File-backed store
final class FileNamespace: FountainStoreNamespace {
    private let root: URL
    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func keyValue() -> KeyValueStore { FileKVStore(fileURL: root.appendingPathComponent("kv.json")) }
}

final class FileKVStore: KeyValueStore {
    private let fileURL: URL
    private var cache: [String: String]
    private let q = DispatchQueue(label: "FountainStore.FileKVStore")
    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([String:String].self, from: data) {
            self.cache = decoded
        } else {
            self.cache = [:]
        }
    }
    func getString(forKey key: String) -> String? {
        return q.sync { cache[key] }
    }
    func setString(_ value: String, forKey key: String) {
        q.sync {
            cache[key] = value
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}

// MARK: - In-memory store
final class MemoryNamespace: FountainStoreNamespace {
    func keyValue() -> KeyValueStore { MemoryKVStore.shared }
}

final class MemoryKVStore: KeyValueStore {
    static let shared = MemoryKVStore()
    private var cache: [String: String] = [:]
    func getString(forKey key: String) -> String? { cache[key] }
    func setString(_ value: String, forKey key: String) { cache[key] = value }
}

