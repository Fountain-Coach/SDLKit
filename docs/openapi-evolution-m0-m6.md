# SDLKit OpenAPI Evolution for Milestones M0–M6

## Purpose
The SDLKit backend roadmap now targets a 3D scene graph, multi-API shader compilation, and shared graphics/compute scheduling across Metal, Direct3D, and Vulkan.【F:AGENTS.md†L17-L123】 The current OpenAPI contract (`sdlkit.gui.v1.yaml`) still reflects a 2D SDL_Renderer-style control surface focused on window management and immediate-mode drawing commands.【F:sdlkit.gui.v1.yaml†L39-L520】 This document evaluates how the OpenAPI should evolve to support milestones M0 through M6 and highlights items that are better left out of the HTTP interface.

## Current OpenAPI Coverage Snapshot
* **Window lifecycle and presentation controls** are fully described (open, resize, present, show/hide, fullscreen, etc.).【F:sdlkit.gui.v1.yaml†L39-L220】
* **Immediate-mode 2D rendering endpoints** dominate the API (draw rectangles/lines/circles, textures, text, clip rects, etc.), which assumes SDL’s software or simple GPU renderer.【F:sdlkit.gui.v1.yaml†L320-L520】
* There is **no representation of GPU backends, shader artifacts, buffers, textures, meshes, pipelines, or compute workloads** that the new architecture requires.【F:AGENTS.md†L40-L189】

The gap indicates that we need a versioned expansion (likely `sdlkit.render.v1` or `sdlkit.engine.v1`) that either replaces or complements the GUI endpoints.

## Milestone-by-Milestone Assessment
### M0 — C Shim & Windowing
* **Makes sense to expose:**
  * Window lifecycle stays in scope; we already have most endpoints.
  * Add a `GET /agent/system/native-handles` (or similar) that returns the platform-specific surface/handle trio (`CAMetalLayer`, `HWND`, `VkSurfaceKHR`) so the RenderBackend can bootstrap.【F:AGENTS.md†L163-L166】
  * Consider a negotiation endpoint that confirms which native APIs are available on the host.
* **Probably avoid:** Exposing raw pointers/addresses over HTTP; instead, return serialized descriptors (e.g., a struct with `type` and integer/opaque tokens) so the native shim can map them locally.

### M1 — Triangle on Each Backend
* **Makes sense:**
  * Introduce resource creation endpoints: `createBuffer`, `createTexture`, `destroyResource`, aligning with the shared handle types.【F:AGENTS.md†L44-L67】
  * Add a pipeline registration endpoint that consumes shader artifact references produced offline by the ShaderAgent.【F:AGENTS.md†L78-L133】
  * Provide a `beginFrame/endFrame` control surface with error reporting to align with RenderBackend contracts.【F:AGENTS.md†L102-L123】
* **Avoid:** Streaming per-vertex data for every frame via HTTP; keep data uploads coarse-grained (buffers/textures) and rely on handles for draw submissions.

### M2 — Scene MVP
* **Makes sense:**
  * Add scene graph management endpoints: `createScene`, `addNode`, `setTransform`, `attachMesh`, `setCamera`. These mirror the SceneGraphAgent responsibilities.【F:AGENTS.md†L85-L147】
  * Include draw submission endpoints that accept batches of `(MeshHandle, PipelineHandle, BindingSet, transform)` as defined in the contract.【F:AGENTS.md†L86-L118】
  * Provide eventing or state query endpoints for resize/device-lost notifications.
* **Avoid:** Modeling per-frame traversal over HTTP; the API should accept already-culled submissions rather than replicating traversal logic remotely.

### M3 — Materials & Lighting
* **Makes sense:**
  * Extend schema components to represent material parameter blocks, texture bindings, and shader feature toggles keyed by `ShaderID` (`basic_lit`, etc.).【F:AGENTS.md†L175-L177】
  * Add validation endpoints that confirm material layouts against shader reflection metadata to catch mismatches early.【F:AGENTS.md†L78-L96】
