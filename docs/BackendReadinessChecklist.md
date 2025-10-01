# Metal, Vulkan & D3D12 Alpha Readiness Checklist

This checklist documents the current expectations, validation steps, and known gaps for stabilizing SDLKit's Metal, Vulkan, and Direct3D 12 backends during the alpha milestone. It is intended for engineers and QA reviewers scheduling verification work prior to declaring feature parity across desktop platforms.

## Usage

1. Review the **Feature Parity** table to confirm each backend meets the minimum supported capabilities.
2. Execute the **Manual Testing** sequences on target hardware (macOS 13+ w/ Apple GPU, Linux w/ Vulkan 1.2 GPU).
3. File regressions or block release if any **Known Limitations** violate product requirements.

---

## Feature Parity Expectations

| Capability | Metal (macOS) | Vulkan (Linux) | D3D12 (Windows) | Notes |
| --- | --- | --- | --- | --- |
| Unlit triangle sample | ✅ | ✅ | ✅ | All backends render `unlit_triangle` shader without validation errors.
| Lit mesh rendering | ✅ | ✅ | ✅ | Requires `basic_lit` shader push constants (MVP, light direction, base color) to match cross-platform layout.
| Texture sampling | ✅ BindingSet textures & samplers wired | ✅ Descriptor-set binding with fallback sampler | ✅ Descriptor heap binding with static samplers | Metal now mirrors the BindingSet-driven texture/sampler path exercised by Vulkan and D3D12 textured draws.
| Resize handling | ✅ | ⚠️ Requires additional testing | ✅ | Vulkan swapchain recreation validated on latest driver stack but needs soak testing.
| GPU compute interop | ⚠️ Planned post-alpha | ⚠️ Planned post-alpha | ⚠️ Planned post-alpha | Compute integration begins after graphics alpha stabilization.

Legend: ✅ — Verified in current builds, ⚠️ — Partial or pending follow-up work.

---

## Manual Testing Sequences

### Metal (macOS)

1. Launch `SDLKitDemo` with the Metal backend in debug configuration.
2. Export `SDLKIT_METAL_VALIDATION=1` and `SDLKIT_GOLDEN=1` to match CI validation coverage.
3. Verify window creation without API validation errors.
4. Render the lit textured scene and adjust base color through debug UI; confirm tint propagates via push constants and textures remain sampled.
5. Resize window between standard aspect ratios (16:9, 4:3) and ensure swapchain/depth resources recreate without flicker.
6. Capture golden images for unlit and lit textured scenes; compare with stored baselines and archive updated hashes if deviations are expected. Attach captured hashes/logs to the CI artifact bucket for review.

### Vulkan (Linux)

1. Launch `SDLKitDemo` using the Vulkan backend under `VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation`.
2. Confirm push constant uploads match shader byte size (MVP + light direction + base color) with no validation warnings.
3. Execute the lit textured scene and verify descriptor-backed texture/sampler bindings produce expected imagery.
4. Force a window resize and validate swapchain recreation (new depth image, framebuffer rebuild).
5. Export rendered frames for golden-image comparison and archive logs from validation layers. Ensure CI runs with `SDLKIT_VK_VALIDATION_CAPTURE=1` remain warning-free.

### D3D12 (Windows)

1. Launch `SDLKitDemo` on a Windows validation machine with the D3D12 backend and the debug layer enabled.
2. Ensure the lit textured scene renders using the shared BindingSet resource path and that descriptor heaps do not overflow (monitor debug output for heap exhaustion warnings).
3. Capture golden frames and compare hashes with the CI baselines produced by the Vulkan/Metal runs to confirm cross-backend parity.
4. Record driver version, GPU, and any deviations; feed these into the cross-backend verification report.

---

## Known Limitations Blocking Beta

- **Automated Metal validation coverage**: Golden-image harness still runs manually; integrate Metal API validation into CI to catch regressions sooner.
- **Cross-backend device verification**: Schedule a coordinated pass on physical hardware to confirm the updated BindingSet-driven textured scenes across Metal, Vulkan, and D3D12.
- **Compute scheduling**: GPU compute interoperability is scheduled for the next milestone and is not considered part of the alpha readiness scope.

---

## Beta-Readiness Delta Tracking

| Backend | Remaining Gaps | Owners | Target Date |
| --- | --- | --- | --- |
| Metal | ✅ CI integration pending: land `macos-metal-golden` job with validation toggles enforced.<br>⚠️ Document recovery procedure when golden hashes drift between debug/profile builds. | GraphicsAgent + Release Eng | 2024-05-24 |
| Vulkan | ⚠️ Run extended resize/soak campaign on AMD + Mesa to validate swapchain robustness.<br>⚠️ Capture validation logs for cross-backend report. | GraphicsAgent (Linux) | 2024-05-28 |
| D3D12 | ⚠️ Gather descriptor heap telemetry under prolonged golden runs.<br>⚠️ Confirm golden outputs match Metal/Vulkan captures after pipeline cache warm-up. | GraphicsAgent (Windows) | 2024-05-29 |

> Update this table after each verification pass so the stabilization review has an authoritative delta list.

Keep this checklist updated as tasks in the [Metal & Vulkan Alpha Stabilization Task Matrix](MetalVulkanAlphaTaskMatrix.md) progress.
