import Foundation

@MainActor
public enum RenderBackendTestHarness {
    public enum HarnessError: Error, CustomStringConvertible {
        case captureUnsupported(backend: String)
        case goldenMismatch(expected: String, actual: String, key: String)

        public var description: String {
            switch self {
            case .captureUnsupported(let backend):
                return "Backend \(backend) does not expose GoldenImageCapturable"
            case .goldenMismatch(let expected, let actual, let key):
                return "Golden hash mismatch for \(key): expected=\(expected) actual=\(actual)"
            }
        }
    }

    public enum Test: String, CaseIterable {
        case unlitTriangle = "unlit_triangle"
        case basicLit = "basic_lit"
        case computeStorageTexture = "compute_storage_texture"
    }

    public struct Result: Sendable {
        public let backend: String
        public let test: Test
        public let hash: String
        public let goldenKey: String
    }

    public struct Options: Sendable {
        public var width: Int
        public var height: Int
        public var computeTextureSize: (width: Int, height: Int)
        public var allowGoldenWrite: Bool
        public var logger: (@Sendable (String) -> Void)?

        public init(width: Int = 256,
                    height: Int = 256,
                    computeTextureSize: (Int, Int) = (40, 30),
                    allowGoldenWrite: Bool = ProcessInfo.processInfo.environment["SDLKIT_GOLDEN_WRITE"] == "1",
                    logger: (@Sendable (String) -> Void)? = nil) {
            self.width = width
            self.height = height
            self.computeTextureSize = computeTextureSize
            self.allowGoldenWrite = allowGoldenWrite
            self.logger = logger
        }
    }

    public static func runFullSuite(backendOverride: String,
                                    options: Options = Options()) throws -> [Result] {
        let window = SDLWindow(config: .init(title: "SDLKitHarness-\(backendOverride)",
                                             width: options.width,
                                             height: options.height))
        try window.open()
        defer { window.close() }
        try window.show()

        let backend = try RenderBackendFactory.makeBackend(window: window, override: backendOverride)
        guard let capturable = backend as? GoldenImageCapturable else {
            throw HarnessError.captureUnsupported(backend: backendOverride)
        }

        var results: [Result] = []
        results.append(try runUnlitTriangle(window: window,
                                            backend: backend,
                                            capturable: capturable,
                                            backendKey: backendOverride,
                                            options: options))
        results.append(try runBasicLit(window: window,
                                       backend: backend,
                                       capturable: capturable,
                                       backendKey: backendOverride,
                                       options: options))
        results.append(try runComputeStorageTexture(window: window,
                                                    backend: backend,
                                                    capturable: capturable,
                                                    backendKey: backendOverride,
                                                    options: options))
        return results
    }

