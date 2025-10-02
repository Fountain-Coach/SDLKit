#if os(Windows)
import XCTest
import Foundation
import Direct3D12
@testable import SDLKit

@MainActor
final class D3D12DeviceLossRecoveryTests: XCTestCase {
    func testDeviceLossRecoveryRestoresResources() async throws {
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "DeviceLoss", width: 128, height: 128))
            let backend = try D3D12RenderBackend(window: window)

            var events: [RenderBackendDeviceEvent] = []
            backend.deviceEventHandler = { event in
                events.append(event)
            }

            #if DEBUG
            let logCapture = SDLLogCapture()
            defer { logCapture.stop() }
            #endif

            let vertexModule = try ShaderLibrary.shared.module(for: ShaderID("unlit_triangle"))
            let vertexStride = vertexModule.vertexLayout.stride
            let vertexCount = 3
            var vertexData = Data(count: vertexStride * vertexCount)
            vertexData.withUnsafeMutableBytes { bytes in
                guard let base = bytes.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
                // position + color
                let values: [Float] = [
                    -0.5, -0.5, 0.0, 1.0, 0.0, 0.0,
                     0.0,  0.5, 0.0, 0.0, 1.0, 0.0,
                     0.5, -0.5, 0.0, 0.0, 0.0, 1.0
                ]
                for (index, value) in values.enumerated() {
                    base[index] = value
                }
            }
            let vertexBuffer = try backend.createBuffer(bytes: vertexData.withUnsafeBytes { $0.baseAddress },
                                                         length: vertexData.count,
                                                         usage: .vertex)
            let meshHandle = try backend.registerMesh(vertexBuffer: vertexBuffer,
                                                       vertexCount: vertexCount,
                                                       indexBuffer: nil,
                                                       indexCount: 0,
                                                       indexFormat: .uint16)

            let textureBytes = Data(repeating: 0x7F, count: 64 * 64 * 4)
            let textureDesc = TextureDescriptor(width: 64,
                                                height: 64,
                                                mipLevels: 1,
                                                format: .rgba8Unorm,
                                                usage: .shaderRead)
            let texture = try backend.createTexture(descriptor: textureDesc,
                                                    initialData: TextureInitialData(mipLevelData: [textureBytes]))
            let sampler = try backend.createSampler(descriptor: SamplerDescriptor(label: "Linear"))

            let pipelineDesc = GraphicsPipelineDescriptor(label: "DeviceLossPipeline",
                                                          shader: vertexModule.id,
                                                          vertexLayout: vertexModule.vertexLayout,
                                                          colorFormats: [.bgra8Unorm],
                                                          depthFormat: .depth32Float)
            _ = try backend.makePipeline(pipelineDesc)

#if DEBUG
            let baselineInventory = backend.debugResourceInventory()
#endif

            try backend.beginFrame()
            backend.debugSimulateDeviceRemoval()
            XCTAssertThrowsError(try backend.endFrame()) { error in
                guard case AgentError.deviceLost = error else {
                    XCTFail("Expected AgentError.deviceLost, received \(error)")
                    return
                }
            }

            XCTAssertTrue(events.contains { if case .willReset = $0 { return true } else { return false } })
            XCTAssertTrue(events.contains { if case .didReset = $0 { return true } else { return false } })
#if DEBUG
            XCTAssertFalse(events.contains { if case .resetFailed = $0 { return true } else { return false } })
            XCTAssertNotNil(backend.debugTextureState(for: texture))
            let recoveredInventory = backend.debugResourceInventory()
            XCTAssertEqual(recoveredInventory, baselineInventory)
            XCTAssertTrue(logCapture.entries.contains(where: { entry in
                entry.component == "SDLKit.Graphics.D3D12" && entry.message.contains("device removal")
            }))
            XCTAssertTrue(logCapture.entries.contains(where: { entry in
                entry.component == "SDLKit.Graphics.D3D12" && entry.message.contains("Device reset completed after loss")
            }))
            XCTAssertNotNil(backend.debugSamplerDescriptor(for: sampler))
#else
            _ = texture
            _ = sampler
#endif

            try backend.beginFrame()
            try backend.endFrame()

            try backend.resize(width: 196, height: 196)

#if DEBUG
            let postResizeInventory = backend.debugResourceInventory()
            XCTAssertEqual(postResizeInventory, baselineInventory)
#endif

            _ = try backend.registerMesh(vertexBuffer: vertexBuffer,
                                         vertexCount: vertexCount,
                                         indexBuffer: nil,
                                         indexCount: 0,
                                         indexFormat: .uint16)
            _ = try backend.makePipeline(pipelineDesc)
            _ = meshHandle

            try backend.beginFrame()
            try backend.endFrame()
        }
    }
}
#endif
