// Linux Vulkan backend scaffold: creates a VkInstance with SDL-required extensions
// and an SDL-created VkSurfaceKHR. Other operations are currently delegated to the
// stub core until full Vulkan rendering is implemented.

#if os(Linux) && canImport(VulkanMinimal)
import Foundation
import Glibc
import VulkanMinimal
#if canImport(CVulkan)
import CVulkan
#endif

@MainActor
public final class VulkanRenderBackend: RenderBackend, GoldenImageCapturable {
    private let window: SDLWindow
    private let surface: RenderSurface
    private var core: StubRenderBackendCore

    // Vulkan handles
    private var vkInstance = VulkanMinimalInstance()
    private var vkSurface: VkSurfaceKHR? = nil
    #if canImport(CVulkan)
    // Validation
    private var debugMessenger: VkDebugUtilsMessengerEXT? = nil
    // Device/Queues
    private var physicalDevice: VkPhysicalDevice? = nil
    private var device: VkDevice? = nil
    private var graphicsQueueFamilyIndex: UInt32 = 0
    private var presentQueueFamilyIndex: UInt32 = 0
    private var graphicsQueue: VkQueue? = nil
    private var presentQueue: VkQueue? = nil

    // Swapchain and render targets
    private var swapchain: VkSwapchainKHR? = nil
    private var swapchainImages: [VkImage?] = []
    private var swapchainImageViews: [VkImageView?] = []
    private var renderPass: VkRenderPass? = nil
    private var framebuffers: [VkFramebuffer?] = []
    private var colorFormat: VkFormat = VK_FORMAT_B8G8R8A8_UNORM
    private var colorSpace: VkColorSpaceKHR = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
    private var surfaceExtent = VkExtent2D(width: 1, height: 1)

    // Depth resources
    private var depthFormat: VkFormat = VK_FORMAT_D32_SFLOAT
    private var depthImage: VkImage? = nil
    private var depthMemory: VkDeviceMemory? = nil
    private var depthView: VkImageView? = nil

    // Command and sync
    private var commandPool: VkCommandPool? = nil
    private var commandBuffers: [VkCommandBuffer?] = []
    private var imageAvailableSemaphores: [VkSemaphore?] = []
    private var renderFinishedSemaphores: [VkSemaphore?] = []
    private var inFlightFences: [VkFence?] = []
    private var maxFramesInFlight: Int = 2
    private var currentFrame: Int = 0
    private var frameActive: Bool = false
    private var currentImageIndex: UInt32 = 0

    // Pipeline and geometry
    private struct PipelineResource {
        var handle: PipelineHandle
        var pipelineLayout: VkPipelineLayout?
        var pipeline: VkPipeline?
        var vertexStride: UInt32
    }
    private var pipelines: [PipelineHandle: PipelineResource] = [:]
    private var builtinPipeline: PipelineHandle? = nil

    private struct MeshResource {
        let vertexBuffer: BufferHandle
        let vertexCount: Int
        let indexBuffer: BufferHandle?
        let indexCount: Int
        let indexFormat: IndexFormat
    }
    private var meshes: [MeshHandle: MeshResource] = [:]

    // Builtin vertex buffer (pos.xyz + color.xyz)
    private var builtinVertexBuffer: VkBuffer? = nil
    private var builtinVertexMemory: VkDeviceMemory? = nil
    private var builtinVertexCount: Int = 0

    // Capture state (golden image test)
    private var captureRequested: Bool = false
    private var captureBuffer: VkBuffer? = nil
    private var captureMemory: VkDeviceMemory? = nil
    private var captureBufferSize: VkDeviceSize = 0
    private var lastCaptureHash: String?

    private struct BufferResource {
        var buffer: VkBuffer?
        var memory: VkDeviceMemory?
        var length: Int
        var usage: BufferUsage
    }
    private var buffers: [BufferHandle: BufferResource] = [:]
    #endif

    public required init(window: SDLWindow) throws {
        self.window = window
        self.surface = try RenderSurface(window: window)
        self.core = try StubRenderBackendCore(kind: .vulkan, window: window)

        try initializeVulkan()
        #if canImport(CVulkan)
        try initializeDeviceAndQueues()
        #endif
    }

    deinit {
        // Ensure GPU idle-equivalent and destroy Vulkan objects
        #if canImport(CVulkan)
        if let dev = device {
            _ = vkDeviceWaitIdle(dev)
            destroySwapchainResources()
            // Destroy sync objects
            for s in imageAvailableSemaphores { if let sem = s { vkDestroySemaphore(dev, sem, nil) } }
            for s in renderFinishedSemaphores { if let sem = s { vkDestroySemaphore(dev, sem, nil) } }
            for f in inFlightFences { if let ff = f { vkDestroyFence(dev, ff, nil) } }
            imageAvailableSemaphores.removeAll(); renderFinishedSemaphores.removeAll(); inFlightFences.removeAll()
            // Destroy builtin buffer
            if let vb = builtinVertexBuffer { vkDestroyBuffer(dev, vb, nil) }
            if let vm = builtinVertexMemory { vkFreeMemory(dev, vm, nil) }
            builtinVertexBuffer = nil; builtinVertexMemory = nil
            // Destroy pipelines
            for (_, p) in pipelines {
                if let pl = p.pipeline { vkDestroyPipeline(dev, pl, nil) }
                if let layout = p.pipelineLayout { vkDestroyPipelineLayout(dev, layout, nil) }
            }
            pipelines.removeAll(); builtinPipeline = nil
            // Destroy command pool
            if let pool = commandPool { vkDestroyCommandPool(dev, pool, nil) }
            commandPool = nil
            vkDestroyDevice(dev, nil)
        }
        if let inst = vkInstance.handle {
            if let surf = vkSurface {
                vkDestroySurfaceKHR(inst, surf, nil)
                vkSurface = nil
            }
            if let messenger = debugMessenger {
                destroyDebugMessenger(instance: inst, messenger: messenger)
                debugMessenger = nil
            }
        }
        #endif
        try? waitGPU()
        VulkanMinimalDestroyInstance(&vkInstance)
    }

    // MARK: - RenderBackend
    public func beginFrame() throws {
        #if canImport(CVulkan)
        guard let dev = device, let sc = swapchain, let gq = graphicsQueue else {
            throw AgentError.internalError("Vulkan device/swapchain not initialized")
        }
        try ensureCommandPoolAndSync()

        // Wait for the previous frame to finish
        if var fence = inFlightFences[currentFrame] {
            withUnsafePointer(to: &fence) { fptr in
                _ = vkWaitForFences(dev, 1, fptr, VK_TRUE, UInt64.max)
                _ = vkResetFences(dev, 1, fptr)
            }
        }

        // Acquire next image
        var imgIndex: UInt32 = 0
        let acquireRes = vkAcquireNextImageKHR(dev, sc, UInt64.max, imageAvailableSemaphores[currentFrame], nil, &imgIndex)
        if acquireRes == VK_ERROR_OUT_OF_DATE_KHR {
            try recreateSwapchain(width: surfaceExtent.width, height: surfaceExtent.height)
            return try beginFrame() // retry once
        } else if acquireRes != VK_SUCCESS && acquireRes != VK_SUBOPTIMAL_KHR {
            throw AgentError.internalError("vkAcquireNextImageKHR failed (res=\(acquireRes))")
        }
        currentImageIndex = imgIndex

        // Begin command buffer
        guard let cmd = commandBuffers[currentFrame] else {
            throw AgentError.internalError("Command buffer unavailable for frame")
        }
        var beginInfo = VkCommandBufferBeginInfo()
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        beginInfo.flags = UInt32(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT)
        _ = withUnsafePointer(to: beginInfo) { ptr in vkBeginCommandBuffer(cmd, ptr) }

        // Begin render pass
        guard let rp = renderPass, Int(currentImageIndex) < framebuffers.count, let fb = framebuffers[Int(currentImageIndex)] else {
            throw AgentError.internalError("Render pass or framebuffer not ready")
        }
        var clearColor = VkClearValue(color: VkClearColorValue(float32: (0.05, 0.05, 0.08, 1.0)))
        var clearDepth = VkClearValue(depthStencil: VkClearDepthStencilValue(depth: 1.0, stencil: 0))
        var clears = [clearColor, clearDepth]

        var rpBegin = VkRenderPassBeginInfo()
        rpBegin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        rpBegin.renderPass = rp
        rpBegin.framebuffer = fb
        rpBegin.renderArea = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: surfaceExtent)
        clears.withUnsafeMutableBufferPointer { buf in
            rpBegin.clearValueCount = UInt32(buf.count)
            rpBegin.pClearValues = buf.baseAddress
        }
        withUnsafePointer(to: rpBegin) { ptr in
            vkCmdBeginRenderPass(cmd, ptr, VK_SUBPASS_CONTENTS_INLINE)
        }

