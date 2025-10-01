import Foundation
import Dispatch
#if canImport(FountainStore)
import FountainStore
#endif

// Centralized non-secret settings persistence backed by FountainStore.
// Keys: simple names like "render.backend.override", "vk.validation", etc.
@preconcurrency public enum SettingsStore {
    public static func getString(_ key: String) -> String? {
#if canImport(FountainStore)
        if let value = FSSettingsBridge.get(key) { return value }
#endif
        return FallbackSettingsBridge.get(key)
    }

    public static func setString(_ key: String, _ value: String) {
#if canImport(FountainStore)
        FSSettingsBridge.set(key, value)
#endif
        FallbackSettingsBridge.set(key, value)
    }

    public static func getBool(_ key: String) -> Bool? {
        if let s = getString(key) {
            let v = s.lowercased()
            if ["1","true","yes","on"].contains(v) { return true }
            if ["0","false","no","off"].contains(v) { return false }
        }
        return nil
    }

    public static func setBool(_ key: String, _ value: Bool) {
        setString(key, value ? "1" : "0")
    }

    // Dump all settings into a map (key -> value) using FountainStore scan.
    public static func dumpAll() -> [String: String] {
#if canImport(FountainStore)
        let persisted = FSSettingsBridge.list()
        let fallback = FallbackSettingsBridge.list()
        if persisted.isEmpty { return fallback }
        return persisted.merging(fallback) { current, _ in current }
#else
        return FallbackSettingsBridge.list()
#endif
    }
}

#if canImport(FountainStore)
import FountainStore

private struct SettingDoc: Codable, Identifiable { let id: String; let value: String }

private enum FSSettingsBridge {
    static func path() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(".fountain/sdlkit", isDirectory: true)
    }
    static func get(_ key: String) -> String? {
        runBlocking {
            let store = try await FountainStore.open(.init(path: path()))
            let coll = await store.collection("settings", of: SettingDoc.self)
            return try await coll.get(id: key)?.value
        }
    }
    static func set(_ key: String, _ value: String) {
        _ = runBlocking {
            let store = try await FountainStore.open(.init(path: path()))
            let coll = await store.collection("settings", of: SettingDoc.self)
            try await coll.put(SettingDoc(id: key, value: value))
            return true
        }
    }
    static func list() -> [String: String] {
        runBlocking {
            let store = try await FountainStore.open(.init(path: path()))
            let coll = await store.collection("settings", of: SettingDoc.self)
            // Scan all (up to a reasonable limit)
            let docs = try await coll.scan(prefix: nil, limit: 1000, snapshot: nil)
            var out: [String: String] = [:]
            for d in docs { out[d.id] = d.value }
            return out
        } ?? [:]
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

private actor FallbackSettingsActor {
    private var storage: [String: String] = [:]
    func get(_ key: String) -> String? { storage[key] }
    func set(_ key: String, value: String) { storage[key] = value }
    func list() -> [String: String] { storage }
}

private enum FallbackSettingsBridge {
    static let actor = FallbackSettingsActor()

    static func get(_ key: String) -> String? {
        runBlocking { await actor.get(key) }
    }

    static func set(_ key: String, _ value: String) {
        runBlocking { await actor.set(key, value: value) }
    }

    static func list() -> [String: String] {
        runBlocking { await actor.list() }
    }

    private static func runBlocking<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T!
        Task.detached {
            result = await body()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
}
