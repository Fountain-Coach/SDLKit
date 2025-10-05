import XCTest
@testable import SDLKit

final class AudioRingBufferTests: XCTestCase {
    func testSPSCFloatRingBufferBasic() {
        let rb = SPSCFloatRingBuffer(capacity: 8)
        var out = Array(repeating: Float(0), count: 4)
        // empty read
        XCTAssertEqual(out.withUnsafeMutableBufferPointer { rb.read(into: $0) }, 0)
        // write 3
        let inA: [Float] = [1, 2, 3]
        let wrote = inA.withUnsafeBufferPointer { rb.write($0) }
        XCTAssertEqual(wrote, 3)
        // read 2
        var out2 = Array(repeating: Float(0), count: 2)
        let read2 = out2.withUnsafeMutableBufferPointer { rb.read(into: $0) }
        XCTAssertEqual(read2, 2)
        XCTAssertEqual(out2, [1, 2])
        // write wrap-around
        let inB: [Float] = [4, 5, 6, 7, 8]
        let wroteB = inB.withUnsafeBufferPointer { rb.write($0) }
        XCTAssertGreaterThan(wroteB, 0)
        // drain remaining
        var drain = Array(repeating: Float(0), count: 6)
        let readAll = drain.withUnsafeMutableBufferPointer { rb.read(into: $0) }
        XCTAssertEqual(readAll, 1 + wroteB) // 1 remaining from first write + wroteB
    }
}