    private static func runUnlitTriangle(window: SDLWindow,
                                         backend: RenderBackend,
                                         capturable: GoldenImageCapturable,
                                         backendKey: String,
                                         options: Options) throws -> Result {
        let tintedBaseColor: (Float, Float, Float, Float) = (0.6, 0.45, 0.9, 1.0)
        struct Vertex { var px: Float; var py: Float; var pz: Float; var r: Float; var g: Float; var b: Float }
        let vertices: [Vertex] = [
            Vertex(px: -0.6, py: -0.5, pz: 0.0, r: 1.0, g: 0.0, b: 0.0),
            Vertex(px: 0.0, py: 0.6, pz: 0.0, r: 0.0, g: 1.0, b: 0.0),
            Vertex(px: 0.6, py: -0.5, pz: 0.0, r: 0.0, g: 0.0, b: 1.0)
        ]
        let vertexBuffer = try vertices.withUnsafeBytes { buffer in
            try backend.createBuffer(bytes: buffer.baseAddress,
                                     length: buffer.count,
                                     usage: .vertex)
        }
        var mesh = Mesh(vertexBuffer: vertexBuffer, vertexCount: vertices.count)
        let material = Material(shader: ShaderID("unlit_triangle"),
                                params: .init(baseColor: tintedBaseColor))
        let node = SceneNode(name: "HarnessTriangle",
                             transform: .identity,
                             mesh: mesh,
                             material: material)
        let root = SceneNode(name: "Root")
        root.addChild(node)
        let aspect = Float(options.width) / Float(max(1, options.height))
        let camera = Camera(view: float4x4.lookAt(eye: (0, 0, 2.0),
                                                  center: (0, 0, 0),
                                                  up: (0, 1, 0)),
                            projection: float4x4.perspective(fovYRadians: .pi / 3,
                                                             aspect: aspect,
                                                             zNear: 0.1,
                                                             zFar: 100.0))
        let scene = Scene(root: root, camera: camera, lightDirection: (0.0, 0.0, -1.0))

        capturable.requestCapture()
        try SceneGraphRenderer.updateAndRender(scene: scene,
                                               backend: backend,
                                               colorFormat: .bgra8Unorm,
                                               depthFormat: .depth32Float)
        let hash = try capturable.takeCaptureHash()
        let key = GoldenRefs.key(backend: backendKey,
                                 width: options.width,
                                 height: options.height,
                                 material: Test.unlitTriangle.rawValue)
        try compareGolden(hash: hash, key: key, options: options)
        return Result(backend: backendKey, test: .unlitTriangle, hash: hash, goldenKey: key)
    }

    private static func runBasicLit(window: SDLWindow,
                                    backend: RenderBackend,
                                    capturable: GoldenImageCapturable,
                                    backendKey: String,
                                    options: Options) throws -> Result {
        let mesh = try MeshFactory.makeLitCube(backend: backend, size: 1.1)
        let tintedBaseColor: (Float, Float, Float, Float) = (0.6, 0.45, 0.9, 1.0)
        let pixels: [UInt8] = [
            255,   0,   0, 255,
              0, 255,   0, 255,
              0,   0, 255, 255,
            255, 255, 255, 255
        ]
        let textureDescriptor = TextureDescriptor(width: 2,
                                                  height: 2,
                                                  mipLevels: 1,
                                                  format: .rgba8Unorm,
                                                  usage: .shaderRead)
        let textureData = TextureInitialData(mipLevelData: [Data(pixels)])
        let textureHandle = try backend.createTexture(descriptor: textureDescriptor, initialData: textureData)
        let material = Material(shader: ShaderID("basic_lit"),
                                params: .init(lightDirection: (0.3, -0.5, 0.8),
                                              baseColor: tintedBaseColor,
                                              texture: textureHandle))
        let node = SceneNode(name: "HarnessCube",
                             transform: .identity,
                             mesh: mesh,
                             material: material)
        let root = SceneNode(name: "Root")
        root.addChild(node)
        let aspect = Float(options.width) / Float(max(1, options.height))
        let camera = Camera(view: float4x4.lookAt(eye: (0, 0, 2.2),
                                                  center: (0, 0, 0),
                                                  up: (0, 1, 0)),
                            projection: float4x4.perspective(fovYRadians: .pi / 3,
                                                             aspect: aspect,
                                                             zNear: 0.1,
                                                             zFar: 100.0))
        let scene = Scene(root: root, camera: camera, lightDirection: (0.3, -0.5, 0.8))

        capturable.requestCapture()
        try SceneGraphRenderer.updateAndRender(scene: scene,
                                               backend: backend,
                                               colorFormat: .bgra8Unorm,
                                               depthFormat: .depth32Float)
        let hash = try capturable.takeCaptureHash()
        let key = GoldenRefs.key(backend: backendKey,
                                 width: options.width,
                                 height: options.height,
                                 material: Test.basicLit.rawValue)
        try compareGolden(hash: hash, key: key, options: options)
        return Result(backend: backendKey, test: .basicLit, hash: hash, goldenKey: key)
    }

