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

SDLKit targets the Fountain‑Coach SDL3 fork and auto-discovers the library via `pkg-config`. Set optional `SDL3_INCLUDE_DIR`/`SDL3_LIB_DIR` overrides when installing to a custom prefix. [Read more →](docs/install.md)

## Install SDL3

Follow the platform-specific setup instructions (Homebrew, apt, vcpkg, or manual builds) to provision SDL3 and expose the runtime libraries. [Read more →](docs/install.md)

## Build & Test

- Requires Swift 6.1+
- Build: `swift build`
- Test: `swift test`

### Audio (preview)

- New SDLAudio wrappers expose SDL3 audio streams for capture and playback.
- `SDLAudioCapture` opens the default recording device and lets you pull interleaved `.f32` frames.
- `SDLAudioPlayback` opens the default playback device and accepts queued PCM samples.
- Headless CI and shim builds compile these APIs but return `sdlUnavailable` or throw on use.
- Device enumeration: `SDLAudioDeviceList.list(.playback/.recording)` gets device IDs, names, and preferred specs.
- Resampler: `SDLAudioResampler` wraps SDL_CreateAudioStream for format/rate conversion.
- JSON endpoints (preview):
  - `POST /agent/audio/devices`
  - `POST /agent/audio/capture/open` → `{ audio_id }`
  - `POST /agent/audio/capture/read` → `{ frames, channels, format, data_base64 }` (Float32 interleaved)
  - `POST /agent/audio/playback/open` → `{ audio_id }`
  - `POST /agent/audio/playback/sine` (queue a sine tone)
  - `POST /agent/audio/playback/queue/open` → `{ audio_id }` (starts a ring-buffered drain)
  - `POST /agent/audio/playback/queue/enqueue` (enqueue base64 f32 PCM)
  - `POST /agent/audio/playback/play_wav` → opens (or reuses) playback and queues WAV
  - `POST /agent/audio/features/start` → start mel/onset extractor
    - accepts `{ use_gpu: true, window_id, backend }` to run DFT on GPU when a render backend is available for a window
  - `POST /agent/audio/features/read_mel` → `{ frames, mel_bands, mel_base64, onset_base64 }`
  - `POST /agent/audio/a2m/start` → start stub note detection (threshold/hysteresis)
  - `POST /agent/audio/a2m/read` → `{ events: [{ kind, note, velocity, frameIndex, timestamp_ms }] }`

### Shader toolchain workflow

The repository includes the DXC/SPIRV-Cross-driven shader build pipeline and SwiftPM plugin so you can regenerate graphics and compute artifacts locally. [Read more →](docs/shader-toolchain.md)

## Documentation

- [Installation Guide](docs/install.md) — set up the Fountain‑Coach SDL3 fork, configure environment overrides, and verify your toolchain.
- [Shader Toolchain Guide](docs/shader-toolchain.md) — install DXC/SPIRV-Cross, run the SwiftPM plugin, and validate shader artifacts.
- [Scene Graph & Demo Guide](docs/scenegraph.md) — launch the 3D demo, manage golden images, and tune scene graph defaults.

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

The agent reads several environment variables at runtime. Key options include (see [Glossary & Tags](docs/tags.md) for full definitions):

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

Launch the 3D demo to exercise the shared `RenderBackend` implementations, override backends, manage golden images, and tweak scene defaults using the CLI utilities. [Read more →](docs/scenegraph.md)

### Golden Image Parity (M3)

Enable automated reference-image validation for the scene graph by turning on the `SDLKIT_GOLDEN` flag or invoking the `SDLKitGolden` CLI. [Read more →](docs/scenegraph.md)

### Settings & Secrets

Persist renderer and scene defaults, shader tool paths, and secret values via the `SDLKitSettings`/`SDLKitSecrets` CLIs. [Read more →](docs/scenegraph.md) Refer to the [Glossary & Tags appendix](docs/tags.md) for descriptions of the related keys and secrets.

### Settings Reference

