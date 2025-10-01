import Foundation
import SDLKit
#if canImport(SDLKitTTF)
import SDLKitTTF
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(VulkanMinimal)
import VulkanMinimal
#endif

#if HEADLESS_CI
@main
@MainActor
struct DemoApp {
    static func main() {
        print("SDLKitDemo: skipped (HEADLESS_CI set)")
    }
}
#elseif os(macOS) || os(Windows) || os(Linux)
@main
struct DemoApp {
    private enum DemoPlatform: String {
        case macOS
        case windows
        case linux
    }

    static func main() {
        guard SDLKitConfig.guiEnabled else {
            print("GUI disabled. Set SDLKIT_GUI_ENABLED=1 to enable.")
            return
        }

        #if os(macOS)
        let platform: DemoPlatform = .macOS
        #elseif os(Windows)
        let platform: DemoPlatform = .windows
        #elseif os(Linux)
        let platform: DemoPlatform = .linux
        #else
        let platform: DemoPlatform = .macOS
        #endif

        let agent = SDLKitGUIAgent()
        do {
            try runDemo(on: platform, agent: agent)
            print("SDLKitDemo: completed smoke test for \(platform.rawValue)")
        } catch AgentError.sdlUnavailable {
            print("SDL unavailable on this build. Install SDL3 to run the demo.")
        } catch {
            print("SDLKitDemo error: \(error)")
        }
    }

    @MainActor
    private static func runDemo(on platform: DemoPlatform, agent: SDLKitGUIAgent) throws {
        if SDLKitConfig.demoForceLegacy2D {
            try runLegacy2DDemo(on: platform, agent: agent)
            return
        }

        do {
            try runSceneGraphDemo(on: platform)
        } catch {
            print("Triangle demo failed (\(error)); falling back to legacy 2D showcase")
            try runLegacy2DDemo(on: platform, agent: agent)
        }
    }

    @MainActor
    private static func runLegacy2DDemo(on platform: DemoPlatform, agent: SDLKitGUIAgent) throws {
        let windowId = try agent.openWindow(title: "SDLKit Demo", width: 640, height: 480)
        defer { agent.closeWindow(windowId: windowId) }

        try showcaseDrawing(windowId: windowId, agent: agent)
        try logNativeHandles(for: platform, windowId: windowId, agent: agent)

        let start = Date()
        while Date().timeIntervalSince(start) < 2.0 {
            _ = try agent.captureEvent(windowId: windowId, timeoutMs: 100)
        }
    }

    @MainActor
    private static func logNativeHandles(for platform: DemoPlatform, windowId: Int, agent: SDLKitGUIAgent) throws {
        let handles = try agent.nativeHandles(windowId: windowId)
        switch platform {
        case .macOS:
            #if canImport(QuartzCore)
            if let layer = handles.metalLayer as? CAMetalLayer {
                let nameDescription: String
                if let name = layer.name {
                    if let stringName = name as? String {
                        nameDescription = stringName
                    } else {
                        nameDescription = String(describing: name)
                    }
                } else {
                    nameDescription = "nil"
                }
                print("SDLKitDemo: CAMetalLayer => class=\(String(describing: type(of: layer))) name=\(nameDescription)")
            } else {
                print("SDLKitDemo: CAMetalLayer unavailable on macOS")
            }
            #else
            print("SDLKitDemo: QuartzCore unavailable on this build")
            #endif
        case .windows:
            if let hwnd = handles.win32HWND {
                let value = UInt(bitPattern: hwnd)
                let formatted = String(format: "0x%016llX", UInt64(value))
                print("SDLKitDemo: Win32 HWND => \(formatted)")
            } else {
                print("SDLKitDemo: Win32 HWND unavailable")
            }
        case .linux:
            #if canImport(VulkanMinimal)
            var instance = VulkanMinimalInstance()
            let result = VulkanMinimalCreateInstance(&instance)
            guard result == VK_SUCCESS, let vkInstance = instance.handle else {
                print("SDLKitDemo: Vulkan instance creation failed (code=\(result))")
                VulkanMinimalDestroyInstance(&instance)
                return
            }
            defer { VulkanMinimalDestroyInstance(&instance) }
            let surface = try handles.createVulkanSurface(instance: vkInstance)
            let formattedSurface = String(format: "0x%016llX", UInt64(surface))
            print("SDLKitDemo: Vulkan surface => \(formattedSurface)")
            #else
            print("SDLKitDemo: Vulkan headers unavailable; skipping surface creation")
            #endif
        }
    }

