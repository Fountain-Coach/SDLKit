import Foundation

@MainActor
public final class AudioGPUFeatureExtractor {
    private struct WeightKey: Hashable { let sampleRate: Int; let frameSize: Int; let melBands: Int }
    private static var weightCache: [WeightKey: [Float]] = [:]
    private let backend: RenderBackend
    private let frameSize: Int
    private let nBins: Int
    private let mel: MelFilterBank
    private let window: [Float]
    private let computeDFT: ComputePipelineHandle
    private let computeMel: ComputePipelineHandle?
    private let melBands: Int
    private var melWeightsBuffer: BufferHandle?

    public init?(backend: RenderBackend, sampleRate: Int, frameSize: Int, melBands: Int) {
        guard let plan = FFTPlan(n: frameSize) else { return nil }
        // we reuse MelFilterBank and FFTPlan visibility by placing this file in Core; FFTPlan is internal to AudioFeatures.swift
        self.backend = backend
        self.frameSize = frameSize
        self.nBins = frameSize / 2 + 1
        self.window = hannWindow(frameSize)
        self.mel = MelFilterBank(sampleRate: sampleRate, nFft: frameSize, nMels: melBands)
        self.melBands = melBands
        do {
            let dftDesc = ComputePipelineDescriptor(label: "audio_dft_power", shader: ShaderID("audio_dft_power"))
            self.computeDFT = try backend.makeComputePipeline(dftDesc)
            // If mel projection compute is present, set up weights buffer
            if (try? ShaderLibrary.shared.computeModule(for: ShaderID("audio_mel_project"))) != nil {
                let melDesc = ComputePipelineDescriptor(label: "audio_mel_project", shader: ShaderID("audio_mel_project"))
                self.computeMel = try backend.makeComputePipeline(melDesc)
                // Flatten weights [mel][bin] with CPU cache
                let key = WeightKey(sampleRate: sampleRate, frameSize: frameSize, melBands: melBands)
                var weightsFlat = Self.weightCache[key] ?? []
                if weightsFlat.isEmpty {
                    weightsFlat.reserveCapacity(melBands * nBins)
                    for m in 0..<melBands { weightsFlat.append(contentsOf: mel.weights[m].prefix(nBins)) }
                    Self.weightCache[key] = weightsFlat
                }
                melWeightsBuffer = try backend.createBuffer(bytes: weightsFlat, length: weightsFlat.count * MemoryLayout<Float>.size, usage: .storage)
            } else {
                self.computeMel = nil
            }
        } catch {
            return nil
        }
        _ = plan // silence unused; plan existence ensures power-of-two, actual DFT is done on GPU
    }

    // Process a batch of mono frames; returns mel energies per frame
    public func process(frames: [[Float]]) throws -> [[Float]] {
        guard !frames.isEmpty else { return [] }
        let fcount = frames.count
        // Prepare input (windowed)
        var input: [Float] = Array(repeating: 0, count: fcount * frameSize)
        for i in 0..<fcount {
            let src = frames[i]
            for n in 0..<min(frameSize, src.count) {
                input[i*frameSize + n] = src[n] * window[n]
            }
        }
        let inputBytes = input.count * MemoryLayout<Float>.size
        let outputCount = fcount * nBins
        let outputBytes = outputCount * MemoryLayout<Float>.size
        let inBuf = try backend.createBuffer(bytes: input, length: inputBytes, usage: .storage)
        let powerBuf = try backend.createBuffer(bytes: nil, length: outputBytes, usage: .storage)

        var bindings = BindingSet()
        bindings.setBuffer(inBuf, at: 0)
        bindings.setBuffer(powerBuf, at: 1)
        // Push constants: frameSize, nBins, frames, pad
        var params = [UInt32(frameSize), UInt32(nBins), UInt32(fcount), 0]
        let pbytes = Data(bytes: &params, count: MemoryLayout<UInt32>.size * 4)
        bindings.materialConstants = BindingSet.MaterialConstants(data: pbytes)

        let total = fcount * nBins
        let tgSize = 64
        let groups = (total + tgSize - 1) / tgSize
        try backend.dispatchCompute(computeDFT, groupsX: groups, groupsY: 1, groupsZ: 1, bindings: bindings)
        try backend.waitGPU()

        // If mel compute is available, run it; else read back power and project on CPU
        if let melPipe = computeMel, let wbuf = melWeightsBuffer {
            let melCount = fcount * melBands
            let melBytes = melCount * MemoryLayout<Float>.size
            let outMelBuf = try backend.createBuffer(bytes: nil, length: melBytes, usage: .storage)
            var melBindings = BindingSet()
            melBindings.setBuffer(powerBuf, at: 0)
            melBindings.setBuffer(wbuf, at: 1)
            melBindings.setBuffer(outMelBuf, at: 2)
            var mparams = [UInt32(nBins), UInt32(melBands), UInt32(fcount), 0]
            let mpbytes = Data(bytes: &mparams, count: MemoryLayout<UInt32>.size * 4)
            melBindings.materialConstants = BindingSet.MaterialConstants(data: mpbytes)
            let totalMel = fcount * melBands
            let melGroups = (totalMel + tgSize - 1) / tgSize
            try backend.dispatchCompute(melPipe, groupsX: melGroups, groupsY: 1, groupsZ: 1, bindings: melBindings)
            try backend.waitGPU()
            var flat = Array(repeating: Float(0), count: melCount)
            try flat.withUnsafeMutableBytes { raw in
                try backend.readback(buffer: outMelBuf, into: raw.baseAddress!, length: melBytes)
            }
            backend.destroy(.buffer(outMelBuf))
            backend.destroy(.buffer(inBuf))
            backend.destroy(.buffer(powerBuf))
            var result: [[Float]] = []
            result.reserveCapacity(fcount)
            for i in 0..<fcount { let s = i * melBands; result.append(Array(flat[s..<(s+melBands)])) }
            return result
        } else {
            var power = Array(repeating: Float(0), count: outputCount)
            try power.withUnsafeMutableBytes { raw in
                try backend.readback(buffer: powerBuf, into: raw.baseAddress!, length: outputBytes)
            }
            backend.destroy(.buffer(inBuf))
            backend.destroy(.buffer(powerBuf))
            var result: [[Float]] = []
            result.reserveCapacity(fcount)
            for i in 0..<fcount {
                let start = i * nBins
                let spectrum = Array(power[start..<(start+nBins)])
                result.append(mel.apply(powerSpectrum: spectrum))
            }
            return result
        }
    }
}
