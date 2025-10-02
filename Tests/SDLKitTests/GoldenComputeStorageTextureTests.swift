import XCTest
@testable import SDLKit

final class GoldenComputeStorageTextureTests: XCTestCase {
    private func shouldRunGolden() -> Bool {
        ProcessInfo.processInfo.environment["SDLKIT_GOLDEN"] == "1"
    }

    private func runGoldenComputeTest(backendOverride: String, backendKey: String) async throws {
        guard shouldRunGolden() else {
            throw XCTSkip("Golden compute test disabled; set SDLKIT_GOLDEN=1 to enable")
        }

        do {
            try await MainActor.run {
                let window = SDLWindow(config: .init(title: "GoldenCompute", width: 160, height: 120))
                try window.open()
                defer { window.close() }
                try window.show()

                let backend = try RenderBackendFactory.makeBackend(window: window, override: backendOverride)
                guard let capturable = backend as? GoldenImageCapturable else {
                    throw XCTSkip("Backend does not support capture hashing")
                }

                let computePipeline = try backend.makeComputePipeline(
                    ComputePipelineDescriptor(label: "compute_storage", shader: ShaderID("compute_storage_texture"))
                )

                let storageTexture = try backend.createTexture(
                    descriptor: TextureDescriptor(width: 40, height: 30, mipLevels: 1, format: .rgba8Unorm, usage: .shaderWrite),
                    initialData: nil
                )

                // Depth texture exercises depth target allocation alongside color capture.
                _ = try backend.createTexture(
                    descriptor: TextureDescriptor(width: window.config.width,
                                                   height: window.config.height,
                                                   mipLevels: 1,
                                                   format: .depth32Float,
                                                   usage: .depthStencil),
                    initialData: nil
                )

                let module = try ShaderLibrary.shared.module(for: ShaderID("unlit_triangle"))
                let pipeline = try backend.makePipeline(
                    GraphicsPipelineDescriptor(label: "golden_sample_pipeline",
                                               shader: ShaderID("basic_lit"),
                                               vertexLayout: module.vertexLayout,
                                               colorFormats: [.bgra8Unorm],
                                               depthFormat: .depth32Float)
                )

                let vertices: [Float] = [
                    -1, -1, 0, 1, 0, 0,
                     0,  1, 0, 0, 1, 0,
                     1, -1, 0, 0, 0, 1
                ]
                let vertexBuffer = try vertices.withUnsafeBytes { buffer in
                    try backend.createBuffer(bytes: buffer.baseAddress, length: buffer.count, usage: .vertex)
                }
                let mesh = try backend.registerMesh(vertexBuffer: vertexBuffer,
                                                    vertexCount: 3,
                                                    indexBuffer: nil,
                                                    indexCount: 0,
                                                    indexFormat: .uint16)

                try backend.beginFrame()
                var frameEnded = false
                defer {
                    if !frameEnded {
                        try? backend.endFrame()
                    }
                }

                var computeBindings = BindingSet()
                computeBindings.setTexture(storageTexture, at: 0)
                try backend.dispatchCompute(computePipeline,
                                            groupsX: 5,
                                            groupsY: 3,
                                            groupsZ: 1,
                                            bindings: computeBindings)

                capturable.requestCapture()

                var bindings = BindingSet()
                bindings.setTexture(storageTexture, at: 10)
                if module.pushConstantSize > 0 {
                    bindings.materialConstants = BindingSet.MaterialConstants(data: Data(repeating: 0, count: module.pushConstantSize))
                }

                try backend.draw(mesh: mesh,
                                  pipeline: pipeline,
                                  bindings: bindings,
                                  transform: .identity)

                try backend.endFrame()
                frameEnded = true

                let hash = try capturable.takeCaptureHash()
                let key = GoldenRefs.key(backend: backendKey,
                                         width: window.config.width,
                                         height: window.config.height,
                                         material: "compute_storage_texture")
                if let expected = GoldenRefs.getExpected(for: key), !expected.isEmpty {
                    XCTAssertEqual(hash, expected, "Golden hash mismatch for \(key)")
                } else {
                    print("Golden compute hash: \(hash) key=\(key)")
                    if ProcessInfo.processInfo.environment["SDLKIT_GOLDEN_WRITE"] == "1" {
                        GoldenRefs.setExpected(hash, for: key)
                    }
                }
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch AgentError.sdlUnavailable {
            throw XCTSkip("SDL unavailable; skipping golden compute test")
        } catch AgentError.notImplemented {
            throw XCTSkip("Required shader artifacts unavailable for golden compute test")
        }
    }

    func testComputeStorageTextureMetal() async throws {
        #if os(macOS)
        try await runGoldenComputeTest(backendOverride: "metal", backendKey: "metal")
        #else
        throw XCTSkip("Metal golden compute test only runs on macOS")
        #endif
    }

    func testComputeStorageTextureVulkan() async throws {
        #if os(Linux)
        setenv("SDLKIT_VK_VALIDATION_CAPTURE", "1", 1)
        setenv("SDLKIT_VK_VALIDATION", "1", 1)
        try await runGoldenComputeTest(backendOverride: "vulkan", backendKey: "vulkan")
        #else
        throw XCTSkip("Vulkan golden compute test only runs on Linux")
        #endif
    }

    func testComputeStorageTextureD3D12() async throws {
        #if os(Windows)
        try await runGoldenComputeTest(backendOverride: "d3d12", backendKey: "d3d12")
        #else
        throw XCTSkip("D3D12 golden compute test only runs on Windows")
        #endif
    }
}
