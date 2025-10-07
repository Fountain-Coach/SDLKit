import Foundation

final class AudioA2MStream {
    private let sessId: Int
    private let sess: SDLKitJSONAgent.CaptureSessionProxy
    private let a2m: AudioA2MStub
    private let featCPU: AudioFeaturePump?
    private let gpuState: SDLKitJSONAgent.GPUStreamProxy?
    private let lock = NSLock()
    private var events: [MIDIEvent] = []
    private var nextFrameIndex: Int = 0
    private var running = true
    private var thread: Thread?

    private let sink: ((MIDIEvent) -> Void)?

    private var overlapMono: [Float] = []
    private var frameIndex: Int = 0

    init(sessId: Int, sess: SDLKitJSONAgent.CaptureSessionProxy, a2m: AudioA2MStub, featCPU: AudioFeaturePump?, gpuState: SDLKitJSONAgent.GPUStreamProxy?, sink: ((MIDIEvent) -> Void)? = nil) {
        self.sessId = sessId
        self.sess = sess
        self.a2m = a2m
        self.featCPU = featCPU
        self.gpuState = gpuState
        self.sink = sink
        let t = Thread { [weak self] in self?.runLoop() }
        t.name = "SDLKit.A2MStream"
        t.qualityOfService = .userInitiated
        self.thread = t
        t.start()
    }

    func stop() { running = false }

    func poll(since: Int, max: Int) -> [MIDIEvent] {
        lock.lock(); defer { lock.unlock() }
        let start = min(since, events.count)
        let end = min(events.count, start + max)
        return Array(events[start..<end])
    }

    private func append(_ newEvents: [MIDIEvent]) {
        lock.lock(); events.append(contentsOf: newEvents); lock.unlock()
        if let sink = sink { newEvents.forEach { sink($0) } }
    }

    private func runLoop() {
        while running {
            if let cpu = featCPU {
                let res = cpu.readMel(frames: 32, melBands: cpu.melBands)
                if res.frames > 0 {
                    var framesMel: [[Float]] = []
                    framesMel.reserveCapacity(res.frames)
                    for i in 0..<res.frames { let s = i * cpu.melBands; framesMel.append(Array(res.mel[s..<(s+cpu.melBands)])) }
                    let ev = a2m.process(melFrames: framesMel, startFrameIndex: nextFrameIndex)
                    nextFrameIndex += res.frames
                    append(ev)
                } else {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            } else if let gpu = gpuState {
                // Pull raw hopSize frames from pump
                let hs = gpu.hopSize
                let chans = sess.cap.spec.channels
                var raw = Array(repeating: Float(0), count: 32 * hs * chans)
                let read = sess.pump.readFrames(into: &raw)
                if read > 0 {
                    var mono: [Float] = overlapMono; mono.reserveCapacity(overlapMono.count + read)
                    for i in 0..<read { var acc: Float = 0; for c in 0..<chans { acc += raw[i*chans + c] }; mono.append(acc / Float(chans)) }
                    var windows: [[Float]] = []
                    var idx = 0
                    while idx + gpu.frameSize <= mono.count && windows.count < 32 {
                        windows.append(Array(mono[idx..<(idx+gpu.frameSize)]))
                        idx += hs
                    }
                    overlapMono = (idx < mono.count) ? Array(mono[idx..<mono.count]) : []
                    if !windows.isEmpty {
                        var melFrames: [[Float]] = []
                        let group = DispatchGroup(); group.enter()
                        DispatchQueue.main.async {
                            melFrames = (try? gpu.gpu.process(frames: windows)) ?? []
                            group.leave()
                        }
                        group.wait()
                        let ev = a2m.process(melFrames: melFrames, startFrameIndex: nextFrameIndex)
                        nextFrameIndex += melFrames.count
                        append(ev)
                    }
                } else {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            } else {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }
}
