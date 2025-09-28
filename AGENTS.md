# AGENTS.md — SDLKit Repo Guidelines and GUI Agent Contract (v1)

This document serves two purposes:

1) Repository guidance for humans and coding agents working here.
2) The public SDLKit GUI Agent contract used by FountainAI planners/tools.

---

## 1. Repo Overview

- Module: SDLKit — Swift Package wrapping SDL3 with a Swift‑friendly API.
- System bindings: CSDL3 — SwiftPM system‑library target binding to native SDL3.
- Agent layer: SDLKitGUIAgent — exposes bounded GUI tools to FountainAI.

### 1.1 Project Layout (skeleton)

- Package.swift
- Sources/
  - CSDL3/
    - module.modulemap
    - shim.h
  - SDLKit/
    - SDLKit.swift
    - Agent/SDLKitGUIAgent.swift
    - Core/SDLWindow.swift
    - Core/SDLRenderer.swift
    - Support/Errors.swift
- Tests/
  - SDLKitTests/SDLKitTests.swift

---

## 2. Setup & Build

- macOS: `brew install sdl3`
- Linux (Debian/Ubuntu): `sudo apt-get install -y libsdl3-dev`
- Windows: use vcpkg: `vcpkg install sdl3` and ensure headers/libs are discoverable.
- Build: `swift build`
- Test: `swift test`
- Note: `CSDL3` relies on system SDL3 being present at compile/link time.

---

## 3. Coding Conventions

- Follow Swift API Design Guidelines; keep public API Swift‑idiomatic.
- Contain C interop in `CSDL3` and internal wrappers; don’t leak raw pointers publicly.
- Use typed `Error` enums with stable cases and user‑actionable messages.
- Execute SDL calls on the main thread when required (especially on Apple platforms).
- Document public APIs; keep docs and code synchronized.

---

## 4. Testing & CI

- Use XCTest in `Tests/SDLKitTests`.
- Headless friendliness: Prefer rendering paths that can no‑op or skip in headless CI.
- If SDL3 is missing, skip integration tests with a clear reason rather than failing hard.

---

## 5. Security & Permissions

- GUI features are disabled by default in server/headless contexts.
- Expose explicit configuration flags to enable local GUI actions.

---

## 6. Observability

- Logging: info/warn/error with component tags (e.g., `SDLKit.Agent`, `SDLKit.Window`).
- Metrics: counts for opens/closes, presents, and error types.
- Tracing: include correlation IDs in agent responses when routed through a gateway.

---

## 7. Versioning

- Agent version: `sdlkit.gui.v1`.
- Additive evolution only for minor versions; avoid breaking existing tools.
- Deprecations: add warnings and grace periods before removal.

---

## 8. Configuration (env vars)

- `SDLKIT_GUI_ENABLED` (default true on desktop, false on server): enable/disable GUI tools.
- `SDLKIT_PRESENT_POLICY` = `auto|explicit` (default `explicit`): draw batching vs implicit present.
- `SDLKIT_MAX_WINDOWS` (default 8): soft cap on concurrent windows.
- `SDLKIT_LOG_LEVEL` = `debug|info|warn|error` (default `info`).

---

## 9. Limits & Lifecycle

- Main‑thread policy: All SDL calls hop to the main thread when required.
- Cleanup: User‑initiated window close triggers resource cleanup and a `window_closed` signal.
- Timeouts: Tool calls should complete promptly; planners may retry on `timeout`.

---

## 10. GUI Agent Contract (sdlkit.gui.v1)

Purpose: Provide bounded, safe GUI actions via JSON tools. No arbitrary drawing beyond declared tools.

### 10.1 Capabilities

- openWindow
  - Request JSON: `{ "title": string, "width": integer >= 1, "height": integer >= 1 }`
  - Response JSON: `{ "window_id": integer }`

- closeWindow
  - Request: `{ "window_id": integer }`
  - Response: `{ "ok": boolean }`

