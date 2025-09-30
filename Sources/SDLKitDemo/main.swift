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

    private struct ExitSignal: Error {}

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
        } catch is ExitSignal {
            print("SDLKitDemo: user exit")
        } catch AgentError.sdlUnavailable {
            print("SDL unavailable on this build. Install SDL3 to run the demo.")
        } catch {
            print("SDLKitDemo error: \(error)")
        }
    }

    @MainActor
    private static func runDemo(on platform: DemoPlatform, agent: SDLKitGUIAgent) throws {
        let windowId = try agent.openWindow(title: "SDLKit Demo", width: 640, height: 480)
        defer { agent.closeWindow(windowId: windowId) }

        try showcaseDrawing(windowId: windowId, agent: agent)
        try logNativeHandles(for: platform, windowId: windowId, agent: agent)

        let start = Date()
        while Date().timeIntervalSince(start) < 2.0 {
            if let event = try agent.captureEvent(windowId: windowId, timeoutMs: 100) {
                switch event.type {
                case .quit, .windowClosed, .keyDown, .mouseDown:
                    throw ExitSignal()
                default:
                    break
                }
            }
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
}
#else
@main
struct DemoApp {
    static func main() {
        print("SDLKitDemo: unsupported platform for this demo")
    }
}
#endif
