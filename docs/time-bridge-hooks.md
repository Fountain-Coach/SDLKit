# Time‑Bridge Hooks — Closing Gaps Incrementally with Small, Safe Steps

This plan breaks the largest gaps into small, time‑bounded steps that Codex (or any contributor) can complete locally under limited wall‑clock budgets. Each step has a narrow scope, clear acceptance criteria, and feature flags for safe rollout.

Principles
- Keep changes small (≤ 3 files, ≤ ~150 LOC) with a single semantic commit.
- Prefer additive work behind flags; avoid breaking default paths.
- Provide a dry‑run or HEADLESS_CI‑safe mode where possible.

## T1 — Audio OpenAPI Spec
Goal: Document the audio endpoints and serve a JSON mirror.
Steps (≤ 30 min)
- Add `sdlkit.audio.v1.yaml` alongside `sdlkit.gui.v1.yaml`.
- Extend `OpenAPISpec.swift` or `JSONTools` loader to serve `/openapi-audio.yaml` and `/openapi-audio.json` following the same env‑override rules.
Acceptance
- `curl /openapi-audio.json` returns the JSON mirror of the YAML (or external file).

## T2 — Minimal Reflection Check (SPIR‑V/DXIL)
Goal: Catch common binding/layout drift early.
Steps (≤ 60 min)
- Add `ShaderReflection.swift` with a helper that optionally parses SPIR‑V via `spirv-cross --reflect` JSON (when tools are present) or a lightweight DXIL parser on Windows.
- Compare: declared `BindingSlot`s and `vertexLayout` vs reflected bindings/attributes.
- Gate behind `SDLKIT_REFLECTION_VALIDATE=1`. On mismatch → `AgentError.invalidArgument` with actionable details.
Acceptance
- With the flag set, a deliberate mismatch in a test module produces a clear error.

## T3 — Interop M5 (Instanced Meshes)
Goal: Compute → instance transform+color buffer; instanced draw call.
Steps (≤ 90 min)
- Add `Shaders/compute/instances_update.hlsl` to update N instance matrices/colors.
- Extend SceneGraph to hold an `instanceBuffer` and count; add a tiny instanced cube draw in the demo behind `SDLKIT_INSTANCED_DEMO=1`.
- Add a harness capture (optional; manual first).
Acceptance
- Demo renders multiple moving instances; compute updates visible in animation.

## T4 — CI GPU Gate (macOS)
Goal: Ensure golden runs execute on PRs that change graphics/shaders.
Steps (≤ 30 min)
- In `.github/workflows/ci.yml`, add a `paths` filter for Graphics/Shaders to auto‑run the GPU job, or a label auto‑apply action that dispatches GPU mode.
Acceptance
- PRs touching `Sources/SDLKit/Graphics/**` or `Shaders/**` run the macOS GPU golden step by default.

## T5 — Scene Culling (Feature Flag)
Goal: Basic frustum culling behind `SDLKIT_CULLING=1`.
Steps (≤ 45 min)
- Add `Culling.swift` with AABB vs frustum; SceneNode can provide a default AABB based on mesh type.
- Apply culling in `SceneGraphRenderer.updateAndRender` only when the flag is set.
Acceptance
- With the flag set, off‑screen nodes are skipped (log counters for verification).

## T6 — Add‑a‑Material Quickstart
Goal: Reduce friction for new shaders.
Steps (≤ 30 min)
- New doc `docs/add-material.md` with a 10‑step recipe to add a shader, bindings, and a demo snippet.
- Cross‑link from README.
Acceptance
- Doc published and referenced from README + shader tooling guide.

## Integration Guardrails
- Env flags: `SDLKIT_REFLECTION_VALIDATE`, `SDLKIT_INSTANCED_DEMO`, `SDLKIT_CULLING`.
- HEADLESS_CI: keep reflection disabled by default; demo flags ignored.
- OpenAPI: serve audio spec only when present; otherwise return not_implemented to avoid brittle builds.

