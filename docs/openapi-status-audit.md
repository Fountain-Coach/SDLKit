# SDLKit OpenAPI Evolution — Status Audit

This audit reviews the "Executable Task List" from [`docs/openapi-evolution-m0-m6.md`](openapi-evolution-m0-m6.md) and captures the current implementation status across the repository. Each task references the authoritative assets (OpenAPI specs or design notes) that satisfy the milestone goals or call out remaining follow-up items.

## Summary Table

| Task | Scope | Status | Evidence & Notes |
| --- | --- | --- | --- |
| 1. Define API versioning strategy | Versioning, namespace planning | ✅ Complete | `docs/sdlkit-render-v1-plan.md` establishes the `sdlkit.render.v1` namespace, semantic versioning, dual-publication strategy, and migration guidance.【F:docs/sdlkit-render-v1-plan.md†L1-L33】 |
| 2. Model shared handles in OpenAPI components | Handle schemas (`ShaderID`, `BufferHandle`, etc.) | ✅ Complete | `sdlkit.render.v1.yaml` ships canonical schemas for shader IDs and GPU resource handles, ensuring consistent validation across agents.【F:sdlkit.render.v1.yaml†L626-L700】 |
| 3. Add native-handle negotiation endpoints (M0) | Platform surface discovery | ✅ Complete | System endpoints `/agent/system/native-handles` and `/agent/system/native-handles/negotiate` expose Metal/D3D/Vulkan handles with backend negotiation semantics.【F:sdlkit.render.v1.yaml†L28-L110】 |
| 4. Introduce resource & pipeline management paths (M1) | Buffers, textures, pipelines, frame control | ✅ Complete | Render endpoints cover buffer/texture creation, pipeline registration, resource destruction, and the frame lifecycle contract with begin/end/wait surfaces.【F:sdlkit.render.v1.yaml†L112-L240】 |
| 5. Create scene graph management paths (M2) | Scene, nodes, draws | ✅ Complete | Scene endpoints manage scene handles, node transforms, camera binding, and draw submission batches consistent with the scene graph contract.【F:sdlkit.render.v1.yaml†L242-L362】【F:sdlkit.render.v1.yaml†L780-L836】 |
| 6. Extend materials & lighting schemas (M3) | Materials, lights, validation | ✅ Complete | Material registration, light descriptors, and shader-backed validation endpoints appear with detailed parameter schemas.【F:sdlkit.render.v1.yaml†L364-L452】【F:sdlkit.render.v1.yaml†L836-L872】 |
| 7. Add compute scheduler endpoints (M4) | Compute pipelines, dispatch, readback | ✅ Complete | Compute endpoints handle pipeline registration, asynchronous dispatch, readback jobs, and job status queries mirroring the compute scheduler contract.【F:sdlkit.render.v1.yaml†L454-L598】 |
| 8. Model graphics/compute synchronization (M5) | Fences, dependency modeling | ✅ Complete (updated in this PR) | Fence tokens/signals combine with the new `ResourceBarrier` schema to describe state transitions consumed by draw and dispatch payloads, covering graphics/compute interop requirements.【F:sdlkit.render.v1.yaml†L494-L610】【F:sdlkit.render.v1.yaml†L926-L1060】 |
| 9. Publish documentation artifacts (M6) | Docs linkage & examples | ✅ Complete (updated in this PR) | `/docs/render` now returns concrete guide metadata that links to scene graph, shader toolchain, and installation docs, satisfying the publication requirement.【F:sdlkit.render.v1.yaml†L600-L640】 |
| 10. Deprecate or re-tag 2D-only endpoints | GUI compatibility | ✅ Complete | Legacy 2D drawing endpoints in `sdlkit.gui.v1.yaml` are tagged `Legacy2D` and marked deprecated to steer clients toward the render namespace.【F:sdlkit.gui.v1.yaml†L452-L498】 |

## Follow-up Suggestions

* Monitor cross-spec changes so shared handle schemas remain synchronized between render and GUI agents.
* Expand future docs under `/docs/render` with example payloads or Postman collections as milestone M6 deliverables evolve.
* Consider adding mesh creation/upload endpoints to complement existing mesh handle references once asset workflows are formalized.
