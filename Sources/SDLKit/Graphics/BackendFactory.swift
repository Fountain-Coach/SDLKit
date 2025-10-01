import Foundation

@MainActor
final class StubRenderBackendCore {
    enum Kind: String {
        case metal
        case d3d12
        case vulkan

        var label: String {
            switch self {
            case .metal: return "Metal"
            case .d3d12: return "D3D12"
            case .vulkan: return "Vulkan"
            }
        }
    }

    struct BufferResource {
        var data: Data
        var usage: BufferUsage
    }

    struct TextureResource {
        var descriptor: TextureDescriptor
        var data: TextureInitialData?
    }

    struct PipelineResource {
        var descriptor: GraphicsPipelineDescriptor
    }

    struct ComputePipelineResource {
        var descriptor: ComputePipelineDescriptor
    }

    struct MeshResource {
        var vertexBuffer: BufferHandle
        var vertexCount: Int
        var indexBuffer: BufferHandle?
        var indexCount: Int
        var indexFormat: IndexFormat

        func matches(vertexBuffer: BufferHandle,
                     vertexCount: Int,
                     indexBuffer: BufferHandle?,
                     indexCount: Int,
                     indexFormat: IndexFormat) -> Bool {
            self.vertexBuffer == vertexBuffer &&
            self.vertexCount == vertexCount &&
            self.indexBuffer == indexBuffer &&
            self.indexCount == indexCount &&
            self.indexFormat == indexFormat
        }
    }

    private let kind: Kind
    private let surface: RenderSurface
    private(set) var currentSize: (width: Int, height: Int)
    private var buffers: [BufferHandle: BufferResource] = [:]
    private var textures: [TextureHandle: TextureResource] = [:]
    private var pipelines: [PipelineHandle: PipelineResource] = [:]
    private var computePipelines: [ComputePipelineHandle: ComputePipelineResource] = [:]
    private var meshes: [MeshHandle: MeshResource] = [:]
    private var frameActive = false

    init(kind: Kind, window: SDLWindow) throws {
        self.kind = kind
        self.surface = try RenderSurface(window: window)
        self.currentSize = (width: window.config.width, height: window.config.height)
        SDLLogger.info("SDLKit.Graphics", "Initialized stub \(kind.label) backend")
        logSurface()
    }

    private func logSurface() {
        #if canImport(QuartzCore)
        if let layer = surface.metalLayer {
            SDLLogger.debug("SDLKit.Graphics", "Surface metalLayer=\(layer)")
        }
        #endif
        if let hwnd = surface.win32HWND {
            SDLLogger.debug("SDLKit.Graphics", String(format: "Surface HWND=0x%016llX", UInt64(UInt(bitPattern: hwnd))))
        }
    }

    func registerMesh(vertexBuffer: BufferHandle,
                      vertexCount: Int,
                      indexBuffer: BufferHandle?,
                      indexCount: Int,
                      indexFormat: IndexFormat) -> MeshHandle {
        if let existing = meshes.first(where: { $0.value.matches(vertexBuffer: vertexBuffer,
                                                                 vertexCount: vertexCount,
                                                                 indexBuffer: indexBuffer,
                                                                 indexCount: indexCount,
                                                                 indexFormat: indexFormat) })?.key {
            return existing
        }
        let handle = MeshHandle()
        meshes[handle] = MeshResource(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexFormat: indexFormat
        )
        return handle
    }

    func beginFrame() throws {
        guard !frameActive else {
            throw AgentError.internalError("beginFrame called twice without endFrame")
        }
        frameActive = true
        SDLLogger.debug("SDLKit.Graphics", "beginFrame on \(kind.label)")
    }

    func endFrame() throws {
        guard frameActive else {
            throw AgentError.internalError("endFrame called without beginFrame")
        }
        frameActive = false
        SDLLogger.debug("SDLKit.Graphics", "endFrame on \(kind.label)")
    }

    func resize(width: Int, height: Int) {
        currentSize = (width, height)
        SDLLogger.info("SDLKit.Graphics", "resize => \(width)x\(height) on \(kind.label)")
    }

    func waitGPU() {
        SDLLogger.debug("SDLKit.Graphics", "waitGPU on \(kind.label)")
    }

