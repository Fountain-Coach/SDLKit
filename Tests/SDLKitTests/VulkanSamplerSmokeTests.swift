#if os(Linux) && canImport(VulkanMinimal)
import XCTest
@testable import SDLKit

@MainActor
final class VulkanSamplerSmokeTests: XCTestCase {
    private let graphicsShaderID = ShaderID("vk_sampler_graphics_test")
    private let computeShaderID = ShaderID("vk_sampler_compute_test")

    override func setUp() {
        super.setUp()
        setenv("SDLKIT_VK_VALIDATION_CAPTURE", "1", 1)
        setenv("SDLKIT_VK_VALIDATION", "1", 1)
    }

    private func registerGraphicsSamplerModule() throws -> ShaderModule {
        let base = try ShaderLibrary.shared.module(for: ShaderID("unlit_triangle"))
        var bindings = base.bindings
        var fragmentBindings = bindings[.fragment] ?? []
        fragmentBindings.append(BindingSlot(index: 11, kind: .sampler))
        bindings[.fragment] = fragmentBindings
        let module = ShaderModule(
            id: graphicsShaderID,
            vertexEntryPoint: base.vertexEntryPoint,
            fragmentEntryPoint: base.fragmentEntryPoint,
            vertexLayout: base.vertexLayout,
            bindings: bindings,
            pushConstantSize: base.pushConstantSize,
            artifacts: base.artifacts
        )
        ShaderLibrary.shared._registerTestModule(module)
        return module
    }

