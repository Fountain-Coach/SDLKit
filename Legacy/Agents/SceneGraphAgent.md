# SceneGraphAgent

**Role:** Implements the 3D scene graph (nodes, cameras, lights, meshes, materials), update loop (transforms, culling), and draw submission to the RenderBackend.

> Based on Implementation Strategy – Section 1 “3D Scene Graph Architecture” and Section 10 roles.

---

## Objectives
- Hierarchical transforms; world‑space propagation.
- Cameras (perspective/orthographic), light types (directional/point/spot).
- Materials referencing pipelines/shaders from ShaderAgent.
- Submission of visible objects to GraphicsAgent each frame.

## Core Types (Swift Sketch)

```swift
public final class Scene {
    public var root = SceneNode("root")
    public var activeCamera: Camera?
    public var lights: [Light] = []
}

public class SceneNode {
    public let name: String
    public var localTransform: float4x4
    public private(set) var worldTransform: float4x4
    public weak var parent: SceneNode?
    public var children: [SceneNode] = []
    // attachable components:
    public var mesh: Mesh? = nil
    public init(_ name: String) { self.name = name; self.localTransform = .identity; self.worldTransform = .identity }
}

public final class Camera: SceneNode {
    public enum Projection { case perspective(fovY: Float, near: Float, far: Float),
                              case orthographic(width: Float, height: Float, near: Float, far: Float) }
    public var projection: Projection
}

public struct Mesh {
    public let vertexBuffer: BufferHandle
    public let indexBuffer: BufferHandle?
    public let indexCount: Int
    public var material: Material
}

public struct Material {
    public let pipeline: PipelineHandle
    public var bindings: BindingSet // textures, uniform buffers, samplers
}
```

---

## Frame Update & Render (Pseudo)

```swift
func updateAndRender(scene: Scene, backend: RenderBackend) {
    // 1) Update world transforms
    propagateWorld(from: scene.root, parentMatrix: .identity)

    // 2) Cull (optional simple frustum test with active camera)
    let visible = gatherVisible(scene: scene)

    // 3) Submit
    try? backend.beginFrame()
    for node in visible where node.mesh != nil {
        let m = node.mesh!
        try? backend.draw(mesh: m.vertexBuffer.asMeshHandle(index: m.indexBuffer, count: m.indexCount),
                          pipeline: m.material.pipeline,
                          bindings: m.material.bindings,
                          transform: node.worldTransform)
    }
    try? backend.endFrame()
}
```

### Sampler Bindings

- Materials that sample textures should request explicit sampler state objects from `RenderBackend.createSampler` during material setup.
- Populate both the texture and sampler slots when filling a `BindingSet`:
  ```swift
  var bindings = BindingSet()
  bindings.setTexture(albedoTextureHandle, at: 10)
  bindings.setSampler(linearWrapSampler, at: 10) // same slot as texture sampler declared in shader
  ```
- This explicit pairing ensures shaders receive the correct filtering and addressing modes across Metal, D3D12, and Vulkan.

---

## Inputs
- Window size & camera parameters (for projection).
- Materials (pipelines + bindings) from **ShaderAgent**/**GraphicsAgent**.
- Models/geometry streams (application-defined).

## Outputs
- Ordered draw calls via **GraphicsAgent**.
- Per‑frame uniform data (camera matrices, light lists).

## Milestones
1) Transform system + simple traversal.
2) Single camera + unlit mesh.
3) Lighting pass (per‑pixel Blinn/Phong) with one directional light.
4) Depth & culling; multiple meshes; resizing.
5) Material system (textures, samplers, constants).

## Risks
- State duplication across nodes: introduce components and reuse materials.
- Performance: add coarse culling and instancing after MVP.

## Testing
- Unit tests for transform propagation.
- Golden‑image tests for a fixed scene (tolerances per backend).

