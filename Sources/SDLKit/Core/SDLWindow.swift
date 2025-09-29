import Foundation
#if !HEADLESS_CI && canImport(CSDL3)
import CSDL3
#endif

@MainActor
public final class SDLWindow {
    public struct Config {
        public var title: String
        public var width: Int
        public var height: Int
        public init(title: String, width: Int, height: Int) {
            self.title = title; self.width = width; self.height = height
        }
    }
    public struct Info: Equatable, Codable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int
        public var title: String
        public init(x: Int, y: Int, width: Int, height: Int, title: String) { self.x = x; self.y = y; self.width = width; self.height = height; self.title = title }
    }

    public let config: Config
    #if canImport(CSDL3) && !HEADLESS_CI
    var handle: UnsafeMutablePointer<SDL_Window>?
    #endif

    public init(config: Config) { self.config = config }

    public func open() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        try SDLCore.shared.ensureInitialized()
        let flags: UInt32 = 0 // e.g., SDL_WINDOW_HIDDEN
        guard let win = SDLKit_CreateWindow(config.title, Int32(config.width), Int32(config.height), flags) else {
            throw AgentError.internalError(SDLCore.lastError())
        }
        handle = win
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func close() {
        #if canImport(CSDL3) && !HEADLESS_CI
        if let win = handle {
            SDLKit_DestroyWindow(win)
        }
        handle = nil
        #endif
    }

    // MARK: - Controls
    public func show() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_ShowWindow(win)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func hide() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_HideWindow(win)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setTitle(_ title: String) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_SetWindowTitle(win, title)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setPosition(x: Int, y: Int) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_SetWindowPosition(win, Int32(x), Int32(y))
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func resize(width: Int, height: Int) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_SetWindowSize(win, Int32(width), Int32(height))
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func maximize() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_MaximizeWindow(win)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func minimize() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_MinimizeWindow(win)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func restore() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_RestoreWindow(win)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setFullscreen(_ enabled: Bool) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        if SDLKit_SetWindowFullscreen(win, enabled ? 1 : 0) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setOpacity(_ opacity: Float) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        if SDLKit_SetWindowOpacity(win, opacity) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setAlwaysOnTop(_ enabled: Bool) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        if SDLKit_SetWindowAlwaysOnTop(win, enabled ? 1 : 0) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func info() throws -> Info {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
        SDLKit_GetWindowPosition(win, &x, &y)
        SDLKit_GetWindowSize(win, &w, &h)
        let title = String(cString: SDLKit_GetWindowTitle(win))
        return Info(x: Int(x), y: Int(y), width: Int(w), height: Int(h), title: title)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func center() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        SDLKit_CenterWindow(win)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }
}

@MainActor
enum SDLCore {
    case shared

    #if canImport(CSDL3) && !HEADLESS_CI
    private static var initialized = false
    #endif

    func ensureInitialized() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        if !Self.initialized {
            // Initialize core and video; if video is unavailable (headless), this may fail at runtime.
            // Callers should handle errors gracefully.
            if SDLKit_Init(0) != 0 { // 0 => initialize nothing explicitly; subsystems init lazily
                throw AgentError.internalError(SDLCore.lastError())
            }
            Self.initialized = true
        }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    func shutdown() {
        #if canImport(CSDL3) && !HEADLESS_CI
        if Self.initialized {
            SDLKit_Quit()
            Self.initialized = false
        }
        #endif
    }

    #if canImport(CSDL3) && !HEADLESS_CI
    static func lastError() -> String { String(cString: SDLKit_GetError()) }

    static func _testingSetInitialized(_ value: Bool) {
        initialized = value
    }
    #else
    static func lastError() -> String { "SDL unavailable" }
    #endif
}
