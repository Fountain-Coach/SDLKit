import Foundation

@MainActor
public struct SDLKitJSONAgent {
    private let agent: SDLKitGUIAgent
    public init() { self.agent = SDLKitGUIAgent() }
    public init(agent: SDLKitGUIAgent) { self.agent = agent }

    // Minimal audio session store (preview)
    private struct CaptureSession { let cap: SDLAudioCapture; let pump: SDLAudioChunkedCapturePump; var feat: AudioFeaturePump?; var a2m: AudioA2MStub?; var featureFrameCursor: Int }
    private static var _capStore: [Int: CaptureSession] = [:]
    private static var _playStore: [Int: SDLAudioPlayback] = [:]
    private static var _playQueues: [Int: SDLAudioPlaybackQueue] = [:]
    private static var _monitors: [Int: AudioMonitor] = [:] // keyed by capture audio_id
    private static var _nextAudioId: Int = 1

    private struct GPUState { let gpu: AudioGPUFeatureExtractor; let frameSize: Int; let hopSize: Int; let melBands: Int; var overlapMono: [Float]; var prevMel: [Float]? }
    private enum GPUStore {
        private static var map: [Int: GPUState] = [:]
        static func set(_ id: Int, gpu: AudioGPUFeatureExtractor, frameSize: Int, hopSize: Int, melBands: Int) { map[id] = GPUState(gpu: gpu, frameSize: frameSize, hopSize: hopSize, melBands: melBands, overlapMono: [], prevMel: nil) }
        static func get(_ id: Int) -> (gpu: AudioGPUFeatureExtractor, frameSize: Int, hopSize: Int, melBands: Int)? {
            guard let s = map[id] else { return nil }
            return (s.gpu, s.frameSize, s.hopSize, s.melBands)
        }
        static func buildWindowsAppend(audioId: Int, mono: [Float], frameSize: Int, hopSize: Int, maxFrames: Int) -> [[Float]] {
            guard var s = map[audioId] else { return [] }
            var seq = s.overlapMono
            seq.append(contentsOf: mono)
            var out: [[Float]] = []
            var idx = 0
            while idx + frameSize <= seq.count && out.count < maxFrames {
                out.append(Array(seq[idx..<(idx+frameSize)]))
                idx += hopSize
            }
            s.overlapMono = (idx < seq.count) ? Array(seq[idx..<seq.count]) : []
            map[audioId] = s
            return out
        }
        static func getPrevMel(_ id: Int) -> [Float]? { map[id]?.prevMel }
        static func setPrevMel(_ id: Int, prev: [Float]?) { if var s = map[id] { s.prevMel = prev; map[id] = s } }
    }

    public enum Endpoint: String {
        case open = "/agent/gui/window/open"
        case close = "/agent/gui/window/close"
        case show = "/agent/gui/window/show"
        case hide = "/agent/gui/window/hide"
        case resize = "/agent/gui/window/resize"
        case setTitle = "/agent/gui/window/setTitle"
        case setPosition = "/agent/gui/window/setPosition"
        case getInfo = "/agent/gui/window/getInfo"
        case maximize = "/agent/gui/window/maximize"
        case minimize = "/agent/gui/window/minimize"
        case restore = "/agent/gui/window/restore"
        case setFullscreen = "/agent/gui/window/setFullscreen"
        case setOpacity = "/agent/gui/window/setOpacity"
        case setAlwaysOnTop = "/agent/gui/window/setAlwaysOnTop"
        case center = "/agent/gui/window/center"
        case present = "/agent/gui/present"
        case drawRect = "/agent/gui/drawRectangle"
        case clear = "/agent/gui/clear"
        case drawLine = "/agent/gui/drawLine"
        case drawCircleFilled = "/agent/gui/drawCircleFilled"
        case drawText = "/agent/gui/drawText"
        case captureEvent = "/agent/gui/captureEvent"
        case openapiYAML = "/openapi.yaml"
        case openapiJSON = "/openapi.json"
        case health = "/health"
        case version = "/version"
        case clipboardGet = "/agent/gui/clipboard/get"
        case clipboardSet = "/agent/gui/clipboard/set"
        case inputKeyboard = "/agent/gui/input/getKeyboardState"
        case inputMouse = "/agent/gui/input/getMouseState"
        case displayList = "/agent/gui/display/list"
        case displayGetInfo = "/agent/gui/display/getInfo"
        case textureLoad = "/agent/gui/texture/load"
        case textureDraw = "/agent/gui/texture/draw"
        case textureFree = "/agent/gui/texture/free"
        case textureDrawTiled = "/agent/gui/texture/drawTiled"
        case textureDrawRotated = "/agent/gui/texture/drawRotated"
        case screenshot = "/agent/gui/screenshot/capture"
        case renderGetOutputSize = "/agent/gui/render/getOutputSize"
        case renderGetScale = "/agent/gui/render/getScale"
        case renderSetScale = "/agent/gui/render/setScale"
        case renderGetDrawColor = "/agent/gui/render/getDrawColor"
        case renderSetDrawColor = "/agent/gui/render/setDrawColor"
        case renderGetViewport = "/agent/gui/render/getViewport"
        case renderSetViewport = "/agent/gui/render/setViewport"
        case renderGetClipRect = "/agent/gui/render/getClipRect"
        case renderSetClipRect = "/agent/gui/render/setClipRect"
        case renderDisableClipRect = "/agent/gui/render/disableClipRect"
        case drawPoints = "/agent/gui/drawPoints"
        case drawLines = "/agent/gui/drawLines"
        case drawRects = "/agent/gui/drawRects"
        // Audio (preview)
        case audioDevices = "/agent/audio/devices"
        case audioCaptureOpen = "/agent/audio/capture/open"
        case audioCaptureRead = "/agent/audio/capture/read"
        case audioPlaybackOpen = "/agent/audio/playback/open"
        case audioPlaybackSine = "/agent/audio/playback/sine"
        case audioFeaturesStart = "/agent/audio/features/start"
        case audioFeaturesReadMel = "/agent/audio/features/read_mel"
        case audioA2MStart = "/agent/audio/a2m/start"
        case audioA2MRead = "/agent/audio/a2m/read"
        case audioPlaybackQueueOpen = "/agent/audio/playback/queue/open"
        case audioPlaybackQueueEnqueue = "/agent/audio/playback/queue/enqueue"
        case audioPlaybackPlayWAV = "/agent/audio/playback/play_wav"
        case audioMonitorStart = "/agent/audio/monitor/start"
        case audioMonitorStop = "/agent/audio/monitor/stop"
    }

