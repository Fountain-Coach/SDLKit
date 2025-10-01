import Foundation
import SDLKit

@main
@MainActor
struct SDLKitSecretsCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else { return printUsage() }
        var key: String?
        var value: String?
        var backend: Secrets.Backend = Secrets.defaultBackend()

        var it = args.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--key", "-k": key = it.next()
            case "--value", "-v": value = it.next()
            case "--backend", "-b":
                if let b = it.next() {
                    switch b {
                    case "keychain": backend = .keychain(service: "SDLKit")
                    case "secret-service": backend = .secretService(service: "SDLKit")
                    case "file":
                        let pwd = ProcessInfo.processInfo.environment["SDLKIT_SECRET_PASSWORD"] ?? "change-me"
                        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                        backend = .file(url: cwd.appendingPathComponent(".fountain/secrets.json"), password: pwd, iterations: 600_000)
                    default: break
                    }
                }
            default: break
            }
        }

        do {
            switch cmd {
            case "set":
                guard let k = key, let v = value else { return printUsage() }
                try Secrets.store(key: k, data: Data(v.utf8), backend: backend)
                print("Secret set for \(k)")
            case "get":
                guard let k = key else { return printUsage() }
                if let data = try Secrets.retrieve(key: k, backend: backend), let s = String(data: data, encoding: .utf8) {
                    print(s)
                } else {
                    print("")
                }
            case "delete":
                guard let k = key else { return printUsage() }
                try Secrets.delete(key: k, backend: backend)
                print("Secret deleted for \(k)")
            default:
                printUsage()
            }
        } catch {
            print("SDLKitSecrets error: \(error)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        Usage: sdlkit-secrets <set|get|delete> --key KEY [--value VALUE] [--backend keychain|secret-service|file]
        """)
    }
}

