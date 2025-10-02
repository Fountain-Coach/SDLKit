#if os(Linux) && canImport(VulkanMinimal)
import XCTest
import Foundation
import VulkanMinimal
@testable import SDLKit

@MainActor
final class VulkanDeviceLossRecoveryTests: XCTestCase {
    func testDeviceLossRecoveryRestoresResources() async throws {
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "VulkanDeviceLoss", width: 160, height: 160))
            let backend = try VulkanRenderBackend(window: window)

            var events: [RenderBackendDeviceEvent] = []
            backend.deviceEventHandler = { event in
                events.append(event)
            }

            let module = try ShaderLibrary.shared.module(for: ShaderID("unlit_triangle"))
            let vertexStride = module.vertexLayout.stride
            let vertexCount = 3
            var vertexData = Data(count: vertexStride * vertexCount)
            vertexData.withUnsafeMutableBytes { bytes in
                guard let base = bytes.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
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

            let textureDescriptor = TextureDescriptor(width: 32,
                                                       height: 32,
                                                       mipLevels: 1,
                                                       format: .rgba8Unorm,
                                                       usage: .shaderRead)
            let textureData = Data(repeating: 0xAB, count: textureDescriptor.width * textureDescriptor.height * 4)
            let textureHandle = try backend.createTexture(descriptor: textureDescriptor,
                                                           initialData: TextureInitialData(mipLevelData: [textureData]))
            let sampler = try backend.createSampler(descriptor: SamplerDescriptor(label: "Linear"))

            let pipelineDescriptor = GraphicsPipelineDescriptor(label: "VulkanDeviceLoss",
                                                                shader: module.id,
                                                                vertexLayout: module.vertexLayout,
                                                                colorFormats: [.bgra8Unorm],
                                                                depthFormat: .depth32Float)
            _ = try backend.makePipeline(pipelineDescriptor)

            try backend.beginFrame()
            // The GraphicsAgent risk guidance calls for centralized recovery; we drive the synthetic
            // loss path here so contributors can validate reset handling without removing hardware.
            backend.debugSimulateDeviceLoss()
            XCTAssertThrowsError(try backend.endFrame()) { error in
                guard case AgentError.deviceLost = error else {
                    XCTFail("Expected AgentError.deviceLost, received \(error)")
                    return
                }
            }

            XCTAssertTrue(events.contains { if case .willReset = $0 { return true } else { return false } })
            XCTAssertTrue(events.contains { if case .didReset = $0 { return true } else { return false } })

            XCTAssertEqual(backend.debugBufferLength(for: vertexBuffer), vertexData.count)
            XCTAssertEqual(backend.debugTextureDescriptor(for: textureHandle)?.width, textureDescriptor.width)
            XCTAssertGreaterThanOrEqual(backend.debugTextureCount(), 1)

            _ = VulkanRenderBackend.drainCapturedValidationMessages()

            try backend.beginFrame()
            try backend.endFrame()

            _ = try backend.registerMesh(vertexBuffer: vertexBuffer,
                                         vertexCount: vertexCount,
                                         indexBuffer: nil,
                                         indexCount: 0,
                                         indexFormat: .uint16)
            _ = try backend.makePipeline(pipelineDescriptor)
            _ = meshHandle
            _ = sampler
        }
    }
}
#endif
