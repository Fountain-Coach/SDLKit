// Linux Vulkan backend scaffold: creates a VkInstance with SDL-required extensions
// and an SDL-created VkSurfaceKHR. Other operations are currently delegated to the
// stub core until full Vulkan rendering is implemented.

#if os(Linux)
import Foundation
import Glibc
import VulkanMinimal
#if canImport(CVulkan)
import CVulkan
#endif

@MainActor
public final class VulkanRenderBackend: RenderBackend {
    private let window: SDLWindow
    private let surface: RenderSurface
    private var core: StubRenderBackendCore

    // Vulkan handles
    private var vkInstance = VulkanMinimalInstance()
    private var vkSurface: VkSurfaceKHR? = nil
    #if canImport(CVulkan)
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
            vkDestroyDevice(dev, nil)
        }
        if vkSurface != 0, let inst = vkInstance.handle {
            if let surf = vkSurface {
                vkDestroySurfaceKHR(inst, surf, nil)
            }
            vkSurface = nil
        }
        #endif
        try? waitGPU()
        VulkanMinimalDestroyInstance(&vkInstance)
    }

    // MARK: - RenderBackend
    public func beginFrame() throws { try core.beginFrame() }
    public func endFrame() throws { try core.endFrame() }
    public func resize(width: Int, height: Int) throws {
        core.resize(width: width, height: height)
        #if canImport(CVulkan)
        if device != nil {
            try recreateSwapchain(width: UInt32(max(1, width)), height: UInt32(max(1, height)))
        }
        #endif
    }
    public func waitGPU() throws { core.waitGPU() }

    public func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle {
        try core.createBuffer(bytes: bytes, length: length, usage: usage)
    }
    public func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle {
        core.createTexture(descriptor: descriptor, initialData: initialData)
    }
    public func destroy(_ handle: ResourceHandle) { core.destroy(handle) }
    public func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle { core.makePipeline(desc) }
    public func draw(mesh: MeshHandle, pipeline: PipelineHandle, bindings: BindingSet, pushConstants: UnsafeRawPointer?, transform: float4x4) throws {
        try core.draw(mesh: mesh, pipeline: pipeline, bindings: bindings, pushConstants: pushConstants, transform: transform)
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

        let extCount = UInt32(requiredExtensions.count)
        let cStrings: [UnsafeMutablePointer<CChar>] = requiredExtensions.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }

        var extPointerArray: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
        let result = extPointerArray.withUnsafeBufferPointer { buf -> Int32 in
            VulkanMinimalCreateInstanceWithExtensions(buf.baseAddress, extCount, &vkInstance)
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
            "Instance+Surface ready. extCount=\(requiredExtensions.count) surface=\(String(describing: vkSurface))"
        )
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

        // Create swapchain and render targets at initial size
        try recreateSwapchain(width: UInt32(window.config.width), height: UInt32(window.config.height))
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

        // Create render pass
        try createRenderPass(device: dev)

        // Create framebuffers
        try createFramebuffers(device: dev)

        SDLLogger.info("SDLKit.Graphics.Vulkan", "Swapchain created: images=\(swapchainImages.count) extent=\(surfaceExtent.width)x\(surfaceExtent.height)")
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

    private func destroySwapchainResources() {
        guard let dev = device else { return }
        for i in 0..<framebuffers.count { if let fb = framebuffers[i] { vkDestroyFramebuffer(dev, fb, nil) } }
        framebuffers.removeAll()
        if let rp = renderPass { vkDestroyRenderPass(dev, rp, nil); renderPass = nil }
        for i in 0..<swapchainImageViews.count { if let v = swapchainImageViews[i] { vkDestroyImageView(dev, v, nil) } }
        swapchainImageViews.removeAll()
        if let dv = depthView { vkDestroyImageView(dev, dv, nil); depthView = nil }
        if let di = depthImage { vkDestroyImage(dev, di, nil); depthImage = nil }
        if let dm = depthMemory { vkFreeMemory(dev, dm, nil); depthMemory = nil }
        if let sc = swapchain { vkDestroySwapchainKHR(dev, sc, nil); swapchain = nil }
    }
    #endif
    #endif
}
#endif
