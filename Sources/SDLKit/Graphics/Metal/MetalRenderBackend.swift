#if canImport(Metal) && canImport(QuartzCore)
import Foundation
import Metal
import QuartzCore
#if canImport(AppKit)
import AppKit
#endif

@MainActor
public final class MetalRenderBackend: RenderBackend {
    private struct BufferResource {
        let buffer: MTLBuffer
        let length: Int
    }

    private struct PipelineResource {
        let state: MTLRenderPipelineState
        let descriptor: GraphicsPipelineDescriptor
        let vertexStride: Int
        let colorPixelFormats: [MTLPixelFormat]
        let depthPixelFormat: MTLPixelFormat?
    }

    private let window: SDLWindow
    private let surface: RenderSurface
    private let layer: CAMetalLayer
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    private var buffers: [BufferHandle: BufferResource] = [:]
    private var textures: [TextureHandle: MTLTexture] = [:]
    private var pipelines: [PipelineHandle: PipelineResource] = [:]

    private var currentDrawable: CAMetalDrawable?
    private var currentCommandBuffer: MTLCommandBuffer?
    private var currentRenderEncoder: MTLRenderCommandEncoder?
    private var currentRenderPassDescriptor: MTLRenderPassDescriptor?
    private var depthTexture: MTLTexture?
    private var lastSubmittedCommandBuffer: MTLCommandBuffer?

    private let shaderLibrary: ShaderLibrary
    private var metalLibraries: [ShaderID: MTLLibrary] = [:]
    private var drawableSize: CGSize
    private var depthPixelFormat: MTLPixelFormat?

    private let triangleBufferHandle: BufferHandle
    private let triangleVertexCount: Int

    private var layerScale: CGFloat