Review the available configuration keys and serialized formats, plus examples for dumping and migrating settings. [Read more →](docs/scenegraph.md)
## Agent Contract

See `AGENTS.md:1` for the `sdlkit.gui.v1` tool definitions, error codes, event schema, threading policy, present policy, configuration keys, and contributor workflow. Consult the [Glossary & Tags appendix](docs/tags.md) for short explanations of agent names and frequently referenced tags.

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
  3. `SDLKIT_GOLDEN=1 swift test --filter GoldenComputeStorageTextureTests/testComputeStorageTextureMetal` exercises the compute-to-texture path, capturing the final color/depth hash with the Metal stub or backend; the test skips unless capture support is available.【F:Tests/SDLKitTests/GoldenComputeStorageTextureTests.swift†L1-L116】

- **Direct3D 12 (Windows)**
  1. Set `SDLKIT_BACKEND=d3d12` if needed and run `swift run SDLKitDemo` to exercise swap-chain setup and the SceneGraph demo on D3D12.【F:Sources/SDLKitDemo/main.swift†L160-L221】
  2. `SDLKIT_GOLDEN=1 swift test --filter GoldenImageTests/testSceneGraphGoldenHash_D3D12` validates the lit-scene output and ensures GPU capture support is wired up.【F:Tests/SDLKitTests/GoldenImageTests.swift†L59-L80】
  3. `SDLKIT_GOLDEN=1 swift test --filter GoldenComputeStorageTextureTests/testComputeStorageTextureD3D12` validates compute writes into a storage texture before drawing, skipping automatically when capture is unsupported on the current configuration.【F:Tests/SDLKitTests/GoldenComputeStorageTextureTests.swift†L80-L116】

- **Vulkan (Linux)**
  1. `swift run SDLKitDemo` automatically chooses the Vulkan backend when running on Linux, exercising triangle + lit scene rendering.【F:Sources/SDLKitDemo/main.swift†L24-L115】【F:Sources/SDLKitDemo/main.swift†L160-L221】
  2. `SDLKIT_GOLDEN=1 swift test --filter GoldenImageTests/testSceneGraphGoldenHash_Vulkan` renders the lit cube and compares its capture hash against the stored baseline.【F:Tests/SDLKitTests/GoldenImageTests.swift†L45-L58】
  3. `SDLKIT_GOLDEN=1 swift test --filter GoldenComputeStorageTextureTests/testComputeStorageTextureVulkan` covers the compute-to-texture path while enabling validation captures; the test documents its Linux-only skip when invoked elsewhere.【F:Tests/SDLKitTests/GoldenComputeStorageTextureTests.swift†L58-L79】

All platforms can additionally run `swift test --filter SceneGraphComputeInteropTests` when the SDL3 stub is enabled to verify compute dispatch + render interop (`scenegraph_wave`).【F:Tests/SDLKitTests/SceneGraphComputeInteropTests.swift†L1-L41】

## Acceptance demos & tests

To reproduce the M1–M6 acceptance milestones referenced in `AGENTS.md`, use the following entry points:

- **M1 – Cross-backend triangle:** `swift run SDLKitDemo` issues the unlit triangle pipeline across whichever backend the factory selects.【F:Sources/SDLKitDemo/main.swift†L160-L221】【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L164-L205】
- **M2/M3 – Scene graph + lighting:** The demo transitions into the lit SceneGraph sample, while the golden image tests render the cube with `basic_lit` to validate lighting consistency.【F:Sources/SDLKitDemo/main.swift†L221-L276】【F:Tests/SDLKitTests/GoldenImageTests.swift†L1-L80】
- **M4 – Compute vector add:** `ShaderLibrary` includes the `vector_add` compute module so agents can register compute pipelines or write parity tests via `ShaderLibrary.shared.computeModule(for:)`, using the same artifact cache as the graphics shaders.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L206-L256】 The CI pipeline runs a parity test on Metal that compares GPU output to CPU via the new buffer readback API.【F:Sources/SDLKit/Graphics/RenderBackend.swift†L208-L235】【F:Tests/SDLKitTests/ComputeVectorAddParityTests.swift†L1-L60】
- **M5 – Graphics/compute interop:** `SceneGraphComputeInteropTests` animates a scene node whose vertices are rewritten each frame by the `scenegraph_wave` compute shader, proving shared resource flow.【F:Sources/SDLKit/SceneGraph/SceneGraphComputeInterop.swift†L1-L88】【F:Tests/SDLKitTests/SceneGraphComputeInteropTests.swift†L1-L41】 The regression harness uses a real compute shader (`ibl_brdf_lut`) to produce a storage texture prior to drawing so all backends exercise actual compute pipelines.【F:Sources/SDLKit/Support/RenderBackendTestHarness.swift†L200-L290】【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L481-L520】

