# SDLKit Graphics Backend Implementation Audit

## Scope and Method
This audit reviews the three platform renderers under `Sources/SDLKit/Graphics` — Metal, Direct3D 12, and Vulkan — and the shared infrastructure they depend on. The goal is to identify which parts of each backend are production ready, highlight implementation gaps or operational risks, and produce a concrete backlog to lift every backend to the same production bar. The review focused on frame lifecycle management, resource and pipeline creation, shader integration, compute support, diagnostics, and conformance with the cross-agent contracts defined in `AGENTS.md`.

## Executive Summary
- **MetalRenderBackend** is feature complete for basic rendering and compute but hardcodes default uniform data and lacks sampler bindings and synchronization breadth for compute workloads, which will matter once real scene data and UAV workloads arrive.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L1-L539】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L540-L606】
- **D3D12RenderBackend** implements the full swapchain, resource, and pipeline stack, yet texture creation is limited to shader-read usage and compute dispatch ignores push-constant payloads, leaving material/compute parity behind Metal and Vulkan.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L8-L1420】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L426-L520】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1356-L1404】
- **VulkanRenderBackend** covers instance/swapchain setup, render passes, and descriptor management, but still depends on a stub core when `CVulkan` is absent, fabricates default push constants, and blocks compute textures/samplers, which prevents full-feature validation on Linux.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L12-L214】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L960-L1268】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1273-L1478】

## MetalRenderBackend
### Implemented Capabilities
- Initializes `CAMetalLayer`, device, command queue, triple buffering semaphore, and a built-in triangle vertex buffer for validation smoke tests.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L1-L130】
- Provides full frame lifecycle (`beginFrame`, `endFrame`, `resize`, `waitGPU`) and resource creation for buffers, textures, meshes, graphics pipelines, and compute pipelines.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L134-L539】
- Supports golden-image capture by reading back the drawable and hashing it, enabling automated visual regression checks.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L58-L68】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L188-L199】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L452-L539】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L840-L870】

### Gaps and Risks
- When push constants are absent, the backend injects default lighting/base-color data instead of surfacing the missing material payload, which will mask integration bugs with SceneGraphAgent.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L40-L43】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L414-L449】
- Sampler bindings are silently ignored for compute shaders because samplers are not modeled in `BindingSet`, preventing feature parity with graphics shaders and future filtering workloads.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L503-L521】
- Compute dispatch always issues a `.buffers` memory barrier and never covers textures/UAVs, leaving texture writes and read-after-write hazards unchecked.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L503-L539】
- There is no device-loss or drawable-restore handling beyond logging, so layer reconfiguration or Metal device removal would terminate the renderer instead of recovering.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L134-L208】

### Readiness Verdict
Metal is close to production-ready for the triangle and basic scene milestones but needs stronger error surfacing and resource binding completeness before the lighting and compute milestones can be trusted.

## D3D12RenderBackend
### Implemented Capabilities
- Builds the full DXGI/D3D12 stack (factory, device, swapchain, descriptor heaps, fences) and maintains frame resources, viewport state, and builtin geometry for validation runs.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L8-L420】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L700-L818】
- Implements buffer creation with state tracking, SRV-backed textures, mesh registration, graphics draw submission, and compute pipelines with UAV barriers for storage buffers.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L368-L520】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L785-L818】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1160-L1218】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1320-L1404】
- Provides golden-image capture hooks (`requestCapture`, `takeCaptureHash`) and DX12 debug-layer toggles for diagnostics.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1408-L1420】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1892-L1895】

### Gaps and Risks
- Texture creation rejects any usage besides `.shaderRead`, blocking render-targets, storage textures, and depth resources required for advanced materials and post-processing.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L426-L454】
- Graphics uniforms default to baked light/base-color data when push constants are missing, hiding material binding regressions instead of failing fast.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L58-L60】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1174-L1197】
- Compute dispatch must run inside `beginFrame`/`endFrame` and drops push-constant payloads with a warning, so compute shaders cannot receive parameter data and cannot be scheduled independently of the graphics loop.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1356-L1394】
- There is no handling for device removal/swapchain recreation errors (`DXGI_ERROR_DEVICE_REMOVED`, `DEVICE_RESET`), so device loss will crash the renderer.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1034-L1126】

### Readiness Verdict
D3D12 matches Metal for core rendering but is missing critical texture usages and compute data plumbing; production readiness requires closing those gaps and adding device-loss recovery.

## VulkanRenderBackend
### Implemented Capabilities
- Creates the Vulkan instance, optional debug messenger, selects queues, builds swapchain/depth targets, command buffers, and synchronization objects, falling back to the stub renderer when `CVulkan` is unavailable.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L12-L214】
- Constructs graphics pipelines with descriptor sets, push constant ranges, and per-frame descriptor pools, and executes draw calls that bind buffers, descriptors, and fallback textures.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L960-L1268】
- Implements buffer/texture uploads, golden-image capture via image copy, and validation message capture hooks for automated QA.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L320-L480】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L480-L640】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L286-L318】

