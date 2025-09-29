import Foundation

@MainActor
public struct SDLKitJSONAgent {
    private let agent: SDLKitGUIAgent
    public init() { self.agent = SDLKitGUIAgent() }
    public init(agent: SDLKitGUIAgent) { self.agent = agent }

    public enum Endpoint: String {
        case open = "/agent/gui/window/open"
        case close = "/agent/gui/window/close"
        case show = "/agent/gui/window/show"
        case hide = "/agent/gui/window/hide"
        case resize = "/agent/gui/window/resize"
        case setTitle = "/agent/gui/window/setTitle"
        case setPosition = "/agent/gui/window/setPosition"
        case getInfo = "/agent/gui/window/getInfo"
        case maximize = "/agent/gui/window/maximize"
        case minimize = "/agent/gui/window/minimize"
        case restore = "/agent/gui/window/restore"
        case setFullscreen = "/agent/gui/window/setFullscreen"
        case setOpacity = "/agent/gui/window/setOpacity"
        case setAlwaysOnTop = "/agent/gui/window/setAlwaysOnTop"
        case center = "/agent/gui/window/center"
        case present = "/agent/gui/present"
        case drawRect = "/agent/gui/drawRectangle"
        case clear = "/agent/gui/clear"
        case drawLine = "/agent/gui/drawLine"
        case drawCircleFilled = "/agent/gui/drawCircleFilled"
        case drawText = "/agent/gui/drawText"
        case captureEvent = "/agent/gui/captureEvent"
        case openapiYAML = "/openapi.yaml"
        case openapiJSON = "/openapi.json"
        case health = "/health"
        case version = "/version"
        case clipboardGet = "/agent/gui/clipboard/get"
        case clipboardSet = "/agent/gui/clipboard/set"
        case inputKeyboard = "/agent/gui/input/getKeyboardState"
        case inputMouse = "/agent/gui/input/getMouseState"
        case displayList = "/agent/gui/display/list"
        case displayGetInfo = "/agent/gui/display/getInfo"
    }

