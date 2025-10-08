import Foundation
import SDLKitAPI
import SDLKitAPIServerAdapter

@main
struct Main {
  static func main() async throws {
    let api = SDLKitAPIServerAdapter()
    // Health
    let healthOut = try await api.health(headers: .init())
    switch healthOut {
    case .ok(let ok):
      if case .json(let body) = ok.body {
        let payload = try JSONEncoder().encode(["ok": body.ok ?? true])
        if let str = String(data: payload, encoding: .utf8) { print(str) }
      }
    default:
      print("{\"ok\":false}")
    }
    // Version
    let versionOut = try await api.version(headers: .init())
    switch versionOut {
    case .ok(let ok):
      if case .json(let body) = ok.body {
        let payload = try JSONEncoder().encode(["version": body.version])
        if let str = String(data: payload, encoding: .utf8) { print(str) }
      }
    default:
      print("{\"version\":\"unknown\"}")
    }
  }
}
