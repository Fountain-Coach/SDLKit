import Foundation
import XCTest
@testable import SDLKit

@MainActor
private final class EnforcingBackend: RenderBackend {
    private var frameActive = false
    private let window: SDLWindow
    private let computeOverride: Int?
    private var pipelineRequirements: [PipelineHandle: Int] = [:]
    private var computeRequirements: [ComputePipelineHandle: Int] = [:]

    private init(baseWindow: SDLWindow, override: Int?) {
        self.window = baseWindow
        self.computeOverride = override
    }

    convenience init(window: SDLWindow, computeOverride: Int? = nil) throws {
        self.init(baseWindow: window, override: computeOverride)
    }

    required convenience init(window: SDLWindow) throws {
        try self.init(window: window, computeOverride: nil)
    }

    func beginFrame() throws {
        guard !frameActive else { throw AgentError.internalError("beginFrame called twice") }
        frameActive = true
    }

    func endFrame() throws {
        guard frameActive else { throw AgentError.internalError("endFrame without beginFrame") }
        frameActive = false
    }

    func resize(width: Int, height: Int) throws {
        _ = (width, height)
    }

    func waitGPU() throws {}

    func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle {
        _ = (bytes, length, usage)
        return BufferHandle()
    }

    func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle {
        _ = (descriptor, initialData)
        return TextureHandle()
    }

    func createSampler(descriptor: SamplerDescriptor) throws -> SamplerHandle {
        _ = descriptor
        return SamplerHandle()
    }

    func destroy(_ handle: ResourceHandle) {
        _ = handle
    }

    func registerMesh(vertexBuffer: BufferHandle,
                      vertexCount: Int,
                      indexBuffer: BufferHandle?,
                      indexCount: Int,
                      indexFormat: IndexFormat) throws -> MeshHandle {
        _ = (vertexBuffer, vertexCount, indexBuffer, indexCount, indexFormat)
        return MeshHandle()
    }

    func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle {
        let handle = PipelineHandle()
        let module = try ShaderLibrary.shared.module(for: desc.shader)
        pipelineRequirements[handle] = module.pushConstantSize
        return handle
    }

    func draw(mesh: MeshHandle,
              pipeline: PipelineHandle,
              bindings: BindingSet,
              transform: float4x4) throws {
        guard frameActive else { throw AgentError.internalError("draw outside beginFrame/endFrame") }
        _ = (mesh, transform)
        let expected = pipelineRequirements[pipeline] ?? 0
        if expected > 0 {
            guard let payload = bindings.materialConstants else {
                let message = "Shader requires \(expected) bytes of material constants but none were provided."
                SDLLogger.error("SDLKit.Graphics.Tests", message)
                throw AgentError.invalidArgument(message)
            }
            guard payload.byteCount == expected else {
                let message = "Shader requires \(expected) bytes of material constants but received \(payload.byteCount)."
                SDLLogger.error("SDLKit.Graphics.Tests", message)
                throw AgentError.invalidArgument(message)
            }
        }
    }

    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle {
        let handle = ComputePipelineHandle()
        let expected = computeOverride ?? (try? ShaderLibrary.shared.computeModule(for: desc.shader).pushConstantSize) ?? 0
        computeRequirements[handle] = expected
        return handle
    }

    func dispatchCompute(_ pipeline: ComputePipelineHandle,
                         groupsX: Int,
                         groupsY: Int,
                         groupsZ: Int,
                         bindings: BindingSet) throws {
        guard frameActive else { throw AgentError.internalError("dispatchCompute outside beginFrame/endFrame") }
        _ = (pipeline, groupsX, groupsY, groupsZ)
        let expected = computeRequirements[pipeline] ?? 0
        if expected > 0 {
            guard let payload = bindings.materialConstants else {
                let message = "Compute shader requires \(expected) bytes of push constants but none were provided."
                SDLLogger.error("SDLKit.Graphics.Tests", message)
                throw AgentError.invalidArgument(message)
            }
            guard payload.byteCount == expected else {
                let message = "Compute shader requires \(expected) bytes of push constants but received \(payload.byteCount)."
                SDLLogger.error("SDLKit.Graphics.Tests", message)
                throw AgentError.invalidArgument(message)
            }
        }
    }
}

final class PushConstantValidationTests: XCTestCase {
    func testDrawWithoutMaterialConstantsThrows() async throws {
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "DrawValidation", width: 64, height: 64))
            let backend = try EnforcingBackend(window: window)
            let shader = ShaderID("basic_lit")
            let module = try ShaderLibrary.shared.module(for: shader)
            let descriptor = GraphicsPipelineDescriptor(
                label: "test",
                shader: shader,
                vertexLayout: module.vertexLayout,
                colorFormats: [.bgra8Unorm]
            )
            let pipeline = try backend.makePipeline(descriptor)
            let mesh = try backend.registerMesh(vertexBuffer: BufferHandle(), vertexCount: 3, indexBuffer: nil, indexCount: 0, indexFormat: .uint16)

            try backend.beginFrame()
            defer { try? backend.endFrame() }

            var bindings = BindingSet()
            XCTAssertThrowsError(try backend.draw(mesh: mesh, pipeline: pipeline, bindings: bindings, transform: .identity)) { error in
                guard case AgentError.invalidArgument = error else {
                    return XCTFail("Expected invalidArgument error")
                }
            }

            var data = Data(count: module.pushConstantSize)
            data.withUnsafeMutableBytes { buffer in
                if let base = buffer.baseAddress {
                    memset(base, 0, buffer.count)
                }
            }
            bindings.materialConstants = BindingSet.MaterialConstants(data: data)
            XCTAssertNoThrow(try backend.draw(mesh: mesh, pipeline: pipeline, bindings: bindings, transform: .identity))
        }
    }

    func testDispatchWithoutConstantsThrows() async throws {
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "DispatchValidation", width: 64, height: 64))
            let backend = try EnforcingBackend(window: window, computeOverride: 16)
            let descriptor = ComputePipelineDescriptor(label: "computeTest", shader: ShaderID("vector_add"))
            let pipeline = try backend.makeComputePipeline(descriptor)

            try backend.beginFrame()
            defer { try? backend.endFrame() }

            let bindings = BindingSet()
            XCTAssertThrowsError(try backend.dispatchCompute(pipeline, groupsX: 1, groupsY: 1, groupsZ: 1, bindings: bindings)) { error in
                guard case AgentError.invalidArgument = error else {
                    return XCTFail("Expected invalidArgument error")
                }
            }

            var bindingsWithData = BindingSet()
            bindingsWithData.materialConstants = BindingSet.MaterialConstants(data: Data(repeating: 0, count: 16))
            XCTAssertNoThrow(try backend.dispatchCompute(pipeline, groupsX: 1, groupsY: 1, groupsZ: 1, bindings: bindingsWithData))
        }
    }
}
