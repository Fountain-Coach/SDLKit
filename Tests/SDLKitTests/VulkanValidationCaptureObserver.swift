#if os(Linux) && canImport(VulkanMinimal)
import XCTest
@testable import SDLKit

@MainActor
private final class VulkanValidationCaptureObserver: NSObject, XCTestObservation {
    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        let env = ProcessInfo.processInfo.environment["SDLKIT_VK_VALIDATION_CAPTURE"]?.lowercased()
        let shouldEnforce = env == "1" || env == "true" || env == "yes"
        guard shouldEnforce else { return }
        let messages = VulkanRenderBackend.drainCapturedValidationMessages()
        guard messages.isEmpty else {
            let joined = messages.joined(separator: "\n")
            fputs("Vulkan validation warnings captured during tests:\n\(joined)\n", stderr)
            fatalError("Vulkan validation warnings detected")
        }
    }
}

@MainActor
private let _vulkanValidationCaptureObserver = VulkanValidationCaptureObserver()
#endif
