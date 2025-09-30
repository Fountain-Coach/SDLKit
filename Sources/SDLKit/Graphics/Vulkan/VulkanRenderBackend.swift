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
    private var vkSurface: VkSurfaceKHR = 0
    #if canImport(CVulkan)
    // Device/Queues
    private var physicalDevice: VkPhysicalDevice? = nil
    private var device: VkDevice? = nil
    private var graphicsQueueFamilyIndex: UInt32 = 0
    private var presentQueueFamilyIndex: UInt32 = 0
    private var graphicsQueue: VkQueue? = nil
    private var presentQueue: VkQueue? = nil
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
            vkDestroyDevice(dev, nil)
        }
        if vkSurface != 0, let inst = vkInstance.handle {
            vkDestroySurfaceKHR(inst, vkSurface, nil)
            vkSurface = 0
        }
        #endif
        try? waitGPU()
        VulkanMinimalDestroyInstance(&vkInstance)
    }

    // MARK: - RenderBackend
    public func beginFrame() throws { try core.beginFrame() }
    public func endFrame() throws { try core.endFrame() }
    public func resize(width: Int, height: Int) throws { core.resize(width: width, height: height) }
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
            "Instance+Surface ready. extCount=\(requiredExtensions.count) surface=0x\(String(format: "%016llX", UInt64(vkSurface)))"
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
                vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, vkSurface, &presentSupport)
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
                vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, vkSurface, &presentSupport)
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
    }
    #endif
}
#endif