### Gaps and Risks
- The backend still instantiates `StubRenderBackendCore` and only enables the full path when the optional `CVulkan` module is present, impeding default Linux builds from exercising real Vulkan code paths.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L148-L156】
- Like the other backends, it injects default light/base-color push constants when none are supplied, reducing the chance of detecting SceneGraph binding regressions.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L141-L145】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1226-L1238】
- Compute pipelines reject textures and samplers entirely and require dispatches to occur outside an active graphics frame, preventing parity with Metal compute workflows and mixed graphics/compute workloads.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1273-L1340】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1427-L1478】
- Swapchain recreation paths exist but device-loss paths (`VK_ERROR_DEVICE_LOST`) are not differentiated from resize/suboptimal events, risking crashes on TDR or driver resets.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L189-L214】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L240-L320】

### Readiness Verdict
Vulkan is the furthest from production parity: it needs guaranteed native builds, fuller compute support, and hardened device-loss handling to meet the multi-platform milestone.

## Cross-Cutting Observations
- Shader metadata comes from a shared `ShaderLibrary`, but only a handful of shaders are registered, so backend validation depends on these golden modules and will need expansion for more advanced materials.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L1-L118】
- All backends default missing push constants to baked lighting data; this masks integration failures and should be replaced with explicit error reporting.
- Compute support is inconsistent: Metal allows inline compute (with missing barriers), D3D12 forces compute inside the graphics frame, and Vulkan forbids compute while a frame is active. This prevents a unified `ComputeScheduler` from targeting all APIs reliably.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L470-L539】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1356-L1404】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1427-L1478】
- Sampler resources are unmodelled in `BindingSet`, leaving gaps in compute shaders (Metal ignores samplers, Vulkan rejects them, D3D12 cannot bind them via SRV tables).【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L503-L521】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1273-L1340】

## Feature Toggles and Graceful Degradation
- **Metal storage textures** now require `MTLDevice.readWriteTextureSupport != .tierNone`; texture creation falls back with `AgentError.invalidArgument` when the GPU cannot service `.shaderWrite` requests. Callers should catch this error and disable compute passes that rely on storage textures or route the workload through buffers instead.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L236-L307】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L960-L998】
- **Metal render/depth targets** are allocated in `.storageModePrivate` and initialized via GPU blits, so CPU-side readback should request a dedicated staging texture rather than reusing the render target handle.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L236-L307】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L960-L1006】
- **Vulkan storage and attachment textures** validate both device features and format capabilities. If `createTexture` throws due to `VK_FORMAT_FEATURE_*` gaps or missing storage-image support, higher layers should fall back to compatible formats (e.g., `rgba8Unorm` for color, `depth32Float` for depth) or skip compute passes on that adapter.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L510-L640】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L2400-L2467】

## Production Readiness Backlog
1. **Unify push-constant/material binding contracts.** Make `BindingSet` carry explicit material payloads, remove backend default fallbacks, and add validation that emits actionable errors when bindings are missing.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L414-L449】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1174-L1197】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1226-L1238】
2. **Implement sampler resources across compute and graphics.** Extend `BindingSet`/resource creation APIs to expose sampler handles and implement binding for Metal, D3D12, and Vulkan compute/graphics paths.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L503-L521】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1273-L1340】
3. **Broaden texture support.** Add render-target, depth-stencil, and storage texture creation to D3D12 and verify Vulkan storage textures plus Metal private storage modes to satisfy SceneGraph and ComputeAgent requirements.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L426-L454】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L320-L640】
4. **Harden compute scheduling.** Allow compute dispatch on dedicated command queues (D3D12/Vulkan), supply push constants, and add texture/UAV barriers so GPU compute features can be validated uniformly.【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L470-L539】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1356-L1404】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L1427-L1478】
5. **Device-loss and swapchain resilience.** Implement explicit handling for device-removed/device-lost cases in D3D12 and Vulkan, rebuild pipelines/swapchains, and add soak tests that trigger resize/device-reset scenarios.【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1034-L1126】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L189-L214】
6. **Guarantee native Vulkan builds.** Make `CVulkan` a hard dependency (or provide an alternate path) so Linux CI executes the real backend instead of the stub, and expand validation message capture into automated CI assertions.【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L148-L156】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L286-L318】
7. **Expand shader coverage and automated tests.** Add lit/material shader modules to `ShaderLibrary` and create backend regression tests (triangle, lit mesh, compute vector-add) that leverage the golden-image capture interfaces across all platforms.【F:Sources/SDLKit/Graphics/ShaderLibrary.swift†L73-L118】【F:Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift†L188-L199】【F:Sources/SDLKit/Graphics/D3D12/D3DRenderBackend.swift†L1892-L1895】【F:Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift†L286-L318】

Delivering the backlog above will align all three backends with the production milestones in `AGENTS.md` and unblock cross-agent integration for shaders, scene graph, and compute workloads.
