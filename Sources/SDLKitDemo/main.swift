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
        let env = ProcessInfo.processInfo.environment
        if (env["SDLKIT_AUDIO_DEMO"] ?? "0") == "1" {
            try runAudioMelDemo(agent: agent)
            return
        }
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
    private static func runAudioMelDemo(agent: SDLKitGUIAgent) throws {
        let windowId = try agent.openWindow(title: "SDLKit Audio Mel", width: 800, height: 400)
        defer { agent.closeWindow(windowId: windowId) }
        // Setup capture
        let cap = try SDLAudioCapture(spec: .init(sampleRate: 48000, channels: 1, format: .f32))
        let pump = SDLAudioChunkedCapturePump(capture: cap, bufferFrames: 48000/2)
        // Try GPU
        let backend = try agent.makeRenderBackend(windowId: windowId)
        let frameSize = 1024, hopSize = 256, melBands = 64
        var gpuExtractor = AudioGPUFeatureExtractor(backend: backend, sampleRate: cap.spec.sampleRate, frameSize: frameSize, melBands: melBands)
        var useGPU = gpuExtractor != nil
        var overlap: [Float] = []
        let barWidth = max(1, 800 / melBands)
        let height = 400
        let start = Date()
        while Date().timeIntervalSince(start) < 5.0 {
            // Build one frame from pump
            var hop = Array(repeating: Float(0), count: hopSize * cap.spec.channels)
            let got = pump.readFrames(into: &hop)
            if got == 0 { Thread.sleep(forTimeInterval: 0.005); continue }
            var mono: [Float] = overlap
            mono.reserveCapacity(overlap.count + got)
            if cap.spec.channels == 1 {
                mono.append(contentsOf: hop.prefix(got))
            } else {
                for i in 0..<got {
                    var acc: Float = 0
                    for c in 0..<cap.spec.channels { acc += hop[i*cap.spec.channels + c] }
                    mono.append(acc / Float(cap.spec.channels))
                }
            }
            // allow runtime toggle via any key press
            if let e = try? agent.captureEvent(windowId: windowId, timeoutMs: 0) {
                switch e.type {
                case .keyDown:
                    useGPU.toggle()
                case .quit, .windowClosed:
                    break
                default: break
                }
            }
            if mono.count >= frameSize {
                let frame = Array(mono.prefix(frameSize))
                overlap = Array(mono.dropFirst(hopSize))
                let mel: [Float]
                if useGPU, let ge = gpuExtractor, let m = try? ge.process(frames: [frame]).first {
                    mel = m
                } else {
                    guard let ex = AudioFeatureExtractor(sampleRate: cap.spec.sampleRate, channels: 1, frameSize: frameSize, hopSize: hopSize, melBands: melBands) else { continue }
                    mel = ex.processFrame(frame).mel
                }
                // Derive simple note for overlay
                var maxVal: Float = 0; var maxIdx = 0
                for i in 0..<min(melBands, mel.count) { if mel[i] > maxVal { maxVal = mel[i]; maxIdx = i } }
                let note = 36 + (maxIdx * (96 - 36)) / max(1, melBands-1)
                let velocity = max(1, min(127, Int((maxVal * 127.0 * 0.01).rounded())))

                // Draw bars
                try agent.clear(windowId: windowId, color: 0xFF101010)
                for i in 0..<min(melBands, mel.count) {
                    let v = min(1.0, Double(mel[i]) * 0.01)
                    let h = Int(v * Double(height))
                    let x = i * barWidth
                    try agent.drawRectangle(windowId: windowId, x: x, y: height - h, width: barWidth - 1, height: h, color: 0xFF33CCFF)
                }
                #if canImport(SDLKitTTF)
                do {
                    let text = "Note: \(note)  Vel: \(velocity)"
                    try agent.drawText(windowId: windowId, text: text, x: 10, y: 8, font: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf", size: 18, color: 0xFFFFFFFF)
                } catch { /* ignore if font unavailable */ }
                #endif
                try agent.present(windowId: windowId)
            }
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
            #if os(Linux)
            let surfaceValue = UInt(bitPattern: surface)
            let formattedSurface = String(format: "0x%016llX", UInt64(surfaceValue))
            #else
            let formattedSurface = String(format: "0x%016llX", UInt64(surface))
            #endif
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

        let mesh = try backend.registerMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertices.count,
            indexBuffer: nil,
            indexCount: 0,
            indexFormat: .uint16
        )

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
            let bindings = BindingSet()
            try backend.draw(
                mesh: mesh,
                pipeline: pipeline,
                bindings: bindings,
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

        // Create scene graph with two nodes/materials; defaults can come from Settings
        let unlitMesh = Mesh(vertexBuffer: unlitVB, vertexCount: unlitVerts.count)
        let defaultMaterial = SDLKitConfigStore.defaultMaterial()
        let defaultBaseColor = SDLKitConfigStore.defaultBaseColor()
        let unlitParams = MaterialParams(baseColor: defaultBaseColor)
        let unlitMat = Material(shader: ShaderID("unlit_triangle"), params: unlitParams)
        let unlitNode = SceneNode(name: "Unlit", transform: float4x4.translation(x: -0.8, y: 0, z: 0), mesh: unlitMesh, material: unlitMat)

        let litLight = SDLKitConfigStore.defaultLightDirection() ?? (0.3, -0.5, 0.8)
        let litParams = MaterialParams(lightDirection: litLight, baseColor: defaultBaseColor)
        let litShader = defaultMaterial == "unlit" ? ShaderID("unlit_triangle") : ShaderID("basic_lit")
        let litMat = Material(shader: litShader, params: litParams)
        let litNode = SceneNode(name: "Lit", transform: float4x4.translation(x: 0.8, y: 0, z: 0), mesh: litMesh, material: litMat)

        let root = SceneNode(name: "Root")
        root.addChild(unlitNode)
        root.addChild(litNode)

        var computeResources: SceneGraphComputeInterop.Resources?
        if let compute = try? SceneGraphComputeInterop.makeNode(backend: backend) {
            let (computeNode, resources) = compute
            root.addChild(computeNode)
            computeResources = resources
        } else {
            SDLLogger.info("SDLKit.SceneGraphDemo", "scenegraph_wave compute shader unavailable; skipping interop node")
        }

        // Add a simple perspective camera
        let aspect: Float = Float(window.config.width) / Float(max(1, window.config.height))
        let view = float4x4.lookAt(eye: (0, 0, 2), center: (0, 0, 0), up: (0, 1, 0))
        let proj = float4x4.perspective(fovYRadians: .pi/3, aspect: aspect, zNear: 0.1, zFar: 100.0)
        var scene = Scene(root: root, camera: Camera(view: view, projection: proj))
        // Optional: override light direction from SecretStore/Settings if present
        if let vec = SDLKitConfigStore.defaultLightDirection() { scene.lightDirection = vec }

        // Animate rotation for a few frames
        let frames = 180
        for i in 0..<frames {
            let t = Float(i) * (Float.pi / 90.0)
            unlitNode.localTransform = float4x4.rotationZ(t) * float4x4.translation(x: -0.8, y: 0, z: 0)
            litNode.localTransform = float4x4.rotationZ(-t) * float4x4.translation(x: 0.8, y: 0, z: 0)
            // Animate light direction subtly
            scene.lightDirection = (0.3 * cosf(t) + 0.3, -0.5, 0.8 * sinf(t) + 0.2)
            try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend, beforeRender: {
                if let resources = computeResources {
                    try SceneGraphComputeInterop.dispatchCompute(backend: backend, resources: resources)
                }
            })
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
                #if os(Linux)
                let surfaceValue = UInt(bitPattern: surfaceHandle)
                let formattedSurface = String(format: "0x%016llX", UInt64(surfaceValue))
                #else
                let formattedSurface = String(format: "0x%016llX", UInt64(surfaceHandle))
                #endif
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
