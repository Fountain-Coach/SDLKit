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
        var data: Data

        var width: Int { descriptor.width }
        var height: Int { descriptor.height }
        var usage: TextureUsage { descriptor.usage }
        var format: TextureFormat { descriptor.format }
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
    private var samplers: [SamplerHandle: SamplerDescriptor] = [:]
    private var pipelines: [PipelineHandle: PipelineResource] = [:]
    private var computePipelines: [ComputePipelineHandle: ComputePipelineResource] = [:]
    private var meshes: [MeshHandle: MeshResource] = [:]
    private var frameActive = false
    private var framebuffer: Data = Data()
    private var depthbuffer: Data = Data()
    private var captureRequested = false
    private var lastCaptureHash: String?
    private var lastCaptureData: Data?
    private var lastCaptureBytesPerRow: Int = 0

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
        let colorBytes = max(1, currentSize.width * currentSize.height * 4)
        framebuffer = Data(count: colorBytes)
        depthbuffer = Data(count: max(1, currentSize.width * currentSize.height * MemoryLayout<Float>.size))
        lastCaptureHash = nil
        lastCaptureData = nil
        lastCaptureBytesPerRow = 0
    }

    func endFrame() throws {
        guard frameActive else {
            throw AgentError.internalError("endFrame called without beginFrame")
        }
        frameActive = false
        SDLLogger.debug("SDLKit.Graphics", "endFrame on \(kind.label)")
        if captureRequested {
            var combined = framebuffer
            combined.append(depthbuffer)
            lastCaptureHash = StubRenderBackendCore.hashHex(combined)
            lastCaptureData = framebuffer
            lastCaptureBytesPerRow = max(1, currentSize.width * 4)
            captureRequested = false
        }
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
        let bytesPerPixel: Int
        switch descriptor.format {
        case .rgba8Unorm, .bgra8Unorm:
            bytesPerPixel = 4
        case .depth32Float:
            bytesPerPixel = MemoryLayout<Float>.size
        }
        let pixelCount = max(1, descriptor.width * descriptor.height)
        var storage = Data(count: pixelCount * bytesPerPixel)
        if let firstLevel = initialData?.mipLevelData.first, !firstLevel.isEmpty {
            let copyCount = min(storage.count, firstLevel.count)
            storage.replaceSubrange(0..<copyCount, with: firstLevel.prefix(copyCount))
        }
        textures[handle] = TextureResource(descriptor: descriptor, data: storage)
        SDLLogger.debug("SDLKit.Graphics", "createTexture id=\(handle.rawValue) size=\(descriptor.width)x\(descriptor.height) format=\(descriptor.format.rawValue)")
        return handle
    }

    func createSampler(descriptor: SamplerDescriptor) -> SamplerHandle {
        let handle = SamplerHandle()
        samplers[handle] = descriptor
        SDLLogger.debug("SDLKit.Graphics", "createSampler id=\(handle.rawValue) label=\(descriptor.label ?? "<nil>")")
        return handle
    }

    func destroy(_ handle: ResourceHandle) {
        switch handle {
        case .buffer(let h):
            buffers.removeValue(forKey: h)
        case .texture(let h):
            textures.removeValue(forKey: h)
        case .sampler(let h):
            samplers.removeValue(forKey: h)
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
        if let pipelineResource = pipelines[pipeline], pipelineResource.descriptor.shader.rawValue == "basic_lit" {
            if let textureHandle = bindings.texture(at: 10), let resource = textures[textureHandle] {
                blit(texture: resource)
            }
        }
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
        try applyComputeWork(for: pipeline, groupsX: groupsX, groupsY: groupsY, groupsZ: groupsZ, bindings: bindings)
    }

    func requestCapture() {
        captureRequested = true
    }

    func takeCaptureHash() throws -> String {
        guard let hash = lastCaptureHash else {
            throw AgentError.internalError("No capture hash available; call requestCapture() before endFrame")
        }
        return hash
    }

    func takeCapturePayload() throws -> GoldenImageCapture {
        guard let data = lastCaptureData else {
            throw AgentError.internalError("No capture data available; call requestCapture() before endFrame")
        }
        let width = max(1, currentSize.width)
        let height = max(1, currentSize.height)
        let bytesPerRow = lastCaptureBytesPerRow > 0 ? lastCaptureBytesPerRow : max(1, width * 4)
        return GoldenImageCapture(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            layout: .bgra8Unorm,
            data: data
        )
    }

    private func applyComputeWork(for pipeline: ComputePipelineHandle,
                                   groupsX: Int,
                                   groupsY: Int,
                                   groupsZ: Int,
                                   bindings: BindingSet) throws {
        guard let descriptor = computePipelines[pipeline]?.descriptor else { return }
        guard descriptor.shader.rawValue == "compute_storage_texture" else { return }
        guard let textureHandle = bindings.texture(at: 0) else {
            throw AgentError.invalidArgument("Missing storage texture binding at slot 0")
        }
        guard var resource = textures[textureHandle] else {
            throw AgentError.invalidArgument("Unknown storage texture handle")
        }
        guard resource.usage == .shaderWrite else {
            throw AgentError.invalidArgument("Storage texture binding must have shaderWrite usage")
        }
        guard resource.format == .rgba8Unorm || resource.format == .bgra8Unorm else {
            throw AgentError.invalidArgument("Storage texture must be a color format")
        }

        let width = max(1, resource.width)
        let height = max(1, resource.height)
        let totalPixels = width * height
        if resource.data.count < totalPixels * 4 {
            resource.data = Data(count: totalPixels * 4)
        }

        resource.data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let normalizedX = Float(x) / Float(max(1, width - 1))
                    let normalizedY = Float(y) / Float(max(1, height - 1))
                    base[offset + 0] = UInt8(min(255, max(0, Int(normalizedX * 255.0))))
                    base[offset + 1] = UInt8(min(255, max(0, Int(normalizedY * 255.0))))
                    let pattern = UInt8(((x + y + groupsX + groupsY + groupsZ) % 256))
                    base[offset + 2] = pattern
                    base[offset + 3] = 255
                }
            }
        }

        textures[textureHandle] = resource
    }

    private func blit(texture resource: TextureResource) {
        guard resource.format == .rgba8Unorm || resource.format == .bgra8Unorm else { return }
        let targetWidth = max(1, currentSize.width)
        let targetHeight = max(1, currentSize.height)
        let sourceWidth = max(1, resource.width)
        let sourceHeight = max(1, resource.height)
        if framebuffer.count < targetWidth * targetHeight * 4 {
            framebuffer = Data(count: targetWidth * targetHeight * 4)
        }

        framebuffer.withUnsafeMutableBytes { dstBuf in
            resource.data.withUnsafeBytes { srcBuf in
                guard let dstBase = dstBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                guard let srcBase = srcBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for y in 0..<targetHeight {
                    let srcY = min(sourceHeight - 1, y * sourceHeight / max(1, targetHeight))
                    for x in 0..<targetWidth {
                        let srcX = min(sourceWidth - 1, x * sourceWidth / max(1, targetWidth))
                        let dstOffset = (y * targetWidth + x) * 4
                        let srcOffset = (srcY * sourceWidth + srcX) * 4
                        dstBase[dstOffset + 0] = srcBase[srcOffset + 0]
                        dstBase[dstOffset + 1] = srcBase[srcOffset + 1]
                        dstBase[dstOffset + 2] = srcBase[srcOffset + 2]
                        dstBase[dstOffset + 3] = srcBase[srcOffset + 3]
                    }
                }
            }
        }

        depthbuffer.withUnsafeMutableBytes { buffer in
            guard let depthBase = buffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            let count = targetWidth * targetHeight
            for index in 0..<count {
                let x = index % targetWidth
                depthBase[index] = Float(x) / Float(max(1, targetWidth - 1))
            }
        }
    }

    private static func hashHex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

@MainActor
public class StubRenderBackend: RenderBackend {
    fileprivate let core: StubRenderBackendCore
    public var deviceEventHandler: RenderBackendDeviceEventHandler?

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
    public func createSampler(descriptor: SamplerDescriptor) throws -> SamplerHandle { core.createSampler(descriptor: descriptor) }
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

extension StubRenderBackend: GoldenImageCapturable {
    public func requestCapture() {
        core.requestCapture()
    }

    public func takeCaptureHash() throws -> String {
        try core.takeCaptureHash()
    }

    public func takeCapturePayload() throws -> GoldenImageCapture {
        try core.takeCapturePayload()
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
