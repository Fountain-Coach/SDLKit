# ComputeAgent

**Role:** Provides a cross‑platform GPU compute layer for non‑graphics workloads (audio DSP, physics, ML inference). Shares the same device/context as graphics; exposes simple APIs to create compute pipelines and dispatch workloads.

> See Implementation Strategy – Section 5 “GPU Compute Module Design” and Section 10 roles.

---

## Objectives
- Uniform compute API across Metal/D3D/Vulkan.
- Zero‑copy interop with graphics buffers/textures when possible.
- Simple synchronization model (per‑frame fences or explicit barriers by backend).

## Scope
- Define compute pipeline descriptors and dispatch APIs.
- Integrate with ShaderAgent for compute shader artifacts.
- Buffer/texture binding model aligned with graphics for resource sharing.

---

## API Sketch

```swift
public struct ComputePipelineDescriptor {
    public let shaderID: ShaderID       // from ShaderAgent
    public let bindings: [BindingSlot]  // UAV/SRV textures & buffers
    public let pushConstantSize: Int
}

public struct ComputeDispatch {
    public let groupsX: Int
    public let groupsY: Int
    public let groupsZ: Int
}

public protocol ComputeScheduler {
    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle
    func dispatch(_ d: ComputeDispatch,
                  pipeline: ComputePipelineHandle,
                  bindings: BindingSet) throws
    func readback(buffer: BufferHandle, into: UnsafeMutableRawPointer, length: Int) throws
}
```

### Samplers in Compute Workflows
- Compute shaders that sample textures must request sampler handles from the graphics backend (`RenderBackend.createSampler`).
- Bind sampler handles explicitly via `BindingSet.setSampler(_, at:)` to ensure filtering and addressing state is consistent across platforms.
- `BindingSet` validation rejects mismatched resource types at dispatch time, surfacing incorrect bindings early in development.

**Inputs**
- Compiled compute shader binaries from **ShaderAgent**.
- Resource handles (buffers/textures) from **GraphicsAgent**.
- Work sizes and parameters from higher‑level systems (e.g., physics/audio modules).

**Outputs**
- Executed GPU workloads with results in shared buffers or CPU‑visible staging buffers.

**Use‑Case Examples**
- **Audio DSP:** FFT/Convolution reverb in compute; output to audio buffers.
- **Physics:** Particle update or broadphase on GPU; positions written into vertex buffers.
- **ML:** Small model inference with compute shaders (or interop with platform ML when available).

**Milestones**
1) Vector‑add sample with validation on all backends.
2) Buffer <-> texture interop demo (e.g., compute writes to texture, graphics samples it).
3) Readback path + correctness tests.
4) Performance benchmarks & tuning guides.

**Risks**
- Synchronization errors: provide helper utilities per backend (barriers, resource states).
- Readback stalls: recommend staging/pipelining; document patterns.

