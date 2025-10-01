import XCTest
@testable import SDLKit

final class GoldenImageTests: XCTestCase {
    func testSceneGraphGoldenHash_Metal() async throws {
        #if os(macOS)
        // Only run if explicitly enabled
        let shouldRun = ProcessInfo.processInfo.environment["SDLKIT_GOLDEN"]
        guard shouldRun == "1" else {
            throw XCTSkip("Golden image test disabled; set SDLKIT_GOLDEN=1 to enable")
        }

        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "GoldenTest", width: 256, height: 256))
            try window.open()
            defer { window.close() }
            try window.show()

            let backend = try RenderBackendFactory.makeBackend(window: window, override: "metal")
            guard let cap = backend as? GoldenImageCapturable else {
                throw XCTSkip("Backend not capture-capable")
            }

            // Build a simple lit scene (cube) with fixed light & camera
            let mesh = try MeshFactory.makeLitCube(backend: backend, size: 1.2)
            let material = Material(shader: ShaderID("basic_lit"), params: .init(lightDirection: (0.3, -0.5, 0.8), baseColor: (1,1,1,1)))
            let node = SceneNode(name: "Cube", transform: .identity, mesh: mesh, material: material)
            let root = SceneNode(name: "Root")
            root.addChild(node)
            let aspect: Float = Float(window.config.width) / Float(max(1, window.config.height))
            let cam = Camera(view: float4x4.lookAt(eye: (0,0,2.2), center: (0,0,0), up: (0,1,0)),
                             projection: float4x4.perspective(fovYRadians: .pi/3, aspect: aspect, zNear: 0.1, zFar: 100))
            let scene = Scene(root: root, camera: cam, lightDirection: (0.3, -0.5, 0.8))

            cap.requestCapture()
            try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend)
            let hash = try cap.takeCaptureHash()

            if let expected = ProcessInfo.processInfo.environment["SDLKIT_GOLDEN_REF"], !expected.isEmpty {
                XCTAssertEqual(hash, expected, "Golden hash mismatch")
            } else {
                print("Golden hash: \(hash)")
            }
        }
        #else
        throw XCTSkip("Golden image test only supported on macOS in this harness")
        #endif
    }
}

