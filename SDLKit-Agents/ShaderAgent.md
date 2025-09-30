# ShaderAgent

**Role:** Owns shader source organization, cross‑compilation, and pipeline creation across Metal (MSL), Direct3D (HLSL/DXIL), and Vulkan (SPIR‑V). Produces artifacts consumed by render and compute backends.

> Based on Implementation Strategy – Section 4 “Shader Abstraction and Cross‑Compilation Strategy” and Section 10 roles.

---

## Objectives
- Single‑source authoring (prefer HLSL) with **compile‑time** generation of: `.metallib` (Metal), DXIL (DirectX), and SPIR‑V (Vulkan).
- Define a `Shader`/`Pipeline` abstraction the engine can request by **ID**.
- Provide reflection/meta (expected vertex attributes, resource bindings, push constants).

## Scope
- Repo layout for shader sources and generated artifacts.
- Build scripts / SPM plugin to run **DXC** and **SPIRV‑Cross**, then Apple `metal`/`metallib` tools.
- Swift loaders that transform artifacts into backend pipeline objects.

---

## Directory Layout

```
Shaders/
  common/                   # shared .hlsl includes (types, lighting)
  graphics/
    basic_lit.hlsl          # VS/PS entry points: BasicVS, BasicPS
    unlit_textured.hlsl
  compute/
    fft_compute.hlsl        # CS entry point: FFTCS
Generated/                  # output per-platform (ignored in VCS)
  metal/*.metallib
  dxil/*.dxil
  spirv/*.spv
```

---

## Build Pipeline (Pseudo)

```bash
# HLSL → SPIR-V (Vulkan) and DXIL (DirectX)
dxc -T vs_6_7 -E BasicVS   -spirv -Fo Generated/spirv/basic_lit_vs.spv Shaders/graphics/basic_lit.hlsl
dxc -T ps_6_7 -E BasicPS   -spirv -Fo Generated/spirv/basic_lit_ps.spv Shaders/graphics/basic_lit.hlsl
dxc -T vs_6_7 -E BasicVS   -Fo Generated/dxil/basic_lit_vs.dxil       Shaders/graphics/basic_lit.hlsl
dxc -T ps_6_7 -E BasicPS   -Fo Generated/dxil/basic_lit_ps.dxil       Shaders/graphics/basic_lit.hlsl

# SPIR-V → MSL (Metal), then compile to metallib
spirv-cross Generated/spirv/basic_lit_vs.spv --msl > Generated/metal/basic_lit_vs.msl
spirv-cross Generated/spirv/basic_lit_ps.spv --msl > Generated/metal/basic_lit_ps.msl
xcrun metal   -o Generated/metal/basic_lit.air Generated/metal/basic_lit_vs.msl Generated/metal/basic_lit_ps.msl
xcrun metallib -o Generated/metal/basic_lit.metallib Generated/metal/basic_lit.air
```

*(Integrate via SwiftPM plugin or Makefile; only run the relevant steps per platform build.)*

---

## Swift Abstractions

```swift
public struct ShaderID: Hashable { public let rawValue: String }

public struct ShaderModuleDescriptor {
    public let id: ShaderID
    public let stages: [ShaderStage: URL] // per-platform artifact URLs
    public let vertexLayout: VertexLayout
    public let bindings: [BindingSlot]
}

public protocol ShaderLibrary {
    func load(_ id: ShaderID) throws -> ShaderModuleDescriptor
    func makeGraphicsPipeline(_ desc: GraphicsPipelineRequest) throws -> PipelineHandle
    func makeComputePipeline(_ desc: ComputePipelineRequest) throws -> ComputePipelineHandle
}
```

**Responsibilities**
- Maintain a registry (JSON/YAML) mapping **material/pipeline names → entry points, defines, vertex layout**.
- Emit platform artifacts and a metadata blob (reflection results).
- Provide thin loaders per backend to convert artifacts into pipeline objects.

**Inputs**
- Author‑time HLSL sources (+ optional GLSL/MSL variants).
- Target API list from build (Metal, D3D, Vulkan).
- Material/pipeline requests from SceneGraphAgent/GraphicsAgent.

**Outputs**
- Compiled artifacts (.metallib/.dxil/.spv).
- Pipeline descriptors & reflection metadata.

**Milestones**
1) Toolchain bootstrap (DXC/SPIRV‑Cross/metal).
2) Compile basic unlit and lit pipelines.
3) Metadata/reflection consumed by all backends.
4) CI shader build jobs per platform.

**Risks**
- Cross‑compilation mismatches (semantics/layout): enforce strict conventions and validation.
- Platform‑specific features: gate via `#ifdef` defines and provide fallbacks.