    @MainActor
    private static func runTriangleDemo(on platform: DemoPlatform) throws {
        let window = SDLWindow(config: .init(title: "SDLKit Triangle", width: 640, height: 480))
        try window.open()
        defer { window.close() }
        try window.show()

        let backend = try RenderBackendFactory.makeBackend(window: window)
        defer { try? backend.waitGPU() }

        let surface = try RenderSurface(window: window)
        logNativeHandles(for: platform, surface: surface)

        struct Vertex {
            var position: (Float, Float, Float)
            var color: (Float, Float, Float)
        }

        let vertices: [Vertex] = [
            Vertex(position: (-0.6, -0.5, 0), color: (1, 0, 0)),
            Vertex(position: (0.0, 0.6, 0), color: (0, 1, 0)),
            Vertex(position: (0.6, -0.5, 0), color: (0, 0, 1))
        ]

        let vertexBuffer = try vertices.withUnsafeBytes { buffer -> BufferHandle in
            try backend.createBuffer(bytes: buffer.baseAddress, length: buffer.count, usage: .vertex)
        }

        let mesh = MeshHandle()
        if let stub = backend as? StubRenderBackend {
            stub.register(mesh: mesh, vertexBuffer: vertexBuffer, vertexCount: vertices.count)
        }

        let shaderModule = try ShaderLibrary.shared.module(for: ShaderID("unlit_triangle"))
        let vertexLayout = shaderModule.vertexLayout

        let pipeline = try backend.makePipeline(
            GraphicsPipelineDescriptor(
                label: "unlit_triangle",
                shader: shaderModule.id,
                vertexLayout: vertexLayout,
                colorFormats: [.bgra8Unorm]
            )
        )

        for _ in 0..<3 {
            try backend.beginFrame()
            let bindings = BindingSet(slots: [0: vertexBuffer])
            try backend.draw(
                mesh: mesh,
                pipeline: pipeline,
                bindings: bindings,
                pushConstants: nil,
                transform: float4x4.identity
            )
            try backend.endFrame()
            Thread.sleep(forTimeInterval: 1.0 / 30.0)
        }
    }

