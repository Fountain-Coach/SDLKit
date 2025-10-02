#if os(Linux) && canImport(VulkanMinimal)
import XCTest
@testable import SDLKit

@MainActor
final class VulkanComputeInteropTests: XCTestCase {
    private let computeShaderID = ShaderID("vk_frame_compute_barrier")

    override func setUp() {
        super.setUp()
        setenv("SDLKIT_VK_VALIDATION_CAPTURE", "1", 1)
        setenv("SDLKIT_VK_VALIDATION", "1", 1)
    }

    private func registerInteropComputeModule() throws -> ComputeShaderModule {
        let base = try ShaderLibrary.shared.computeModule(for: ShaderID("vector_add"))
        var bindings = base.bindings
        bindings.append(BindingSlot(index: 3, kind: .sampledTexture))
        bindings.append(BindingSlot(index: 4, kind: .sampler))
        bindings.append(BindingSlot(index: 5, kind: .storageTexture))
        let module = ComputeShaderModule(
            id: computeShaderID,
            entryPoint: base.entryPoint,
            threadgroupSize: base.threadgroupSize,
            pushConstantSize: base.pushConstantSize,
            bindings: bindings,
            artifacts: base.artifacts
        )
        ShaderLibrary.shared._registerTestComputeModule(module)
        return module
    }

