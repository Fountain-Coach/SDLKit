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
            let tintedBaseColor: (Float, Float, Float, Float) = (0.6, 0.45, 0.9, 1.0)
            let material = Material(
                shader: ShaderID("basic_lit"),
                params: .init(lightDirection: (0.3, -0.5, 0.8), baseColor: tintedBaseColor)
            )
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
            let key = GoldenRefs.key(backend: "metal", width: 256, height: 256)
            if let expected = GoldenRefs.getExpected(for: key), !expected.isEmpty {
                XCTAssertEqual(hash, expected, "Golden hash mismatch for \(key)")
            } else {
                print("Golden hash: \(hash) key=\(key)")
                if ProcessInfo.processInfo.environment["SDLKIT_GOLDEN_WRITE"] == "1" {
                    GoldenRefs.setExpected(hash, for: key)
                }
            }
        }
        #else
        throw XCTSkip("Golden image test only supported on macOS in this harness")
        #endif
    }

    func testSceneGraphGoldenHash_Vulkan() async throws {
        #if os(Linux)
        setenv("SDLKIT_VK_VALIDATION_CAPTURE", "1", 1)
        setenv("SDLKIT_VK_VALIDATION", "1", 1)
        let shouldRun = ProcessInfo.processInfo.environment["SDLKIT_GOLDEN"]
        guard shouldRun == "1" else { throw XCTSkip("Golden test disabled") }
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "GoldenTestVK", width: 256, height: 256))
            try window.open(); defer { window.close() }; try window.show()
            let backend = try RenderBackendFactory.makeBackend(window: window, override: "vulkan")
            guard let cap = backend as? GoldenImageCapturable else { throw XCTSkip("No capture") }
            guard let vkBackend = backend as? VulkanRenderBackend else { throw XCTSkip("Backend not VulkanRenderBackend") }
            let pixels: [UInt8] = [
                255,   0,   0, 255,
                  0, 255,   0, 255,
                  0,   0, 255, 255,
                255, 255, 255, 255
            ]
            let textureDescriptor = TextureDescriptor(width: 2, height: 2, format: .rgba8Unorm, usage: .shaderRead)
            let textureData = TextureInitialData(mipLevelData: [Data(pixels)])
            let textureHandle = try backend.createTexture(descriptor: textureDescriptor, initialData: textureData)
            let mesh = try MeshFactory.makeLitCube(backend: backend, size: 1.1)
            let tintedBaseColor: (Float, Float, Float, Float) = (0.6, 0.45, 0.9, 1.0)
            let material = Material(
                shader: ShaderID("basic_lit"),
                params: .init(lightDirection: (0.3,-0.5,0.8), baseColor: tintedBaseColor, texture: textureHandle)
            )
            let node = SceneNode(name: "Cube", transform: .identity, mesh: mesh, material: material)
            let root = SceneNode(name: "Root"); root.addChild(node)
            let scene = Scene(root: root, camera: .identity(aspect: 1.0), lightDirection: (0.3,-0.5,0.8))
            cap.requestCapture()
            try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend)
            let hash = try cap.takeCaptureHash()
            let key = GoldenRefs.key(backend: "vulkan", width: 256, height: 256)
            let validationMessages = vkBackend.takeValidationMessages()
            XCTAssertTrue(validationMessages.isEmpty, "Vulkan validation warnings: \(validationMessages)")
            if let expected = GoldenRefs.getExpected(for: key), !expected.isEmpty { XCTAssertEqual(hash, expected, "Golden hash mismatch for \(key)") } else { print("VK Golden hash: \(hash) key=\(key)"); if ProcessInfo.processInfo.environment["SDLKIT_GOLDEN_WRITE"] == "1" { GoldenRefs.setExpected(hash, for: key) } }
        }
        #else
        throw XCTSkip("Vulkan golden test only on Linux")
        #endif
    }

    func testSceneGraphGoldenHash_D3D12() async throws {
        #if os(Windows)
        let shouldRun = ProcessInfo.processInfo.environment["SDLKIT_GOLDEN"]
        guard shouldRun == "1" else { throw XCTSkip("Golden test disabled") }
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "GoldenTestDX12", width: 256, height: 256))
            try window.open(); defer { window.close() }; try window.show()
            let backend = try RenderBackendFactory.makeBackend(window: window, override: "d3d12")
            guard let cap = backend as? GoldenImageCapturable else { throw XCTSkip("No capture") }
            let mesh = try MeshFactory.makeLitCube(backend: backend, size: 1.1)
            let material = Material(shader: ShaderID("basic_lit"), params: .init(lightDirection: (0.3,-0.5,0.8), baseColor: (1,1,1,1)))
            let node = SceneNode(name: "Cube", transform: .identity, mesh: mesh, material: material)
            let root = SceneNode(name: "Root"); root.addChild(node)
            let scene = Scene(root: root, camera: .identity(aspect: 1.0), lightDirection: (0.3,-0.5,0.8))
            cap.requestCapture()
            try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend)
            let hash = try cap.takeCaptureHash()
            let key = GoldenRefs.key(backend: "d3d12", width: 256, height: 256)
            if let expected = GoldenRefs.getExpected(for: key), !expected.isEmpty { XCTAssertEqual(hash, expected, "Golden hash mismatch for \(key)") } else { print("DX12 Golden hash: \(hash) key=\(key)"); if ProcessInfo.processInfo.environment["SDLKIT_GOLDEN_WRITE"] == "1" { GoldenRefs.setExpected(hash, for: key) } }
        }
        #else
        throw XCTSkip("D3D12 golden test only on Windows")
        #endif
    }
}
