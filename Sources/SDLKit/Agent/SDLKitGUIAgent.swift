import Foundation

public final class SDLKitGUIAgent {
    private var nextID: Int = 1
    private var windows: [Int: Any] = [:] // Placeholder until real SDLWindow exists

    public init() {}

    @discardableResult
    public func openWindow(title: String, width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else { throw AgentError.invalidArgument("width/height must be > 0") }
        guard SDLKitConfig.guiEnabled else { throw AgentError.sdlUnavailable }
        // TODO: create SDLWindow + SDLRenderer
        let id = nextID; nextID += 1
        windows[id] = ()
        return id
    }

    public func closeWindow(windowId: Int) {
        // TODO: destroy SDL resources
        windows.removeValue(forKey: windowId)
    }

    public func drawText(windowId: Int, text: String, x: Int, y: Int, font: String? = nil, size: Int? = nil, color: UInt32? = nil) throws {
        guard windows[windowId] != nil else { throw AgentError.windowNotFound }
        // TODO: render text if SDL_ttf available
        throw AgentError.notImplemented
    }

    public func drawRectangle(windowId: Int, x: Int, y: Int, width: Int, height: Int, color: UInt32) throws {
        guard windows[windowId] != nil else { throw AgentError.windowNotFound }
        // TODO: draw primitive rectangle
        throw AgentError.notImplemented
    }

    public func present(windowId: Int) throws {
        guard windows[windowId] != nil else { throw AgentError.windowNotFound }
        // TODO: present renderer
        throw AgentError.notImplemented
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

