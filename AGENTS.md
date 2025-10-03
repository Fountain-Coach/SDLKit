# AGENTS.md — SDLKit 3D Graphics, Multi‑API Shaders, and GPU Compute

This document orchestrates the four specialized agents that implement SDLKit’s 3D/compute extension.
It defines **scope, contracts, hand‑offs, acceptance criteria,** and **milestones** so multiple contributors
(or autonomous agents) can work safely in parallel.

**Agents**
- [GraphicsAgent](GraphicsAgent.md)
- [ShaderAgent](ShaderAgent.md)
- [ComputeAgent](ComputeAgent.md)
- [SceneGraphAgent](SceneGraphAgent.md)

---

## 1) System Overview

**Goal:** Extend SDLKit with a full 3D scene graph, a compile‑time **multi‑API shader** layer (Metal/D3D/Vulkan),
and a **GPU compute** layer—while keeping SDL windowing/eventing intact.

**High‑level flow**

```
SceneGraphAgent  →  GraphicsAgent(RenderBackend)  →  Native GPU API
       ↑                       ↑
       └──── ShaderAgent ──────┘
                 ↑
           ComputeAgent
```

- SceneGraphAgent: updates transforms, culls, and submits visible draws.
- GraphicsAgent: owns platform backends (Metal/D3D/Vulkan), resources, frame lifecycle.
- ShaderAgent: single‑source shaders → MSL / DXIL / SPIR‑V artifacts, reflection metadata.
- ComputeAgent: non‑graphics GPU workloads sharing the same device & resources.

> SDL still creates the window and provides native handles; we **bypass SDL_Renderer** for advanced 3D, using
Metal/Direct3D/Vulkan directly via a small C shim (CAMetalLayer / HWND / VkSurfaceKHR).

---

## 2) Shared Types & IDs (Cross‑Agent Contract)

These opaque handles/types **must be consistent** across agents.

```swift
public struct ShaderID: Hashable { public let rawValue: String } // e.g. "basic_lit"
public struct BufferHandle:    Hashable { /* opaque id */ }
public struct TextureHandle:   Hashable { /* opaque id */ }
public struct PipelineHandle:  Hashable { /* opaque id */ }
public struct ComputePipelineHandle: Hashable { /* opaque id */ }
public struct MeshHandle:      Hashable { /* opaque id */ }

public enum BufferUsage { case vertex, index, uniform, storage, staging }
public enum TextureFormat { case rgba8Unorm, bgra8Unorm, depth32Float /* … */ }

public struct TextureDescriptor { /* width, height, mipLevels, format, usage */ }
public struct TextureInitialData { /* per‑mip byte blobs */ }

public struct VertexLayout { /* attribute semantics, formats, strides */ }
public enum ShaderStage { case vertex, fragment, compute }

public struct BindingSlot {
    public let index: Int
    public enum Kind { case uniformBuffer, storageBuffer, sampledTexture, storageTexture, sampler }
    public let kind: Kind
}
// Engine‑level typed union used in draw/dispatch calls.
public struct BindingSet {
    public mutating func setBuffer(_ h: BufferHandle, at: Int)
    public mutating func setTexture(_ h: TextureHandle, at: Int)
    public mutating func setSampler(_ h: SamplerHandle, at: Int)
    public var materialConstants: MaterialConstants? // push/material constants (bytes)
}
```

**Conventions**
- All IDs (e.g., `ShaderID("basic_lit")`) are globally unique.
- Vertex attribute semantics (`POSITION`, `NORMAL`, `TEXCOORD0`, etc.) are fixed and documented by ShaderAgent.
- Binding indices are backend‑agnostic logical indices; backends map them to API‑specific registers/indices.

---

## 3) Contracts & Hand‑Offs

### 3.1 ShaderAgent ⇄ GraphicsAgent
- **Input to ShaderAgent:** shader definitions (`ShaderID`, entry points, vertex layout, bindings, defines).
- **Output from ShaderAgent:** per‑platform artifacts (Metal `.metallib`, DirectX **DXIL**, Vulkan **SPIR‑V**)
  and reflection metadata (attributes, bindings, push constants).
