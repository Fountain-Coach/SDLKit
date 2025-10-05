import XCTest
@testable import SDLKit
#if canImport(CSDL3)
import CSDL3
#endif

final class AudioTests: XCTestCase {
    func testAudioCaptureConstructorBehaves() throws {
        #if canImport(CSDL3)
        // In stub mode, opening should fail gracefully (returns NULL -> throws).
        if SDLKitStub_IsActive() == 1 {
            XCTAssertThrowsError(try SDLAudioCapture())
            return
        }
        #endif
        #if HEADLESS_CI
        // Headless CI should report SDL unavailable
        XCTAssertThrowsError(try SDLAudioCapture())
        #else
        // On dev machines with SDL3 and audio available, this may succeed or throw.
        // We just exercise the constructor and ensure it doesn't crash.
        _ = try? SDLAudioCapture()
        #endif
    }
}

