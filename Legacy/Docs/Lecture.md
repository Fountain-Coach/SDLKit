# SDLKit Graphics Stack Lecture (2024 Repository Audit)

## 1. Project Snapshot

SDLKit is a Swift-first wrapper around the Fountain-Coach SDL3 fork. The package separates the low level SDL window/event loop
from higher level graphics, scene, compute, audio, and agent tooling so the same runtime can serve human developers and
automation agents. The README classifies the project as pre-alpha, but the status section documents working SDL window/renderer
wrappers, a JSON GUI agent, cross-platform 3D back ends, and shared compute pipelines.【F:README.md†L1-L44】 The SwiftPM
package exposes a `CSDL3` system module, the `SDLKit` library, and a shader build plugin while committing generated shader
artifacts under `Sources/SDLKit/Generated`.【F:README.md†L46-L63】

The repository is organized around a layered runtime:

- `Sources/SDLKit/Core` contains the SDL wrappers (`SDLWindow`, `SDLRenderer`, input/clipboard/display helpers) and optional
audio/MIDI utilities. Window lifetimes, native handle access, and headless fallbacks are all implemented here.【F:Sources/SDLKit/Core/SDLWindow.swift†L1-L190】【F:Sources/SDLKit/Core/SDLRenderer.swift†L1-L181】
- `Sources/SDLKit/Agent` implements the JSON surface (`SDLKitGUIAgent`) that exposes window controls, primitive drawing, and
render-backend access to external planners.【F:Sources/SDLKit/Agent/SDLKitGUIAgent.swift†L1-L154】
- `Sources/SDLKit/Graphics` houses the rendering abstraction (`RenderBackend`), shader library, generated artifacts, and the
platform back ends for Metal, Direct3D 12, and Vulkan.【F:Sources/SDLKit/Graphics/RenderBackend.swift†L1-L118】【F:Sources/SDLKit/Graphics/BackendFactory.swift†L512-L557】
- `Sources/SDLKit/SceneGraph` contains the scene, node, material, and renderer logic that walks the scene graph each frame and
dispatches GPU work.【F:Sources/SDLKit/SceneGraph/SceneGraph.swift†L1-L120】【F:Sources/SDLKit/SceneGraph/SceneGraph.swift†L160-L251】
- `Sources/SDLKit/Support` provides shared helpers (configuration, math, logging, golden-reference support, settings/secrets) used
across the stack.【F:Sources/SDLKit/Support/Config.swift†L1-L44】【F:Sources/SDLKit/Support/RenderBackendTestHarness.swift†L1-L78】
- `Shaders/` plus `Scripts/ShaderBuild` host the single-source shader code and the Python pipeline that regenerates DXIL, SPIR-V,
and Metal binaries via DXC, SPIRV-Cross, and platform compilers.【F:Scripts/ShaderBuild/build-shaders.py†L1-L83】

## 2. Core Runtime & Agent Surface

`SDLWindow` wraps SDL3 window management, including native handle queries for Metal layers, Win32 HWND, and Vulkan surface
creation, and routes operations through `AgentError` to keep error reporting consistent in agent flows.【F:Sources/SDLKit/Core/SDLWindow.swift†L17-L115】【F:Sources/SDLKit/Core/SDLWindow.swift†L117-L192】
`SDLRenderer` manages texture atlases, CPU-side batching, and primitive drawing; headless builds fall back to a stub renderer so
CI can exercise higher layers without SDL linked.【F:README.md†L12-L19】【F:Sources/SDLKit/Core/SDLRenderer.swift†L1-L181】 The JSON agent wires these components together,
limiting the number of simultaneously open windows, routing draw calls, and exposing helpers such as `makeRenderBackend` so tests
and tools can attach to the high-performance renderer when SDL is available.【F:Sources/SDLKit/Agent/SDLKitGUIAgent.swift†L11-L120】【F:Sources/SDLKit/Agent/SDLKitGUIAgent.swift†L136-L195】

