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

public final class SDLAudioCapture {
    #if canImport(CSDL3) && !HEADLESS_CI
    private var stream: UnsafeMutablePointer<SDL_AudioStream>?
    private let spec: SDLAudioSpec
    #endif

    public init(spec: SDLAudioSpec = SDLAudioSpec()) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        self.spec = spec
        try SDLCore.shared.ensureInitialized()
        guard let s = SDLKit_OpenDefaultAudioRecordingStream(Int32(spec.sampleRate), spec.format.cFormat, Int32(spec.channels)) else {
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
    #if canImport(CSDL3) && !HEADLESS_CI
    private var stream: UnsafeMutablePointer<SDL_AudioStream>?
    private let spec: SDLAudioSpec
    #endif

    public init(spec: SDLAudioSpec = SDLAudioSpec()) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        self.spec = spec
        try SDLCore.shared.ensureInitialized()
        guard let s = SDLKit_OpenDefaultAudioPlaybackStream(Int32(spec.sampleRate), spec.format.cFormat, Int32(spec.channels)) else {
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
        samples.withUnsafeBytes { raw in
            try? self.queue(samples: raw)
        }
    }
}
