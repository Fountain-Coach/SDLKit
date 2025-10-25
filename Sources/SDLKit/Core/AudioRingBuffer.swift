import Foundation
#if canImport(Atomics)
import Atomics
#endif

// Single-producer single-consumer ring buffer for Float samples (interleaved frames)
public final class SPSCFloatRingBuffer {
    private let capacity: Int
    private var buffer: [Float]
    #if canImport(Atomics)
    private let head: ManagedAtomic<Int>
    private let tail: ManagedAtomic<Int>
    #else
    private var headVal: Int = 0
    private var tailVal: Int = 0
    private let lock = NSLock()
    #endif

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.buffer = Array(repeating: 0, count: capacity)
        #if canImport(Atomics)
        self.head = ManagedAtomic(0)
        self.tail = ManagedAtomic(0)
        #endif
    }

    public var availableToRead: Int {
        #if canImport(Atomics)
        let h = head.load(ordering: .acquiring)
        let t = tail.load(ordering: .acquiring)
        #else
        lock.lock(); let h = headVal; let t = tailVal; lock.unlock()
        #endif
        return h >= t ? (h - t) : (capacity - (t - h))
    }

    public var availableToWrite: Int { capacity - 1 - availableToRead }

    // Producer: push up to count samples; returns written count
    public func write(_ src: UnsafeBufferPointer<Float>) -> Int {
        let count = src.count
        if count == 0 { return 0 }
        #if canImport(Atomics)
        var h = head.load(ordering: .acquiring)
        let t = tail.load(ordering: .acquiring)
        #else
        lock.lock(); var h = headVal; let t = tailVal; lock.unlock()
        #endif
        let free = h >= t ? (capacity - (h - t) - 1) : (t - h - 1)
        if free <= 0 { return 0 }
        let n = min(count, free)
        let first = min(n, capacity - h)
        buffer.withUnsafeMutableBufferPointer { dst in
            if first > 0 {
                dst.baseAddress!.advanced(by: h).update(from: src.baseAddress!, count: first)
            }
            if n > first {
                let rem = n - first
                dst.baseAddress!.update(from: src.baseAddress!.advanced(by: first), count: rem)
            }
        }
        h = (h + n) % capacity
        #if canImport(Atomics)
        head.store(h, ordering: .releasing)
        #else
        lock.lock(); headVal = h; lock.unlock()
        #endif
        return n
    }

    // Consumer: read up to count samples; returns read count
    public func read(into dst: UnsafeMutableBufferPointer<Float>) -> Int {
        let count = dst.count
        if count == 0 { return 0 }
        #if canImport(Atomics)
        let h = head.load(ordering: .acquiring)
        var t = tail.load(ordering: .acquiring)
        #else
        lock.lock(); let h = headVal; var t = tailVal; lock.unlock()
        #endif
        let avail = t <= h ? (h - t) : (capacity - (t - h))
        if avail <= 0 { return 0 }
        let n = min(count, avail)
        let first = min(n, capacity - t)
        buffer.withUnsafeBufferPointer { src in
            if first > 0 {
                dst.baseAddress!.update(from: src.baseAddress!.advanced(by: t), count: first)
            }
            if n > first {
                let rem = n - first
                dst.baseAddress!.advanced(by: first).update(from: src.baseAddress!, count: rem)
            }
        }
        t = (t + n) % capacity
        #if canImport(Atomics)
        tail.store(t, ordering: .releasing)
        #else
        lock.lock(); tailVal = t; lock.unlock()
        #endif
        return n
    }
}

// A helper that runs a background pump from SDLAudioCapture into the ring buffer.
public final class SDLAudioChunkedCapturePump: @unchecked Sendable {
    private let capture: SDLAudioCapture
    private let ring: SPSCFloatRingBuffer
    private let channels: Int
    private var thread: Thread?
    private var running = true

    public init(capture: SDLAudioCapture, bufferFrames: Int) {
        self.capture = capture
        self.channels = capture.spec.channels
        self.ring = SPSCFloatRingBuffer(capacity: max(1, bufferFrames * channels * 2))
        let t = Thread { [weak self] in self?.threadLoop() }
        t.name = "SDLKit.AudioPump"
        t.qualityOfService = .userInitiated
        self.thread = t
        t.start()
    }

    deinit { stop() }

    public func stop() { running = false }

    public func readFrames(into dstFrames: inout [Float]) -> Int {
        return dstFrames.withUnsafeMutableBufferPointer { buf in
            ring.read(into: buf)
        } / channels
    }

    private func threadLoop() {
        let temp = Array(repeating: Float(0), count: 4096)
        while running {
            let availFrames = capture.availableFrames()
            if availFrames <= 0 {
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }
            let wantFrames = min(availFrames, temp.count / channels)
            if wantFrames > 0 {
                var arr = Array(repeating: Float(0), count: wantFrames * channels)
                if let read = try? capture.readFrames(into: &arr), read > 0 {
                    arr.withUnsafeBufferPointer { rb in _ = ring.write(rb) }
                }
            }
        }
    }

    
}
