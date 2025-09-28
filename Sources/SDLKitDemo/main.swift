import Foundation
import SDLKit
#if canImport(SDLKitTTF)
import SDLKitTTF
#endif

#if os(macOS)
@main
struct DemoApp {
    static func main() {
        guard SDLKitConfig.guiEnabled else {
            print("GUI disabled. Set SDLKIT_GUI_ENABLED=1 to enable.")
            return
        }
        let agent = SDLKitGUIAgent()
        do {
            let win = try agent.openWindow(title: "SDLKit Demo", width: 640, height: 480)
            // Clear background
            try agent.clear(windowId: win, color: "#0F0F13")
            // Draw a rectangle
            try agent.drawRectangle(windowId: win, x: 40, y: 40, width: 200, height: 120, color: "#3366FF")
            // Draw a line
            try agent.drawLine(windowId: win, x1: 0, y1: 0, x2: 639, y2: 479, color: "#FFCC00")
            // Draw a filled circle
            try agent.drawCircleFilled(windowId: win, cx: 320, cy: 240, radius: 60, color: "#55FFAA")
            // Try text if TTF is available
            #if !HEADLESS_CI
            do {
                try agent.drawText(windowId: win, text: "SDLKit ✓", x: 20, y: 200, font: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf", size: 22, color: 0xFFFFFFFF)
            } catch AgentError.notImplemented {
                print("SDL_ttf not available; skipping text rendering")
            } catch {
                print("Text draw error: \(error)")
            }
            #endif
            try agent.present(windowId: win)

            print("Demo running. Press any key or close window to exit...")
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let ev = try agent.captureEvent(windowId: win, timeoutMs: 100) {
                    switch ev.type {
                    case .quit, .windowClosed, .keyDown, .mouseDown:
                        throw ExitSignal()
                    default:
                        break
                    }
                }
            }
        } catch is ExitSignal {
            // user requested exit
        } catch AgentError.sdlUnavailable {
            print("SDL unavailable on this build. Install SDL3 to run the demo.")
        } catch {
            print("Demo error: \(error)")
        }
        print("Demo exit.")
    }
    struct ExitSignal: Error {}
}
#else
@main
struct DemoApp {
    static func main() { print("SDLKitDemo: unsupported platform for this demo") }
}
#endif
