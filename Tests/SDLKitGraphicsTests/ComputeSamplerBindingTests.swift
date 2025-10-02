import Foundation
import XCTest
@testable import SDLKit

@MainActor
private final class SamplerTrackingBackend: RenderBackend {
    private var frameActive = false
    private let window: SDLWindow
    private let requiredSamplerSlots: Set<Int>
    private var samplerDescriptors: [SamplerHandle: SamplerDescriptor] = [:]
    private var computeRequirements: [ComputePipelineHandle: Set<Int>] = [:]
    private(set) var lastBoundSamplers: [Int: SamplerDescriptor] = [:]

    private init(baseWindow: SDLWindow, requiredSlots: Set<Int>) {
        self.window = baseWindow
        self.requiredSamplerSlots = requiredSlots
    }

    convenience init(window: SDLWindow, requiredSlots: Set<Int> = [1]) throws {
        self.init(baseWindow: window, requiredSlots: requiredSlots)
    }

    required convenience init(window: SDLWindow) throws {
        try self.init(window: window, requiredSlots: [1])
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
        let handle = SamplerHandle()
        samplerDescriptors[handle] = descriptor
        return handle
    }

    func destroy(_ handle: ResourceHandle) {
        switch handle {
        case .sampler(let sampler):
            samplerDescriptors.removeValue(forKey: sampler)
        default:
            break
        }
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
        _ = desc
        return PipelineHandle()
    }

    func draw(mesh: MeshHandle,
              pipeline: PipelineHandle,
              bindings: BindingSet,
              transform: float4x4) throws {
        _ = (mesh, pipeline, bindings, transform)
    }

    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle {
        _ = desc
        let handle = ComputePipelineHandle()
        computeRequirements[handle] = requiredSamplerSlots
        return handle
    }

    func dispatchCompute(_ pipeline: ComputePipelineHandle,
                         groupsX: Int,
                         groupsY: Int,
                         groupsZ: Int,
                         bindings: BindingSet) throws {
        guard frameActive else { throw AgentError.internalError("dispatchCompute outside beginFrame/endFrame") }
        _ = (groupsX, groupsY, groupsZ)
        guard let expectedSlots = computeRequirements[pipeline] else {
            throw AgentError.internalError("Unknown compute pipeline")
        }

        var bound: [Int: SamplerDescriptor] = [:]
        for slot in expectedSlots {
            guard let handle = bindings.sampler(at: slot) else {
                throw AgentError.invalidArgument("Missing sampler for slot \(slot)")
            }
            guard let descriptor = samplerDescriptors[handle] else {
                throw AgentError.invalidArgument("Unknown sampler handle for slot \(slot)")
            }
            bound[slot] = descriptor
        }
        lastBoundSamplers = bound
    }
}

final class ComputeSamplerBindingTests: XCTestCase {
    func testDispatchComputeWithSamplerSucceeds() async throws {
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "SamplerDispatch", width: 32, height: 32))
            let backend = try SamplerTrackingBackend(window: window, requiredSlots: [2])
            let descriptor = SamplerDescriptor(
                label: "NearestClamp",
                minFilter: .nearest,
                magFilter: .nearest,
                mipFilter: .notMipmapped,
                addressModeU: .clampToEdge,
                addressModeV: .clampToEdge,
                addressModeW: .mirrorRepeat,
                lodMinClamp: 0,
                lodMaxClamp: 4,
                maxAnisotropy: 1
            )
            let sampler = try backend.createSampler(descriptor: descriptor)
            let pipeline = try backend.makeComputePipeline(ComputePipelineDescriptor(label: "requiresSampler", shader: ShaderID("sampled_compute")))

            try backend.beginFrame()
            defer { try? backend.endFrame() }

            var bindings = BindingSet()
            bindings.setSampler(sampler, at: 2)

            XCTAssertNoThrow(try backend.dispatchCompute(pipeline, groupsX: 1, groupsY: 1, groupsZ: 1, bindings: bindings))

            let boundDescriptor = try XCTUnwrap(backend.lastBoundSamplers[2])
            XCTAssertEqual(boundDescriptor.minFilter, .nearest)
            XCTAssertEqual(boundDescriptor.magFilter, .nearest)
            XCTAssertEqual(boundDescriptor.addressModeU, .clampToEdge)
            XCTAssertEqual(boundDescriptor.addressModeV, .clampToEdge)
            XCTAssertEqual(boundDescriptor.addressModeW, .mirrorRepeat)
            XCTAssertEqual(boundDescriptor.mipFilter, .notMipmapped)
        }
    }
}
