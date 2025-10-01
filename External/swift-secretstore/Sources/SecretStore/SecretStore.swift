import Dispatch
import Foundation

public enum SecretStoreError: Error {
    case invalidEncoding
}

public protocol SecretStore {
    func storeSecret(_ data: Data, for key: String) throws
    func retrieveSecret(for key: String) throws -> Data?
    func deleteSecret(for key: String) throws
}

public final class FileKeystore: SecretStore {
    private let storeURL: URL
    private let password: String
    private let iterations: Int
    private let queue = DispatchQueue(label: "SecretStore.FileKeystore")

    public init(storeURL: URL, password: String, iterations: Int) throws {
        self.storeURL = storeURL
        self.password = password
        self.iterations = iterations
        try ensureParentDirectory()
    }

    public func storeSecret(_ data: Data, for key: String) throws {
        try queue.syncVoid {
            var contents = try loadContents()
            contents[key] = data.base64EncodedString()
            try writeContents(contents)
        }
    }

    public func retrieveSecret(for key: String) throws -> Data? {
        return try queue.sync {
            guard let encoded = try loadContents()[key] else { return nil }
            guard let decoded = Data(base64Encoded: encoded) else {
                throw SecretStoreError.invalidEncoding
            }
            return decoded
        }
    }

    public func deleteSecret(for key: String) throws {
        try queue.syncVoid {
            var contents = try loadContents()
            contents.removeValue(forKey: key)
            try writeContents(contents)
        }
    }

    private func ensureParentDirectory() throws {
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func loadContents() throws -> [String: String] {
        if !FileManager.default.fileExists(atPath: storeURL.path) {
            return [:]
        }
        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func writeContents(_ contents: [String: String]) throws {
        let data = try JSONEncoder().encode(contents)
        try data.write(to: storeURL, options: [.atomic])
    }
}

public final class KeychainStore: SecretStore {
    private let keystore: any SecretStore

    public init(service: String) {
        self.keystore = Self.makeStore(service: service, folder: ".secretstore/keychain")
    }

    public func storeSecret(_ data: Data, for key: String) throws {
        try keystore.storeSecret(data, for: key)
    }

    public func retrieveSecret(for key: String) throws -> Data? {
        try keystore.retrieveSecret(for: key)
    }

    public func deleteSecret(for key: String) throws {
        try keystore.deleteSecret(for: key)
    }
}

public final class SecretServiceStore: SecretStore {
    private let keystore: any SecretStore

    public init(service: String) {
        self.keystore = Self.makeStore(service: service, folder: ".secretstore/secret-service")
    }

    public func storeSecret(_ data: Data, for key: String) throws {
        try keystore.storeSecret(data, for: key)
    }

    public func retrieveSecret(for key: String) throws -> Data? {
        try keystore.retrieveSecret(for: key)
    }

    public func deleteSecret(for key: String) throws {
        try keystore.deleteSecret(for: key)
    }
}

private final class InMemoryKeystore: SecretStore {
    private var storage: [String: Data] = [:]
    private let queue = DispatchQueue(label: "SecretStore.InMemory")

    func storeSecret(_ data: Data, for key: String) throws {
        queue.syncVoid { storage[key] = data }
    }

    func retrieveSecret(for key: String) throws -> Data? {
        queue.sync { storage[key] }
    }

    func deleteSecret(for key: String) throws {
        queue.syncVoid { storage.removeValue(forKey: key) }
    }
}

private extension DispatchQueue {
    func syncVoid(_ work: () throws -> Void) rethrows {
        try sync(execute: work)
    }
}

private extension KeychainStore {
    static func makeStore(service: String, folder: String) -> any SecretStore {
        let base = FileManager.default.homeDirectoryForCurrentUser
        let directory = base.appendingPathComponent(folder, isDirectory: true)
        let url = directory.appendingPathComponent("\(service).json")
        if let store = try? FileKeystore(storeURL: url, password: service, iterations: 1) {
            return store
        }
        return InMemoryKeystore()
    }
}

private extension SecretServiceStore {
    static func makeStore(service: String, folder: String) -> any SecretStore {
        let base = FileManager.default.homeDirectoryForCurrentUser
        let directory = base.appendingPathComponent(folder, isDirectory: true)
        let url = directory.appendingPathComponent("\(service).json")
        if let store = try? FileKeystore(storeURL: url, password: service, iterations: 1) {
            return store
        }
        return InMemoryKeystore()
    }
}
