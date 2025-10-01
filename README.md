# SDLKit — Swift SDL3 Wrapper (Pre‑Alpha)

SDLKit is a Swift Package that wraps SDL3 and exposes a Swift‑friendly API and a small, bounded GUI Agent for the FountainAI ecosystem.

- Purpose: decouple SDL3 interop from higher‑level modules, enable reuse across projects, and provide a safe tool surface for AI planners.
- SDL upstream: this project targets the Fountain‑Coach SDL fork: https://github.com/Fountain-Coach/SDL

## Status

- Alpha: Core window + renderer wrappers are wired to SDL3 when available; headless builds remain supported via `-DHEADLESS_CI`.
- JSON Agent implements the documented tools (window controls, primitives, batches, textures, optional text, events, clipboard, input, display, screenshot).
- See `AGENTS.md:1` for the official agent contract and repo guidelines.

## Project Structure

- `Package.swift:1` — SwiftPM definition with system library `CSDL3` and library target `SDLKit`.
- `Sources/CSDL3/module.modulemap:1`, `Sources/CSDL3/shim.h:1` — system bindings for SDL3 headers and link flags.
- `Sources/SDLKit/SDLKit.swift:1` — config and global feature flags.
- `Sources/SDLKit/Support/Errors.swift:1` — canonical error types for tools.
- `Sources/SDLKit/Core/SDLWindow.swift:1`, `Sources/SDLKit/Core/SDLRenderer.swift:1` — placeholders for wrappers.
- `Sources/SDLKit/Agent/SDLKitGUIAgent.swift:1` — agent with stubbed tool methods.
- `Tests/SDLKitTests/SDLKitTests.swift:1` — minimal XCTest.

### Planned Extensions

In addition to the existing sources above, upcoming work for the 3D and compute extension will add new folders:
- `Sources/SDLKit/Graphics/` — platform‑specific backends and a `RenderBackend` protocol.
- `Sources/SDLKit/Scene/` — scene graph types (`Scene`, `SceneNode`, `Camera`, `Light`, `Mesh`, `Material`).
- `Sources/SDLKit/Shaders/` — single‑source shader code and build scripts.
- `Sources/SDLKit/Compute/` — GPU compute interfaces.
These directories are not yet present in the repository but are described in the implementation strategy and `AGENTS.md`.

## Using Our SDL Fork

This package is designed to work with the Fountain‑Coach SDL3 fork:

- Repo: https://github.com/Fountain-Coach/SDL
- Follow that repo’s instructions to build/install SDL3 for your platform.
- SDLKit discovers SDL3 via `pkg-config` name `sdl3` and links `SDL3`.
- If you install the fork to a nonstandard prefix, set:
  - `SDL3_INCLUDE_DIR` to the SDL include directory (e.g., `/opt/sdl/include`)
  - `SDL3_LIB_DIR` to the SDL lib directory (e.g., `/opt/sdl/lib`)
  These are picked up by `Package.swift` to pass `-I`/`-L` to the build.

## Install SDL3

- macOS: `brew install sdl3` (or build/install the Fountain‑Coach fork if preferred).
- Linux (Debian/Ubuntu): `sudo apt-get install -y libsdl3-dev` (or build from the fork).
- Windows: install via vcpkg (`vcpkg install sdl3`) and ensure headers/libs are discoverable.
  - If using a custom prefix, export `LD_LIBRARY_PATH=/path/to/prefix/lib:$LD_LIBRARY_PATH` when running binaries so the dynamic linker can find `libSDL3.so`.

## Build & Test

- Requires Swift 6.1+
- Build: `swift build`
- Test: `swift test`

### Shader toolchain prerequisites

Compiling the cross-platform shader library requires external tools:

