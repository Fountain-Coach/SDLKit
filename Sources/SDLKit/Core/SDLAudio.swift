import Foundation
#if canImport(CSDL3)
import CSDL3
#endif

#if canImport(CSDL3) && !HEADLESS_CI
// Treat SDL_AudioStream as opaque pointer on Swift side for portability
typealias SDL_AudioStream = OpaquePointer
#endif

public enum SDLAudioSampleFormat {
    case f32
    case s16

    #if canImport(CSDL3) && !HEADLESS_CI
    var cFormat: UInt32 {
        switch self {
        case .f32: return SDLKit_AudioFormat_F32()
        case .s16: return SDLKit_AudioFormat_S16()
        }
    }
    #endif

    var bytesPerSample: Int {
        switch self {
        case .f32: return 4
        case .s16: return 2
        }
    }
}

public struct SDLAudioSpec: Equatable {
    public var sampleRate: Int
    public var channels: Int
    public var format: SDLAudioSampleFormat
    public init(sampleRate: Int = 48000, channels: Int = 2, format: SDLAudioSampleFormat = .f32) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.format = format
    }
}

public enum SDLAudioDeviceKind { case playback, recording }

public struct SDLAudioDeviceInfo: Equatable {
    public let id: UInt64
    public let kind: SDLAudioDeviceKind
    public let name: String
    public let preferred: SDLAudioSpec
    public let bufferFrames: Int
}

@MainActor
public enum SDLAudioDeviceList {
    #if canImport(CSDL3) && !HEADLESS_CI
    public static func list(_ kind: SDLAudioDeviceKind) throws -> [SDLAudioDeviceInfo] {
        try SDLCore.shared.ensureInitialized()
        var ids = Array<UInt64>(repeating: 0, count: 32)
        let n: Int32 = ids.withUnsafeMutableBufferPointer { buf in
            if kind == .playback {
                return SDLKit_ListAudioPlaybackDevices(buf.baseAddress, Int32(buf.count))
            } else {
                return SDLKit_ListAudioRecordingDevices(buf.baseAddress, Int32(buf.count))
            }
        }
        if n < 0 { throw AgentError.internalError(SDLCore.lastError()) }
        var results: [SDLAudioDeviceInfo] = []
        for i in 0..<Int(n) {
            let devid = ids[i]
            guard let cname = SDLKit_GetAudioDeviceNameU64(devid) else { continue }
            let name = String(cString: cname)
            var sr: Int32 = 0, fmt: UInt32 = 0, ch: Int32 = 0, frames: Int32 = 0
            if SDLKit_GetAudioDevicePreferredFormatU64(devid, &sr, &fmt, &ch, &frames) != 0 {
                // If format query fails, provide a basic default
                sr = 48000; fmt = SDLKit_AudioFormat_F32(); ch = 2; frames = 0
            }
            let spec = SDLAudioSpec(sampleRate: Int(sr), channels: Int(ch), format: (fmt == SDLKit_AudioFormat_S16() ? .s16 : .f32))
            results.append(.init(id: devid, kind: kind, name: name, preferred: spec, bufferFrames: Int(frames)))
        }
        return results
    }
    #else
    public static func list(_ kind: SDLAudioDeviceKind) throws -> [SDLAudioDeviceInfo] {
        throw AgentError.sdlUnavailable
    }
    #endif
}

public final class SDLAudioCapture {
    public let spec: SDLAudioSpec
    #if canImport(CSDL3) && !HEADLESS_CI
    private var stream: UnsafeMutablePointer<SDL_AudioStream>?
    #endif

    public init(spec: SDLAudioSpec = SDLAudioSpec(), deviceId: UInt64? = nil) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        self.spec = spec
        try SDLCore.shared.ensureInitialized()
        let s: UnsafeMutablePointer<SDL_AudioStream>?
        if let devid = deviceId {
            s = SDLKit_OpenAudioRecordingStreamU64(devid, Int32(spec.sampleRate), spec.format.cFormat, Int32(spec.channels))
        } else {
            s = SDLKit_OpenDefaultAudioRecordingStream(Int32(spec.sampleRate), spec.format.cFormat, Int32(spec.channels))
        }
        guard let s else {
            throw AgentError.internalError(SDLCore.lastError())
        }
        self.stream = s
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    deinit { shutdown() }

    public func shutdown() {
        #if canImport(CSDL3) && !HEADLESS_CI
        if let s = stream {
            SDLKit_DestroyAudioStream(s)
            stream = nil
        }
        #endif
    }

    public var bytesPerFrame: Int {
        #if canImport(CSDL3) && !HEADLESS_CI
        return spec.channels * spec.format.bytesPerSample
        #else
        return 0
        #endif
    }

