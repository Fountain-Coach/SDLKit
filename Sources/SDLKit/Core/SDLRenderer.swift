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

    public func drawLine(x1: Int, y1: Int, x2: Int, y2: Int, color: UInt32) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        // Fallback Bresenham rendering using 1x1 rects to avoid SDL API drift for lines.
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        let a = UInt8((color >> 24) & 0xFF)
        let rr = UInt8((color >> 16) & 0xFF)
        let gg = UInt8((color >> 8) & 0xFF)
        let bb = UInt8(color & 0xFF)
        if SDLKit_SetRenderDrawColor(r, rr, gg, bb, a) != 0 {
            throw AgentError.internalError(SDLCore.lastError())
        }
        var x0 = x1, y0 = y1
        let dx = abs(x2 - x1)
        let dy = -abs(y2 - y1)
        let sx = x1 < x2 ? 1 : -1
        let sy = y1 < y2 ? 1 : -1
        var err = dx + dy
        while true {
            var p = SDL_FRect(x: Float(x0), y: Float(y0), w: 1, h: 1)
            if SDLKit_RenderFillRect(r, &p) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
            if x0 == x2 && y0 == y2 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
        if SDLKitConfig.presentPolicy == .auto { SDLKit_RenderPresent(r) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func drawCircleFilled(cx: Int, cy: Int, radius: Int, color: UInt32) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard radius >= 0 else { throw AgentError.invalidArgument("radius must be >= 0") }
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        let a = UInt8((color >> 24) & 0xFF)
        let rr = UInt8((color >> 16) & 0xFF)
        let gg = UInt8((color >> 8) & 0xFF)
        let bb = UInt8(color & 0xFF)
        if SDLKit_SetRenderDrawColor(r, rr, gg, bb, a) != 0 {
            throw AgentError.internalError(SDLCore.lastError())
        }
        // Midpoint circle, drawing horizontal spans for a filled circle
        var x = radius
        var y = 0
        var err = 1 - x
        func drawSpan(_ cx: Int, _ cy: Int, _ x: Int, _ y: Int) throws {
            let x0 = cx - x
            let w0 = 2 * x + 1
            var rect1 = SDL_FRect(x: Float(x0), y: Float(cy + y), w: Float(w0), h: 1)
            var rect2 = SDL_FRect(x: Float(x0), y: Float(cy - y), w: Float(w0), h: 1)
            if SDLKit_RenderFillRect(r, &rect1) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
            if y != 0 {
                if SDLKit_RenderFillRect(r, &rect2) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
            }
        }
        while x >= y {
            try drawSpan(cx, cy, x, y)
            y += 1
            if err < 0 {
                err += 2 * y + 1
            } else {
                x -= 1
                err += 2 * (y - x + 1)
            }
        }
        if SDLKitConfig.presentPolicy == .auto { SDLKit_RenderPresent(r) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }
}
