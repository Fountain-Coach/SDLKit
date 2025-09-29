import Foundation
#if !HEADLESS_CI && canImport(CSDL3)
import CSDL3
#endif

@MainActor
open class SDLKitGUIAgent {
    private var nextID: Int = 1
    private struct WindowBundle { let window: SDLWindow; let renderer: SDLRenderer }
    private var windows: [Int: WindowBundle] = [:]

    public init() {}

    @discardableResult
    open func openWindow(title: String, width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else { throw AgentError.invalidArgument("width/height must be > 0") }
        let windowLimit = SDLKitConfig.maxWindows
        guard windows.count < windowLimit else {
            SDLLogger.warn("SDLKit.Agent", "Refusing to open window: limit=\(windowLimit) current=\(windows.count)")
            throw AgentError.invalidArgument("Window limit of \(windowLimit) reached")
        }
        guard SDLKitConfig.guiEnabled else { throw AgentError.sdlUnavailable }
        let limit = SDLKitConfig.maxWindows
        guard windows.count < limit else {
            SDLLogger.warn("SDLKit.Agent", "Refusing to open window: limit=\(limit) current=\(windows.count)")
            throw AgentError.invalidArgument("Window limit of \(limit) reached")
        }

        let window = SDLWindow(config: .init(title: title, width: width, height: height))
        try window.open()
        let renderer = try SDLRenderer(width: width, height: height, window: window)

        let id = nextID; nextID += 1
        windows[id] = WindowBundle(window: window, renderer: renderer)
        SDLLogger.info("SDLKit.Agent", "Opened window id=\(id) \(width)x\(height) title=\(title)")
        return id
    }

    open func closeWindow(windowId: Int) {
        guard let bundle = windows.removeValue(forKey: windowId) else { return }
        SDLLogger.info("SDLKit.Agent", "Closing window id=\(windowId)")
        bundle.renderer.shutdown()
        bundle.window.close()
        if windows.isEmpty {
            SDLCore.shared.shutdown()
        }
    }

