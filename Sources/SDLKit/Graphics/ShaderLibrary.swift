import Foundation

public struct ShaderModuleArtifacts {
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

public struct ShaderModule {
    public let id: ShaderID
    public let vertexEntryPoint: String
    public let fragmentEntryPoint: String?
    public let vertexLayout: VertexLayout
    public let bindings: [ShaderStage: [BindingSlot]]
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

    private let modules: [ShaderID: ShaderModule]
    private init() {
        let root = ShaderLibrary.resolveGeneratedRoot()
        self.modules = ShaderLibrary.loadModules(root: root)
    }

    public func module(for id: ShaderID) throws -> ShaderModule {
        guard let module = modules[id] else {
            throw AgentError.invalidArgument("Unknown shader id: \(id.rawValue)")
        }
        return module
    }

    public func metalLibraryURL(for id: ShaderID) throws -> URL {
        let module = try module(for: id)
        return try module.artifacts.requireMetalLibrary(for: id)
    }

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
        let unlit = makeUnlitTriangleModule(root: root)
        let lit = makeBasicLitModule(root: root)
        return [unlit.id: unlit, lit.id: lit]
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

        return ShaderModule(
            id: id,
            vertexEntryPoint: "unlit_triangle_vs",
            fragmentEntryPoint: "unlit_triangle_ps",
            vertexLayout: layout,
            // Vertex stage expects a 4x4 transform:
            // - D3D12: cbuffer at b0
            // - Metal: constant buffer at [[buffer(1)]] (backend sets it)
            // - Vulkan: push constants (backend sets it)
            bindings: [ .vertex: [ BindingSlot(index: 0, kind: .uniformBuffer) ] ],
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

        return ShaderModule(
            id: id,
            vertexEntryPoint: "basic_lit_vs",
            fragmentEntryPoint: "basic_lit_ps",
            vertexLayout: layout,
            bindings: [ .vertex: [ BindingSlot(index: 0, kind: .uniformBuffer) ] ],
            artifacts: artifacts
        )
    }

    private static func existingFile(_ url: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}