    @MainActor
    private static func runSceneGraphDemo(on platform: DemoPlatform) throws {
        let window = SDLWindow(config: .init(title: "SDLKit SceneGraph", width: 640, height: 480))
        try window.open()
        defer { window.close() }
        try window.show()

        let backend = try RenderBackendFactory.makeBackend(window: window)
        defer { try? backend.waitGPU() }

        // Unlit triangle vertex buffer (pos.xyz + color.xyz)
        struct UnlitVertex { var position: (Float, Float, Float); var color: (Float, Float, Float) }
        let unlitVerts: [UnlitVertex] = [
            .init(position: (-0.6, -0.5, 0), color: (1, 0, 0)),
            .init(position: ( 0.0,  0.6, 0), color: (0, 1, 0)),
            .init(position: ( 0.6, -0.5, 0), color: (0, 0, 1))
        ]
        let unlitVB = try unlitVerts.withUnsafeBytes { buf in
            try backend.createBuffer(bytes: buf.baseAddress, length: buf.count, usage: .vertex)
        }

        // Lit mesh: use primitive cube with normals
        let litMesh = try MeshFactory.makeLitCube(backend: backend, size: 1.0)

        // Create scene graph with two nodes/materials
        let unlitMesh = Mesh(vertexBuffer: unlitVB, vertexCount: unlitVerts.count)
        let unlitMat = Material(shader: ShaderID("unlit_triangle"))
        let unlitNode = SceneNode(name: "Unlit", transform: float4x4.translation(x: -0.8, y: 0, z: 0), mesh: unlitMesh, material: unlitMat)

        let litMat = Material(shader: ShaderID("basic_lit"), params: .init(lightDirection: (0.3, -0.5, 0.8)))
        let litNode = SceneNode(name: "Lit", transform: float4x4.translation(x: 0.8, y: 0, z: 0), mesh: litMesh, material: litMat)

        let root = SceneNode(name: "Root")
        root.addChild(unlitNode)
        root.addChild(litNode)

        // Add a simple perspective camera
        let aspect: Float = Float(window.config.width) / Float(max(1, window.config.height))
        let view = float4x4.lookAt(eye: (0, 0, 2), center: (0, 0, 0), up: (0, 1, 0))
        let proj = float4x4.perspective(fovYRadians: .pi/3, aspect: aspect, zNear: 0.1, zFar: 100.0)
        var scene = Scene(root: root, camera: Camera(view: view, projection: proj))
        // Optional: override light direction from SecretStore if present
        if let data = try? Secrets.retrieve(key: "light_dir"), let s = data.flatMap({ String(data: $0, encoding: .utf8) }) {
            let parts = s.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 3 { scene.lightDirection = (parts[0], parts[1], parts[2]) }
        }

        // Animate rotation for a few frames
        let frames = 180
        for i in 0..<frames {
            let t = Float(i) * (Float.pi / 90.0)
            unlitNode.localTransform = float4x4.rotationZ(t) * float4x4.translation(x: -0.8, y: 0, z: 0)
            litNode.localTransform = float4x4.rotationZ(-t) * float4x4.translation(x: 0.8, y: 0, z: 0)
            // Animate light direction subtly
            scene.lightDirection = (0.3 * cosf(t) + 0.3, -0.5, 0.8 * sinf(t) + 0.2)
            try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend)
            Thread.sleep(forTimeInterval: 1.0 / 60.0)
        }
    }

    @MainActor
    private static func showcaseDrawing(windowId: Int, agent: SDLKitGUIAgent) throws {
        try agent.clear(windowId: windowId, color: "#0F0F13")
        try agent.drawRectangle(windowId: windowId, x: 40, y: 40, width: 200, height: 120, color: "#3366FF")
        try agent.drawLine(windowId: windowId, x1: 0, y1: 0, x2: 639, y2: 479, color: "#FFCC00")
        try agent.drawCircleFilled(windowId: windowId, cx: 320, cy: 240, radius: 60, color: "#55FFAA")
        #if canImport(SDLKitTTF)
        do {
            try agent.drawText(windowId: windowId, text: "SDLKit ✓", x: 20, y: 200, font: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf", size: 22, color: 0xFFFFFFFF)
        } catch AgentError.notImplemented {
            print("SDL_ttf not available; skipping text rendering")
        } catch {
            print("Text draw error: \(error)")
        }
        #endif
        try agent.present(windowId: windowId)
    }

    @MainActor
    private static func logNativeHandles(for platform: DemoPlatform, surface: RenderSurface) {
        switch platform {
        case .macOS:
            #if canImport(QuartzCore)
            if let layer = surface.metalLayer as? CAMetalLayer {
                let nameDescription: String
                if let name = layer.name {
                    if let stringName = name as? String {
                        nameDescription = stringName
                    } else {
                        nameDescription = String(describing: name)
                    }
                } else {
                    nameDescription = "nil"
                }
                print("SDLKitDemo: CAMetalLayer => class=\(String(describing: type(of: layer))) name=\(nameDescription)")
            } else {
                print("SDLKitDemo: CAMetalLayer unavailable on macOS")
            }
            #else
            print("SDLKitDemo: QuartzCore unavailable on this build")
            #endif
        case .windows:
            if let hwnd = surface.win32HWND {
                let value = UInt(bitPattern: hwnd)
                let formatted = String(format: "0x%016llX", UInt64(value))
                print("SDLKitDemo: Win32 HWND => \(formatted)")
            } else {
                print("SDLKitDemo: Win32 HWND unavailable")
            }
        case .linux:
            #if canImport(VulkanMinimal)
            var instance = VulkanMinimalInstance()
            let result = VulkanMinimalCreateInstance(&instance)
            guard result == VK_SUCCESS, let vkInstance = instance.handle else {
                print("SDLKitDemo: Vulkan instance creation failed (code=\(result))")
                VulkanMinimalDestroyInstance(&instance)
                return
            }
            defer { VulkanMinimalDestroyInstance(&instance) }
            do {
                let surfaceHandle = try surface.createVulkanSurface(instance: vkInstance)
                let formattedSurface = String(format: "0x%016llX", UInt64(surfaceHandle))
                print("SDLKitDemo: Vulkan surface => \(formattedSurface)")
            } catch {
                print("SDLKitDemo: Vulkan surface creation failed: \(error)")
            }
            #else
            print("SDLKitDemo: Vulkan headers unavailable; skipping surface creation")
            #endif
        }
    }
}
#else
@main
struct DemoApp {
    static func main() {
        print("SDLKitDemo: unsupported platform for this demo")
    }
}
#endif
