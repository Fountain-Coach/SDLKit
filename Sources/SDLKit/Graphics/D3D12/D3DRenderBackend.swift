#if os(Windows) && canImport(WinSDK)
import Foundation
import WinSDK
import Direct3D12
import DXGI

@MainActor
public final class D3D12RenderBackend: RenderBackend {
    private enum Constants {
        static let frameCount = 2
        static let preferredBackBufferFormat: DXGI_FORMAT = DXGI_FORMAT_B8G8R8A8_UNORM
        static let preferredDepthFormat: DXGI_FORMAT = DXGI_FORMAT_D32_FLOAT
    }

    private struct BufferResource {
        let resource: UnsafeMutablePointer<ID3D12Resource>
        let length: Int
        let usage: BufferUsage
    }

    private struct PipelineResource {
        let handle: PipelineHandle
        let descriptor: GraphicsPipelineDescriptor
        let module: ShaderModule
        let rootSignature: UnsafeMutablePointer<ID3D12RootSignature>
        let pipelineState: UnsafeMutablePointer<ID3D12PipelineState>
        let vertexStride: Int
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

    private var builtinPipeline: PipelineHandle?
    private var builtinVertexBuffer: BufferHandle?

    private var frameActive = false
    private var debugLayerEnabled = false
    private let shaderLibrary = ShaderLibrary.shared

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

        try checkHRESULT(commandList.pointee.lpVtbl.pointee.Close(commandList), "ID3D12GraphicsCommandList.Close")

        var listPointer = UnsafeMutableRawPointer(commandList).assumingMemoryBound(to: ID3D12CommandList.self)
        commandQueue.pointee.lpVtbl.pointee.ExecuteCommandLists(commandQueue, 1, &listPointer)

        try checkHRESULT(swapChain.pointee.lpVtbl.pointee.Present(swapChain, 1, 0), "IDXGISwapChain3.Present")

        let currentFrame = Int(frameIndex)
        let fenceValue = fenceValues[currentFrame] + 1
        fenceValues[currentFrame] = fenceValue
        try checkHRESULT(commandQueue.pointee.lpVtbl.pointee.Signal(commandQueue, fence, fenceValue), "ID3D12CommandQueue.Signal")

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
        buffers[handle] = BufferResource(resource: resource, length: length, usage: usage)
        return handle
    }

    public func createTexture(descriptor: TextureDescriptor, initialData: TextureInitialData?) throws -> TextureHandle {
        _ = descriptor
        _ = initialData
        throw AgentError.notImplemented
    }

    public func destroy(_ handle: ResourceHandle) {
        switch handle {
        case .buffer(let buffer):
            if var resource = buffers.removeValue(forKey: buffer)?.resource {
                releaseCOM(&resource)
            }
        case .texture:
            break
        case .pipeline(let pipelineHandle):
            if let resource = pipelines.removeValue(forKey: pipelineHandle) {
                var state: UnsafeMutablePointer<ID3D12PipelineState>? = resource.pipelineState
                var signature: UnsafeMutablePointer<ID3D12RootSignature>? = resource.rootSignature
                releaseCOM(&state)
                releaseCOM(&signature)
            }
        case .computePipeline:
            break
        case .mesh:
            break
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

        // Root signature with one CBV at b0 for vertex shader (transform)
        var cbv = D3D12_ROOT_PARAMETER()
        cbv.ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV
        cbv.ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL
        cbv.Anonymous.Descriptor = D3D12_ROOT_DESCRIPTOR(ShaderRegister: 0, RegisterSpace: 0)
        var rootDesc = D3D12_ROOT_SIGNATURE_DESC()
        var params = [cbv]
        params.withUnsafeMutableBufferPointer { buf in
            rootDesc.NumParameters = UINT(buf.count)
            rootDesc.pParameters = buf.baseAddress
        }
        rootDesc.NumStaticSamplers = 0
        rootDesc.pStaticSamplers = nil
        rootDesc.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT

        var serializedRoot: UnsafeMutablePointer<ID3DBlob>?
        var errorBlob: UnsafeMutablePointer<ID3DBlob>?
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
            vertexStride: module.vertexLayout.stride
        )
        if builtinPipeline == nil {
            builtinPipeline = handle
        }
        return handle
    }

