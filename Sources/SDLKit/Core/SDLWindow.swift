import Foundation
#if canImport(CSDL3)
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

    public let config: Config
    #if canImport(CSDL3) && !HEADLESS_CI
    var handle: UnsafeMutablePointer<SDL_Window>?
    #endif

    public init(config: Config) { self.config = config }

    public func open() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        try SDLCore.shared.ensureInitialized()
        let flags: UInt32 = 0 // e.g., SDL_WINDOW_HIDDEN
        guard let win = SDL_CreateWindow(config.title, Int32(config.width), Int32(config.height), flags) else {
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
            SDL_DestroyWindow(win)
        }
        handle = nil
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
            if SDL_Init(0) != 0 { // 0 => initialize nothing explicitly; subsystems init lazily
                throw AgentError.internalError(SDLCore.lastError())
            }
            Self.initialized = true
        }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    #if canImport(CSDL3) && !HEADLESS_CI
    static func lastError() -> String { String(cString: SDL_GetError()) }
    #else
    static func lastError() -> String { "SDL unavailable" }
    #endif
}
