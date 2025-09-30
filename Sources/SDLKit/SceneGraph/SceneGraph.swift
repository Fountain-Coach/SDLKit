import Foundation

public struct Material {
    public var shader: ShaderID
    public init(shader: ShaderID) { self.shader = shader }
}

public struct Mesh {
    public var vertexBuffer: BufferHandle
    public var vertexCount: Int
    public init(vertexBuffer: BufferHandle, vertexCount: Int) {
        self.vertexBuffer = vertexBuffer
        self.vertexCount = vertexCount
    }
}

@MainActor
public final class SceneNode {
    public var name: String
    public var localTransform: float4x4
    public private(set) var worldTransform: float4x4
    public var mesh: Mesh?
    public var material: Material?
    public private(set) var children: [SceneNode] = []

    public init(name: String = "node", transform: float4x4 = .identity, mesh: Mesh? = nil, material: Material? = nil) {
        self.name = name
        self.localTransform = transform
        self.worldTransform = transform
        self.mesh = mesh
        self.material = material
    }

    public func addChild(_ node: SceneNode) { children.append(node) }

    public func updateWorldTransform(parent: float4x4) {
        worldTransform = parent * localTransform
        for child in children { child.updateWorldTransform(parent: worldTransform) }
    }
}

@MainActor
public struct Camera {
    public var view: float4x4
    public var projection: float4x4
    public init(view: float4x4, projection: float4x4) { self.view = view; self.projection = projection }
    public static func identity(aspect: Float = 1.0) -> Camera {
        let view = float4x4.identity
        let proj = float4x4.perspective(fovYRadians: .pi/3, aspect: aspect, zNear: 0.1, zFar: 100.0)
        return Camera(view: view, projection: proj)
    }
}

@MainActor
public struct Scene {
    public var root: SceneNode
    public var camera: Camera?
    public init(root: SceneNode, camera: Camera? = nil) { self.root = root; self.camera = camera }
}

@MainActor
public enum SceneGraphRenderer {
    // Simple cache of pipelines per shader id
    private static var pipelineCache: [ShaderID: PipelineHandle] = [:]

    public static func updateAndRender(scene: Scene, backend: RenderBackend, colorFormat: TextureFormat = .bgra8Unorm, depthFormat: TextureFormat? = .depth32Float) throws {
        scene.root.updateWorldTransform(parent: .identity)
        try backend.beginFrame()
        defer { try? backend.endFrame() }
        let vp: float4x4
        if let cam = scene.camera {
            vp = cam.view * cam.projection
        } else {
            vp = .identity
        }
        try renderNode(scene.root, backend: backend, colorFormat: colorFormat, depthFormat: depthFormat, vp: vp)
    }

    private static func renderNode(_ node: SceneNode, backend: RenderBackend, colorFormat: TextureFormat, depthFormat: TextureFormat?, vp: float4x4) throws {
        if let mesh = node.mesh, let material = node.material {
            let pipeline = try pipelineFor(material: material, backend: backend, colorFormat: colorFormat, depthFormat: depthFormat)
            var bindings = BindingSet()
            bindings.setValue(mesh.vertexBuffer, for: 0)
            let mvp = node.worldTransform * vp
            try backend.draw(mesh: MeshHandle(), pipeline: pipeline, bindings: bindings, pushConstants: nil, transform: mvp)
        }
        for child in node.children { try renderNode(child, backend: backend, colorFormat: colorFormat, depthFormat: depthFormat, vp: vp) }
    }

    private static func pipelineFor(material: Material, backend: RenderBackend, colorFormat: TextureFormat, depthFormat: TextureFormat?) throws -> PipelineHandle {
        if let cached = pipelineCache[material.shader] { return cached }
        let module = try ShaderLibrary.shared.module(for: material.shader)
        let desc = GraphicsPipelineDescriptor(
            label: material.shader.rawValue,
            shader: material.shader,
            vertexLayout: module.vertexLayout,
            colorFormats: [colorFormat],
            depthFormat: depthFormat,
            sampleCount: 1
        )
        let handle = try backend.makePipeline(desc)
        pipelineCache[material.shader] = handle
        return handle
    }
}