    public func availableFrames() -> Int {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let s = stream else { return 0 }
        let bytes = SDLKit_GetAudioStreamAvailable(s)
        if bytes <= 0 { return 0 }
        return Int(bytes) / bytesPerFrame
        #else
        return 0
        #endif
    }

    // Reads up to buffer.count frames into the buffer (interleaved), returns frames read.
    public func readFrames(into buffer: inout [Float]) throws -> Int {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard spec.format == .f32 else { throw AgentError.invalidArgument("readFrames currently supports .f32 only") }
        guard let s = stream else { throw AgentError.internalError("audio stream not open") }
        if buffer.isEmpty { return 0 }
        let maxFrames = buffer.count / spec.channels
        let byteCount = maxFrames * bytesPerFrame
        let rc = buffer.withUnsafeMutableBytes { raw -> Int32 in
            return SDLKit_GetAudioStreamData(s, raw.baseAddress, Int32(byteCount))
        }
        if rc < 0 { throw AgentError.internalError(SDLCore.lastError()) }
        return Int(rc) / bytesPerFrame
        #else
        throw AgentError.sdlUnavailable
        #endif
    }
}

public final class SDLAudioPlayback {
    public let spec: SDLAudioSpec
    #if canImport(CSDL3) && !HEADLESS_CI
    private var stream: UnsafeMutablePointer<SDL_AudioStream>?
    #endif

    public init(spec: SDLAudioSpec = SDLAudioSpec(), deviceId: UInt64? = nil) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        self.spec = spec
        try SDLCore.shared.ensureInitialized()
        let s: UnsafeMutablePointer<SDL_AudioStream>?
        if let devid = deviceId {
            s = SDLKit_OpenAudioPlaybackStreamU64(devid, Int32(spec.sampleRate), spec.format.cFormat, Int32(spec.channels))
        } else {
            s = SDLKit_OpenDefaultAudioPlaybackStream(Int32(spec.sampleRate), spec.format.cFormat, Int32(spec.channels))
        }
        guard let s else {
            throw AgentError.internalError(SDLCore.lastError())
        }
        self.stream = s
        #else
        self.spec = spec
        throw AgentError.sdlUnavailable
        #endif
    }

    deinit { shutdown() }

    public func shutdown() {
        #if canImport(CSDL3) && !HEADLESS_CI
        if let s = stream {
            SDLKit_DestroyAudioStream(s)
            stream = nil
        }
        #endif
    }

    public func queue(samples: UnsafeRawBufferPointer) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let s = stream else { throw AgentError.internalError("audio stream not open") }
        if samples.count == 0 { return }
        let rc = SDLKit_PutAudioStreamData(s, samples.baseAddress, Int32(samples.count))
        if rc != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func queue(samples: [Float]) throws {
        try samples.withUnsafeBytes { raw in
            try self.queue(samples: raw)
        }
    }

    // Simple sine generator helper
    public func playSine(frequency: Double, amplitude: Double = 0.2, seconds: Double) throws {
        let totalFrames = Int(Double(spec.sampleRate) * seconds)
        var buffer = Array(repeating: Float(0), count: totalFrames * spec.channels)
        let twoPi = 2.0 * Double.pi
        for i in 0..<totalFrames {
            let t = Double(i) / Double(spec.sampleRate)
            let s = Float(sin(twoPi * frequency * t) * amplitude)
            for c in 0..<spec.channels { buffer[i * spec.channels + c] = s }
        }
        try queue(samples: buffer)
    }
}

public final class SDLAudioPlaybackQueue {
    private let playback: SDLAudioPlayback
    private let ring: SPSCFloatRingBuffer
    private let channels: Int
    private let chunkFrames: Int
    private var running = true
    private let thread: Thread

    public init(playback: SDLAudioPlayback, capacityFrames: Int = 48000, chunkFrames: Int = 2048) {
        self.playback = playback
        self.channels = playback.spec.channels
        self.ring = SPSCFloatRingBuffer(capacity: max(1, capacityFrames * channels * 2))
        self.chunkFrames = max(128, chunkFrames)
        self.thread = Thread { [weak self] in self?.runLoop() }
        self.thread.name = "SDLKit.AudioPlaybackQueue"
        self.thread.qualityOfService = .userInitiated
        self.thread.start()
    }

    deinit { stop() }

    public func stop() { running = false }

    public func enqueue(samples: [Float]) {
        samples.withUnsafeBufferPointer { _ = ring.write($0) }
    }