## Maintainers — Seeding Golden Baselines

The GPU-enabled regression harness (Metal on macOS, Vulkan on Linux) compares rendered output against stored baselines. To initialize or update these baselines, use GitHub Actions’ manual dispatch. The baselines are persisted in `.fountain/sdlkit` (cached between CI runs) and exposed as artifacts for review.

Steps:

1) Seed macOS (Metal) baselines

```bash
gh workflow run CI -f os=macos -f gpu=true --ref main
gh run watch <run-id>
```

- The CI job includes a “Seed golden store (Metal, GPU) [manual]” step that runs with `SDLKIT_GOLDEN_WRITE=1` and writes baselines to `.fountain/sdlkit`.
- Artifacts: `macos-golden-artifacts-gpu` contain the capture image(s) and hash files.

2) Seed Linux (Vulkan) baselines

```bash
gh workflow run CI -f os=linux --ref main
gh run watch <run-id>
```

- The CI job includes a “Seed golden store (Vulkan, GPU) [manual]” step that runs under Xvfb with validation enabled and writes baselines.
- Artifacts: `linux-golden-artifacts-gpu` contain the capture image(s) and hash files.

3) Verify strict parity

Push normally or re-run CI. The GPU harness runs in strict mode (without the write flag) and fails on mismatches (when dispatched with `gpu=true`). To intentionally update baselines after a legitimate rendering change, repeat steps 1–2 with `gpu=true`.

### PR comment trigger (for GPU runs)

You can trigger a GPU-enabled CI run from a pull request comment:

```text
/gpu-test            # macOS GPU harness strict run
/gpu-test --seed     # macOS GPU harness with seeding enabled
/gpu-test all --seed # same as above but allows future multi-OS expansion
```

Note: Linux GPU harness is disabled on hosted runners. The dispatcher will route `/gpu-test linux` to macOS.

### PR label trigger (for GPU runs)

Apply one of these labels to a pull request to trigger a macOS GPU-enabled CI run:

- `gpu` — runs the GPU harness in strict mode (no baseline writes)
- `gpu-seed` — runs the GPU harness with baseline seeding enabled (`seed=true`)

The label dispatcher will post a confirmation comment when CI is dispatched. GPU steps only run on macOS runners; Linux GPU is disabled on hosted runners.

Notes:
- The golden store is cached across CI runs. If you need a clean slate, bump the cache key (the workflow references `.github/workflows/ci.yml`) or purge the cache from the Actions UI.
- Headless harness and unit tests continue to run for fast feedback; the GPU harness provides cross-backend visual parity assurance.
- **M6 – Tooling & docs:** This README and the shader build plugin document the full toolchain; updating shaders or adding materials now exercises the same workflow CI runs.【F:Plugins/ShaderBuildPlugin/Plugin.swift†L10-L39】【F:Scripts/ShaderBuild/build-shaders.py†L20-L189】

## Glossary & Tags

The [Glossary & Tags appendix](docs/tags.md) groups every agent name, environment variable, settings key, and secret used throughout SDLKit. The most common tags you will encounter are `SDLKIT_MAX_WINDOWS`, `SDLKIT_RENDER_BACKEND`, `SDLKIT_PRESENT_POLICY`, and the cross-agent roles such as `GraphicsAgent` and `ShaderAgent`.
