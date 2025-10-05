import Foundation

public struct ShaderModuleArtifacts: Sendable {
    public let dxilVertex: URL?
    public let dxilFragment: URL?
    public let spirvVertex: URL?
    public let spirvFragment: URL?
    public let metalLibrary: URL?

    func requireDXILVertex(for id: ShaderID) throws -> URL {
        guard let url = dxilVertex else {
            throw AgentError.internalError("DXIL vertex shader for \(id.rawValue) not found. Run the shader build plugin.")
        }
        return url
    }

    func dxilFragmentURL(for id: ShaderID) throws -> URL? {
        if let url = dxilFragment, FileManager.default.fileExists(atPath: url.path) { return url }
        return nil
    }

    func requireMetalLibrary(for id: ShaderID) throws -> URL {
        guard let url = metalLibrary else {
            throw AgentError.internalError("Metal library for \(id.rawValue) not found. Run the shader build plugin.")
        }
        return url
    }

    func requireSPIRVVertex(for id: ShaderID) throws -> URL {
        guard let url = spirvVertex else {
            throw AgentError.internalError("SPIR-V vertex shader for \(id.rawValue) not found. Run the shader build plugin.")
        }
        return url
    }
}

public struct ComputeShaderModuleArtifacts: Sendable {
    public let dxil: URL?
    public let spirv: URL?
    public let metalLibrary: URL?

    func requireDXIL(for id: ShaderID) throws -> URL {
        guard let url = dxil else {
            throw AgentError.internalError("DXIL compute shader for \(id.rawValue) not found. Run the shader build plugin.")
        }
        return url
    }

    func requireSPIRV(for id: ShaderID) throws -> URL {
        guard let url = spirv else {
            throw AgentError.internalError("SPIR-V compute shader for \(id.rawValue) not found. Run the shader build plugin.")
        }
        return url
    }

    func requireMetalLibrary(for id: ShaderID) throws -> URL {
        guard let url = metalLibrary else {
            throw AgentError.internalError("Metal library for compute shader \(id.rawValue) not found. Run the shader build plugin.")
        }
        return url
    }
}

public struct ComputeShaderModule: Sendable {
    public let id: ShaderID
    public let entryPoint: String
    public let threadgroupSize: (Int, Int, Int)
    public let pushConstantSize: Int
    public let bindings: [BindingSlot]
    public let artifacts: ComputeShaderModuleArtifacts
}

public struct ShaderModule: Sendable {
    public let id: ShaderID
    public let vertexEntryPoint: String
    public let fragmentEntryPoint: String?
    public let vertexLayout: VertexLayout
    public let bindings: [ShaderStage: [BindingSlot]]
    public let pushConstantSize: Int
    public let artifacts: ShaderModuleArtifacts

    func validateVertexLayout(_ layout: VertexLayout) throws {
        guard layout == vertexLayout else {
            throw AgentError.invalidArgument("Vertex layout mismatch for shader \(id.rawValue)")
        }
    }
}

@MainActor
public final class ShaderLibrary {
    public static let shared = ShaderLibrary()

    private var modules: [ShaderID: ShaderModule]
    private var computeModules: [ShaderID: ComputeShaderModule]
    private init() {
        let root = ShaderLibrary.resolveGeneratedRoot()
        self.modules = ShaderLibrary.loadModules(root: root)
        self.computeModules = ShaderLibrary.loadComputeModules(root: root)
    }

    public func module(for id: ShaderID) throws -> ShaderModule {
        guard let module = modules[id] else {
            throw AgentError.invalidArgument("Unknown shader id: \(id.rawValue)")
        }
        return module
    }

    public func computeModule(for id: ShaderID) throws -> ComputeShaderModule {
        guard let module = computeModules[id] else {
            throw AgentError.invalidArgument("Unknown compute shader id: \(id.rawValue)")
        }
        return module
    }

    public func metalLibraryURL(for id: ShaderID) throws -> URL {
        let module = try module(for: id)
        return try module.artifacts.requireMetalLibrary(for: id)
    }

    public func metalLibraryURLForComputeShader(_ id: ShaderID) throws -> URL {
        let module = try computeModule(for: id)
        return try module.artifacts.requireMetalLibrary(for: id)
    }

#if DEBUG
    internal func _registerTestModule(_ module: ShaderModule) {
        modules[module.id] = module
    }

