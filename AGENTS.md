# SDLKit – SDLKitGUIAgent (Interactive GUI Agent)

This document defines the root AI agent interface exposed by SDLKit to the FountainAI platform. It formalizes what the AI can do in a GUI through SDLKit and how those capabilities are invoked and implemented.

## Role and Scope

- Purpose: Bridge high‑level AI plans and the low‑level SDLKit API for interactive graphics.
- Responsibilities: Open/close windows, draw/update content, present frames, and optionally capture user events.
- Non‑goals: No AI planning/logic. The agent only exposes safe, bounded GUI operations.

## Capabilities (Agent Tools)

These functions are presented to the planner (e.g., via OpenAI function calling or a Tools/OpenAPI layer). Arguments are JSON‑serializable. Errors are returned as structured failures.

- openWindow(title: string, width: int, height: int) -> windowId
  - Opens a window, returning a handle used by subsequent calls. If opening fails, returns an error.

- closeWindow(windowId: int) -> void
  - Closes/destroys the window and associated rendering resources. No‑op or error if not found.

- drawText(windowId: int, text: string, x: int, y: int, font?: string, size?: int, color?: string|int) -> void
  - Renders text at coordinates. Requires SDL_ttf for real text; before that, may be unimplemented or fall back to a placeholder. Should present or be followed by `present`.

- drawRectangle(windowId: int, x: int, y: int, width: int, height: int, color: string|int) -> void
  - Draws a filled rectangle (and is a model for future primitives like lines/circles). Uses SDLKit’s renderer.

- present(windowId: int) -> void
  - Presents the back buffer to screen. Kept explicit so callers can batch multiple draw calls before a single present to reduce flicker.

- captureEvent(windowId: int, timeoutMs?: int) -> Event? (potential/optional)
  - Lets the AI wait for a user event. May require a “pending”/resume mechanism in the function‑caller, or be deferred until after one‑way calls are stable. Event would be a small structured object (e.g., `{ type: "keyDown", key: "A" }`).

## Implementation Notes

- Registration: Implemented in SDLKit, registered with FountainKit’s tool registry. Exposed via internal function‑caller or local tool server.
- Resource model: Maintain maps from `windowId` to `SDLWindow`/`SDLRenderer` for multi‑window support.
- Threading: Perform SDL calls on the main thread where required (especially on macOS). Dispatch work accordingly.
- Present policy: Either auto‑present in draw calls or require explicit `present`. Keeping `present` explicit grants more control; choose one policy and document it.
- Cleanup: On user‑initiated close (e.g., SDL_QUIT), auto‑cleanup resources and inform callers/planner so they don’t render to a dead window.

## Event Model

- Pull: `captureEvent` blocks (with optional timeout) and returns a single event; suitable for simple flows.
- Push (optional): The agent may push events to the system (e.g., via telemetry or a stream) such as `window_closed` or key presses. Start with pull; consider push as interactivity grows.

## Integration in Plans

Agent functions appear as tools the planner can choose. Example plan: get data → `openWindow` → `drawText`/`drawImage` → `present` → optionally loop on `captureEvent` → `closeWindow`.

## Security and Permissions

- The agent opens windows on the local machine. Enable only in appropriate contexts (desktop/dev), disabled on locked‑down servers by default.
- Provide a configuration toggle to enable/disable GUI features in FountainKit.

## Pseudo‑code Sketch (illustrative)

```swift
final class SDLKitGUIAgent: ToolAgent {
    private var windows: [Int: SDLWindow] = [:]
    private var renderers: [Int: SDLRenderer] = [:]
    private var nextID: Int = 1

    func openWindow(title: String, width: Int, height: Int) throws -> Int {
        let id = nextID; nextID += 1
        let window = SDLWindow(config: .init(title: title, width: width, height: height))
        try window.open()
        let renderer = SDLRenderer(width: width, height: height, for: window)
        windows[id] = window
        renderers[id] = renderer
        return id
    }

    func closeWindow(windowId: Int) {
        guard let window = windows.removeValue(forKey: windowId) else { return }
        renderers.removeValue(forKey: windowId)
        window.close()
    }

    func drawText(windowId: Int, text: String, x: Int, y: Int, font: String?, size: Int?, color: UInt32?) throws {
        guard let renderer = renderers[windowId] else { throw AgentError.windowNotFound }
        let fontName = font ?? "Arial"
        let fontSize = size ?? 16
        if SDLKit.isTextRenderingEnabled {
            let fontObj = try SDLFont(name: fontName, size: fontSize)
            renderer.drawText(fontObj, text: text, x: x, y: y, color: color ?? 0xFFFFFFFF)
        } else {
            // Optional: draw placeholder or no‑op
        }
        renderer.present()
    }

    // drawRectangle, present, captureEvent, …
}
```

## OpenAPI Sketch (illustrative)

```yaml
paths:
  /agent/gui/window/open:
    post:
      summary: Open a GUI window
      operationId: guiOpenWindow
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                title:  { type: string }
                width:  { type: integer }
                height: { type: integer }
      responses:
        "200":
          description: Window opened
          content:
            application/json:
              schema:
                type: object
                properties:
                  window_id: { type: integer }
```

## Future Extensions

- drawImage(texture/image)
- Primitive shapes (lines, circles), text layout
- Event streaming/telemetry integration
- Multi‑window management helpers

## References

- Teatro AGENTS.md: https://github.com/Fountain-Coach/Teatro/blob/21d080f70b2c238469bbb0133a5f14b20afdd0ab/AGENTS.md
- Related GUI backend sources (TeatroGUI, SDL components) as cited in the design document.

