import Foundation

@MainActor
public struct SDLKitJSONAgent {
    private let agent: SDLKitGUIAgent
    public init() { self.agent = SDLKitGUIAgent() }
    public init(agent: SDLKitGUIAgent) { self.agent = agent }

    public enum Endpoint: String {
        case open = "/agent/gui/window/open"
        case close = "/agent/gui/window/close"
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
    }

    public func handle(path: String, body: Data) -> Data {
        guard let ep = Endpoint(rawValue: path) else { return Self.errorJSON(code: "invalid_endpoint", details: path) }
        do {
            switch ep {
            case .openapiYAML:
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
            }
        } catch let e as AgentError {
            return Self.errorJSON(from: e)
        } catch {
            return Self.errorJSON(code: "invalid_argument", details: String(describing: error))
        }
    }

    // MARK: - Models
    private struct OpenWindowReq: Codable { let title: String; let width: Int; let height: Int }
    private struct WindowOnlyReq: Codable { let window_id: Int }
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