    public func drawText(windowId: Int, text: String, x: Int, y: Int, font: String? = nil, size: Int? = nil, color: UInt32? = nil) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        #if !HEADLESS_CI && canImport(CSDL3)
        let fontPath = SDLFontResolver.resolve(fontSpec: font)
        guard let fontPath, let s = (size ?? 16) as Int?, s > 0 else {
            throw AgentError.invalidArgument("No usable font (set font path or use 'system:default') or invalid size")
        }
        let argb = color ?? 0xFFFFFFFF
        SDLLogger.debug("SDLKit.Agent", "drawText id=\(windowId) at (\(x),\(y)) font=\(fontPath) size=\(s) color=\(String(format: "%08X", argb)) text=\(text)")
        try bundle.renderer.drawText(text, x: x, y: y, color: argb, fontPath: fontPath, size: s)
        #else
        throw AgentError.notImplemented
        #endif
    }

    open func drawRectangle(windowId: Int, x: Int, y: Int, width: Int, height: Int, color: UInt32) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        SDLLogger.debug("SDLKit.Agent", "drawRectangle id=\(windowId) x=\(x) y=\(y) w=\(width) h=\(height) color=\(String(format: "%08X", color))")
        try bundle.renderer.drawRectangle(x: x, y: y, width: width, height: height, color: color)
    }

    // Convenience overload: color as string (e.g., "#RRGGBB", "#AARRGGBB", or a name like "red").
    open func drawRectangle(windowId: Int, x: Int, y: Int, width: Int, height: Int, color: String) throws {
        let argb: UInt32
        do { argb = try SDLColor.parse(color) } catch { throw AgentError.invalidArgument("Invalid color: \(color)") }
        try drawRectangle(windowId: windowId, x: x, y: y, width: width, height: height, color: argb)
    }

    open func present(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        SDLLogger.debug("SDLKit.Agent", "present id=\(windowId)")
        bundle.renderer.present()
    }

    internal func _testingPopulateWindows(count: Int) {
        windows.removeAll()
        nextID = 1
        guard count > 0 else { return }
        for _ in 0..<count {
            let id = nextID; nextID += 1
            let window = SDLWindow(config: .init(title: "test-\(id)", width: 1, height: 1))
            let renderer = SDLRenderer(testingWidth: 1, testingHeight: 1)
            windows[id] = WindowBundle(window: window, renderer: renderer)
        }
    }

    internal func _testingRenderer(for windowId: Int) -> SDLRenderer? {
        return windows[windowId]?.renderer
    }

    // MARK: - Window controls
    public func showWindow(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.show()
    }

    public func hideWindow(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.hide()
    }

    public func setTitle(windowId: Int, title: String) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.setTitle(title)
    }

    public func setPosition(windowId: Int, x: Int, y: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.setPosition(x: x, y: y)
    }

    public func resizeWindow(windowId: Int, width: Int, height: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.resize(width: width, height: height)
    }

    public func maximizeWindow(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.maximize()
    }

    public func minimizeWindow(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.minimize()
    }

    public func restoreWindow(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.restore()
    }

    public func setFullscreen(windowId: Int, enabled: Bool) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.setFullscreen(enabled)
    }

    public func setOpacity(windowId: Int, opacity: Float) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.setOpacity(opacity)
    }

    public func setAlwaysOnTop(windowId: Int, enabled: Bool) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.setAlwaysOnTop(enabled)
    }

    public func getWindowInfo(windowId: Int) throws -> SDLWindow.Info {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        return try bundle.window.info()
    }

    public func centerWindow(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.window.center()
    }

    // MARK: - Textures
    open func textureLoad(windowId: Int, id: String, path: String) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.loadTexture(id: id, path: path)
    }

    open func textureDraw(windowId: Int, id: String, x: Int, y: Int, width: Int?, height: Int?) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.drawTexture(id: id, x: x, y: y, width: width, height: height)
    }

    open func textureFree(windowId: Int, id: String) {
        guard let bundle = windows[windowId] else { return }
        bundle.renderer.freeTexture(id: id)
    }

    open func textureDrawRotated(windowId: Int, id: String, x: Int, y: Int, width: Int?, height: Int?, angle: Double, cx: Float?, cy: Float?) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.drawTextureRotated(id: id, x: x, y: y, width: width, height: height, angleDegrees: angle, centerX: cx, centerY: cy)
    }

    // MARK: - Geometry batches
    public func drawPoints(windowId: Int, points: [(Int, Int)], color: UInt32) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.drawPoints(points, color: color)
    }
    public func drawLines(windowId: Int, segments: [(Int, Int, Int, Int)], color: UInt32) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.drawLines(segments, color: color)
    }
    public func drawRects(windowId: Int, rects: [(Int, Int, Int, Int)], color: UInt32, filled: Bool) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.drawRects(rects, color: color, filled: filled)
    }

    // MARK: - Render state accessors
    public func getRenderOutputSize(windowId: Int) throws -> (width: Int, height: Int) {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        return try bundle.renderer.getOutputSize()
    }
    public func getRenderScale(windowId: Int) throws -> (sx: Float, sy: Float) {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        return try bundle.renderer.getScale()
    }
    public func setRenderScale(windowId: Int, sx: Float, sy: Float) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.setScale(sx: sx, sy: sy)
    }
    public func getRenderDrawColor(windowId: Int) throws -> UInt32 {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        return try bundle.renderer.getDrawColor()
    }
    public func setRenderDrawColor(windowId: Int, color: UInt32) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.setDrawColor(color)
    }
    public func getRenderViewport(windowId: Int) throws -> (x: Int, y: Int, width: Int, height: Int) {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        return try bundle.renderer.getViewport()
    }
    public func setRenderViewport(windowId: Int, x: Int, y: Int, width: Int, height: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.setViewport(x: x, y: y, width: width, height: height)
    }
    public func getRenderClipRect(windowId: Int) throws -> (x: Int, y: Int, width: Int, height: Int) {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        return try bundle.renderer.getClipRect()
    }
    public func setRenderClipRect(windowId: Int, x: Int, y: Int, width: Int, height: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.setClipRect(x: x, y: y, width: width, height: height)
    }
    public func disableRenderClipRect(windowId: Int) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        try bundle.renderer.disableClipRect()
    }

    open func screenshotRaw(windowId: Int) throws -> SDLRenderer.RawScreenshot {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        return try bundle.renderer.captureRawScreenshot()
    }

    open func screenshotPNG(windowId: Int) throws -> SDLRenderer.PNGScreenshot {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        return try bundle.renderer.capturePNGScreenshot()
    }

    // New tools: clear, line, circle
    public func clear(windowId: Int, color: UInt32) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        SDLLogger.debug("SDLKit.Agent", "clear id=\(windowId) color=\(String(format: "%08X", color))")
        try bundle.renderer.clear(color: color)
    }

    public func clear(windowId: Int, color: String) throws {
        let argb: UInt32
        do { argb = try SDLColor.parse(color) } catch { throw AgentError.invalidArgument("Invalid color: \(color)") }
        try clear(windowId: windowId, color: argb)
    }

    public func drawLine(windowId: Int, x1: Int, y1: Int, x2: Int, y2: Int, color: UInt32) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        SDLLogger.debug("SDLKit.Agent", "drawLine id=\(windowId) (\(x1),\(y1))->(\(x2),\(y2)) color=\(String(format: "%08X", color))")
        try bundle.renderer.drawLine(x1: x1, y1: y1, x2: x2, y2: y2, color: color)
    }

    public func drawLine(windowId: Int, x1: Int, y1: Int, x2: Int, y2: Int, color: String) throws {
        let argb: UInt32
        do { argb = try SDLColor.parse(color) } catch { throw AgentError.invalidArgument("Invalid color: \(color)") }
        try drawLine(windowId: windowId, x1: x1, y1: y1, x2: x2, y2: y2, color: argb)
    }

    public func drawCircleFilled(windowId: Int, cx: Int, cy: Int, radius: Int, color: UInt32) throws {
        guard let bundle = windows[windowId] else { throw AgentError.windowNotFound }
        SDLLogger.debug("SDLKit.Agent", "drawCircleFilled id=\(windowId) c=(\(cx),\(cy)) r=\(radius) color=\(String(format: "%08X", color))")
        try bundle.renderer.drawCircleFilled(cx: cx, cy: cy, radius: radius, color: color)
    }

    public func drawCircleFilled(windowId: Int, cx: Int, cy: Int, radius: Int, color: String) throws {
        let argb: UInt32
        do { argb = try SDLColor.parse(color) } catch { throw AgentError.invalidArgument("Invalid color: \(color)") }
        try drawCircleFilled(windowId: windowId, cx: cx, cy: cy, radius: radius, color: argb)
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
        #if !HEADLESS_CI && canImport(CSDL3)
        var out = SDLKit_Event(type: 0, x: 0, y: 0, keycode: 0, button: 0)
        let got: Int32
        if let t = timeoutMs, t > 0 {
            got = Int32(SDLKit_WaitEventTimeout(&out, Int32(t)))
        } else {
            got = Int32(SDLKit_PollEvent(&out))
        }
        if got == 0 { return nil }
        let type = Int32(bitPattern: out.type)
        switch type {
        case Int32(SDLKIT_EVENT_KEY_DOWN): return Event(type: .keyDown, key: String(out.keycode))
        case Int32(SDLKIT_EVENT_KEY_UP): return Event(type: .keyUp, key: String(out.keycode))
        case Int32(SDLKIT_EVENT_MOUSE_DOWN): return Event(type: .mouseDown, x: Int(out.x), y: Int(out.y), button: Int(out.button))
        case Int32(SDLKIT_EVENT_MOUSE_UP): return Event(type: .mouseUp, x: Int(out.x), y: Int(out.y), button: Int(out.button))
        case Int32(SDLKIT_EVENT_MOUSE_MOVE): return Event(type: .mouseMove, x: Int(out.x), y: Int(out.y))
        case Int32(SDLKIT_EVENT_QUIT): return Event(type: .quit)
        case Int32(SDLKIT_EVENT_WINDOW_CLOSED): return Event(type: .windowClosed)
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
