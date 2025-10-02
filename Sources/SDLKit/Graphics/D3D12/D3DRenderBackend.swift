#if os(Windows) && canImport(WinSDK)
import Foundation
import WinSDK
import Direct3D12
import DXGI

@MainActor
public final class D3D12RenderBackend: RenderBackend, GoldenImageCapturable {
    private enum Constants {
        static let frameCount = 2
        static let preferredBackBufferFormat: DXGI_FORMAT = DXGI_FORMAT_B8G8R8A8_UNORM
        static let preferredDepthFormat: DXGI_FORMAT = DXGI_FORMAT_D32_FLOAT
    }

    private struct BufferResource {
        let resource: UnsafeMutablePointer<ID3D12Resource>
        let length: Int
        let usage: BufferUsage
        var state: D3D12_RESOURCE_STATES
    }

    private struct PipelineResource {
        let handle: PipelineHandle
        let descriptor: GraphicsPipelineDescriptor
        let module: ShaderModule
        let rootSignature: UnsafeMutablePointer<ID3D12RootSignature>
        let pipelineState: UnsafeMutablePointer<ID3D12PipelineState>
        let vertexStride: Int
        let fragmentTextureParameterIndices: [Int: Int]
        let samplerParameterIndices: [Int: Int]
    }

    private struct MeshResource {
        let vertexBuffer: BufferHandle
        let vertexCount: Int
        let indexBuffer: BufferHandle?
        let indexCount: Int
        let indexFormat: IndexFormat
    }

    private struct ComputePipelineResource {
        let handle: ComputePipelineHandle
        let descriptor: ComputePipelineDescriptor
        let module: ComputeShaderModule
        let rootSignature: UnsafeMutablePointer<ID3D12RootSignature>
        let pipelineState: UnsafeMutablePointer<ID3D12PipelineState>
        let uniformParameterIndices: [Int: Int]
        let storageParameterIndices: [Int: Int]
    }

    private struct TextureResource {
        let resource: UnsafeMutablePointer<ID3D12Resource>
        let descriptorIndex: UINT
        let cpuHandle: D3D12_CPU_DESCRIPTOR_HANDLE
        let gpuHandle: D3D12_GPU_DESCRIPTOR_HANDLE
        var state: D3D12_RESOURCE_STATES
    }

    private struct SamplerResource {
        let descriptor: SamplerDescriptor
        let descriptorIndex: UINT
        let cpuHandle: D3D12_CPU_DESCRIPTOR_HANDLE
        let gpuHandle: D3D12_GPU_DESCRIPTOR_HANDLE
    }

    private struct FrameResources {
        var renderTarget: UnsafeMutablePointer<ID3D12Resource>?
        var commandAllocator: UnsafeMutablePointer<ID3D12CommandAllocator>?
        var rtvHandle: D3D12_CPU_DESCRIPTOR_HANDLE
        init() {
            renderTarget = nil
            commandAllocator = nil
            rtvHandle = D3D12_CPU_DESCRIPTOR_HANDLE(ptr: 0)
        }
    }

    private let window: SDLWindow
    private let surface: RenderSurface
    private let hwnd: HWND

    private var factory: UnsafeMutablePointer<IDXGIFactory6>?
    private var device: UnsafeMutablePointer<ID3D12Device>?
    private var commandQueue: UnsafeMutablePointer<ID3D12CommandQueue>?
    private var swapChain: UnsafeMutablePointer<IDXGISwapChain3>?
    private var rtvHeap: UnsafeMutablePointer<ID3D12DescriptorHeap>?
    private var dsvHeap: UnsafeMutablePointer<ID3D12DescriptorHeap>?
    private var srvHeap: UnsafeMutablePointer<ID3D12DescriptorHeap>?
    private var depthStencil: UnsafeMutablePointer<ID3D12Resource>?
    private var commandList: UnsafeMutablePointer<ID3D12GraphicsCommandList>?
    private var fence: UnsafeMutablePointer<ID3D12Fence>?
    private var fenceEvent: HANDLE?

    private var frames: [FrameResources]
    private var fenceValues: [UInt64]

    private var frameIndex: UInt32 = 0
    private var viewport: D3D12_VIEWPORT
    private var scissorRect: RECT
    private var rtvDescriptorSize: UINT = 0
    private var currentWidth: Int
    private var currentHeight: Int
    private var transformBuffer: UnsafeMutablePointer<ID3D12Resource>?

    private var buffers: [BufferHandle: BufferResource] = [:]
    private var pipelines: [PipelineHandle: PipelineResource] = [:]
    private var computePipelines: [ComputePipelineHandle: ComputePipelineResource] = [:]
    private var meshes: [MeshHandle: MeshResource] = [:]
    private var textures: [TextureHandle: TextureResource] = [:]
    private var samplers: [SamplerHandle: SamplerResource] = [:]

    private var builtinPipeline: PipelineHandle?
    private var builtinVertexBuffer: BufferHandle?

    private var frameActive = false
    private var debugLayerEnabled = false
    private let shaderLibrary = ShaderLibrary.shared

    private var srvDescriptorSize: UINT = 0
    private var nextSrvDescriptorIndex: UINT = 0
    private var fallbackTextureHandle: TextureHandle?
    private let maxSrvDescriptors: UINT = 256
    private var samplerHeap: UnsafeMutablePointer<ID3D12DescriptorHeap>?
    private var samplerDescriptorSize: UINT = 0
    private var nextSamplerDescriptorIndex: UINT = 0
    private var freeSamplerDescriptorIndices: [UINT] = []
    private let maxSamplerDescriptors: UINT = 64

    // Capture state
    private var captureRequested: Bool = false
    private var lastCaptureHash: String?
    private var readbackBuffer: UnsafeMutablePointer<ID3D12Resource>?
    private var readbackBufferSize: UINT64 = 0

    public required init(window: SDLWindow) throws {
        self.window = window
        self.surface = try RenderSurface(window: window)

        guard let rawHWND = surface.win32HWND else {
            throw AgentError.internalError("SDL window does not expose a Win32 HWND")
        }
        guard let castHWND = HWND(bitPattern: UInt(bitPattern: rawHWND)) else {
            throw AgentError.internalError("Unable to convert HWND pointer")
        }
        self.hwnd = castHWND

        self.frames = Array(repeating: FrameResources(), count: Constants.frameCount)
        self.fenceValues = Array(repeating: 0, count: Constants.frameCount)
        self.currentWidth = max(1, window.config.width)
        self.currentHeight = max(1, window.config.height)
        self.viewport = D3D12_VIEWPORT(TopLeftX: 0, TopLeftY: 0, Width: Float(currentWidth), Height: Float(currentHeight), MinDepth: 0.0, MaxDepth: 1.0)
        self.scissorRect = RECT(left: 0, top: 0, right: LONG(currentWidth), bottom: LONG(currentHeight))

        try initializeD3D()
        try createBuiltinTriangleResources()
        SDLLogger.info("SDLKit.Graphics.D3D12", "Initialized D3D12 backend with size=\(currentWidth)x\(currentHeight)")
    }

    deinit {
        try? waitGPU()
        releaseResources()
    }

    // MARK: - RenderBackend

    public func beginFrame() throws {
        guard !frameActive else {
            throw AgentError.internalError("beginFrame called while a frame is active")
        }
        guard let commandList else {
            throw AgentError.internalError("D3D12 command list unavailable")
        }

        frameActive = true
        try waitForFrameCompletion(Int(frameIndex))

        guard let allocator = frames[Int(frameIndex)].commandAllocator else {
            throw AgentError.internalError("Missing command allocator for frame")
        }
        try checkHRESULT(allocator.pointee.lpVtbl.pointee.Reset(allocator), "ID3D12CommandAllocator.Reset")
        try checkHRESULT(commandList.pointee.lpVtbl.pointee.Reset(commandList, allocator, nil), "ID3D12GraphicsCommandList.Reset")

        var vp = viewport
        commandList.pointee.lpVtbl.pointee.RSSetViewports(commandList, 1, &vp)
        var rect = scissorRect
        commandList.pointee.lpVtbl.pointee.RSSetScissorRects(commandList, 1, &rect)

        var barrier = D3D12_RESOURCE_BARRIER()
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION
        barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE
        barrier.Transition = D3D12_RESOURCE_TRANSITION_BARRIER(
            pResource: frames[Int(frameIndex)].renderTarget,
            Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
            StateBefore: D3D12_RESOURCE_STATE_PRESENT,
            StateAfter: D3D12_RESOURCE_STATE_RENDER_TARGET
        )
        commandList.pointee.lpVtbl.pointee.ResourceBarrier(commandList, 1, &barrier)

        var rtvHandle = frames[Int(frameIndex)].rtvHandle
        if let dsvHeap {
            var dsvHandle = dsvHeap.pointee.lpVtbl.pointee.GetCPUDescriptorHandleForHeapStart(dsvHeap)
            commandList.pointee.lpVtbl.pointee.OMSetRenderTargets(commandList, 1, &rtvHandle, false, &dsvHandle)
            var clearColor: [Float] = [0.05, 0.05, 0.08, 1.0]
            clearColor.withUnsafeMutableBufferPointer { buffer in
                commandList.pointee.lpVtbl.pointee.ClearRenderTargetView(commandList, rtvHandle, buffer.baseAddress, 0, nil)
            }
            commandList.pointee.lpVtbl.pointee.ClearDepthStencilView(commandList, dsvHandle, D3D12_CLEAR_FLAG_DEPTH, 1.0, 0, 0, nil)
        } else {
            commandList.pointee.lpVtbl.pointee.OMSetRenderTargets(commandList, 1, &rtvHandle, false, nil)
            var clearColor: [Float] = [0.05, 0.05, 0.08, 1.0]
            clearColor.withUnsafeMutableBufferPointer { buffer in
                commandList.pointee.lpVtbl.pointee.ClearRenderTargetView(commandList, rtvHandle, buffer.baseAddress, 0, nil)
            }
        }
    }