Configuration values (max windows, render-backend override, scene defaults) and persisted settings/secrets are surfaced through
`SDLKitConfigStore`, letting demos and automation tweak lighting, materials, and golden-image behavior without editing code.【F:Sources/SDLKit/Support/Config.swift†L1-L44】

## 3. Render Backend Abstraction

### 3.1 Protocol and Data Model

The `RenderBackend` protocol is the single contract between high-level systems and GPU back ends. It defines lifecycle hooks
(`beginFrame`, `endFrame`, `resize`, `waitGPU`), resource creation for buffers/textures/samplers, mesh registration, draw calls,
and compute dispatch. Opaque handle structs (`BufferHandle`, `TextureHandle`, `PipelineHandle`, etc.) decouple the scene graph and
agents from platform APIs.【F:Sources/SDLKit/Graphics/RenderBackend.swift†L1-L118】【F:Sources/SDLKit/Graphics/RenderBackend.swift†L352-L415】 Binding and pipeline descriptors describe how resources are
bound, while `BindingSet.MaterialConstants` carries push-constant blobs for material parameters.【F:Sources/SDLKit/Graphics/RenderBackend.swift†L200-L286】【F:Sources/SDLKit/Graphics/RenderBackend.swift†L300-L349】

Optional `GoldenImageCapturable` conformance allows back ends to capture rendered frames for parity testing, and `RenderSurface`
provides easy access to SDL-native handles (Metal layer, Win32 HWND, Vulkan instance extensions) during initialization.【F:Sources/SDLKit/Graphics/RenderBackend.swift†L318-L349】【F:Sources/SDLKit/Graphics/RenderBackend.swift†L350-L415】

### 3.2 Backend Selection & Stub Core

`RenderBackendFactory` chooses the appropriate implementation based on platform defaults or overrides (`metal`, `d3d12`, `vulkan`).
For environments where the native API is unavailable (for example, running Linux tests without Vulkan headers), the factory falls
back to lightweight subclasses of `StubRenderBackend` that record operations in memory but still honor the protocol surface and
support golden-image capture.【F:Sources/SDLKit/Graphics/BackendFactory.swift†L413-L474】【F:Sources/SDLKit/Graphics/BackendFactory.swift†L520-L557】 The stub core backs compute fallbacks and CPU readbacks, and it is
reused by the Vulkan backend to guarantee functionality while the full renderer matures.【F:Sources/SDLKit/Graphics/BackendFactory.swift†L520-L557】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1-L39】

## 4. Platform Back Ends

### 4.1 Metal

`MetalRenderBackend` creates a `CAMetalLayer`, command queue, and resource caches for buffers, textures, samplers, graphics, and
compute pipelines. Draw calls set up render passes, bind resources according to shader reflection, and optionally capture golden
images from the drawable. The backend also manages depth textures, pipeline caching, and sampler reuse so that scene graph updates
stay efficient.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L1-L120】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L212-L330】 Compute dispatch uses `MTLComputePipelineState` and
shares binding logic with graphics pipelines.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L120-L210】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L512-L620】

### 4.2 Direct3D 12

`D3D12RenderBackend` sets up DXGI factories, swap chains, descriptor heaps, frame fences, and a full resource lifetime model. It
tracks buffer states, descriptor indices, and push-constant bindings so that render and compute pipelines can be recreated on
device reset. Mesh registration uploads vertex/index buffers, while draw calls bind descriptor tables based on shader metadata and
encode commands into per-frame command lists.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1-L120】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L120-L220】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L640-L760】
Golden-image capture is implemented by copying swap-chain contents and packaging them as hashes/payloads for parity tests.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1040-L1150】

### 4.3 Vulkan

