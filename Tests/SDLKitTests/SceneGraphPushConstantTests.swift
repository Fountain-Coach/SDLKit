import Foundation
import XCTest
@testable import SDLKit

@MainActor
private final class RecordingRenderBackend: RenderBackend {
    private struct BufferResource { var data: Data; var usage: BufferUsage }
    private struct TextureResource { var descriptor: TextureDescriptor; var data: TextureInitialData? }
    private struct MeshResource {
        let vertexBuffer: BufferHandle
        let vertexCount: Int
        let indexBuffer: BufferHandle?
        let indexCount: Int
        let indexFormat: IndexFormat
    }

    private var buffers: [BufferHandle: BufferResource] = [:]
    private var textures: [TextureHandle: TextureResource] = [:]
    private var meshes: [MeshHandle: MeshResource] = [:]
    private var pipelines: [PipelineHandle: GraphicsPipelineDescriptor] = [:]
    private var frameActive = false

    var drawCallCount = 0
    var lastBindings: BindingSet?
    var lastPushConstants: [Float]?

    required init(window: SDLWindow) throws {
        _ = window
    }

    func beginFrame() throws {
        guard !frameActive else { throw AgentError.internalError("beginFrame called twice") }
        frameActive = true
    }

    func endFrame() throws {
        guard frameActive else { throw AgentError.internalError("endFrame without beginFrame") }
        frameActive = false
    }

    func resize(width: Int, height: Int) throws { _ = (width, height) }
    func waitGPU() throws {}

    func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle {
        var data = Data()
        if let bytes, length > 0 {
            data = Data(bytes: bytes, count: length)
        }
        let handle = BufferHandle()
        buffers[handle] = BufferResource(data: data, usage: usage)
        return handle
    }

    func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle {
        let handle = TextureHandle()
        textures[handle] = TextureResource(descriptor: descriptor, data: initialData)
        return handle
    }

    func destroy(_ handle: ResourceHandle) {
        switch handle {
        case .buffer(let h): buffers.removeValue(forKey: h)
        case .texture(let h): textures.removeValue(forKey: h)
        case .pipeline(let h): pipelines.removeValue(forKey: h)
        case .computePipeline: break
        case .mesh(let h): meshes.removeValue(forKey: h)
        }
    }

    func registerMesh(vertexBuffer: BufferHandle,
                      vertexCount: Int,
                      indexBuffer: BufferHandle?,
                      indexCount: Int,
                      indexFormat: IndexFormat) throws -> MeshHandle {
        if let existing = meshes.first(where: { (_, resource) in
            resource.vertexBuffer == vertexBuffer &&
            resource.vertexCount == vertexCount &&
            resource.indexBuffer == indexBuffer &&
            resource.indexCount == indexCount &&
            resource.indexFormat == indexFormat
        })?.key {
            return existing
        }
        let handle = MeshHandle()
        meshes[handle] = MeshResource(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexFormat: indexFormat
        )
        return handle
    }

    func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle {
        let handle = PipelineHandle()
        pipelines[handle] = desc
        return handle
    }

    func draw(mesh: MeshHandle,
              pipeline: PipelineHandle,
              bindings: BindingSet,
              transform: float4x4) throws {
        guard frameActive else { throw AgentError.internalError("draw outside beginFrame/endFrame") }
        guard meshes[mesh] != nil else { throw AgentError.internalError("Unknown mesh handle") }
        guard pipelines[pipeline] != nil else { throw AgentError.internalError("Unknown pipeline handle") }
        _ = transform
        drawCallCount += 1
        lastBindings = bindings
        if let payload = bindings.materialConstants {
            payload.withUnsafeBytes { bytes in
                let floats = bytes.bindMemory(to: Float.self)
                lastPushConstants = Array(floats)
            }
        } else {
            lastPushConstants = nil
        }
    }

    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle {
        _ = desc
        throw AgentError.notImplemented
    }

    func dispatchCompute(_ pipeline: ComputePipelineHandle,
                         groupsX: Int,
                         groupsY: Int,
                         groupsZ: Int,
                         bindings: BindingSet) throws {
        _ = (pipeline, groupsX, groupsY, groupsZ, bindings)
        throw AgentError.notImplemented
    }
}

final class SceneGraphPushConstantTests: XCTestCase {
    func testSceneGraphPushConstantsIncludeBaseColor() async throws {
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "PC", width: 128, height: 128))
            let backend = try RecordingRenderBackend(window: window)
            SceneGraphRenderer.resetPipelineCache()
            let mesh = try MeshFactory.makeLitCube(backend: backend, size: 1.0)
            let baseColor: (Float, Float, Float, Float) = (0.25, 0.5, 0.75, 1.0)
            let light: (Float, Float, Float) = (0.1, -0.2, 0.3)
            let material = Material(
                shader: ShaderID("basic_lit"),
                params: MaterialParams(lightDirection: light, baseColor: baseColor)
            )
            let node = SceneNode(name: "Tinted", mesh: mesh, material: material)
            let root = SceneNode(name: "Root")
            root.addChild(node)
            let scene = Scene(root: root, camera: nil, lightDirection: (0.3, -0.5, 0.8))

            try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend)

            XCTAssertEqual(backend.drawCallCount, 1)
            guard let push = backend.lastPushConstants else {
                XCTFail("Expected push constants to be recorded")
                return
            }
            XCTAssertEqual(push.count, 24)
            let recordedLight = Array(push[16..<20])
            XCTAssertEqual(recordedLight[0], light.0, accuracy: 1e-6)
            XCTAssertEqual(recordedLight[1], light.1, accuracy: 1e-6)
            XCTAssertEqual(recordedLight[2], light.2, accuracy: 1e-6)
            let recordedBase = Array(push[20..<24])
            XCTAssertEqual(recordedBase[0], baseColor.0, accuracy: 1e-6)
            XCTAssertEqual(recordedBase[1], baseColor.1, accuracy: 1e-6)
            XCTAssertEqual(recordedBase[2], baseColor.2, accuracy: 1e-6)
            XCTAssertEqual(recordedBase[3], baseColor.3, accuracy: 1e-6)
        }
    }

    func testSceneGraphBindsMaterialTexture() async throws {
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "Tex", width: 128, height: 128))
            let backend = try RecordingRenderBackend(window: window)
            SceneGraphRenderer.resetPipelineCache()
            let mesh = try MeshFactory.makeLitCube(backend: backend, size: 1.0)
            let pixels: [UInt8] = [
                255,   0,   0, 255,
                  0, 255,   0, 255,
                  0,   0, 255, 255,
                255, 255, 255, 255
            ]
            let descriptor = TextureDescriptor(width: 2, height: 2, mipLevels: 1, format: .rgba8Unorm, usage: .shaderRead)
            let initialData = TextureInitialData(mipLevelData: [Data(pixels)])
            let textureHandle = try backend.createTexture(descriptor: descriptor, initialData: initialData)
            let material = Material(shader: ShaderID("basic_lit"), params: .init(texture: textureHandle))
            let node = SceneNode(name: "Textured", mesh: mesh, material: material)
            let root = SceneNode(name: "Root")
            root.addChild(node)
            let scene = Scene(root: root, camera: nil, lightDirection: (0.0, 0.0, -1.0))

            try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend)

            guard let bindings = backend.lastBindings else {
                XCTFail("Expected bindings to be recorded")
                return
            }
            let boundTexture: TextureHandle? = bindings.value(for: 10, as: TextureHandle.self)
            XCTAssertEqual(boundTexture, textureHandle)
        }
    }
}