* **Avoid:** Exposing low-level lighting equations; the API should carry data (light descriptors, material constants) but not re-describe shading code.

### M4 — Compute MVP
* **Makes sense:**
  * Mirror the compute scheduler contract with endpoints for `makeComputePipeline`, `dispatchCompute`, and `readbackBuffer` using shared handles.【F:AGENTS.md†L120-L142】【F:AGENTS.md†L179-L181】
  * Encode dispatch dimensions and push constants in schemas.
* **Avoid:** Forcing synchronous blocking dispatch unless explicitly requested; allow async job handles so HTTP latency does not stall GPU work.

### M5 — Graphics ⇄ Compute Interop
* **Makes sense:**
  * Introduce synchronization primitives (barrier/fence descriptions) and allow compute jobs to signal readiness of buffers used by graphics draws.【F:AGENTS.md†L183-L185】
  * Provide instancing-friendly draw submission schemas so compute-generated particle data can be rendered without copying.
* **Avoid:** Automatic orchestration of complex dependency graphs via REST; document expectations for the caller to order submissions properly.

### M6 — Packaging & Docs
* **Makes sense:**
  * Version the OpenAPI (`v2.0.0` or new namespace) and include examples/tutorial references that mirror the developer guide requirement.【F:AGENTS.md†L187-L189】
  * Publish bundled schemas for shaders/materials/compute samples and add tags to the spec for discoverability.
* **Avoid:** Collapsing everything into a single monolithic path; keep logical groupings (window, render, shader, compute, scene) with tags so docs stay navigable.

## Executable Task List
1. **Define API versioning strategy**: draft a proposal for `sdlkit.render.v1` (new tag namespace) while keeping legacy GUI endpoints intact for compatibility. Output: design doc + version bump PR.
2. **Model shared handles in OpenAPI components**: add schemas for `ShaderID`, `BufferHandle`, `TextureHandle`, `PipelineHandle`, `ComputePipelineHandle`, `MeshHandle`, `BindingSlot`, and `BindingSet` with validation rules.【F:AGENTS.md†L44-L67】
3. **Add native-handle negotiation endpoints for M0**: specify request/response schemas that expose Metal/D3D/Vulkan surface descriptors without raw pointers.【F:AGENTS.md†L163-L166】
4. **Introduce resource & pipeline management paths (M1)**: `/agent/render/buffer/create`, `/agent/render/texture/create`, `/agent/render/pipeline/register`, `/agent/render/frame/begin|end` with error reporting aligned to RenderBackend contract.【F:AGENTS.md†L102-L123】
5. **Create scene graph management paths (M2)**: `/agent/scene/create`, `/agent/scene/node`, `/agent/scene/submitDraws`, including bulk submission payloads following the `(MeshHandle, PipelineHandle, BindingSet, worldMatrix)` tuple.【F:AGENTS.md†L85-L118】
6. **Extend materials & lighting schemas (M3)**: define material parameter blocks, light descriptors, and a validation endpoint referencing shader reflection metadata.【F:AGENTS.md†L175-L177】【F:AGENTS.md†L78-L96】
7. **Add compute scheduler endpoints (M4)**: `/agent/compute/pipeline`, `/agent/compute/dispatch`, `/agent/compute/readback` with asynchronous job tracking options.【F:AGENTS.md†L120-L142】【F:AGENTS.md†L179-L181】
8. **Model graphics/compute synchronization (M5)**: add schemas for barriers/fences and update draw/dispatch endpoints to accept dependency tokens.【F:AGENTS.md†L183-L185】
9. **Publish documentation artifacts (M6)**: update OpenAPI tags, examples, and external docs links so they reference the new shader/material/compute guides.【F:AGENTS.md†L187-L189】
10. **Deprecate or re-tag 2D-only endpoints**: mark `drawRectangle`, `drawLine`, etc., as legacy to prevent confusion once the 3D stack is primary.【F:sdlkit.gui.v1.yaml†L470-L520】

These tasks can be tracked in the repo’s issue tracker or a milestone board to coordinate Shader, Graphics, Compute, and SceneGraph agent workstreams.
