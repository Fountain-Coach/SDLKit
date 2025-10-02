#if canImport(Metal) && canImport(QuartzCore)
import Foundation
import Metal
import QuartzCore
#if canImport(AppKit)
import AppKit
#endif

@MainActor
public final class MetalRenderBackend: RenderBackend, GoldenImageCapturable {
    private struct BufferResource {
        let buffer: MTLBuffer
        let length: Int
    }

    private enum TextureAccessState {
        case unknown
        case shaderRead
        case shaderWrite
        case renderTarget
    }

    private struct PipelineResource {
        let state: MTLRenderPipelineState
        let descriptor: GraphicsPipelineDescriptor
        let vertexStride: Int
        let colorPixelFormats: [MTLPixelFormat]
        let depthPixelFormat: MTLPixelFormat?
        let vertexBindings: [BindingSlot]
        let fragmentBindings: [BindingSlot]
        let pushConstantSize: Int
    }

    private struct ComputePipelineResource {
        let state: MTLComputePipelineState
        let module: ComputeShaderModule
    }

    private struct MeshResource {
        let vertexBuffer: BufferHandle
        let vertexCount: Int
        let indexBuffer: BufferHandle?
        let indexCount: Int
        let indexFormat: IndexFormat
    }

    private struct SamplerResource {
        let descriptor: SamplerDescriptor
        let state: MTLSamplerState
    }

    private struct TextureResource {
        var texture: MTLTexture
        var usage: TextureUsage
        var access: TextureAccessState
    }

    private let window: SDLWindow
    private let surface: RenderSurface
    private let layer: CAMetalLayer
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    private var buffers: [BufferHandle: BufferResource] = [:]
    private var textures: [TextureHandle: TextureResource] = [:]
    private var samplers: [SamplerHandle: SamplerResource] = [:]
    private var pipelines: [PipelineHandle: PipelineResource] = [:]
    private var computePipelines: [ComputePipelineHandle: ComputePipelineResource] = [:]
    private var meshes: [MeshHandle: MeshResource] = [:]

    private var currentDrawable: CAMetalDrawable?
    private var currentCommandBuffer: MTLCommandBuffer?
    private var currentRenderEncoder: MTLRenderCommandEncoder?
    private var currentRenderPassDescriptor: MTLRenderPassDescriptor?
    private var depthTexture: MTLTexture?
    private var lastSubmittedCommandBuffer: MTLCommandBuffer?
    private var captureRequested: Bool = false
    private var lastCaptureHash: String?
    private var lastCaptureData: Data?
    private var lastCaptureBytesPerRow: Int = 0
    private var lastCaptureSize: (width: Int, height: Int) = (0, 0)

    private let shaderLibrary: ShaderLibrary
    public var deviceEventHandler: RenderBackendDeviceEventHandler?
    private var metalLibraries: [ShaderID: MTLLibrary] = [:]
    private var drawableSize: CGSize
    private var depthPixelFormat: MTLPixelFormat?

    private let triangleBufferHandle: BufferHandle
    private let triangleVertexCount: Int

    private var layerScale: CGFloat

