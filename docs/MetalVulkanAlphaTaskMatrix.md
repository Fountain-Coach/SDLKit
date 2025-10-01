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
| ☐ | Shading | Align push constant layout with cross-platform shaders | • Extend `basic_lit.metal` & `unlit_triangle.metal` `Uniforms` with `float4 baseColor`.<br>• Copy full 96-byte push constants in `MetalRenderBackend.draw` and seed defaults when none provided.<br>• Update tests/golden captures to verify baseColor tinting. |
| ☐ | Resource Binding | Implement `BindingSet` resource consumption in draw path | • Cache reflected bindings per pipeline.<br>• Bind buffers, textures, and samplers for vertex/fragment stages using logical slots.<br>• Emit `AgentError.invalidArgument` for missing resources.<br>• Add textured draw regression exercising bindings. |
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
| ☐ | Testing | Expand golden-image matrix | • Ensure macOS + Linux jobs render both unlit & lit textured scenes.<br>• Record baseline images for new tests. |

---

## Next Steps

1. Prioritize Metal-side BindingSet integration and push-constant alignment to match the Vulkan and D3D12 implementations.
2. Expand the golden-image matrix (macOS + Linux) to cover textured scenes and record updated baselines.
3. Wire the validation capture hook into CI so Vulkan layer warnings fail fast during automation.

