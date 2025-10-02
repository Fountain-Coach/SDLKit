import Foundation

public struct float4x4 {
    public typealias Column = (Float, Float, Float, Float)
    public var columns: (Column, Column, Column, Column)
    public init(_ c0: Column, _ c1: Column, _ c2: Column, _ c3: Column) {
        self.columns = (c0, c1, c2, c3)
    }

    public init() {
        self.init(
            (1, 0, 0, 0),
            (0, 1, 0, 0),
            (0, 0, 1, 0),
            (0, 0, 0, 1)
        )
    }

    public static var identity: float4x4 { float4x4() }
}

public struct ShaderID: Hashable, Codable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct BufferHandle: Hashable, Codable, Sendable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct TextureHandle: Hashable, Codable, Sendable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct SamplerHandle: Hashable, Codable, Sendable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct PipelineHandle: Hashable, Codable, Sendable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct ComputePipelineHandle: Hashable, Codable, Sendable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct MeshHandle: Hashable, Codable, Sendable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public enum BufferUsage {
    case vertex
    case index
    case uniform
    case storage
    case staging
}

public enum TextureFormat: String, Codable, Sendable {
    case rgba8Unorm
    case bgra8Unorm
    case depth32Float
}

public struct TextureDescriptor: Sendable {
    public var width: Int
    public var height: Int
    public var mipLevels: Int
    public var format: TextureFormat
    public var usage: TextureUsage
    public init(width: Int, height: Int, mipLevels: Int = 1, format: TextureFormat, usage: TextureUsage) {
        self.width = width
        self.height = height
        self.mipLevels = mipLevels
        self.format = format
        self.usage = usage
    }
}

public struct TextureInitialData: Sendable {
    public var mipLevelData: [Data]
    public init(mipLevelData: [Data] = []) { self.mipLevelData = mipLevelData }
}

public enum SamplerMinMagFilter: String, Codable, Sendable {
    case nearest
    case linear
}

public enum SamplerMipFilter: String, Codable, Sendable {
    case notMipmapped
    case nearest
    case linear
}

public enum SamplerAddressMode: String, Codable, Sendable {
    case clampToEdge
    case repeatTexture
    case mirrorRepeat
}

public struct SamplerDescriptor: Sendable {
    public var label: String?
    public var minFilter: SamplerMinMagFilter
    public var magFilter: SamplerMinMagFilter
    public var mipFilter: SamplerMipFilter
    public var addressModeU: SamplerAddressMode
    public var addressModeV: SamplerAddressMode
    public var addressModeW: SamplerAddressMode
    public var lodMinClamp: Float
    public var lodMaxClamp: Float
    public var maxAnisotropy: Int

    public init(label: String? = nil,
                minFilter: SamplerMinMagFilter = .linear,
                magFilter: SamplerMinMagFilter = .linear,
                mipFilter: SamplerMipFilter = .linear,
                addressModeU: SamplerAddressMode = .repeatTexture,
                addressModeV: SamplerAddressMode = .repeatTexture,
                addressModeW: SamplerAddressMode = .repeatTexture,
                lodMinClamp: Float = 0,
                lodMaxClamp: Float = Float.greatestFiniteMagnitude,
                maxAnisotropy: Int = 1) {
        self.label = label
        self.minFilter = minFilter
        self.magFilter = magFilter
        self.mipFilter = mipFilter
        self.addressModeU = addressModeU
        self.addressModeV = addressModeV
        self.addressModeW = addressModeW
        self.lodMinClamp = lodMinClamp
        self.lodMaxClamp = lodMaxClamp
        self.maxAnisotropy = max(1, maxAnisotropy)
    }
}

public struct VertexLayout: Equatable, Sendable {
    public struct Attribute: Equatable, Sendable {
        public var index: Int
        public var semantic: String
        public var format: VertexFormat
        public var offset: Int
        public init(index: Int, semantic: String, format: VertexFormat, offset: Int) {
            self.index = index
            self.semantic = semantic
            self.format = format
            self.offset = offset
        }
    }
    public var stride: Int
    public var attributes: [Attribute]
    public init(stride: Int, attributes: [Attribute]) {
        self.stride = stride
        self.attributes = attributes
    }
}

public enum VertexFormat: Equatable, Sendable {
    case float2
    case float3
    case float4
}

public enum IndexFormat: String, Codable, Sendable {
    case uint16
    case uint32
}

public enum ShaderStage: Sendable {
    case vertex
    case fragment
    case compute
}

public struct BindingSlot: Sendable {
    public let index: Int
    public let kind: Kind
    public init(index: Int, kind: Kind) {
        self.index = index
        self.kind = kind
    }

    public enum Kind: Sendable {
        case uniformBuffer
        case storageBuffer
        case sampledTexture
        case storageTexture
        case sampler
    }
}

public struct BindingSet {
    public struct MaterialConstants: Sendable {
        public private(set) var data: Data