    func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) -> BufferHandle {
        var data = Data()
        if let bytes, length > 0 {
            data = Data(bytes: bytes, count: length)
        }
        let handle = BufferHandle()
        buffers[handle] = BufferResource(data: data, usage: usage)
        SDLLogger.debug("SDLKit.Graphics", "createBuffer id=\(handle.rawValue) bytes=\(length) usage=\(usage)")
        return handle
    }

    func bufferData(_ handle: BufferHandle) -> Data? {
        buffers[handle]?.data
    }

    func withMutableBufferData(_ handle: BufferHandle, _ body: (inout Data) throws -> Void) throws {
        guard var resource = buffers[handle] else {
            throw AgentError.invalidArgument("Unknown buffer handle \(handle.rawValue)")
        }
        try body(&resource.data)
        buffers[handle] = resource
    }

    func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) -> TextureHandle {
        let handle = TextureHandle()
        textures[handle] = TextureResource(descriptor: descriptor, data: initialData)
        SDLLogger.debug("SDLKit.Graphics", "createTexture id=\(handle.rawValue) size=\(descriptor.width)x\(descriptor.height) format=\(descriptor.format.rawValue)")
        return handle
    }

    func destroy(_ handle: ResourceHandle) {
        switch handle {
        case .buffer(let h):
            buffers.removeValue(forKey: h)
        case .texture(let h):
            textures.removeValue(forKey: h)
        case .pipeline(let h):
            pipelines.removeValue(forKey: h)
        case .computePipeline(let h):
            computePipelines.removeValue(forKey: h)
        case .mesh(let h):
            meshes.removeValue(forKey: h)
        }
        SDLLogger.debug("SDLKit.Graphics", "destroy handle=\(handle)")
    }

    func makePipeline(_ desc: GraphicsPipelineDescriptor) -> PipelineHandle {
        let handle = PipelineHandle()
        pipelines[handle] = PipelineResource(descriptor: desc)
        SDLLogger.debug(
            "SDLKit.Graphics",
            "makePipeline id=\(handle.rawValue) label=\(desc.label ?? "<nil>") shader=\(desc.shader.rawValue)"
        )
        return handle
    }

    func draw(mesh: MeshHandle,
              pipeline: PipelineHandle,
              bindings: BindingSet,
              transform: float4x4) throws {
        guard frameActive else {
            throw AgentError.internalError("draw called outside beginFrame/endFrame")
        }
        guard pipelines[pipeline] != nil else {
            throw AgentError.internalError("Unknown pipeline for draw call")
        }
        guard let meshResource = meshes[mesh] else {
            throw AgentError.internalError("Unknown mesh handle for draw call")
        }
        SDLLogger.debug(
            "SDLKit.Graphics",
            "draw mesh=\(mesh.rawValue) pipeline=\(pipeline.rawValue) vertexBuffer=\(meshResource.vertexBuffer.rawValue) vertexCount=\(meshResource.vertexCount) indexBuffer=\(meshResource.indexBuffer?.rawValue ?? 0) indexCount=\(meshResource.indexCount)"
        )
        _ = bindings
        _ = transform
    }

    func makeComputePipeline(_ desc: ComputePipelineDescriptor) -> ComputePipelineHandle {
        let handle = ComputePipelineHandle()
        computePipelines[handle] = ComputePipelineResource(descriptor: desc)
        SDLLogger.debug("SDLKit.Graphics", "makeComputePipeline id=\(handle.rawValue) label=\(desc.label ?? "<nil>")")
        return handle
    }

    func dispatchCompute(_ pipeline: ComputePipelineHandle,
                         groupsX: Int, groupsY: Int, groupsZ: Int,
                         bindings: BindingSet) throws {
        guard computePipelines[pipeline] != nil else {
            throw AgentError.internalError("Unknown compute pipeline")
        }
        SDLLogger.debug("SDLKit.Graphics", "dispatchCompute pipeline=\(pipeline.rawValue) groups=(\(groupsX),\(groupsY),\(groupsZ))")
        _ = bindings
    }
}

@MainActor
public class StubRenderBackend: RenderBackend {
    fileprivate let core: StubRenderBackendCore

    fileprivate init(kind: StubRenderBackendCore.Kind, window: SDLWindow) throws {
        self.core = try StubRenderBackendCore(kind: kind, window: window)
    }

    required public init(window: SDLWindow) throws {
        fatalError("Use specialized subclass initializers")
    }

