import Foundation

@MainActor
public final class AudioGPUFeatureExtractor {
    private let backend: RenderBackend
    private let frameSize: Int
    private let nBins: Int
    private let mel: MelFilterBank
    private let window: [Float]
    private let compute: ComputePipelineHandle

    public init?(backend: RenderBackend, sampleRate: Int, frameSize: Int, melBands: Int) {
        guard let plan = FFTPlan(n: frameSize) else { return nil }
        // we reuse MelFilterBank and FFTPlan visibility by placing this file in Core; FFTPlan is internal to AudioFeatures.swift
        self.backend = backend
        self.frameSize = frameSize
        self.nBins = frameSize / 2 + 1
        self.window = hannWindow(frameSize)
        self.mel = MelFilterBank(sampleRate: sampleRate, nFft: frameSize, nMels: melBands)
        do {
            let desc = ComputePipelineDescriptor(label: "audio_dft_power", shader: ShaderID("audio_dft_power"))
            self.compute = try backend.makeComputePipeline(desc)
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
        let outBuf = try backend.createBuffer(bytes: nil, length: outputBytes, usage: .storage)

        var bindings = BindingSet()
        bindings.setBuffer(inBuf, at: 0)
        bindings.setBuffer(outBuf, at: 1)
        // Push constants: frameSize, nBins, frames, pad
        var params = [UInt32(frameSize), UInt32(nBins), UInt32(fcount), 0]
        let pbytes = Data(bytes: &params, count: MemoryLayout<UInt32>.size * 4)
        bindings.materialConstants = BindingSet.MaterialConstants(data: pbytes)

        let total = fcount * nBins
        let tgSize = 64
        let groups = (total + tgSize - 1) / tgSize
        try backend.dispatchCompute(compute, groupsX: groups, groupsY: 1, groupsZ: 1, bindings: bindings)
        try backend.waitGPU()

        var power = Array(repeating: Float(0), count: outputCount)
        try power.withUnsafeMutableBytes { raw in
            try backend.readback(buffer: outBuf, into: raw.baseAddress!, length: outputBytes)
        }
        backend.destroy(.buffer(inBuf))
        backend.destroy(.buffer(outBuf))

        // CPU mel projection
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