    private static func runComputeStorageTexture(window: SDLWindow,
                                                 backend: RenderBackend,
                                                 capturable: GoldenImageCapturable,
                                                 backendKey: String,
                                                 options: Options) throws -> Result {
        let computeDescriptor = ComputePipelineDescriptor(label: "harness_compute_storage",
                                                          shader: ShaderID("compute_storage_texture"))
        let computePipeline = try backend.makeComputePipeline(computeDescriptor)
        let storageDescriptor = TextureDescriptor(width: options.computeTextureSize.width,
                                                  height: options.computeTextureSize.height,
                                                  mipLevels: 1,
                                                  format: .rgba8Unorm,
                                                  usage: .shaderWrite)
        let storageTexture = try backend.createTexture(descriptor: storageDescriptor, initialData: nil)

        _ = try backend.createTexture(descriptor: TextureDescriptor(width: options.width,
                                                                    height: options.height,
                                                                    mipLevels: 1,
                                                                    format: .depth32Float,
                                                                    usage: .depthStencil),
                                      initialData: nil)

        let module = try ShaderLibrary.shared.module(for: ShaderID("unlit_triangle"))
        let pipeline = try backend.makePipeline(GraphicsPipelineDescriptor(label: "harness_compute_graphics",
                                                                           shader: ShaderID("basic_lit"),
                                                                           vertexLayout: module.vertexLayout,
                                                                           colorFormats: [.bgra8Unorm],
                                                                           depthFormat: .depth32Float))

        let vertices: [Float] = [
            -1, -1, 0, 1, 0, 0,
             0,  1, 0, 0, 1, 0,
             1, -1, 0, 0, 0, 1
        ]
        let vertexBuffer = try vertices.withUnsafeBytes { buffer in
            try backend.createBuffer(bytes: buffer.baseAddress,
                                     length: buffer.count,
                                     usage: .vertex)
        }
        let mesh = try backend.registerMesh(vertexBuffer: vertexBuffer,
                                             vertexCount: 3,
                                             indexBuffer: nil,
                                             indexCount: 0,
                                             indexFormat: .uint16)

        try backend.beginFrame()
        var frameEnded = false
        defer {
            if !frameEnded {
                try? backend.endFrame()
            }
        }

        var computeBindings = BindingSet()
        computeBindings.setTexture(storageTexture, at: 0)
        try backend.dispatchCompute(computePipeline,
                                     groupsX: max(1, options.computeTextureSize.width / 8),
                                     groupsY: max(1, options.computeTextureSize.height / 8),
                                     groupsZ: 1,
                                     bindings: computeBindings)

        capturable.requestCapture()

        var bindings = BindingSet()
        bindings.setTexture(storageTexture, at: 10)
        if module.pushConstantSize > 0 {
            bindings.materialConstants = BindingSet.MaterialConstants(data: Data(repeating: 0,
                                                                                 count: module.pushConstantSize))
        }

        try backend.draw(mesh: mesh,
                          pipeline: pipeline,
                          bindings: bindings,
                          transform: .identity)

        try backend.endFrame()
        frameEnded = true

        let hash = try capturable.takeCaptureHash()
        let key = GoldenRefs.key(backend: backendKey,
                                 width: options.width,
                                 height: options.height,
                                 material: Test.computeStorageTexture.rawValue)
        try compareGolden(hash: hash, key: key, options: options)
        return Result(backend: backendKey, test: .computeStorageTexture, hash: hash, goldenKey: key)
    }

    private static func compareGolden(hash: String,
                                      key: String,
                                      options: Options) throws {
        if let expected = GoldenRefs.getExpected(for: key), !expected.isEmpty {
            guard expected == hash else {
                throw HarnessError.goldenMismatch(expected: expected, actual: hash, key: key)
            }
        } else {
            options.logger?("Golden hash (missing baseline) hash=\(hash) key=\(key)")
            if options.allowGoldenWrite {
                GoldenRefs.setExpected(hash, for: key)
            }
        }
    }
}
