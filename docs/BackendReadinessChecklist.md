# Metal & Vulkan Alpha Readiness Checklist

This checklist documents the current expectations, validation steps, and known gaps for stabilizing SDLKit's Metal and Vulkan backends during the alpha milestone. It is intended for engineers and QA reviewers scheduling verification work prior to declaring feature parity across desktop platforms.

## Usage

1. Review the **Feature Parity** table to confirm each backend meets the minimum supported capabilities.
2. Execute the **Manual Testing** sequences on target hardware (macOS 13+ w/ Apple GPU, Linux w/ Vulkan 1.2 GPU).
3. File regressions or block release if any **Known Limitations** violate product requirements.

---

## Feature Parity Expectations

| Capability | Metal (macOS) | Vulkan (Linux) | Notes |
| --- | --- | --- | --- |
| Unlit triangle sample | ✅ | ✅ | Both backends render `unlit_triangle` shader without validation errors.
| Lit mesh rendering | ✅ | ✅ | Requires `basic_lit` shader push constants (MVP, light direction, base color) to match cross-platform layout.
| Texture sampling | ⚠️ Pending BindingSet integration | ⚠️ Pending descriptor set binding | Texture paths remain disabled until BindingSet work lands on both backends.
| Resize handling | ✅ | ⚠️ Requires additional testing | Vulkan swapchain recreation validated on latest driver stack but needs soak testing.
| GPU compute interop | ⚠️ Planned post-alpha | ⚠️ Planned post-alpha | Compute integration begins after graphics alpha stabilization.

Legend: ✅ — Verified in current builds, ⚠️ — Partial or pending follow-up work.

---

## Manual Testing Sequences

### Metal (macOS)

1. Launch `SDLKitDemo` with the Metal backend in debug configuration.
2. Verify window creation without API validation errors.
3. Render the lit mesh scene and adjust base color through debug UI; confirm tint propagates via push constants.
4. Resize window between standard aspect ratios (16:9, 4:3) and ensure swapchain/depth resources recreate without flicker.
5. Capture golden images for unlit and lit textured scenes; compare with stored baselines.

### Vulkan (Linux)

1. Launch `SDLKitDemo` using the Vulkan backend under `VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation`.
2. Confirm push constant uploads match shader byte size (MVP + light direction + base color) with no validation warnings.
3. Execute textured scene rendering once descriptor binding work is merged; record discrepancies.
4. Force a window resize and validate swapchain recreation (new depth image, framebuffer rebuild).
5. Export rendered frames for golden-image comparison and archive logs from validation layers.

---

## Known Limitations Blocking Beta

- **Texture resource binding**: Both backends lack complete `BindingSet` integration, preventing textured material validation.
- **Automated validation coverage**: Continuous integration does not yet capture Metal or Vulkan validation logs, limiting early detection.
- **Compute scheduling**: GPU compute interoperability is scheduled for the next milestone and is not considered part of the alpha readiness scope.

Keep this checklist updated as tasks in the [Metal & Vulkan Alpha Stabilization Task Matrix](MetalVulkanAlphaTaskMatrix.md) progress.
