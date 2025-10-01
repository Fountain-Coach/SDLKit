# SDLKit — Swift SDL3 Wrapper (Pre‑Alpha)

*Cross-platform Swift access to SDL3 with graphics, compute, and GUI agents built for humans and autonomous planners alike.*

SDLKit wraps SDL3 with a Swift-first API that keeps the event loop, windowing, and rendering primitives approachable for toolsmiths and automation agents. The package separates SDL interop from higher-level modules so teams can reuse the foundation across projects while exposing a predictable surface area for AI planners. SDLKit targets the Fountain‑Coach SDL fork (https://github.com/Fountain-Coach/SDL) and adds modern 3D, shader, and compute systems on top of it.

> **Start here:** [Quickstart](#quick-start-pre-alpha) · [Install](#install-sdl3) · [Architecture](#project-structure) · [Docs](/docs)

## Status

SDLKit is currently in **alpha**: core window and renderer wrappers bind to SDL3 when available, and headless builds remain supported via `-DHEADLESS_CI`. The JSON Agent implements the documented window controls, primitive drawing, batching, texture uploads, optional text, events, clipboard access, input, display, and screenshot tools. Cross-platform 3D modules are live, providing Metal, D3D12, and Vulkan backends, a scene graph for transform propagation, and compute pipelines that share shader metadata. See `AGENTS.md:1` for the authoritative agent contract and repository guidelines.

## Project Structure

- `Package.swift:1` — SwiftPM definition with system library `CSDL3`, the main `SDLKit` library, and the shader build plugin hook.
- `Sources/CSDL3/module.modulemap:1`, `Sources/CSDL3/shim.h:1` — system bindings for SDL3 headers and link flags.
- `Sources/SDLKit/Core/SDLWindow.swift:1`, `Sources/SDLKit/Core/SDLRenderer.swift:1` — Swift wrappers around SDL windowing and renderer state.
- `Sources/SDLKit/Graphics/` — shared render abstractions plus Metal, Direct3D 12, Vulkan, and stub backends for tests. The `RenderBackend` protocol defines buffer, texture, graphics, and compute entry points while `RenderBackendFactory` selects the platform implementation at runtime.【F:Sources/SDLKit/Graphics/RenderBackend.swift†L1-L118】【F:Sources/SDLKit/Graphics/BackendFactory.swift†L1-L120】
- `Sources/SDLKit/SceneGraph/` — scene graph nodes, cameras, mesh registration, material bindings, and the renderer that walks the graph per frame.【F:Sources/SDLKit/SceneGraph/SceneGraph.swift†L1-L132】【F:Sources/SDLKit/SceneGraph/SceneGraph.swift†L133-L224】
- `Sources/SDLKit/Generated/` — committed shader artifacts (DXIL, SPIR-V, Metallib) that ship with the package and are loaded by `ShaderLibrary`.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L120-L188】
- `Shaders/graphics/`, `Shaders/compute/`, and `Scripts/ShaderBuild/` — single-source HLSL/compute kernels, reference Metal hand-written sources, and the Python build helper executed by the SwiftPM plugin.【F:Scripts/ShaderBuild/build-shaders.py†L8-L95】
- `Tests/SDLKitTests/` — smoke tests for shader artifacts, graphics/scene rendering, compute interop, and optional golden image verification per backend.【F:Tests/SDLKitTests/GoldenImageTests.swift†L1-L80】【F:Tests/SDLKitTests/SceneGraphComputeInteropTests.swift†L1-L41】

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

### Shader toolchain workflow

SDLKit ships committed shader binaries, but the toolchain is part of the repository so contributors can rebuild them or add new modules.

1. **Install external tools**
   - DXC is required for HLSL → DXIL/SPIR-V compilation. Set `SDLKIT_SHADER_DXC` or add `dxc` to `PATH`.
   - Optional: SPIRV-Cross converts SPIR-V → MSL when native `.metal` sources are unavailable (`SDLKIT_SHADER_SPIRV_CROSS`).
   - Optional: Apple `metal`/`metallib` (macOS) build `.metallib` outputs directly. Environment variables `SDLKIT_SHADER_METAL` and `SDLKIT_SHADER_METALLIB` override discovery.【F:Scripts/ShaderBuild/build-shaders.py†L20-L96】
   - Python 3 drives the helper script invoked by SwiftPM.
   - You can also place tool binaries under `External/Toolchains/bin` to avoid modifying your global PATH.【F:Scripts/ShaderBuild/build-shaders.py†L20-L40】

2. **Provide per-project overrides**
   - Optional `.fountain/sdlkit/shader-tools.env` files inject environment overrides when the plugin runs, letting teams codify tool paths or compiler flags.【F:Plugins/ShaderBuildPlugin/Plugin.swift†L16-L33】

3. **Invoke the build**
   - Building `SDLKit` automatically triggers the `ShaderBuildPlugin`, which calls `Scripts/ShaderBuild/build-shaders.py <package-root> <workdir>` before compilation.【F:Plugins/ShaderBuildPlugin/Plugin.swift†L10-L31】
   - Manual rebuild: `python3 Scripts/ShaderBuild/build-shaders.py "$(pwd)" .build/shader-cache`. The script emits DXIL/SPIR-V/Metallib artifacts, writes optional intermediate `.msl/.air` files, and records a `shader-build.log` summary in the working directory.【F:Scripts/ShaderBuild/build-shaders.py†L58-L189】

4. **Artifact layout**
   - Final binaries are copied into `Sources/SDLKit/Generated/{dxil,spirv,metal}` and loaded by `ShaderLibrary` at runtime. The library also exposes compute shaders (`vector_add`, `scenegraph_wave`) so both graphics and compute paths share the same metadata.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L120-L256】

5. **Verification**
   - `swift test --filter ShaderArtifactsTests` confirms all expected shader files exist and match the manifest.【F:Tests/SDLKitTests/ShaderArtifactsTests.swift†L20-L40】

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

## Graphics, SceneGraph, and Compute Modules

SDLKit’s 3D stack is implemented and ready for extension work:

- **Render backends** create buffers, textures, graphics pipelines, and compute pipelines through a shared `RenderBackend` API. Platform factories select Metal, D3D12, Vulkan, or a stub backend based on build configuration so tests can run headless.【F:Sources/SDLKit/Graphics/RenderBackend.swift†L1-L118】【F:Sources/SDLKit/Graphics/BackendFactory.swift†L1-L120】
- **ShaderLibrary** packages graphics shaders (`unlit_triangle`, `basic_lit`) and compute programs (`vector_add`, `scenegraph_wave`), returning reflection metadata and cached artifacts for each API.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L164-L256】
- **SceneGraph** orchestrates materials, mesh registration, world transforms, and per-frame submission. The renderer automatically caches pipelines per shader ID, binds per-material data, and renders hierarchies depth-first.【F:Sources/SDLKit/SceneGraph/SceneGraph.swift†L96-L224】
- **Compute interop** exposes helper utilities that allocate shared buffers, dispatch compute workloads, and feed results back into the scene graph; CPU fallbacks keep tests running on the stub backend.【F:Sources/SDLKit/SceneGraph/SceneGraphComputeInterop.swift†L1-L88】【F:Sources/SDLKit/SceneGraph/SceneGraphComputeInterop.swift†L89-L154】

## Agent Specifications

The 3D & compute extension is coordinated through the agent design docs at the repository root. Each file expands on the APIs summarised above:

- `GraphicsAgent.md` — implementation and API contract for the low-level rendering backend (Metal, Direct3D, Vulkan).
- `ShaderAgent.md` — compiler toolchain and pipeline creation for shaders (HLSL → SPIR-V/DXIL/MSL).
- `ComputeAgent.md` — GPU compute abstractions for tasks such as audio DSP, physics and machine learning.
- `SceneGraphAgent.md` — high-level scene graph API (nodes, cameras, lights, meshes, materials) and draw submission protocol.

Consult these documents when contributing to or integrating with the 3D & compute extension.

## Platform verification

Use the SwiftPM demo and focused XCTest targets to validate each GPU backend after toolchain setup:

- **Metal (macOS)**
  1. `SDLKIT_GUI_ENABLED=1 swift run SDLKitDemo` boots the triangle + lit scene walkthrough using the Metal backend by default.【F:Sources/SDLKitDemo/main.swift†L24-L115】【F:Sources/SDLKitDemo/main.swift†L160-L221】
  2. `SDLKIT_GOLDEN=1 swift test --filter GoldenImageTests/testSceneGraphGoldenHash_Metal` captures a lit cube frame and compares it to the recorded hash.【F:Tests/SDLKitTests/GoldenImageTests.swift†L1-L44】

- **Direct3D 12 (Windows)**
  1. Set `SDLKIT_BACKEND=d3d12` if needed and run `swift run SDLKitDemo` to exercise swap-chain setup and the SceneGraph demo on D3D12.【F:Sources/SDLKitDemo/main.swift†L160-L221】
  2. `SDLKIT_GOLDEN=1 swift test --filter GoldenImageTests/testSceneGraphGoldenHash_D3D12` validates the lit-scene output and ensures GPU capture support is wired up.【F:Tests/SDLKitTests/GoldenImageTests.swift†L59-L80】

- **Vulkan (Linux)**
  1. `swift run SDLKitDemo` automatically chooses the Vulkan backend when running on Linux, exercising triangle + lit scene rendering.【F:Sources/SDLKitDemo/main.swift†L24-L115】【F:Sources/SDLKitDemo/main.swift†L160-L221】
  2. `SDLKIT_GOLDEN=1 swift test --filter GoldenImageTests/testSceneGraphGoldenHash_Vulkan` renders the lit cube and compares its capture hash against the stored baseline.【F:Tests/SDLKitTests/GoldenImageTests.swift†L45-L58】

All platforms can additionally run `swift test --filter SceneGraphComputeInteropTests` when the SDL3 stub is enabled to verify compute dispatch + render interop (`scenegraph_wave`).【F:Tests/SDLKitTests/SceneGraphComputeInteropTests.swift†L1-L41】

## Acceptance demos & tests

To reproduce the M1–M6 acceptance milestones referenced in `AGENTS.md`, use the following entry points:

- **M1 – Cross-backend triangle:** `swift run SDLKitDemo` issues the unlit triangle pipeline across whichever backend the factory selects.【F:Sources/SDLKitDemo/main.swift†L160-L221】【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L164-L205】
- **M2/M3 – Scene graph + lighting:** The demo transitions into the lit SceneGraph sample, while the golden image tests render the cube with `basic_lit` to validate lighting consistency.【F:Sources/SDLKitDemo/main.swift†L221-L276】【F:Tests/SDLKitTests/GoldenImageTests.swift†L1-L80】
- **M4 – Compute vector add:** `ShaderLibrary` includes the `vector_add` compute module so agents can register compute pipelines or write parity tests via `ShaderLibrary.shared.computeModule(for:)`, using the same artifact cache as the graphics shaders.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L206-L256】
- **M5 – Graphics/compute interop:** `SceneGraphComputeInteropTests` animates a scene node whose vertices are rewritten each frame by the `scenegraph_wave` compute shader, proving shared resource flow.【F:Sources/SDLKit/SceneGraph/SceneGraphComputeInterop.swift†L1-L88】【F:Tests/SDLKitTests/SceneGraphComputeInteropTests.swift†L1-L41】
- **M6 – Tooling & docs:** This README and the shader build plugin document the full toolchain; updating shaders or adding materials now exercises the same workflow CI runs.【F:Plugins/ShaderBuildPlugin/Plugin.swift†L10-L39】【F:Scripts/ShaderBuild/build-shaders.py†L20-L189】
