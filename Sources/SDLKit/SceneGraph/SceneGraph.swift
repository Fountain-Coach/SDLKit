import Foundation

public struct MaterialParams: Equatable {
    public var lightDirection: (Float, Float, Float)?
    public var baseColor: (Float, Float, Float, Float)?
    public var texture: TextureHandle?
    public init(lightDirection: (Float, Float, Float)? = nil,
                baseColor: (Float, Float, Float, Float)? = nil,
                texture: TextureHandle? = nil) {
        self.lightDirection = lightDirection
        self.baseColor = baseColor
        self.texture = texture
    }

    public static func == (lhs: MaterialParams, rhs: MaterialParams) -> Bool {
        Self.vec3Equal(lhs.lightDirection, rhs.lightDirection) &&
        Self.vec4Equal(lhs.baseColor, rhs.baseColor) &&
        lhs.texture == rhs.texture
    }

    private static func vec3Equal(_ lhs: (Float, Float, Float)?, _ rhs: (Float, Float, Float)?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.some(l), .some(r)): return l.0 == r.0 && l.1 == r.1 && l.2 == r.2
        default: return false
        }
    }

    private static func vec4Equal(_ lhs: (Float, Float, Float, Float)?, _ rhs: (Float, Float, Float, Float)?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.some(l), .some(r)): return l.0 == r.0 && l.1 == r.1 && l.2 == r.2 && l.3 == r.3
        default: return false
        }
    }
}

public struct Material {
    public var shader: ShaderID
    public var params: MaterialParams
    public init(shader: ShaderID, params: MaterialParams = MaterialParams()) {
        self.shader = shader
        self.params = params
    }
}

fileprivate struct MeshRegistrationCache: Equatable {
    var handle: MeshHandle
    var vertexBuffer: BufferHandle
    var vertexCount: Int
    var indexBuffer: BufferHandle?
    var indexCount: Int
    var indexFormat: IndexFormat
}

public struct Mesh {
    public var vertexBuffer: BufferHandle {
        didSet { registrationCache = nil }
    }
    public var vertexCount: Int {
        didSet { registrationCache = nil }
    }
    public var indexBuffer: BufferHandle? {
        didSet { registrationCache = nil }
    }
    public var indexCount: Int {
        didSet { registrationCache = nil }
    }
    public var indexFormat: IndexFormat {
        didSet { registrationCache = nil }
    }

    fileprivate var registrationCache: MeshRegistrationCache?

    public init(vertexBuffer: BufferHandle, vertexCount: Int, indexBuffer: BufferHandle? = nil, indexCount: Int = 0, indexFormat: IndexFormat = .uint16) {
        self.vertexBuffer = vertexBuffer
        self.vertexCount = vertexCount
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.indexFormat = indexFormat
        self.registrationCache = nil
    }

    @MainActor
    public mutating func ensureHandle(with backend: RenderBackend) throws -> MeshHandle {
        if let cache = registrationCache,
           cache.vertexBuffer == vertexBuffer,
           cache.vertexCount == vertexCount,
           cache.indexBuffer == indexBuffer,
           cache.indexCount == indexCount,
           cache.indexFormat == indexFormat {
            return cache.handle
        }
        let handle = try backend.registerMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexFormat: indexFormat
        )
        registrationCache = MeshRegistrationCache(
            handle: handle,
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexFormat: indexFormat
        )
        return handle
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
    public var lightDirection: (Float, Float, Float) // world-space direction
    public init(root: SceneNode, camera: Camera? = nil, lightDirection: (Float, Float, Float) = (0.3, -0.5, 0.8)) {
        self.root = root; self.camera = camera; self.lightDirection = lightDirection
    }
}

@MainActor
public enum SceneGraphRenderer {
    // Simple cache of pipelines per shader id
    private static var pipelineCache: [ShaderID: PipelineHandle] = [:]

    public static func resetPipelineCache() {
        pipelineCache.removeAll()
    }

    public static func updateAndRender(
        scene: Scene,
        backend: RenderBackend,
        colorFormat: TextureFormat = .bgra8Unorm,
        depthFormat: TextureFormat? = .depth32Float,
        beforeRender: (() throws -> Void)? = nil
    ) throws {
        scene.root.updateWorldTransform(parent: .identity)
        try backend.beginFrame()
        defer { try? backend.endFrame() }
        if let beforeRender {
            try beforeRender()
        }
        let vp: float4x4
        if let cam = scene.camera {
            vp = cam.view * cam.projection
        } else {
            vp = .identity
        }
        try renderNode(scene.root, backend: backend, colorFormat: colorFormat, depthFormat: depthFormat, vp: vp, lightDir: scene.lightDirection)
    }

    private static func renderNode(_ node: SceneNode, backend: RenderBackend, colorFormat: TextureFormat, depthFormat: TextureFormat?, vp: float4x4, lightDir: (Float, Float, Float)) throws {
        if var mesh = node.mesh, let material = node.material {
            let pipeline = try pipelineFor(material: material, backend: backend, colorFormat: colorFormat, depthFormat: depthFormat)
            let meshHandle = try mesh.ensureHandle(with: backend)
            node.mesh = mesh
            var bindings = BindingSet()
            if let textureHandle = material.params.texture {
                bindings.setValue(textureHandle, for: 10) // fragment texture slot 0
            }
            let mvp = node.worldTransform * vp
            // Determine light direction preference: material overrides scene
            let matLight = material.params.lightDirection ?? lightDir
            // Determine base color: default white if none; alpha encodes hasTexture (1 => texture bound)
            let base = material.params.baseColor ?? (1,1,1,1)
            // Build push constants block: 16 floats (MVP) + 4 floats (lightDir) + 4 floats (baseColor)
            var data = mvp.toFloatArray()
            data.append(contentsOf: [matLight.0, matLight.1, matLight.2, 0.0])
            data.append(contentsOf: [base.0, base.1, base.2, base.3])
            let constantsData = data.withUnsafeBytes { buffer in Data(buffer) }
            bindings.materialConstants = BindingSet.MaterialConstants(data: constantsData)
            try backend.draw(
                mesh: meshHandle,
                pipeline: pipeline,
                bindings: bindings,
                transform: mvp
            )
        }
        for child in node.children { try renderNode(child, backend: backend, colorFormat: colorFormat, depthFormat: depthFormat, vp: vp, lightDir: lightDir) }
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
