import Foundation

// Minimal CPU feature extraction: STFT -> mel energies + onset (spectral flux).
// Pure Swift implementation for portability.

func hannWindow(_ n: Int) -> [Float] {
    guard n > 0 else { return [] }
    let factor = 2.0 * Float.pi / Float(n - 1)
    return (0..<n).map { 0.5 * (1.0 - cos(Float($0) * factor)) }
}

// Iterative radix-2 FFT (complex), in-place arrays (real, imag).
final class FFTPlan {
    let n: Int
    private let levels: Int
    private let cosTable: [Float]
    private let sinTable: [Float]

    init?(n: Int) {
        guard n > 0 && (n & (n - 1)) == 0 else { return nil } // power of two
        self.n = n
        self.levels = Int(log2(Float(n)))
        var cosT = [Float](repeating: 0, count: n / 2)
        var sinT = [Float](repeating: 0, count: n / 2)
        for i in 0..<(n/2) {
            let angle = -2.0 * Float.pi * Float(i) / Float(n)
            cosT[i] = cos(angle)
            sinT[i] = sin(angle)
        }
        self.cosTable = cosT
        self.sinTable = sinT
    }

    func forward(real: inout [Float], imag: inout [Float]) {
        // Bit-reversed addressing permutation
        var j = 0
        for i in 1..<(n - 1) {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { real.swapAt(i, j); imag.swapAt(i, j) }
        }
        var size = 2
        while size <= n {
            let halfsize = size >> 1
            let tablestep = n / size
            var i = 0
            while i < n {
                var k = 0
                for j in i..<(i + halfsize) {
                    let l = j + halfsize
                    let tpre =  real[l] * cosTable[k] - imag[l] * sinTable[k]
                    let tpim =  real[l] * sinTable[k] + imag[l] * cosTable[k]
                    real[l] = real[j] - tpre
                    imag[l] = imag[j] - tpim
                    real[j] += tpre
                    imag[j] += tpim
                    k += tablestep
                }
                i += size
            }
            size <<= 1
        }
    }
}

final class MelFilterBank {
    let sampleRate: Int
    let nFft: Int
    let nBins: Int
    let nMels: Int
    let weights: [[Float]] // [mel][bin]

    init(sampleRate: Int, nFft: Int, nMels: Int, fMin: Float = 0, fMax: Float? = nil) {
        self.sampleRate = sampleRate
        self.nFft = nFft
        self.nBins = nFft / 2 + 1
        self.nMels = nMels
        let fmax = fMax ?? Float(sampleRate) / 2
        func hz2mel(_ f: Float) -> Float { 2595.0 * log10(1.0 + f / 700.0) }
        func mel2hz(_ m: Float) -> Float { 700.0 * (pow(10.0, m / 2595.0) - 1.0) }
        let melMin = hz2mel(fMin)
        let melMax = hz2mel(fmax)
        let melPoints = (0..<(nMels + 2)).map { i in melMin + (melMax - melMin) * Float(i) / Float(nMels + 1) }
        let hzPoints = melPoints.map { mel2hz($0) }
        let binPoints = hzPoints.map { Int(round(($0 / Float(sampleRate)) * Float(nFft))) }
        var w: [[Float]] = Array(repeating: Array(repeating: 0, count: nBins), count: nMels)
        for m in 1...(nMels) {
            let f_m_minus = binPoints[m - 1]
            let f_m = binPoints[m]
            let f_m_plus = binPoints[m + 1]
            if f_m_minus >= f_m_plus { continue }
            let left = max(0, min(f_m_minus, nBins-1))
            let center = max(0, min(f_m, nBins-1))
            let right = max(0, min(f_m_plus, nBins-1))
            if left < center {
                for k in left..<center { w[m-1][k] = Float(k - left) / Float(max(1, center - left)) }
            }
            if center < right {
                for k in center..<right { w[m-1][k] = Float(right - k) / Float(max(1, right - center)) }
            }
        }
        self.weights = w
    }

    func apply(powerSpectrum: [Float]) -> [Float] {
        var out = Array(repeating: Float(0), count: nMels)
        for m in 0..<nMels {
            var acc: Float = 0
            let w = weights[m]
            for k in 0..<min(nBins, powerSpectrum.count) {
                let wk = w[k]
                if wk != 0 { acc += wk * powerSpectrum[k] }
            }
            out[m] = acc
        }
        return out
    }
}

public final class AudioFeatureExtractor {
    public let sampleRate: Int
    public let frameSize: Int
    public let hopSize: Int
    public let melBands: Int
    public let channels: Int

    private let window: [Float]
    private let fft: FFTPlan
    private let mel: MelFilterBank
    private var prevMel: [Float]?