    public func handle(path: String, body: Data) -> Data {
        guard let ep = Endpoint(rawValue: path) else {
            if path.hasPrefix("/agent/gui/") { return Self.errorJSON(code: "not_implemented", details: path) }
            return Self.errorJSON(code: "invalid_endpoint", details: path)
        }
        do {
            switch ep {
            case .openapiYAML:
                if let ext = Self.loadExternalOpenAPIYAML() { return ext }
                return Data(SDLKitOpenAPI.yaml.utf8)
            case .openapiJSON:
                return SDLKitOpenAPI.json
            case .health:
                return try JSONEncoder().encode(["ok": true])
            case .version:
                return try JSONEncoder().encode(["agent": SDLKitOpenAPI.agentVersion, "openapi": SDLKitOpenAPI.specVersion])
            case .open:
                let req = try JSONDecoder().decode(OpenWindowReq.self, from: body)
                let id = try agent.openWindow(title: req.title, width: req.width, height: req.height)
                return try JSONEncoder().encode(["window_id": id])
            case .close:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                agent.closeWindow(windowId: req.window_id)
                return Self.okJSON()
            case .show:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.showWindow(windowId: req.window_id)
                return Self.okJSON()
            case .hide:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.hideWindow(windowId: req.window_id)
                return Self.okJSON()
            case .resize:
                let req = try JSONDecoder().decode(ResizeReq.self, from: body)
                try agent.resizeWindow(windowId: req.window_id, width: req.width, height: req.height)
                return Self.okJSON()
            case .setTitle:
                let req = try JSONDecoder().decode(SetTitleReq.self, from: body)
                try agent.setTitle(windowId: req.window_id, title: req.title)
                return Self.okJSON()
            case .setPosition:
                let req = try JSONDecoder().decode(SetPositionReq.self, from: body)
                try agent.setPosition(windowId: req.window_id, x: req.x, y: req.y)
                return Self.okJSON()
            case .getInfo:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                let info = try agent.getWindowInfo(windowId: req.window_id)
                struct R: Codable { let x: Int; let y: Int; let width: Int; let height: Int; let title: String }
                return try JSONEncoder().encode(R(x: info.x, y: info.y, width: info.width, height: info.height, title: info.title))
            case .maximize:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.maximizeWindow(windowId: req.window_id)
                return Self.okJSON()
            case .minimize:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.minimizeWindow(windowId: req.window_id)
                return Self.okJSON()
            case .restore:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.restoreWindow(windowId: req.window_id)
                return Self.okJSON()
            case .setFullscreen:
                let req = try JSONDecoder().decode(ToggleReq.self, from: body)
                try agent.setFullscreen(windowId: req.window_id, enabled: req.enabled)
                return Self.okJSON()
            case .setOpacity:
                let req = try JSONDecoder().decode(OpacityReq.self, from: body)
                try agent.setOpacity(windowId: req.window_id, opacity: Float(req.opacity))
                return Self.okJSON()
            case .setAlwaysOnTop:
                let req = try JSONDecoder().decode(ToggleReq.self, from: body)
                try agent.setAlwaysOnTop(windowId: req.window_id, enabled: req.enabled)
                return Self.okJSON()
            case .center:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.centerWindow(windowId: req.window_id)
                return Self.okJSON()
            case .present:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                try agent.present(windowId: req.window_id)
                return Self.okJSON()
            case .drawRect:
                let req = try JSONDecoder().decode(RectReq.self, from: body)
                if let cstr = req.colorString { try agent.drawRectangle(windowId: req.window_id, x: req.x, y: req.y, width: req.width, height: req.height, color: cstr) }
                else { try agent.drawRectangle(windowId: req.window_id, x: req.x, y: req.y, width: req.width, height: req.height, color: req.color ?? 0xFFFFFFFF) }
                return Self.okJSON()
            case .clear:
                let req = try JSONDecoder().decode(ColorReq.self, from: body)
                if let cstr = req.colorString { try agent.clear(windowId: req.window_id, color: cstr) }
                else { try agent.clear(windowId: req.window_id, color: req.color ?? 0xFF000000) }
                return Self.okJSON()
            case .drawLine:
                let req = try JSONDecoder().decode(LineReq.self, from: body)
                if let cstr = req.colorString { try agent.drawLine(windowId: req.window_id, x1: req.x1, y1: req.y1, x2: req.x2, y2: req.y2, color: cstr) }
                else { try agent.drawLine(windowId: req.window_id, x1: req.x1, y1: req.y1, x2: req.x2, y2: req.y2, color: req.color ?? 0xFFFFFFFF) }
                return Self.okJSON()
            case .drawCircleFilled:
                let req = try JSONDecoder().decode(CircleReq.self, from: body)
                if let cstr = req.colorString { try agent.drawCircleFilled(windowId: req.window_id, cx: req.cx, cy: req.cy, radius: req.radius, color: cstr) }
                else { try agent.drawCircleFilled(windowId: req.window_id, cx: req.cx, cy: req.cy, radius: req.radius, color: req.color ?? 0xFFFFFFFF) }
                return Self.okJSON()
            case .drawText:
                let req = try JSONDecoder().decode(TextReq.self, from: body)
                try agent.drawText(windowId: req.window_id, text: req.text, x: req.x, y: req.y, font: req.font, size: req.size, color: req.color)
                return Self.okJSON()
            case .captureEvent:
                let req = try JSONDecoder().decode(EventReq.self, from: body)
                if let ev = try agent.captureEvent(windowId: req.window_id, timeoutMs: req.timeout_ms) {
                    return try JSONEncoder().encode(["event": JEvent(ev)])
                } else {
                    return try JSONEncoder().encode([String: String]())
                }
            case .clipboardGet:
                // Require a valid window_id to ensure context
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                _ = try agent.getWindowInfo(windowId: req.window_id)
                let text = try SDLClipboard.getText()
                struct R: Codable { let text: String }
                return try JSONEncoder().encode(R(text: text))
            case .clipboardSet:
                let req = try JSONDecoder().decode(ClipboardSetReq.self, from: body)
                _ = try agent.getWindowInfo(windowId: req.window_id)
                try SDLClipboard.setText(req.text)
                return Self.okJSON()
            case .inputKeyboard:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                _ = try agent.getWindowInfo(windowId: req.window_id)
                let m = try SDLInput.getKeyboardModifiers()
                struct R: Codable { let modifiers: SDLInput.KeyboardModifiers }
                return try JSONEncoder().encode(R(modifiers: m))
            case .inputMouse:
                let req = try JSONDecoder().decode(WindowOnlyReq.self, from: body)
                _ = try agent.getWindowInfo(windowId: req.window_id)
                let s = try SDLInput.getMouseState()
                return try JSONEncoder().encode(s)
            case .displayList:
                let list = try SDLDisplay.list()
                struct R: Codable { let displays: [SDLDisplay.Summary] }
                return try JSONEncoder().encode(R(displays: list))
            case .displayGetInfo:
                let req = try JSONDecoder().decode(DisplayIndexReq.self, from: body)
                let b = try SDLDisplay.getInfo(index: req.index)
                struct R: Codable { let bounds: SDLDisplay.Bounds }
                return try JSONEncoder().encode(R(bounds: b))
            }
        } catch let e as AgentError {
            return Self.errorJSON(from: e)
        } catch {
            return Self.errorJSON(code: "invalid_argument", details: String(describing: error))
        }
    }

