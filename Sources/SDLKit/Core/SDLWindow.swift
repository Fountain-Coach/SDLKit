import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(Metal)
import Metal
#endif
#if canImport(CSDL3)
import CSDL3
#endif
#if canImport(Vulkan)
import Vulkan
#endif
#if os(Linux) && canImport(CVulkan)
import CVulkan
#endif
#if !HEADLESS_CI && canImport(CSDL3Compat)
import CSDL3Compat
#endif
#if canImport(QuartzCore)
public typealias SDLKitMetalLayer = CAMetalLayer
#else
public typealias SDLKitMetalLayer = AnyObject
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

    @MainActor
    public struct NativeHandles {
        public let metalLayer: SDLKitMetalLayer?
        public let win32HWND: UnsafeMutableRawPointer?
        #if canImport(CSDL3) && !HEADLESS_CI
        private let windowHandle: UnsafeMutableRawPointer
        #endif

        #if canImport(CSDL3) && !HEADLESS_CI
        fileprivate init(window: UnsafeMutableRawPointer) {
            self.windowHandle = window
            #if canImport(QuartzCore)
            if let pointer = SDLKit_MetalLayerForWindow(window) {
                self.metalLayer = Unmanaged<SDLKitMetalLayer>.fromOpaque(pointer).takeUnretainedValue()
            } else {
                self.metalLayer = nil
            }
            #else
            self.metalLayer = nil
            #endif
            #if canImport(CSDL3Compat)
            self.win32HWND = SDLKit_Win32HWND_Compat(window)
            #else
            self.win32HWND = SDLKit_Win32HWND(window)
            #endif
        }
        #else
        fileprivate init() {
            self.metalLayer = nil
            self.win32HWND = nil
        }
        #endif

        public func createVulkanSurface(instance: VkInstance) throws -> VkSurfaceKHR {
            #if canImport(CSDL3) && !HEADLESS_CI
            var surface: VkSurfaceKHR?
            if !SDLKit_CreateVulkanSurface(windowHandle, instance, &surface) {
                throw AgentError.internalError(SDLCore.lastError())
            }
            // On platforms where VkSurfaceKHR is imported as an optional handle (OpaquePointer?), unwrap.
            guard let s = surface else {
                throw AgentError.internalError("SDLKit_CreateVulkanSurface returned success but produced a nil surface")
            }
            return s
            #else
            _ = instance
            throw AgentError.sdlUnavailable
            #endif
        }

        public func vulkanInstanceExtensions() throws -> [String] {
            #if canImport(CSDL3) && !HEADLESS_CI && (canImport(CVulkan) || canImport(VulkanMinimal))
            var count: UInt32 = 0
            var namesPtr: UnsafePointer<UnsafePointer<CChar>?>? = nil
            let ok = withUnsafeMutablePointer(to: &count) { countPtr in
                withUnsafeMutablePointer(to: &namesPtr) { namesPtrPtr in
                    namesPtrPtr.withMemoryRebound(to: Optional<UnsafePointer<CChar>>.self, capacity: 1) { rebound in
                        SDLKit_Vulkan_GetInstanceExtensions(windowHandle, countPtr, rebound) != 0
                    }
                }
            }
            guard ok, count > 0, let namesBase = namesPtr else { return [] }
            var result: [String] = []
            result.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                if let cstr = namesBase.advanced(by: i).pointee {
                    result.append(String(cString: cstr))
                }
            }
            return result
            #else
            throw AgentError.sdlUnavailable
            #endif
        }
    }

    public let config: Config
    #if canImport(CSDL3) && !HEADLESS_CI
    var handle: UnsafeMutableRawPointer?
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

    public func nativeHandles() throws -> NativeHandles {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = handle else { throw AgentError.internalError("Window not opened") }
        return NativeHandles(window: win)
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

    private static var initialized = false

    func ensureInitialized() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        if !Self.initialized {
            #if os(macOS)
            // Provide sane defaults on macOS when not explicitly set to reduce
            // initialization failures in ad-hoc runs (outside of our launchers).
            let env = ProcessInfo.processInfo.environment
            if env["SDL_VIDEODRIVER"] == nil { setenv("SDL_VIDEODRIVER", "cocoa", 1) }
            if env["SDL_AUDIODRIVER"] == nil { setenv("SDL_AUDIODRIVER", "dummy", 1) }
            #endif
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
        #if canImport(CSDL3)
        if Self.initialized {
            SDLKit_Quit()
        }
        #endif
        Self.initialized = false
    }

    #if canImport(CSDL3) && !HEADLESS_CI
    static func lastError() -> String { String(cString: SDLKit_GetError()) }
    #else
    static func lastError() -> String { "SDL unavailable" }
    #endif

    static func _testingSetInitialized(_ value: Bool) {
        Self.initialized = value
    }
}
#if HEADLESS_CI
// Provide minimal aliases so headless builds don't fail type lookup
typealias SDL_Window = OpaquePointer
#endif
