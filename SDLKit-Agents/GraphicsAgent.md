# GraphicsAgent

**Role:** Owns the rendering infrastructure and platform backends (Metal, Direct3D, Vulkan). Integrates low-level GPU handles from SDL, implements the `RenderBackend` protocol, and runs the frame lifecycle (init → render → present → resize → teardown).  

> Source of truth for scope and responsibilities is the Implementation Strategy – Section 10 “Draft AGENTS.md”.

---

## Objectives
- Provide a unified rendering backend API consumed by SDLKit’s 3D scene layer.
- Implement platform-specific backends:
  - **MetalRenderBackend** (macOS/iOS)
  - **D3DRenderBackend** (Windows / Direct3D 12)
  - **VulkanRenderBackend** (Linux; optionally macOS via MoltenVK)
- Bridge **SDL window handles** to native graphics contexts (CAMetalLayer, HWND, VkSurfaceKHR).
- Manage GPU resources (buffers, textures, pipelines) and frame submission.

## Scope
- Extend `SDLWindow` creation to select a graphics API (auto/metal/d3d/vulkan).
- Add C shim helpers to retrieve native handles:
  - `SDLKit_MetalLayerForWindow(SDL_Window*) -> void*`
  - `SDLKit_Win32HWND(SDL_Window*) -> void*`
  - `SDLKit_CreateVulkanSurface(SDL_Window*, VkInstance) -> VkSurfaceKHR`
- Implement `RenderBackend` protocol and its three concrete backends.
- Handle resize events and swapchain recreation.
- Expose uniform APIs for graphics & compute (compute dispatch may be a no-op if unsupported).

## Out of Scope (Non‑Goals)
- High-level scene graph logic (belongs to **SceneGraphAgent**).
- Shader cross-compilation (belongs to **ShaderAgent**).
- Algorithm design for compute workloads (belongs to **ComputeAgent**).

---

## Public Protocol (API Sketch)

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
    func destroy(_ handle: ResourceHandle)

    // Pipelines (graphics)
    func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle
    func draw(mesh: MeshHandle,
              pipeline: PipelineHandle,
              bindings: BindingSet,
              pushConstants: UnsafeRawPointer?,
              transform: float4x4) throws

    // Pipelines (compute)
    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle
    func dispatchCompute(_ pipeline: ComputePipelineHandle,
                         groupsX: Int, groupsY: Int, groupsZ: Int,
                         bindings: BindingSet,
                         pushConstants: UnsafeRawPointer?) throws
}
```

> *Handles and descriptors are opaque engine types; implementations will provide platform-specific storage.*

### Event Integration

- Subscribe to SDL window events; on `WINDOW_RESIZED`, call `resize(...)`.
- On shutdown, ensure all GPU work is idle before releasing OS/SDL resources.

---

## Platform Backends

### MetalRenderBackend (Apple platforms)
- Acquire `CAMetalLayer` from SDL via shim; set up `MTLDevice`, `MTLCommandQueue`.
- Maintain depth/stencil textures per swap size; manage `MTLRenderPassDescriptor` each frame.
- Build `MTLRenderPipelineState` and `MTLComputePipelineState` from ShaderAgent outputs (.metallib).

### D3DRenderBackend (Windows)
- Acquire `HWND` from SDL; create DXGI factory, `ID3D12Device`, command queues, swapchain.
- Implement descriptor heaps, command allocators, and a fence-based frame pacing.
- Build PSO (graphics/compute) from ShaderAgent outputs (DXIL).

### VulkanRenderBackend (Linux / optional macOS via MoltenVK)
- Request instance extensions from SDL; create `VkInstance`.
- Create `VkSurfaceKHR` via shim; pick physical device & queue families; create `VkDevice`.
- Create swapchain, depth images, render passes, framebuffers; implement pipeline cache.
- Build `VkPipeline` / `VkPipelineLayout` from ShaderAgent outputs (SPIR‑V).

---

## Inputs
- SDL window (`SDLWindow`), native window/surface handles from C shim.
- Compiled shader artifacts from **ShaderAgent**.
- Renderable sets (meshes + materials + transforms) from **SceneGraphAgent**.

## Outputs
- Presented frames.
- GPU resource handles returned to higher layers.
- Diagnostics (validation errors, device lost events).

---

## Dependencies
- **CSDL3 shim** additions for native handles.
- **ShaderAgent** for cross-compiled shader binaries.
- **SceneGraphAgent** for draw submission order and materials.
- **ComputeAgent** for compute dispatch integration.

---

## Milestones & Acceptance Criteria

1) **C Shim Ready**
   - Metal layer / HWND / Vulkan surface retrieval callable from Swift.
   - Verified on each platform with a minimal sample.

2) **Triangle on Each Backend**
   - Render a colored triangle using platform-native pipeline; present without validation errors.

3) **Resource & Resize**
   - Create/destroy buffers & textures; handle window resize with correct back buffer reallocation.

4) **Scene Integration**
   - Draw a mesh list from SceneGraphAgent including per-object transforms and a depth buffer.

5) **Compute Hook**
   - Run a trivial compute shader (e.g., vector add) and verify output buffer.

6) **Stability**
   - 60s render soak with resize and minimize/restore; no leaks, no device‑lost on happy path.

---

## Risks & Mitigations
- **Device lost / swapchain invalidation:** centralize recreate paths; add exhaustive error mapping.
- **API divergence:** keep `RenderBackend` minimal & stable; hide platform quirks behind helpers.
- **Threading pitfalls:** enforce single-threaded command recording per backend or document rules.

---

## Testing
- Headless frame capture where supported; checksum a tiny offscreen render.
- Validation layers (Vulkan), D3D12 debug layer, Metal API validation toggles.
- CI matrix per platform to compile and run smoke tests.