- drawText
  - Request: `{ "window_id": integer, "text": string, "x": integer, "y": integer, "font"?: string, "size"?: integer, "color"?: string|integer }`
  - Response: `{ "ok": boolean }`
  - Notes: Real text requires SDL_ttf; otherwise may be unimplemented or draw a placeholder.

- drawRectangle
  - Request: `{ "window_id": integer, "x": integer, "y": integer, "width": integer, "height": integer, "color": string|integer }`
  - Response: `{ "ok": boolean }`

- clear (new)
  - Request: `{ "window_id": integer, "color": string|integer }`
  - Response: `{ "ok": boolean }`

- drawLine (new)
  - Request: `{ "window_id": integer, "x1": integer, "y1": integer, "x2": integer, "y2": integer, "color": string|integer }`
  - Response: `{ "ok": boolean }`

- drawCircleFilled (new)
  - Request: `{ "window_id": integer, "cx": integer, "cy": integer, "radius": integer >= 0, "color": string|integer }`
  - Response: `{ "ok": boolean }`

- present
  - Request: `{ "window_id": integer }`
  - Response: `{ "ok": boolean }`

- captureEvent (optional)
  - Request: `{ "window_id": integer, "timeout_ms"?: integer }`
  - Response: `{ "event"?: Event }`

### 10.2 Errors (canonical)

- `window_not_found`: specified window does not exist.
- `sdl_unavailable`: SDL not installed/initialized.
- `not_implemented`: capability not available on this build.
- `invalid_argument`: failed validation (e.g., negative size, bad color).
- `timeout`: no event within requested time.
- `internal_error`: unexpected failure; include `details` field.

### 10.3 Event Schema

- Event (object):
  - `type`: `key_down|key_up|mouse_down|mouse_up|mouse_move|quit|window_closed`
  - Additional fields per type, e.g., `key`, `button`, `x`, `y`.

### 10.4 OpenAPI Sketch

- `POST /agent/gui/window/open` → `{ window_id }`
- Similar endpoints for `close`, `drawText`, `drawRectangle`, `present`, `captureEvent`.
- New endpoints: `clear`, `drawLine`, `drawCircleFilled`.

### 10.5 Threading & Present Policy

- Threading: Calls can arrive from any thread; the agent serializes effects on the main thread.
- Present policy: `explicit` (default) favors batching; `auto` presents after each draw.

---

## 11. Contributor Workflow (for humans and coding agents)

- Build with `swift build`; test with `swift test`.
- Keep patches focused; avoid unrelated refactors.
- Update docs when changing public APIs or behavior.
- To add a new tool:
  - Extend the schema in this file.
  - Implement in `Sources/SDLKit/Agent` with validation and error mapping.
  - Add tests in `Tests/SDLKitTests` and sample usage.
  - For text rendering (SDL_ttf): optional inclusion is scaffolded. When available at build/link time, enable `drawText`; otherwise return `not_implemented`.

---

## 12. Appendix — Code Skeleton

See the files in this repository for a minimal, compilable skeleton:

- `Package.swift:1`
- `Sources/CSDL3/module.modulemap:1`, `Sources/CSDL3/shim.h:1`
- `Sources/SDLKit/SDLKit.swift:1`
- `Sources/SDLKit/Agent/SDLKitGUIAgent.swift:1`
- `Sources/SDLKit/Core/SDLWindow.swift:1`, `Sources/SDLKit/Core/SDLRenderer.swift:1`
- `Sources/SDLKit/Support/Errors.swift:1`
- `Tests/SDLKitTests/SDLKitTests.swift:1`

---

## 13. References

- Teatro AGENTS.md (context): https://github.com/Fountain-Coach/Teatro/blob/21d080f70b2c238469bbb0133a5f14b20afdd0ab/AGENTS.md
- SDL3 installation docs per platform; see Setup.
