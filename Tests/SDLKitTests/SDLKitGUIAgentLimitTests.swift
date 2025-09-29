import XCTest
@testable import SDLKit

final class SDLKitGUIAgentLimitTests: XCTestCase {
    func testOpenWindowHonorsMaxWindowCap() async throws {
        let key = "SDLKIT_MAX_WINDOWS"
        let priorValue = getenv(key).map { String(cString: $0) }
        setenv(key, "2", 1)
        defer {
            if let priorValue {
                setenv(key, priorValue, 1)
            } else {
                unsetenv(key)
            }
        }

        try await MainActor.run {
            let agent = SDLKitGUIAgent()
            agent._testingPopulateWindows(count: SDLKitConfig.maxWindows)
            XCTAssertThrowsError(try agent.openWindow(title: "overflow", width: 100, height: 100)) { error in
                guard case AgentError.invalidArgument(let message) = error else {
                    return XCTFail("Expected invalidArgument, got: \(error)")
                }
                XCTAssertTrue(message.contains("2"), "Error message should mention the configured limit")
            }
        }
    }
}