    private func registerComputeSamplerModule() throws -> ComputeShaderModule {
        let base = try ShaderLibrary.shared.computeModule(for: ShaderID("vector_add"))
        var bindings = base.bindings
        bindings.append(BindingSlot(index: 3, kind: .sampledTexture))
        bindings.append(BindingSlot(index: 4, kind: .sampler))
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

    func testTriangleSamplerUpdateGeneratesNoValidationWarnings() async throws {
        do {
            try await MainActor.run {
                _ = VulkanRenderBackend.drainCapturedValidationMessages()
                let module = try registerGraphicsSamplerModule()
                defer { ShaderLibrary.shared._unregisterTestModule(graphicsShaderID) }

                let window = SDLWindow(config: .init(title: "VKSamplerGraphics", width: 128, height: 128))
                try window.open()
                defer { window.close() }
                try window.show()

                let backend = try RenderBackendFactory.makeBackend(window: window, override: "vulkan")
                guard let vkBackend = backend as? VulkanRenderBackend else {
                    throw XCTSkip("Backend not VulkanRenderBackend")
                }

                let descriptor = GraphicsPipelineDescriptor(
                    label: "vk_sampler_graphics",
                    shader: graphicsShaderID,
                    vertexLayout: module.vertexLayout,
                    colorFormats: [.bgra8Unorm],
                    depthFormat: .depth32Float
                )
                let pipeline = try backend.makePipeline(descriptor)

                let vertices: [Float] = [
                    0,   0, 0, 1, 0, 0,
                    0,   1, 0, 0, 1, 0,
                    1,   0, 0, 0, 0, 1
                ]
                let vertexBuffer = try backend.createBuffer(
                    bytes: vertices,
                    length: vertices.count * MemoryLayout<Float>.size,
                    usage: .vertex
                )
                let mesh = try backend.registerMesh(
                    vertexBuffer: vertexBuffer,
                    vertexCount: 3,
                    indexBuffer: nil,
                    indexCount: 0,
                    indexFormat: .uint16
                )

                let textureDescriptor = TextureDescriptor(width: 1, height: 1, mipLevels: 1, format: .rgba8Unorm, usage: .shaderRead)
                let pixel = Data([255, 255, 255, 255])
                let texture = try backend.createTexture(
                    descriptor: textureDescriptor,
                    initialData: TextureInitialData(mipLevelData: [pixel])
                )

                let samplerDescriptor = SamplerDescriptor(
                    label: "SmokeLinearClamp",
                    minFilter: .linear,
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

                try backend.beginFrame()
                var frameEnded = false
                defer {
                    if !frameEnded {
                        try? backend.endFrame()
                    }
                }

                var bindings = BindingSet()
                bindings.setTexture(texture, at: 10)
                bindings.setSampler(sampler, at: 11)
                if module.pushConstantSize > 0 {
                    bindings.materialConstants = BindingSet.MaterialConstants(data: Data(repeating: 0, count: module.pushConstantSize))
                }

                try backend.draw(mesh: mesh, pipeline: pipeline, bindings: bindings, transform: .identity)
                try backend.endFrame()
                frameEnded = true

                let messages = vkBackend.takeValidationMessages()
                XCTAssertTrue(messages.isEmpty, "Vulkan validation warnings: \(messages)")
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch AgentError.sdlUnavailable {
            throw XCTSkip("SDL unavailable; skipping Vulkan sampler smoke test")
        } catch AgentError.notImplemented {
            throw XCTSkip("Vulkan backend unavailable in this configuration")
        }
    }

    func testComputeSamplerUpdateGeneratesNoValidationWarnings() async throws {
        do {
            try await MainActor.run {
                _ = VulkanRenderBackend.drainCapturedValidationMessages()
                let module = try registerComputeSamplerModule()
                defer { ShaderLibrary.shared._unregisterTestComputeModule(computeShaderID) }
                XCTAssertFalse(module.bindings.isEmpty)

                let window = SDLWindow(config: .init(title: "VKSamplerCompute", width: 64, height: 64))
                try window.open()
                defer { window.close() }
                try window.show()

                let backend = try RenderBackendFactory.makeBackend(window: window, override: "vulkan")
                guard let vkBackend = backend as? VulkanRenderBackend else {
                    throw XCTSkip("Backend not VulkanRenderBackend")
                }

                let pipeline = try backend.makeComputePipeline(ComputePipelineDescriptor(label: "vk_sampler_compute", shader: computeShaderID))

                let bufferLength = 16
                let zeros = Data(repeating: 0, count: bufferLength)
                let buffer0 = try backend.createBuffer(bytes: zeros, length: bufferLength, usage: .storage)
                let buffer1 = try backend.createBuffer(bytes: zeros, length: bufferLength, usage: .storage)
                let buffer2 = try backend.createBuffer(bytes: zeros, length: bufferLength, usage: .storage)

                let textureDescriptor = TextureDescriptor(width: 1, height: 1, mipLevels: 1, format: .rgba8Unorm, usage: .shaderRead)
                let texPixel = Data([0, 0, 0, 255])
                let texture = try backend.createTexture(
                    descriptor: textureDescriptor,
                    initialData: TextureInitialData(mipLevelData: [texPixel])
                )

                let samplerDescriptor = SamplerDescriptor(
                    label: "SmokeNearestWrap",
                    minFilter: .nearest,
                    magFilter: .nearest,
                    mipFilter: .nearest,
                    addressModeU: .repeatTexture,
                    addressModeV: .repeatTexture,
                    addressModeW: .mirrorRepeat,
                    lodMinClamp: 0,
                    lodMaxClamp: 4,
                    maxAnisotropy: 1
                )
                let sampler = try backend.createSampler(descriptor: samplerDescriptor)

                var bindings = BindingSet()
                bindings.setBuffer(buffer0, at: 0)
                bindings.setBuffer(buffer1, at: 1)
                bindings.setBuffer(buffer2, at: 2)
                bindings.setTexture(texture, at: 3)
                bindings.setSampler(sampler, at: 4)

                try backend.dispatchCompute(pipeline, groupsX: 1, groupsY: 1, groupsZ: 1, bindings: bindings)

                let messages = vkBackend.takeValidationMessages()
                XCTAssertTrue(messages.isEmpty, "Vulkan validation warnings: \(messages)")
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch AgentError.sdlUnavailable {
            throw XCTSkip("SDL unavailable; skipping Vulkan sampler compute test")
        } catch AgentError.notImplemented {
            throw XCTSkip("Vulkan backend unavailable in this configuration")
        }
    }
}
#endif