    public init?(sampleRate: Int, channels: Int, frameSize: Int, hopSize: Int, melBands: Int) {
        guard let plan = FFTPlan(n: frameSize) else { return nil }
        self.sampleRate = sampleRate
        self.channels = channels
        self.frameSize = frameSize
        self.hopSize = hopSize
        self.melBands = melBands
        self.window = hannWindow(frameSize)
        self.fft = plan
        self.mel = MelFilterBank(sampleRate: sampleRate, nFft: frameSize, nMels: melBands)
    }

    // Input: mono frameSize samples
    public func processFrame(_ frame: [Float]) -> (mel: [Float], onset: Float) {
        var re = frame.enumerated().map { $0.element * window[$0.offset] }
        var im = Array(repeating: Float(0), count: frameSize)
        fft.forward(real: &re, imag: &im)
        let nBins = frameSize / 2 + 1
        var power = Array(repeating: Float(0), count: nBins)
        for k in 0..<nBins {
            let rr = re[k]
            let ii = im[k]
            power[k] = rr*rr + ii*ii
        }
        let melVec = mel.apply(powerSpectrum: power)
        var onset: Float = 0
        if let prev = prevMel {
            let n = min(prev.count, melVec.count)
            var flux: Float = 0
            for i in 0..<n { let d = melVec[i] - prev[i]; if d > 0 { flux += d } }
            onset = flux
        }
        prevMel = melVec
        return (melVec, onset)
    }
}

// Background mel extraction from a running capture pump.
public final class AudioFeaturePump: @unchecked Sendable {
    private let cap: SDLAudioCapture
    private let pump: SDLAudioChunkedCapturePump
    private let extractor: AudioFeatureExtractor
    private let channels: Int
    public let frameSize: Int
    public let hopSize: Int
    public let melBands: Int
    public let sampleRate: Int
    private var running = true
    private var thread: Thread?

    private let queueLock = NSLock()
    private var melQueue: [Float] = [] // concatenated mel frames
    private var onsetQueue: [Float] = []

    public init?(capture: SDLAudioCapture, pump: SDLAudioChunkedCapturePump, frameSize: Int, hopSize: Int, melBands: Int) {
        self.cap = capture
        self.pump = pump
        self.channels = capture.spec.channels
        self.frameSize = frameSize
        self.hopSize = hopSize
        self.melBands = melBands
        self.sampleRate = capture.spec.sampleRate
        guard let ex = AudioFeatureExtractor(sampleRate: capture.spec.sampleRate, channels: capture.spec.channels, frameSize: frameSize, hopSize: hopSize, melBands: melBands) else { return nil }
        self.extractor = ex
        start()
    }

    deinit { stop() }

    public func stop() { running = false }

    public func readMel(frames: Int, melBands: Int) -> (frames: Int, mel: [Float], onset: [Float]) {
        queueLock.lock()
        let haveFrames = melQueue.count / melBands
        let take = min(frames, haveFrames)
        let melCount = take * melBands
        let melOut = Array(melQueue.prefix(melCount))
        let onsetOut = Array(onsetQueue.prefix(take))
        melQueue.removeFirst(melOut.count)
        onsetQueue.removeFirst(onsetOut.count)
        queueLock.unlock()
        return (take, melOut, onsetOut)
    }

    private func start() {
        let t = Thread { [weak self] in self?.threadLoop() }
        t.name = "SDLKit.AudioFeaturePump"
        t.qualityOfService = .userInitiated
        self.thread = t
        t.start()
    }

    private func threadLoop() {
        var overlap = [Float]()
        while running {
            // Read one hop worth of frames (blocking-ish)
            var hop = Array(repeating: Float(0), count: hopSize * channels)
            var got = pump.readFrames(into: &hop)
            if got == 0 { continue }
            if got < hopSize {
                hop.removeSubrange(got*channels..<hop.count)
            }
            // Downmix to mono
            var mono: [Float] = []
            mono.reserveCapacity((overlap.count) + hop.count / channels)
            if !overlap.isEmpty { mono.append(contentsOf: overlap) }
            // Average across channels per frame
            let frames = hop.count / channels
            for i in 0..<frames {
                var acc: Float = 0
                for c in 0..<channels { acc += hop[i*channels + c] }
                mono.append(acc / Float(channels))
            }
            // While we have enough for a frame
            var idx = 0
            while idx + frameSize <= mono.count {
                let frame = Array(mono[idx..<(idx+frameSize)])
                let (mel, onset) = extractor.processFrame(frame)
                queueLock.lock()
                melQueue.append(contentsOf: mel)
                onsetQueue.append(onset)
                queueLock.unlock()
                idx += hopSize
            }
            // Keep overlap
            if idx < mono.count { overlap = Array(mono[idx..<mono.count]) } else { overlap.removeAll(keepingCapacity: true) }
        }
    }

    
}