    private func makeIdentityBuffer(_ backend: RenderBackend) throws -> BufferHandle {
        let matrix = float4x4.identity.toFloatArray()
        return try matrix.withUnsafeBytes { bytes in
            try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .uniform)
        }
    }

    func testInterleavedComputeAndGraphicsWithinFrameHasNoValidationWarnings() async throws {
        do {
            try await MainActor.run {
                _ = VulkanRenderBackend.drainCapturedValidationMessages()
                let computeModule = try registerInteropComputeModule()
                defer { ShaderLibrary.shared._unregisterTestComputeModule(computeShaderID) }

                let window = SDLWindow(config: .init(title: "VKComputeFrame", width: 160, height: 160))
                try window.open()
                defer { window.close() }
                try window.show()

                let backend = try RenderBackendFactory.makeBackend(window: window, override: "vulkan")
                guard let vkBackend = backend as? VulkanRenderBackend else {
                    throw XCTSkip("Backend not VulkanRenderBackend")
                }

                let computePipeline = try backend.makeComputePipeline(ComputePipelineDescriptor(label: "vk_frame_compute", shader: computeShaderID))

                let bufferLength = 256
                let zeroes = Data(repeating: 0, count: bufferLength)
                let buffer0 = try backend.createBuffer(bytes: zeroes, length: bufferLength, usage: .storage)
                let buffer1 = try backend.createBuffer(bytes: zeroes, length: bufferLength, usage: .storage)
                let buffer2 = try backend.createBuffer(bytes: zeroes, length: bufferLength, usage: .storage)

                let sampledDescriptor = TextureDescriptor(width: 2, height: 2, mipLevels: 1, format: .rgba8Unorm, usage: .shaderRead)
                let sampledPixels = TextureInitialData(mipLevelData: [Data(repeating: 255, count: 4 * 4)])
                let sampledTexture = try backend.createTexture(descriptor: sampledDescriptor, initialData: sampledPixels)

                let samplerDescriptor = SamplerDescriptor(
                    label: "FrameComputeLinear",
                    minFilter: .linear,
                    magFilter: .linear,
                    mipFilter: .notMipmapped,
                    addressModeU: .repeatTexture,
                    addressModeV: .repeatTexture,
                    addressModeW: .repeatTexture,
                    lodMinClamp: 0,
                    lodMaxClamp: 1,
                    maxAnisotropy: 1
                )
                let computeSampler = try backend.createSampler(descriptor: samplerDescriptor)

                let storageTextureDescriptor = TextureDescriptor(width: 2, height: 2, mipLevels: 1, format: .rgba8Unorm, usage: .shaderWrite)
                let storageTexture = try backend.createTexture(descriptor: storageTextureDescriptor, initialData: nil)

                let graphicsModule = try ShaderLibrary.shared.module(for: ShaderID("unlit_triangle"))
                let graphicsDescriptor = GraphicsPipelineDescriptor(
                    label: "vk_frame_graphics",
                    shader: graphicsModule.id,
                    vertexLayout: graphicsModule.vertexLayout,
                    colorFormats: [.bgra8Unorm],
                    depthFormat: .depth32Float
                )
                let graphicsPipeline = try backend.makePipeline(graphicsDescriptor)

                let vertices: [Float] = [
                    -0.5, -0.5, 0, 1, 0, 0,
                     0.5, -0.5, 0, 0, 1, 0,
                     0.0,  0.6, 0, 0, 0, 1
                ]
                let vertexBuffer = try backend.createBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, usage: .vertex)
                let mesh = try backend.registerMesh(vertexBuffer: vertexBuffer, vertexCount: 3, indexBuffer: nil, indexCount: 0, indexFormat: .uint16)

                let uniformBuffer = try makeIdentityBuffer(backend)

                try backend.beginFrame()
                var frameEnded = false
                defer {
                    if !frameEnded {
                        try? backend.endFrame()
                    }
                }

                var computeBindings = BindingSet()
                computeBindings.setBuffer(buffer0, at: 0)
                computeBindings.setBuffer(buffer1, at: 1)
                computeBindings.setBuffer(buffer2, at: 2)
                computeBindings.setTexture(sampledTexture, at: 3)
                computeBindings.setSampler(computeSampler, at: 4)
                computeBindings.setTexture(storageTexture, at: 5)

                try backend.dispatchCompute(computePipeline, groupsX: 2, groupsY: 1, groupsZ: 1, bindings: computeBindings)

                var graphicsBindings = BindingSet()
                graphicsBindings.setBuffer(uniformBuffer, at: 0)
                graphicsBindings.setTexture(sampledTexture, at: 10)

                try backend.draw(mesh: mesh, pipeline: graphicsPipeline, bindings: graphicsBindings, transform: .identity)

                try backend.dispatchCompute(computePipeline, groupsX: 1, groupsY: 1, groupsZ: 1, bindings: computeBindings)

                try backend.endFrame()
                frameEnded = true

                let messages = vkBackend.takeValidationMessages()
                XCTAssertTrue(messages.isEmpty, "Vulkan validation warnings: \(messages)")
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch AgentError.sdlUnavailable {
            throw XCTSkip("SDL unavailable; skipping Vulkan compute interop test")
        } catch AgentError.notImplemented {
            throw XCTSkip("Vulkan backend unavailable in this configuration")
        }
    }

    func testOutOfFrameComputeCompletesBeforeNextFrame() async throws {
        do {
            try await MainActor.run {
                _ = VulkanRenderBackend.drainCapturedValidationMessages()
                let computeModule = try registerInteropComputeModule()
                defer { ShaderLibrary.shared._unregisterTestComputeModule(computeShaderID) }

                let window = SDLWindow(config: .init(title: "VKComputeOutOfFrame", width: 96, height: 96))
                try window.open()
                defer { window.close() }
                try window.show()

                let backend = try RenderBackendFactory.makeBackend(window: window, override: "vulkan")
                guard let vkBackend = backend as? VulkanRenderBackend else {
                    throw XCTSkip("Backend not VulkanRenderBackend")
                }

                let computePipeline = try backend.makeComputePipeline(ComputePipelineDescriptor(label: "vk_transfer_compute", shader: computeShaderID))

                let bufferLength = 128
                let zeroes = Data(repeating: 0, count: bufferLength)
                let buffer0 = try backend.createBuffer(bytes: zeroes, length: bufferLength, usage: .storage)
                let buffer1 = try backend.createBuffer(bytes: zeroes, length: bufferLength, usage: .storage)
                let buffer2 = try backend.createBuffer(bytes: zeroes, length: bufferLength, usage: .storage)

                let sampledDescriptor = TextureDescriptor(width: 1, height: 1, mipLevels: 1, format: .rgba8Unorm, usage: .shaderRead)
                let sampledTexture = try backend.createTexture(descriptor: sampledDescriptor, initialData: TextureInitialData(mipLevelData: [Data([0, 0, 0, 255])]))

                let samplerDescriptor = SamplerDescriptor(
                    label: "VKComputeOutOfFrameSampler",
                    minFilter: .nearest,
                    magFilter: .nearest,
                    mipFilter: .notMipmapped,
                    addressModeU: .clampToEdge,
                    addressModeV: .clampToEdge,
                    addressModeW: .clampToEdge,
                    lodMinClamp: 0,
                    lodMaxClamp: 1,
                    maxAnisotropy: 1
                )
                let sampler = try backend.createSampler(descriptor: samplerDescriptor)

                let storageTextureDescriptor = TextureDescriptor(width: 1, height: 1, mipLevels: 1, format: .rgba8Unorm, usage: .shaderWrite)
                let storageTexture = try backend.createTexture(descriptor: storageTextureDescriptor, initialData: nil)

                var bindings = BindingSet()
                bindings.setBuffer(buffer0, at: 0)
                bindings.setBuffer(buffer1, at: 1)
                bindings.setBuffer(buffer2, at: 2)
                bindings.setTexture(sampledTexture, at: 3)
                bindings.setSampler(sampler, at: 4)
                bindings.setTexture(storageTexture, at: 5)

                try backend.dispatchCompute(computePipeline, groupsX: 1, groupsY: 1, groupsZ: 1, bindings: bindings)
                try backend.dispatchCompute(computePipeline, groupsX: 2, groupsY: 1, groupsZ: 1, bindings: bindings)

                try backend.beginFrame()
                try backend.endFrame()

                let messages = vkBackend.takeValidationMessages()
                XCTAssertTrue(messages.isEmpty, "Vulkan validation warnings: \(messages)")
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch AgentError.sdlUnavailable {
            throw XCTSkip("SDL unavailable; skipping Vulkan transfer compute test")
        } catch AgentError.notImplemented {
            throw XCTSkip("Vulkan backend unavailable in this configuration")
        }
    }
}
#endif
