import XCTest
@testable import SDLKit

final class BackendHarnessTests: XCTestCase {
    private func shouldRunHarness() -> Bool {
        ProcessInfo.processInfo.environment["SDLKIT_GOLDEN"] == "1"
    }

    private var backendMatrix: [String] {
        #if os(macOS)
        return ["metal"]
        #elseif os(Windows)
        return ["d3d12"]
        #elseif os(Linux)
        return ["vulkan"]
        #else
        return []
        #endif
    }

    func testRenderBackendHarnessSuite() async throws {
        guard shouldRunHarness() else {
            throw XCTSkip("Harness disabled; set SDLKIT_GOLDEN=1 to enable")
        }

        let backends = backendMatrix
        try await MainActor.run {
            for backend in backends {
                do {
                    let results = try RenderBackendTestHarness.runFullSuite(backendOverride: backend)
                    XCTAssertEqual(results.count, RenderBackendTestHarness.Test.allCases.count,
                                   "Expected one hash per harness test")
                } catch let skip as XCTSkip {
                    throw skip
                } catch AgentError.sdlUnavailable {
                    throw XCTSkip("SDL unavailable; skipping harness suite")
                } catch AgentError.notImplemented {
                    throw XCTSkip("Shader artifacts unavailable for harness suite")
                } catch AgentError.invalidArgument(let message) {
                    throw XCTSkip(message)
                } catch RenderBackendTestHarness.HarnessError.captureUnsupported {
                    throw XCTSkip("Backend missing capture support; skipping harness suite")
                }
            }
        }
    }
}