- **GraphicsAgent obligation:** turn artifacts into pipeline objects (`PipelineHandle`/`ComputePipelineHandle`),
  validate layouts against reflection metadata, and report mismatches clearly.

### 3.2 SceneGraphAgent ⇄ GraphicsAgent
- **SceneGraph → Graphics:** ordered draw submissions: `(MeshHandle, PipelineHandle, BindingSet, worldMatrix)`
  bracketed by `beginFrame()`/`endFrame()`; notify `resize(width,height)` on window events.
- **Graphics → SceneGraph:** resource handles for meshes/textures; device‑lost / resize callbacks; frame timing.

### 3.3 ComputeAgent ⇄ GraphicsAgent
- **Compute → Graphics:** requests to create compute pipelines & dispatch jobs with `BindingSet` and push constants.
- **Graphics → Compute:** shared resource handles and synchronization (barriers/fences); readback APIs.

### 3.4 SceneGraphAgent ⇄ ShaderAgent
- **Scene materials** reference `ShaderID`s. SceneGraphAgent supplies material constants and texture bindings
  in `BindingSet` format, matching ShaderAgent’s reflection.

---

## 4) Interfaces (Authoritative Sketch)

### 4.1 RenderBackend (GraphicsAgent)
```swift
public protocol RenderBackend {
    // Lifecycle
    init(window: SDLWindow) throws
    func beginFrame() throws
    func endFrame() throws
    func resize(width: Int, height: Int) throws
    func waitGPU() throws

    // Resources
    func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle
    func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle
    func createSampler(descriptor: SamplerDescriptor) throws -> SamplerHandle
    func destroy(_ handle: ResourceHandle)
    func readback(buffer: BufferHandle, into dst: UnsafeMutableRawPointer, length: Int) throws

    // Mesh registration
    func registerMesh(vertexBuffer: BufferHandle,
                      vertexCount: Int,
                      indexBuffer: BufferHandle?,
                      indexCount: Int,
                      indexFormat: IndexFormat) throws -> MeshHandle

    // Graphics pipelines
    func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle
    func draw(mesh: MeshHandle,
              pipeline: PipelineHandle,
              bindings: BindingSet,
              transform: float4x4) throws

    // Compute pipelines
    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle
    func dispatchCompute(_ pipeline: ComputePipelineHandle,
                         groupsX: Int, groupsY: Int, groupsZ: Int,
                         bindings: BindingSet) throws
}
```

### 4.2 ShaderLibrary (ShaderAgent)
```swift
public protocol ShaderLibrary {
    func load(_ id: ShaderID) throws -> ShaderModuleDescriptor // carries artifact URLs + reflection
    func makeGraphicsPipeline(_ req: GraphicsPipelineRequest) throws -> PipelineHandle
    func makeComputePipeline(_ req: ComputePipelineRequest) throws -> ComputePipelineHandle
}
```

### 4.3 ComputeScheduler (ComputeAgent)
```swift
// Note: In SDLKit, compute is integrated into RenderBackend for symmetry and simplicity.
// A separate facade can exist if needed, forwarding to the RenderBackend methods.
public protocol ComputeScheduler {
    func makeComputePipeline(_ d: ComputePipelineDescriptor) throws -> ComputePipelineHandle
    func dispatch(_ groups: (Int, Int, Int), pipeline: ComputePipelineHandle,
                  bindings: BindingSet) throws
    func readback(buffer: BufferHandle, into dst: UnsafeMutableRawPointer, length: Int) throws
}
```

### 4.4 SceneGraph (SceneGraphAgent)
- `Scene`, `SceneNode`, `Camera`, `Light`, `Mesh`, `Material` types.
- `updateAndRender(scene, backend)` utility drives propagation, culling, submission.

---

## 5) Build & Tooling Agreements

- **Single‑source shaders (prefer HLSL)** compiled to **SPIR‑V** (Vulkan) and **DXIL** (DirectX) via **DXC**;
  **SPIRV‑Cross** converts SPIR‑V to **MSL** then Apple’s `metal`/`metallib` produces `.metallib`.
- Artifacts are addressed by `ShaderID` and shipped per‑platform.
- SwiftPM plugins or scripts run the toolchain conditionally per OS.
- Validation layers enabled in dev (Vulkan), D3D12 debug layer, Metal API validation; CI turns them on in tests.