    public required init(window: SDLWindow) throws {
        self.window = window
        self.surface = try RenderSurface(window: window)

        guard let layer = surface.metalLayer else {
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
        lastCaptureData = nil
        lastCaptureBytesPerRow = 0
        lastCaptureSize = (0, 0)

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

        if captureRequested {
            let width = drawable.texture.width
            let height = drawable.texture.height
            let bpp = 4
            let bytesPerRow = width * bpp
            let length = bytesPerRow * height
            var data = Data(count: length)
            data.withUnsafeMutableBytes { buf in
                if let base = buf.baseAddress {
                    let region = MTLRegionMake2D(0, 0, width, height)
                    drawable.texture.getBytes(base, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
                }
            }
            lastCaptureHash = MetalRenderBackend.hashHex(data: data)
            lastCaptureData = data
            lastCaptureBytesPerRow = bytesPerRow
            lastCaptureSize = (width, height)
            captureRequested = false
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
        let usage = convertTextureUsage(descriptor.usage)
        textureDescriptor.usage = usage
        textureDescriptor.storageMode = .private
        textureDescriptor.mipmapLevelCount = descriptor.mipLevels

        if usage.contains(.shaderWrite) {
            guard device.readWriteTextureSupport != .tierNone else {
                throw AgentError.invalidArgument("Metal device does not support read/write textures")
            }
        }

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw AgentError.internalError("Failed to create Metal texture")
        }

        if let initialData, !initialData.mipLevelData.isEmpty {
            if textureDescriptor.storageMode == .private {
                try uploadInitialTextureData(initialData,
                                             to: texture,
                                             pixelFormat: pixelFormat,
                                             width: descriptor.width,
                                             height: descriptor.height)
            } else {
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
        }

        let handle = TextureHandle()
        textures[handle] = TextureResource(texture: texture, usage: descriptor.usage, access: .unknown)
        SDLLogger.debug("SDLKit.Graphics.Metal", "createTexture id=\(handle.rawValue) size=\(descriptor.width)x\(descriptor.height) format=\(descriptor.format.rawValue)")
        return handle
    }

    public func createSampler(descriptor: SamplerDescriptor) throws -> SamplerHandle {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.label = descriptor.label
        samplerDescriptor.minFilter = convertFilter(descriptor.minFilter)
        samplerDescriptor.magFilter = convertFilter(descriptor.magFilter)
        samplerDescriptor.mipFilter = convertMipFilter(descriptor.mipFilter)
        samplerDescriptor.maxAnisotropy = descriptor.maxAnisotropy
        samplerDescriptor.lodMinClamp = descriptor.lodMinClamp
        samplerDescriptor.lodMaxClamp = descriptor.lodMaxClamp
        samplerDescriptor.sAddressMode = convertAddressMode(descriptor.addressModeU)
        samplerDescriptor.tAddressMode = convertAddressMode(descriptor.addressModeV)
        samplerDescriptor.rAddressMode = convertAddressMode(descriptor.addressModeW)

        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw AgentError.internalError("Failed to create Metal sampler state")
        }

        let handle = SamplerHandle()
        let resource = SamplerResource(descriptor: descriptor, state: sampler)
        samplers[handle] = resource
        SDLLogger.debug("SDLKit.Graphics.Metal", "createSampler id=\(handle.rawValue) label=\(descriptor.label ?? "<nil>")")
        return handle
    }

    public func destroy(_ handle: ResourceHandle) {
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
    }

    public func registerMesh(vertexBuffer: BufferHandle,
                             vertexCount: Int,
                             indexBuffer: BufferHandle?,
                             indexCount: Int,
                             indexFormat: IndexFormat) throws -> MeshHandle {
        guard buffers[vertexBuffer] != nil else {
            throw AgentError.internalError("Unknown vertex buffer during mesh registration")
        }
        if let indexBuffer {
            guard buffers[indexBuffer] != nil else {
                throw AgentError.internalError("Unknown index buffer during mesh registration")
            }
        }

        if let existing = meshes.first(where: { (_, resource) in
            resource.vertexBuffer == vertexBuffer &&
            resource.vertexCount == vertexCount &&
            resource.indexBuffer == indexBuffer &&
            resource.indexCount == indexCount &&
            resource.indexFormat == indexFormat
        })?.key {
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
        // Use modern rasterSampleCount to avoid deprecation warnings
        pipelineDescriptor.rasterSampleCount = desc.sampleCount

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
            depthPixelFormat: depthAttachmentPixelFormat,
            vertexBindings: module.bindings[.vertex] ?? [],
            fragmentBindings: module.bindings[.fragment] ?? [],
            pushConstantSize: module.pushConstantSize
        )
        pipelines[handle] = resource
        SDLLogger.debug("SDLKit.Graphics.Metal", "makePipeline id=\(handle.rawValue) label=\(pipelineDescriptor.label ?? "<nil>")")
        return handle
    }

    public func draw(mesh: MeshHandle,
                     pipeline: PipelineHandle,
                     bindings: BindingSet,
                     transform: float4x4) throws {
        guard let pipelineResource = pipelines[pipeline] else {
            throw AgentError.internalError("Unknown pipeline handle")
        }
        guard let commandBuffer = currentCommandBuffer else {
            throw AgentError.internalError("draw called outside of beginFrame/endFrame")
        }

        guard let meshResource = meshes[mesh] else {
            throw AgentError.internalError("Unknown mesh handle for draw")
        }
        guard let vertexResource = buffers[meshResource.vertexBuffer] else {
            throw AgentError.internalError("Vertex buffer handle not found for mesh")
        }

        let encoder = try obtainRenderEncoder(for: pipelineResource, commandBuffer: commandBuffer)
        encoder.setRenderPipelineState(pipelineResource.state)
        let expectedUniformLength = pipelineResource.pushConstantSize
        if expectedUniformLength > 0 {
            guard let payload = bindings.materialConstants else {
                let message = "Shader \(pipelineResource.descriptor.shader.rawValue) expects \(expectedUniformLength) bytes of material constants but none were provided."
                SDLLogger.error("SDLKit.Graphics.Metal", message)
                throw AgentError.invalidArgument(message)
            }
            let byteCount = payload.byteCount
            guard byteCount == expectedUniformLength else {
                let message = "Shader \(pipelineResource.descriptor.shader.rawValue) expects \(expectedUniformLength) bytes of material constants but received \(byteCount)."
                SDLLogger.error("SDLKit.Graphics.Metal", message)
                throw AgentError.invalidArgument(message)
            }
            payload.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setVertexBytes(base, length: bytes.count, index: 1)
                encoder.setFragmentBytes(base, length: bytes.count, index: 1)
            }
        } else if let payload = bindings.materialConstants, payload.byteCount > 0 {
            SDLLogger.warn(
                "SDLKit.Graphics.Metal",
                "Material constants (\(payload.byteCount) bytes) provided for shader \(pipelineResource.descriptor.shader.rawValue) which does not declare push constants. Data will be ignored."
            )
        }
        encoder.setVertexBuffer(vertexResource.buffer, offset: 0, index: 0)

        try bindResources(
            pipelineResource.vertexBindings,
            stage: .vertex,
            shader: pipelineResource.descriptor.shader,
            encoder: encoder,
            bindings: bindings
        )
        try bindResources(
            pipelineResource.fragmentBindings,
            stage: .fragment,
            shader: pipelineResource.descriptor.shader,
            encoder: encoder,
            bindings: bindings
        )

        let vertexCount = meshResource.vertexCount > 0
            ? meshResource.vertexCount
            : max(1, vertexResource.length / max(1, pipelineResource.vertexStride))

        if let indexHandle = meshResource.indexBuffer,
           meshResource.indexCount > 0,
           let indexResource = buffers[indexHandle] {
            let indexType = convertIndexFormat(meshResource.indexFormat)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: meshResource.indexCount,
                indexType: indexType,
                indexBuffer: indexResource.buffer,
                indexBufferOffset: 0
            )
        } else {
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }
    }

