# Metal, Vulkan & D3D12 Alpha Stabilization Task Matrix

This matrix tracks the concrete work required to graduate SDLKit's Metal (macOS), Vulkan (Linux), and Direct3D 12 (Windows) backends from their current alpha preview state to a **stable alpha** milestone. Tasks are actionable engineering items that can be scheduled immediately.

## Legend

| Status | Meaning |
| --- | --- |
| ☐ | Not started |
| ☐▶ | In progress |
| ☑ | Complete |

---

## Metal (macOS)

| Status | Area | Task | Notes |
| --- | --- | --- | --- |
| ☑ | Shading | Align push constant layout with cross-platform shaders | • Metal shaders now mirror the 96-byte push constant block (`uMVP`, `lightDir`, `baseColor`).<br>• `MetalRenderBackend.draw` streams the full block (or seeded defaults) into stage buffer slot 1.<br>• macOS golden renders tint meshes to confirm base-color propagation. |
| ☑ | Resource Binding | Implement `BindingSet` resource consumption in draw path | • Pipeline cache stores reflected bindings per pipeline.<br>• Draws bind buffers/textures/samplers per logical slot and flag invalid handles.<br>• SceneGraph regression covers textured materials to keep the path exercised. |
| ☐ | Validation | Expand automated coverage | • Integrate Metal run of golden-image harness covering lit + textured scenes.<br>• Ensure CI toggles Metal API validation for debug runs. |

---

## Vulkan (Linux)

| Status | Area | Task | Notes |
| --- | --- | --- | --- |
| ☑ | Push Constants | Match shader push-constant sizing | • `ShaderModule` now carries a 96-byte constant size for graphics shaders.<br>• Vulkan pipelines size `VkPushConstantRange` from metadata and include base-color defaults when push data is absent. |
| ☑ | Textures & Samplers | Replace stub texture backend | • Introduced `TextureResource` wrapping image/memory/view/sampler lifecycle.<br>• `createTexture` performs staging uploads, layout transitions, and default sampler creation.<br>• Resources tear down cleanly during destroy/deinit. |
| ☑ | Descriptor Binding | Bind `BindingSet` resources during draws | • Descriptor set layouts derive from shader reflection and allocate per-frame pools.<br>• Draw path binds buffers and textures (with a fallback white texture) before issuing commands.<br>• Linux golden test now exercises a lit textured scene under validation layers. |
| ☑ | Validation | Harden runtime checks | • Debug builds enable validation layers by default with optional overrides.<br>• Callback captures warnings/errors when `SDLKIT_VK_VALIDATION_CAPTURE` is set, exposing messages to tests. |

---

## D3D12 (Windows)

| Status | Area | Task | Notes |
| --- | --- | --- | --- |
| ☑ | Resource Binding | Wire `BindingSet` resources through draw path | • Root signatures expose descriptor tables for fragment textures with per-slot static samplers.<br>• Shader-visible SRV heaps allocate descriptors lazily and reuse handles across draws.<br>• Missing bindings fall back to a cached 1×1 white texture. |
| ☑ | Texture Upload | Implement texture creation & staging uploads | • `createTexture` now supports shader-read formats via upload buffers and resource state transitions.<br>• Fallback textures are created lazily and cleaned up during backend teardown.<br>• Descriptor heap allocation guards against exhaustion. |
| ☑ | Testing | Extend D3D12 golden image coverage | • Golden image test uploads a 2×2 test texture and validates the captured hash under `SDLKIT_GOLDEN` runs.<br>• Ensures descriptor heaps and sampler defaults behave consistently on Windows hardware. |

---

## Cross-Cutting

| Status | Area | Task | Notes |
| --- | --- | --- | --- |
| ☑ | Documentation | Publish backend readiness checklist | • Document Metal/Vulkan/D3D12 feature parity expectations and manual testing steps.<br>• Outline known limitations blocking beta.<br>• See [Metal, Vulkan & D3D12 Alpha Readiness Checklist](BackendReadinessChecklist.md) for the published guidance. |
| ☑ | Testing | Expand golden-image matrix | • macOS & Linux golden harnesses now render textured lit scenes with deterministic base-color tinting.<br>• Refresh stored hashes after capturing new baselines. |

---

## Next Steps

- ☐ Finish the Metal validation work by integrating the expanded golden-image harness into CI and enforcing API validation toggles for debug runs.
- ☐ Schedule a cross-backend verification pass that replays the lit textured scene on physical devices to confirm the new resource-binding paths.
- ☐ Draft the beta-readiness delta list (per backend) so remaining blockers after Metal validation are documented ahead of the stabilization review.