    public func endFrame() throws {
        guard frameActive else {
            throw AgentError.internalError("endFrame called without beginFrame")
        }
        guard let commandList, let commandQueue, let swapChain, let fence else {
            throw AgentError.internalError("D3D12 command resources unavailable")
        }

        // Optional capture: transition to COPY_SOURCE, copy to readback buffer, then to PRESENT
        if captureRequested, let rt = frames[Int(frameIndex)].renderTarget {
            var desc = D3D12_RESOURCE_DESC()
            desc = rt.pointee.lpVtbl.pointee.GetDesc(rt)
            var footprint = D3D12_PLACED_SUBRESOURCE_FOOTPRINT()
            var numRows: UINT = 0
            var rowSize: UINT64 = 0
            var totalBytes: UINT64 = 0
            var subresourceDesc = desc
            withUnsafeMutablePointer(to: &footprint) { fptr in
                withUnsafeMutablePointer(to: &numRows) { nr in
                    withUnsafeMutablePointer(to: &rowSize) { rs in
                        withUnsafeMutablePointer(to: &totalBytes) { tb in
                            device?.pointee.lpVtbl.pointee.GetCopyableFootprints(device, &subresourceDesc, 0, 1, fptr, nr, rs, tb, &totalBytes)
                        }
                    }
                }
            }

            if readbackBuffer == nil || readbackBufferSize < totalBytes {
                if var rb = readbackBuffer { releaseCOM(&rb); readbackBuffer = nil }
                var heapProps = D3D12_HEAP_PROPERTIES(Type: D3D12_HEAP_TYPE_READBACK, CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN, MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN, CreationNodeMask: 0, VisibleNodeMask: 0)
                var bufferDesc = D3D12_RESOURCE_DESC.Buffer(totalBytes)
                var rb: UnsafeMutablePointer<ID3D12Resource>?
                try withUnsafeMutablePointer(to: &rb) { pointer in
                    try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                        try checkHRESULT(device!.pointee.lpVtbl.pointee.CreateCommittedResource(device, &heapProps, D3D12_HEAP_FLAG_NONE, &bufferDesc, D3D12_RESOURCE_STATE_COPY_DEST, nil, &IID_ID3D12Resource, raw), "CreateCommittedResource(readback)")
                    }
                }
                readbackBuffer = rb
                readbackBufferSize = totalBytes
            }

            // Transition RENDER_TARGET -> COPY_SOURCE
            var toCopy = D3D12_RESOURCE_BARRIER()
            toCopy.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION
            toCopy.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE
            toCopy.Transition = D3D12_RESOURCE_TRANSITION_BARRIER(pResource: rt, Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES, StateBefore: D3D12_RESOURCE_STATE_RENDER_TARGET, StateAfter: D3D12_RESOURCE_STATE_COPY_SOURCE)
            commandList.pointee.lpVtbl.pointee.ResourceBarrier(commandList, 1, &toCopy)

            // Copy texture to readback buffer
            var src = D3D12_TEXTURE_COPY_LOCATION(pResource: rt, Type: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX, Anonymous: D3D12_TEXTURE_COPY_LOCATION._Anonymous(subresourceIndex: 0))
            var dst = D3D12_TEXTURE_COPY_LOCATION(pResource: readbackBuffer, Type: D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT, Anonymous: D3D12_TEXTURE_COPY_LOCATION._Anonymous(placedFootprint: footprint))
            var box: D3D12_BOX? = nil
            commandList.pointee.lpVtbl.pointee.CopyTextureRegion(commandList, &dst, 0, 0, 0, &src, &box)

            // Transition COPY_SOURCE -> PRESENT
            var toPresent = D3D12_RESOURCE_BARRIER()
            toPresent.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION
            toPresent.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE
            toPresent.Transition = D3D12_RESOURCE_TRANSITION_BARRIER(pResource: rt, Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES, StateBefore: D3D12_RESOURCE_STATE_COPY_SOURCE, StateAfter: D3D12_RESOURCE_STATE_PRESENT)
            commandList.pointee.lpVtbl.pointee.ResourceBarrier(commandList, 1, &toPresent)
        } else {
            var barrier = D3D12_RESOURCE_BARRIER()
            barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION
            barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE
            barrier.Transition = D3D12_RESOURCE_TRANSITION_BARRIER(
                pResource: frames[Int(frameIndex)].renderTarget,
                Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                StateBefore: D3D12_RESOURCE_STATE_RENDER_TARGET,
                StateAfter: D3D12_RESOURCE_STATE_PRESENT
            )
            commandList.pointee.lpVtbl.pointee.ResourceBarrier(commandList, 1, &barrier)
        }

        try checkHRESULT(commandList.pointee.lpVtbl.pointee.Close(commandList), "ID3D12GraphicsCommandList.Close")

        var listPointer = UnsafeMutableRawPointer(commandList).assumingMemoryBound(to: ID3D12CommandList.self)
        commandQueue.pointee.lpVtbl.pointee.ExecuteCommandLists(commandQueue, 1, &listPointer)

        try checkHRESULT(swapChain.pointee.lpVtbl.pointee.Present(swapChain, 1, 0), "IDXGISwapChain3.Present")

        let currentFrame = Int(frameIndex)
        let fenceValue = fenceValues[currentFrame] + 1
        fenceValues[currentFrame] = fenceValue
        try checkHRESULT(commandQueue.pointee.lpVtbl.pointee.Signal(commandQueue, fence, fenceValue), "ID3D12CommandQueue.Signal")

        // If capture requested, wait for GPU and compute hash now
        if captureRequested {
            try checkHRESULT(commandQueue.pointee.lpVtbl.pointee.Signal(commandQueue, fence, fenceValues[Int(frameIndex)] + 1), "ID3D12CommandQueue.Signal(capture)")
            fenceValues[Int(frameIndex)] += 1
            try waitForFence(value: fenceValues[Int(frameIndex)])
            if let rb = readbackBuffer {
                var mapped: UnsafeMutableRawPointer?
                try checkHRESULT(rb.pointee.lpVtbl.pointee.Map(rb, 0, nil, &mapped), "ID3D12Resource.Map(readback)")
                if let mapped, let rt = frames[Int(frameIndex)].renderTarget {
                    var desc = rt.pointee.lpVtbl.pointee.GetDesc(rt)
                    var footprint = D3D12_PLACED_SUBRESOURCE_FOOTPRINT()
                    var numRows: UINT = 0
                    var rowSize: UINT64 = 0
                    var totalBytes: UINT64 = 0
                    device?.pointee.lpVtbl.pointee.GetCopyableFootprints(device, &desc, 0, 1, &footprint, &numRows, &rowSize, &totalBytes)
                    let width = Int(desc.Width)
                    let height = Int(desc.Height)
                    let rowPitch = Int(footprint.Footprint.RowPitch)
                    var data = Data(count: rowPitch * height)
                    data.withUnsafeMutableBytes { buf in
                        if let base = buf.baseAddress {
                            memcpy(base, mapped, rowPitch * height)
                        }
                    }
                    lastCaptureHash = D3D12RenderBackend.hashHexRowMajor(data: data, width: width, height: height, rowPitch: rowPitch, bpp: 4)
                }
                rb.pointee.lpVtbl.pointee.Unmap(rb, 0, nil)
            }
            captureRequested = false
        }

        frameIndex = swapChain.pointee.lpVtbl.pointee.GetCurrentBackBufferIndex(swapChain)
        try waitForFrameCompletion(Int(frameIndex))