    private struct CacheSignature: Equatable {
        let path: String
        let mtime: Date?
        let size: UInt64?

        func matches(_ other: CacheSignature) -> Bool {
            guard path == other.path else { return false }
            switch (mtime, other.mtime) {
            case (nil, nil): break
            case let (lhs?, rhs?) where lhs == rhs: break
            default: return false
            }
            switch (size, other.size) {
            case (nil, nil): break
            case let (lhs?, rhs?) where lhs == rhs: break
            default: return false
            }
            return true
        }
    }

    private struct CachedFile {
        let signature: CacheSignature
        let data: Data
    }

    private struct CachedConversion {
        let data: Data
        let sourceSignature: CacheSignature
        let sourceData: Data

        func matches(_ file: CachedFile) -> Bool {
            if sourceSignature.matches(file.signature) { return true }
            guard sourceSignature.path == file.signature.path else { return false }
            return sourceData == file.data
        }
    }

    private static var cachedOpenAPIEnvPath: String?
    private static var externalYAMLCache: CachedFile?
    private static var externalJSONCache: CachedFile?
    private static var yamlConversionCache: CachedConversion?
    internal static var _openAPIConversionObserver: (() -> Void)?

    public func handle(path: String, body: Data) -> Data {
        guard let ep = Endpoint(rawValue: path) else {
            if path.hasPrefix("/agent/gui/") { return Self.errorJSON(code: "not_implemented", details: path) }
            return Self.errorJSON(code: "invalid_endpoint", details: path)
        }
        do {
            switch ep {
            case .audioDevices:
                struct R: Codable { struct D: Codable { let id: UInt64; let kind: String; let name: String; let sample_rate: Int; let channels: Int; let format: String; let buffer_frames: Int }; let playback: [D]; let recording: [D] }
                let playback = try SDLAudioDeviceList.list(.playback).map { d in R.D(id: d.id, kind: "playback", name: d.name, sample_rate: d.preferred.sampleRate, channels: d.preferred.channels, format: d.preferred.format == .f32 ? "f32" : "s16", buffer_frames: d.bufferFrames) }
                let recording = try SDLAudioDeviceList.list(.recording).map { d in R.D(id: d.id, kind: "recording", name: d.name, sample_rate: d.preferred.sampleRate, channels: d.preferred.channels, format: d.preferred.format == .f32 ? "f32" : "s16", buffer_frames: d.bufferFrames) }
                return try JSONEncoder().encode(R(playback: playback, recording: recording))
            case .audioCaptureOpen:
                struct Req: Codable { let device_id: UInt64?; let sample_rate: Int?; let channels: Int?; let format: String? }
                struct Res: Codable { let audio_id: Int }
                let req = try JSONDecoder().decode(Req.self, from: body)
                let fmt: SDLAudioSampleFormat = (req.format?.lowercased() == "s16") ? .s16 : .f32
                let spec = SDLAudioSpec(sampleRate: req.sample_rate ?? 48000, channels: req.channels ?? 2, format: fmt)
                let cap = try SDLAudioCapture(spec: spec, deviceId: req.device_id)
                // Choose a generous ring buffer (0.5s) for now
                let pump = SDLAudioChunkedCapturePump(capture: cap, bufferFrames: max(2048, spec.sampleRate / 2))
                let aid = Self._nextAudioId; Self._nextAudioId += 1; Self._capStore[aid] = CaptureSession(cap: cap, pump: pump, feat: nil, a2m: nil, featureFrameCursor: 0)
                return try JSONEncoder().encode(Res(audio_id: aid))
            case .audioCaptureRead:
                struct Req: Codable { let audio_id: Int; let frames: Int }
                struct Res: Codable { let frames: Int; let channels: Int; let format: String; let data_base64: String }
                let req = try JSONDecoder().decode(Req.self, from: body)
                guard let sess = Self._capStore[req.audio_id] else { throw AgentError.invalidArgument("unknown audio_id") }
                var framesBuf = Array(repeating: Float(0), count: max(0, req.frames) * sess.cap.spec.channels)
                let gotFrames = sess.pump.readFrames(into: &framesBuf)
                let data = Data(bytes: framesBuf, count: gotFrames * sess.cap.spec.channels * MemoryLayout<Float>.size)
                let out = Res(frames: gotFrames, channels: sess.cap.spec.channels, format: "f32", data_base64: data.base64EncodedString())
                return try JSONEncoder().encode(out)
            case .audioPlaybackOpen:
                struct Req: Codable { let device_id: UInt64?; let sample_rate: Int?; let channels: Int?; let format: String? }
                struct Res: Codable { let audio_id: Int }
                let req = try JSONDecoder().decode(Req.self, from: body)
                let fmt: SDLAudioSampleFormat = (req.format?.lowercased() == "s16") ? .s16 : .f32
                let spec = SDLAudioSpec(sampleRate: req.sample_rate ?? 48000, channels: req.channels ?? 2, format: fmt)
                let pb = try SDLAudioPlayback(spec: spec, deviceId: req.device_id)
                let aid = Self._nextAudioId; Self._nextAudioId += 1; Self._playStore[aid] = pb
                return try JSONEncoder().encode(Res(audio_id: aid))
            case .audioPlaybackSine:
                struct Req: Codable { let audio_id: Int; let frequency: Double; let seconds: Double; let amplitude: Double? }
                let req = try JSONDecoder().decode(Req.self, from: body)
                guard let pb = Self._playStore[req.audio_id] else { throw AgentError.invalidArgument("unknown audio_id") }
                try pb.playSine(frequency: req.frequency, amplitude: req.amplitude ?? 0.2, seconds: req.seconds)
                return Self.okJSON()
            case .audioFeaturesStart:
                struct Req: Codable { let audio_id: Int; let frame_size: Int?; let hop_size: Int?; let mel_bands: Int?; let use_gpu: Bool?; let window_id: Int?; let backend: String? }
                struct Res: Codable { let ok: Bool }
                let req = try JSONDecoder().decode(Req.self, from: body)
                guard var sess = Self._capStore[req.audio_id] else { throw AgentError.invalidArgument("unknown audio_id") }
                let fs = req.frame_size ?? 2048
                let hs = req.hop_size ?? max(256, fs/4)
                let mb = req.mel_bands ?? 64
                var ok = false
                if (req.use_gpu ?? false), let windowId = req.window_id {
                    // Try GPU path
                    if let backend = try? agent.makeRenderBackend(windowId: windowId, override: req.backend) {
                        if let gpu = AudioGPUFeatureExtractor(backend: backend, sampleRate: sess.cap.spec.sampleRate, frameSize: fs, melBands: mb) {
                            // Store GPU settings in session by piggybacking on feat=nil and tracking overlap in cap store via featureFrameCursor only for timestamps.
                            // We don't persist GPU extractor; we process on-demand in readMel using this backend each call would need a gpu ref; store via feat=nil and not used.
                            // For simplicity here, keep CPU pump for raw frames and do GPU extraction on read.
                            sess.feat = nil
                            // Keep a placeholder by attaching a2m to nil; we only need to know we're GPU-enabled. We encode a sentinel by setting featureFrameCursor = -1
                            sess.featureFrameCursor = -1
                            // We'll stash the extractor in a static map keyed by audio_id to reuse between reads.
                            GPUStore.set(req.audio_id, gpu: gpu, frameSize: fs, hopSize: hs, melBands: mb)
                            ok = true
                        }
                    }
                }
                if !ok {
                    if let feat = AudioFeaturePump(capture: sess.cap, pump: sess.pump, frameSize: fs, hopSize: hs, melBands: mb) {
                        sess.feat = feat
                        Self._capStore[req.audio_id] = sess
                        ok = true
                    } else {
                        throw AgentError.invalidArgument("invalid feature config (frame_size must be power-of-two)")
                    }
                }
                Self._capStore[req.audio_id] = sess
                return try JSONEncoder().encode(Res(ok: ok))
            case .audioFeaturesReadMel:
                struct Req: Codable { let audio_id: Int; let frames: Int; let mel_bands: Int }
                struct Res: Codable { let frames: Int; let mel_bands: Int; let mel_base64: String; let onset_base64: String }
                let req = try JSONDecoder().decode(Req.self, from: body)
                guard let sess = Self._capStore[req.audio_id] else { throw AgentError.invalidArgument("features not started for audio_id") }
                var got = 0
                var mel: [Float] = []
                var onset: [Float] = []
                if let feat = sess.feat {
                    let res = feat.readMel(frames: req.frames, melBands: req.mel_bands)
                    got = res.frames; mel = res.mel; onset = res.onset
                } else if let g = GPUStore.get(req.audio_id) {
                    // GPU path on-demand: pull raw frames from pump and window them
                    let fs = g.frameSize, hs = g.hopSize, mb = g.melBands
                    let framesToMake = min(req.frames, 64)
                    // read framesToMake * hs frames
                    var raw = Array(repeating: Float(0), count: framesToMake * hs * sess.cap.spec.channels)
                    let read = sess.pump.readFrames(into: &raw)
                    if read > 0 {
                        // downmix
                        let chans = sess.cap.spec.channels
                        let frameCount = read
                        var mono = [Float](); mono.reserveCapacity(frameCount)
                        for i in 0..<frameCount {
                            var acc: Float = 0
                            for c in 0..<chans { acc += raw[i*chans + c] }
                            mono.append(acc / Float(chans))
                        }
                        // build windows from overlap store
                        let windows = GPUStore.buildWindowsAppend(audioId: req.audio_id, mono: mono, frameSize: fs, hopSize: hs, maxFrames: framesToMake)
                        let melFrames = (try? g.gpu.process(frames: windows)) ?? []
                        // flatten mel
                        mel.reserveCapacity(melFrames.count * mb)
                        var prev: [Float]? = GPUStore.getPrevMel(req.audio_id)
                        for mf in melFrames {
                            mel.append(contentsOf: mf)
                            if let p = prev {
                                let n = min(p.count, mf.count)
                                var flux: Float = 0
                                for i in 0..<n { let d = mf[i]-p[i]; if d > 0 { flux += d } }
                                onset.append(flux)
                            } else { onset.append(0) }
                            prev = mf
                        }
                        GPUStore.setPrevMel(req.audio_id, prev: prev)
                        got = melFrames.count
                    }
                } else {
                    throw AgentError.invalidArgument("features not started for audio_id")
                }
                let melData = mel.withUnsafeBufferPointer { Data(buffer: $0) }
                let onsetData = onset.withUnsafeBufferPointer { Data(buffer: $0) }
                let out = Res(frames: got, mel_bands: req.mel_bands, mel_base64: melData.base64EncodedString(), onset_base64: onsetData.base64EncodedString())
                return try JSONEncoder().encode(out)
            case .audioPlaybackQueueOpen:
                struct Req: Codable { let device_id: UInt64?; let sample_rate: Int?; let channels: Int?; let format: String? }
                struct Res: Codable { let audio_id: Int }
                let req = try JSONDecoder().decode(Req.self, from: body)
                let fmt: SDLAudioSampleFormat = (req.format?.lowercased() == "s16") ? .s16 : .f32
                let spec = SDLAudioSpec(sampleRate: req.sample_rate ?? 48000, channels: req.channels ?? 2, format: fmt)
                let pb = try SDLAudioPlayback(spec: spec, deviceId: req.device_id)
                let q = SDLAudioPlaybackQueue(playback: pb)
                let aid = Self._nextAudioId; Self._nextAudioId += 1; Self._playStore[aid] = pb; Self._playQueues[aid] = q
                return try JSONEncoder().encode(Res(audio_id: aid))
            case .audioPlaybackQueueEnqueue:
                struct Req: Codable { let audio_id: Int; let format: String; let channels: Int; let data_base64: String }
                let req = try JSONDecoder().decode(Req.self, from: body)
                guard let q = Self._playQueues[req.audio_id] else { throw AgentError.invalidArgument("unknown audio_id or queue not open") }
                guard req.format.lowercased() == "f32" else { throw AgentError.invalidArgument("only f32 supported") }
                guard let data = Data(base64Encoded: req.data_base64) else { throw AgentError.invalidArgument("invalid base64") }
                var samples = Array(repeating: Float(0), count: data.count / MemoryLayout<Float>.size)
                _ = samples.withUnsafeMutableBytes { dst in data.copyBytes(to: dst) }
                q.enqueue(samples: samples)
                return Self.okJSON()
            case .audioPlaybackPlayWAV:
                struct Req: Codable { let path: String; let audio_id: Int?; let device_id: UInt64?; let sample_rate: Int?; let channels: Int?; let format: String? }
                struct Res: Codable { let audio_id: Int }
                let req = try JSONDecoder().decode(Req.self, from: body)
                let wav = try SDLAudioWAV.load(path: req.path)
                let pb: SDLAudioPlayback
                let aid: Int
                if let id = req.audio_id, let existing = Self._playStore[id] {
                    pb = existing; aid = id
                } else {
                    let fmt: SDLAudioSampleFormat = (req.format?.lowercased() == "s16") ? .s16 : .f32
                    let spec = SDLAudioSpec(sampleRate: req.sample_rate ?? wav.sampleRate, channels: req.channels ?? wav.channels, format: fmt)
                    pb = try SDLAudioPlayback(spec: spec, deviceId: req.device_id)
                    aid = Self._nextAudioId; Self._nextAudioId += 1; Self._playStore[aid] = pb
                }
                let samples = try wav.converted(to: pb.spec)
                try pb.queue(samples: samples)
                return try JSONEncoder().encode(Res(audio_id: aid))
            case .audioMonitorStart:
                struct Req: Codable { let capture_id: Int; let playback_id: Int; let chunk_frames: Int? }
                struct Res: Codable { let ok: Bool }
                let req = try JSONDecoder().decode(Req.self, from: body)
                guard let sess = Self._capStore[req.capture_id], let pb = Self._playStore[req.playback_id] else { throw AgentError.invalidArgument("invalid capture_id or playback_id") }
                let mon = try AudioMonitor(capture: sess.cap, pump: sess.pump, playback: pb, chunkFrames: req.chunk_frames ?? 1024)
                Self._monitors[req.capture_id] = mon
                return try JSONEncoder().encode(Res(ok: true))
            case .audioMonitorStop:
                struct Req: Codable { let capture_id: Int }
                struct Res: Codable { let ok: Bool }
                let req = try JSONDecoder().decode(Req.self, from: body)
                if let mon = Self._monitors.removeValue(forKey: req.capture_id) { mon.stop() }
                return try JSONEncoder().encode(Res(ok: true))
            case .audioA2MStart:
                struct Req: Codable { let audio_id: Int; let mel_bands: Int; let energy_threshold: Float?; let min_on_frames: Int?; let min_off_frames: Int? }
                struct Res: Codable { let ok: Bool }
                let req = try JSONDecoder().decode(Req.self, from: body)
                guard var sess = Self._capStore[req.audio_id] else { throw AgentError.invalidArgument("unknown audio_id") }
                let stub = AudioA2MStub(melBands: req.mel_bands, energyThreshold: req.energy_threshold ?? 1e-2, minOnFrames: req.min_on_frames ?? 2, minOffFrames: req.min_off_frames ?? 2)
                sess.a2m = stub
                sess.featureFrameCursor = 0
                Self._capStore[req.audio_id] = sess
                return try JSONEncoder().encode(Res(ok: true))
            case .audioA2MRead:
                struct Req: Codable { let audio_id: Int; let frames: Int; let mel_bands: Int }
                struct EventOut: Codable { let kind: String; let note: Int; let velocity: Int; let frameIndex: Int; let timestamp_ms: Int }
                struct Res: Codable { let events: [EventOut] }
                let req = try JSONDecoder().decode(Req.self, from: body)
                guard var sess = Self._capStore[req.audio_id], let feat = sess.feat, let a2m = sess.a2m else { throw AgentError.invalidArgument("A2M not started for audio_id") }
                let (got, mel, _) = feat.readMel(frames: req.frames, melBands: req.mel_bands)
                var framesMel: [[Float]] = []
                framesMel.reserveCapacity(got)
                for i in 0..<got { let start = i * req.mel_bands; framesMel.append(Array(mel[start..<(start+req.mel_bands)])) }
                let events = a2m.process(melFrames: framesMel, startFrameIndex: sess.featureFrameCursor)
                sess.featureFrameCursor += got
                Self._capStore[req.audio_id] = sess
                let msPerFrame = Int((Double(feat.hopSize) / Double(feat.sampleRate)) * 1000.0)
                let outEvents = events.map { e in EventOut(kind: e.kind.rawValue, note: e.note, velocity: e.velocity, frameIndex: e.frameIndex, timestamp_ms: e.frameIndex * msPerFrame) }
                return try JSONEncoder().encode(Res(events: outEvents))
            case .openapiYAML:
                if let ext = Self.loadExternalOpenAPIYAML() { return ext }
                return Data(SDLKitOpenAPI.yaml.utf8)
            case .openapiJSON:
                // Prefer converting an external YAML to JSON for exact mirroring
                if let converted = Self.cachedJSONFromExternalYAML() { return converted }
                if let ext = Self.loadExternalOpenAPIJSON() { return ext }
                return SDLKitOpenAPI.json
            case .health:
                return try JSONEncoder().encode(["ok": true])
            case .version:
                let specVer = Self.externalOpenAPIVersion() ?? SDLKitOpenAPI.specVersion
                return try JSONEncoder().encode(["agent": SDLKitOpenAPI.agentVersion, "openapi": specVer])
            case .open:
                let req = try JSONDecoder().decode(OpenWindowReq.self, from: body)
                let id = try agent.openWindow(title: req.title, width: req.width, height: req.height)
                return try JSONEncoder().encode(["window_id": id])
            case .close:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                agent.closeWindow(windowId: req.window_id)
                return Self.okJSON()
            case .show:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.showWindow(windowId: req.window_id)
                return Self.okJSON()
            case .hide:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.hideWindow(windowId: req.window_id)
                return Self.okJSON()
            case .resize:
                let req = try JSONDecoder().decode(ResizeReq.self, from: body)
                try agent.resizeWindow(windowId: req.window_id, width: req.width, height: req.height)
                return Self.okJSON()
            case .setTitle:
                let req = try JSONDecoder().decode(SetTitleReq.self, from: body)
                try agent.setTitle(windowId: req.window_id, title: req.title)
                return Self.okJSON()
            case .setPosition:
                let req = try JSONDecoder().decode(SetPositionReq.self, from: body)
                try agent.setPosition(windowId: req.window_id, x: req.x, y: req.y)
                return Self.okJSON()
            case .getInfo:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                let info = try agent.getWindowInfo(windowId: req.window_id)
                struct R: Codable { let x: Int; let y: Int; let width: Int; let height: Int; let title: String }
                return try JSONEncoder().encode(R(x: info.x, y: info.y, width: info.width, height: info.height, title: info.title))
            case .maximize:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.maximizeWindow(windowId: req.window_id)
                return Self.okJSON()
            case .minimize:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.minimizeWindow(windowId: req.window_id)
                return Self.okJSON()
            case .restore:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.restoreWindow(windowId: req.window_id)
                return Self.okJSON()
            case .setFullscreen:
                let req = try JSONDecoder().decode(ToggleReq.self, from: body)
                try agent.setFullscreen(windowId: req.window_id, enabled: req.enabled)
                return Self.okJSON()
            case .setOpacity:
                let req = try JSONDecoder().decode(OpacityReq.self, from: body)
                try agent.setOpacity(windowId: req.window_id, opacity: Float(req.opacity))
                return Self.okJSON()
            case .setAlwaysOnTop:
                let req = try JSONDecoder().decode(ToggleReq.self, from: body)
                try agent.setAlwaysOnTop(windowId: req.window_id, enabled: req.enabled)
                return Self.okJSON()
            case .center:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.centerWindow(windowId: req.window_id)
                return Self.okJSON()
            case .present:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.present(windowId: req.window_id)
                return Self.okJSON()
            case .drawRect:
                let req = try JSONDecoder().decode(RectReq.self, from: body)
                if let cstr = req.colorString { try agent.drawRectangle(windowId: req.window_id, x: req.x, y: req.y, width: req.width, height: req.height, color: cstr) }
                else { try agent.drawRectangle(windowId: req.window_id, x: req.x, y: req.y, width: req.width, height: req.height, color: req.color ?? 0xFFFFFFFF) }
                return Self.okJSON()
            case .clear:
                let req = try JSONDecoder().decode(ColorReq.self, from: body)
                if let cstr = req.colorString { try agent.clear(windowId: req.window_id, color: cstr) }
                else { try agent.clear(windowId: req.window_id, color: req.color ?? 0xFF000000) }
                return Self.okJSON()
            case .drawLine:
                let req = try JSONDecoder().decode(LineReq.self, from: body)
                if let cstr = req.colorString { try agent.drawLine(windowId: req.window_id, x1: req.x1, y1: req.y1, x2: req.x2, y2: req.y2, color: cstr) }
                else { try agent.drawLine(windowId: req.window_id, x1: req.x1, y1: req.y1, x2: req.x2, y2: req.y2, color: req.color ?? 0xFFFFFFFF) }
                return Self.okJSON()
            case .drawCircleFilled:
                let req = try JSONDecoder().decode(CircleReq.self, from: body)
                if let cstr = req.colorString { try agent.drawCircleFilled(windowId: req.window_id, cx: req.cx, cy: req.cy, radius: req.radius, color: cstr) }
                else { try agent.drawCircleFilled(windowId: req.window_id, cx: req.cx, cy: req.cy, radius: req.radius, color: req.color ?? 0xFFFFFFFF) }
                return Self.okJSON()
            case .drawText:
                let req = try JSONDecoder().decode(TextReq.self, from: body)
                try agent.drawText(windowId: req.window_id, text: req.text, x: req.x, y: req.y, font: req.font, size: req.size, color: req.color)
                return Self.okJSON()
            case .captureEvent:
                let req = try JSONDecoder().decode(EventReq.self, from: body)
                if let ev = try agent.captureEvent(windowId: req.window_id, timeoutMs: req.timeout_ms) {
                    return try JSONEncoder().encode(["event": JEvent(ev)])
                } else {
                    return try JSONEncoder().encode([String: String]())
                }
            case .clipboardGet:
                // Require a valid window_id to ensure context
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                _ = try agent.getWindowInfo(windowId: req.window_id)
                let text = try SDLClipboard.getText()
                struct R: Codable { let text: String }
                return try JSONEncoder().encode(R(text: text))
            case .clipboardSet:
                let req = try JSONDecoder().decode(ClipboardSetReq.self, from: body)
                _ = try agent.getWindowInfo(windowId: req.window_id)
                try SDLClipboard.setText(req.text)
                return Self.okJSON()
            case .inputKeyboard:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                _ = try agent.getWindowInfo(windowId: req.window_id)
                let m = try SDLInput.getKeyboardModifiers()
                struct R: Codable { let modifiers: SDLInput.KeyboardModifiers }
                return try JSONEncoder().encode(R(modifiers: m))
            case .inputMouse:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                _ = try agent.getWindowInfo(windowId: req.window_id)
                let s = try SDLInput.getMouseState()
                return try JSONEncoder().encode(s)
            case .displayList:
                let list = try SDLDisplay.list()
                struct R: Codable { let displays: [SDLDisplay.Summary] }
                return try JSONEncoder().encode(R(displays: list))
            case .displayGetInfo:
                let req = try JSONDecoder().decode(DisplayIndexReq.self, from: body)
                let b = try SDLDisplay.getInfo(index: req.index)
                struct R: Codable { let bounds: SDLDisplay.Bounds }
                return try JSONEncoder().encode(R(bounds: b))
            case .textureLoad:
                let req = try JSONDecoder().decode(TextureLoadReq.self, from: body)
                try agent.textureLoad(windowId: req.window_id, id: req.id, path: req.path)
                return Self.okJSON()
            case .textureDraw:
                let req = try JSONDecoder().decode(TextureDrawReq.self, from: body)
                try agent.textureDraw(windowId: req.window_id, id: req.id, x: req.x, y: req.y, width: req.width, height: req.height)
                return Self.okJSON()
            case .textureFree:
                let req = try JSONDecoder().decode(TextureFreeReq.self, from: body)
                agent.textureFree(windowId: req.window_id, id: req.id)
                return Self.okJSON()
            case .textureDrawTiled:
                let req = try JSONDecoder().decode(TextureDrawTiledReq.self, from: body)
                // Implement tiled by repeated drawTexture
                let tilesX = max(1, req.width / req.tileWidth)
                let tilesY = max(1, req.height / req.tileHeight)
                for ty in 0..<tilesY {
                    for tx in 0..<tilesX {
                        let dx = req.x + tx * req.tileWidth
                        let dy = req.y + ty * req.tileHeight
                        try agent.textureDraw(windowId: req.window_id, id: req.id, x: dx, y: dy, width: req.tileWidth, height: req.tileHeight)
                    }
                }
                return Self.okJSON()
            case .textureDrawRotated:
                let req = try JSONDecoder().decode(TextureDrawRotatedReq.self, from: body)
                try agent.textureDrawRotated(windowId: req.window_id, id: req.id, x: req.x, y: req.y, width: req.width, height: req.height, angle: req.angle, cx: req.cx, cy: req.cy)
                return Self.okJSON()
            case .screenshot:
                let req = try JSONDecoder().decode(ScreenshotReq.self, from: body)
                switch req.format {
                case .raw:
                    let shot = try agent.screenshotRaw(windowId: req.window_id)
                    return try JSONEncoder().encode(shot)
                case .png:
                    do {
                        let shot = try agent.screenshotPNG(windowId: req.window_id)
                        return try JSONEncoder().encode(shot)
                    } catch AgentError.notImplemented {
                        return Self.errorJSON(code: "not_implemented", details: "PNG screenshots require SDL_image; retry with format \"raw\".")
                    }
                }
            case .renderGetOutputSize:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                let (w, h) = try agent.getRenderOutputSize(windowId: req.window_id)
                struct R: Codable { let width: Int; let height: Int }
                return try JSONEncoder().encode(R(width: w, height: h))
            case .renderGetScale:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                let s = try agent.getRenderScale(windowId: req.window_id)
                struct R: Codable { let sx: Float; let sy: Float }
                return try JSONEncoder().encode(R(sx: s.sx, sy: s.sy))
            case .renderSetScale:
                let req = try JSONDecoder().decode(RenderScaleReq.self, from: body)
                try agent.setRenderScale(windowId: req.window_id, sx: req.sx, sy: req.sy)
                return Self.okJSON()
            case .renderGetDrawColor:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                let col = try agent.getRenderDrawColor(windowId: req.window_id)
                struct R: Codable { let color: UInt32 }
                return try JSONEncoder().encode(R(color: col))
            case .renderSetDrawColor:
                let req = try JSONDecoder().decode(ColorReq.self, from: body)
                let argb: UInt32
                if let cstr = req.colorString { argb = (try? SDLColor.parse(cstr)) ?? 0xFFFFFFFF } else { argb = req.color ?? 0xFFFFFFFF }
                try agent.setRenderDrawColor(windowId: req.window_id, color: argb)
                return Self.okJSON()
            case .renderGetViewport:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                let v = try agent.getRenderViewport(windowId: req.window_id)
                struct R: Codable { let x: Int; let y: Int; let width: Int; let height: Int }
                return try JSONEncoder().encode(R(x: v.x, y: v.y, width: v.width, height: v.height))
            case .renderSetViewport:
                let req = try JSONDecoder().decode(RectOnlyReq.self, from: body)
                try agent.setRenderViewport(windowId: req.window_id, x: req.x, y: req.y, width: req.width, height: req.height)
                return Self.okJSON()
            case .renderGetClipRect:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                let v = try agent.getRenderClipRect(windowId: req.window_id)
                struct R: Codable { let x: Int; let y: Int; let width: Int; let height: Int }
                return try JSONEncoder().encode(R(x: v.x, y: v.y, width: v.width, height: v.height))
            case .renderSetClipRect:
                let req = try JSONDecoder().decode(RectOnlyReq.self, from: body)
                try agent.setRenderClipRect(windowId: req.window_id, x: req.x, y: req.y, width: req.width, height: req.height)
                return Self.okJSON()
            case .renderDisableClipRect:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.disableRenderClipRect(windowId: req.window_id)
                return Self.okJSON()
            case .drawPoints:
                let req = try JSONDecoder().decode(PointsReq.self, from: body)
                let color = try req.color.resolved()
                try agent.drawPoints(windowId: req.window_id, points: req.points.map { ($0.x, $0.y) }, color: color)
                return Self.okJSON()
            case .drawLines:
                let req = try JSONDecoder().decode(LinesReq.self, from: body)
                let color = try req.color.resolved()
                try agent.drawLines(windowId: req.window_id, segments: req.segments.map { ($0.x1, $0.y1, $0.x2, $0.y2) }, color: color)
                return Self.okJSON()
            case .drawRects:
                let req = try JSONDecoder().decode(RectsReq.self, from: body)
                let color = try req.color.resolved()
                try agent.drawRects(windowId: req.window_id, rects: req.rects.map { ($0.x, $0.y, $0.width, $0.height) }, color: color, filled: req.filled ?? true)
                return Self.okJSON()
            }
        } catch let e as AgentError {
            return Self.errorJSON(from: e)
        } catch {
            return Self.errorJSON(code: "invalid_argument", details: String(describing: error))
        }
    }