    internal func _unregisterTestModule(_ id: ShaderID) {
        modules.removeValue(forKey: id)
    }

    internal func _registerTestComputeModule(_ module: ComputeShaderModule) {
        computeModules[module.id] = module
    }

    internal func _unregisterTestComputeModule(_ id: ShaderID) {
        computeModules.removeValue(forKey: id)
    }
#endif

    private static func resolveGeneratedRoot() -> URL {
        let fm = FileManager.default
        if let override = SettingsStore.getString("shader.root"), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let override = ProcessInfo.processInfo.environment["SDLKIT_SHADER_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        #if SWIFT_PACKAGE
        if let resourceURL = Bundle.module.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Generated", isDirectory: true)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        #endif

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent("Sources/SDLKit/Generated", isDirectory: true)
    }

    private static func loadModules(root: URL) -> [ShaderID: ShaderModule] {
        var modules: [ShaderID: ShaderModule] = [:]

        let unlit = makeUnlitTriangleModule(root: root)
        modules[unlit.id] = unlit

        let lit = makeBasicLitModule(root: root)
        modules[lit.id] = lit

        if let directional = makeDirectionalLitModule(root: root) {
            modules[directional.id] = directional
        }

        if let pbr = makePBRForwardModule(root: root) {
            modules[pbr.id] = pbr
        }

        return modules
    }

    private static func loadComputeModules(root: URL) -> [ShaderID: ComputeShaderModule] {
        var result: [ShaderID: ComputeShaderModule] = [:]
        if let sceneWave = makeScenegraphWaveComputeModule(root: root) {
            result[sceneWave.id] = sceneWave
        }
        if let vectorAdd = makeVectorAddComputeModule(root: root) {
            result[vectorAdd.id] = vectorAdd
        }
        if let prefilter = makeIBLPrefilterEnvComputeModule(root: root) {
            result[prefilter.id] = prefilter
        }
        if let brdf = makeIBLBRDFLUTComputeModule(root: root) {
            result[brdf.id] = brdf
        }
        if let audio = makeAudioDFTPowerComputeModule(root: root) {
            result[audio.id] = audio
        }
        if let audioMel = makeAudioMelProjectComputeModule(root: root) {
            result[audioMel.id] = audioMel
        }
        if let onset = makeAudioOnsetFluxComputeModule(root: root) {
            result[onset.id] = onset
        }
        return result
    }

    private static func makeUnlitTriangleModule(root: URL) -> ShaderModule {
        let id = ShaderID("unlit_triangle")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)
        let artifacts = ShaderModuleArtifacts(
            dxilVertex: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("unlit_triangle_vs.dxil")),
            dxilFragment: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("unlit_triangle_ps.dxil")),
            spirvVertex: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("unlit_triangle.vert.spv")),
            spirvFragment: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("unlit_triangle.frag.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("unlit_triangle.metallib"))
        )

        let layout = VertexLayout(
            stride: MemoryLayout<Float>.size * 6,
            attributes: [
                .init(index: 0, semantic: "POSITION", format: .float3, offset: 0),
                .init(index: 1, semantic: "COLOR", format: .float3, offset: MemoryLayout<Float>.size * 3)
            ]
        )

        let pushConstantSize = MemoryLayout<Float>.size * 24

        return ShaderModule(
            id: id,
            vertexEntryPoint: "unlit_triangle_vs",
            fragmentEntryPoint: "unlit_triangle_ps",
            vertexLayout: layout,
            // Vertex stage expects a 4x4 transform:
            // - D3D12: cbuffer at b0
            // - Metal: constant buffer at [[buffer(1)]] (backend sets it)
            // - Vulkan: push constants (backend sets it)
            bindings: [
                .vertex: [ BindingSlot(index: 0, kind: .uniformBuffer) ],
                .fragment: [ BindingSlot(index: 10, kind: .sampledTexture) ]
            ],
            pushConstantSize: pushConstantSize,
            artifacts: artifacts
        )
    }

    private static func makeBasicLitModule(root: URL) -> ShaderModule {
        let id = ShaderID("basic_lit")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)
        let artifacts = ShaderModuleArtifacts(
            dxilVertex: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("basic_lit_vs.dxil")),
            dxilFragment: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("basic_lit_ps.dxil")),
            spirvVertex: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("basic_lit.vert.spv")),
            spirvFragment: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("basic_lit.frag.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("basic_lit.metallib"))
        )

        let layout = VertexLayout(
            stride: MemoryLayout<Float>.size * 9,
            attributes: [
                .init(index: 0, semantic: "POSITION", format: .float3, offset: 0),
                .init(index: 1, semantic: "NORMAL", format: .float3, offset: MemoryLayout<Float>.size * 3),
                .init(index: 2, semantic: "COLOR", format: .float3, offset: MemoryLayout<Float>.size * 6)
            ]
        )

        let pushConstantSize = MemoryLayout<Float>.size * 24

        return ShaderModule(
            id: id,
            vertexEntryPoint: "basic_lit_vs",
            fragmentEntryPoint: "basic_lit_ps",
            vertexLayout: layout,
            bindings: [
                .vertex: [ BindingSlot(index: 0, kind: .uniformBuffer) ],
                .fragment: [ BindingSlot(index: 10, kind: .sampledTexture) ]
            ],
            pushConstantSize: pushConstantSize,
            artifacts: artifacts
        )
    }

    private static func makeDirectionalLitModule(root: URL) -> ShaderModule? {
        let id = ShaderID("directional_lit")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)
        let artifacts = ShaderModuleArtifacts(
            dxilVertex: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("directional_lit_vs.dxil")),
            dxilFragment: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("directional_lit_ps.dxil")),
            spirvVertex: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("directional_lit.vert.spv")),
            spirvFragment: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("directional_lit.frag.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("directional_lit.metallib"))
        )

        if artifacts.dxilVertex == nil && artifacts.spirvVertex == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let layout = VertexLayout(
            stride: MemoryLayout<Float>.size * 8,
            attributes: [
                .init(index: 0, semantic: "POSITION", format: .float3, offset: 0),
                .init(index: 1, semantic: "NORMAL", format: .float3, offset: MemoryLayout<Float>.size * 3),
                .init(index: 2, semantic: "TEXCOORD0", format: .float2, offset: MemoryLayout<Float>.size * 6)
            ]
        )

        let pushConstantSize = MemoryLayout<Float>.size * 60

        return ShaderModule(
            id: id,
            vertexEntryPoint: "directional_lit_vs",
            fragmentEntryPoint: "directional_lit_ps",
            vertexLayout: layout,
            bindings: [
                .vertex: [BindingSlot(index: 0, kind: .uniformBuffer)],
                .fragment: [
                    BindingSlot(index: 10, kind: .sampledTexture),
                    BindingSlot(index: 10, kind: .sampler),
                    BindingSlot(index: 20, kind: .sampledTexture),
                    BindingSlot(index: 20, kind: .sampler)
                ]
            ],
            pushConstantSize: pushConstantSize,
            artifacts: artifacts
        )
    }

    private static func makePBRForwardModule(root: URL) -> ShaderModule? {
        let id = ShaderID("pbr_forward")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)
        let artifacts = ShaderModuleArtifacts(
            dxilVertex: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("pbr_forward_vs.dxil")),
            dxilFragment: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("pbr_forward_ps.dxil")),
            spirvVertex: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("pbr_forward.vert.spv")),
            spirvFragment: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("pbr_forward.frag.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("pbr_forward.metallib"))
        )

        if artifacts.dxilVertex == nil && artifacts.spirvVertex == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let layout = VertexLayout(
            stride: MemoryLayout<Float>.size * 11,
            attributes: [
                .init(index: 0, semantic: "POSITION", format: .float3, offset: 0),
                .init(index: 1, semantic: "NORMAL", format: .float3, offset: MemoryLayout<Float>.size * 3),
                .init(index: 2, semantic: "TANGENT", format: .float3, offset: MemoryLayout<Float>.size * 6),
                .init(index: 3, semantic: "TEXCOORD0", format: .float2, offset: MemoryLayout<Float>.size * 9)
            ]
        )

        let pushConstantSize = MemoryLayout<Float>.size * 60

        return ShaderModule(
            id: id,
            vertexEntryPoint: "pbr_forward_vs",
            fragmentEntryPoint: "pbr_forward_ps",
            vertexLayout: layout,
            bindings: [
                .vertex: [BindingSlot(index: 0, kind: .uniformBuffer)],
                .fragment: [
                    BindingSlot(index: 1, kind: .uniformBuffer),
                    BindingSlot(index: 10, kind: .sampledTexture),
                    BindingSlot(index: 10, kind: .sampler),
                    BindingSlot(index: 11, kind: .sampledTexture),
                    BindingSlot(index: 12, kind: .sampledTexture),
                    BindingSlot(index: 13, kind: .sampledTexture),
                    BindingSlot(index: 14, kind: .sampledTexture),
                    BindingSlot(index: 20, kind: .sampledTexture),
                    BindingSlot(index: 21, kind: .sampledTexture),
                    BindingSlot(index: 21, kind: .sampler),
                    BindingSlot(index: 22, kind: .sampledTexture),
                    BindingSlot(index: 22, kind: .sampler)
                ]
            ],
            pushConstantSize: pushConstantSize,
            artifacts: artifacts
        )
    }

    private static func makeVectorAddComputeModule(root: URL) -> ComputeShaderModule? {
        let id = ShaderID("vector_add")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)

        let artifacts = ComputeShaderModuleArtifacts(
            dxil: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("vector_add_cs.dxil")),
            spirv: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("vector_add.comp.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("vector_add.metallib"))
        )

        if artifacts.dxil == nil && artifacts.spirv == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let bindings: [BindingSlot] = [
            BindingSlot(index: 0, kind: .storageBuffer),
            BindingSlot(index: 1, kind: .storageBuffer),
            BindingSlot(index: 2, kind: .storageBuffer)
        ]

        return ComputeShaderModule(
            id: id,
            entryPoint: "vector_add_cs",
            threadgroupSize: (64, 1, 1),
            pushConstantSize: MemoryLayout<Float>.size * 4,
            bindings: bindings,
            artifacts: artifacts
        )
    }

    private static func makeScenegraphWaveComputeModule(root: URL) -> ComputeShaderModule? {
        let id = ShaderID("scenegraph_wave")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)

        let artifacts = ComputeShaderModuleArtifacts(
            dxil: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("scenegraph_wave_cs.dxil")),
            spirv: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("scenegraph_wave.comp.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("scenegraph_wave.metallib"))
        )

        if artifacts.dxil == nil && artifacts.spirv == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let bindings: [BindingSlot] = [
            BindingSlot(index: 0, kind: .storageBuffer),
            BindingSlot(index: 1, kind: .storageBuffer),
            BindingSlot(index: 2, kind: .storageBuffer)
        ]

        return ComputeShaderModule(
            id: id,
            entryPoint: "main",
            threadgroupSize: (1, 1, 1),
            pushConstantSize: 0,
            bindings: bindings,
            artifacts: artifacts
        )
    }

    private static func makeIBLPrefilterEnvComputeModule(root: URL) -> ComputeShaderModule? {
        let id = ShaderID("ibl_prefilter_env")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)

        let artifacts = ComputeShaderModuleArtifacts(
            dxil: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("ibl_prefilter_env_cs.dxil")),
            spirv: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("ibl_prefilter_env.comp.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("ibl_prefilter_env.metallib"))
        )

        if artifacts.dxil == nil && artifacts.spirv == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let bindings: [BindingSlot] = [
            BindingSlot(index: 0, kind: .sampledTexture),
            BindingSlot(index: 0, kind: .sampler),
            BindingSlot(index: 1, kind: .storageTexture)
        ]

        return ComputeShaderModule(
            id: id,
            entryPoint: "ibl_prefilter_env_cs",
            threadgroupSize: (8, 8, 1),
            pushConstantSize: MemoryLayout<Float>.size * 4,
            bindings: bindings,
            artifacts: artifacts
        )
    }

    private static func makeIBLBRDFLUTComputeModule(root: URL) -> ComputeShaderModule? {
        let id = ShaderID("ibl_brdf_lut")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)

        let artifacts = ComputeShaderModuleArtifacts(
            dxil: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("ibl_brdf_lut_cs.dxil")),
            spirv: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("ibl_brdf_lut.comp.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("ibl_brdf_lut.metallib"))
        )

        if artifacts.dxil == nil && artifacts.spirv == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let bindings: [BindingSlot] = [
            BindingSlot(index: 0, kind: .storageTexture)
        ]

        return ComputeShaderModule(
            id: id,
            entryPoint: "ibl_brdf_lut_cs",
            threadgroupSize: (16, 16, 1),
            pushConstantSize: MemoryLayout<Float>.size * 4,
            bindings: bindings,
            artifacts: artifacts
        )
    }

    private static func makeAudioDFTPowerComputeModule(root: URL) -> ComputeShaderModule? {
        let id = ShaderID("audio_dft_power")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)

        let artifacts = ComputeShaderModuleArtifacts(
            dxil: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("audio_dft_power_cs.dxil")),
            spirv: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("audio_dft_power.comp.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("audio_dft_power.metallib"))
        )

        if artifacts.dxil == nil && artifacts.spirv == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let bindings: [BindingSlot] = [
            BindingSlot(index: 0, kind: .storageBuffer), // input samples
            BindingSlot(index: 1, kind: .storageBuffer)  // output power
        ]

        return ComputeShaderModule(
            id: id,
            entryPoint: "audio_dft_power_cs",
            threadgroupSize: (64, 1, 1),
            pushConstantSize: MemoryLayout<UInt32>.size * 4,
            bindings: bindings,
            artifacts: artifacts
        )
    }

    private static func makeAudioMelProjectComputeModule(root: URL) -> ComputeShaderModule? {
        let id = ShaderID("audio_mel_project")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)

        let artifacts = ComputeShaderModuleArtifacts(
            dxil: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("audio_mel_project_cs.dxil")),
            spirv: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("audio_mel_project.comp.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("audio_mel_project.metallib"))
        )

        if artifacts.dxil == nil && artifacts.spirv == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let bindings: [BindingSlot] = [
            BindingSlot(index: 0, kind: .storageBuffer), // input power spectra
            BindingSlot(index: 1, kind: .storageBuffer), // mel weights matrix
            BindingSlot(index: 2, kind: .storageBuffer)  // output mel energies
        ]

        return ComputeShaderModule(
            id: id,
            entryPoint: "audio_mel_project_cs",
            threadgroupSize: (64, 1, 1),
            pushConstantSize: MemoryLayout<UInt32>.size * 4,
            bindings: bindings,
            artifacts: artifacts
        )
    }

    private static func makeAudioOnsetFluxComputeModule(root: URL) -> ComputeShaderModule? {
        let id = ShaderID("audio_onset_flux")
        let dxilRoot = root.appendingPathComponent("dxil", isDirectory: true)
        let spirvRoot = root.appendingPathComponent("spirv", isDirectory: true)
        let metalRoot = root.appendingPathComponent("metal", isDirectory: true)

        let artifacts = ComputeShaderModuleArtifacts(
            dxil: ShaderLibrary.existingFile(dxilRoot.appendingPathComponent("audio_onset_flux_cs.dxil")),
            spirv: ShaderLibrary.existingFile(spirvRoot.appendingPathComponent("audio_onset_flux.comp.spv")),
            metalLibrary: ShaderLibrary.existingFile(metalRoot.appendingPathComponent("audio_onset_flux.metallib"))
        )

        if artifacts.dxil == nil && artifacts.spirv == nil && artifacts.metalLibrary == nil {
            return nil
        }

        let bindings: [BindingSlot] = [
            BindingSlot(index: 0, kind: .storageBuffer), // mel frames
            BindingSlot(index: 1, kind: .storageBuffer), // prev mel
            BindingSlot(index: 2, kind: .storageBuffer)  // onset out
        ]

        return ComputeShaderModule(
            id: id,
            entryPoint: "audio_onset_flux_cs",
            threadgroupSize: (1, 1, 1),
            pushConstantSize: MemoryLayout<UInt32>.size * 4,
            bindings: bindings,
            artifacts: artifacts
        )
    }

    private static func existingFile(_ url: URL) -> URL? {
        do {
            if let realized = try ShaderArtifactMaterializer.materializeArtifactIfNeeded(at: url) {
                return realized
            }
        } catch {
            // Fall back to simple existence checks below if decoding fails.
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}