    public func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle {
        let module = try shaderLibrary.computeModule(for: desc.shader)
        let library = try loadMetalLibrary(for: module)
        let function = try makeFunction(module.entryPoint, library: library)
        let state: MTLComputePipelineState
        do {
            state = try device.makeComputePipelineState(function: function)
        } catch {
            SDLLogger.error("SDLKit.Graphics.Metal", "Failed to create compute pipeline state: \(error)")
            throw error
        }

        let handle = ComputePipelineHandle()
        computePipelines[handle] = ComputePipelineResource(state: state, module: module)
        SDLLogger.debug("SDLKit.Graphics.Metal", "makeComputePipeline id=\(handle.rawValue) label=\(desc.label ?? module.id.rawValue)")
        return handle
    }

    public func dispatchCompute(_ pipeline: ComputePipelineHandle,
                                 groupsX: Int,
                                 groupsY: Int,
                                 groupsZ: Int,
                                 bindings: BindingSet) throws {
        guard let resource = computePipelines[pipeline] else {
            throw AgentError.internalError("Unknown compute pipeline handle")
        }
        if let encoder = currentRenderEncoder {
            throw AgentError.invalidArgument("Cannot dispatch compute while a render pass is active (encoder=\(encoder))")
        }

        let commandBuffer: MTLCommandBuffer
        let ownsCommandBuffer: Bool
        if let active = currentCommandBuffer {
            commandBuffer = active
            ownsCommandBuffer = false
        } else {
            guard let buffer = commandQueue.makeCommandBuffer() else {
                throw AgentError.internalError("Unable to allocate Metal command buffer for compute dispatch")
            }
            buffer.label = "SDLKit.Compute"
            commandBuffer = buffer
            ownsCommandBuffer = true
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AgentError.internalError("Failed to create Metal compute command encoder")
        }
        encoder.label = "SDLKit.ComputeDispatch"
        encoder.setComputePipelineState(resource.state)

        var textureTracker = MetalComputeTextureAccessTracker()
        var updatedTextureResources: [(TextureHandle, TextureResource)] = []

        for slot in resource.module.bindings {
            switch slot.kind {
            case .uniformBuffer, .storageBuffer:
                guard let entry = bindings.resource(at: slot.index) else {
                    encoder.endEncoding()
                    throw AgentError.invalidArgument("Missing buffer binding for compute slot \(slot.index)")
                }
                switch entry {
                case .buffer(let handle):
                    guard let bufferResource = buffers[handle] else {
                        encoder.endEncoding()
                        throw AgentError.invalidArgument("Unknown buffer handle for compute slot \(slot.index)")
                    }
                    encoder.setBuffer(bufferResource.buffer, offset: 0, index: slot.index)
                case .texture:
                    encoder.endEncoding()
                    throw AgentError.invalidArgument("Texture bound to buffer slot \(slot.index) in compute dispatch")
                }
            case .sampledTexture, .storageTexture:
                guard let entry = bindings.resource(at: slot.index) else {
                    encoder.endEncoding()
                    throw AgentError.invalidArgument("Missing texture binding for compute slot \(slot.index)")
                }
                switch entry {
                case .texture(let handle):
                    guard var texture = textures[handle] else {
                        encoder.endEncoding()
                        throw AgentError.invalidArgument("Unknown texture handle for compute slot \(slot.index)")
                    }
                    let requirement: MetalComputeTextureAccessTracker.Requirement = (slot.kind == .storageTexture) ? .writable : .readable
                    if let reason = textureTracker.register(handle: handle, requirement: requirement, usage: texture.usage) {
                        let message = "Cannot encode compute access for texture \(handle.rawValue): \(reason)"
                        SDLLogger.error("SDLKit.Graphics.Metal", message)
                        encoder.endEncoding()
                        throw AgentError.invalidArgument(message)
                    }
                    encoder.setTexture(texture.texture, index: slot.index)
                    switch requirement {
                    case .readable:
                        texture.access = .shaderRead
                    case .writable:
                        texture.access = .shaderWrite
                    }
                    updatedTextureResources.append((handle, texture))
                case .buffer:
                    encoder.endEncoding()
                    throw AgentError.invalidArgument("Buffer bound to texture slot \(slot.index) in compute dispatch")
                }
            case .sampler:
                encoder.setSamplerState(nil, index: slot.index)
                guard let samplerHandle = bindings.sampler(at: slot.index) else {
                    let error = samplerError(
                        shader: resource.module.id,
                        stage: .compute,
                        slot: slot.index,
                        reason: "is missing a sampler"
                    )
                    encoder.endEncoding()
                    throw error
                }
                guard let samplerResource = samplers[samplerHandle] else {
                    let error = samplerError(
                        shader: resource.module.id,
                        stage: .compute,
                        slot: slot.index,
                        reason: "references unknown sampler handle \(samplerHandle.rawValue)"
                    )
                    encoder.endEncoding()
                    throw error
                }
                encoder.setSamplerState(samplerResource.state, index: slot.index)
            }
        }

        for (handle, texture) in updatedTextureResources {
            textures[handle] = texture
        }

        let barrierHandles = textureTracker.handlesNeedingBarrier
        var barrierTextures: [MTLTexture] = []
        barrierTextures.reserveCapacity(barrierHandles.count)
        for handle in barrierHandles {
            if let texture = textures[handle]?.texture {
                barrierTextures.append(texture)
            }
        }

        let expectedPushConstantSize = resource.module.pushConstantSize
        if expectedPushConstantSize > 0 {
            guard let payload = bindings.materialConstants else {
                let message = "Compute shader \(resource.module.id.rawValue) expects \(expectedPushConstantSize) bytes of push constants but none were provided."
                SDLLogger.error("SDLKit.Graphics.Metal", message)
                encoder.endEncoding()
                throw AgentError.invalidArgument(message)
            }
            let byteCount = payload.byteCount
            guard byteCount == expectedPushConstantSize else {
                let message = "Compute shader \(resource.module.id.rawValue) expects \(expectedPushConstantSize) bytes of push constants but received \(byteCount)."
                SDLLogger.error("SDLKit.Graphics.Metal", message)
                encoder.endEncoding()
                throw AgentError.invalidArgument(message)
            }
            payload.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setBytes(base, length: bytes.count, index: 0)
            }
        } else if let payload = bindings.materialConstants, payload.byteCount > 0 {
            SDLLogger.warn(
                "SDLKit.Graphics.Metal",
                "Compute shader \(resource.module.id.rawValue) ignores provided material constants of size \(payload.byteCount) bytes."
            )
        }