    private static func cachedJSONFromExternalYAML() -> Data? {
        if let envPath = normalizedEnvPath(ProcessInfo.processInfo.environment) {
            let lower = envPath.lowercased()
            if lower.hasSuffix(".json") || lower.hasSuffix(".jsonc") {
                return nil
            }
        }
        guard let yamlEntry = loadExternalOpenAPIYAMLCacheEntry() else { return nil }
        if let cached = yamlConversionCache, cached.matches(yamlEntry) { return cached.data }
        guard let converted = OpenAPIConverter.yamlToJSON(yamlEntry.data) else { return nil }
        yamlConversionCache = CachedConversion(data: converted, sourceSignature: yamlEntry.signature, sourceData: yamlEntry.data)
        _openAPIConversionObserver?()
        return converted
    }

    private static func loadExternalOpenAPIYAML() -> Data? {
        return loadExternalOpenAPIYAMLCacheEntry()?.data
    }

    private static func loadExternalOpenAPIJSON() -> Data? {
        return loadExternalOpenAPIJSONCacheEntry()?.data
    }

    private static func loadExternalOpenAPIYAMLCacheEntry() -> CachedFile? {
        let env = ProcessInfo.processInfo.environment
        let envPath = normalizedEnvPath(env)
        refreshEnvPathCacheIfNeeded(envPath)
        var checked = Set<String>()
        if let envPath {
            checked.insert(envPath)
            if let entry = fetchFile(at: envPath, allowedExtensions: [".yaml", ".yml"], getCache: { externalYAMLCache }, setCache: setYAMLCache) {
                return entry
            }
        }
        let candidates = [
            "sdlkit.gui.v1.yaml",
            "openapi.yaml",
            "openapi/sdlkit.gui.v1.yaml"
        ]
        for rel in candidates where !checked.contains(rel) {
            if let entry = fetchFile(at: rel, allowedExtensions: [".yaml", ".yml"], getCache: { externalYAMLCache }, setCache: setYAMLCache) {
                return entry
            }
        }
        return nil
    }

