import Foundation

@MainActor
public final class SDLKitGUIAgent {
    private var nextID: Int = 1
    private struct WindowBundle { let window: SDLWindow; let renderer: SDLRenderer }
    private var windows: [Int: WindowBundle] = [:]

    public init() {}

    @discardableResult
    public func openWindow(title: String, width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else { throw AgentError.invalidArgument("width/height must be > 0") }
        guard SDLKitConfig.guiEnabled else { throw AgentError.sdlUnavailable }

        let window = SDLWindow(config: .init(title: title, width: width, height: height))
        try window.open()
        let renderer = try SDLRenderer(width: width, height: height, window: window)

        let id = nextID; nextID += 1
        windows[id] = WindowBundle(window: window, renderer: renderer)
        return id
    }

    public func closeWindow(windowId: Int) {
        guard let bundle = windows.removeValue(forKey: windowId) else { return }
        bundle.window.close()
        // Renderer destroyed with window by SDL; nothing further here.
    }

    public func drawText(windowId: Int, text: String, x: Int, y: Int, font: String? = nil, size: Int? = nil, color: UInt32? = nil) throws {
        guard windows[windowId] != nil else { throw AgentError.windowNotFound }
        // TODO: render text if SDL_ttf available
        throw AgentError.notImplemented
    }

    public func drawRectangle(windowId: Int, x: Int, y: Int, width: Int, height: Int, color: UInt32) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.drawRectangle(x: x, y: y, width: width, height: height, color: color)
    }

    public func present(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        bundle.renderer.present()
    }

    public struct Event: Equatable {
        public enum Kind { case keyDown, keyUp, mouseDown, mouseUp, mouseMove, quit, windowClosed }
        public var type: Kind
        public var x: Int?; public var y: Int?; public var key: String?; public var button: Int?
        public init(type: Kind, x: Int? = nil, y: Int? = nil, key: String? = nil, button: Int? = nil) {
            self.type = type; self.x = x; self.y = y; self.key = key; self.button = button
        }
    }

    public func captureEvent(windowId: Int, timeoutMs: Int? = nil) throws -> Event? {
        guard windows[windowId] != nil else { throw AgentError.windowNotFound }
        // TODO: block/poll for event with timeout
        throw AgentError.notImplemented
    }
}
