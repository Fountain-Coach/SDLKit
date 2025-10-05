import XCTest
@testable import SDLKit

final class AudioA2MStubTests: XCTestCase {
    func testStubEmitsOnAndOff() {
        let bands = 8
        let stub = AudioA2MStub(melBands: bands, energyThreshold: 0.1, minOnFrames: 1, minOffFrames: 1)
        // Build 6 frames; frames 2-4 have rising energy at band index 3
        var frames: [[Float]] = []
        for i in 0..<6 {
            var f = Array(repeating: Float(0), count: bands)
            if (2...4).contains(i) { f[3] = 0.5 }
            frames.append(f)
        }
        let ev = stub.process(melFrames: frames, startFrameIndex: 0)
        // Expect note_on at frame 2 and note_off at frame 5 (first frame with 0 after activity)
        XCTAssertTrue(ev.contains(where: { $0.kind == .note_on && $0.frameIndex == 2 }))
        XCTAssertTrue(ev.contains(where: { $0.kind == .note_off && $0.frameIndex >= 5 }))
    }
}