    private func runLoop() {
        var buf = Array(repeating: Float(0), count: chunkFrames * channels)
        while running {
            let read = buf.withUnsafeMutableBufferPointer { ring.read(into: $0) }
            if read > 0 {
                let bytes = read * MemoryLayout<Float>.size
                buf.withUnsafeBytes { raw in
                    try? playback.queue(samples: UnsafeRawBufferPointer(start: raw.baseAddress, count: bytes))
                }
            } else {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }
}

public struct SDLAudioWAV {
    public let sampleRate: Int
    public let channels: Int
    public let format: SDLAudioSampleFormat
    public let data: Data

    #if canImport(CSDL3) && !HEADLESS_CI
    public static func load(path: String) throws -> SDLAudioWAV {
        var spec = SDL_AudioSpec()
        var buf: UnsafeMutablePointer<UInt8>? = nil
        var len: UInt32 = 0
        let rc = path.withCString { p in SDLKit_LoadWAV(p, &spec, &buf, &len) }
        guard rc == 0, let buf, len > 0 else { throw AgentError.internalError(SDLCore.lastError()) }
        defer { SDLKit_free(buf) }
        let data = Data(bytes: buf, count: Int(len))
        let fmt: SDLAudioSampleFormat = (spec.format == SDLKit_AudioFormat_S16()) ? .s16 : .f32
        return SDLAudioWAV(sampleRate: Int(spec.freq), channels: Int(spec.channels), format: fmt, data: data)
    }

    public func converted(to spec: SDLAudioSpec) throws -> [Float] {
        if format == .f32 && spec.sampleRate == sampleRate && spec.channels == channels {
            // reinterpret data as Float
            var out: [Float] = Array(repeating: 0, count: data.count / MemoryLayout<Float>.size)
            _ = out.withUnsafeMutableBytes { dst in data.copyBytes(to: dst) }
            return out
        }
        let src = SDLAudioSpec(sampleRate: sampleRate, channels: channels, format: format)
        let resampler = try SDLAudioResampler(src: src, dst: spec)
        if format == .f32 {
            var floats = Array(repeating: Float(0), count: data.count / MemoryLayout<Float>.size)
            _ = floats.withUnsafeMutableBytes { dst in data.copyBytes(to: dst) }
            return try resampler.convert(samples: floats)
        } else {
            // s16 -> f32 via temporary conversion
            let sampleCount = data.count / MemoryLayout<Int16>.size
            var floats = Array(repeating: Float(0), count: sampleCount)
            data.withUnsafeBytes { raw in
                let s16 = raw.bindMemory(to: Int16.self)
                for i in 0..<sampleCount { floats[i] = Float(s16[i]) / 32768.0 }
            }
            return try resampler.convert(samples: floats)
        }
    }
    #else
    public static func load(path: String) throws -> SDLAudioWAV { throw AgentError.sdlUnavailable }
    public func converted(to spec: SDLAudioSpec) throws -> [Float] { throw AgentError.sdlUnavailable }
    #endif
}

public final class SDLAudioResampler {
    #if canImport(CSDL3) && !HEADLESS_CI
    private var stream: UnsafeMutablePointer<SDL_AudioStream>?
    #endif
    public let src: SDLAudioSpec
    public let dst: SDLAudioSpec

    public init(src: SDLAudioSpec, dst: SDLAudioSpec) throws {
        self.src = src; self.dst = dst
        #if canImport(CSDL3) && !HEADLESS_CI
        try SDLCore.shared.ensureInitialized()
        guard let s = SDLKit_CreateAudioStreamConvert(Int32(src.sampleRate), src.format.cFormat, Int32(src.channels), Int32(dst.sampleRate), dst.format.cFormat, Int32(dst.channels)) else {
            throw AgentError.internalError(SDLCore.lastError())
        }
        self.stream = s
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    deinit {
        #if canImport(CSDL3) && !HEADLESS_CI
        if let s = stream { SDLKit_DestroyAudioStream(s) }
        #endif
    }

    public func convert(samples input: [Float]) throws -> [Float] {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard src.format == .f32 && dst.format == .f32 else { throw AgentError.invalidArgument("SDLAudioResampler.convert supports .f32 only") }
        guard let s = stream else { throw AgentError.internalError("resampler not initialized") }
        if input.isEmpty { return [] }
        let putRC = input.withUnsafeBytes { raw -> Int32 in
            return SDLKit_PutAudioStreamData(s, raw.baseAddress, Int32(raw.count))
        }
        if putRC != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        // Estimate space: simple upper bound (2x) for safety
        var out = Array(repeating: Float(0), count: max(1, (input.count * dst.sampleRate) / max(1, src.sampleRate) * dst.channels / max(1, src.channels) + 8))
        let outBytes = out.count * MemoryLayout<Float>.size
        let got = out.withUnsafeMutableBytes { raw -> Int32 in
            return SDLKit_GetAudioStreamData(s, raw.baseAddress, Int32(outBytes))
        }
        if got < 0 { throw AgentError.internalError(SDLCore.lastError()) }
        let samples = Int(got) / MemoryLayout<Float>.size
        if samples < out.count { out.removeSubrange(samples..<out.count) }
        return out
        #else
        throw AgentError.sdlUnavailable
        #endif
    }
}
