# Device Loss & Swapchain Resize Testing Guide

This guide explains how to reproduce the synthetic device-loss and resize scenarios that back up the automated integration tests on Windows (Direct3D 12) and Linux (Vulkan).

> **Tip:** Set `SDLKIT_LOG_LEVEL=debug` when running the commands below to see the same recovery log lines asserted by the tests.

## Windows (Direct3D 12)

1. Ensure the Windows Swift toolchain is installed (CI uses `swift-actions/setup-swift`).
2. From a Visual Studio Developer PowerShell, run the Direct3D 12 integration test directly:
   ```powershell
   swift test --filter D3D12DeviceLossRecoveryTests/testDeviceLossRecoveryRestoresResources
   ```
   The test uses the `debugSimulateDeviceRemoval` shim to trigger a DXGI device removal, validates that resources are recreated, performs a swapchain resize, and checks that frames present afterwards.
3. To cross-check with vendor tooling, enable the D3D12 debug layer via `dxcfg.exe`, then attach PIX or the DirectX Control Panel to the SDLKit sample (`swift run SDLKitDemo --backend d3d12`). Use the "Force device removed" toggle to trigger a reset while resizing the window; the log output should match the entries asserted in the tests.

## Linux (Vulkan)

1. Install the Vulkan SDK (CI relies on the loader and validation layers provided by the `swift:6.1-jammy` container).
2. Run the Vulkan integration test:
   ```bash
   SDLKIT_LOG_LEVEL=debug swift test --filter VulkanDeviceLossRecoveryTests/testDeviceLossRecoveryRestoresResources
   ```
   This drives `debugSimulateDeviceLoss()` to make the backend rebuild the device, forces a swapchain resize, and asserts that rendering resumes without leaking tracked resources.
3. For manual experiments, launch the demo harness with validation layers enabled and use `VK_LAYER_KHRONOS_validation`'s `vk_layer_settings.txt` to inject device-loss return codes while resizing the window:
   ```bash
   export VK_LAYER_PATH=/path/to/vulkan/explicit_layer.d
   export VK_LOADER_DEBUG=all
   swift run SDLKitDemo --backend vulkan
   ```

## Investigating Failures

- Recovery logs should include entries similar to:
  - `[error] SDLKit.Graphics.D3D12: beginFrame failed due to device removal ...`
  - `[info] SDLKit.Graphics.Vulkan: Device reset completed after loss: ...`
- If the counts in `debugResourceInventory()` drift after the scenario, the integration tests will fail. Inspect the log output around `Device reset completed` to find the offending resource.
- When chasing flakes, rerun the affected test with `--repeat 5` to stress recovery while monitoring GPU memory usage with vendor tools (PIX, RenderDoc, Radeon GPU Profiler).

These steps mirror the automated CI workflow, making it straightforward to reproduce failures locally before pushing patches.
