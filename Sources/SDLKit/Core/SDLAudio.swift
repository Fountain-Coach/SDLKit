import Foundation
#if canImport(CSDL3)
import CSDL3
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

    deinit { #if canImport(CSDL3) && !HEADLESS_CI; if let s = stream { SDLKit_DestroyAudioStream(s) }; #endif }

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
