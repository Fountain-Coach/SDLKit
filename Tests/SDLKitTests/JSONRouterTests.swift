import XCTest
@testable import SDLKit

final class JSONRouterTests: XCTestCase {
    private struct ErrorEnvelope: Decodable {
        struct ErrorBody: Decodable { let code: String }
        let error: ErrorBody
    }

    private struct VersionEnvelope: Decodable {
        let agent: String
        let openapi: String
    }

    func testUnknownEndpointsReturnExpectedErrors() async throws {
        await MainActor.run {
            SDLKitJSONAgent.resetOpenAPICacheForTesting()
        }

        let unknownData = await MainActor.run { () -> Data in
            let agent = SDLKitJSONAgent()
            return agent.handle(path: "/agent/gui/unknown", body: Data())
        }
        let unknown = try JSONDecoder().decode(ErrorEnvelope.self, from: unknownData)
        XCTAssertEqual(unknown.error.code, "not_implemented")

        let nonAgentData = await MainActor.run { () -> Data in
            let agent = SDLKitJSONAgent()
            return agent.handle(path: "/foo", body: Data())
        }
        let nonAgent = try JSONDecoder().decode(ErrorEnvelope.self, from: nonAgentData)
        XCTAssertEqual(nonAgent.error.code, "invalid_endpoint")
    }

    func testExternalJSONSpecServedViaEnvironmentPath() async throws {
        await MainActor.run {
            SDLKitJSONAgent.resetOpenAPICacheForTesting()
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDLKitJSONRouterTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let jsonURL = tmpDir.appendingPathComponent("spec.json")
        let spec: [String: Any] = [
            "openapi": "3.1.0",
            "info": [
                "title": "External Spec",
                "version": "9.9.9"
            ],
            "paths": [:],
            "components": [:]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: spec, options: [.sortedKeys])
        try jsonData.write(to: jsonURL)

        let originalEnv = ProcessInfo.processInfo.environment["SDLKIT_OPENAPI_PATH"]
        setenv("SDLKIT_OPENAPI_PATH", jsonURL.path, 1)
        addTeardownBlock {
            if let originalEnv {
                setenv("SDLKIT_OPENAPI_PATH", originalEnv, 1)
            } else {
                unsetenv("SDLKIT_OPENAPI_PATH")
            }
        }

        let (openapiData, versionData) = await MainActor.run { () -> (Data, Data) in
            let agent = SDLKitJSONAgent()
            return (
                agent.handle(path: "/openapi.json", body: Data()),
                agent.handle(path: "/version", body: Data())
            )
        }

        XCTAssertEqual(openapiData, jsonData)

        let version = try JSONDecoder().decode(VersionEnvelope.self, from: versionData)
        XCTAssertEqual(version.openapi, "9.9.9")
        XCTAssertEqual(version.agent, SDLKitOpenAPI.agentVersion)
    }

    func testRemovingExternalSpecFallsBackToEmbeddedVersion() async throws {
        await MainActor.run {
            SDLKitJSONAgent.resetOpenAPICacheForTesting()
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDLKitJSONRouterTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let jsonURL = tmpDir.appendingPathComponent("spec.json")
        let spec: [String: Any] = [
            "openapi": "3.1.0",
            "info": [
                "title": "External Spec",
                "version": "4.5.6"
            ],
            "paths": [:],
            "components": [:]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: spec, options: [.sortedKeys])
        try jsonData.write(to: jsonURL)

        let originalEnv = ProcessInfo.processInfo.environment["SDLKIT_OPENAPI_PATH"]
        setenv("SDLKIT_OPENAPI_PATH", jsonURL.path, 1)
        addTeardownBlock {
            if let originalEnv {
                setenv("SDLKIT_OPENAPI_PATH", originalEnv, 1)
            } else {
                unsetenv("SDLKIT_OPENAPI_PATH")
            }
        }

        let initialVersionData = await MainActor.run { () -> Data in
            let agent = SDLKitJSONAgent()
            return agent.handle(path: "/version", body: Data())
        }
        let initialVersion = try JSONDecoder().decode(VersionEnvelope.self, from: initialVersionData)
        XCTAssertEqual(initialVersion.openapi, "4.5.6")
        XCTAssertEqual(initialVersion.agent, SDLKitOpenAPI.agentVersion)

        try FileManager.default.removeItem(at: jsonURL)

        let (fallbackJSON, fallbackVersionData) = await MainActor.run { () -> (Data, Data) in
            let agent = SDLKitJSONAgent()
            return (
                agent.handle(path: "/openapi.json", body: Data()),
                agent.handle(path: "/version", body: Data())
            )
        }

        XCTAssertEqual(fallbackJSON, SDLKitOpenAPI.json)

        let fallbackVersion = try JSONDecoder().decode(VersionEnvelope.self, from: fallbackVersionData)
        XCTAssertEqual(fallbackVersion.openapi, SDLKitOpenAPI.specVersion)
        XCTAssertEqual(fallbackVersion.agent, SDLKitOpenAPI.agentVersion)
    }
}
