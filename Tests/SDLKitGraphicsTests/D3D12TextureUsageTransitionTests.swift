#if os(Windows)
import XCTest
import Direct3D12
@testable import SDLKit

@MainActor
final class D3D12TextureUsageTransitionTests: XCTestCase {
    private let graphicsShaderID = ShaderID("d3d_texture_usage_sample")
    private let computeShaderID = ShaderID("d3d_texture_usage_compute")

    private func registerGraphicsModule() throws -> ShaderModule {
        let base = try ShaderLibrary.shared.module(for: ShaderID("unlit_triangle"))
        let module = ShaderModule(
            id: graphicsShaderID,
            vertexEntryPoint: base.vertexEntryPoint,
            fragmentEntryPoint: base.fragmentEntryPoint,
            vertexLayout: base.vertexLayout,
            bindings: [
                .vertex: base.bindings[.vertex] ?? [],
                .fragment: [
                    BindingSlot(index: 5, kind: .sampledTexture),
                    BindingSlot(index: 6, kind: .sampler)
                ]
            ],
            pushConstantSize: base.pushConstantSize,
            artifacts: base.artifacts
        )
        ShaderLibrary.shared._registerTestModule(module)
        return module
    }

    private func registerComputeModule() throws -> ComputeShaderModule? {
        guard let base = try? ShaderLibrary.shared.computeModule(for: ShaderID("vector_add")) else {
            return nil
        }
        var bindings = base.bindings
        bindings.append(BindingSlot(index: 3, kind: .storageTexture))
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

    override func tearDown() {
        super.tearDown()
        ShaderLibrary.shared._unregisterTestModule(graphicsShaderID)
        ShaderLibrary.shared._unregisterTestComputeModule(computeShaderID)
    }

    func testRenderTargetSampleAndUAVTransitions() async throws {
        try await MainActor.run {
            let graphicsModule = try registerGraphicsModule()
            guard let _ = try registerComputeModule() else {
                throw XCTSkip("Compute shader artifacts unavailable for storage texture validation")
            }

            let window = SDLWindow(config: .init(title: "TextureUsageTransitions", width: 64, height: 64))
            let backend = try D3D12RenderBackend(window: window)

            let vertices: [Float] = [
                -1, -1, 0, 1, 0, 0,
                 0,  1, 0, 0, 1, 0,
                 1, -1, 0, 0, 0, 1
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

            let samplerDescriptor = SamplerDescriptor(
                label: "LinearClamp",
                minFilter: .linear,
                magFilter: .linear,
                mipFilter: .linear,
                addressModeU: .clampToEdge,
                addressModeV: .clampToEdge,
                addressModeW: .clampToEdge,
                lodMinClamp: 0,
                lodMaxClamp: 4,
                maxAnisotropy: 1
            )
            let sampler = try backend.createSampler(descriptor: samplerDescriptor)

            let offscreenDesc = TextureDescriptor(
                width: window.config.width,
                height: window.config.height,
                mipLevels: 1,
                format: .rgba8Unorm,
                usage: .renderTarget
            )
            let offscreen = try backend.createTexture(descriptor: offscreenDesc, initialData: nil)
            let offscreenDescriptors = try XCTUnwrap(backend.debugTextureDescriptors(for: offscreen))
            XCTAssertTrue(offscreenDescriptors.hasRenderTargetView)
            XCTAssertTrue(offscreenDescriptors.hasShaderResourceView)
            XCTAssertFalse(offscreenDescriptors.hasUnorderedAccessView)

            let pipelineDescriptor = GraphicsPipelineDescriptor(
                label: "texture_usage_sample",
                shader: graphicsShaderID,
                vertexLayout: graphicsModule.vertexLayout,
                colorFormats: [.bgra8Unorm]
            )
            let pipeline = try backend.makePipeline(pipelineDescriptor)

            try backend.beginFrame()
            defer { try? backend.endFrame() }

            try backend.debugBindRenderTarget(offscreen, clearColor: (0.25, 0.5, 0.75, 1.0))
            XCTAssertEqual(backend.debugTextureState(for: offscreen), D3D12_RESOURCE_STATE_RENDER_TARGET)

            try backend.debugBindDefaultRenderTarget()

            var drawBindings = BindingSet()
            drawBindings.setTexture(offscreen, at: 5)
            drawBindings.setSampler(sampler, at: 6)
            drawBindings.materialConstants = BindingSet.MaterialConstants(data: Data(repeating: 0, count: graphicsModule.pushConstantSize))

            try backend.draw(mesh: mesh, pipeline: pipeline, bindings: drawBindings, transform: .identity)
            XCTAssertEqual(backend.debugTextureState(for: offscreen), D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE)

            let computePipeline = try backend.makeComputePipeline(ComputePipelineDescriptor(label: "texture_usage_compute", shader: computeShaderID))
            let bufferLength = 64
            let zero = Data(repeating: 0, count: bufferLength)
            let buffer0 = try backend.createBuffer(bytes: zero, length: bufferLength, usage: .storage)
            let buffer1 = try backend.createBuffer(bytes: zero, length: bufferLength, usage: .storage)
            let buffer2 = try backend.createBuffer(bytes: zero, length: bufferLength, usage: .storage)

            let storageDesc = TextureDescriptor(width: 8, height: 8, mipLevels: 1, format: .rgba8Unorm, usage: .shaderWrite)
            let storageTexture = try backend.createTexture(descriptor: storageDesc, initialData: nil)
            let storageDescriptors = try XCTUnwrap(backend.debugTextureDescriptors(for: storageTexture))
            XCTAssertTrue(storageDescriptors.hasUnorderedAccessView)
            XCTAssertTrue(storageDescriptors.hasShaderResourceView)

            var computeBindings = BindingSet()
            computeBindings.setBuffer(buffer0, at: 0)
            computeBindings.setBuffer(buffer1, at: 1)
            computeBindings.setBuffer(buffer2, at: 2)
            computeBindings.setTexture(storageTexture, at: 3)

            try backend.dispatchCompute(computePipeline, groupsX: 1, groupsY: 1, groupsZ: 1, bindings: computeBindings)
            XCTAssertEqual(backend.debugTextureState(for: storageTexture), D3D12_RESOURCE_STATE_UNORDERED_ACCESS)
        }
    }
}
#endif
