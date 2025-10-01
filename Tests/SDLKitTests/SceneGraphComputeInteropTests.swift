import XCTest
@testable import SDLKit
#if canImport(CSDL3)
import CSDL3
#endif

final class SceneGraphComputeInteropTests: XCTestCase {
    func testSceneGraphComputeInteropFrames() async throws {
        do {
            try await MainActor.run {
#if canImport(CSDL3)
                guard SDLKitStub_IsActive() != 0 else {
                    throw XCTSkip("SDL3 stub unavailable; compute interop test requires stub backend")
                }
#endif
                let window = SDLWindow(config: .init(title: "ComputeInterop", width: 256, height: 256))
                try window.open()
                defer { window.close() }
                try window.show()

                let backend = try RenderBackendFactory.makeBackend(window: window)
                guard let (computeNode, resources) = try? SceneGraphComputeInterop.makeNode(backend: backend) else {
                    throw XCTSkip("scenegraph_wave compute shader unavailable on this configuration")
                }

                let root = SceneNode(name: "Root")
                root.addChild(computeNode)
                let aspect = Float(window.config.width) / Float(max(1, window.config.height))
                let scene = Scene(root: root, camera: Camera.identity(aspect: aspect))

                for _ in 0..<180 {
                    try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend, beforeRender: {
                        try SceneGraphComputeInterop.dispatchCompute(backend: backend, resources: resources)
                    })
                }
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch AgentError.sdlUnavailable {
            throw XCTSkip("SDL unavailable; skipping compute interop test")
        } catch AgentError.internalError(let message) where message.contains("SDLKit SDL3 stub") {
            throw XCTSkip(message)
        } catch AgentError.notImplemented {
            throw XCTSkip("scenegraph_wave compute shader unavailable on this configuration")
        }
    }
}