    public func draw(mesh: MeshHandle, pipeline: PipelineHandle, bindings: BindingSet, pushConstants: UnsafeRawPointer?, transform: float4x4) throws {
        _ = mesh
        _ = pushConstants
        _ = transform
        guard frameActive else {
            throw AgentError.internalError("draw called outside beginFrame/endFrame")
        }
        guard let commandList else {
            throw AgentError.internalError("Command list unavailable during draw")
        }
        guard let pipelineResource = pipelines[pipeline] else {
            throw AgentError.internalError("Unknown pipeline handle for draw")
        }

        let boundBuffer = bindings.value(for: 0, as: BufferHandle.self) ?? builtinVertexBuffer
        guard let bufferHandle = boundBuffer, let buffer = buffers[bufferHandle] else {
            throw AgentError.internalError("Vertex buffer binding missing for draw call")
        }
        let stride = pipelineResource.vertexStride
        guard stride > 0 else {
            throw AgentError.internalError("Pipeline vertex stride is zero")
        }
        let vertexCount = buffer.length / stride
        guard vertexCount > 0 else { return }

        commandList.pointee.lpVtbl.pointee.SetPipelineState(commandList, pipelineResource.pipelineState)
        commandList.pointee.lpVtbl.pointee.SetGraphicsRootSignature(commandList, pipelineResource.rootSignature)
        // Upload uniforms (matrix + lightDir) to a small CBV and bind to root slot 0
        if transformBuffer == nil {
            try? createTransformBuffer()
        }
        if let tbuf = transformBuffer {
            var mapped: UnsafeMutableRawPointer?
            _ = tbuf.pointee.lpVtbl.pointee.Map(tbuf, 0, nil, &mapped)
            if let mapped {
                // Prepare 80 bytes: matrix (64) + lightDir (16)
                var data: [Float] = transform.toFloatArray()
                if let pc = pushConstants {
                    let ptr = pc.bindMemory(to: Float.self, capacity: 20)
                    let buf = UnsafeBufferPointer(start: ptr, count: 20)
                    data = Array(buf)
                } else {
                    data.append(contentsOf: [0.3, -0.5, 0.8, 0.0])
                }
                data.withUnsafeBytes { bytes in memcpy(mapped, bytes.baseAddress, min(80, bytes.count)) }
            }
            tbuf.pointee.lpVtbl.pointee.Unmap(tbuf, 0, nil)
            let gpuAddress = tbuf.pointee.lpVtbl.pointee.GetGPUVirtualAddress(tbuf)
            commandList.pointee.lpVtbl.pointee.SetGraphicsRootConstantBufferView(commandList, 0, gpuAddress)
        }
        commandList.pointee.lpVtbl.pointee.IASetPrimitiveTopology(commandList, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST)

        var view = D3D12_VERTEX_BUFFER_VIEW(
            BufferLocation: buffer.resource.pointee.lpVtbl.pointee.GetGPUVirtualAddress(buffer.resource),
            SizeInBytes: UINT(buffer.length),
            StrideInBytes: UINT(stride)
        )
        commandList.pointee.lpVtbl.pointee.IASetVertexBuffers(commandList, 0, 1, &view)
        commandList.pointee.lpVtbl.pointee.DrawInstanced(commandList, UINT(vertexCount), 1, 0, 0)
    }

    public func makeComputePipeline(_ desc: ComputePipelineDescriptor) throws -> ComputePipelineHandle {
        _ = desc
        throw AgentError.notImplemented
    }

    public func dispatchCompute(_ pipeline: ComputePipelineHandle, groupsX: Int, groupsY: Int, groupsZ: Int, bindings: BindingSet, pushConstants: UnsafeRawPointer?) throws {
        _ = pipeline
        _ = groupsX
        _ = groupsY
        _ = groupsZ
        _ = bindings
        _ = pushConstants
        throw AgentError.notImplemented
    }

    // MARK: - Initialization

    private func initializeD3D() throws {
        #if DEBUG
        enableDebugLayer()
        #endif
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

    // MARK: - Cleanup

    private func releaseResources() {
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
