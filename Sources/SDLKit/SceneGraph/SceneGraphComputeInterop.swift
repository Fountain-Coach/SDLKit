import Foundation

@MainActor
public enum SceneGraphComputeInterop {
    public struct Resources {
        let computePipeline: ComputePipelineHandle
        let stateBuffer: BufferHandle
        let configBuffer: BufferHandle
        let vertexBuffer: BufferHandle
        let vertexCount: Int
    }

    private struct CPUState {
        var baseX: Float
        var baseY: Float
        var baseZ: Float
        var phase: Float
    }

    private struct CPUConfig {
        var colorR: Float
        var colorG: Float
        var colorB: Float
        var phaseIncrement: Float
    }

    public static func makeNode(backend: RenderBackend) throws -> (SceneNode, Resources) {
        let shaderID = ShaderID("scenegraph_wave")
        guard (try? ShaderLibrary.shared.computeModule(for: shaderID)) != nil else {
            throw AgentError.notImplemented
        }

        let computePipeline = try backend.makeComputePipeline(ComputePipelineDescriptor(label: "scenegraph_wave", shader: shaderID))

        let vertexCount = 3
        let states: [CPUState] = [
            CPUState(baseX: -0.5, baseY: -0.6, baseZ: 0.0, phase: 0.0),
            CPUState(baseX: 0.0, baseY: 0.8, baseZ: 0.0, phase: .pi * 0.33),
            CPUState(baseX: 0.5, baseY: -0.6, baseZ: 0.0, phase: .pi * 0.66)
        ]
        let configs: [CPUConfig] = [
            CPUConfig(colorR: 1.0, colorG: 0.4, colorB: 0.4, phaseIncrement: 0.05),
            CPUConfig(colorR: 0.4, colorG: 1.0, colorB: 0.5, phaseIncrement: 0.045),
            CPUConfig(colorR: 0.4, colorG: 0.6, colorB: 1.0, phaseIncrement: 0.065)
        ]

        let stateBuffer = try states.withUnsafeBytes { bytes in
            try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
        }
        let configBuffer = try configs.withUnsafeBytes { bytes in
            try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
        }
        let vertexBufferLength = vertexCount * MemoryLayout<Float>.size * 6
        let zeroed = [UInt8](repeating: 0, count: vertexBufferLength)
        let vertexBuffer = try zeroed.withUnsafeBytes { bytes in
            try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
        }

        var mesh = Mesh(vertexBuffer: vertexBuffer, vertexCount: vertexCount)
        let material = Material(shader: ShaderID("unlit_triangle"), params: MaterialParams(baseColor: (1, 1, 1, 1)))
        let node = SceneNode(name: "ComputeWave", transform: .identity, mesh: mesh, material: material)

        // Ensure mesh registration uses the storage-backed buffer
        _ = try mesh.ensureHandle(with: backend)
        node.mesh = mesh

        let resources = Resources(
            computePipeline: computePipeline,
            stateBuffer: stateBuffer,
            configBuffer: configBuffer,
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount
        )
        return (node, resources)
    }

    public static func dispatchCompute(backend: RenderBackend, resources: Resources) throws {
        var bindings = BindingSet()
        bindings.setValue(resources.stateBuffer, for: 0)
        bindings.setValue(resources.configBuffer, for: 1)
        bindings.setValue(resources.vertexBuffer, for: 2)
        try backend.dispatchCompute(
            resources.computePipeline,
            groupsX: resources.vertexCount,
            groupsY: 1,
            groupsZ: 1,
            bindings: bindings
        )
        try applyCPUFallbackIfNeeded(backend: backend, resources: resources)
    }

    private static func applyCPUFallbackIfNeeded(backend: RenderBackend, resources: Resources) throws {
        guard let stub = backend as? StubRenderBackend else { return }
        guard let configData = stub.bufferData(resources.configBuffer) else { return }
        let vertexCount = resources.vertexCount
        if configData.count < vertexCount * MemoryLayout<Float>.size * 4 { return }

        try stub.withMutableBufferData(resources.stateBuffer) { stateData in
            guard stateData.count >= vertexCount * MemoryLayout<Float>.size * 4 else { return }
            try stub.withMutableBufferData(resources.vertexBuffer) { vertexData in
                if vertexData.count < vertexCount * MemoryLayout<Float>.size * 6 {
                    vertexData = Data(count: vertexCount * MemoryLayout<Float>.size * 6)
                }
                stateData.withUnsafeMutableBytes { stateBytes in
                    configData.withUnsafeBytes { configBytes in
                        vertexData.withUnsafeMutableBytes { vertexBytes in
                            let statePtr = stateBytes.bindMemory(to: Float.self)
                            let configPtr = configBytes.bindMemory(to: Float.self)
                            let vertexPtr = vertexBytes.bindMemory(to: Float.self)
                            for index in 0..<vertexCount {
                                let stateBase = index * 4
                                let configBase = index * 4
                                let phase = statePtr[stateBase + 3] + configPtr[configBase + 3]
                                statePtr[stateBase + 3] = phase
                                let cosValue = Float(cos(Double(phase)))
                                let sinValue = Float(sin(Double(phase)))
                                let baseX = statePtr[stateBase + 0]
                                let baseY = statePtr[stateBase + 1]
                                let baseZ = statePtr[stateBase + 2]
                                let rotatedX = baseX * cosValue - baseY * sinValue
                                let rotatedY = baseX * sinValue + baseY * cosValue
                                let rotatedZ = baseZ
                                let scale = Float(0.6 + 0.4 * sin(Double(phase)))
                                let colorR = clamp(configPtr[configBase + 0] * scale, lower: 0.0, upper: 1.0)
                                let colorG = clamp(configPtr[configBase + 1] * scale, lower: 0.0, upper: 1.0)
                                let colorB = clamp(configPtr[configBase + 2] * scale, lower: 0.0, upper: 1.0)
                                let vertexBase = index * 6
                                vertexPtr[vertexBase + 0] = rotatedX
                                vertexPtr[vertexBase + 1] = rotatedY
                                vertexPtr[vertexBase + 2] = rotatedZ
                                vertexPtr[vertexBase + 3] = colorR
                                vertexPtr[vertexBase + 4] = colorG
                                vertexPtr[vertexBase + 5] = colorB
                            }
                        }
                    }
                }
            }
        }
    }
}

private func clamp(_ value: Float, lower: Float, upper: Float) -> Float {
    return min(max(value, lower), upper)
}
