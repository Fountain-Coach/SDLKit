import Foundation
import SDLKit

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
            // Clear background and draw a rectangle
            // Use explicit draw via renderer by leveraging agent conveniences.
            try agent.drawRectangle(windowId: win, x: 40, y: 40, width: 200, height: 120, color: "#3366FF")
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

