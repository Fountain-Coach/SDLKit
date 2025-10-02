#if canImport(Metal)
import XCTest
@testable import SDLKit

final class MetalComputeTextureBarrierTests: XCTestCase {
    func testComputeWriteThenSampleRequiresBarrier() {
        var tracker = MetalComputeTextureAccessTracker()
        let handle = TextureHandle()
        XCTAssertNil(tracker.register(handle: handle, requirement: .writable, usage: .shaderWrite))
        XCTAssertNil(tracker.register(handle: handle, requirement: .readable, usage: .shaderWrite))
        XCTAssertTrue(tracker.handlesNeedingBarrier.contains(handle))
        XCTAssertNil(tracker.failureMessage(for: handle))
    }

    func testUnsupportedWriteUsageProducesFailureMessage() {
        var tracker = MetalComputeTextureAccessTracker()
        let handle = TextureHandle()
        let message = tracker.register(handle: handle, requirement: .writable, usage: .renderTarget)
        XCTAssertNotNil(message)
        XCTAssertEqual(tracker.failureMessage(for: handle), message)
        XCTAssertTrue(tracker.handlesNeedingBarrier.isEmpty)
    }

    func testRenderTargetReadableIsAccepted() {
        var tracker = MetalComputeTextureAccessTracker()
        let handle = TextureHandle()
        XCTAssertNil(tracker.register(handle: handle, requirement: .readable, usage: .renderTarget))
        XCTAssertTrue(tracker.handlesNeedingBarrier.contains(handle))
    }
}
#endif