    private static func loadExternalOpenAPIYAML() -> Data? {
        let env = ProcessInfo.processInfo.environment
        if let p = env["SDLKIT_OPENAPI_PATH"], !p.isEmpty, FileManager.default.fileExists(atPath: p) {
            return try? Data(contentsOf: URL(fileURLWithPath: p))
        }
        // Try repo-root defaults
        let candidates = [
            "sdlkit.gui.v1.yaml",
            "openapi.yaml",
            "openapi/sdlkit.gui.v1.yaml"
        ]
        for rel in candidates {
            if FileManager.default.fileExists(atPath: rel) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: rel)) { return data }
            }
        }
        return nil
    }

    // MARK: - Models
    private struct OpenWindowReq: Codable { let title: String; let width: Int; let height: Int }
    private struct WindowOnlyReq: Codable { let window_id: Int }
    private struct ResizeReq: Codable { let window_id: Int; let width: Int; let height: Int }
    private struct SetTitleReq: Codable { let window_id: Int; let title: String }
    private struct SetPositionReq: Codable { let window_id: Int; let x: Int; let y: Int }
    private struct ToggleReq: Codable { let window_id: Int; let enabled: Bool }
    private struct OpacityReq: Codable { let window_id: Int; let opacity: Double }
    private struct RectReq: Codable {
        let window_id: Int, x: Int, y: Int, width: Int, height: Int
        let color: UInt32?
        let colorString: String?
        enum CodingKeys: String, CodingKey { case window_id, x, y, width, height, color }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            x = try c.decode(Int.self, forKey: .x)
            y = try c.decode(Int.self, forKey: .y)
            width = try c.decode(Int.self, forKey: .width)
            height = try c.decode(Int.self, forKey: .height)
            if let s = try? c.decode(String.self, forKey: .color) { colorString = s; color = nil }
            else { color = try? c.decode(UInt32.self, forKey: .color); colorString = nil }
        }
    }
    private struct ColorReq: Codable {
        let window_id: Int
        let color: UInt32?
        let colorString: String?
        enum CodingKeys: String, CodingKey { case window_id, color }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            if let s = try? c.decode(String.self, forKey: .color) { colorString = s; color = nil }
            else { color = try? c.decode(UInt32.self, forKey: .color); colorString = nil }
        }
    }
    private struct LineReq: Codable {
        let window_id: Int, x1: Int, y1: Int, x2: Int, y2: Int
        let color: UInt32?
        let colorString: String?
        enum CodingKeys: String, CodingKey { case window_id, x1, y1, x2, y2, color }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            x1 = try c.decode(Int.self, forKey: .x1)
            y1 = try c.decode(Int.self, forKey: .y1)
            x2 = try c.decode(Int.self, forKey: .x2)
            y2 = try c.decode(Int.self, forKey: .y2)
            if let s = try? c.decode(String.self, forKey: .color) { colorString = s; color = nil }
            else { color = try? c.decode(UInt32.self, forKey: .color); colorString = nil }
        }
    }
    private struct CircleReq: Codable {
        let window_id: Int, cx: Int, cy: Int, radius: Int
        let color: UInt32?
        let colorString: String?
        enum CodingKeys: String, CodingKey { case window_id, cx, cy, radius, color }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            window_id = try c.decode(Int.self, forKey: .window_id)
            cx = try c.decode(Int.self, forKey: .cx)
            cy = try c.decode(Int.self, forKey: .cy)
            radius = try c.decode(Int.self, forKey: .radius)
            if let s = try? c.decode(String.self, forKey: .color) { colorString = s; color = nil }
            else { color = try? c.decode(UInt32.self, forKey: .color); colorString = nil }
        }
    }
    private struct TextReq: Codable {
        let window_id: Int, text: String, x: Int, y: Int
        let font: String?
        let size: Int?
        let color: UInt32?
    }
    private struct EventReq: Codable { let window_id: Int; let timeout_ms: Int? }
    private struct ClipboardSetReq: Codable { let window_id: Int; let text: String }
    private struct DisplayIndexReq: Codable { let index: Int }

    private struct JEvent: Codable {
        let type: String
        let x: Int?
        let y: Int?
        let key: String?
        let button: Int?
        init(_ e: SDLKitGUIAgent.Event) {
            switch e.type {
            case .keyDown: type = "key_down"
            case .keyUp: type = "key_up"
            case .mouseDown: type = "mouse_down"
            case .mouseUp: type = "mouse_up"
            case .mouseMove: type = "mouse_move"
            case .quit: type = "quit"
            case .windowClosed: type = "window_closed"
            }
            self.x = e.x; self.y = e.y; self.key = e.key; self.button = e.button
        }
    }

    // MARK: - Error helpers
    private static func okJSON() -> Data { try! JSONEncoder().encode(["ok": true]) }
    private static func errorJSON(code: String, details: String?) -> Data {
        struct Err: Codable { let error: E; struct E: Codable { let code: String; let details: String? } }
        return try! JSONEncoder().encode(Err(error: .init(code: code, details: details)))
    }
    private static func errorJSON(from e: AgentError) -> Data {
        switch e {
        case .windowNotFound: return errorJSON(code: "window_not_found", details: nil)
        case .sdlUnavailable: return errorJSON(code: "sdl_unavailable", details: nil)
        case .notImplemented: return errorJSON(code: "not_implemented", details: nil)
        case .invalidArgument(let msg): return errorJSON(code: "invalid_argument", details: msg)
        case .internalError(let msg): return errorJSON(code: "internal_error", details: msg)
        }
    }
}
