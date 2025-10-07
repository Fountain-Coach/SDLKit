# SDLKit Status Audit — Graphics, Compute, SceneGraph, and Audio (Preview)

This document captures the current state of SDLKit versus its stated goals and lays out the concrete gaps to close. It is designed to help contributors (human or agent) pick up small, bounded tasks and iterate safely under time constraints.

## Executive Summary

What works now
- Multi‑API backends: Metal (macOS), Vulkan (Linux), D3D12 (Windows code present, CI off).
- Scene graph: unlit + basic lit, transforms, camera; compute interop demo (wave).
- Shader toolchain: HLSL → DXIL/SPIR‑V/MSL via DXC + SPIRV‑Cross; artifacts embedded and loaded.
- Compute: pipelines for vector add and IBL helpers; harness exercises compute→graphics.
- Harness + CI: golden image harness; macOS/Linux headless jobs; optional GPU/manual path.
- Audio (preview): capture, playback, device enum, ring buffer, WAV loader, resampler, GPU DFT/mel/onset, A2M stub, MIDI out (macOS), JSON endpoints, demo visualizer.

Gaps (most important first)
- Reflection/validation
  - Promise: strict reflection checks. Current: module manifests are hand‑authored in Swift without validating the compiled artifacts.
  - Risk: binding/attribute drift across backends; debugging overhead.
- Interop M5 acceptance (instanced meshes)
  - Promise: compute → instanced rendering. Current: compute populates a single storage‑backed vertex buffer; not instanced.
- OpenAPI coverage
  - Promise: JSON agent documented by OpenAPI. Current: GUI covered; audio endpoints are not in the spec or served.
- CI “golden” gate enforcement
  - Promise: parity checked on every merge across Metal/Vulkan. Current: GPU golden run is manual/label gated.
- Scene culling (optional but noted)
  - Promise: culling optional. Current: no culling pass.
- Packaging/docs polish
  - Promise: M6 packaging/docs. Current: shader toolchain doc exists; no short “add a material” recipe.

## Detailed Findings

Graphics backends
- Metal: full feature path with capture and compute. Good error hygiene. (Sources/SDLKit/Graphics/Metal/MetalRenderBackend.swift:10)
- Vulkan: real swapchain + device, validation capture, compute integration. Rendering still relies on core patterns shared with the stub in places. (Sources/SDLKit/Graphics/Vulkan/VulkanRenderBackend.swift:18)
- D3D12: device loss tests and resource state tracking present; Windows CI disabled due to toolchain.

SceneGraph
- Types and renderer present; transforms and lighting are correct; no culling; interop sample writes a single mesh buffer rather than instances. (Sources/SDLKit/SceneGraph/SceneGraph.swift:114, Sources/SDLKit/SceneGraph/SceneGraphComputeInterop.swift:27)

Shader library & tooling
- Robust build pipeline and module registry; missing runtime reflection validation against artifacts; manifests are hand‑maintained. (Sources/SDLKit/Graphics/ShaderLibrary.swift:1, Scripts/ShaderBuild/build-shaders.py:1)

Harness & CI
- Harness runs triangle/basic_lit/compute texture; persists golden keys; macOS/Linux headless jobs OK; GPU jobs gated manually. (Sources/SDLKit/Support/RenderBackendTestHarness.swift:1, .github/workflows/ci.yml:1)

Audio (preview)
- Capture, playback, queue, WAV, device enum, ring buffer, resampler, GPU DFT/mel/onset, A2M stub, MIDI Out (macOS), JSON endpoints, streaming, demo visualizer. OpenAPI spec missing for these endpoints.

## Risks & Impact
- Without reflection checks, shader layout drift can pass local tests but fail on another backend.
- Without instanced interop, we don’t stress multi‑resource binding and draw‑indexed‑instanced paths.
- Without OpenAPI for audio, clients can’t auto‑generate bindings and drift can accumulate.
- Without GPU golden runs per PR, graphical regressions may slip between manual runs.

## Near‑Term Recommendations
1) Minimal reflection checks (SPIR‑V/DXIL)
- Validate: binding indices per stage, vertex attributes, push constant sizes.
- Fail with actionable error if mismatched with `ShaderLibrary` manifest.

2) Interop M5 — instance buffer path
- Add compute shader to update an instance transform+color buffer.
- Render instanced quads/spheres; add a harness capture to lock behavior.

3) OpenAPI for audio
- Author `sdlkit.audio.v1.yaml` covering current endpoints.
- Extend agent to serve `openapi.json` for audio like the GUI spec.

4) CI GPU enforcement
- Activate macOS GPU harness on PRs that modify Graphics/Shader directories (label or paths‑filter trigger).
- Keep Linux Vulkan GPU harness TODO behind a separate pipeline until SDK availability is stable.

5) Optional: culling pass
- Add trivial frustum culling (AABB vs frustum) behind a feature flag.

6) Docs polish
- Add “Add a material quickly” guide: pick ShaderID, bindings cheat‑sheet from `ShaderLibrary`, and a mini sample.

