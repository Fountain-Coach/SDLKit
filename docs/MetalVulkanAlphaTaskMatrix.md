# Metal & Vulkan Alpha Stabilization Task Matrix

This matrix tracks the concrete work required to graduate SDLKit's Metal (macOS) and Vulkan (Linux) backends from their current alpha preview state to a **stable alpha** milestone. Tasks are actionable engineering items that can be scheduled immediately.

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
| ☐ | Push Constants | Match shader push-constant sizing | • Expose expected byte count from `ShaderModule`.<br>• Size `VkPushConstantRange` per pipeline.<br>• Upload all floats (MVP + lightDir + baseColor).<br>• Extend fallback path with default baseColor. |
| ☐ | Textures & Samplers | Replace stub texture backend | • Introduce `TextureResource` tracking image, memory, view, sampler.<br>• Implement `createTexture` with staging uploads & layout transitions.<br>• Destroy resources correctly on teardown. |
| ☐ | Descriptor Binding | Bind `BindingSet` resources during draws | • Derive descriptor set layouts from shader reflection.<br>• Allocate/update descriptor sets per frame.<br>• Bind buffers/textures/samplers before draws.<br>• Add textured render smoke test under validation layers. |
| ☐ | Validation | Harden runtime checks | • Enable Vulkan validation layers in debug builds.<br>• Capture validation log gate in CI to prevent regressions. |

---

## Cross-Cutting

| Status | Area | Task | Notes |
| --- | --- | --- | --- |
| ☐ | Documentation | Publish backend readiness checklist | • Document Metal/Vulkan feature parity expectations and manual testing steps.<br>• Outline known limitations blocking beta. |
| ☐ | Testing | Expand golden-image matrix | • Ensure macOS + Linux jobs render both unlit & lit textured scenes.<br>• Record baseline images for new tests. |

---

## Next Steps

1. Prioritize the Metal shading and Vulkan push constant fixes—they unblock validation of baseColor-sensitive materials across both platforms.
2. Schedule resource binding work (Metal BindingSet, Vulkan descriptors) to bring texture support online.
3. Follow up with validation and documentation tasks once the rendering paths are feature complete.

