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
public struct BufferHandle:    Hashable { let _id: UInt64 }
public struct TextureHandle:   Hashable { let _id: UInt64 }
public struct PipelineHandle:  Hashable { let _id: UInt64 }
public struct ComputePipelineHandle: Hashable { let _id: UInt64 }
public struct MeshHandle:      Hashable { let _id: UInt64 }

public enum BufferUsage { case vertex, index, uniform, storage, staging }
public enum TextureFormat { case rgba8Unorm, bgra8Unorm, depth32Float /* … */ }

public struct TextureDescriptor { /* width, height, mipLevels, format, usage flags */ }
public struct TextureInitialData { /* per‑mip raw pointers or slices */ }

public struct VertexLayout { /* attribute semantics, formats, strides */ }
public enum ShaderStage { case vertex, fragment, compute }

public struct BindingSlot {
    public let index: Int
    public enum Kind { case uniformBuffer, storageBuffer, sampledTexture, storageTexture, sampler }
    public let kind: Kind
}
public struct BindingSet { public var slots: [Int: Any] } // engine‑level typed union
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
    init(window: SDLWindow) throws
    func beginFrame() throws
    func endFrame() throws
    func resize(width: Int, height: Int) throws
    func waitGPU() throws

    func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle
    func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle
    func destroy(_ handle: Any) // Buffer/Texture/Pipeline

    func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle
    func draw(mesh: MeshHandle, pipeline: PipelineHandle,
              bindings: BindingSet,
              transform: float4x4) throws

    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle
    func dispatchCompute(_ p: ComputePipelineHandle, groupsX: Int, groupsY: Int, groupsZ: Int,
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
- Vector‑add compute; verify buffer output; integrate schedule via GraphicsAgent.
- Acceptance: CPU vs GPU parity; dispatch timing logged; no stalls.

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

- Matrix builds: macOS (Metal), Windows (D3D12), Linux (Vulkan).
- Smoke tests: triangle; scene‑mesh; compute vector‑add.
- Optional headless checksums (where supported) and `--validation on` runs.
- Artifacts: upload compiled shaders and logs for inspection.

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