        let threadgroupSize = resource.module.threadgroupSize
        let tgWidth = max(1, threadgroupSize.0 > 0 ? threadgroupSize.0 : resource.state.threadExecutionWidth)
        let tgHeight = max(1, threadgroupSize.1)
        let tgDepth = max(1, threadgroupSize.2)
        let threadsPerThreadgroup = MTLSize(width: tgWidth, height: tgHeight, depth: tgDepth)
        let threadgroups = MTLSize(width: max(1, groupsX), height: max(1, groupsY), depth: max(1, groupsZ))
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        let usedResourceBarriers = encodeTextureBarriers(within: encoder, textures: barrierTextures)
        encoder.memoryBarrier(scope: .buffers)
        encoder.endEncoding()

        if !usedResourceBarriers, !barrierTextures.isEmpty {
            if !encodeBlitTextureBarriers(on: commandBuffer, textures: barrierTextures) {
                let handles = barrierHandles.map { String($0.rawValue) }.sorted().joined(separator: ", ")
                let message = "Unable to encode texture synchronization barrier for compute-dispatched textures [\(handles)]."
                SDLLogger.error("SDLKit.Graphics.Metal", message)
            }
        }

        if ownsCommandBuffer {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }

    // MARK: - Helpers

    private func encodeTextureBarriers(within encoder: MTLComputeCommandEncoder,
                                      textures: [MTLTexture]) -> Bool {
        guard !textures.isEmpty else { return true }
        if #available(macOS 10.14, iOS 12.0, tvOS 12.0, *) {
            encoder.memoryBarrier(resources: textures)
            return true
        } else {
            encoder.memoryBarrier(scope: [.textures])
            return false
        }
    }

    private func encodeBlitTextureBarriers(on commandBuffer: MTLCommandBuffer,
                                           textures: [MTLTexture]) -> Bool {
        // MTLBlitCommandEncoder does not support memoryBarrier APIs. Rely on
        // command-encoder boundaries and implicit hazard tracking. We still
        // create a no-op blit encoder to ensure any pending blits are ordered.
        guard !textures.isEmpty else { return true }
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return false }
        blitEncoder.label = "SDLKit.TextureBarrierBlitNoOp"
        blitEncoder.endEncoding()
        return true
    }

    private func bindResources(_ slots: [BindingSlot],
                               stage: ShaderStage,
                               shader: ShaderID,
                               encoder: MTLRenderCommandEncoder,
                               bindings: BindingSet) throws {
        guard !slots.isEmpty else { return }
        for slot in slots {
            switch slot.kind {
            case .uniformBuffer:
                guard let entry = bindings.resource(at: slot.index) else { continue }
                switch entry {
                case .buffer(let handle):
                    guard let bufferResource = buffers[handle] else {
                        throw AgentError.invalidArgument("Missing buffer resource for slot \(slot.index)")
                    }
                    let index = metalBufferIndex(for: slot)
                    switch stage {
                    case .vertex:
                        encoder.setVertexBuffer(bufferResource.buffer, offset: 0, index: index)
                    case .fragment:
                        encoder.setFragmentBuffer(bufferResource.buffer, offset: 0, index: index)
                    default:
                        continue
                    }
                case .texture:
                    throw AgentError.invalidArgument("Texture bound to buffer slot \(slot.index) in draw call")
                }
            case .storageBuffer:
                guard let entry = bindings.resource(at: slot.index) else {
                    throw AgentError.invalidArgument("Missing buffer binding for slot \(slot.index)")
                }
                switch entry {
                case .buffer(let handle):
                    guard let bufferResource = buffers[handle] else {
                        throw AgentError.invalidArgument("Unknown buffer handle for slot \(slot.index)")
                    }
                    let index = metalBufferIndex(for: slot)
                    switch stage {
                    case .vertex:
                        encoder.setVertexBuffer(bufferResource.buffer, offset: 0, index: index)
                    case .fragment:
                        encoder.setFragmentBuffer(bufferResource.buffer, offset: 0, index: index)
                    default:
                        continue
                    }
                case .texture:
                    throw AgentError.invalidArgument("Texture bound to buffer slot \(slot.index) in draw call")
                }
            case .sampledTexture, .storageTexture:
                guard let entry = bindings.resource(at: slot.index) else {
                    throw AgentError.invalidArgument("Missing texture binding for slot \(slot.index)")
                }
                switch entry {
                case .texture(let handle):
                    guard var textureResource = textures[handle] else {
                        throw AgentError.invalidArgument("Unknown texture handle for slot \(slot.index)")
                    }
                    textureResource.access = .shaderRead
                    textures[handle] = textureResource
                    switch stage {
                    case .vertex:
                        encoder.setVertexTexture(textureResource.texture, index: slot.index)
                    case .fragment:
                        encoder.setFragmentTexture(textureResource.texture, index: slot.index)
                    default:
                        continue
                    }
                case .buffer:
                    throw AgentError.invalidArgument("Buffer bound to texture slot \(slot.index) in draw call")
                }
            case .sampler:
                let samplerHandle = bindings.sampler(at: slot.index)
                switch stage {
                case .vertex:
                    encoder.setVertexSamplerState(nil, index: slot.index)
                case .fragment:
                    encoder.setFragmentSamplerState(nil, index: slot.index)
                default:
                    continue
                }

                guard let samplerHandle else {
                    let error = samplerError(shader: shader, stage: stage, slot: slot.index, reason: "is missing a sampler")
                    throw error
                }

                guard let samplerResource = samplers[samplerHandle] else {
                    let error = samplerError(
                        shader: shader,
                        stage: stage,
                        slot: slot.index,
                        reason: "references unknown sampler handle \(samplerHandle.rawValue)"
                    )
                    throw error
                }

                switch stage {
                case .vertex:
                    encoder.setVertexSamplerState(samplerResource.state, index: slot.index)
                case .fragment:
                    encoder.setFragmentSamplerState(samplerResource.state, index: slot.index)
                default:
                    continue
                }
            }
        }
    }

    private func metalBufferIndex(for slot: BindingSlot) -> Int {
        switch slot.kind {
        case .uniformBuffer, .storageBuffer:
            return slot.index + 1
        default:
            return slot.index
        }
    }

    private func samplerError(shader: ShaderID, stage: ShaderStage, slot: Int, reason: String) -> AgentError {
        let stageName = stageDescription(stage)
        let message = "Shader \(shader.rawValue) \(reason) for \(stageName) sampler slot \(slot)."
        SDLLogger.error("SDLKit.Graphics.Metal", message)
        return AgentError.invalidArgument(message)
    }

    private func stageDescription(_ stage: ShaderStage) -> String {
        switch stage {
        case .vertex:
            return "vertex"
        case .fragment:
            return "fragment"
        case .compute:
            return "compute"
        }
    }

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
                if let depthAttachment = descriptor.depthAttachment {
                    depthAttachment.texture = depthTexture
                    depthAttachment.loadAction = .clear
                    depthAttachment.storeAction = .dontCare
                    depthAttachment.clearDepth = 1.0
                }
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
        if let colorAttachment = descriptor.colorAttachments[0] {
            colorAttachment.texture = drawable.texture
            colorAttachment.loadAction = .clear
            colorAttachment.storeAction = .store
            colorAttachment.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        }
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
        if let layout0 = descriptor.layouts[0] {
            layout0.stride = layout.stride
            layout0.stepFunction = .perVertex
        }
        for attribute in layout.attributes {
            guard let format = convertVertexFormat(attribute.format) else {
                throw AgentError.invalidArgument("Unsupported vertex format: \(attribute.format)")
            }
            if let attr = descriptor.attributes[attribute.index] {
                attr.bufferIndex = 0
                attr.offset = attribute.offset
                attr.format = format
            }
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

    private func loadMetalLibrary(for module: ComputeShaderModule) throws -> MTLLibrary {
        if let cached = metalLibraries[module.id] {
            return cached
        }
        let url = try module.artifacts.requireMetalLibrary(for: module.id)
        SDLLogger.info("SDLKit.Graphics.Metal", "Loading compute metallib for \(module.id.rawValue) from \(url.path)")
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

    private func convertIndexFormat(_ format: IndexFormat) -> MTLIndexType {
        switch format {
        case .uint16:
            return .uint16
        case .uint32:
            return .uint32
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
            return [.renderTarget, .shaderRead]
        case .depthStencil:
            return [.renderTarget]
        }
    }

    private func uploadInitialTextureData(_ data: TextureInitialData,
                                          to texture: MTLTexture,
                                          pixelFormat: MTLPixelFormat,
                                          width: Int,
                                          height: Int) throws {
        let mipCount = max(1, texture.mipmapLevelCount)
        let stagingDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: mipCount > 1
        )
        stagingDescriptor.storageMode = .shared
        stagingDescriptor.usage = [.shaderRead, .shaderWrite]
        stagingDescriptor.mipmapLevelCount = mipCount

        guard let stagingTexture = device.makeTexture(descriptor: stagingDescriptor) else {
            throw AgentError.internalError("Failed to create Metal staging texture")
        }

        for (level, levelData) in data.mipLevelData.enumerated() {
            if level >= mipCount { break }
            let levelWidth = max(1, width >> level)
            let levelHeight = max(1, height >> level)
            let bytesPerPixel = MetalRenderBackend.bytesPerPixel(for: pixelFormat)
            let bytesPerRow = levelWidth * bytesPerPixel
            levelData.withUnsafeBytes { buffer in
                if let base = buffer.baseAddress {
                    let region = MTLRegionMake2D(0, 0, levelWidth, levelHeight)
                    stagingTexture.replace(region: region,
                                           mipmapLevel: level,
                                           withBytes: base,
                                           bytesPerRow: bytesPerRow)
                }
            }
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw AgentError.internalError("Failed to allocate Metal blit command buffer")
        }
        commandBuffer.label = "SDLKit.TextureUpload"

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw AgentError.internalError("Failed to create Metal blit encoder")
        }

        for level in 0..<min(data.mipLevelData.count, mipCount) {
            blitEncoder.copy(from: stagingTexture,
                             sourceSlice: 0,
                             sourceLevel: level,
                             to: texture,
                             destinationSlice: 0,
                             destinationLevel: level,
                             sliceCount: 1,
                             levelCount: 1)
        }
        blitEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func convertFilter(_ filter: SamplerMinMagFilter) -> MTLSamplerMinMagFilter {
        switch filter {
        case .nearest:
            return .nearest
        case .linear:
            return .linear
        }
    }

    private func convertMipFilter(_ filter: SamplerMipFilter) -> MTLSamplerMipFilter {
        switch filter {
        case .notMipmapped:
            return .notMipmapped
        case .nearest:
            return .nearest
        case .linear:
            return .linear
        }
    }

    private func convertAddressMode(_ mode: SamplerAddressMode) -> MTLSamplerAddressMode {
        switch mode {
        case .clampToEdge:
            return .clampToEdge
        case .repeatTexture:
            return .repeat
        case .mirrorRepeat:
            return .mirrorRepeat
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

    // MARK: - GoldenImageCapturable
    public func requestCapture() { captureRequested = true }
    public func takeCaptureHash() throws -> String {
        guard let h = lastCaptureHash else { throw AgentError.internalError("No capture hash available; call requestCapture() before endFrame") }
        return h
    }

    public func takeCapturePayload() throws -> GoldenImageCapture {
        guard let data = lastCaptureData else {
            throw AgentError.internalError("No capture data available; call requestCapture() before endFrame")
        }
        let width = lastCaptureSize.width > 0 ? lastCaptureSize.width : Int(layer.drawableSize.width)
        let height = lastCaptureSize.height > 0 ? lastCaptureSize.height : Int(layer.drawableSize.height)
        let bytesPerRow = lastCaptureBytesPerRow > 0 ? lastCaptureBytesPerRow : max(1, width * 4)
        return GoldenImageCapture(width: width,
                                  height: height,
                                  bytesPerRow: bytesPerRow,
                                  layout: .bgra8Unorm,
                                  data: data)
    }

    private static func hashHex(data: Data) -> String {
        // FNV-1a 64-bit
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for byte in buf {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }
        return String(format: "%016llx", hash)
    }
}

struct MetalComputeTextureAccessTracker {
    enum Requirement {
        case readable
        case writable

        var description: String {
            switch self {
            case .readable:
                return "shaderRead"
            case .writable:
                return "shaderWrite"
            }
        }
    }

    private var readable: Set<TextureHandle> = []
    private var writable: Set<TextureHandle> = []
    private var failures: [TextureHandle: String] = [:]

    mutating func register(handle: TextureHandle,
                           requirement: Requirement,
                           usage: TextureUsage) -> String? {
        switch requirement {
        case .readable:
            guard MetalComputeTextureAccessTracker.supportsRead(usage: usage) else {
                let reason = "requires shaderRead capability but texture was created with usage \(usage)"
                failures[handle] = reason
                return reason
            }
            readable.insert(handle)
            return nil
        case .writable:
            guard usage == .shaderWrite else {
                let reason = "requires shaderWrite capability but texture was created with usage \(usage)"
                failures[handle] = reason
                return reason
            }
            writable.insert(handle)
            return nil
        }
    }

    var handlesNeedingBarrier: Set<TextureHandle> { readable.union(writable) }

    func failureMessage(for handle: TextureHandle) -> String? { failures[handle] }

    private static func supportsRead(usage: TextureUsage) -> Bool {
        switch usage {
        case .shaderRead, .shaderWrite, .renderTarget:
            return true
        case .depthStencil:
            return false
        }
    }
}
#endif
