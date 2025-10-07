import Foundation

public final class AudioMonitor: @unchecked Sendable {
    private let cap: SDLAudioCapture
    private let pump: SDLAudioChunkedCapturePump
    private let playback: SDLAudioPlayback
    private let queue: SDLAudioPlaybackQueue
    private let resampler: SDLAudioResampler?
    private let chunkFrames: Int
    private var running = true
    private var thread: Thread?

    public init(capture: SDLAudioCapture, pump: SDLAudioChunkedCapturePump, playback: SDLAudioPlayback, chunkFrames: Int = 1024) throws {
        self.cap = capture
        self.pump = pump
        self.playback = playback
        self.queue = SDLAudioPlaybackQueue(playback: playback, capacityFrames: capture.spec.sampleRate, chunkFrames: chunkFrames)
        self.chunkFrames = max(128, chunkFrames)
        if capture.spec.sampleRate != playback.spec.sampleRate || capture.spec.channels != playback.spec.channels || capture.spec.format != .f32 || playback.spec.format != .f32 {
            self.resampler = try SDLAudioResampler(src: capture.spec, dst: playback.spec)
        } else {
            self.resampler = nil
        }
        let t = Thread { [weak self] in self?.runLoop() }
        t.name = "SDLKit.AudioMonitor"
        t.qualityOfService = .userInteractive
        self.thread = t
        t.start()
    }

    public func stop() { running = false }

    private func runLoop() {
        var buf = Array(repeating: Float(0), count: chunkFrames * cap.spec.channels)
        while running {
            let got = pump.readFrames(into: &buf)
            if got > 0 {
                let samples = Array(buf.prefix(got * cap.spec.channels))
                if let r = resampler {
                    if let out = try? r.convert(samples: samples) { queue.enqueue(samples: out) }
                } else {
                    queue.enqueue(samples: samples)
                }
            } else {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }

    
}
