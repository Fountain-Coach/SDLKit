import Foundation
#if canImport(SecretStore)
import SecretStore
#endif

// Centralized secret management backed by SecretStore
@MainActor
public enum Secrets {
    public enum Backend {
        case keychain(service: String)
        case secretService(service: String)
        case file(url: URL, password: String, iterations: Int)
    }

    public static func defaultBackend() -> Backend {
        #if os(macOS)
        return .keychain(service: "SDLKit")
        #elseif os(Linux)
        if ProcessInfo.processInfo.environment["SDLKIT_USE_FILE_KEYSTORE"] == "1" {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let url = cwd.appendingPathComponent(".fountain/secrets.json")
            let pwd = ProcessInfo.processInfo.environment["SDLKIT_SECRET_PASSWORD"] ?? "change-me"
            return .file(url: url, password: pwd, iterations: 600_000)
        }
        return .secretService(service: "SDLKit")
        #else
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let url = cwd.appendingPathComponent(".fountain/secrets.json")
        let pwd = ProcessInfo.processInfo.environment["SDLKIT_SECRET_PASSWORD"] ?? "change-me"
        return .file(url: url, password: pwd, iterations: 600_000)
        #endif
    }

    public static func store(key: String, data: Data, backend: Backend = defaultBackend()) throws {
        #if canImport(SecretStore)
        let store = try makeStore(backend: backend)
        try store.storeSecret(data, for: namespaced(key))
        #else
        throw AgentError.internalError("SecretStore not available")
        #endif
    }

    public static func retrieve(key: String, backend: Backend = defaultBackend()) throws -> Data? {
        #if canImport(SecretStore)
        let store = try makeStore(backend: backend)
        return try store.retrieveSecret(for: namespaced(key))
        #else
        throw AgentError.internalError("SecretStore not available")
        #endif
    }

    public static func delete(key: String, backend: Backend = defaultBackend()) throws {
        #if canImport(SecretStore)
        let store = try makeStore(backend: backend)
        try store.deleteSecret(for: namespaced(key))
        #else
        throw AgentError.internalError("SecretStore not available")
        #endif
    }

    #if canImport(SecretStore)
    private static func makeStore(backend: Backend) throws -> any SecretStore {
        switch backend {
        case .keychain(let service):
            return KeychainStore(service: service)
        case .secretService(let service):
            return SecretServiceStore(service: service)
        case .file(let url, let password, let iterations):
            return try FileKeystore(storeURL: url, password: password, iterations: iterations)
        }
    }
    #endif

    private static func namespaced(_ key: String) -> String {
        "sdlkit." + key
    }
}

