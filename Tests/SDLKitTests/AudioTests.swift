import XCTest
@testable import SDLKit
#if canImport(CSDL3)
import CSDL3
#endif

final class AudioTests: XCTestCase {
    func testAudioCaptureConstructorBehaves() async throws {
        #if canImport(CSDL3)
        // In stub mode, opening should fail gracefully (returns NULL -> throws).
        if SDLKitStub_IsActive() == 1 {
            do {
                try await MainActor.run {
                    _ = try SDLAudioCapture()
                }
                XCTFail("Expected SDLAudioCapture to throw under stub")
            } catch {
                // expected
            }
            return
        }
        #endif
        #if HEADLESS_CI
        // Headless CI should report SDL unavailable
        do {
            try await MainActor.run {
                _ = try SDLAudioCapture()
            }
            XCTFail("Expected SDLAudioCapture to throw in HEADLESS_CI")
        } catch {
            // expected
        }
        #else
        // On dev machines with SDL3 and audio available, this may succeed or throw.
        // We just exercise the constructor and ensure it doesn't crash.
        _ = try? await MainActor.run {
            _ = try SDLAudioCapture()
        }
        #endif
    }
}