        public init(data: Data) { self.data = data }

        public init(bytes: UnsafeRawPointer, length: Int) {
            if length > 0 {
                self.data = Data(bytes: bytes, count: length)
            } else {
                self.data = Data()
            }
        }

        public var byteCount: Int { data.count }

        public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
            try data.withUnsafeBytes(body)
        }
    }

    public enum Resource: Sendable {
        case buffer(BufferHandle)
        case texture(TextureHandle)
    }

    public private(set) var resources: [Int: Resource]
    public private(set) var samplers: [Int: SamplerHandle]
    public var materialConstants: MaterialConstants?
    public init(resources: [Int: Resource] = [:],
                samplers: [Int: SamplerHandle] = [:],
                materialConstants: MaterialConstants? = nil) {
        self.resources = resources
        self.samplers = samplers
        self.materialConstants = materialConstants
    }
    public mutating func setBuffer(_ handle: BufferHandle, at index: Int) {
        resources[index] = .buffer(handle)
    }
    public mutating func setTexture(_ handle: TextureHandle, at index: Int) {
        resources[index] = .texture(handle)
    }
    public mutating func setSampler(_ handle: SamplerHandle, at index: Int) {
        samplers[index] = handle
    }
    public mutating func removeResource(at index: Int) {
        resources.removeValue(forKey: index)
    }
    public mutating func removeSampler(at index: Int) {
        samplers.removeValue(forKey: index)
    }
    public func resource(at index: Int) -> Resource? { resources[index] }
    public func buffer(at index: Int) -> BufferHandle? {
        if case let .buffer(handle) = resources[index] { return handle }
        return nil
    }
    public func texture(at index: Int) -> TextureHandle? {
        if case let .texture(handle) = resources[index] { return handle }
        return nil
    }
    public func sampler(at index: Int) -> SamplerHandle? { samplers[index] }
}

public enum TextureUsage: Sendable {
    case shaderRead
    case shaderWrite
    case renderTarget
    case depthStencil
}

public struct GraphicsPipelineDescriptor {
    public var label: String?
    public var shader: ShaderID
    public var vertexLayout: VertexLayout
    public var colorFormats: [TextureFormat]
    public var depthFormat: TextureFormat?
    public var sampleCount: Int
    public init(label: String? = nil,
                shader: ShaderID,
                vertexLayout: VertexLayout,
                colorFormats: [TextureFormat],
                depthFormat: TextureFormat? = nil,
                sampleCount: Int = 1) {
        self.label = label
        self.shader = shader
        self.vertexLayout = vertexLayout
        self.colorFormats = colorFormats
        self.depthFormat = depthFormat
        self.sampleCount = sampleCount
    }
}

public struct ComputePipelineDescriptor {
    public var label: String?
    public var shader: ShaderID
    public init(label: String? = nil, shader: ShaderID) {
        self.label = label
        self.shader = shader
    }
}

public enum ResourceHandle: Hashable {
    case buffer(BufferHandle)
    case texture(TextureHandle)
    case sampler(SamplerHandle)
    case pipeline(PipelineHandle)
    case computePipeline(ComputePipelineHandle)
    case mesh(MeshHandle)
}

// Optional protocol: backends may support golden-image capture for tests.
// Call `requestCapture()` before ending a frame, then fetch the hash via `takeCaptureHash()`.
public protocol GoldenImageCapturable {
    func requestCapture()
    func takeCaptureHash() throws -> String
}

@MainActor
public struct RenderSurface {
    public let window: SDLWindow
    public let handles: SDLWindow.NativeHandles
    public init(window: SDLWindow) throws {
        self.window = window
        self.handles = try window.nativeHandles()
    }
    public var metalLayer: SDLKitMetalLayer? { handles.metalLayer }
    public var win32HWND: UnsafeMutableRawPointer? { handles.win32HWND }
    public func createVulkanSurface(instance: VkInstance) throws -> VkSurfaceKHR {
        try handles.createVulkanSurface(instance: instance)
    }
}

@MainActor
public protocol RenderBackend {
    init(window: SDLWindow) throws
    func beginFrame() throws
    func endFrame() throws
    func resize(width: Int, height: Int) throws
    func waitGPU() throws

    func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle
    func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle
    func createSampler(descriptor: SamplerDescriptor) throws -> SamplerHandle
    func destroy(_ handle: ResourceHandle)

    func registerMesh(vertexBuffer: BufferHandle,
                      vertexCount: Int,
                      indexBuffer: BufferHandle?,
                      indexCount: Int,
                      indexFormat: IndexFormat) throws -> MeshHandle

    func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle
    func draw(mesh: MeshHandle,
              pipeline: PipelineHandle,
              bindings: BindingSet,
              transform: float4x4) throws

    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle
    func dispatchCompute(_ pipeline: ComputePipelineHandle,
                         groupsX: Int, groupsY: Int, groupsZ: Int,
                         bindings: BindingSet) throws
}