    public func beginFrame() throws { try core.beginFrame() }
    public func endFrame() throws { try core.endFrame() }
    public func resize(width: Int, height: Int) throws { core.resize(width: width, height: height) }
    public func waitGPU() throws { core.waitGPU() }
    public func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle { core.createBuffer(bytes: bytes, length: length, usage: usage) }
    public func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle { core.createTexture(descriptor: descriptor, initialData: initialData) }
    public func destroy(_ handle: ResourceHandle) { core.destroy(handle) }
    public func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle { core.makePipeline(desc) }
    public func draw(mesh: MeshHandle, pipeline: PipelineHandle, bindings: BindingSet, transform: float4x4) throws { try core.draw(mesh: mesh, pipeline: pipeline, bindings: bindings, transform: transform) }
    public func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle { core.makeComputePipeline(desc) }
    public func dispatchCompute(_ pipeline: ComputePipelineHandle, groupsX: Int, groupsY: Int, groupsZ: Int, bindings: BindingSet) throws { try core.dispatchCompute(pipeline, groupsX: groupsX, groupsY: groupsY, groupsZ: groupsZ, bindings: bindings) }

    public func registerMesh(vertexBuffer: BufferHandle,
                             vertexCount: Int,
                             indexBuffer: BufferHandle?,
                             indexCount: Int,
                             indexFormat: IndexFormat) throws -> MeshHandle {
        return core.registerMesh(vertexBuffer: vertexBuffer,
                                 vertexCount: vertexCount,
                                 indexBuffer: indexBuffer,
                                 indexCount: indexCount,
                                 indexFormat: indexFormat)
    }

    func bufferData(_ handle: BufferHandle) -> Data? { core.bufferData(handle) }

    func withMutableBufferData(_ handle: BufferHandle, _ body: (inout Data) throws -> Void) throws {
        try core.withMutableBufferData(handle, body)
    }
}

#if !canImport(Metal)
@MainActor
public final class MetalRenderBackend: StubRenderBackend {
    required public init(window: SDLWindow) throws {
        try super.init(kind: .metal, window: window)
    }
}
#endif

#if !os(Windows)
@MainActor
public final class D3D12RenderBackend: StubRenderBackend {
    required public init(window: SDLWindow) throws {
        try super.init(kind: .d3d12, window: window)
    }
}
#endif

#if !(os(Linux) && canImport(VulkanMinimal) && canImport(CVulkan))
@MainActor
public final class VulkanRenderBackend: StubRenderBackend {
    required public init(window: SDLWindow) throws {
        try super.init(kind: .vulkan, window: window)
    }

    public func takeValidationMessages() -> [String] {
        return []
    }
}
#endif

@MainActor
public enum RenderBackendFactory {
    public enum Choice: String {
        case metal
        case d3d12
        case vulkan

        static func parse(_ raw: String) -> Choice? {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch value {
            case "metal", "mtl": return .metal
            case "d3d12", "direct3d", "dx12": return .d3d12
            case "vulkan", "vk": return .vulkan
            default: return nil
            }
        }
    }

    public static func defaultChoice() -> Choice {
        #if os(macOS)
        return .metal
        #elseif os(Windows)
        return .d3d12
        #elseif os(Linux)
        return .vulkan
        #else
        return .metal
        #endif
    }

    public static func makeBackend(window: SDLWindow, override: String? = nil) throws -> RenderBackend {
        let overrideValue = override ?? SDLKitConfig.renderBackendOverride
        let choice: Choice
        if let overrideValue {
            guard let parsed = Choice.parse(overrideValue) else {
                throw AgentError.invalidArgument("Unknown render backend override: \(overrideValue)")
            }
            choice = parsed
        } else {
            choice = defaultChoice()
        }
        if !isChoiceSupported(choice) {
            throw AgentError.invalidArgument("Render backend \(choice.rawValue) not supported on this platform")
        }
        SDLLogger.info("SDLKit.Graphics", "RenderBackendFactory => \(choice.rawValue)")
        switch choice {
        case .metal:
            return try MetalRenderBackend(window: window)
        case .d3d12:
            return try D3D12RenderBackend(window: window)
        case .vulkan:
            return try VulkanRenderBackend(window: window)
        }
    }

    private static func isChoiceSupported(_ choice: Choice) -> Bool {
        switch choice {
        case .metal:
            #if os(macOS)
            return true
            #else
            return false
            #endif
        case .d3d12:
            #if os(Windows)
            return true
            #else
            return false
            #endif
        case .vulkan:
            #if os(Linux)
            return true
            #else
            return false
            #endif
        }
    }
}