The Vulkan backend now builds a full `VkInstance`, negotiates SDL extensions, configures validation layers, and manages swapchain,
depth, command pool, and synchronization objects. Rendering still delegates resource management and draw/dispatch logic to the stub
core while the native path is finished, but validation capture and surface management are real so golden testing can exercise SDL
integration and shader modules on Linux.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1-L39】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L200-L320】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1440-L1760】

## 5. Shader Toolchain & Library

`ShaderLibrary` loads compiled graphics and compute modules from `Sources/SDLKit/Generated`, exposing reflection metadata (vertex
layouts, binding slots, push-constant sizes) to the render back ends and scene graph. It automatically base64-decodes artifacts if
only compressed payloads are committed and keeps helper factories for test modules.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L1-L120】【F:Sources/SDLKit/Graphics/ShaderArtifactMaterializer.swift†L1-L54】
The SwiftPM build plugin invokes `Scripts/ShaderBuild/build-shaders.py`, which orchestrates DXC, SPIRV-Cross, Metal, and
metallib tools to regenerate DXIL, SPIR-V, and metallib binaries from the shared HLSL/GLSL sources.【F:Scripts/ShaderBuild/build-shaders.py†L1-L126】

Compute modules cover graphics (scene graph wave deformation, IBL prefilter/BRDF LUT) and audio DSP (DFT power, mel projection,
onset detection), demonstrating how render and audio systems share GPU resources.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L185-L232】【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L393-L604】

## 6. Scene Graph & Compute Interop

`SceneGraph` structures materials, meshes, and transforms, while `SceneGraphRenderer` caches pipelines per shader, binds textures
and samplers based on shader reflection, pushes material constants (MVP, lighting, base color), and renders each node recursively.
Device-loss events reset caches automatically to survive backend resets.【F:Sources/SDLKit/SceneGraph/SceneGraph.swift†L1-L120】【F:Sources/SDLKit/SceneGraph/SceneGraph.swift†L160-L251】

`SceneGraphComputeInterop` shows how compute shaders update mesh vertex buffers before rendering. It provisions storage buffers for
state/config data, dispatches the `scenegraph_wave` compute shader, and applies a CPU fallback when the stub backend is in use so
headless CI still produces motion.【F:Sources/SDLKit/SceneGraph/SceneGraphComputeInterop.swift†L1-L86】【F:Sources/SDLKit/SceneGraph/SceneGraphComputeInterop.swift†L87-L156】 Mesh helpers in
`MeshPrimitives` generate cubes and sphere primitives with vertex/index buffers ready for registration.【F:Sources/SDLKit/SceneGraph/MeshPrimitives.swift†L1-L120】

## 7. Testing, Harnesses & Docs

The `RenderBackendTestHarness` automates parity runs for unlit triangles, lit cubes, and compute-to-texture workflows, capturing
hashes and optional payloads for golden references. It can also store artifacts on disk when `SDLKIT_GOLDEN_WRITE` is enabled.【F:Sources/SDLKit/Support/RenderBackendTestHarness.swift†L1-L120】【F:Sources/SDLKit/Support/RenderBackendTestHarness.swift†L120-L220】
Unit tests validate golden hashes per backend, push-constant updates, and scene/compute interop by spinning 180 frames and
comparing CPU and GPU outputs.【F:Tests/SDLKitTests/GoldenImageTests.swift†L1-L120】【F:Tests/SDLKitTests/SceneGraphComputeInteropTests.swift†L1-L41】 Docs in `docs/` cover installation, shader tooling,
scene graph demos, status audits, and time-bridge hooks for targeted contributions.【F:README.md†L65-L108】

## 8. Roadmap & Open Work

The README roadmap still calls out wiring SDL window/renderer paths, completing agent endpoints, shipping SDL_ttf text rendering,
and rounding out the GPU extension (native Vulkan paths, additional shaders, compute-driven demos).【F:README.md†L109-L152】 The
new lecture content should be kept in sync with `docs/status-audit.md` and backend source files as the Vulkan renderer graduates
from the stub core and new materials/shaders are added.