---

## 6) Milestones & Cross‑Agent Acceptance

> **Quality Gate (current):** The RenderBackend regression harness (golden image + compute suite) must pass on Metal (macOS) and Vulkan (Linux) before closing milestones **M1–M5**. CI runs the harness on each platform leg and publishes capture hashes/images for review when a failure occurs.
>
> Note: The Windows (D3D12) leg is temporarily disabled because Swift ≥ 6 is required for Concurrency and is not currently available on Windows runners. The D3D12 backend remains a milestone target but is not part of CI until Swift 6+ lands on Windows.

**M0 — C Shim & Windowing**
- Shim exposes: `CAMetalLayer`, `HWND`, `VkSurfaceKHR`. Minimal sample retrieves each and logs success.
- Acceptance: sample runs on each platform; correct handle types; no crashes.

**M1 — Triangle on Each Backend**
- One `ShaderID("unlit_triangle")`; backends create pipelines and present a triangle.
- Acceptance: identical color output; no validation errors; resizes recreate swapchain/depth.

**M2 — Scene MVP**
- SceneGraph draws a single unlit mesh; per‑object transforms; depth buffer.
- Acceptance: mesh renders & moves; culling optional; resize works.

**M3 — Materials & Lighting**
- `basic_lit` shader with vertex normals + one directional light.
- Acceptance: lighting matches reference image within tolerance on all backends.

**M4 — Compute MVP**
- Vector‑add compute; verify buffer output; integrated via `RenderBackend` compute APIs.
- Acceptance: CPU vs GPU parity (buffer readback); dispatch timing logged; no stalls.

**M5 — Graphics ⇄ Compute Interop**
- Compute updates a particle buffer rendered as instanced meshes.
- Acceptance: smooth animation; no resource hazards; frame pacing stable 60s soak.

**M6 — Packaging & Docs**
- Developer guide for adding a new shader/material; scene and compute samples.
- Acceptance: new shader path verified end‑to‑end on two platforms.

---

## 7) Responsibilities Matrix

| Area | GraphicsAgent | ShaderAgent | ComputeAgent | SceneGraphAgent |
|---|---|---|---|---|
| Window/Device Init | **Owns** | – | – | – |
| C Shim Native Handles | **Owns** | – | – | – |
| Shader Build Tooling | – | **Owns** | – | – |
| Pipeline Creation | **Owns** (from artifacts) | Supplies artifacts | Supplies compute artifacts | Requests by `ShaderID` |
| Resources (Buffers/Textures) | **Owns** | – | Shares | Requests/uses |
| Draw Submission | Executes | – | – | **Owns order** |
| Compute Dispatch | Executes | – | **Owns APIs** | Requests results |
| Scene Update/Culling | – | – | Assists (physics) | **Owns** |

---

## 8) Risks & Mitigations

- **API Divergence:** keep `RenderBackend` small; push quirks into helpers.
- **Synchronization Bugs:** provide backend‑specific guards (barriers/fences) and a testing harness.
- **Cross‑compile Mismatches:** strict reflection checks; golden‑image tests; follow naming/layout conventions.
- **Device Lost/Resize:** centralize recreate paths; backpressure frame start if swapchain invalid.

---

## 9) CI & Quality Gates

- Matrix builds (CI): macOS (Metal), Linux (Vulkan).
- Windows (D3D12) is excluded from CI due to the Swift ≥ 6 requirement; re‑enable when Windows toolchains catch up.
- Smoke tests: triangle; scene‑mesh; compute vector‑add.
- Note: Headless CI skips GPU-backed golden tests. A GPU-enabled leg (windowing allowed) should
  run the regression harness to enforce cross-backend parity before merges.
- Optional headless checksums (where supported) and `--validation on` runs.
- Artifacts: upload compiled shaders and logs for inspection.

---

## 12) CI Shepherding Guide (macOS + Linux)

This section documents how the repository keeps CI green across macOS and Linux and how to debug quickly.

