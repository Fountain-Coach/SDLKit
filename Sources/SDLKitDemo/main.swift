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
            try runTriangleDemo(on: platform)
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

        let stride = MemoryLayout<Vertex>.stride
        let colorOffset = MemoryLayout<Vertex>.offset(of: \.color) ?? MemoryLayout<(Float, Float, Float)>.stride
        let vertexLayout = VertexLayout(
            stride: stride,
            attributes: [
                .init(index: 0, semantic: "POSITION", format: .float3, offset: 0),
                .init(index: 1, semantic: "COLOR", format: .float3, offset: colorOffset)
            ]
        )

        let pipeline = try backend.makePipeline(
            GraphicsPipelineDescriptor(
                label: "unlit_triangle",
                vertexShader: ShaderID("unlit_triangle_vs"),
                fragmentShader: ShaderID("unlit_triangle_fs"),
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