    private static func loadExternalOpenAPIJSONCacheEntry() -> CachedFile? {
        let env = ProcessInfo.processInfo.environment
        let envPath = normalizedEnvPath(env)
        refreshEnvPathCacheIfNeeded(envPath)
        var checked = Set<String>()
        if let envPath {
            checked.insert(envPath)
            if let entry = fetchFile(at: envPath, allowedExtensions: [".json"], getCache: { externalJSONCache }, setCache: setJSONCache) {
                return entry
            }
        }
        let candidates = [
            "openapi.json",
            "sdlkit.gui.v1.json",
            "openapi/openapi.json",
            "openapi/sdlkit.gui.v1.json"
        ]
        for rel in candidates where !checked.contains(rel) {
            if let entry = fetchFile(at: rel, allowedExtensions: [".json"], getCache: { externalJSONCache }, setCache: setJSONCache) {
                return entry
            }
        }
        return nil
    }

    private static func fetchFile(
        at path: String,
        allowedExtensions: [String],
        getCache: () -> CachedFile?,
        setCache: (CachedFile?) -> Void
    ) -> CachedFile? {
        let lower = path.lowercased()
        guard allowedExtensions.contains(where: { lower.hasSuffix($0) }) else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            if let existing = getCache(), existing.signature.path == path {
                setCache(nil)
            }
            return nil
        }
        let signature = cacheSignature(for: path)
        if let existing = getCache(), existing.signature.matches(signature) {
            return existing
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            if let existing = getCache(), existing.signature.path == path {
                setCache(nil)
            }
            return nil
        }
        let entry = CachedFile(signature: signature, data: data)
        setCache(entry)
        return entry
    }

    private static func cacheSignature(for path: String) -> CacheSignature {
        var mtime: Date?
        var size: UInt64?
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            mtime = attrs[.modificationDate] as? Date
            if let n = attrs[.size] as? NSNumber { size = n.uint64Value }
        }
        return CacheSignature(path: path, mtime: mtime, size: size)
    }

    private static func setYAMLCache(_ entry: CachedFile?) {
        externalYAMLCache = entry
        guard let entry else {
            yamlConversionCache = nil
            return
        }
        if let cached = yamlConversionCache, !cached.matches(entry) {
            yamlConversionCache = nil
        }
    }

    private static func setJSONCache(_ entry: CachedFile?) {
        externalJSONCache = entry
    }

    private static func normalizedEnvPath(_ env: [String: String]) -> String? {
        if let raw = env["SDLKIT_OPENAPI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        guard let cString = getenv("SDLKIT_OPENAPI_PATH") else { return nil }
        guard let raw = String(validatingCString: cString)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private static func refreshEnvPathCacheIfNeeded(_ envPath: String?) {
        if envPath != cachedOpenAPIEnvPath {
            cachedOpenAPIEnvPath = envPath
            setYAMLCache(nil)
            setJSONCache(nil)
        }
    }

    static func resetOpenAPICacheForTesting() {
        cachedOpenAPIEnvPath = nil
        setYAMLCache(nil)
        setJSONCache(nil)
    }

    private static func externalOpenAPIVersion() -> String? {
        if let jsonEntry = loadExternalOpenAPIJSONCacheEntry() {
            if let obj = try? JSONSerialization.jsonObject(with: jsonEntry.data) as? [String: Any],
               let info = obj["info"] as? [String: Any],
               let ver = info["version"] as? String { return ver }
        }
        if let converted = cachedJSONFromExternalYAML() {
            if let obj = try? JSONSerialization.jsonObject(with: converted) as? [String: Any],
               let info = obj["info"] as? [String: Any],
               let ver = info["version"] as? String { return ver }
        }
        if let yamlEntry = externalYAMLCache ?? loadExternalOpenAPIYAMLCacheEntry(),
           let text = String(data: yamlEntry.data, encoding: .utf8) {
            let infoAnchor = text.range(of: "\ninfo:") ?? text.range(of: "^info:", options: .regularExpression)
            if let infoAnchor {
                let afterInfo = text[infoAnchor.upperBound...]
                let endRange = afterInfo.range(of: "\npaths:")
                let block = endRange != nil ? afterInfo[..<endRange!.lowerBound] : afterInfo[afterInfo.startIndex...]
                if let verLine = block.range(of: "\n\\s*version:\\s*([^\n#]+)", options: .regularExpression) {
                    let line = block[verLine]
                    if let colon = line.range(of: ":") {
                        var v = line[colon.upperBound...].trimmingCharacters(in: .whitespaces)
                        if v.hasPrefix("\"") && v.hasSuffix("\"") { v.removeFirst(); v.removeLast() }
                        if v.hasPrefix("'") && v.hasSuffix("'") { v.removeFirst(); v.removeLast() }
                        return String(v)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Models
    private struct OpenWindowReq: Codable { let title: String; let width: Int; let height: Int }
    private struct WindowOnlyReq: Codable { let window_id: Int }
    private struct ResizeReq: Codable { let window_id: Int; let width: Int; let height: Int }
    private struct SetTitleReq: Codable { let window_id: Int; let title: String }
    private struct SetPositionReq: Codable { let window_id: Int; let x: Int; let y: Int }
    private struct ToggleReq: Codable { let window_id: Int; let enabled: Bool }
    private struct OpacityReq: Codable { let window_id: Int; let opacity: Double }
    private struct RectReq: Codable {
        let window_id: Int, x: Int, y: Int, width: Int, height: Int
        let color: UInt32?
        let colorString: String?
        enum CodingKeys: String, CodingKey { case window_id, x, y, width, height, color }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            x = try c.decode(Int.self, forKey: .x)
            y = try c.decode(Int.self, forKey: .y)
            width = try c.decode(Int.self, forKey: .width)
            height = try c.decode(Int.self, forKey: .height)
            if let s = try? c.decode(String.self, forKey: .color) { colorString = s; color = nil }
            else { color = try? c.decode(UInt32.self, forKey: .color); colorString = nil }
        }
    }
    private struct ColorReq: Codable {
        let window_id: Int
        let color: UInt32?
        let colorString: String?
        enum CodingKeys: String, CodingKey { case window_id, color }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            if let s = try? c.decode(String.self, forKey: .color) { colorString = s; color = nil }
            else { color = try? c.decode(UInt32.self, forKey: .color); colorString = nil }
        }
    }
    private struct LineReq: Codable {
        let window_id: Int, x1: Int, y1: Int, x2: Int, y2: Int
        let color: UInt32?
        let colorString: String?
        enum CodingKeys: String, CodingKey { case window_id, x1, y1, x2, y2, color }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            x1 = try c.decode(Int.self, forKey: .x1)
            y1 = try c.decode(Int.self, forKey: .y1)
            x2 = try c.decode(Int.self, forKey: .x2)
            y2 = try c.decode(Int.self, forKey: .y2)
            if let s = try? c.decode(String.self, forKey: .color) { colorString = s; color = nil }
            else { color = try? c.decode(UInt32.self, forKey: .color); colorString = nil }
        }
    }
    private struct CircleReq: Codable {
        let window_id: Int, cx: Int, cy: Int, radius: Int
        let color: UInt32?
        let colorString: String?
        enum CodingKeys: String, CodingKey { case window_id, cx, cy, radius, color }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            cx = try c.decode(Int.self, forKey: .cx)
            cy = try c.decode(Int.self, forKey: .cy)
            radius = try c.decode(Int.self, forKey: .radius)
            if let s = try? c.decode(String.self, forKey: .color) { colorString = s; color = nil }
            else { color = try? c.decode(UInt32.self, forKey: .color); colorString = nil }
        }
    }
    private struct TextReq: Codable {
        let window_id: Int, text: String, x: Int, y: Int
        let font: String?
        let size: Int?
        let color: UInt32?
    }
    private struct EventReq: Codable { let window_id: Int; let timeout_ms: Int? }
    private struct ScreenshotReq: Codable {
        enum Format: String, Codable {
            case raw
            case png
        }
        let window_id: Int
        let format: Format
        enum CodingKeys: String, CodingKey { case window_id, format }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            if let rawValue = try c.decodeIfPresent(String.self, forKey: .format)?.lowercased() {
                guard let fmt = Format(rawValue: rawValue) else {
                    throw DecodingError.dataCorruptedError(forKey: .format, in: c, debugDescription: "format must be 'raw' or 'png'")
                }
                format = fmt
            } else {
                format = .raw
            }
        }
    }
    private struct ClipboardSetReq: Codable { let window_id: Int; let text: String }
    private struct DisplayIndexReq: Codable { let index: Int }
    private struct TextureLoadReq: Codable { let window_id: Int; let id: String; let path: String }
    private struct TextureDrawReq: Codable { let window_id: Int; let id: String; let x: Int; let y: Int; let width: Int?; let height: Int? }
    private struct TextureFreeReq: Codable { let window_id: Int; let id: String }
    private struct TextureDrawTiledReq: Codable { let window_id: Int; let id: String; let x: Int; let y: Int; let width: Int; let height: Int; let tileWidth: Int; let tileHeight: Int }
    private struct TextureDrawRotatedReq: Codable { let window_id: Int; let id: String; let x: Int; let y: Int; let width: Int?; let height: Int?; let angle: Double; let cx: Float?; let cy: Float? }
    private struct RenderScaleReq: Codable { let window_id: Int; let sx: Float; let sy: Float }
    private struct RectOnlyReq: Codable { let window_id: Int; let x: Int; let y: Int; let width: Int; let height: Int }
    private struct PointsReq: Codable { let window_id: Int; let points: [P]; let color: ColorValue; struct P: Codable { let x: Int; let y: Int } }
    private struct LinesReq: Codable { let window_id: Int; let segments: [S]; let color: ColorValue; struct S: Codable { let x1: Int; let y1: Int; let x2: Int; let y2: Int } }
    private struct RectsReq: Codable { let window_id: Int; let rects: [R]; let color: ColorValue; let filled: Bool?; struct R: Codable { let x: Int; let y: Int; let width: Int; let height: Int } }
    private enum ColorValue: Codable { case int(UInt32), str(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .str(s) } else { self = .int(try c.decode(UInt32.self)) }
        }
        func resolved() throws -> UInt32 {
            switch self { case .int(let v): return v; case .str(let s): return try SDLColor.parse(s) }
        }
    }

    private struct JEvent: Codable {
        let type: String
        let x: Int?
        let y: Int?
        let key: String?
        let button: Int?
        init(_ e: SDLKitGUIAgent.Event) {
            switch e.type {
            case .keyDown: type = "key_down"
            case .keyUp: type = "key_up"
            case .mouseDown: type = "mouse_down"
            case .mouseUp: type = "mouse_up"
            case .mouseMove: type = "mouse_move"
            case .quit: type = "quit"
            case .windowClosed: type = "window_closed"
            }
            self.x = e.x; self.y = e.y; self.key = e.key; self.button = e.button
        }
    }

    // MARK: - Error helpers
    private static func okJSON() -> Data { try! JSONEncoder().encode(["ok": true]) }
    private static func errorJSON(code: String, details: String?) -> Data {
        struct Err: Codable { let error: E; struct E: Codable { let code: String; let details: String? } }
        return try! JSONEncoder().encode(Err(error: .init(code: code, details: details)))
    }
    private static func errorJSON(from e: AgentError) -> Data {
        switch e {
        case .windowNotFound: return errorJSON(code: "window_not_found", details: nil)
        case .sdlUnavailable: return errorJSON(code: "sdl_unavailable", details: nil)
        case .notImplemented: return errorJSON(code: "not_implemented", details: nil)
        case .invalidArgument(let msg): return errorJSON(code: "invalid_argument", details: msg)
        case .internalError(let msg): return errorJSON(code: "internal_error", details: msg)
        case .deviceLost(let details): return errorJSON(code: "device_lost", details: details)
        case .missingDependency(let dep): return errorJSON(code: "missing_dependency", details: dep)
        }
    }
}
