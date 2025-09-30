// Linux Vulkan backend scaffold: creates a VkInstance with SDL-required extensions
// and an SDL-created VkSurfaceKHR. Other operations are currently delegated to the
// stub core until full Vulkan rendering is implemented.

#if os(Linux)
import Foundation
import Glibc
import VulkanMinimal

@MainActor
public final class VulkanRenderBackend: RenderBackend {
    private let window: SDLWindow
    private let surface: RenderSurface
    private var core: StubRenderBackendCore

    // Vulkan handles
    private var vkInstance = VulkanMinimalInstance()
    private var vkSurface: VkSurfaceKHR = 0

    public required init(window: SDLWindow) throws {
        self.window = window
        self.surface = try RenderSurface(window: window)
        self.core = try StubRenderBackendCore(kind: .vulkan, window: window)

        try initializeVulkan()
    }

    deinit {
        // Ensure GPU idle-equivalent in the stub path
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
}
#endif