- [DirectX Shader Compiler (DXC)](https://github.com/microsoft/DirectXShaderCompiler)
- [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross)
- Apple’s Metal toolchain (`metal` and `metallib`) from Xcode command line tools (macOS only)
- Python 3 (for the shader build helper script)

Install them on your platform and ensure they are available on `PATH` before building shaders.

The SwiftPM `ShaderBuildPlugin` target runs automatically when the `SDLKit` module builds. To invoke it manually (for example to pre-populate shader caches) run:

```bash
python3 Scripts/ShaderBuild/build-shaders.py "$(pwd)" .build/shader-cache
```

Generated artifacts are copied into `Sources/SDLKit/Generated/{dxil,spirv,metal}` and shipped with the library bundle.

### Headless CI mode

- CI runs without installing SDL3 and compiles in headless mode using a build define.
- To mirror CI locally: `swift test -Xswiftc -DHEADLESS_CI`
- In `HEADLESS_CI` builds, SDL interop and linking are compiled out. GUI calls return `sdlUnavailable`.

### Consumer builds (with autolink)

- The system module `CSDL3` autolinks `SDL3` for consumer builds. Install SDL3 via your platform’s package manager or the Fountain‑Coach fork and ensure headers/libs are discoverable. See Install SDL3 above.
- For text rendering (SDL_ttf), use the `SDLKitTTF` product to autolink `SDL3_ttf`:
  - Package.swift dependency example:
    - `.package(url: "https://github.com/your-org/SDLKit.git", from: "0.1.0")`
    - target deps: `[ .product(name: "SDLKitTTF", package: "SDLKit") ]`
  - Then in Swift: `import SDLKitTTF` (this also re‑exports `SDLKit`).
  - Without `SDLKitTTF`, `drawText` remains available but returns `notImplemented` if SDL_ttf isn’t present at build/link time.

## Configuration

The agent reads several environment variables at runtime. Key options include:

- `SDLKIT_MAX_WINDOWS` — soft cap on concurrently open windows. Defaults to `8`. Set to any positive integer to raise or lower the cap. Non-positive or non-numeric values fall back to the default.

### Colors

- Colors accept integer ARGB (0xAARRGGBB) or strings.
- String formats: `#RRGGBB`, `#AARRGGBB`, `0xRRGGBB`, `0xAARRGGBB`, and CSS color names (e.g., `aliceblue`, `tomato`, `rebeccapurple`).

### Fonts

- `drawText` accepts a `font` string that can be:
  - A filesystem path to a `.ttf` file
  - `system:default` (macOS: tries common system fonts like Arial Unicode)
  - `name:<id>` where `<id>` was previously registered via `SDLFontRegistry.register(name:path:)`
- If `font` is omitted, the agent tries `system:default`.
- If `size` is omitted, the agent uses `16`.
- `SDLKitState.isTextRenderingEnabled` returns `true` once the optional `SDLKitTTF` product (and SDL_ttf) are linked, allowing 
text rendering paths to activate.

macOS CI: not enabled by default. If you need macOS validation, set up a self‑hosted macOS runner and add a job targeting `runs-on: [self-hosted, macOS]`.

## Quick Start (pre‑alpha)

```swift
import SDLKit

let agent = SDLKitGUIAgent()
let windowId = try agent.openWindow(title: "SDLKit", width: 800, height: 600)
// drawText/drawRectangle/present currently throw notImplemented until wired
agent.closeWindow(windowId: windowId)
```

### Triangle & SceneGraph Demo (Metal/D3D12/Vulkan)

- Run: `swift run SDLKitDemo`
- By default the app opens a window, selects the platform backend (Metal on macOS, D3D12 on Windows, Vulkan on Linux), uploads a static triangle, and walks a `beginFrame → draw → endFrame` loop using the new `RenderBackend` protocol.
- Override the backend via persisted setting or env:
  - Persisted: `swift run SDLKitSettings set --key render.backend.override --value metal`
  - Env: `SDLKIT_RENDER_BACKEND=metal|d3d12|vulkan swift run SDLKitDemo`
- Force the legacy 2D smoke test instead of the triangle with `SDLKIT_DEMO_FORCE_2D=1 swift run SDLKitDemo`.
- The previous rectangle/line/circle/text showcase still runs in legacy mode and continues to honor SDL_ttf availability.
### Golden Image Parity (M3)

- Enable tests: `SDLKIT_GOLDEN=1 swift test` (optional `SDLKIT_GOLDEN_WRITE=1` to store current hash)
- Manage references with CLI:
  - Write: `swift run SDLKitGolden --backend metal --size 256x256 --material basic_lit --write`
  - Verify: `swift run SDLKitGolden --backend metal --size 256x256 --material basic_lit`

### Settings & Secrets

- Settings persist via FountainStore under `.fountain/sdlkit` (collection `settings`). Examples:
  - `swift run SDLKitSettings set --key render.backend.override --value metal`
  - `swift run SDLKitSettings set-bool --key vk.validation --value true`
  - `swift run SDLKitSettings set --key scene.default.material --value basic_lit`
  - `swift run SDLKitSettings set --key scene.default.baseColor --value "1.0,1.0,1.0,1.0"`
  - `swift run SDLKitSettings set --key scene.default.lightDirection --value "0.3,-0.5,0.8"`
- Migration from env to settings:
  - `swift run SDLKitMigrate` migrates known `SDLKIT_*` env vars into FountainStore settings and prints a JSON summary.
- Shader tool paths:
  - Set with SDLKitSettings (e.g., `shader.dxc.path`) and run `swift run SDLKitSettings write-env` to generate `.fountain/sdlkit/shader-tools.env` consumed by the shader build plugin.

### Settings Reference

- Keys and types (all stored as strings; booleans serialized as "1"/"0"):
  - render.backend.override: String (metal|d3d12|vulkan)
  - present.policy: String (auto|explicit)
  - vk.validation: Bool
  - dx12.debug_layer: Bool
  - shader.root: String (path)
  - shader.dxc.path: String (path)
  - shader.spirv_cross.path: String (path)
  - shader.metal.path: String (path)
  - shader.metallib.path: String (path)
  - scene.default.material: String (unlit|basic_lit)
  - scene.default.baseColor: String ("r,g,b,a")
  - scene.default.lightDirection: String ("x,y,z")
  - golden.last.key: String
  - golden.auto.write: Bool

- Example JSON dump (via `swift run SDLKitSettings dump`):
  {
    "render.backend.override": "metal",
    "present.policy": "auto",
    "vk.validation": "1",
    "scene.default.material": "basic_lit",
    "scene.default.baseColor": "1.0,1.0,1.0,1.0",
    "scene.default.lightDirection": "0.3,-0.5,0.8"
  }
- Secrets persist via SecretStore (Keychain on macOS, Secret Service on Linux, file keystore fallback).
  - Example: `swift run SDLKitSecrets set --key light_dir --value "0.3,-0.5,0.8"`
  - The demo reads `light_dir` to set the scene light when present.
## Agent Contract

See `AGENTS.md:1` for the `sdlkit.gui.v1` tool definitions, error codes, event schema, threading policy, present policy, configuration keys, and contributor workflow.

## Roadmap

- Wire actual SDL window/renderer in `Core` wrappers.
- Implement agent tools (open/close/present/draw primitives/text).
- Add optional SDL_ttf text rendering and color parsing.
- Headless/CI execution paths and cross‑platform tests.
- OpenAPI/tool wiring samples and end‑to‑end examples.

### 3D & Compute Extension Tasks (planned)

- Integrate native GPU contexts (Metal, Direct3D, Vulkan) behind a new `RenderBackend` abstraction.
- Add a cross‑platform shader pipeline (HLSL → SPIR‑V/DXIL/MSL) via a `ShaderAgent`.
- Introduce a high‑level scene graph to manage 3D objects, lights and cameras via a `SceneGraphAgent`.
- Expose GPU compute pipelines to accelerate physics, audio and machine‑learning workloads via a `ComputeAgent`.
- Document the new agent protocols and extension architecture in `AGENTS.md` and the Implementation Strategy.

## Contributing

- Start with `AGENTS.md:1` for repo conventions and the agent schema.
- Keep changes focused; update docs when adding/changing public API.
- Platform notes and SDL build guidance live in the SDL fork and will be referenced here as wiring progresses.

## JSON Tool Layer

This package provides a simple JSON routing helper for the agent: `SDLKitJSONAgent`. You can embed it in your own HTTP server or IPC layer.

Example usage:

```swift
import SDLKit

let router = SDLKitJSONAgent()

// Open
let openReq = #"{ "title":"Demo", "width":640, "height":480 }"#.data(using: .utf8)!
let openRes = router.handle(path: "/agent/gui/window/open", body: openReq)
// { "window_id": 1 }

// Draw rectangle with color string
let rectReq = #"{ "window_id":1, "x":40, "y":40, "width":200, "height":120, "color":"#3366FF" }"#.data(using: .utf8)!
_ = router.handle(path: "/agent/gui/drawRectangle", body: rectReq)

// Clear background
let clearReq = #"{ "window_id":1, "color":"#0F0F13" }"#.data(using: .utf8)!
_ = router.handle(path: "/agent/gui/clear", body: clearReq)

// Present
let presentReq = #"{ "window_id":1 }"#.data(using: .utf8)!
_ = router.handle(path: "/agent/gui/present", body: presentReq)
```

Endpoints (paths):
- `/agent/gui/window/open` → `{ window_id }`
- `/agent/gui/window/close` → `{ ok }`
- `/agent/gui/present` → `{ ok }`
- `/agent/gui/drawRectangle` → `{ ok }` (color as string or integer ARGB)
- `/agent/gui/clear` → `{ ok }` (color as string or integer ARGB)
- `/agent/gui/drawLine` → `{ ok }`
- `/agent/gui/drawCircleFilled` → `{ ok }`
- `/agent/gui/drawText` → `{ ok }` (requires SDL_ttf)
- `/agent/gui/captureEvent` → `{ event?: { ... } }`

Errors are returned as `{ "error": { "code": string, "details"?: string } }` with canonical codes defined in `AGENTS.md`.

### OpenAPI (source of truth)

- Canonical spec: repo root `sdlkit.gui.v1.yaml` (or `openapi.yaml`).
- Discovery order for serving docs:
  - `SDLKIT_OPENAPI_PATH` (YAML or JSON)
  - `sdlkit.gui.v1.yaml` or `openapi.yaml` at repo root
  - `openapi/sdlkit.gui.v1.yaml` (legacy fallback only)
- Served endpoints:
  - `GET /openapi.yaml` → YAML (external file if present, else embedded)
  - `GET /openapi.json` → JSON mirror. If an external YAML is present, it is converted to JSON at runtime; otherwise an external JSON is served when present; else a generated JSON from the embedded spec is returned.

#### YAML→JSON Conversion (Yams)

- The agent uses a YAML→JSON converter to ensure `/openapi.json` mirrors the external YAML exactly.
- Converter is enabled by default via the Yams dependency and a compile‑time flag `OPENAPI_USE_YAMS`.
- Opt‑out: set `SDLKIT_NO_YAMS=1` at build time to disable Yams and the converter.
  - Example: `SDLKIT_NO_YAMS=1 swift build`
  - In this mode, `/openapi.json` serves an external JSON if present, else the embedded JSON.
- Tests: deep comparison between converted YAML and served JSON is enabled by default and skipped automatically when Yams is disabled.

### Example HTTP Server (separate)

- A minimal HTTP server sample is provided under `Examples/SDLKitJSONServer` to avoid cluttering the main package.
- It uses SwiftNIO and routes POST JSON bodies to `SDLKitJSONAgent`.

Run:
- `cd Examples/SDLKitJSONServer`
- `swift run SDLKitJSONServer`
- Default bind: `127.0.0.1:8080`. Configure via env: `SDLKIT_SERVER_HOST`, `SDLKIT_SERVER_PORT`.

Curl examples:
- Open: `curl -sX POST localhost:8080/agent/gui/window/open -d '{"title":"Demo","width":640,"height":480}' -H 'Content-Type: application/json'`
- Draw: `curl -sX POST localhost:8080/agent/gui/drawRectangle -d '{"window_id":1,"x":40,"y":40,"width":200,"height":120,"color":"#3366FF"}' -H 'Content-Type: application/json'`
- Present: `curl -sX POST localhost:8080/agent/gui/present -d '{"window_id":1}' -H 'Content-Type: application/json'`

Note: GUI requires SDL3 installed and `SDLKIT_GUI_ENABLED=1` in your environment.

## 3D & Compute Extension (pre‑alpha)

We are actively designing and implementing a major extension to SDLKit that brings **cross‑platform 3D rendering** and **GPU compute** support to the framework.  This extension will coexist with the existing 2D agent and will enable advanced graphics and compute workflows within the FountainAI ecosystem.

### Highlights

- **Scene Graph:** A hierarchy of `Scene`, `SceneNode`, `Camera`, `Light`, `Mesh` and `Material` types for organising 3D content.
- **Multi‑API Rendering:** A `GraphicsAgent` will manage native GPU contexts and backends for **Metal**, **Direct3D** and **Vulkan**, providing a unified `RenderBackend` interface.
- **Shader Pipeline:** Shaders authored in HLSL will be compiled at build time into platform‑specific formats (MSL/DXIL/SPIR‑V) via a `ShaderAgent`.
- **GPU Compute:** A `ComputeAgent` will expose compute pipelines to accelerate audio DSP, physics simulations and machine‑learning workloads.
- **Modular Design:** These capabilities are modularised into dedicated agents (see `AGENTS.md` for full specifications) and will integrate non‑destructively with the existing 2D API.

See the **Implementation Strategy for Extending SDLKit with 3D Graphics, Multi‑API Shaders, and GPU Compute (PDF)** in this repo and **AGENTS.md** for the detailed design and current status.

## Agent Specifications

The 3D & compute extension introduces several specialized agents.  For a high‑level overview, start with `AGENTS.md`.  Each agent has its own detailed specification in a companion Markdown file at the root of this repository:

- `GraphicsAgent.md` — implementation and API contract for the low‑level rendering backend (Metal, Direct3D, Vulkan).
- `ShaderAgent.md` — compiler toolchain and pipeline creation for shaders (HLSL → SPIR‑V/DXIL/MSL).
- `ComputeAgent.md` — GPU compute abstractions for tasks such as audio DSP, physics and machine learning.
- `SceneGraphAgent.md` — high‑level scene graph API (nodes, cameras, lights, meshes, materials) and draw submission protocol.

Consult these documents when contributing to or integrating with the 3D & compute extension.
