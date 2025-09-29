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
    var textures: [String: UnsafeMutablePointer<SDL_Texture>] = [:]
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

    // MARK: - Textures
    public func loadTexture(id: String, path: String) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        if let existing = textures[id] { SDLKit_DestroyTexture(existing) }
        // Try SDL_image if available for non-BMP formats; fall back to BMP
        #if canImport(CSDL3IMAGE)
        let ext = (path as NSString).pathExtension.lowercased()
        let useIMG = ext != "bmp"
        let surf: UnsafeMutablePointer<SDL_Surface>? = useIMG ? SDLKit_IMG_Load(path) : SDLKit_LoadBMP(path)
        #else
        let surf: UnsafeMutablePointer<SDL_Surface>? = SDLKit_LoadBMP(path)
        #endif
        guard let surf else { throw AgentError.internalError(SDLCore.lastError()) }
        defer { SDLKit_DestroySurface(surf) }
        guard let tex = SDLKit_CreateTextureFromSurface(r, surf) else { throw AgentError.internalError(SDLCore.lastError()) }
        textures[id] = tex
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func drawTexture(id: String, x: Int, y: Int, width: Int?, height: Int?) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        guard let tex = textures[id] else { throw AgentError.invalidArgument("texture not found: \(id)") }
        var tw: Int32 = 0, th: Int32 = 0
        SDLKit_GetTextureSize(tex, &tw, &th)
        let w = Float(width ?? Int(tw))
        let h = Float(height ?? Int(th))
        var dst = SDL_FRect(x: Float(x), y: Float(y), w: w, h: h)
        if SDLKit_RenderTexture(r, tex, nil, &dst) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        if SDLKitConfig.presentPolicy == .auto { SDLKit_RenderPresent(r) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func freeTexture(id: String) {
        #if canImport(CSDL3) && !HEADLESS_CI
        if let tex = textures.removeValue(forKey: id) { SDLKit_DestroyTexture(tex) }
        #endif
    }

    // MARK: - Render state queries
    public func getOutputSize() throws -> (width: Int, height: Int) {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        var w: Int32 = 0, h: Int32 = 0
        SDLKit_GetRenderOutputSize(r, &w, &h)
        return (Int(w), Int(h))
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func getScale() throws -> (sx: Float, sy: Float) {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        var sx: Float = 0, sy: Float = 0
        SDLKit_GetRenderScale(r, &sx, &sy)
        return (sx, sy)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setScale(sx: Float, sy: Float) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        if SDLKit_SetRenderScale(r, sx, sy) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func getDrawColor() throws -> UInt32 {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        var rr: UInt8 = 0, gg: UInt8 = 0, bb: UInt8 = 0, aa: UInt8 = 0
        SDLKit_GetRenderDrawColor(r, &rr, &gg, &bb, &aa)
        return (UInt32(aa) << 24) | (UInt32(rr) << 16) | (UInt32(gg) << 8) | UInt32(bb)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setDrawColor(_ color: UInt32) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        let a = UInt8((color >> 24) & 0xFF)
        let rr = UInt8((color >> 16) & 0xFF)
        let gg = UInt8((color >> 8) & 0xFF)
        let bb = UInt8(color & 0xFF)
        if SDLKit_SetRenderDrawColor(r, rr, gg, bb, a) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func getViewport() throws -> (x: Int, y: Int, width: Int, height: Int) {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
        SDLKit_GetRenderViewport(r, &x, &y, &w, &h)
        return (Int(x), Int(y), Int(w), Int(h))
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setViewport(x: Int, y: Int, width: Int, height: Int) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        if SDLKit_SetRenderViewport(r, Int32(x), Int32(y), Int32(width), Int32(height)) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func getClipRect() throws -> (x: Int, y: Int, width: Int, height: Int) {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
        SDLKit_GetRenderClipRect(r, &x, &y, &w, &h)
        return (Int(x), Int(y), Int(w), Int(h))
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func setClipRect(x: Int, y: Int, width: Int, height: Int) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        if SDLKit_SetRenderClipRect(r, Int32(x), Int32(y), Int32(width), Int32(height)) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func disableClipRect() throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        if SDLKit_DisableRenderClipRect(r) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public struct RawScreenshot: Codable {
        public let raw_base64: String
        public let width: Int
        public let height: Int
        public let pitch: Int
        public let format: String // e.g., ABGR8888
    }

    public func captureRawScreenshot() throws -> RawScreenshot {
        #if canImport(CSDL3) && !HEADLESS_CI
        let (ow, oh) = try getOutputSize()
        let pitch = ow * 4
        var buffer = [UInt8](repeating: 0, count: pitch * oh)
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        let rc = buffer.withUnsafeMutableBytes { ptr in
            SDLKit_RenderReadPixels(r, 0, 0, Int32(ow), Int32(oh), ptr.baseAddress, Int32(pitch))
        }
        if rc != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        let data = Data(buffer)
        let b64 = data.base64EncodedString()
        return RawScreenshot(raw_base64: b64, width: ow, height: oh, pitch: pitch, format: "ABGR8888")
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    public func drawText(_ text: String, x: Int, y: Int, color: UInt32, fontPath: String, size: Int) throws {
        #if canImport(CSDL3) && !HEADLESS_CI
        guard let r = handle else { throw AgentError.internalError("Renderer not created") }
        guard SDLKit_TTF_Available() != 0 else { throw AgentError.notImplemented }
        try Self.ensureTTFInited()
        let font = try Self.getFont(path: fontPath, size: size)
        let a = UInt8((color >> 24) & 0xFF)
        let rr = UInt8((color >> 16) & 0xFF)
        let gg = UInt8((color >> 8) & 0xFF)
        let bb = UInt8(color & 0xFF)
        let tex: UnsafeMutablePointer<SDL_Texture>? = text.withCString { cstr in
            guard let surf = SDLKit_TTF_RenderUTF8_Blended(font, cstr, rr, gg, bb, a) else { return nil }
            defer { SDLKit_DestroySurface(surf) }
            return SDLKit_CreateTextureFromSurface(r, surf)
        }
        guard let texture = tex else { throw AgentError.internalError(SDLCore.lastError()) }
        defer { SDLKit_DestroyTexture(texture) }
        var tw: Int32 = 0, th: Int32 = 0
        SDLKit_GetTextureSize(texture, &tw, &th)
        var dst = SDL_FRect(x: Float(x), y: Float(y), w: Float(tw), h: Float(th))
        if SDLKit_RenderTexture(r, texture, nil, &dst) != 0 {
            throw AgentError.internalError(SDLCore.lastError())
        }
        if SDLKitConfig.presentPolicy == .auto { SDLKit_RenderPresent(r) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    #if canImport(CSDL3) && !HEADLESS_CI
    private struct FontKey: Hashable { let path: String; let size: Int }
    private static var ttfInitialized = false
    private static var fontCache: [FontKey: UnsafeMutableRawPointer] = [:]

    private static func ensureTTFInited() throws {
        if !ttfInitialized {
            if SDLKit_TTF_Init() != 0 { throw AgentError.internalError(SDLCore.lastError()) }
            ttfInitialized = true
        }
    }

    private static func getFont(path: String, size: Int) throws -> UnsafeMutablePointer<SDLKit_TTF_Font> {
        let key = FontKey(path: path, size: size)
        if let cached = fontCache[key] {
            return cached.bindMemory(to: SDLKit_TTF_Font.self, capacity: 1)
        }
        guard let f = SDLKit_TTF_OpenFont(path, Int32(size)) else {
            throw AgentError.internalError(SDLCore.lastError())
        }
        fontCache[key] = UnsafeMutableRawPointer(f)
        return f
    }
    #endif
}