    public required init(window: SDLWindow) throws {
        self.window = window
        self.surface = try RenderSurface(window: window)

        guard let layer = surface.metalLayer as? CAMetalLayer else {
            throw AgentError.internalError("SDL window does not expose a CAMetalLayer")
        }

        guard let device = layer.device ?? MTLCreateSystemDefaultDevice() else {
            throw AgentError.internalError("Unable to create Metal device")
        }

        self.layer = layer
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw AgentError.internalError("Unable to create Metal command queue")
        }
        self.commandQueue = queue

        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        if #available(macOS 10.13, iOS 11.0, tvOS 11.0, *) {
            layer.maximumDrawableCount = 3
        }

        #if canImport(AppKit)
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        #else
        let scale: CGFloat = 1.0
        #endif
        self.layerScale = scale
        layer.contentsScale = scale

        let initialSize = CGSize(width: max(1, window.config.width), height: max(1, window.config.height))
        self.drawableSize = initialSize
        layer.drawableSize = CGSize(width: initialSize.width * scale, height: initialSize.height * scale)

        self.shaderLibrary = ShaderLibrary.shared

        guard let triangle = MetalRenderBackend.makeTriangleVertexBuffer(device: device) else {
            throw AgentError.internalError("Failed to allocate builtin Metal triangle buffer")
        }
        self.triangleBufferHandle = triangle.handle
        self.triangleVertexCount = triangle.count
        self.buffers[triangle.handle] = BufferResource(buffer: triangle.buffer, length: triangle.buffer.length)

        SDLLogger.info(
            "SDLKit.Graphics.Metal",
            "Initialized Metal backend on device=\(device.name) drawableSize=\(Int(initialSize.width))x\(Int(initialSize.height))"
        )
    }

    // MARK: - RenderBackend

    public func beginFrame() throws {
        guard currentCommandBuffer == nil else {
            throw AgentError.internalError("beginFrame called while a frame is already active")
        }

        inflightSemaphore.wait()

        guard let drawable = layer.nextDrawable() else {
            inflightSemaphore.signal()
            throw AgentError.internalError("Failed to acquire CAMetalDrawable")
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            throw AgentError.internalError("Unable to allocate command buffer")
        }
        commandBuffer.label = "SDLKit.Frame"
        commandBuffer.addCompletedHandler { [weak self] buffer in
            if let error = buffer.error {
                SDLLogger.error("SDLKit.Graphics.Metal", "Metal command buffer error: \(error)")
            }
            self?.inflightSemaphore.signal()
        }

        self.currentDrawable = drawable
        self.currentCommandBuffer = commandBuffer
        self.currentRenderPassDescriptor = makeRenderPassDescriptor(for: drawable)
        self.currentRenderEncoder = nil
    }

    public func endFrame() throws {
        guard let commandBuffer = currentCommandBuffer, let drawable = currentDrawable else {
            throw AgentError.internalError("endFrame called without active frame")
        }

        if let encoder = currentRenderEncoder {
            encoder.endEncoding()
            currentRenderEncoder = nil
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
        lastSubmittedCommandBuffer = commandBuffer

        currentCommandBuffer = nil
        currentDrawable = nil
        currentRenderPassDescriptor = nil
    }

    public func resize(width: Int, height: Int) throws {
        let clampedWidth = max(1, width)
        let clampedHeight = max(1, height)
        layerScale = layer.contentsScale
        drawableSize = CGSize(width: clampedWidth, height: clampedHeight)
        layer.drawableSize = CGSize(width: CGFloat(clampedWidth) * layerScale, height: CGFloat(clampedHeight) * layerScale)
        depthTexture = nil
        SDLLogger.info("SDLKit.Graphics.Metal", "Resized CAMetalLayer to \(clampedWidth)x\(clampedHeight)")
    }

    public func waitGPU() throws {
        if let buffer = lastSubmittedCommandBuffer {
            buffer.waitUntilCompleted()
        }
    }

    public func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle {
        guard length > 0 else {
            throw AgentError.invalidArgument("Buffer length must be greater than zero")
        }

        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw AgentError.internalError("Failed to allocate MTLBuffer")
        }
        if let bytes {
            memcpy(buffer.contents(), bytes, length)
        }
        buffer.label = "SDLKit.Buffer.\(usage)"

        let handle = BufferHandle()
        buffers[handle] = BufferResource(buffer: buffer, length: length)
        SDLLogger.debug("SDLKit.Graphics.Metal", "createBuffer id=\(handle.rawValue) length=\(length) usage=\(usage)")
        return handle
    }

    public func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle {
        let pixelFormat = try convertTextureFormat(descriptor.format)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: descriptor.width,
            height: descriptor.height,
            mipmapped: descriptor.mipLevels > 1
        )
        textureDescriptor.usage = convertTextureUsage(descriptor.usage)
        textureDescriptor.storageMode = .shared
        textureDescriptor.mipmapLevelCount = descriptor.mipLevels

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw AgentError.internalError("Failed to create Metal texture")
        }

        if let initialData, !initialData.mipLevelData.isEmpty {
            for (level, data) in initialData.mipLevelData.enumerated() {
                let levelWidth = max(1, descriptor.width >> level)
                let levelHeight = max(1, descriptor.height >> level)
                let bytesPerPixel = MetalRenderBackend.bytesPerPixel(for: pixelFormat)
                let bytesPerRow = levelWidth * bytesPerPixel
                data.withUnsafeBytes { buffer in
                    if let base = buffer.baseAddress {
                        let region = MTLRegionMake2D(0, 0, levelWidth, levelHeight)
                        texture.replace(region: region, mipmapLevel: level, withBytes: base, bytesPerRow: bytesPerRow)
                    }
                }
            }
        }

        let handle = TextureHandle()
        textures[handle] = texture
        SDLLogger.debug("SDLKit.Graphics.Metal", "createTexture id=\(handle.rawValue) size=\(descriptor.width)x\(descriptor.height) format=\(descriptor.format.rawValue)")
        return handle
    }

    public func destroy(_ handle: ResourceHandle) {
        switch handle {
        case .buffer(let h):
            buffers.removeValue(forKey: h)
        case .texture(let h):
            textures.removeValue(forKey: h)
        case .pipeline(let h):
            pipelines.removeValue(forKey: h)
        case .computePipeline, .mesh:
            break
        }
    }

    public func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle {
        let module = try shaderLibrary.module(for: desc.shader)
        try module.validateVertexLayout(desc.vertexLayout)

        let vertexDescriptor = try makeVertexDescriptor(from: module.vertexLayout)
        let library = try loadMetalLibrary(for: module)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = desc.label ?? module.id.rawValue
        pipelineDescriptor.vertexFunction = try makeFunction(module.vertexEntryPoint, library: library)
        if let fragment = module.fragmentEntryPoint {
            pipelineDescriptor.fragmentFunction = try makeFunction(fragment, library: library)
        }
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.sampleCount = desc.sampleCount

        if desc.colorFormats.isEmpty {
            throw AgentError.invalidArgument("Pipeline requires at least one color attachment")
        }

        var colorPixelFormats: [MTLPixelFormat] = []
        for (index, format) in desc.colorFormats.enumerated() {
            let pixelFormat = try convertTextureFormat(format)
            pipelineDescriptor.colorAttachments[index].pixelFormat = pixelFormat
            colorPixelFormats.append(pixelFormat)
        }

        if let first = colorPixelFormats.first, first != layer.pixelFormat {
            SDLLogger.warn(
                "SDLKit.Graphics.Metal",
                "Pipeline color format (\(first)) differs from CAMetalLayer format (\(layer.pixelFormat)); overriding to match layer"
            )
            pipelineDescriptor.colorAttachments[0].pixelFormat = layer.pixelFormat
            colorPixelFormats[0] = layer.pixelFormat
        }

        var depthAttachmentPixelFormat: MTLPixelFormat?

        if let depthFormat = desc.depthFormat {
            let pixelFormat = try convertDepthFormat(depthFormat)
            pipelineDescriptor.depthAttachmentPixelFormat = pixelFormat
            depthAttachmentPixelFormat = pixelFormat
            depthPixelFormat = pixelFormat
            depthTexture = nil
        }

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            SDLLogger.error("SDLKit.Graphics.Metal", "Failed to create pipeline state: \(error)")
            throw error
        }

        let handle = PipelineHandle()
        let resource = PipelineResource(
            state: pipelineState,
            descriptor: desc,
            vertexStride: max(1, module.vertexLayout.stride),
            colorPixelFormats: colorPixelFormats,
            depthPixelFormat: depthAttachmentPixelFormat
        )
        pipelines[handle] = resource
        SDLLogger.debug("SDLKit.Graphics.Metal", "makePipeline id=\(handle.rawValue) label=\(pipelineDescriptor.label ?? "<nil>")")
        return handle
    }

    public func draw(mesh: MeshHandle,
                     pipeline: PipelineHandle,
                     bindings: BindingSet,
                     pushConstants: UnsafeRawPointer?,
                     transform: float4x4) throws {
        _ = mesh
        _ = pushConstants

        guard let pipelineResource = pipelines[pipeline] else {
            throw AgentError.internalError("Unknown pipeline handle")
        }
        guard let commandBuffer = currentCommandBuffer else {
            throw AgentError.internalError("draw called outside of beginFrame/endFrame")
        }

        let vertexHandle = bindings.value(for: 0, as: BufferHandle.self) ?? triangleBufferHandle
        guard let vertexResource = buffers[vertexHandle] else {
            throw AgentError.internalError("Vertex buffer handle not found")
        }

        let encoder = try obtainRenderEncoder(for: pipelineResource, commandBuffer: commandBuffer)
        encoder.setRenderPipelineState(pipelineResource.state)
        // Push transform as vertex bytes at buffer index 1 (matches MSL [[buffer(1)]])
        var matrix = transform.toFloatArray()
        matrix.withUnsafeBytes { bytes in
            encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 1)
        }
        encoder.setVertexBuffer(vertexResource.buffer, offset: 0, index: 0)

        let vertexCount: Int
        if vertexHandle == triangleBufferHandle {
            vertexCount = triangleVertexCount
        } else {
            vertexCount = max(1, vertexResource.length / max(1, pipelineResource.vertexStride))
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }

    public func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle {
        SDLLogger.warn("SDLKit.Graphics.Metal", "Compute pipelines are not yet implemented")
        throw AgentError.notImplemented
    }

    public func dispatchCompute(_ pipeline: ComputePipelineHandle,
                                 groupsX: Int,
                                 groupsY: Int,
                                 groupsZ: Int,
                                 bindings: BindingSet,
                                 pushConstants: UnsafeRawPointer?) throws {
        _ = pipeline
        _ = groupsX
        _ = groupsY
        _ = groupsZ
        _ = bindings
        _ = pushConstants
        SDLLogger.warn("SDLKit.Graphics.Metal", "dispatchCompute is not implemented")
        throw AgentError.notImplemented
    }

    // MARK: - Helpers

    private func obtainRenderEncoder(for pipeline: PipelineResource, commandBuffer: MTLCommandBuffer) throws -> MTLRenderCommandEncoder {
        if let encoder = currentRenderEncoder {
            return encoder
        }
        guard let descriptor = currentRenderPassDescriptor else {
            throw AgentError.internalError("Render pass descriptor missing for frame")
        }

        if depthPixelFormat != nil {
            let width = currentDrawable?.texture.width ?? Int(drawableSize.width * layerScale)
            let height = currentDrawable?.texture.height ?? Int(drawableSize.height * layerScale)
            ensureDepthTexture(width: width, height: height)
            if let depthTexture {
                let depthAttachment = descriptor.depthAttachment
                depthAttachment.texture = depthTexture
                depthAttachment.loadAction = .clear
                depthAttachment.storeAction = .dontCare
                depthAttachment.clearDepth = 1.0
            }
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw AgentError.internalError("Failed to create render command encoder")
        }
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(drawableSize.width),
            height: Double(drawableSize.height),
            znear: 0.0,
            zfar: 1.0
        ))
        currentRenderEncoder = encoder
        return encoder
    }

    private func makeRenderPassDescriptor(for drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        let colorAttachment = descriptor.colorAttachments[0]
        colorAttachment.texture = drawable.texture
        colorAttachment.loadAction = .clear
        colorAttachment.storeAction = .store
        colorAttachment.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        return descriptor
    }

    private func ensureDepthTexture(width: Int, height: Int) {
        guard let depthPixelFormat else {
            depthTexture = nil
            return
        }
        if let depthTexture, depthTexture.width == width, depthTexture.height == height {
            return
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        depthTexture = device.makeTexture(descriptor: descriptor)
        depthTexture?.label = "SDLKit.Depth"
    }

    private func makeFunction(_ entry: String, library: MTLLibrary) throws -> MTLFunction {
        guard let function = library.makeFunction(name: entry) else {
            throw AgentError.internalError("Shader function \(entry) not found in metallib")
        }
        return function
    }

    private func makeVertexDescriptor(from layout: VertexLayout) throws -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.layouts[0].stride = layout.stride
        descriptor.layouts[0].stepFunction = .perVertex
        for attribute in layout.attributes {
            guard let format = convertVertexFormat(attribute.format) else {
                throw AgentError.invalidArgument("Unsupported vertex format: \(attribute.format)")
            }
            let attr = descriptor.attributes[attribute.index]
            attr.bufferIndex = 0
            attr.offset = attribute.offset
            attr.format = format
        }
        return descriptor
    }

    private func loadMetalLibrary(for module: ShaderModule) throws -> MTLLibrary {
        if let cached = metalLibraries[module.id] {
            return cached
        }
        let url = try module.artifacts.requireMetalLibrary(for: module.id)
        SDLLogger.info("SDLKit.Graphics.Metal", "Loading metallib for \(module.id.rawValue) from \(url.path)")
        let library = try device.makeLibrary(URL: url)
        metalLibraries[module.id] = library
        return library
    }

    private static func makeTriangleVertexBuffer(device: MTLDevice) -> (handle: BufferHandle, buffer: MTLBuffer, count: Int)? {
        struct Vertex {
            var position: (Float, Float, Float)
            var color: (Float, Float, Float)
        }

        let vertices: [Vertex] = [
            Vertex(position: (-0.6, -0.5, 0), color: (1, 0, 0)),
            Vertex(position: (0.0, 0.6, 0), color: (0, 1, 0)),
            Vertex(position: (0.6, -0.5, 0), color: (0, 0, 1))
        ]

        let length = vertices.count * MemoryLayout<Vertex>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: length, options: .storageModeShared) else {
            return nil
        }
        buffer.label = "SDLKit.BuiltinTriangle"
        return (BufferHandle(), buffer, vertices.count)
    }

    private func convertTextureFormat(_ format: TextureFormat) throws -> MTLPixelFormat {
        switch format {
        case .rgba8Unorm:
            return .rgba8Unorm
        case .bgra8Unorm:
            return .bgra8Unorm
        case .depth32Float:
            return .depth32Float
        }
    }

    private func convertDepthFormat(_ format: TextureFormat) throws -> MTLPixelFormat {
        switch format {
        case .depth32Float:
            return .depth32Float
        default:
            throw AgentError.invalidArgument("Unsupported depth format: \(format)")
        }
    }

    private func convertVertexFormat(_ format: VertexFormat) -> MTLVertexFormat? {
        switch format {
        case .float2:
            return .float2
        case .float3:
            return .float3
        case .float4:
            return .float4
        }
    }

    private func convertTextureUsage(_ usage: TextureUsage) -> MTLTextureUsage {
        switch usage {
        case .shaderRead:
            return [.shaderRead]
        case .shaderWrite:
            return [.shaderRead, .shaderWrite]
        case .renderTarget:
            return [.renderTarget]
        case .depthStencil:
            return [.renderTarget]
        }
    }

    private static func bytesPerPixel(for format: MTLPixelFormat) -> Int {
        switch format {
        case .rgba8Unorm, .bgra8Unorm:
            return 4
        case .depth32Float:
            return 4
        default:
            return 4
        }
    }
}
#endif