        // Set viewport & scissor dynamically
        var viewport = VkViewport(x: 0, y: 0, width: Float(surfaceExtent.width), height: Float(surfaceExtent.height), minDepth: 0.0, maxDepth: 1.0)
        withUnsafePointer(to: &viewport) { vptr in vkCmdSetViewport(cmd, 0, 1, vptr) }
        var scissor = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: surfaceExtent)
        withUnsafePointer(to: &scissor) { sptr in vkCmdSetScissor(cmd, 0, 1, sptr) }

        frameActive = true
        #else
        try core.beginFrame()
        #endif
    }

    public func endFrame() throws {
        #if canImport(CVulkan)
        guard frameActive, let dev = device, let gq = graphicsQueue, let pq = presentQueue else {
            throw AgentError.internalError("endFrame called without active frame")
        }
        guard let cmd = commandBuffers[currentFrame] else { throw AgentError.internalError("Missing command buffer") }
        vkCmdEndRenderPass(cmd)

        // Optional capture: copy swapchain image to host-visible buffer
        if captureRequested, let scImages = swapchainImages[Int(currentImageIndex)], let dev = device {
            let pixelSize: VkDeviceSize = 4
            let bytesNeeded = VkDeviceSize(surfaceExtent.width) * VkDeviceSize(surfaceExtent.height) * pixelSize
            if captureBuffer == nil || captureBufferSize < bytesNeeded {
                if let oldB = captureBuffer { vkDestroyBuffer(dev, oldB, nil); captureBuffer = nil }
                if let oldM = captureMemory { vkFreeMemory(dev, oldM, nil); captureMemory = nil }
                var buf: VkBuffer? = nil
                var mem: VkDeviceMemory? = nil
                try createBuffer(size: bytesNeeded, usage: UInt32(VK_BUFFER_USAGE_TRANSFER_DST_BIT), properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT), bufferOut: &buf, memoryOut: &mem)
                captureBuffer = buf
                captureMemory = mem
                captureBufferSize = bytesNeeded
            }

            // Barrier: PRESENT -> TRANSFER_SRC
            var barrier = VkImageMemoryBarrier()
            barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
            barrier.srcAccessMask = 0
            barrier.dstAccessMask = UInt32(VK_ACCESS_TRANSFER_READ_BIT)
            barrier.oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
            barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
            barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
            barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
            barrier.image = scImages
            barrier.subresourceRange = VkImageSubresourceRange(aspectMask: UInt32(VK_IMAGE_ASPECT_COLOR_BIT), baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1)
            withUnsafePointer(to: &barrier) { bptr in
                vkCmdPipelineBarrier(cmd, UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT), UInt32(VK_PIPELINE_STAGE_TRANSFER_BIT), 0, 0, nil, 0, nil, 1, bptr)
            }

            // Copy to buffer
            var region = VkBufferImageCopy()
            region.bufferOffset = 0
            region.bufferRowLength = 0 // tightly packed
            region.bufferImageHeight = 0
            region.imageSubresource = VkImageSubresourceLayers(aspectMask: UInt32(VK_IMAGE_ASPECT_COLOR_BIT), mipLevel: 0, baseArrayLayer: 0, layerCount: 1)
            region.imageOffset = VkOffset3D(x: 0, y: 0, z: 0)
            region.imageExtent = VkExtent3D(width: surfaceExtent.width, height: surfaceExtent.height, depth: 1)
            withUnsafePointer(to: &region) { rptr in
                vkCmdCopyImageToBuffer(cmd, scImages, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, captureBuffer, 1, rptr)
            }

            // Barrier: TRANSFER_SRC -> PRESENT
            barrier.srcAccessMask = UInt32(VK_ACCESS_TRANSFER_READ_BIT)
            barrier.dstAccessMask = 0
            barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
            barrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
            withUnsafePointer(to: &barrier) { bptr in
                vkCmdPipelineBarrier(cmd, UInt32(VK_PIPELINE_STAGE_TRANSFER_BIT), UInt32(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT), 0, 0, nil, 0, nil, 1, bptr)
            }
        }
        _ = vkEndCommandBuffer(cmd)

        // Submit
        var waitStageMask: VkPipelineStageFlags = UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
        var waitSemaphore = imageAvailableSemaphores[currentFrame]
        var signalSemaphore = renderFinishedSemaphores[currentFrame]
        var cmdLocal = cmd
        var submit = VkSubmitInfo()
        submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        submit.waitSemaphoreCount = 1
        withUnsafePointer(to: &waitSemaphore) { ws in submit.pWaitSemaphores = ws }
        submit.pWaitDstStageMask = &waitStageMask
        submit.commandBufferCount = 1
        withUnsafePointer(to: &cmdLocal) { cp in submit.pCommandBuffers = cp }
        submit.signalSemaphoreCount = 1
        withUnsafePointer(to: &signalSemaphore) { sp in submit.pSignalSemaphores = sp }

        _ = withUnsafePointer(to: submit) { ptr in vkQueueSubmit(gq, 1, ptr, inFlightFences[currentFrame]) }

        // Present
        var pi = VkPresentInfoKHR()
        pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
        pi.waitSemaphoreCount = 1
        withUnsafePointer(to: &signalSemaphore) { sp in pi.pWaitSemaphores = sp }
        pi.swapchainCount = 1
        guard let scNonOpt = swapchain else { throw AgentError.internalError("Swapchain missing") }
        var scLocal = scNonOpt
        withUnsafePointer(to: &scLocal) { scPtr in pi.pSwapchains = scPtr }
        var imageIndexCopy = currentImageIndex
        withUnsafePointer(to: &imageIndexCopy) { idxPtr in pi.pImageIndices = idxPtr }
        let presentRes = withUnsafePointer(to: pi) { ptr in vkQueuePresentKHR(pq, ptr) }
        if presentRes == VK_ERROR_OUT_OF_DATE_KHR || presentRes == VK_SUBOPTIMAL_KHR {
            try recreateSwapchain(width: surfaceExtent.width, height: surfaceExtent.height)
        } else if presentRes != VK_SUCCESS {
            throw AgentError.internalError("vkQueuePresentKHR failed (res=\(presentRes))")
        }

        if captureRequested {
            // Wait for GPU to finish so buffer is ready, then map and hash
            _ = vkQueueWaitIdle(gq)
            if let mem = captureMemory {
                var mapped: UnsafeMutableRawPointer? = nil
                _ = vkMapMemory(dev, mem, 0, captureBufferSize, 0, &mapped)
                if let mapped {
                    let count = Int(captureBufferSize)
                    let data = Data(bytes: mapped, count: count)
                    lastCaptureHash = VulkanRenderBackend.hashHex(data: data)
                }
                vkUnmapMemory(dev, mem)
            }
            captureRequested = false
        }

        currentFrame = (currentFrame + 1) % maxFramesInFlight
        frameActive = false
        #else
        try core.endFrame()
        #endif
    }
    public func resize(width: Int, height: Int) throws {
        core.resize(width: width, height: height)
        #if canImport(CVulkan)
        if device != nil {
            try recreateSwapchain(width: UInt32(max(1, width)), height: UInt32(max(1, height)))
        }
        #endif
    }
    public func waitGPU() throws {
        #if canImport(CVulkan)
        if let dev = device { _ = vkDeviceWaitIdle(dev) }
        #else
        core.waitGPU()
        #endif
    }

    public func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle {
        #if canImport(CVulkan)
        guard length > 0 else { throw AgentError.invalidArgument("Buffer length must be > 0") }
        guard let dev = device else { throw AgentError.internalError("Vulkan device not ready") }

        let size = VkDeviceSize(length)
        let handle = BufferHandle()

        func buildUsageFlags(for usage: BufferUsage) -> UInt32 {
            var flags: UInt32 = 0
            switch usage {
            case .vertex: flags |= UInt32(VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT)
            case .index: flags |= UInt32(VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT)
            case .uniform: flags |= UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT)
            case .storage: flags |= UInt32(VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT)
            case .staging: flags |= UInt32(VK_BUFFER_USAGE_TRANSFER_SRC_BIT)
            }
            return flags
        }

        func memProps(for usage: BufferUsage) -> UInt32 {
            switch usage {
            case .staging:
                return UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
            default:
                return UInt32(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
            }
        }

        var buffer: VkBuffer? = nil
        var memory: VkDeviceMemory? = nil
        let usageFlags = buildUsageFlags(for: usage)
        let desiredProps = memProps(for: usage)
        try createBuffer(size: size, usage: usageFlags, properties: desiredProps, bufferOut: &buffer, memoryOut: &memory)

        if let bytes {
            if (desiredProps & UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) != 0 {
                var mapped: UnsafeMutableRawPointer? = nil
                _ = vkMapMemory(dev, memory, 0, size, 0, &mapped)
                if let mapped { memcpy(mapped, bytes, length); vkUnmapMemory(dev, memory) }
            } else {
                // Create staging and copy
                var stagingBuffer: VkBuffer? = nil
                var stagingMemory: VkDeviceMemory? = nil
                try createBuffer(size: size, usage: UInt32(VK_BUFFER_USAGE_TRANSFER_SRC_BIT), properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT), bufferOut: &stagingBuffer, memoryOut: &stagingMemory)
                var mapped: UnsafeMutableRawPointer? = nil
                _ = vkMapMemory(dev, stagingMemory, 0, size, 0, &mapped)
                if let mapped { memcpy(mapped, bytes, length); vkUnmapMemory(dev, stagingMemory) }
                try copyBuffer(src: stagingBuffer, dst: buffer, size: size)
                if let sb = stagingBuffer { vkDestroyBuffer(dev, sb, nil) }
                if let sm = stagingMemory { vkFreeMemory(dev, sm, nil) }
            }
        }

        let res = BufferResource(buffer: buffer, memory: memory, length: length, usage: usage)
        buffers[handle] = res
        return handle
        #else
        return try core.createBuffer(bytes: bytes, length: length, usage: usage)
        #endif
    }

    // MARK: - GoldenImageCapturable
    public func requestCapture() { captureRequested = true }
    public func takeCaptureHash() throws -> String {
        guard let h = lastCaptureHash else { throw AgentError.internalError("No capture hash available; call requestCapture() before endFrame") }
        return h
    }

    private static func hashHex(data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for byte in buf { hash ^= UInt64(byte); hash = hash &* prime }
        }
        return String(format: "%016llx", hash)
    }
    public func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle {
        core.createTexture(descriptor: descriptor, initialData: initialData)
    }

    public func registerMesh(vertexBuffer: BufferHandle,
                             vertexCount: Int,
                             indexBuffer: BufferHandle?,
                             indexCount: Int,
                             indexFormat: IndexFormat) throws -> MeshHandle {
        #if canImport(CVulkan)
        if let existing = meshes.first(where: { (_, resource) in
            resource.vertexBuffer == vertexBuffer &&
            resource.vertexCount == vertexCount &&
            resource.indexBuffer == indexBuffer &&
            resource.indexCount == indexCount &&
            resource.indexFormat == indexFormat
        })?.key {
            return existing
        }

        guard buffers[vertexBuffer] != nil else {
            throw AgentError.internalError("Unknown vertex buffer during mesh registration")
        }
        if let indexBuffer {
            guard buffers[indexBuffer] != nil else {
                throw AgentError.internalError("Unknown index buffer during mesh registration")
            }
        }

        let handle = core.registerMesh(vertexBuffer: vertexBuffer,
                                        vertexCount: vertexCount,
                                        indexBuffer: indexBuffer,
                                        indexCount: indexCount,
                                        indexFormat: indexFormat)
        meshes[handle] = MeshResource(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexFormat: indexFormat
        )
        return handle
        #else
        return core.registerMesh(vertexBuffer: vertexBuffer,
                                  vertexCount: vertexCount,
                                  indexBuffer: indexBuffer,
                                  indexCount: indexCount,
                                  indexFormat: indexFormat)
        #endif
    }
    public func destroy(_ handle: ResourceHandle) {
        #if canImport(CVulkan)
        switch handle {
        case .buffer(let h):
            if let res = buffers.removeValue(forKey: h), let dev = device {
                if let b = res.buffer { vkDestroyBuffer(dev, b, nil) }
                if let m = res.memory { vkFreeMemory(dev, m, nil) }
            }
        case .mesh(let h):
            meshes.removeValue(forKey: h)
        default:
            break
        }
        #endif
        core.destroy(handle)
    }
    public func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle {
        #if canImport(CVulkan)
        guard let dev = device else { throw AgentError.internalError("Vulkan device not ready") }
        let module = try ShaderLibrary.shared.module(for: desc.shader)
        try module.validateVertexLayout(desc.vertexLayout)
        if let existing = pipelines.values.first(where: { $0.vertexStride == UInt32(desc.vertexLayout.stride) }) {
            return existing.handle
        }

        // Shader modules
        let vsURL = try module.artifacts.requireSPIRVVertex(for: module.id)
        let fsURL = module.artifacts.spirvFragment
        let vsData = try Data(contentsOf: vsURL)
        var vsModule: VkShaderModule? = nil
        var fsModule: VkShaderModule? = nil
        try vsData.withUnsafeBytes { bytes in
            var smi = VkShaderModuleCreateInfo()
            smi.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
            smi.codeSize = bytes.count
            smi.pCode = bytes.bindMemory(to: UInt32.self).baseAddress
            let r = withUnsafePointer(to: smi) { ptr in vkCreateShaderModule(dev, ptr, nil, &vsModule) }
            if r != VK_SUCCESS || vsModule == nil { throw AgentError.internalError("vkCreateShaderModule(VS) failed (res=\(r))") }
        }
        if let fsURL {
            let fsData = try Data(contentsOf: fsURL)
            try fsData.withUnsafeBytes { bytes in
                var smi = VkShaderModuleCreateInfo()
                smi.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
                smi.codeSize = bytes.count
                smi.pCode = bytes.bindMemory(to: UInt32.self).baseAddress
                let r = withUnsafePointer(to: smi) { ptr in vkCreateShaderModule(dev, ptr, nil, &fsModule) }
                if r != VK_SUCCESS || fsModule == nil { throw AgentError.internalError("vkCreateShaderModule(FS) failed (res=\(r))") }
            }
        }

        // Pipeline stages
        var stageInfos: [VkPipelineShaderStageCreateInfo] = []
        var vsStage = VkPipelineShaderStageCreateInfo()
        vsStage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        vsStage.stage = UInt32(VK_SHADER_STAGE_VERTEX_BIT)
        vsStage.module = vsModule
        var fsStageOpt: VkPipelineShaderStageCreateInfo? = nil
        if let fsModule {
            var fsStage = VkPipelineShaderStageCreateInfo()
            fsStage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
            fsStage.stage = UInt32(VK_SHADER_STAGE_FRAGMENT_BIT)
            fsStage.module = fsModule
            fsStageOpt = fsStage
        }

        // Vertex input
        var binding = VkVertexInputBindingDescription(binding: 0, stride: UInt32(desc.vertexLayout.stride), inputRate: VK_VERTEX_INPUT_RATE_VERTEX)
        var attributes: [VkVertexInputAttributeDescription] = []
        for a in desc.vertexLayout.attributes {
            var attr = VkVertexInputAttributeDescription()
            attr.binding = 0
            attr.location = UInt32(a.index)
            attr.offset = UInt32(a.offset)
            attr.format = convertVertexFormat(a.format)
            attributes.append(attr)
        }
        var vi = VkPipelineVertexInputStateCreateInfo()
        vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
        withUnsafePointer(to: &binding) { bPtr in
            vi.vertexBindingDescriptionCount = 1
            vi.pVertexBindingDescriptions = bPtr
        }
        attributes.withUnsafeMutableBufferPointer { ab in
            vi.vertexAttributeDescriptionCount = UInt32(ab.count)
            vi.pVertexAttributeDescriptions = ab.baseAddress
        }

        var ia = VkPipelineInputAssemblyStateCreateInfo()
        ia.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        ia.primitiveRestartEnable = VK_FALSE

        var viewportState = VkPipelineViewportStateCreateInfo()
        viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewportState.viewportCount = 1
        viewportState.scissorCount = 1

        var raster = VkPipelineRasterizationStateCreateInfo()
        raster.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        raster.depthClampEnable = VK_FALSE
        raster.rasterizerDiscardEnable = VK_FALSE
        raster.polygonMode = VK_POLYGON_MODE_FILL
        raster.cullMode = UInt32(VK_CULL_MODE_NONE.rawValue)
        raster.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE
        raster.depthBiasEnable = VK_FALSE
        raster.lineWidth = 1.0

        var multisample = VkPipelineMultisampleStateCreateInfo()
        multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT
        multisample.sampleShadingEnable = VK_FALSE

        var depthStencil = VkPipelineDepthStencilStateCreateInfo()
        depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        depthStencil.depthTestEnable = VK_TRUE
        depthStencil.depthWriteEnable = VK_TRUE
        depthStencil.depthCompareOp = VK_COMPARE_OP_LESS
        depthStencil.depthBoundsTestEnable = VK_FALSE
        depthStencil.stencilTestEnable = VK_FALSE

        var colorBlendAttachment = VkPipelineColorBlendAttachmentState()
        colorBlendAttachment.colorWriteMask = UInt32(VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT)
        colorBlendAttachment.blendEnable = VK_FALSE
        var colorBlend = VkPipelineColorBlendStateCreateInfo()
        colorBlend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
        withUnsafePointer(to: &colorBlendAttachment) { ptr in
            colorBlend.attachmentCount = 1
            colorBlend.pAttachments = ptr
        }

        var dynStates: [VkDynamicState] = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR]
        var dynamic = VkPipelineDynamicStateCreateInfo()
        dynamic.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
        dynStates.withUnsafeMutableBufferPointer { db in
            dynamic.dynamicStateCount = UInt32(db.count)
            dynamic.pDynamicStates = db.baseAddress
        }

        // Pipeline layout (no descriptors)
        var plInfo = VkPipelineLayoutCreateInfo()
        plInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
        var pcRange = VkPushConstantRange()
        pcRange.stageFlags = UInt32(VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT)
        pcRange.offset = 0
        pcRange.size = 80 // 4x4 float matrix + light dir (vec4)
        withUnsafePointer(to: &pcRange) { ptr in
            plInfo.pushConstantRangeCount = 1
            plInfo.pPushConstantRanges = ptr
        }
        var layout: VkPipelineLayout? = nil
        var r = withUnsafePointer(to: plInfo) { ptr in vkCreatePipelineLayout(dev, ptr, nil, &layout) }
        if r != VK_SUCCESS || layout == nil { throw AgentError.internalError("vkCreatePipelineLayout failed (res=\(r))") }

        // Graphics pipeline
        guard let rp = renderPass else { throw AgentError.internalError("Render pass not ready") }
        var gpInfo = VkGraphicsPipelineCreateInfo()
        gpInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO

        var vsNameCStr = Array(module.vertexEntryPoint.utf8CString)
        let fsNameCStrArr: [CChar]? = module.fragmentEntryPoint.map { Array($0.utf8CString) }

        let createResult: VkResult = vsNameCStr.withUnsafeMutableBufferPointer { vsBuf in
            vsStage.pName = vsBuf.baseAddress
            // Build stageInfos within the lifetime of entry name buffers
            if var fsStage = fsStageOpt, let fsNameArr = fsNameCStrArr {
                return fsNameArr.withUnsafeBufferPointer { fsBuf in
                    fsStage.pName = fsBuf.baseAddress
                    stageInfos = [vsStage, fsStage]
                    return stageInfos.withUnsafeMutableBufferPointer { sb in
                        gpInfo.stageCount = UInt32(sb.count)
                        gpInfo.pStages = sb.baseAddress
                        return withUnsafePointer(to: vi) { viPtr in
                            gpInfo.pVertexInputState = viPtr
                            return withUnsafePointer(to: ia) { iaPtr in
                                gpInfo.pInputAssemblyState = iaPtr
                                return withUnsafePointer(to: viewportState) { vpPtr in
                                    gpInfo.pViewportState = vpPtr
                                    return withUnsafePointer(to: raster) { rsPtr in
                                        gpInfo.pRasterizationState = rsPtr
                                        return withUnsafePointer(to: multisample) { msPtr in
                                            gpInfo.pMultisampleState = msPtr
                                            return withUnsafePointer(to: depthStencil) { dsPtr in
                                                gpInfo.pDepthStencilState = dsPtr
                                                return withUnsafePointer(to: colorBlend) { cbPtr in
                                                    gpInfo.pColorBlendState = cbPtr
                                                    return withUnsafePointer(to: dynamic) { dyPtr in
                                                        gpInfo.pDynamicState = dyPtr
                                                        gpInfo.layout = layout
                                                        gpInfo.renderPass = rp
                                                        gpInfo.subpass = 0
                                                        var pipelineLocal: VkPipeline? = nil
                                                        let cr = withUnsafePointer(to: gpInfo) { ptr in vkCreateGraphicsPipelines(dev, nil, 1, ptr, nil, &pipelineLocal) }
                                                        if cr == VK_SUCCESS { pipeline = pipelineLocal }
                                                        return cr
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                stageInfos = [vsStage]
                return stageInfos.withUnsafeMutableBufferPointer { sb in
                    gpInfo.stageCount = UInt32(sb.count)
                    gpInfo.pStages = sb.baseAddress
                    return withUnsafePointer(to: vi) { viPtr in
                        gpInfo.pVertexInputState = viPtr
                        return withUnsafePointer(to: ia) { iaPtr in
                            gpInfo.pInputAssemblyState = iaPtr
                            return withUnsafePointer(to: viewportState) { vpPtr in
                                gpInfo.pViewportState = vpPtr
                                return withUnsafePointer(to: raster) { rsPtr in
                                    gpInfo.pRasterizationState = rsPtr
                                    return withUnsafePointer(to: multisample) { msPtr in
                                        gpInfo.pMultisampleState = msPtr
                                        return withUnsafePointer(to: depthStencil) { dsPtr in
                                            gpInfo.pDepthStencilState = dsPtr
                                            return withUnsafePointer(to: colorBlend) { cbPtr in
                                                gpInfo.pColorBlendState = cbPtr
                                                return withUnsafePointer(to: dynamic) { dyPtr in
                                                    gpInfo.pDynamicState = dyPtr
                                                    gpInfo.layout = layout
                                                    gpInfo.renderPass = rp
                                                    gpInfo.subpass = 0
                                                    var pipelineLocal: VkPipeline? = nil
                                                    let cr = withUnsafePointer(to: gpInfo) { ptr in vkCreateGraphicsPipelines(dev, nil, 1, ptr, nil, &pipelineLocal) }
                                                    if cr == VK_SUCCESS { pipeline = pipelineLocal }
                                                    return cr
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        let r = createResult
        if r != VK_SUCCESS || pipeline == nil { throw AgentError.internalError("vkCreateGraphicsPipelines failed (res=\(r))") }

        // Clean shader modules (no longer needed after pipeline creation)
        if let m = vsModule { vkDestroyShaderModule(dev, m, nil) }
        if let m = fsModule { vkDestroyShaderModule(dev, m, nil) }

        let handle = PipelineHandle()
        let resource = PipelineResource(handle: handle, pipelineLayout: layout, pipeline: pipeline, vertexStride: UInt32(desc.vertexLayout.stride))
        pipelines[handle] = resource
        if builtinPipeline == nil { builtinPipeline = handle }
        return handle
        #else
        return core.makePipeline(desc)
        #endif
    }

    public func draw(mesh: MeshHandle, pipeline: PipelineHandle, bindings: BindingSet, pushConstants: UnsafeRawPointer?, transform: float4x4) throws {
        #if canImport(CVulkan)
        guard frameActive, let cmd = commandBuffers[currentFrame] else {
            throw AgentError.internalError("draw called outside of beginFrame/endFrame")
        }
        guard let resource = pipelines[pipeline] ?? (builtinPipeline.flatMap { pipelines[$0] }) else {
            throw AgentError.internalError("Unknown pipeline handle")
        }
        guard let pipe = resource.pipeline else { throw AgentError.internalError("Pipeline incomplete") }
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe)
        // Push transform as 4x4 floats (column-major)
        if let layout = resource.pipelineLayout {
            var data: [Float] = transform.toFloatArray()
            if let pc = pushConstants {
                let ptr = pc.bindMemory(to: Float.self, capacity: 20)
                let buf = UnsafeBufferPointer(start: ptr, count: 20)
                data = Array(buf)
            } else {
                data.append(contentsOf: [0.3, -0.5, 0.8, 0.0])
            }
            data.withUnsafeBytes { bytes in
                _ = vkCmdPushConstants(cmd, layout, UInt32(VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT), 0, UInt32(bytes.count), bytes.baseAddress)
            }
        }
        guard let meshResource = meshes[mesh] else {
            throw AgentError.internalError("Unknown mesh handle for draw")
        }
        guard let vertexRes = buffers[meshResource.vertexBuffer], let vertexBuffer = vertexRes.buffer else {
            throw AgentError.internalError("Vertex buffer unavailable for mesh draw")
        }
        let vertexCount = meshResource.vertexCount > 0
            ? UInt32(meshResource.vertexCount)
            : UInt32(max(1, vertexRes.length / max(1, Int(resource.vertexStride))))

        var vertexBuffers = [vertexBuffer]
        var offsets: [VkDeviceSize] = [0]
        vertexBuffers.withUnsafeMutableBufferPointer { bptr in
            offsets.withUnsafeMutableBufferPointer { optr in
                vkCmdBindVertexBuffers(cmd, 0, 1, bptr.baseAddress, optr.baseAddress)
            }
        }

        if let indexHandle = meshResource.indexBuffer,
           meshResource.indexCount > 0,
           let indexRes = buffers[indexHandle],
           let indexBuffer = indexRes.buffer {
            let indexType = convertIndexFormat(meshResource.indexFormat)
            vkCmdBindIndexBuffer(cmd, indexBuffer, 0, indexType)
            vkCmdDrawIndexed(cmd, UInt32(meshResource.indexCount), 1, 0, 0, 0)
        } else {
            vkCmdDraw(cmd, vertexCount, 1, 0, 0)
        }
        #else
        try core.draw(mesh: mesh, pipeline: pipeline, bindings: bindings, pushConstants: pushConstants, transform: transform)
        #endif
    }
    public func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle { core.makeComputePipeline(desc) }
    public func dispatchCompute(_ pipeline: ComputePipelineHandle, groupsX: Int, groupsY: Int, groupsZ: Int, bindings: BindingSet, pushConstants: UnsafeRawPointer?) throws {
        try core.dispatchCompute(pipeline, groupsX: groupsX, groupsY: groupsY, groupsZ: groupsZ, bindings: bindings, pushConstants: pushConstants)
    }

    // MARK: - Vulkan init
    private func initializeVulkan() throws {
        // Query SDL-required instance extensions via the window’s native handles
        let requiredExtensions: [String]
        do {
            requiredExtensions = try surface.handles.vulkanInstanceExtensions()
        } catch AgentError.sdlUnavailable {
            SDLLogger.warn("SDLKit.Graphics.Vulkan", "SDL unavailable; skipping Vulkan instance creation")
            throw AgentError.sdlUnavailable
        } catch {
            SDLLogger.warn("SDLKit.Graphics.Vulkan", "Failed to query Vulkan instance extensions: \(error)")
            throw error
        }

        var extensions = requiredExtensions
        var layers: [String] = []
        let enableValidation: Bool = SettingsStore.getBool("vk.validation") ?? {
            let env = ProcessInfo.processInfo.environment["SDLKIT_VK_VALIDATION"]?.lowercased()
            return env == "1" || env == "true" || env == "yes"
        }()
        if enableValidation {
            if !extensions.contains(where: { $0 == String(cString: VK_EXT_DEBUG_UTILS_EXTENSION_NAME) }) {
                extensions.append(String(cString: VK_EXT_DEBUG_UTILS_EXTENSION_NAME))
            }
            layers.append("VK_LAYER_KHRONOS_validation")
        }

        let extCount = UInt32(extensions.count)
        let cStrings: [UnsafeMutablePointer<CChar>] = extensions.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }

        var extPointerArray: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
        let result: Int32 = extPointerArray.withUnsafeBufferPointer { extBuf in
            if layers.isEmpty {
                return VulkanMinimalCreateInstanceWithExtensions(extBuf.baseAddress, extCount, &vkInstance)
            } else {
                // Build layers array
                let lCStrs: [UnsafeMutablePointer<CChar>] = layers.map { strdup($0) }
                defer { lCStrs.forEach { free($0) } }
                var lPtrs: [UnsafePointer<CChar>?] = lCStrs.map { UnsafePointer($0) }
                let lCount = UInt32(layers.count)
                return lPtrs.withUnsafeBufferPointer { lBuf in
                    VulkanMinimalCreateInstanceWithExtensionsAndLayers(extBuf.baseAddress, extCount, lBuf.baseAddress, lCount, &vkInstance)
                }
            }
        }
        guard result == VK_SUCCESS, vkInstance.handle != nil else {
            throw AgentError.internalError("Vulkan instance creation failed (code=\(result))")
        }

        // Create presentation surface via SDL
        do {
            vkSurface = try surface.createVulkanSurface(instance: vkInstance.handle)
        } catch {
            // Destroy instance on failure to avoid leaks
            VulkanMinimalDestroyInstance(&vkInstance)
            throw error
        }

        SDLLogger.info(
            "SDLKit.Graphics.Vulkan",
            "Instance+Surface ready. extCount=\(extensions.count) validation=\(enableValidation) surface=\(String(describing: vkSurface))"
        )
        #if canImport(CVulkan)
        if enableValidation, let inst = vkInstance.handle {
            setupDebugMessenger(instance: inst)
        }
        #endif
    }

    #if canImport(CVulkan)
    private func initializeDeviceAndQueues() throws {
        guard let instance = vkInstance.handle else {
            throw AgentError.internalError("Vulkan instance not initialized")
        }

        // Enumerate physical devices
        var deviceCount: UInt32 = 0
        var res = vkEnumeratePhysicalDevices(instance, &deviceCount, nil)
        if res != VK_SUCCESS || deviceCount == 0 {
            throw AgentError.internalError("vkEnumeratePhysicalDevices failed or returned zero devices (res=\(res))")
        }
        var physDevices = Array<VkPhysicalDevice?>(repeating: nil, count: Int(deviceCount))
        res = physDevices.withUnsafeMutableBufferPointer { buf in
            vkEnumeratePhysicalDevices(instance, &deviceCount, buf.baseAddress)
        }
        if res != VK_SUCCESS {
            throw AgentError.internalError("vkEnumeratePhysicalDevices(list) failed (res=\(res))")
        }

        var chosenPhys: VkPhysicalDevice? = nil
        var graphicsIndex: UInt32 = 0
        var presentIndex: UInt32 = 0

        // Pick the first device that supports graphics + present for our surface
        outer: for pdOpt in physDevices {
            guard let pd = pdOpt else { continue }
            var qCount: UInt32 = 0
            vkGetPhysicalDeviceQueueFamilyProperties(pd, &qCount, nil)
            if qCount == 0 { continue }
            var qProps = Array<VkQueueFamilyProperties>(repeating: VkQueueFamilyProperties(), count: Int(qCount))
            qProps.withUnsafeMutableBufferPointer { buf in
                vkGetPhysicalDeviceQueueFamilyProperties(pd, &qCount, buf.baseAddress)
            }
            for i in 0..<qCount {
                let props = qProps[Int(i)]
                let supportsGraphics = (props.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT)) != 0
                var presentSupport: VkBool32 = 0
                if let surfaceHandle = vkSurface {
                    vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, surfaceHandle, &presentSupport)
                }
                let supportsPresent = presentSupport != 0
                if supportsGraphics && supportsPresent {
                    chosenPhys = pd
                    graphicsIndex = i
                    presentIndex = i
                    break outer
                }
            }
            // If not unified, look for separate present
            var gIndex: UInt32? = nil
            var pIndex: UInt32? = nil
            for i in 0..<qCount {
                let props = qProps[Int(i)]
                if (props.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT)) != 0 { gIndex = i }
                var presentSupport: VkBool32 = 0
                if let surfaceHandle = vkSurface {
                    vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, surfaceHandle, &presentSupport)
                }
                if presentSupport != 0 { pIndex = i }
            }
            if let gi = gIndex, let pi = pIndex {
                chosenPhys = pd
                graphicsIndex = gi
                presentIndex = pi
                break
            }
        }

        guard let physicalDevice = chosenPhys else {
            throw AgentError.internalError("No suitable Vulkan physical device with graphics+present found")
        }

        // Create logical device with VK_KHR_swapchain
        var uniqueFamilies = [graphicsIndex]
        if presentIndex != graphicsIndex { uniqueFamilies.append(presentIndex) }

        // Prebuild queue create infos without priorities (filled just before vkCreateDevice)
        var queueCreateInfos: [VkDeviceQueueCreateInfo] = uniqueFamilies.map { fam in
            var qci = VkDeviceQueueCreateInfo()
            qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
            qci.queueFamilyIndex = fam
            qci.queueCount = 1
            qci.pQueuePriorities = nil
            return qci
        }
        var prioritiesStorage = Array<Float>(repeating: 1.0, count: uniqueFamilies.count)

        var deviceFeatures = VkPhysicalDeviceFeatures()
        var dci = VkDeviceCreateInfo()
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
        withUnsafePointer(to: &deviceFeatures) { feats in
            dci.pEnabledFeatures = feats
        }

        // Enable swapchain extension
        let swapchainExt = VK_KHR_SWAPCHAIN_EXTENSION_NAME
        var extNames: [UnsafePointer<CChar>?] = [swapchainExt]

        var deviceOpt: VkDevice? = nil
        res = queueCreateInfos.withUnsafeMutableBufferPointer { qciBuf in
            prioritiesStorage.withUnsafeMutableBufferPointer { prioBuf in
                // Fill priorities pointers per queue
                for i in 0..<qciBuf.count {
                    qciBuf[i].pQueuePriorities = prioBuf.baseAddress?.advanced(by: i)
                }
                dci.queueCreateInfoCount = UInt32(qciBuf.count)
                dci.pQueueCreateInfos = qciBuf.baseAddress
                return extNames.withUnsafeMutableBufferPointer { extBuf in
                    dci.enabledExtensionCount = UInt32(extBuf.count)
                    dci.ppEnabledExtensionNames = extBuf.baseAddress
                    return withUnsafePointer(to: dci) { createInfoPtr in
                        vkCreateDevice(physicalDevice, createInfoPtr, nil, &deviceOpt)
                    }
                }
            }
        }
        if res != VK_SUCCESS || deviceOpt == nil {
            throw AgentError.internalError("vkCreateDevice failed (res=\(res))")
        }

        var gq: VkQueue? = nil
        var pq: VkQueue? = nil
        vkGetDeviceQueue(deviceOpt, graphicsIndex, 0, &gq)
        vkGetDeviceQueue(deviceOpt, presentIndex, 0, &pq)
        guard gq != nil && pq != nil else {
            throw AgentError.internalError("Failed to acquire Vulkan device queues")
        }

        // Save
        self.physicalDevice = physicalDevice
        self.device = deviceOpt
        self.graphicsQueueFamilyIndex = graphicsIndex
        self.presentQueueFamilyIndex = presentIndex
        self.graphicsQueue = gq
        self.presentQueue = pq

        SDLLogger.info(
            "SDLKit.Graphics.Vulkan",
            "Device+Queues ready. gfxQ=\(graphicsIndex) presentQ=\(presentIndex)"
        )

        // Create swapchain and render targets at initial size, then command/sync and builtin geometry
        try recreateSwapchain(width: UInt32(window.config.width), height: UInt32(window.config.height))
        try ensureCommandPoolAndSync()
        try createBuiltinTriangleResources()
    }

    private func recreateSwapchain(width: UInt32, height: UInt32) throws {
        guard let instance = vkInstance.handle, let pd = physicalDevice, let dev = device, let surfaceHandle = vkSurface else {
            throw AgentError.internalError("Vulkan device or surface not initialized")
        }
        _ = instance // silence unused

        // Wait device idle before tearing down
        _ = vkDeviceWaitIdle(dev)
        destroySwapchainResources()

        // Query surface capabilities
        var caps = VkSurfaceCapabilitiesKHR()
        var res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, surfaceHandle, &caps)
        if res != VK_SUCCESS {
            throw AgentError.internalError("vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed (res=\(res))")
        }

        // Query surface formats
        var formatCount: UInt32 = 0
        res = vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surfaceHandle, &formatCount, nil)
        if res != VK_SUCCESS || formatCount == 0 {
            throw AgentError.internalError("vkGetPhysicalDeviceSurfaceFormatsKHR count failed (res=\(res))")
        }
        var formats = Array<VkSurfaceFormatKHR>(repeating: VkSurfaceFormatKHR(), count: Int(formatCount))
        res = formats.withUnsafeMutableBufferPointer { buf in
            vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surfaceHandle, &formatCount, buf.baseAddress)
        }
        if res != VK_SUCCESS {
            throw AgentError.internalError("vkGetPhysicalDeviceSurfaceFormatsKHR list failed (res=\(res))")
        }
        // Choose preferred format
        let preferred = formats.first { $0.format == VK_FORMAT_B8G8R8A8_UNORM && $0.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR }
        let chosen = preferred ?? formats[0]
        colorFormat = chosen.format
        colorSpace = chosen.colorSpace

        // Present mode: FIFO is guaranteed
        var presentModeCount: UInt32 = 0
        res = vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surfaceHandle, &presentModeCount, nil)
        if res != VK_SUCCESS || presentModeCount == 0 {
            throw AgentError.internalError("vkGetPhysicalDeviceSurfacePresentModesKHR count failed (res=\(res))")
        }
        var presentModes = Array<VkPresentModeKHR>(repeating: VK_PRESENT_MODE_FIFO_KHR, count: Int(presentModeCount))
        res = presentModes.withUnsafeMutableBufferPointer { buf in
            vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surfaceHandle, &presentModeCount, buf.baseAddress)
        }
        if res != VK_SUCCESS {
            throw AgentError.internalError("vkGetPhysicalDeviceSurfacePresentModesKHR list failed (res=\(res))")
        }
        let chosenPresent = presentModes.contains(VK_PRESENT_MODE_FIFO_KHR) ? VK_PRESENT_MODE_FIFO_KHR : presentModes[0]

        // Extent
        if caps.currentExtent.width != UInt32.max {
            surfaceExtent = caps.currentExtent
        } else {
            var w = max(caps.minImageExtent.width, min(caps.maxImageExtent.width, width))
            var h = max(caps.minImageExtent.height, min(caps.maxImageExtent.height, height))
            surfaceExtent = VkExtent2D(width: w, height: h)
        }

        // Image count
        var imageCount = caps.minImageCount + 1
        if caps.maxImageCount > 0 && imageCount > caps.maxImageCount {
            imageCount = caps.minImageCount
        }

        // Transform
        let preTransform = caps.currentTransform

        // Composite alpha
        let compositeAlphaCandidates: [VkCompositeAlphaFlagBitsKHR] = [
            VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
            VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
            VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR
        ]
        var compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
        for c in compositeAlphaCandidates {
            if (caps.supportedCompositeAlpha & UInt32(c.rawValue)) != 0 { compositeAlpha = c; break }
        }

        // Sharing mode
        var sharingMode = VK_SHARING_MODE_EXCLUSIVE
        var queueFamilyIndices = [graphicsQueueFamilyIndex, presentQueueFamilyIndex]
        if graphicsQueueFamilyIndex != presentQueueFamilyIndex {
            sharingMode = VK_SHARING_MODE_CONCURRENT
        }

        // Create swapchain
        var sci = VkSwapchainCreateInfoKHR()
        sci.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
        sci.surface = surfaceHandle
        sci.minImageCount = imageCount
        sci.imageFormat = colorFormat
        sci.imageColorSpace = colorSpace
        sci.imageExtent = surfaceExtent
        sci.imageArrayLayers = 1
        sci.imageUsage = UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)
        sci.imageSharingMode = sharingMode
        sci.preTransform = preTransform
        sci.compositeAlpha = compositeAlpha
        sci.presentMode = chosenPresent
        sci.clipped = VK_TRUE
        sci.oldSwapchain = nil

        var newSwapchain: VkSwapchainKHR? = nil
        if sharingMode == VK_SHARING_MODE_CONCURRENT {
            res = queueFamilyIndices.withUnsafeBufferPointer { idxBuf in
                var tmp = sci
                tmp.queueFamilyIndexCount = UInt32(idxBuf.count)
                tmp.pQueueFamilyIndices = idxBuf.baseAddress
                return withUnsafePointer(to: tmp) { infoPtr in
                    vkCreateSwapchainKHR(dev, infoPtr, nil, &newSwapchain)
                }
            }
        } else {
            res = withUnsafePointer(to: sci) { infoPtr in
                vkCreateSwapchainKHR(dev, infoPtr, nil, &newSwapchain)
            }
        }
        if res != VK_SUCCESS || newSwapchain == nil {
            throw AgentError.internalError("vkCreateSwapchainKHR failed (res=\(res))")
        }
        self.swapchain = newSwapchain

        // Retrieve images
        var scImageCount: UInt32 = 0
        res = vkGetSwapchainImagesKHR(dev, newSwapchain, &scImageCount, nil)
        if res != VK_SUCCESS || scImageCount == 0 {
            throw AgentError.internalError("vkGetSwapchainImagesKHR count failed (res=\(res))")
        }
        swapchainImages = Array<VkImage?>(repeating: nil, count: Int(scImageCount))
        res = swapchainImages.withUnsafeMutableBufferPointer { buf in
            vkGetSwapchainImagesKHR(dev, newSwapchain, &scImageCount, buf.baseAddress)
        }
        if res != VK_SUCCESS {
            throw AgentError.internalError("vkGetSwapchainImagesKHR list failed (res=\(res))")
        }

        // Create image views for each image
        swapchainImageViews = []
        swapchainImageViews.reserveCapacity(Int(scImageCount))
        for imgOpt in swapchainImages {
            guard let img = imgOpt else { continue }
            var viewInfo = VkImageViewCreateInfo()
            viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
            viewInfo.image = img
            viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
            viewInfo.format = colorFormat
            viewInfo.components = VkComponentMapping(r: VK_COMPONENT_SWIZZLE_IDENTITY, g: VK_COMPONENT_SWIZZLE_IDENTITY, b: VK_COMPONENT_SWIZZLE_IDENTITY, a: VK_COMPONENT_SWIZZLE_IDENTITY)
            viewInfo.subresourceRange = VkImageSubresourceRange(aspectMask: UInt32(VK_IMAGE_ASPECT_COLOR_BIT), baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1)
            var view: VkImageView? = nil
            res = withUnsafePointer(to: viewInfo) { ptr in
                vkCreateImageView(dev, ptr, nil, &view)
            }
            if res != VK_SUCCESS || view == nil {
                throw AgentError.internalError("vkCreateImageView failed (res=\(res))")
            }
            swapchainImageViews.append(view)
        }

        // Create depth resources
        depthFormat = pickSupportedDepthFormat(physicalDevice: pd)
        try createDepthResources(device: dev, physicalDevice: pd)

        // Create render pass if not yet created
        if renderPass == nil {
            try createRenderPass(device: dev)
        }

        // Create framebuffers
        try createFramebuffers(device: dev)

        SDLLogger.info("SDLKit.Graphics.Vulkan", "Swapchain created: images=\(swapchainImages.count) extent=\(surfaceExtent.width)x\(surfaceExtent.height)")
    }

    private func ensureCommandPoolAndSync() throws {
        guard let dev = device else { throw AgentError.internalError("Device not ready for command pool") }
        if commandPool == nil {
            var info = VkCommandPoolCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
            info.queueFamilyIndex = graphicsQueueFamilyIndex
            info.flags = UInt32(VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT)
            var pool: VkCommandPool? = nil
            let r = withUnsafePointer(to: info) { ptr in vkCreateCommandPool(dev, ptr, nil, &pool) }
            if r != VK_SUCCESS || pool == nil { throw AgentError.internalError("vkCreateCommandPool failed (res=\(r))") }
            commandPool = pool
        }

        if commandBuffers.count != maxFramesInFlight {
            if !commandBuffers.isEmpty {
                vkFreeCommandBuffers(dev, commandPool, UInt32(commandBuffers.count), commandBuffers)
            }
            commandBuffers = Array<VkCommandBuffer?>(repeating: nil, count: maxFramesInFlight)
            var alloc = VkCommandBufferAllocateInfo()
            alloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
            alloc.commandPool = commandPool
            alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
            alloc.commandBufferCount = UInt32(maxFramesInFlight)
            let r = withUnsafePointer(to: alloc) { ptr in vkAllocateCommandBuffers(dev, ptr, &commandBuffers) }
            if r != VK_SUCCESS { throw AgentError.internalError("vkAllocateCommandBuffers failed (res=\(r))") }
        }

        if imageAvailableSemaphores.count != maxFramesInFlight {
            // Destroy old sync
            for s in imageAvailableSemaphores { if let sem = s { vkDestroySemaphore(dev, sem, nil) } }
            for s in renderFinishedSemaphores { if let sem = s { vkDestroySemaphore(dev, sem, nil) } }
            for f in inFlightFences { if let ff = f { vkDestroyFence(dev, ff, nil) } }
            imageAvailableSemaphores.removeAll(); renderFinishedSemaphores.removeAll(); inFlightFences.removeAll()

            var si = VkSemaphoreCreateInfo(); si.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
            var fi = VkFenceCreateInfo(); fi.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO; fi.flags = UInt32(VK_FENCE_CREATE_SIGNALED_BIT)
            for _ in 0..<maxFramesInFlight {
                var a: VkSemaphore? = nil
                var b: VkSemaphore? = nil
                var f: VkFence? = nil
                _ = withUnsafePointer(to: si) { ptr in vkCreateSemaphore(dev, ptr, nil, &a) }
                _ = withUnsafePointer(to: si) { ptr in vkCreateSemaphore(dev, ptr, nil, &b) }
                _ = withUnsafePointer(to: fi) { ptr in vkCreateFence(dev, ptr, nil, &f) }
                imageAvailableSemaphores.append(a)
                renderFinishedSemaphores.append(b)
                inFlightFences.append(f)
            }
        }
    }

    private func createBuiltinTriangleResources() throws {
        guard let dev = device else { throw AgentError.internalError("Device not ready for triangle") }
        // Vertex data: 3 vertices, pos.xyz + color.xyz
        let vertices: [Float] = [
            -0.6, -0.5, 0.0,  1.0, 0.0, 0.0,
             0.0,  0.6, 0.0,  0.0, 1.0, 0.0,
             0.6, -0.5, 0.0,  0.0, 0.0, 1.0
        ]
        builtinVertexCount = 3

        // Create staging buffer
        let dataSize = VkDeviceSize(vertices.count * MemoryLayout<Float>.size)
        var stagingBuffer: VkBuffer? = nil
        var stagingMemory: VkDeviceMemory? = nil
        try createBuffer(size: dataSize, usage: UInt32(VK_BUFFER_USAGE_TRANSFER_SRC_BIT), properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT), bufferOut: &stagingBuffer, memoryOut: &stagingMemory)
        // Map and copy
        var mapped: UnsafeMutableRawPointer? = nil
        _ = vkMapMemory(dev, stagingMemory, 0, dataSize, 0, &mapped)
        if let mapped {
            vertices.withUnsafeBytes { bytes in
                memcpy(mapped, bytes.baseAddress, bytes.count)
            }
            vkUnmapMemory(dev, stagingMemory)
        }

        // Create device-local vertex buffer
        var vbuf: VkBuffer? = nil
        var vmem: VkDeviceMemory? = nil
        try createBuffer(size: dataSize, usage: UInt32(VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT), properties: UInt32(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT), bufferOut: &vbuf, memoryOut: &vmem)

        // Copy buffer via one-time command
        try copyBuffer(src: stagingBuffer, dst: vbuf, size: dataSize)

        // Cleanup staging
        if let sb = stagingBuffer { vkDestroyBuffer(dev, sb, nil) }
        if let sm = stagingMemory { vkFreeMemory(dev, sm, nil) }

        builtinVertexBuffer = vbuf
        builtinVertexMemory = vmem
    }

    private func createBuffer(size: VkDeviceSize, usage: UInt32, properties: UInt32, bufferOut: inout VkBuffer?, memoryOut: inout VkDeviceMemory?) throws {
        guard let dev = device, let pd = physicalDevice else { throw AgentError.internalError("Device not ready for buffer") }
        var info = VkBufferCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        info.size = size
        info.usage = usage
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        var buffer: VkBuffer? = nil
        var r = withUnsafePointer(to: info) { ptr in vkCreateBuffer(dev, ptr, nil, &buffer) }
        if r != VK_SUCCESS || buffer == nil { throw AgentError.internalError("vkCreateBuffer failed (res=\(r))") }

        var req = VkMemoryRequirements()
        vkGetBufferMemoryRequirements(dev, buffer, &req)
        var props = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(pd, &props)
        let index = findMemoryTypeIndex(requirements: req, properties: props, required: properties)
        var alloc = VkMemoryAllocateInfo()
        alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        alloc.allocationSize = req.size
        alloc.memoryTypeIndex = index
        var memory: VkDeviceMemory? = nil
        r = withUnsafePointer(to: alloc) { ptr in vkAllocateMemory(dev, ptr, nil, &memory) }
        if r != VK_SUCCESS || memory == nil { throw AgentError.internalError("vkAllocateMemory(buffer) failed (res=\(r))") }
        vkBindBufferMemory(dev, buffer, memory, 0)
        bufferOut = buffer
        memoryOut = memory
    }

    private func copyBuffer(src: VkBuffer?, dst: VkBuffer?, size: VkDeviceSize) throws {
        guard let dev = device, let gq = graphicsQueue, let pool = commandPool, let src = src, let dst = dst else {
            throw AgentError.internalError("copyBuffer prerequisites missing")
        }
        // Allocate a temporary command buffer
        var alloc = VkCommandBufferAllocateInfo()
        alloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        alloc.commandPool = pool
        alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        alloc.commandBufferCount = 1
        var cmd: VkCommandBuffer? = nil
        var r = withUnsafePointer(to: alloc) { ptr in vkAllocateCommandBuffers(dev, ptr, &cmd) }
        if r != VK_SUCCESS || cmd == nil { throw AgentError.internalError("vkAllocateCommandBuffers(copy) failed (res=\(r))") }
        var begin = VkCommandBufferBeginInfo()
        begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        begin.flags = UInt32(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT)
        _ = withUnsafePointer(to: begin) { ptr in vkBeginCommandBuffer(cmd, ptr) }
        var region = VkBufferCopy(srcOffset: 0, dstOffset: 0, size: size)
        withUnsafePointer(to: &region) { rp in vkCmdCopyBuffer(cmd, src, dst, 1, rp) }
        _ = vkEndCommandBuffer(cmd)
        var submit = VkSubmitInfo()
        submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        submit.commandBufferCount = 1
        withUnsafePointer(to: &cmd) { cp in submit.pCommandBuffers = cp }
        _ = withUnsafePointer(to: submit) { sp in vkQueueSubmit(gq, 1, sp, nil) }
        _ = vkQueueWaitIdle(gq)
        vkFreeCommandBuffers(dev, pool, 1, [cmd])
    }

    private func pickSupportedDepthFormat(physicalDevice: VkPhysicalDevice) -> VkFormat {
        let candidates: [VkFormat] = [VK_FORMAT_D32_SFLOAT, VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_D24_UNORM_S8_UINT]
        for fmt in candidates {
            var props = VkFormatProperties()
            vkGetPhysicalDeviceFormatProperties(physicalDevice, fmt, &props)
            if (props.optimalTilingFeatures & UInt32(VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT)) != 0 {
                return fmt
            }
        }
        return VK_FORMAT_D32_SFLOAT
    }

    private func createDepthResources(device: VkDevice, physicalDevice: VkPhysicalDevice) throws {
        // Image
        var imgInfo = VkImageCreateInfo()
        imgInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        imgInfo.imageType = VK_IMAGE_TYPE_2D
        imgInfo.extent = VkExtent3D(width: surfaceExtent.width, height: surfaceExtent.height, depth: 1)
        imgInfo.mipLevels = 1
        imgInfo.arrayLayers = 1
        imgInfo.format = depthFormat
        imgInfo.tiling = VK_IMAGE_TILING_OPTIMAL
        imgInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        imgInfo.usage = UInt32(VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT)
        imgInfo.samples = VK_SAMPLE_COUNT_1_BIT
        imgInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE

        var img: VkImage? = nil
        var res = withUnsafePointer(to: imgInfo) { ptr in
            vkCreateImage(device, ptr, nil, &img)
        }
        if res != VK_SUCCESS || img == nil { throw AgentError.internalError("vkCreateImage(depth) failed (res=\(res))") }
        depthImage = img

        // Allocate memory
        var memReq = VkMemoryRequirements()
        vkGetImageMemoryRequirements(device, img, &memReq)
        var memProps = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProps)
        let memIndex = findMemoryTypeIndex(requirements: memReq, properties: memProps, required: UInt32(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))
        var alloc = VkMemoryAllocateInfo()
        alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        alloc.allocationSize = memReq.size
        alloc.memoryTypeIndex = memIndex
        var memory: VkDeviceMemory? = nil
        res = withUnsafePointer(to: alloc) { ptr in
            vkAllocateMemory(device, ptr, nil, &memory)
        }
        if res != VK_SUCCESS || memory == nil { throw AgentError.internalError("vkAllocateMemory(depth) failed (res=\(res))") }
        depthMemory = memory
        vkBindImageMemory(device, img, memory, 0)

        // Image view
        var viewInfo = VkImageViewCreateInfo()
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        viewInfo.image = img
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
        viewInfo.format = depthFormat
        viewInfo.subresourceRange = VkImageSubresourceRange(aspectMask: UInt32(VK_IMAGE_ASPECT_DEPTH_BIT), baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1)
        var view: VkImageView? = nil
        res = withUnsafePointer(to: viewInfo) { ptr in
            vkCreateImageView(device, ptr, nil, &view)
        }
        if res != VK_SUCCESS || view == nil { throw AgentError.internalError("vkCreateImageView(depth) failed (res=\(res))") }
        depthView = view
    }

    private func findMemoryTypeIndex(requirements: VkMemoryRequirements, properties: VkPhysicalDeviceMemoryProperties, required: UInt32) -> UInt32 {
        let count = Int(properties.memoryTypeCount)
        var resultIndex: UInt32 = 0
        withUnsafePointer(to: properties.memoryTypes) { basePtr in
            let raw = UnsafeRawPointer(basePtr)
            let typesPtr = raw.assumingMemoryBound(to: VkMemoryType.self)
            let buf = UnsafeBufferPointer(start: typesPtr, count: count)
            for i in 0..<count {
                let supports = (requirements.memoryTypeBits & (1 << UInt32(i))) != 0
                let flags = buf[i].propertyFlags
                if supports && (flags & required) == required {
                    resultIndex = UInt32(i)
                    break
                }
            }
        }
        return resultIndex
    }

    private func createRenderPass(device: VkDevice) throws {
        // Color attachment
        var colorAttachment = VkAttachmentDescription()
        colorAttachment.format = colorFormat
        colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT
        colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE
        colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR

        // Depth attachment
        var depthAttachment = VkAttachmentDescription()
        depthAttachment.format = depthFormat
        depthAttachment.samples = VK_SAMPLE_COUNT_1_BIT
        depthAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        depthAttachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depthAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        depthAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depthAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        depthAttachment.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL

        var colorRef = VkAttachmentReference(attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
        var depthRef = VkAttachmentReference(attachment: 1, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL)

        var subpass = VkSubpassDescription()
        subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        subpass.colorAttachmentCount = 1
        withUnsafePointer(to: &colorRef) { ptr in
            subpass.pColorAttachments = ptr
        }
        withUnsafePointer(to: &depthRef) { ptr in
            subpass.pDepthStencilAttachment = ptr
        }

        var dependencies = VkSubpassDependency(
            srcSubpass: VK_SUBPASS_EXTERNAL,
            dstSubpass: 0,
            srcStageMask: UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            dstStageMask: UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            srcAccessMask: 0,
            dstAccessMask: UInt32(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT),
            dependencyFlags: 0
        )

        var attachments = [colorAttachment, depthAttachment]
        var rpInfo = VkRenderPassCreateInfo()
        rpInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        attachments.withUnsafeMutableBufferPointer { ab in
            rpInfo.attachmentCount = UInt32(ab.count)
            rpInfo.pAttachments = ab.baseAddress
        }
        withUnsafePointer(to: &subpass) { sp in
            rpInfo.subpassCount = 1
            rpInfo.pSubpasses = sp
        }
        withUnsafePointer(to: &dependencies) { dep in
            rpInfo.dependencyCount = 1
            rpInfo.pDependencies = dep
        }

        var rp: VkRenderPass? = nil
        let res = withUnsafePointer(to: rpInfo) { ptr in
            vkCreateRenderPass(device, ptr, nil, &rp)
        }
        if res != VK_SUCCESS || rp == nil { throw AgentError.internalError("vkCreateRenderPass failed (res=\(res))") }
        renderPass = rp
    }

    private func createFramebuffers(device: VkDevice) throws {
        guard let rp = renderPass, let dv = depthView else {
            throw AgentError.internalError("Render pass or depth view not ready")
        }
        framebuffers = []
        for viewOpt in swapchainImageViews {
            guard let colorView = viewOpt else { continue }
            var attachments: [VkImageView?] = [colorView, dv]
            var fbInfo = VkFramebufferCreateInfo()
            fbInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
            fbInfo.renderPass = rp
            attachments.withUnsafeMutableBufferPointer { buf in
                fbInfo.attachmentCount = UInt32(buf.count)
                fbInfo.pAttachments = buf.baseAddress
            }
            fbInfo.width = surfaceExtent.width
            fbInfo.height = surfaceExtent.height
            fbInfo.layers = 1
            var fb: VkFramebuffer? = nil
            let res = withUnsafePointer(to: fbInfo) { ptr in
                vkCreateFramebuffer(device, ptr, nil, &fb)
            }
            if res != VK_SUCCESS || fb == nil { throw AgentError.internalError("vkCreateFramebuffer failed (res=\(res))") }
            framebuffers.append(fb)
        }
    }

    // MARK: - Validation (debug utils)
    #if canImport(CVulkan)
    private static let validationVerbosity: VkDebugUtilsMessageSeverityFlagsEXT = {
        let env = ProcessInfo.processInfo.environment["SDLKIT_VK_VALIDATION_VERBOSE"]?.lowercased()
        if env == "1" || env == "true" || env == "yes" {
            return VkDebugUtilsMessageSeverityFlagsEXT(
                VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT.rawValue |
                VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT.rawValue |
                VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT.rawValue |
                VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT.rawValue
            )
        }
        return VkDebugUtilsMessageSeverityFlagsEXT(
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT.rawValue |
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT.rawValue
        )
    }()

    private static let validationTypes: VkDebugUtilsMessageTypeFlagsEXT = VkDebugUtilsMessageTypeFlagsEXT(
        VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT.rawValue |
        VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT.rawValue |
        VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT.rawValue
    )

    private static let debugCallback: @convention(c) (
        VkDebugUtilsMessageSeverityFlagBitsEXT,
        VkDebugUtilsMessageTypeFlagsEXT,
        UnsafePointer<VkDebugUtilsMessengerCallbackDataEXT>?,
        UnsafeMutableRawPointer?
    ) -> VkBool32 = { severity, _, callbackData, _ in
        guard let data = callbackData?.pointee else { return 0 }
        let message = data.pMessage.map { String(cString: $0) } ?? "<no message>"
        switch severity {
        case VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT:
            SDLLogger.error("SDLKit.Graphics.Vulkan", message)
        case VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT:
            SDLLogger.warn("SDLKit.Graphics.Vulkan", message)
        case VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT:
            SDLLogger.info("SDLKit.Graphics.Vulkan", message)
        default:
            SDLLogger.debug("SDLKit.Graphics.Vulkan", message)
        }
        return 0
    }

    private func setupDebugMessenger(instance: VkInstance) {
        var createInfo = VkDebugUtilsMessengerCreateInfoEXT()
        createInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
        createInfo.messageSeverity = Self.validationVerbosity
        createInfo.messageType = Self.validationTypes
        createInfo.pfnUserCallback = VulkanRenderBackend.debugCallback

        let createFn: PFN_vkVoidFunction? = "vkCreateDebugUtilsMessengerEXT".withCString { namePtr in
            vkGetInstanceProcAddr(instance, namePtr)
        }
        guard let createFn else { return }
        typealias CreatePFN = @convention(c) (VkInstance?, UnsafePointer<VkDebugUtilsMessengerCreateInfoEXT>?, UnsafePointer<VkAllocationCallbacks>?, UnsafeMutablePointer<VkDebugUtilsMessengerEXT?>?) -> VkResult
        let typedCreate = unsafeBitCast(createFn, to: CreatePFN.self)

        var messenger: VkDebugUtilsMessengerEXT? = nil
        let res = withUnsafePointer(to: createInfo) { ptr in typedCreate(instance, ptr, nil, &messenger) }
        if res == VK_SUCCESS {
            debugMessenger = messenger
        }
    }

    private func destroyDebugMessenger(instance: VkInstance, messenger: VkDebugUtilsMessengerEXT) {
        let destroyFn: PFN_vkVoidFunction? = "vkDestroyDebugUtilsMessengerEXT".withCString { namePtr in
            vkGetInstanceProcAddr(instance, namePtr)
        }
        guard let destroyFn else { return }
        typealias DestroyPFN = @convention(c) (VkInstance?, VkDebugUtilsMessengerEXT?, UnsafePointer<VkAllocationCallbacks>?) -> Void
        let typedDestroy = unsafeBitCast(destroyFn, to: DestroyPFN.self)
        typedDestroy(instance, messenger, nil)
    }
    #endif

    private func convertIndexFormat(_ format: IndexFormat) -> VkIndexType {
        switch format {
        case .uint16:
            return VK_INDEX_TYPE_UINT16
        case .uint32:
            return VK_INDEX_TYPE_UINT32
        }
    }

    private func convertVertexFormat(_ format: VertexFormat) -> VkFormat {
        switch format {
        case .float2: return VK_FORMAT_R32G32_SFLOAT
        case .float3: return VK_FORMAT_R32G32B32_SFLOAT
        case .float4: return VK_FORMAT_R32G32B32A32_SFLOAT
        }
    }

    private func destroySwapchainResources() {
        guard let dev = device else { return }
        for i in 0..<framebuffers.count { if let fb = framebuffers[i] { vkDestroyFramebuffer(dev, fb, nil) } }
        framebuffers.removeAll()
        // Keep renderPass; it does not depend on swapchain extent
        for i in 0..<swapchainImageViews.count { if let v = swapchainImageViews[i] { vkDestroyImageView(dev, v, nil) } }
        swapchainImageViews.removeAll()
        if let dv = depthView { vkDestroyImageView(dev, dv, nil); depthView = nil }
        if let di = depthImage { vkDestroyImage(dev, di, nil); depthImage = nil }
        if let dm = depthMemory { vkFreeMemory(dev, dm, nil); depthMemory = nil }
        if let sc = swapchain { vkDestroySwapchainKHR(dev, sc, nil); swapchain = nil }
    }
    #endif
}
#endif
