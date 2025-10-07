# Shader Toolchain Guide

SDLKit ships committed shader binaries, but the repository also contains the end-to-end toolchain so contributors can rebuild artifacts or author new shaders. This guide collects the workflow, required tooling, and verification steps that previously lived in the README.

## 1. Install external tools

SDLKit uses a single-source HLSL flow that targets multiple graphics APIs. Install the following utilities and expose them via your `PATH` or the documented environment variables.

- **DXC** — required to compile HLSL to DXIL and SPIR-V. Configure `SDLKIT_SHADER_DXC` or ensure `dxc` is discoverable.
- **SPIRV-Cross** *(optional)* — converts SPIR-V to MSL when native `.metal` sources are unavailable. Configure `SDLKIT_SHADER_SPIRV_CROSS`.
- **Apple `metal` / `metallib`** *(optional, macOS)* — builds `.metallib` outputs directly. Override discovery with `SDLKIT_SHADER_METAL` and `SDLKIT_SHADER_METALLIB`.
- **Python 3** — runs the helper script invoked by the SwiftPM plugin.

You can also place tool binaries under `External/Toolchains/bin` to avoid editing your global `PATH`.

## 2. Provide per-project overrides

The shader build plugin reads optional `.fountain/sdlkit/shader-tools.env` files to inject environment overrides when it runs. This lets teams codify tool paths or compiler flags per repository without touching user shells.

## 3. Invoke the build

Building `SDLKit` automatically triggers the `ShaderBuildPlugin`, which calls:

```
Scripts/ShaderBuild/build-shaders.py <package-root> <workdir>
```

before compilation. You can also trigger the script manually:

```bash
python3 Scripts/ShaderBuild/build-shaders.py "$(pwd)" .build/shader-cache
```

The script emits DXIL, SPIR-V, and Metallib artifacts, writes optional intermediate `.msl/.air` files, and records a `shader-build.log` summary inside the working directory.

## 4. Artifact layout

The plugin copies final binaries into `Sources/SDLKit/Generated/{dxil,spirv,metal}`. `ShaderLibrary` loads these artifacts at runtime and exposes both graphics and compute shaders so render and compute paths share metadata.

## 5. Verification

Run the focused shader tests to ensure the manifest matches the committed binaries:

```bash
swift test --filter ShaderArtifactsTests
```

The tests confirm the expected files exist and align with the manifest checked into source control.

## 6. Binding layout reference

Shader modules share a logical binding model so the graphics and compute agents can build `BindingSet` payloads without
hard-coding backend-specific register numbers. The tables below summarize the bindings that must be populated for each
module.

### Graphics modules

| Shader ID | Vertex inputs | Vertex bindings | Fragment bindings |
| --- | --- | --- | --- |
| `unlit_triangle` | `POSITION`, `COLOR` | `b0` uniform buffer (transform, push constants) | `t10` sampled texture (optional) |
| `basic_lit` | `POSITION`, `NORMAL`, `COLOR` | `b0` uniform buffer (scene constants) | `t10` sampled texture (material albedo) |
| `directional_lit` | `POSITION`, `NORMAL`, `TEXCOORD0` | `b0` uniform buffer (model, view-projection, light matrices) | `t10` albedo texture + sampler `s10`, `t20` shadow map + sampler `s20` |
| `pbr_forward` | `POSITION`, `NORMAL`, `TANGENT`, `TEXCOORD0` | `b0` uniform buffer (scene constants) | `b1` uniform buffer (material constants), `t10` albedo + sampler `s10`, `t11` normal map, `t12` metallic/roughness, `t13` occlusion, `t14` emissive, `t20` irradiance cube, `t21` specular prefilter cube + sampler `s21`, `t22` BRDF LUT + sampler `s22` |

Samplers reuse the same logical index as their paired texture. For example, `pbr_forward` expects the albedo texture and
its sampler in slot `10` so the backend can configure both resources consistently across Metal, D3D12, and Vulkan.

### Compute modules

| Shader ID | Threadgroup size | Bindings | Push constants |
| --- | --- | --- | --- |
| `vector_add` | `(64, 1, 1)` | `t0`/`t1` structured buffers (read), `u2` structured buffer (write) | 16 bytes (element count) |
| `scenegraph_wave` | `(1, 1, 1)` | `t0`, `t1` storage buffers, `t2` storage buffer (vertex data) | none |
| `ibl_prefilter_env` | `(8, 8, 1)` | `t0` environment cube + sampler `s0`, `u1` storage texture array | 16 bytes (`roughness`, `mipLevel`, `faceIndex`, `sampleCount`) |
| `ibl_brdf_lut` | `(16, 16, 1)` | `u0` storage texture (BRDF LUT) | 16 bytes (`sampleCount`) |

These bindings are surfaced through `ShaderLibrary` and validated in `ShaderArtifactsTests`; SceneGraphAgent and ComputeAgent
should mirror the indices when building `BindingSet` instances.
