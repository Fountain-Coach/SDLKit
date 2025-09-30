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

public struct ShaderID: Hashable, Codable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct BufferHandle: Hashable, Codable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct TextureHandle: Hashable, Codable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct PipelineHandle: Hashable, Codable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct ComputePipelineHandle: Hashable, Codable {
    public let rawValue: UInt64
    public init() { self.init(rawValue: UInt64.random(in: UInt64.min...UInt64.max)) }
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct MeshHandle: Hashable, Codable {
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

public enum TextureFormat: String, Codable {
    case rgba8Unorm
    case bgra8Unorm
    case depth32Float
}

public struct TextureDescriptor {
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

public struct TextureInitialData {
    public var mipLevelData: [Data]
    public init(mipLevelData: [Data] = []) { self.mipLevelData = mipLevelData }
}

public struct VertexLayout {
    public struct Attribute {
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

public enum VertexFormat {
    case float2
    case float3
    case float4
}

public enum ShaderStage {
    case vertex
    case fragment
    case compute
}

public struct BindingSlot {
    public let index: Int
    public let kind: Kind
    public init(index: Int, kind: Kind) {
        self.index = index
        self.kind = kind
    }

    public enum Kind {
        case uniformBuffer
        case storageBuffer
        case sampledTexture
        case storageTexture
        case sampler
    }
}

public struct BindingSet {
    public var slots: [Int: Any]
    public init(slots: [Int: Any] = [:]) { self.slots = slots }
    public mutating func setValue(_ value: Any, for index: Int) { slots[index] = value }
    public func value<T>(for index: Int, as type: T.Type) -> T? { slots[index] as? T }
}

public enum TextureUsage {
    case shaderRead
    case shaderWrite
    case renderTarget
    case depthStencil
}

public struct GraphicsPipelineDescriptor {
    public var label: String?
    public var vertexShader: ShaderID
    public var fragmentShader: ShaderID?
    public var vertexLayout: VertexLayout
    public var colorFormats: [TextureFormat]
    public var depthFormat: TextureFormat?
    public var sampleCount: Int
    public init(label: String? = nil,
                vertexShader: ShaderID,
                fragmentShader: ShaderID?,
                vertexLayout: VertexLayout,
                colorFormats: [TextureFormat],
                depthFormat: TextureFormat? = nil,
                sampleCount: Int = 1) {
        self.label = label
        self.vertexShader = vertexShader
        self.fragmentShader = fragmentShader
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
    case pipeline(PipelineHandle)
    case computePipeline(ComputePipelineHandle)
    case mesh(MeshHandle)
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
    func destroy(_ handle: ResourceHandle)

    func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle
    func draw(mesh: MeshHandle,
              pipeline: PipelineHandle,
              bindings: BindingSet,
              pushConstants: UnsafeRawPointer?,
              transform: float4x4) throws

    func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle
    func dispatchCompute(_ pipeline: ComputePipelineHandle,
                         groupsX: Int, groupsY: Int, groupsZ: Int,
                         bindings: BindingSet,
                         pushConstants: UnsafeRawPointer?) throws
}
