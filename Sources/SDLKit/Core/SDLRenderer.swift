import Foundation
#if !HEADLESS_CI && canImport(CSDL3)
import CSDL3
#endif

@MainActor
public final class SDLRenderer {
    public let width: Int
    public let height: Int
    #if canImport(CSDL3) && !HEADLESS_CI
    var handle: UnsafeMutablePointer<SDL_Renderer>?
    #endif

    public init(width: Int, height: Int, window: SDLWindow) throws {
        self.width = width
        self.height = height
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let win = window.handle else { throw AgentError.internalError("Window not opened") }
        handle = SDLKit_CreateRenderer(win, 0)
        if handle == nil { throw AgentError.internalError(SDLCore.lastError()) }
        #endif
    }

    public func present() {
        #if canImport(CSDL3) && !HEADLESS_CI
        if let r = handle { SDLKit_RenderPresent(r) }
        #endif
    }

    public func drawRectangle(x: Int, y: Int, width: Int, height: Int, color: UInt32) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        let a = UInt8((color >> 24) & 0xFF)
        let rr = UInt8((color >> 16) & 0xFF)
        let gg = UInt8((color >> 8) & 0xFF)
        let bb = UInt8(color & 0xFF)
        if SDLKit_SetRenderDrawColor(r, rr, gg, bb, a) != 0 {
            throw AgentError.internalError(SDLCore.lastError())
        }
        var rect = SDL_FRect(x: Float(x), y: Float(y), w: Float(width), h: Float(height))
        if SDLKit_RenderFillRect(r, &rect) != 0 {
            throw AgentError.internalError(SDLCore.lastError())
        }
        if SDLKitConfig.presentPolicy == .auto { SDLKit_RenderPresent(r) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func clear(color: UInt32) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        let a = UInt8((color >> 24) & 0xFF)
        let rr = UInt8((color >> 16) & 0xFF)
        let gg = UInt8((color >> 8) & 0xFF)
        let bb = UInt8(color & 0xFF)
        if SDLKit_SetRenderDrawColor(r, rr, gg, bb, a) != 0 {
            throw AgentError.internalError(SDLCore.lastError())
        }
        if SDLKit_RenderClear(r) != 0 {
            throw AgentError.internalError(SDLCore.lastError())
        }
        if SDLKitConfig.presentPolicy == .auto { SDLKit_RenderPresent(r) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }
}
