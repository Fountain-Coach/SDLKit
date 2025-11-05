// SDLKitAudio — minimal audio host facade
// On macOS, backed by AVAudioEngine SourceNode. Other platforms can add
// backends later; API remains stable for clients.

import Foundation

#if canImport(AVFoundation)
import AVFoundation

public final class SDLKitAudioHost {
    public typealias Render = (_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ frames: Int, _ sampleRate: Double) -> Void

    private var engine: AVAudioEngine?
    private var srcNode: AVAudioSourceNode?
    private let sampleRate: Double
    private let channels: Int
    private let framesPerBuffer: Int
    private let render: Render

    public init(sampleRate: Double = 48000, channels: Int = 2, framesPerBuffer: Int = 256, render: @escaping Render) {
        self.sampleRate = sampleRate
        self.channels = max(1, channels)
        self.framesPerBuffer = max(32, framesPerBuffer)
        self.render = render
    }

    public func start() throws {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let n = Int(frameCount)
            let bufs = UnsafeMutableAudioBufferListPointer(audioBufferList)
            if self.channels == 1 {
                let mono = bufs[0].mData!.bindMemory(to: Float.self, capacity: n)
                self.render(mono, mono, n, self.sampleRate)
            } else {
                let left = bufs[0].mData!.bindMemory(to: Float.self, capacity: n)
                let right = bufs[1].mData!.bindMemory(to: Float.self, capacity: n)
                self.render(left, right, n, self.sampleRate)
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.engine = engine
        self.srcNode = node
    }

    public func stop() {
        guard let engine else { return }
        engine.stop()
        self.engine = nil
        self.srcNode = nil
    }
}

#else
// Stub for non-macOS platforms or environments without AVFoundation
public final class SDLKitAudioHost {
    public typealias Render = (_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ frames: Int, _ sampleRate: Double) -> Void
    public init(sampleRate: Double = 48000, channels: Int = 2, framesPerBuffer: Int = 256, render: @escaping Render) {}
    public func start() throws {}
    public func stop() {}
}
#endif

