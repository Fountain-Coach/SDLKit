#if os(Windows)
import XCTest
import WinSDK
import Direct3D12
@testable import SDLKit

@MainActor
final class D3D12SamplerDescriptorTests: XCTestCase {
    private let graphicsShaderID = ShaderID("d3d_sampler_graphics_test")
    private let computeShaderID = ShaderID("d3d_sampler_compute_test")

    private func registerGraphicsSamplerModule() throws -> ShaderModule {
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

    override func tearDown() {
        super.tearDown()
        ShaderLibrary.shared._unregisterTestModule(graphicsShaderID)
        ShaderLibrary.shared._unregisterTestComputeModule(computeShaderID)
    }

    func testGraphicsSamplerDescriptorTable() async throws {
        try await MainActor.run {
            let module = try registerGraphicsSamplerModule()
            let window = SDLWindow(config: .init(title: "D3D12SamplerGraphics", width: 64, height: 64))
            let backend = try D3D12RenderBackend(window: window)

            let descriptor = GraphicsPipelineDescriptor(
                label: "d3d_sampler_graphics",
                shader: graphicsShaderID,
                vertexLayout: module.vertexLayout,
                colorFormats: [.bgra8Unorm],
                depthFormat: .depth32Float
            )
            let pipeline = try backend.makePipeline(descriptor)

            let vertices: [Float] = [
                0, 0, 0, 1, 0, 0,
                0, 1, 0, 0, 1, 0,
                1, 0, 0, 0, 0, 1
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
            let pixel = Data([255, 0, 0, 255])
            let texture = try backend.createTexture(
                descriptor: textureDescriptor,
                initialData: TextureInitialData(mipLevelData: [pixel])
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
                lodMaxClamp: 8,
                maxAnisotropy: 1
            )
            let sampler = try backend.createSampler(descriptor: samplerDescriptor)

            try backend.beginFrame()
            defer { try? backend.endFrame() }

            var bindings = BindingSet()
            bindings.setTexture(texture, at: 5)
            bindings.setSampler(sampler, at: 6)
            bindings.materialConstants = BindingSet.MaterialConstants(data: Data(repeating: 0, count: module.pushConstantSize))

            try backend.draw(mesh: mesh, pipeline: pipeline, bindings: bindings, transform: .identity)

            let nativeDesc = try XCTUnwrap(backend.debugSamplerDescriptor(for: sampler))
            XCTAssertEqual(nativeDesc.Filter, D3D12_FILTER_MIN_MAG_MIP_LINEAR)
            XCTAssertEqual(nativeDesc.AddressU, D3D12_TEXTURE_ADDRESS_MODE_CLAMP)
            XCTAssertEqual(nativeDesc.AddressV, D3D12_TEXTURE_ADDRESS_MODE_CLAMP)
            XCTAssertEqual(nativeDesc.AddressW, D3D12_TEXTURE_ADDRESS_MODE_CLAMP)

            let parameterIndex = backend.debugGraphicsSamplerParameterIndex(for: pipeline, slot: 6)
            XCTAssertNotNil(parameterIndex)
        }
    }

    func testComputeSamplerDescriptorTable() async throws {
        try await MainActor.run {
            let computeModule = try registerComputeSamplerModule()
            let window = SDLWindow(config: .init(title: "D3D12SamplerCompute", width: 32, height: 32))
            let backend = try D3D12RenderBackend(window: window)

            let pipeline = try backend.makeComputePipeline(ComputePipelineDescriptor(label: "d3d_sampler_compute", shader: computeShaderID))

            let bufferLength = 16
            let bufferData = Data(repeating: 0, count: bufferLength)
            let buffer0 = try backend.createBuffer(bytes: bufferData, length: bufferLength, usage: .storage)
            let buffer1 = try backend.createBuffer(bytes: bufferData, length: bufferLength, usage: .storage)
            let buffer2 = try backend.createBuffer(bytes: bufferData, length: bufferLength, usage: .storage)

            let textureDescriptor = TextureDescriptor(width: 1, height: 1, mipLevels: 1, format: .rgba8Unorm, usage: .shaderRead)
            let pixel = Data([0, 255, 0, 255])
            let texture = try backend.createTexture(
                descriptor: textureDescriptor,
                initialData: TextureInitialData(mipLevelData: [pixel])
            )

            let samplerDescriptor = SamplerDescriptor(
                label: "NearestWrap",
                minFilter: .nearest,
                magFilter: .nearest,
                mipFilter: .nearest,
                addressModeU: .repeatTexture,
                addressModeV: .repeatTexture,
                addressModeW: .repeatTexture,
                lodMinClamp: 0,
                lodMaxClamp: 4,
                maxAnisotropy: 1
            )
            let sampler = try backend.createSampler(descriptor: samplerDescriptor)

            try backend.beginFrame()
            defer { try? backend.endFrame() }

            var bindings = BindingSet()
            bindings.setBuffer(buffer0, at: 0)
            bindings.setBuffer(buffer1, at: 1)
            bindings.setBuffer(buffer2, at: 2)
            bindings.setTexture(texture, at: 3)
            bindings.setSampler(sampler, at: 4)

            try backend.dispatchCompute(pipeline, groupsX: 1, groupsY: 1, groupsZ: 1, bindings: bindings)

            let nativeDesc = try XCTUnwrap(backend.debugSamplerDescriptor(for: sampler))
            XCTAssertEqual(nativeDesc.Filter, D3D12_FILTER_MIN_MAG_MIP_POINT)
            XCTAssertEqual(nativeDesc.AddressU, D3D12_TEXTURE_ADDRESS_MODE_WRAP)
            XCTAssertEqual(nativeDesc.AddressV, D3D12_TEXTURE_ADDRESS_MODE_WRAP)
            XCTAssertEqual(nativeDesc.AddressW, D3D12_TEXTURE_ADDRESS_MODE_WRAP)

            let samplerIndex = backend.debugComputeSamplerParameterIndex(for: pipeline, slot: 4)
            XCTAssertNotNil(samplerIndex)
            let textureIndex = backend.debugComputeTextureParameterIndex(for: pipeline, slot: 3)
            XCTAssertNotNil(textureIndex)
            XCTAssertFalse(computeModule.bindings.isEmpty)
        }
    }
}
#endif