        frameActive = false
    }

    public func resize(width: Int, height: Int) throws {
        guard let swapChain else {
            throw AgentError.internalError("Swap chain unavailable for resize")
        }
        let clampedWidth = max(1, width)
        let clampedHeight = max(1, height)
        currentWidth = clampedWidth
        currentHeight = clampedHeight
        viewport.Width = Float(clampedWidth)
        viewport.Height = Float(clampedHeight)
        scissorRect = RECT(left: 0, top: 0, right: LONG(clampedWidth), bottom: LONG(clampedHeight))

        try waitGPU()
        for index in 0..<Constants.frameCount {
            releaseCOM(&frames[index].renderTarget)
        }

        try checkHRESULT(
            swapChain.pointee.lpVtbl.pointee.ResizeBuffers(
                swapChain,
                UINT(Constants.frameCount),
                UINT(clampedWidth),
                UINT(clampedHeight),
                Constants.preferredBackBufferFormat,
                0
            ),
            "IDXGISwapChain3.ResizeBuffers"
        )

        frameIndex = swapChain.pointee.lpVtbl.pointee.GetCurrentBackBufferIndex(swapChain)
        try createRenderTargetViews()
        try createDepthStencil(width: clampedWidth, height: clampedHeight)
    }

    public func waitGPU() throws {
        guard let commandQueue, let fence else { return }
        let currentFrame = Int(frameIndex)
        let signalValue = fenceValues[currentFrame] + 1
        fenceValues[currentFrame] = signalValue
        try checkHRESULT(commandQueue.pointee.lpVtbl.pointee.Signal(commandQueue, fence, signalValue), "ID3D12CommandQueue.Signal")
        try waitForFence(value: signalValue)
    }

    public func createBuffer(bytes: UnsafeRawPointer?, length: Int, usage: BufferUsage) throws -> BufferHandle {
        guard length > 0 else {
            throw AgentError.invalidArgument("Buffer length must be positive")
        }
        guard let device else {
            throw AgentError.internalError("D3D12 device unavailable")
        }

        var heapProperties = D3D12_HEAP_PROPERTIES(
            Type: D3D12_HEAP_TYPE_UPLOAD,
            CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
            CreationNodeMask: 0,
            VisibleNodeMask: 0
        )
        var bufferDesc = D3D12_RESOURCE_DESC.Buffer(UINT64(length))

        var resource: UnsafeMutablePointer<ID3D12Resource>?
        try withUnsafeMutablePointer(to: &resource) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { rawPointer in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommittedResource(
                        device,
                        &heapProperties,
                        D3D12_HEAP_FLAG_NONE,
                        &bufferDesc,
                        D3D12_RESOURCE_STATE_GENERIC_READ,
                        nil,
                        &IID_ID3D12Resource,
                        rawPointer
                    ),
                    "ID3D12Device.CreateCommittedResource"
                )
            }
        }
        guard let resource else {
            throw AgentError.internalError("Failed to allocate D3D12 buffer")
        }

        if let bytes {
            var mappedMemory: UnsafeMutableRawPointer?
            try checkHRESULT(resource.pointee.lpVtbl.pointee.Map(resource, 0, nil, &mappedMemory), "ID3D12Resource.Map")
            if let mappedMemory {
                memcpy(mappedMemory, bytes, length)
            }
            resource.pointee.lpVtbl.pointee.Unmap(resource, 0, nil)
        }

        let handle = BufferHandle()
        buffers[handle] = BufferResource(resource: resource, length: length, usage: usage, state: D3D12_RESOURCE_STATE_GENERIC_READ)
        return handle
    }

    public func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle {
        guard descriptor.width > 0, descriptor.height > 0 else {
            throw AgentError.invalidArgument("Texture dimensions must be positive")
        }
        guard descriptor.mipLevels >= 1 else {
            throw AgentError.invalidArgument("Texture mipLevels must be >= 1")
        }
        guard descriptor.usage == .shaderRead else {
            throw AgentError.notImplemented("D3D12 backend currently supports shader-read textures only")
        }
        guard let device else {
            throw AgentError.internalError("D3D12 device unavailable")
        }
        try ensureSrvHeap()

        let format = try convertTextureFormat(descriptor.format)

        var textureDesc = D3D12_RESOURCE_DESC()
        textureDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D
        textureDesc.Alignment = 0
        textureDesc.Width = UINT64(descriptor.width)
        textureDesc.Height = UINT(descriptor.height)
        textureDesc.DepthOrArraySize = 1
        textureDesc.MipLevels = UINT16(descriptor.mipLevels)
        textureDesc.Format = format
        textureDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        textureDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN
        textureDesc.Flags = D3D12_RESOURCE_FLAG_NONE

        var heapProps = D3D12_HEAP_PROPERTIES(
            Type: D3D12_HEAP_TYPE_DEFAULT,
            CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
            CreationNodeMask: 0,
            VisibleNodeMask: 0
        )

        var resource: UnsafeMutablePointer<ID3D12Resource>?
        let initialState: D3D12_RESOURCE_STATES = initialData?.mipLevelData.isEmpty == false ? D3D12_RESOURCE_STATE_COPY_DEST : D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE
        try withUnsafeMutablePointer(to: &resource) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommittedResource(
                        device,
                        &heapProps,
                        D3D12_HEAP_FLAG_NONE,
                        &textureDesc,
                        initialState,
                        nil,
                        &IID_ID3D12Resource,
                        raw
                    ),
                    "ID3D12Device.CreateCommittedResource(texture)"
                )
            }
        }
        guard let resource else {
            throw AgentError.internalError("Failed to allocate D3D12 texture resource")
        }

        if initialState == D3D12_RESOURCE_STATE_COPY_DEST, let initialData, !initialData.mipLevelData.isEmpty {
            try uploadInitialTextureData(resource: resource, descriptor: descriptor, initialData: initialData)
        }

        let descriptorIndex = try allocateSrvDescriptorIndex()
        guard let srvHeap else {
            throw AgentError.internalError("D3D12 SRV descriptor heap unavailable")
        }
        var cpuHandle = srvHeap.pointee.lpVtbl.pointee.GetCPUDescriptorHandleForHeapStart(srvHeap)
        var gpuHandle = srvHeap.pointee.lpVtbl.pointee.GetGPUDescriptorHandleForHeapStart(srvHeap)
        cpuHandle.ptr += UINT64(descriptorIndex) * UINT64(srvDescriptorSize)
        gpuHandle.ptr += UINT64(descriptorIndex) * UINT64(srvDescriptorSize)

        var srvDesc = D3D12_SHADER_RESOURCE_VIEW_DESC()
        srvDesc.Format = format
        srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D
        srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING
        srvDesc.Anonymous.Texture2D = D3D12_TEX2D_SRV(
            MostDetailedMip: 0,
            MipLevels: UINT(descriptor.mipLevels),
            PlaneSlice: 0,
            ResourceMinLODClamp: 0
        )
        device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, &srvDesc, cpuHandle)

        let handle = TextureHandle()
        let textureResource = TextureResource(
            resource: resource,
            descriptorIndex: descriptorIndex,
            cpuHandle: cpuHandle,
            gpuHandle: gpuHandle,
            state: D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE
        )
        textures[handle] = textureResource
        return handle
    }

    public func createSampler(descriptor: SamplerDescriptor) throws -> SamplerHandle {
        guard let device else {
            throw AgentError.internalError("D3D12 device unavailable for sampler creation")
        }
        try ensureSamplerHeap()
        guard let samplerHeap else {
            throw AgentError.internalError("D3D12 sampler descriptor heap unavailable")
        }

        let descriptorIndex = try allocateSamplerDescriptorIndex()
        var cpuHandle = samplerHeap.pointee.lpVtbl.pointee.GetCPUDescriptorHandleForHeapStart(samplerHeap)
        var gpuHandle = samplerHeap.pointee.lpVtbl.pointee.GetGPUDescriptorHandleForHeapStart(samplerHeap)
        cpuHandle.ptr += UINT64(descriptorIndex) * UINT64(samplerDescriptorSize)
        gpuHandle.ptr += UINT64(descriptorIndex) * UINT64(samplerDescriptorSize)

        var samplerDesc = D3D12_SAMPLER_DESC()
        samplerDesc.Filter = convertSamplerFilter(descriptor: descriptor)
        samplerDesc.AddressU = convertSamplerAddressMode(descriptor.addressModeU)
        samplerDesc.AddressV = convertSamplerAddressMode(descriptor.addressModeV)
        samplerDesc.AddressW = convertSamplerAddressMode(descriptor.addressModeW)
        samplerDesc.MipLODBias = 0
        samplerDesc.MaxAnisotropy = UINT(max(1, descriptor.maxAnisotropy))
        samplerDesc.ComparisonFunc = D3D12_COMPARISON_FUNC_NEVER
        samplerDesc.BorderColor = D3D12_STATIC_BORDER_COLOR_TRANSPARENT_BLACK
        samplerDesc.MinLOD = descriptor.lodMinClamp
        samplerDesc.MaxLOD = descriptor.mipFilter == .notMipmapped ? descriptor.lodMinClamp : descriptor.lodMaxClamp

        device.pointee.lpVtbl.pointee.CreateSampler(device, &samplerDesc, cpuHandle)

        let handle = SamplerHandle()
        samplers[handle] = SamplerResource(
            descriptor: descriptor,
            descriptorIndex: descriptorIndex,
            cpuHandle: cpuHandle,
            gpuHandle: gpuHandle
        )
        SDLLogger.debug("SDLKit.Graphics.D3D12", "createSampler id=\(handle.rawValue) label=\(descriptor.label ?? "<nil>")")
        return handle
    }

    private func ensureSrvHeap() throws {
        if srvHeap != nil { return }
        guard let device else {
            throw AgentError.internalError("D3D12 device unavailable for SRV heap creation")
        }
        var desc = D3D12_DESCRIPTOR_HEAP_DESC(
            Type: D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
            NumDescriptors: maxSrvDescriptors,
            Flags: D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
            NodeMask: 0
        )
        try withDescriptorHeap(desc: &desc) { heap in
            srvHeap = heap
        }
        srvDescriptorSize = device.pointee.lpVtbl.pointee.GetDescriptorHandleIncrementSize(device, D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV)
        nextSrvDescriptorIndex = 0
    }

    private func allocateSrvDescriptorIndex() throws -> UINT {
        try ensureSrvHeap()
        let index = nextSrvDescriptorIndex
        if index >= maxSrvDescriptors {
            throw AgentError.internalError("Exceeded D3D12 SRV descriptor heap capacity")
        }
        nextSrvDescriptorIndex += 1
        return index
    }

    private func uploadInitialTextureData(resource: UnsafeMutablePointer<ID3D12Resource>,
                                          descriptor: TextureDescriptor,
                                          initialData: TextureInitialData) throws {
        guard let device else {
            throw AgentError.internalError("D3D12 device unavailable for texture upload")
        }

        var desc = resource.pointee.lpVtbl.pointee.GetDesc(resource)
        let mipCount = Int(desc.MipLevels)
        var layouts = Array(repeating: D3D12_PLACED_SUBRESOURCE_FOOTPRINT(), count: mipCount)
        var numRows = Array(repeating: UINT(0), count: mipCount)
        var rowSizes = Array(repeating: UINT64(0), count: mipCount)
        var totalBytes: UINT64 = 0
        device.pointee.lpVtbl.pointee.GetCopyableFootprints(device, &desc, 0, UINT(mipCount), &layouts, &numRows, &rowSizes, &totalBytes)

        var uploadResource: UnsafeMutablePointer<ID3D12Resource>?
        var uploadHeapProps = D3D12_HEAP_PROPERTIES(
            Type: D3D12_HEAP_TYPE_UPLOAD,
            CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
            CreationNodeMask: 0,
            VisibleNodeMask: 0
        )
        var bufferDesc = D3D12_RESOURCE_DESC.Buffer(totalBytes)
        try withUnsafeMutablePointer(to: &uploadResource) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommittedResource(
                        device,
                        &uploadHeapProps,
                        D3D12_HEAP_FLAG_NONE,
                        &bufferDesc,
                        D3D12_RESOURCE_STATE_GENERIC_READ,
                        nil,
                        &IID_ID3D12Resource,
                        raw
                    ),
                    "ID3D12Device.CreateCommittedResource(upload)"
                )
            }
        }
        guard let uploadResource else {
            throw AgentError.internalError("Failed to allocate upload buffer for texture data")
        }
        defer { var temp: UnsafeMutablePointer<ID3D12Resource>? = uploadResource; releaseCOM(&temp) }

        var mapped: UnsafeMutableRawPointer?
        try checkHRESULT(uploadResource.pointee.lpVtbl.pointee.Map(uploadResource, 0, nil, &mapped), "ID3D12Resource.Map(upload)")
        defer { uploadResource.pointee.lpVtbl.pointee.Unmap(uploadResource, 0, nil) }

        let bytesPerPixel = try bytesPerPixel(for: descriptor.format)
        if let mapped {
            for level in 0..<mipCount {
                let mipWidth = max(1, descriptor.width >> level)
                let mipHeight = max(1, descriptor.height >> level)
                let expectedRowBytes = mipWidth * bytesPerPixel
                let rowPitch = Int(layouts[level].Footprint.RowPitch)
                let rows = max(1, Int(numRows[level]))
                let destBase = mapped.advanced(by: Int(layouts[level].Offset))
                let levelData = level < initialData.mipLevelData.count ? initialData.mipLevelData[level] : Data(count: expectedRowBytes * rows)
                if levelData.count < expectedRowBytes * rows {
                    throw AgentError.invalidArgument("Initial texture data for mip \(level) is too small")
                }
                levelData.withUnsafeBytes { buffer in
                    guard let srcBase = buffer.baseAddress else { return }
                    for row in 0..<rows {
                        let dstRow = destBase.advanced(by: rowPitch * row)
                        memset(dstRow, 0, rowPitch)
                        memcpy(dstRow, srcBase.advanced(by: expectedRowBytes * row), expectedRowBytes)
                    }
                }
            }
        }

        try performImmediateCommand { commandList in
            for level in 0..<mipCount {
                var dst = D3D12_TEXTURE_COPY_LOCATION(
                    pResource: resource,
                    Type: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
                    Anonymous: D3D12_TEXTURE_COPY_LOCATION._Anonymous(subresourceIndex: UINT(level))
                )
                var src = D3D12_TEXTURE_COPY_LOCATION(
                    pResource: uploadResource,
                    Type: D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT,
                    Anonymous: D3D12_TEXTURE_COPY_LOCATION._Anonymous(placedFootprint: layouts[level])
                )
                var box: D3D12_BOX? = nil
                commandList.pointee.lpVtbl.pointee.CopyTextureRegion(commandList, &dst, 0, 0, 0, &src, &box)
            }

            var barrier = D3D12_RESOURCE_BARRIER()
            barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION
            barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE
            barrier.Transition = D3D12_RESOURCE_TRANSITION_BARRIER(
                pResource: resource,
                Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                StateBefore: D3D12_RESOURCE_STATE_COPY_DEST,
                StateAfter: D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE
            )
            commandList.pointee.lpVtbl.pointee.ResourceBarrier(commandList, 1, &barrier)
        }
    }

    private func bytesPerPixel(for format: TextureFormat) throws -> Int {
        switch format {
        case .rgba8Unorm, .bgra8Unorm:
            return 4
        case .depth32Float:
            return 4
        }
    }

    private func convertTextureFormat(_ format: TextureFormat) throws -> DXGI_FORMAT {
        switch format {
        case .rgba8Unorm:
            return DXGI_FORMAT_R8G8B8A8_UNORM
        case .bgra8Unorm:
            return DXGI_FORMAT_B8G8R8A8_UNORM
        case .depth32Float:
            return DXGI_FORMAT_R32_FLOAT
        }
    }

    private func convertSamplerFilter(descriptor: SamplerDescriptor) -> D3D12_FILTER {
        if descriptor.maxAnisotropy > 1 {
            return D3D12_FILTER_ANISOTROPIC
        }
        let minLinear = descriptor.minFilter == .linear
        let magLinear = descriptor.magFilter == .linear
        let mipMode: SamplerMipFilter = descriptor.mipFilter == .notMipmapped ? .nearest : descriptor.mipFilter
        switch (minLinear, magLinear, mipMode) {
        case (false, false, .nearest):
            return D3D12_FILTER_MIN_MAG_MIP_POINT
        case (false, false, .linear):
            return D3D12_FILTER_MIN_MAG_POINT_MIP_LINEAR
        case (false, true, .nearest):
            return D3D12_FILTER_MIN_POINT_MAG_LINEAR_MIP_POINT
        case (false, true, .linear):
            return D3D12_FILTER_MIN_POINT_MAG_LINEAR_MIP_LINEAR
        case (true, false, .nearest):
            return D3D12_FILTER_MIN_LINEAR_MAG_POINT_MIP_POINT
        case (true, false, .linear):
            return D3D12_FILTER_MIN_LINEAR_MAG_POINT_MIP_LINEAR
        case (true, true, .nearest):
            return D3D12_FILTER_MIN_MAG_LINEAR_MIP_POINT
        case (true, true, .linear):
            return D3D12_FILTER_MIN_MAG_MIP_LINEAR
        }
    }

    private func convertSamplerAddressMode(_ mode: SamplerAddressMode) -> D3D12_TEXTURE_ADDRESS_MODE {
        switch mode {
        case .clampToEdge:
            return D3D12_TEXTURE_ADDRESS_MODE_CLAMP
        case .repeatTexture:
            return D3D12_TEXTURE_ADDRESS_MODE_WRAP
        case .mirrorRepeat:
            return D3D12_TEXTURE_ADDRESS_MODE_MIRROR
        }
    }

    private func performImmediateCommand(_ encode: (UnsafeMutablePointer<ID3D12GraphicsCommandList>) throws -> Void) throws {
        guard let device, let commandQueue else {
            throw AgentError.internalError("D3D12 device or command queue unavailable for immediate work")
        }
        var allocator: UnsafeMutablePointer<ID3D12CommandAllocator>?
        try withUnsafeMutablePointer(to: &allocator) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommandAllocator(
                        device,
                        D3D12_COMMAND_LIST_TYPE_DIRECT,
                        &IID_ID3D12CommandAllocator,
                        raw
                    ),
                    "ID3D12Device.CreateCommandAllocator(immediate)"
                )
            }
        }
        guard let allocator else {
            throw AgentError.internalError("Failed to create command allocator for immediate work")
        }
        defer { var temp: UnsafeMutablePointer<ID3D12CommandAllocator>? = allocator; releaseCOM(&temp) }

        var list: UnsafeMutablePointer<ID3D12GraphicsCommandList>?
        try withUnsafeMutablePointer(to: &list) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommandList(
                        device,
                        0,
                        D3D12_COMMAND_LIST_TYPE_DIRECT,
                        allocator,
                        nil,
                        &IID_ID3D12GraphicsCommandList,
                        raw
                    ),
                    "ID3D12Device.CreateCommandList(immediate)"
                )
            }
        }
        guard let list else {
            throw AgentError.internalError("Failed to create command list for immediate work")
        }
        do {
            try encode(list)
        } catch {
            list.pointee.lpVtbl.pointee.Close(list)
            var temp: UnsafeMutablePointer<ID3D12GraphicsCommandList>? = list
            releaseCOM(&temp)
            throw error
        }
        try checkHRESULT(list.pointee.lpVtbl.pointee.Close(list), "ID3D12GraphicsCommandList.Close(immediate)")

        var cmdListPointer = UnsafeMutableRawPointer(list).assumingMemoryBound(to: ID3D12CommandList.self)
        commandQueue.pointee.lpVtbl.pointee.ExecuteCommandLists(commandQueue, 1, &cmdListPointer)

        guard let fence else {
            var temp: UnsafeMutablePointer<ID3D12GraphicsCommandList>? = list
            releaseCOM(&temp)
            throw AgentError.internalError("D3D12 fence unavailable for immediate work")
        }
        let currentFrame = Int(frameIndex)
        let fenceValue = fenceValues[currentFrame] + 1
        fenceValues[currentFrame] = fenceValue
        try checkHRESULT(commandQueue.pointee.lpVtbl.pointee.Signal(commandQueue, fence, fenceValue), "ID3D12CommandQueue.Signal(immediate)")
        try waitForFence(value: fenceValue)

        var tempList: UnsafeMutablePointer<ID3D12GraphicsCommandList>? = list
        releaseCOM(&tempList)
    }

    private func ensureFallbackTextureHandle() throws -> TextureHandle {
        if let handle = fallbackTextureHandle, textures[handle] != nil {
            return handle
        }
        let pixel: [UInt8] = [255, 255, 255, 255]
        let data = Data(pixel)
        let descriptor = TextureDescriptor(width: 1, height: 1, mipLevels: 1, format: .rgba8Unorm, usage: .shaderRead)
        let handle = try createTexture(descriptor: descriptor, initialData: TextureInitialData(mipLevelData: [data]))
        fallbackTextureHandle = handle
        return handle
    }

    private func ensureSamplerHeap() throws {
        if samplerHeap != nil { return }
        guard let device else {
            throw AgentError.internalError("D3D12 device unavailable for sampler heap creation")
        }
        var desc = D3D12_DESCRIPTOR_HEAP_DESC(
            Type: D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER,
            NumDescriptors: maxSamplerDescriptors,
            Flags: D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
            NodeMask: 0
        )
        try withDescriptorHeap(desc: &desc) { heap in
            samplerHeap = heap
        }
        samplerDescriptorSize = device.pointee.lpVtbl.pointee.GetDescriptorHandleIncrementSize(device, D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER)
        nextSamplerDescriptorIndex = 0
        freeSamplerDescriptorIndices.removeAll(keepingCapacity: true)
    }

    private func allocateSamplerDescriptorIndex() throws -> UINT {
        if let reused = freeSamplerDescriptorIndices.popLast() {
            return reused
        }
        let index = nextSamplerDescriptorIndex
        if index >= maxSamplerDescriptors {
            throw AgentError.internalError("Exceeded D3D12 sampler descriptor heap capacity")
        }
        nextSamplerDescriptorIndex += 1
        return index
    }

    private func transitionBuffer(_ handle: BufferHandle, to newState: D3D12_RESOURCE_STATES) {
        guard let commandList else { return }
        guard var resource = buffers[handle] else { return }
        if resource.state == newState { return }
        var barrier = D3D12_RESOURCE_BARRIER()
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION
        barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE
        barrier.Anonymous.Transition = D3D12_RESOURCE_TRANSITION_BARRIER(
            pResource: resource.resource,
            Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
            StateBefore: resource.state,
            StateAfter: newState
        )
        commandList.pointee.lpVtbl.pointee.ResourceBarrier(commandList, 1, &barrier)
        resource.state = newState
        buffers[handle] = resource
    }

    private func insertUAVBarrier(_ handle: BufferHandle) {
        guard let commandList else { return }
        guard let resource = buffers[handle] else { return }
        var barrier = D3D12_RESOURCE_BARRIER()
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_UAV
        barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE
        barrier.Anonymous.UAV = D3D12_RESOURCE_UAV_BARRIER(pResource: resource.resource)
        commandList.pointee.lpVtbl.pointee.ResourceBarrier(commandList, 1, &barrier)
    }

    public func registerMesh(vertexBuffer: BufferHandle,
                             vertexCount: Int,
                             indexBuffer: BufferHandle?,
                             indexCount: Int,
                             indexFormat: IndexFormat) throws -> MeshHandle {
        guard buffers[vertexBuffer] != nil else {
            throw AgentError.internalError("Vertex buffer not found during mesh registration")
        }
        if let indexBuffer {
            guard buffers[indexBuffer] != nil else {
                throw AgentError.internalError("Index buffer not found during mesh registration")
            }
        }

        if let existing = meshes.first(where: { (_, resource) in
            resource.vertexBuffer == vertexBuffer &&
            resource.vertexCount == vertexCount &&
            resource.indexBuffer == indexBuffer &&
            resource.indexCount == indexCount &&
            resource.indexFormat == indexFormat
        })?.key {
            return existing
        }

        let handle = MeshHandle()
        meshes[handle] = MeshResource(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexFormat: indexFormat
        )
        return handle
    }

    public func destroy(_ handle: ResourceHandle) {
        switch handle {
        case .buffer(let buffer):
            if var resource = buffers.removeValue(forKey: buffer)?.resource {
                releaseCOM(&resource)
            }
        case .texture(let textureHandle):
            if var texture = textures.removeValue(forKey: textureHandle)?.resource {
                releaseCOM(&texture)
            }
            if fallbackTextureHandle == textureHandle {
                fallbackTextureHandle = nil
            }
        case .sampler(let samplerHandle):
            if let resource = samplers.removeValue(forKey: samplerHandle) {
                freeSamplerDescriptorIndices.append(resource.descriptorIndex)
            }
        case .pipeline(let pipelineHandle):
            if let resource = pipelines.removeValue(forKey: pipelineHandle) {
                var state: UnsafeMutablePointer<ID3D12PipelineState>? = resource.pipelineState
                var signature: UnsafeMutablePointer<ID3D12RootSignature>? = resource.rootSignature
                releaseCOM(&state)
                releaseCOM(&signature)
            }
        case .computePipeline(let handle):
            if let resource = computePipelines.removeValue(forKey: handle) {
                var state: UnsafeMutablePointer<ID3D12PipelineState>? = resource.pipelineState
                var signature: UnsafeMutablePointer<ID3D12RootSignature>? = resource.rootSignature
                releaseCOM(&state)
                releaseCOM(&signature)
            }
        case .mesh(let meshHandle):
            meshes.removeValue(forKey: meshHandle)
        }
    }

    public func makePipeline(_ desc: GraphicsPipelineDescriptor) throws -> PipelineHandle {
        if let existing = pipelines.values.first(where: { $0.descriptor.shader == desc.shader }) {
            return existing.handle
        }
        guard let device else {
            throw AgentError.internalError("D3D12 device unavailable")
        }

        let module = try shaderLibrary.module(for: desc.shader)
        try module.validateVertexLayout(desc.vertexLayout)

        let vertexShaderURL = try module.artifacts.requireDXILVertex(for: module.id)
        let vertexShader = try Data(contentsOf: vertexShaderURL)
        let pixelShaderURL = try module.artifacts.dxilFragmentURL(for: module.id)
        let pixelShader: Data?
        if let url = pixelShaderURL {
            pixelShader = try Data(contentsOf: url)
        } else {
            pixelShader = nil
        }

        // Root signature: CBV at b0 for transform plus descriptor tables for sampled textures.
        var rootParameters: [D3D12_ROOT_PARAMETER] = []
        var descriptorRanges: [[D3D12_DESCRIPTOR_RANGE]] = []
        var descriptorParameterIndices: [Int] = []
        var textureParameterIndices: [Int: Int] = [:]
        var samplerParameterIndices: [Int: Int] = [:]

        var cbv = D3D12_ROOT_PARAMETER()
        cbv.ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV
        cbv.ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL
        cbv.Anonymous.Descriptor = D3D12_ROOT_DESCRIPTOR(ShaderRegister: 0, RegisterSpace: 0)
        rootParameters.append(cbv)

        for (stage, slots) in module.bindings {
            let visibility: D3D12_SHADER_VISIBILITY
            switch stage {
            case .vertex:
                visibility = D3D12_SHADER_VISIBILITY_VERTEX
            case .fragment:
                visibility = D3D12_SHADER_VISIBILITY_PIXEL
            default:
                continue
            }
            for binding in slots.sorted(by: { $0.index < $1.index }) {
                switch binding.kind {
                case .sampledTexture:
                    var range = D3D12_DESCRIPTOR_RANGE(
                        RangeType: D3D12_DESCRIPTOR_RANGE_TYPE_SRV,
                        NumDescriptors: 1,
                        BaseShaderRegister: UINT(binding.index),
                        RegisterSpace: 0,
                        OffsetInDescriptorsFromTableStart: 0
                    )
                    var parameter = D3D12_ROOT_PARAMETER()
                    parameter.ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE
                    parameter.ShaderVisibility = visibility
                    descriptorRanges.append([range])
                    rootParameters.append(parameter)
                    descriptorParameterIndices.append(rootParameters.count - 1)
                    textureParameterIndices[binding.index] = rootParameters.count - 1
                case .sampler:
                    var range = D3D12_DESCRIPTOR_RANGE(
                        RangeType: D3D12_DESCRIPTOR_RANGE_TYPE_SAMPLER,
                        NumDescriptors: 1,
                        BaseShaderRegister: UINT(binding.index),
                        RegisterSpace: 0,
                        OffsetInDescriptorsFromTableStart: 0
                    )
                    var parameter = D3D12_ROOT_PARAMETER()
                    parameter.ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE
                    parameter.ShaderVisibility = visibility
                    descriptorRanges.append([range])
                    rootParameters.append(parameter)
                    descriptorParameterIndices.append(rootParameters.count - 1)
                    samplerParameterIndices[binding.index] = rootParameters.count - 1
                default:
                    continue
                }
            }
        }

        var rootDesc = D3D12_ROOT_SIGNATURE_DESC()
        rootDesc.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT

        var serializedRoot: UnsafeMutablePointer<ID3DBlob>?
        var errorBlob: UnsafeMutablePointer<ID3DBlob>?
        var serializeResult: HRESULT = S_OK
        rootParameters.withUnsafeMutableBufferPointer { paramBuffer in
            rootDesc.NumParameters = UINT(paramBuffer.count)
            rootDesc.pParameters = paramBuffer.baseAddress
            for (tableIndex, parameterIndex) in descriptorParameterIndices.enumerated() {
                descriptorRanges[tableIndex].withUnsafeMutableBufferPointer { rangeBuffer in
                    paramBuffer[parameterIndex].Anonymous.DescriptorTable = D3D12_ROOT_DESCRIPTOR_TABLE(
                        NumDescriptorRanges: UINT(rangeBuffer.count),
                        pDescriptorRanges: rangeBuffer.baseAddress
                    )
                }
            }
            rootDesc.NumStaticSamplers = 0
            rootDesc.pStaticSamplers = nil
            serializeResult = withUnsafePointer(to: &rootDesc) { descPointer -> HRESULT in
                descPointer.withMemoryRebound(to: D3D12_ROOT_SIGNATURE_DESC.self, capacity: 1) { rebound in
                    D3D12SerializeRootSignature(rebound, D3D_ROOT_SIGNATURE_VERSION_1, &serializedRoot, &errorBlob)
                }
            }
        }
        if serializeResult < 0 {
            let message: String
            if let errorBlob, let pointer = errorBlob.pointee.lpVtbl.pointee.GetBufferPointer(errorBlob) {
                let length = errorBlob.pointee.lpVtbl.pointee.GetBufferSize(errorBlob)
                let data = Data(bytes: pointer, count: length)
                message = String(data: data, encoding: .utf8) ?? "Unknown"
            } else {
                message = String(format: "HRESULT=0x%08X", UInt32(bitPattern: serializeResult))
            }
            releaseCOM(&errorBlob)
            releaseCOM(&serializedRoot)
            throw AgentError.internalError("D3D12 root signature serialization failed: \(message)")
        }
        releaseCOM(&errorBlob)

        var rootSignature: UnsafeMutablePointer<ID3D12RootSignature>?
        if let serializedRoot {
            let pointer = serializedRoot.pointee.lpVtbl.pointee.GetBufferPointer(serializedRoot)
            let size = serializedRoot.pointee.lpVtbl.pointee.GetBufferSize(serializedRoot)
            try withUnsafeMutablePointer(to: &rootSignature) { ptr in
                try ptr.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                    try checkHRESULT(
                        device.pointee.lpVtbl.pointee.CreateRootSignature(
                            device,
                            0,
                            pointer,
                            size,
                            &IID_ID3D12RootSignature,
                            raw
                        ),
                        "ID3D12Device.CreateRootSignature"
                    )
                }
            }
        }
        releaseCOM(&serializedRoot)

        guard let rootSignature else {
            throw AgentError.internalError("Failed to create D3D12 root signature")
        }

        // Build input layout from module.vertexLayout
        let attributes = module.vertexLayout.attributes
        let semanticArrays = attributes.map { $0.semantic.utf8CString }
        let semanticPointers = semanticArrays.map { UnsafePointer($0) }
        func dxgiFormat(for fmt: VertexFormat) -> DXGI_FORMAT {
            switch fmt {
            case .float2: return DXGI_FORMAT_R32G32_FLOAT
            case .float3: return DXGI_FORMAT_R32G32B32_FLOAT
            case .float4: return DXGI_FORMAT_R32G32B32A32_FLOAT
            }
        }
        var inputElements: [D3D12_INPUT_ELEMENT_DESC] = []
        inputElements.reserveCapacity(attributes.count)
        for (i, attr) in attributes.enumerated() {
            inputElements.append(
                D3D12_INPUT_ELEMENT_DESC(
                    SemanticName: semanticPointers[i],
                    SemanticIndex: 0,
                    Format: dxgiFormat(for: attr.format),
                    InputSlot: 0,
                    AlignedByteOffset: UINT(attr.offset),
                    InputSlotClass: D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
                    InstanceDataStepRate: 0
                )
            )
        }

        var pipelineDesc = D3D12_GRAPHICS_PIPELINE_STATE_DESC()
        pipelineDesc.pRootSignature = rootSignature
        pipelineDesc.SampleMask = UINT.max
        pipelineDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE
        pipelineDesc.NumRenderTargets = 1
        pipelineDesc.RTVFormats = (Constants.preferredBackBufferFormat, DXGI_FORMAT_UNKNOWN, DXGI_FORMAT_UNKNOWN, DXGI_FORMAT_UNKNOWN, DXGI_FORMAT_UNKNOWN, DXGI_FORMAT_UNKNOWN, DXGI_FORMAT_UNKNOWN, DXGI_FORMAT_UNKNOWN)
        pipelineDesc.DSVFormat = Constants.preferredDepthFormat
        pipelineDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)

        var rasterizer = D3D12_RASTERIZER_DESC()
        rasterizer.FillMode = D3D12_FILL_MODE_SOLID
        rasterizer.CullMode = D3D12_CULL_MODE_BACK
        rasterizer.FrontCounterClockwise = false
        rasterizer.DepthClipEnable = true
        pipelineDesc.RasterizerState = rasterizer

        var blend = D3D12_BLEND_DESC()
        blend.AlphaToCoverageEnable = false
        blend.IndependentBlendEnable = false
        blend.RenderTarget = (D3D12_RENDER_TARGET_BLEND_DESC(
            BlendEnable: false,
            LogicOpEnable: false,
            SrcBlend: D3D12_BLEND_ONE,
            DestBlend: D3D12_BLEND_ZERO,
            BlendOp: D3D12_BLEND_OP_ADD,
            SrcBlendAlpha: D3D12_BLEND_ONE,
            DestBlendAlpha: D3D12_BLEND_ZERO,
            BlendOpAlpha: D3D12_BLEND_OP_ADD,
            LogicOp: D3D12_LOGIC_OP_NOOP,
            RenderTargetWriteMask: UINT8(D3D12_COLOR_WRITE_ENABLE_ALL.rawValue)
        ),
        D3D12_RENDER_TARGET_BLEND_DESC(),
        D3D12_RENDER_TARGET_BLEND_DESC(),
        D3D12_RENDER_TARGET_BLEND_DESC(),
        D3D12_RENDER_TARGET_BLEND_DESC(),
        D3D12_RENDER_TARGET_BLEND_DESC(),
        D3D12_RENDER_TARGET_BLEND_DESC(),
        D3D12_RENDER_TARGET_BLEND_DESC())
        pipelineDesc.BlendState = blend

        var depthStencil = D3D12_DEPTH_STENCIL_DESC()
        depthStencil.DepthEnable = true
        depthStencil.DepthWriteMask = D3D12_DEPTH_WRITE_MASK_ALL
        depthStencil.DepthFunc = D3D12_COMPARISON_FUNC_LESS
        depthStencil.StencilEnable = false
        pipelineDesc.DepthStencilState = depthStencil

        var pipelineState: UnsafeMutablePointer<ID3D12PipelineState>?
        try inputElements.withUnsafeMutableBufferPointer { buffer in
            pipelineDesc.InputLayout = D3D12_INPUT_LAYOUT_DESC(
                pInputElementDescs: buffer.baseAddress,
                NumElements: UINT(buffer.count)
            )
            try vertexShader.withUnsafeBytes { vsBytes in
                guard let vsPointer = vsBytes.baseAddress else {
                    throw AgentError.internalError("Vertex shader bytecode empty")
                }
                pipelineDesc.VS = D3D12_SHADER_BYTECODE(pShaderBytecode: vsPointer, BytecodeLength: vsBytes.count)
                if let pixelShader {
                    try pixelShader.withUnsafeBytes { psBytes in
                        if let psPointer = psBytes.baseAddress {
                            pipelineDesc.PS = D3D12_SHADER_BYTECODE(pShaderBytecode: psPointer, BytecodeLength: psBytes.count)
                        } else {
                            pipelineDesc.PS = D3D12_SHADER_BYTECODE()
                        }
                        try createPipelineState(desc: &pipelineDesc, into: &pipelineState)
                    }
                } else {
                    pipelineDesc.PS = D3D12_SHADER_BYTECODE()
                    try createPipelineState(desc: &pipelineDesc, into: &pipelineState)
                }
            }
        }

        guard let pipelineState else {
            var signature: UnsafeMutablePointer<ID3D12RootSignature>? = rootSignature
            releaseCOM(&signature)
            throw AgentError.internalError("Failed to create D3D12 pipeline state")
        }

        let handle = PipelineHandle()
        pipelines[handle] = PipelineResource(
            handle: handle,
            descriptor: desc,
            module: module,
            rootSignature: rootSignature,
            pipelineState: pipelineState,
            vertexStride: module.vertexLayout.stride,
            fragmentTextureParameterIndices: textureParameterIndices,
            samplerParameterIndices: samplerParameterIndices
        )
        if builtinPipeline == nil {
            builtinPipeline = handle
        }
        return handle
    }

    public func draw(mesh: MeshHandle, pipeline: PipelineHandle, bindings: BindingSet, transform: float4x4) throws {
        guard frameActive else {
            throw AgentError.internalError("draw called outside beginFrame/endFrame")
        }
        guard let commandList else {
            throw AgentError.internalError("Command list unavailable during draw")
        }
        guard let pipelineResource = pipelines[pipeline] else {
            throw AgentError.internalError("Unknown pipeline handle for draw")
        }

        _ = transform

        guard let meshResource = meshes[mesh] else {
            throw AgentError.internalError("Unknown mesh handle for draw")
        }
        guard let buffer = buffers[meshResource.vertexBuffer] else {
            throw AgentError.internalError("Vertex buffer missing for mesh draw call")
        }
        let stride = pipelineResource.vertexStride
        guard stride > 0 else {
            throw AgentError.internalError("Pipeline vertex stride is zero")
        }
        let vertexCount = (meshResource.vertexCount > 0 ? meshResource.vertexCount : buffer.length / stride)
        guard vertexCount > 0 else { return }

        commandList.pointee.lpVtbl.pointee.SetPipelineState(commandList, pipelineResource.pipelineState)
        commandList.pointee.lpVtbl.pointee.SetGraphicsRootSignature(commandList, pipelineResource.rootSignature)
        let needsTextures = !pipelineResource.fragmentTextureParameterIndices.isEmpty
        let needsSamplers = !pipelineResource.samplerParameterIndices.isEmpty
        if needsTextures {
            if srvHeap == nil {
                try ensureSrvHeap()
            }
        }
        if needsSamplers {
            if samplerHeap == nil {
                try ensureSamplerHeap()
            }
        }
        var descriptorHeaps: [UnsafeMutablePointer<ID3D12DescriptorHeap>?] = []
        if needsTextures, let srvHeap { descriptorHeaps.append(srvHeap) }
        if needsSamplers, let samplerHeap { descriptorHeaps.append(samplerHeap) }
        if !descriptorHeaps.isEmpty {
            descriptorHeaps.withUnsafeMutableBufferPointer { buffer in
                commandList.pointee.lpVtbl.pointee.SetDescriptorHeaps(commandList, UINT(buffer.count), buffer.baseAddress)
            }
        }
        if needsTextures {
            for (slot, parameterIndex) in pipelineResource.fragmentTextureParameterIndices.sorted(by: { $0.key < $1.key }) {
                let textureHandle: TextureHandle
                if let entry = bindings.resource(at: slot) {
                    switch entry {
                    case .texture(let handle):
                        textureHandle = handle
                    case .buffer:
                        throw AgentError.invalidArgument("Buffer bound to texture slot \(slot) for draw call")
                    }
                } else {
                    textureHandle = try ensureFallbackTextureHandle()
                }
                guard let texture = textures[textureHandle] else {
                    throw AgentError.invalidArgument("Missing texture binding for slot \(slot)")
                }
                commandList.pointee.lpVtbl.pointee.SetGraphicsRootDescriptorTable(commandList, UINT(parameterIndex), texture.gpuHandle)
            }
        }
        if needsSamplers {
            guard let samplerHeap else {
                throw AgentError.internalError("Sampler descriptor heap unavailable for bindings")
            }
            for (slot, parameterIndex) in pipelineResource.samplerParameterIndices.sorted(by: { $0.key < $1.key }) {
                guard let samplerHandle = bindings.sampler(at: slot) else {
                    throw AgentError.invalidArgument("Missing sampler binding for slot \(slot)")
                }
                guard let sampler = samplers[samplerHandle] else {
                    throw AgentError.invalidArgument("Unknown sampler handle for slot \(slot)")
                }
                commandList.pointee.lpVtbl.pointee.SetGraphicsRootDescriptorTable(commandList, UINT(parameterIndex), sampler.gpuHandle)
            }
        }
        let expectedPushConstantSize = pipelineResource.module.pushConstantSize
        if expectedPushConstantSize > 0 {
            guard let payload = bindings.materialConstants else {
                let message = "Shader \(pipelineResource.descriptor.shader.rawValue) expects \(expectedPushConstantSize) bytes of material constants but none were provided."
                SDLLogger.error("SDLKit.Graphics.D3D12", message)
                throw AgentError.invalidArgument(message)
            }
            let byteCount = payload.byteCount
            guard byteCount == expectedPushConstantSize else {
                let message = "Shader \(pipelineResource.descriptor.shader.rawValue) expects \(expectedPushConstantSize) bytes of material constants but received \(byteCount)."
                SDLLogger.error("SDLKit.Graphics.D3D12", message)
                throw AgentError.invalidArgument(message)
            }
            if transformBuffer == nil {
                try? createTransformBuffer()
            }
            guard let tbuf = transformBuffer else {
                throw AgentError.internalError("Transform buffer unavailable for push constant upload")
            }
            var mapped: UnsafeMutableRawPointer?
            _ = tbuf.pointee.lpVtbl.pointee.Map(tbuf, 0, nil, &mapped)
            if let mapped {
                payload.withUnsafeBytes { bytes in
                    if let base = bytes.baseAddress {
                        memcpy(mapped, base, min(bytes.count, expectedPushConstantSize))
                    }
                }
            }
            tbuf.pointee.lpVtbl.pointee.Unmap(tbuf, 0, nil)
            let gpuAddress = tbuf.pointee.lpVtbl.pointee.GetGPUVirtualAddress(tbuf)
            commandList.pointee.lpVtbl.pointee.SetGraphicsRootConstantBufferView(commandList, 0, gpuAddress)
        } else if let payload = bindings.materialConstants, payload.byteCount > 0 {
            SDLLogger.warn(
                "SDLKit.Graphics.D3D12",
                "Material constants of size \(payload.byteCount) bytes provided for shader \(pipelineResource.descriptor.shader.rawValue) which does not declare push constants. Data will be ignored."
            )
        }
        commandList.pointee.lpVtbl.pointee.IASetPrimitiveTopology(commandList, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST)

        transitionBuffer(meshResource.vertexBuffer, to: D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER)
        var view = D3D12_VERTEX_BUFFER_VIEW(
            BufferLocation: buffer.resource.pointee.lpVtbl.pointee.GetGPUVirtualAddress(buffer.resource),
            SizeInBytes: UINT(buffer.length),
            StrideInBytes: UINT(stride)
        )
        commandList.pointee.lpVtbl.pointee.IASetVertexBuffers(commandList, 0, 1, &view)
        if let indexHandle = meshResource.indexBuffer,
           meshResource.indexCount > 0,
           let indexBuffer = buffers[indexHandle] {
            transitionBuffer(indexHandle, to: D3D12_RESOURCE_STATE_INDEX_BUFFER)
            var ibView = D3D12_INDEX_BUFFER_VIEW(
                BufferLocation: indexBuffer.resource.pointee.lpVtbl.pointee.GetGPUVirtualAddress(indexBuffer.resource),
                SizeInBytes: UINT(indexBuffer.length),
                Format: convertIndexFormat(meshResource.indexFormat)
            )
            commandList.pointee.lpVtbl.pointee.IASetIndexBuffer(commandList, &ibView)
            commandList.pointee.lpVtbl.pointee.DrawIndexedInstanced(commandList, UINT(meshResource.indexCount), 1, 0, 0, 0)
        } else {
            commandList.pointee.lpVtbl.pointee.DrawInstanced(commandList, UINT(vertexCount), 1, 0, 0)
        }
    }

    public func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle {
        guard let device else {
            throw AgentError.internalError("D3D12 device unavailable")
        }
        let module = try shaderLibrary.computeModule(for: desc.shader)
        if let existing = computePipelines.values.first(where: { $0.descriptor.shader == desc.shader }) {
            return existing.handle
        }

        var rootParameters: [D3D12_ROOT_PARAMETER] = []
        var uniformIndices: [Int: Int] = [:]
        var storageIndices: [Int: Int] = [:]
        for slot in module.bindings {
            switch slot.kind {
            case .uniformBuffer:
                var param = D3D12_ROOT_PARAMETER()
                param.ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV
                param.ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL
                param.Anonymous.Descriptor = D3D12_ROOT_DESCRIPTOR(ShaderRegister: UINT(slot.index), RegisterSpace: 0)
                uniformIndices[slot.index] = rootParameters.count
                rootParameters.append(param)
            case .storageBuffer:
                var param = D3D12_ROOT_PARAMETER()
                param.ParameterType = D3D12_ROOT_PARAMETER_TYPE_UAV
                param.ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL
                param.Anonymous.Descriptor = D3D12_ROOT_DESCRIPTOR(ShaderRegister: UINT(slot.index), RegisterSpace: 0)
                storageIndices[slot.index] = rootParameters.count
                rootParameters.append(param)
            case .sampledTexture, .storageTexture, .sampler:
                throw AgentError.notImplemented("Texture and sampler bindings for D3D12 compute pipelines are not yet supported")
            }
        }

        var rootSignature: UnsafeMutablePointer<ID3D12RootSignature>?
        var rootDesc = D3D12_ROOT_SIGNATURE_DESC()
        var serializedRoot: UnsafeMutablePointer<ID3DBlob>?
        var errorBlob: UnsafeMutablePointer<ID3DBlob>?
        try rootParameters.withUnsafeMutableBufferPointer { paramsBuffer in
            rootDesc.NumParameters = UINT(paramsBuffer.count)
            rootDesc.pParameters = paramsBuffer.baseAddress
            rootDesc.NumStaticSamplers = 0
            rootDesc.pStaticSamplers = nil
            rootDesc.Flags = D3D12_ROOT_SIGNATURE_FLAG_NONE

            let serializeResult = withUnsafePointer(to: &rootDesc) { descPointer -> HRESULT in
                descPointer.withMemoryRebound(to: D3D12_ROOT_SIGNATURE_DESC.self, capacity: 1) { rebound in
                    D3D12SerializeRootSignature(rebound, D3D_ROOT_SIGNATURE_VERSION_1, &serializedRoot, &errorBlob)
                }
            }
            if serializeResult < 0 {
                let message: String
                if let errorBlob, let pointer = errorBlob.pointee.lpVtbl.pointee.GetBufferPointer(errorBlob) {
                    let length = errorBlob.pointee.lpVtbl.pointee.GetBufferSize(errorBlob)
                    let data = Data(bytes: pointer, count: length)
                    message = String(data: data, encoding: .utf8) ?? "Unknown"
                } else {
                    message = String(format: "HRESULT=0x%08X", UInt32(bitPattern: serializeResult))
                }
                releaseCOM(&errorBlob)
                releaseCOM(&serializedRoot)
                throw AgentError.internalError("D3D12 compute root signature serialization failed: \(message)")
            }
        }
        releaseCOM(&errorBlob)

        if let serializedRoot {
            let pointer = serializedRoot.pointee.lpVtbl.pointee.GetBufferPointer(serializedRoot)
            let size = serializedRoot.pointee.lpVtbl.pointee.GetBufferSize(serializedRoot)
            try withUnsafeMutablePointer(to: &rootSignature) { ptr in
                try ptr.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                    try checkHRESULT(
                        device.pointee.lpVtbl.pointee.CreateRootSignature(
                            device,
                            0,
                            pointer,
                            size,
                            &IID_ID3D12RootSignature,
                            raw
                        ),
                        "ID3D12Device.CreateRootSignature"
                    )
                }
            }
        }
        releaseCOM(&serializedRoot)

        guard let rootSignature else {
            throw AgentError.internalError("Failed to create D3D12 compute root signature")
        }

        let shaderURL = try module.artifacts.requireDXIL(for: module.id)
        let shaderData = try Data(contentsOf: shaderURL)
        var pipelineState: UnsafeMutablePointer<ID3D12PipelineState>?
        try shaderData.withUnsafeBytes { bytes in
            guard let pointer = bytes.baseAddress else {
                throw AgentError.internalError("DXIL compute shader buffer is empty")
            }
            var desc = D3D12_COMPUTE_PIPELINE_STATE_DESC()
            desc.pRootSignature = rootSignature
            desc.Flags = D3D12_PIPELINE_STATE_FLAG_NONE
            desc.CS = D3D12_SHADER_BYTECODE(pShaderBytecode: pointer, BytecodeLength: bytes.count)
            try withUnsafeMutablePointer(to: &pipelineState) { ptr in
                try ptr.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                    try checkHRESULT(
                        device.pointee.lpVtbl.pointee.CreateComputePipelineState(device, &desc, &IID_ID3D12PipelineState, raw),
                        "ID3D12Device.CreateComputePipelineState"
                    )
                }
            }
        }

        guard let pipelineState else {
            var signature: UnsafeMutablePointer<ID3D12RootSignature>? = rootSignature
            releaseCOM(&signature)
            throw AgentError.internalError("Failed to create D3D12 compute pipeline state")
        }

        let handle = ComputePipelineHandle()
        let resource = ComputePipelineResource(
            handle: handle,
            descriptor: desc,
            module: module,
            rootSignature: rootSignature,
            pipelineState: pipelineState,
            uniformParameterIndices: uniformIndices,
            storageParameterIndices: storageIndices
        )
        computePipelines[handle] = resource
        SDLLogger.debug("SDLKit.Graphics.D3D12", "makeComputePipeline id=\(handle.rawValue) shader=\(module.id.rawValue)")
        return handle
    }

    public func dispatchCompute(_ pipeline: ComputePipelineHandle, groupsX: Int, groupsY: Int, groupsZ: Int, bindings: BindingSet) throws {
        guard frameActive else {
            throw AgentError.internalError("dispatchCompute called outside of beginFrame/endFrame")
        }
        guard let commandList else {
            throw AgentError.internalError("D3D12 command list unavailable for compute dispatch")
        }
        guard let resource = computePipelines[pipeline] else {
            throw AgentError.internalError("Unknown compute pipeline handle")
        }

        commandList.pointee.lpVtbl.pointee.SetPipelineState(commandList, resource.pipelineState)
        commandList.pointee.lpVtbl.pointee.SetComputeRootSignature(commandList, resource.rootSignature)

        for (slot, parameterIndex) in resource.uniformParameterIndices {
            guard let entry = bindings.resource(at: slot) else {
                throw AgentError.invalidArgument("Missing uniform buffer binding at slot \(slot)")
            }
            let handle: BufferHandle
            switch entry {
            case .buffer(let bufferHandle):
                handle = bufferHandle
            case .texture:
                throw AgentError.invalidArgument("Texture bound to uniform buffer slot \(slot) in compute dispatch")
            }
            guard let buffer = buffers[handle] else {
                throw AgentError.invalidArgument("Unknown buffer handle bound at slot \(slot)")
            }
            transitionBuffer(handle, to: D3D12_RESOURCE_STATE_GENERIC_READ)
            let gpuAddress = buffer.resource.pointee.lpVtbl.pointee.GetGPUVirtualAddress(buffer.resource)
            commandList.pointee.lpVtbl.pointee.SetComputeRootConstantBufferView(commandList, UINT(parameterIndex), gpuAddress)
        }

        var storageBindings: [BufferHandle] = []
        for (slot, parameterIndex) in resource.storageParameterIndices {
            guard let entry = bindings.resource(at: slot) else {
                throw AgentError.invalidArgument("Missing storage buffer binding at slot \(slot)")
            }
            let handle: BufferHandle
            switch entry {
            case .buffer(let bufferHandle):
                handle = bufferHandle
            case .texture:
                throw AgentError.invalidArgument("Texture bound to storage buffer slot \(slot) in compute dispatch")
            }
            guard let buffer = buffers[handle] else {
                throw AgentError.invalidArgument("Unknown buffer handle bound at slot \(slot)")
            }
            transitionBuffer(handle, to: D3D12_RESOURCE_STATE_UNORDERED_ACCESS)
            let gpuAddress = buffer.resource.pointee.lpVtbl.pointee.GetGPUVirtualAddress(buffer.resource)
            commandList.pointee.lpVtbl.pointee.SetComputeRootUnorderedAccessView(commandList, UINT(parameterIndex), gpuAddress)
            storageBindings.append(handle)
        }

        let expectedSize = resource.module.pushConstantSize
        if expectedSize > 0 {
            guard let payload = bindings.materialConstants else {
                let message = "Compute shader \(resource.module.id.rawValue) expects \(expectedSize) bytes of push constants but none were provided."
                SDLLogger.error("SDLKit.Graphics.D3D12", message)
                throw AgentError.invalidArgument(message)
            }
            let byteCount = payload.byteCount
            guard byteCount == expectedSize else {
                let message = "Compute shader \(resource.module.id.rawValue) expects \(expectedSize) bytes of push constants but received \(byteCount)."
                SDLLogger.error("SDLKit.Graphics.D3D12", message)
                throw AgentError.invalidArgument(message)
            }
            SDLLogger.error(
                "SDLKit.Graphics.D3D12",
                "Compute push constants of size \(byteCount) bytes requested for shader \(resource.module.id.rawValue), but D3D12 backend does not yet implement them."
            )
            throw AgentError.invalidArgument("Compute push constants are not supported on the D3D12 backend yet")
        } else if let payload = bindings.materialConstants, payload.byteCount > 0 {
            SDLLogger.warn(
                "SDLKit.Graphics.D3D12",
                "Material constants of size \(payload.byteCount) bytes provided for compute shader \(resource.module.id.rawValue) which does not declare push constants. Data will be ignored."
            )
        }

        let dispatchX = max(1, groupsX)
        let dispatchY = max(1, groupsY)
        let dispatchZ = max(1, groupsZ)
        commandList.pointee.lpVtbl.pointee.Dispatch(commandList, UINT(dispatchX), UINT(dispatchY), UINT(dispatchZ))

        for handle in storageBindings {
            insertUAVBarrier(handle)
        }
    }

    // MARK: - Initialization

    private func initializeD3D() throws {
        let enableDbg = SettingsStore.getBool("dx12.debug_layer") ?? false
        if enableDbg {
            enableDebugLayer()
        } else {
            #if DEBUG
            enableDebugLayer()
            #endif
        }
        try createFactory()
        try createDevice()
        try createCommandQueue()
        try createSwapChain()
        try createDescriptorHeaps()
        try createRenderTargetViews()
        try createDepthStencil(width: currentWidth, height: currentHeight)
        try createCommandAllocators()
        try createCommandList()
        try createFence()
        try createTransformBuffer()
    }

    private func createTransformBuffer() throws {
        guard transformBuffer == nil else { return }
        guard let device else { throw AgentError.internalError("Device unavailable for transform buffer") }
        var heapProperties = D3D12_HEAP_PROPERTIES(
            Type: D3D12_HEAP_TYPE_UPLOAD,
            CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
            CreationNodeMask: 0,
            VisibleNodeMask: 0
        )
        var desc = D3D12_RESOURCE_DESC.Buffer(UINT64(256))
        var resource: UnsafeMutablePointer<ID3D12Resource>?
        try withUnsafeMutablePointer(to: &resource) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommittedResource(
                        device,
                        &heapProperties,
                        D3D12_HEAP_FLAG_NONE,
                        &desc,
                        D3D12_RESOURCE_STATE_GENERIC_READ,
                        nil,
                        &IID_ID3D12Resource,
                        raw
                    ),
                    "ID3D12Device.CreateCommittedResource(TransformCB)"
                )
            }
        }
        guard let resource else { throw AgentError.internalError("Failed to create D3D12 transform buffer") }
        transformBuffer = resource
    }

    private func enableDebugLayer() {
        var debug: UnsafeMutablePointer<ID3D12Debug>?
        let result = withUnsafeMutablePointer(to: &debug) { pointer in
            pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                D3D12GetDebugInterface(&IID_ID3D12Debug, raw)
            }
        }
        if result >= 0, let debug {
            debug.pointee.lpVtbl.pointee.EnableDebugLayer(debug)
            debugLayerEnabled = true
            releaseCOM(&debug)
        }
    }

    private func createFactory() throws {
        var factoryPtr: UnsafeMutablePointer<IDXGIFactory6>?
        try withUnsafeMutablePointer(to: &factoryPtr) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                let flags: UINT = debugLayerEnabled ? UINT(DXGI_CREATE_FACTORY_DEBUG) : 0
                let hr = CreateDXGIFactory2(flags, &IID_IDXGIFactory6, raw)
                if hr < 0 && flags != 0 {
                    try checkHRESULT(CreateDXGIFactory2(0, &IID_IDXGIFactory6, raw), "CreateDXGIFactory2")
                } else {
                    try checkHRESULT(hr, "CreateDXGIFactory2")
                }
            }
        }
        guard let factoryPtr else {
            throw AgentError.internalError("Failed to create DXGI factory")
        }
        factory = factoryPtr
    }

    private func createDevice() throws {
        var devicePtr: UnsafeMutablePointer<ID3D12Device>?
        try withUnsafeMutablePointer(to: &devicePtr) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    D3D12CreateDevice(
                        nil,
                        D3D_FEATURE_LEVEL_11_0,
                        &IID_ID3D12Device,
                        raw
                    ),
                    "D3D12CreateDevice"
                )
            }
        }
        guard let devicePtr else {
            throw AgentError.internalError("Unable to create D3D12 device")
        }
        device = devicePtr
    }

    private func createCommandQueue() throws {
        guard let device else {
            throw AgentError.internalError("Device unavailable for command queue creation")
        }
        var desc = D3D12_COMMAND_QUEUE_DESC(
            Type: D3D12_COMMAND_LIST_TYPE_DIRECT,
            Priority: INT(D3D12_COMMAND_QUEUE_PRIORITY_NORMAL.rawValue),
            Flags: D3D12_COMMAND_QUEUE_FLAG_NONE,
            NodeMask: 0
        )
        var queue: UnsafeMutablePointer<ID3D12CommandQueue>?
        try withUnsafeMutablePointer(to: &queue) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommandQueue(
                        device,
                        &desc,
                        &IID_ID3D12CommandQueue,
                        raw
                    ),
                    "ID3D12Device.CreateCommandQueue"
                )
            }
        }
        guard let queue else {
            throw AgentError.internalError("Failed to create D3D12 command queue")
        }
        commandQueue = queue
    }

    private func createSwapChain() throws {
        guard let factory, let commandQueue else {
            throw AgentError.internalError("Factory or command queue unavailable for swap chain")
        }
        var desc = DXGI_SWAP_CHAIN_DESC1()
        desc.Width = UINT(currentWidth)
        desc.Height = UINT(currentHeight)
        desc.Format = Constants.preferredBackBufferFormat
        desc.Stereo = false
        desc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        desc.BufferUsage = UINT(DXGI_USAGE_RENDER_TARGET_OUTPUT.rawValue)
        desc.BufferCount = UINT(Constants.frameCount)
        desc.Scaling = DXGI_SCALING_STRETCH
        desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD
        desc.AlphaMode = DXGI_ALPHA_MODE_IGNORE
        desc.Flags = 0

        var swapChain1: UnsafeMutablePointer<IDXGISwapChain1>?
        let queueUnknown = UnsafeMutableRawPointer(commandQueue).assumingMemoryBound(to: IUnknown.self)
        try withUnsafeMutablePointer(to: &swapChain1) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    factory.pointee.lpVtbl.pointee.CreateSwapChainForHwnd(
                        factory,
                        queueUnknown,
                        hwnd,
                        &desc,
                        nil,
                        nil,
                        raw
                    ),
                    "IDXGIFactory6.CreateSwapChainForHwnd"
                )
            }
        }

        guard let swapChain1 else {
            throw AgentError.internalError("Failed to create DXGI swap chain")
        }

        var swapChain3: UnsafeMutablePointer<IDXGISwapChain3>?
        try withUnsafeMutablePointer(to: &swapChain3) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    swapChain1.pointee.lpVtbl.pointee.QueryInterface(
                        swapChain1,
                        &IID_IDXGISwapChain3,
                        raw
                    ),
                    "IDXGISwapChain1.QueryInterface"
                )
            }
        }
        releaseCOM(&swapChain1)

        guard let swapChain3 else {
            throw AgentError.internalError("Unable to acquire IDXGISwapChain3")
        }
        swapChain = swapChain3
        frameIndex = swapChain3.pointee.lpVtbl.pointee.GetCurrentBackBufferIndex(swapChain3)

        _ = factory.pointee.lpVtbl.pointee.MakeWindowAssociation(factory, hwnd, UINT(DXGI_MWA_NO_ALT_ENTER))
    }

    private func createDescriptorHeaps() throws {
        guard let device else { throw AgentError.internalError("Device unavailable for descriptor heaps") }

        var rtvDesc = D3D12_DESCRIPTOR_HEAP_DESC(
            Type: D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
            NumDescriptors: UINT(Constants.frameCount),
            Flags: D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
            NodeMask: 0
        )
        try withDescriptorHeap(desc: &rtvDesc) { heap in
            rtvHeap = heap
        }
        rtvDescriptorSize = device.pointee.lpVtbl.pointee.GetDescriptorHandleIncrementSize(device, D3D12_DESCRIPTOR_HEAP_TYPE_RTV)

        var dsvDesc = D3D12_DESCRIPTOR_HEAP_DESC(
            Type: D3D12_DESCRIPTOR_HEAP_TYPE_DSV,
            NumDescriptors: 1,
            Flags: D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
            NodeMask: 0
        )
        try withDescriptorHeap(desc: &dsvDesc) { heap in
            dsvHeap = heap
        }
    }

    private func withDescriptorHeap(desc: inout D3D12_DESCRIPTOR_HEAP_DESC, assign: (UnsafeMutablePointer<ID3D12DescriptorHeap>) -> Void) throws {
        guard let device else { throw AgentError.internalError("Device unavailable") }
        var heap: UnsafeMutablePointer<ID3D12DescriptorHeap>?
        try withUnsafeMutablePointer(to: &heap) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateDescriptorHeap(
                        device,
                        &desc,
                        &IID_ID3D12DescriptorHeap,
                        raw
                    ),
                    "ID3D12Device.CreateDescriptorHeap"
                )
            }
        }
        guard let heap else {
            throw AgentError.internalError("Failed to create descriptor heap")
        }
        assign(heap)
    }

    private func createRenderTargetViews() throws {
        guard let device, let swapChain, let rtvHeap else {
            throw AgentError.internalError("Missing resources for RTV creation")
        }
        var handle = rtvHeap.pointee.lpVtbl.pointee.GetCPUDescriptorHandleForHeapStart(rtvHeap)
        for index in 0..<Constants.frameCount {
            var resource: UnsafeMutablePointer<ID3D12Resource>?
            try withUnsafeMutablePointer(to: &resource) { pointer in
                try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                    try checkHRESULT(
                        swapChain.pointee.lpVtbl.pointee.GetBuffer(
                            swapChain,
                            UINT(index),
                            &IID_ID3D12Resource,
                            raw
                        ),
                        "IDXGISwapChain3.GetBuffer"
                    )
                }
            }
            guard let resource else {
                throw AgentError.internalError("Failed to fetch swap chain buffer")
            }
            device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, handle)
            frames[index].renderTarget = resource
            frames[index].rtvHandle = handle
            handle.ptr += UINT64(rtvDescriptorSize)
        }
    }

    private func createDepthStencil(width: Int, height: Int) throws {
        guard let device, let dsvHeap else {
            throw AgentError.internalError("Device or DSV heap unavailable")
        }
        releaseCOM(&depthStencil)

        var heapProps = D3D12_HEAP_PROPERTIES(
            Type: D3D12_HEAP_TYPE_DEFAULT,
            CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
            CreationNodeMask: 0,
            VisibleNodeMask: 0
        )
        var desc = D3D12_RESOURCE_DESC()
        desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D
        desc.Alignment = 0
        desc.Width = UINT64(width)
        desc.Height = UINT(height)
        desc.DepthOrArraySize = 1
        desc.MipLevels = 1
        desc.Format = Constants.preferredDepthFormat
        desc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN
        desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL

        var clearValue = D3D12_CLEAR_VALUE()
        clearValue.Format = Constants.preferredDepthFormat
        clearValue.Anonymous = D3D12_CLEAR_VALUE.__Unnamed_union(DepthStencil: D3D12_DEPTH_STENCIL_VALUE(Depth: 1.0, Stencil: 0))

        try withUnsafeMutablePointer(to: &depthStencil) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommittedResource(
                        device,
                        &heapProps,
                        D3D12_HEAP_FLAG_NONE,
                        &desc,
                        D3D12_RESOURCE_STATE_DEPTH_WRITE,
                        &clearValue,
                        &IID_ID3D12Resource,
                        raw
                    ),
                    "ID3D12Device.CreateCommittedResource(depth)"
                )
            }
        }

        guard let depthStencil else {
            throw AgentError.internalError("Failed to create depth stencil")
        }

        var dsvDesc = D3D12_DEPTH_STENCIL_VIEW_DESC()
        dsvDesc.Format = Constants.preferredDepthFormat
        dsvDesc.ViewDimension = D3D12_DSV_DIMENSION_TEXTURE2D
        dsvDesc.Anonymous.Texture2D = D3D12_TEX2D_DSV(MipSlice: 0)
        dsvDesc.Flags = D3D12_DSV_FLAG_NONE
        let handle = dsvHeap.pointee.lpVtbl.pointee.GetCPUDescriptorHandleForHeapStart(dsvHeap)
        device.pointee.lpVtbl.pointee.CreateDepthStencilView(device, depthStencil, &dsvDesc, handle)
    }

    private func createCommandAllocators() throws {
        guard let device else { throw AgentError.internalError("Device unavailable for allocators") }
        for index in 0..<Constants.frameCount {
            var allocator: UnsafeMutablePointer<ID3D12CommandAllocator>?
            try withUnsafeMutablePointer(to: &allocator) { pointer in
                try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                    try checkHRESULT(
                        device.pointee.lpVtbl.pointee.CreateCommandAllocator(
                            device,
                            D3D12_COMMAND_LIST_TYPE_DIRECT,
                            &IID_ID3D12CommandAllocator,
                            raw
                        ),
                        "ID3D12Device.CreateCommandAllocator"
                    )
                }
            }
            guard let allocator else {
                throw AgentError.internalError("Failed to create command allocator")
            }
            frames[index].commandAllocator = allocator
        }
    }

    private func createCommandList() throws {
        guard let device else { throw AgentError.internalError("Device unavailable for command list") }
        guard let allocator = frames.first?.commandAllocator else {
            throw AgentError.internalError("Command allocator missing for command list creation")
        }
        var list: UnsafeMutablePointer<ID3D12GraphicsCommandList>?
        try withUnsafeMutablePointer(to: &list) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateCommandList(
                        device,
                        0,
                        D3D12_COMMAND_LIST_TYPE_DIRECT,
                        allocator,
                        nil,
                        &IID_ID3D12GraphicsCommandList,
                        raw
                    ),
                    "ID3D12Device.CreateCommandList"
                )
            }
        }
        guard let list else {
            throw AgentError.internalError("Failed to create graphics command list")
        }
        commandList = list
        try checkHRESULT(list.pointee.lpVtbl.pointee.Close(list), "ID3D12GraphicsCommandList.Close")
    }

    private func createFence() throws {
        guard let device else { throw AgentError.internalError("Device unavailable for fence") }
        var fencePtr: UnsafeMutablePointer<ID3D12Fence>?
        try withUnsafeMutablePointer(to: &fencePtr) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateFence(
                        device,
                        0,
                        D3D12_FENCE_FLAG_NONE,
                        &IID_ID3D12Fence,
                        raw
                    ),
                    "ID3D12Device.CreateFence"
                )
            }
        }
        guard let fencePtr else {
            throw AgentError.internalError("Unable to create D3D12 fence")
        }
        fence = fencePtr
        fenceValues = Array(repeating: 0, count: Constants.frameCount)
        fenceEvent = CreateEventW(nil, false, false, nil)
        guard fenceEvent != nil else {
            throw AgentError.internalError("Failed to create fence event")
        }
    }

    private func createBuiltinTriangleResources() throws {
        let vertices: [Float] = [
            -0.6, -0.5, 0.0, 1.0, 0.0, 0.0,
             0.0,  0.6, 0.0, 0.0, 1.0, 0.0,
             0.6, -0.5, 0.0, 0.0, 0.0, 1.0
        ]
        let length = vertices.count * MemoryLayout<Float>.size
        builtinVertexBuffer = try vertices.withUnsafeBytes { bytes in
            try createBuffer(bytes: bytes.baseAddress, length: length, usage: .vertex)
        }
        if builtinPipeline == nil {
            let module = try shaderLibrary.module(for: ShaderID("unlit_triangle"))
            _ = try makePipeline(
                GraphicsPipelineDescriptor(
                    label: "unlit_triangle",
                    shader: module.id,
                    vertexLayout: module.vertexLayout,
                    colorFormats: [.bgra8Unorm],
                    depthFormat: .depth32Float,
                    sampleCount: 1
                )
            )
        }
    }

    private func createPipelineState(desc: inout D3D12_GRAPHICS_PIPELINE_STATE_DESC, into output: inout UnsafeMutablePointer<ID3D12PipelineState>?) throws {
        guard let device else {
            throw AgentError.internalError("Device unavailable for pipeline state creation")
        }
        try withUnsafeMutablePointer(to: &output) { pointer in
            try pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) { raw in
                try checkHRESULT(
                    device.pointee.lpVtbl.pointee.CreateGraphicsPipelineState(
                        device,
                        &desc,
                        &IID_ID3D12PipelineState,
                        raw
                    ),
                    "ID3D12Device.CreateGraphicsPipelineState"
                )
            }
        }
    }

    // MARK: - Synchronization

    private func waitForFrameCompletion(_ index: Int) throws {
        guard let fence else { return }
        let expectedValue = fenceValues[index]
        if fence.pointee.lpVtbl.pointee.GetCompletedValue(fence) < expectedValue {
            try waitForFence(value: expectedValue)
        }
    }

    private func waitForFence(value: UInt64) throws {
        guard let fence, let fenceEvent else { return }
        if fence.pointee.lpVtbl.pointee.GetCompletedValue(fence) < value {
            try checkHRESULT(fence.pointee.lpVtbl.pointee.SetEventOnCompletion(fence, value, fenceEvent), "ID3D12Fence.SetEventOnCompletion")
            WaitForSingleObject(fenceEvent, INFINITE)
        }
    }

    // MARK: - GoldenImageCapturable
    public func requestCapture() { captureRequested = true }
    public func takeCaptureHash() throws -> String {
        guard let h = lastCaptureHash else { throw AgentError.internalError("No capture hash available; call requestCapture() before endFrame") }
        return h
    }

    private static func hashHexRowMajor(data: Data, width: Int, height: Int, rowPitch: Int, bpp: Int) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for y in 0..<height {
                let rowStart = y * rowPitch
                for x in 0..<(width * bpp) {
                    let byte = buf[rowStart + x]
                    hash ^= UInt64(byte)
                    hash = hash &* prime
                }
            }
        }
        return String(format: "%016llx", hash)
    }

    private func convertIndexFormat(_ format: IndexFormat) -> DXGI_FORMAT {
        switch format {
        case .uint16:
            return DXGI_FORMAT_R16_UINT
        case .uint32:
            return DXGI_FORMAT_R32_UINT
        }
    }

    // MARK: - Cleanup

    private func releaseResources() {
        for (_, resource) in computePipelines {
            var state: UnsafeMutablePointer<ID3D12PipelineState>? = resource.pipelineState
            var signature: UnsafeMutablePointer<ID3D12RootSignature>? = resource.rootSignature
            releaseCOM(&state)
            releaseCOM(&signature)
        }
        computePipelines.removeAll()
        for (_, resource) in pipelines {
            var state: UnsafeMutablePointer<ID3D12PipelineState>? = resource.pipelineState
            var signature: UnsafeMutablePointer<ID3D12RootSignature>? = resource.rootSignature
            releaseCOM(&state)
            releaseCOM(&signature)
        }
        pipelines.removeAll()
        for (_, buffer) in buffers {
            var resource: UnsafeMutablePointer<ID3D12Resource>? = buffer.resource
            releaseCOM(&resource)
        }
        buffers.removeAll()
        for (_, texture) in textures {
            var resource: UnsafeMutablePointer<ID3D12Resource>? = texture.resource
            releaseCOM(&resource)
        }
        textures.removeAll()
        samplers.removeAll()
        freeSamplerDescriptorIndices.removeAll(keepingCapacity: false)
        fallbackTextureHandle = nil
        if var rb = readbackBuffer {
            releaseCOM(&rb)
        }
        readbackBuffer = nil
        for index in 0..<Constants.frameCount {
            releaseCOM(&frames[index].renderTarget)
            releaseCOM(&frames[index].commandAllocator)
        }
        releaseCOM(&depthStencil)
        releaseCOM(&commandList)
        releaseCOM(&commandQueue)
        releaseCOM(&swapChain)
        releaseCOM(&rtvHeap)
        releaseCOM(&dsvHeap)
        releaseCOM(&srvHeap)
        releaseCOM(&samplerHeap)
        releaseCOM(&fence)
        releaseCOM(&device)
        releaseCOM(&factory)
        if let fenceEvent {
            CloseHandle(fenceEvent)
        }
    }

    private func releaseCOM<T>(_ pointer: inout UnsafeMutablePointer<T>?) {
        if let value = pointer {
            let unknown = UnsafeMutableRawPointer(value).assumingMemoryBound(to: IUnknown.self)
            _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        }
        pointer = nil
    }

    private func checkHRESULT(_ hr: HRESULT, _ message: String) throws {
        if hr < 0 {
            let code = UInt32(bitPattern: hr)
            let formatted = String(format: "0x%08X", code)
            throw AgentError.internalError("\(message) failed (HRESULT=\(formatted))")
        }
    }
}

#endif