- Headless defaults
  - Use `HEADLESS_CI` at compile time and `SDLKIT_GUI_ENABLED=0` in CI to disable GUI‑only targets and keep unit tests deterministic.
  - Package.swift conditionally includes GUI deps/targets (SDLKitTTF, CSDL3IMAGE/CSDL3TTF, SDLKitDemo) based on `SDLKIT_GUI_ENABLED`.

- Build tests first, then run
  - CI runs `swift build --build-tests` before `swift test` to avoid xctest bundle not found races.

- macOS pipeline
  - Toolchain: install official Swift 6.1 pkg (not setup‑swift action) for consistent concurrency semantics.
  - Logs: filter “prohibited flag(s)” warnings to keep logs readable; upload `macos-swift-test.log` on every run.
  - Tests: unit test step runs only `SDLKitTests` (headless‑friendly); the Metal regression harness runs in a separate step and uploads golden artifacts.

- Linux pipeline
  - Container: `swift:6.1-jammy` with Vulkan SDK packages (`libvulkan-dev`, `vulkan-validationlayers`, `glslang-tools`, `spirv-tools`).
  - Validation: NOT enforced during unit tests (to avoid fatal fail‑fast); it IS enforced in the Vulkan regression harness step.
  - Logs: `linux-swift-test.log` and Vulkan validation logs are uploaded as artifacts.

- SDL3 migration compatibility (C shim)
  - Vulkan: use `SDL_Vulkan_GetInstanceExtensions(Uint32*)` (returns names) and pass the array back to Swift.
  - Input: keyboard uses `ev->key.key`, mouse positions are float; convert to ints for engine events.
  - Displays: enumerate with `SDL_GetDisplays` and map to names/bounds via display IDs.
  - IO: migrate from `SDL_RWops` to `SDL_IOStream`; SDL_image uses `IMG_SavePNG_IO`.
  - RenderReadPixels: now returns `SDL_Surface`; convert/pack to ABGR8888 before copying to caller buffer.
  - Normalize SDL bool returns to 0 (success) / −1 (failure) to align with Swift checks.

- Metal backend hygiene
  - Remove unsupported `MTLBlitCommandEncoder.memoryBarrier` calls; rely on encoder boundaries.
  - Unwrap optional render pass attachments and vertex descriptor entries defensively.
  - Use `rasterSampleCount` to avoid deprecated `sampleCount` warning.

- Shader plugin
  - Python 3.9+ compatible typing (use `Optional[str]`) to prevent plugin crashes on GH runners.

- Self‑healing and manual dispatch
  - A `workflow_dispatch` input (`os=linux|macos|windows|all`) allows targeted runs.
  - A self‑heal workflow listens for failures and re‑runs CI up to 3 times.
  - `gh workflow run CI -f os=macos --ref main` and `gh run watch <id>` for local operator control.

- Troubleshooting checklist
  - Missing target/product (demo) in headless CI: ensure `SDLKIT_GUI_ENABLED=0` and Package.swift guards the `SDLKitDemo` product + target.
  - C shim type errors: reconfirm SDL3 header changes (Vulkan, input, display, IO). Keep the shim resilient and return sane defaults in headless.
  - “prohibited flag(s)” spam: avoid brew‑injected -I/-L in Package.swift and filter remaining warnings in CI steps.
  - Linux fatal test observer: keep Vulkan validation off in the unit test step; enforce in the harness step only.

This regimen keeps CI fast, readable, and robust; the golden harness still enforces graphics parity on each leg.

---

## 10) Quick Start for Agents

1. **ShaderAgent**: bootstrap toolchain; implement registry & compile `unlit_triangle` and `basic_lit`.
2. **GraphicsAgent**: C shim for handles; Metal/D3D/Vulkan backends to clear screen; then triangle.
3. **SceneGraphAgent**: implement node transforms; draw a mesh via backend.
4. **ComputeAgent**: vector‑add compute; readback & parity check.
5. Integrate: Scene renders; compute updates a buffer used by rendering.

---

## 11) Links

- [GraphicsAgent.md](GraphicsAgent.md)
- [ShaderAgent.md](ShaderAgent.md)
- [ComputeAgent.md](ComputeAgent.md)
- [SceneGraphAgent.md](SceneGraphAgent.md)
