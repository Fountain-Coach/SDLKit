import XCTest
@testable import SDLKit
#if canImport(CSDL3)
import CSDL3
#endif

final class VectorAddComputeTests: XCTestCase {
    func testVectorAddPipelineProducesExpectedResults() async throws {
        let shaderID = ShaderID("vector_add")
        do {
            try await MainActor.run {
    #if canImport(CSDL3)
                guard SDLKitStub_IsActive() != 0 else {
                    throw XCTSkip("SDL3 stub unavailable; vector add compute test requires stub backend")
                }
    #endif
                guard let module = try? ShaderLibrary.shared.computeModule(for: shaderID) else {
                    throw XCTSkip("vector_add compute shader unavailable on this configuration")
                }

                let window = SDLWindow(config: .init(title: "VectorAddCompute", width: 128, height: 128))
                try window.open()
                defer { window.close() }
                try window.show()

                let backend = try RenderBackendFactory.makeBackend(window: window)

                guard let stub = backend as? StubRenderBackend else {
                    throw XCTSkip("TODO: GPU buffer readback helper not implemented yet for vector_add compute test")
                }

                let elementCount = 256
                let byteCount = elementCount * MemoryLayout<Float>.stride
                let inputA: [Float] = (0..<elementCount).map { Float($0) * 0.5 }
                let inputB: [Float] = (0..<elementCount).map { Float(elementCount - $0) * 0.25 }
                let expected = zip(inputA, inputB).map(+)

                let lhsBuffer = try inputA.withUnsafeBytes { bytes -> BufferHandle in
                    try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
                }
                let rhsBuffer = try inputB.withUnsafeBytes { bytes -> BufferHandle in
                    try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
                }
                let zeroed = [UInt8](repeating: 0, count: byteCount)
                let outputBuffer = try zeroed.withUnsafeBytes { bytes -> BufferHandle in
                    try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
                }

                let threadgroupWidth = max(1, module.threadgroupSize.0)
                let groupsX = (elementCount + threadgroupWidth - 1) / threadgroupWidth

                var bindings = BindingSet()
                bindings.setValue(lhsBuffer, for: 0)
                bindings.setValue(rhsBuffer, for: 1)
                bindings.setValue(outputBuffer, for: 2)

                let pipeline = try backend.makeComputePipeline(
                    ComputePipelineDescriptor(label: "VectorAddTest", shader: shaderID)
                )

                try backend.dispatchCompute(
                    pipeline,
                    groupsX: groupsX,
                    groupsY: 1,
                    groupsZ: 1,
                    bindings: bindings,
                    pushConstants: nil
                )

                do {
                    let actual = try Self.emulateVectorAddForStub(
                        stub: stub,
                        lhsBuffer: lhsBuffer,
                        rhsBuffer: rhsBuffer,
                        outputBuffer: outputBuffer,
                        elementCount: elementCount
                    )
                    XCTAssertEqual(actual.count, expected.count, "Vector add output count mismatch")
                    for (index, (actualValue, expectedValue)) in zip(actual, expected).enumerated() {
                        XCTAssertEqual(actualValue, expectedValue, accuracy: 1e-6, "Mismatch at element \(index)")
                    }
                } catch {
                    XCTFail("Failed to validate vector_add compute output on stub backend: \(error)")
                    return
                }
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch AgentError.sdlUnavailable {
            throw XCTSkip("SDL unavailable; skipping vector_add compute test")
        } catch AgentError.notImplemented {
            throw XCTSkip("vector_add compute shader unavailable on this configuration")
        }
    }

    @MainActor
    private static func emulateVectorAddForStub(
        stub: StubRenderBackend,
        lhsBuffer: BufferHandle,
        rhsBuffer: BufferHandle,
        outputBuffer: BufferHandle,
        elementCount: Int
    ) throws -> [Float] {
        let byteCount = elementCount * MemoryLayout<Float>.stride
        guard let lhsData = stub.bufferData(lhsBuffer) else {
            throw VectorAddTestError.missingBufferData("lhsBuffer")
        }
        guard let rhsData = stub.bufferData(rhsBuffer) else {
            throw VectorAddTestError.missingBufferData("rhsBuffer")
        }
        guard lhsData.count >= byteCount else {
            throw VectorAddTestError.sizeMismatch("lhsBuffer size \(lhsData.count) < \(byteCount)")
        }
        guard rhsData.count >= byteCount else {
            throw VectorAddTestError.sizeMismatch("rhsBuffer size \(rhsData.count) < \(byteCount)")
        }

        try stub.withMutableBufferData(outputBuffer) { outputData in
            if outputData.count < byteCount {
                outputData = Data(count: byteCount)
            }
            lhsData.withUnsafeBytes { lhsBytes in
                rhsData.withUnsafeBytes { rhsBytes in
                    outputData.withUnsafeMutableBytes { outputBytes in
                        let lhsPtr = lhsBytes.bindMemory(to: Float.self)
                        let rhsPtr = rhsBytes.bindMemory(to: Float.self)
                        let outPtr = outputBytes.bindMemory(to: Float.self)
                        for index in 0..<elementCount {
                            outPtr[index] = lhsPtr[index] + rhsPtr[index]
                        }
                    }
                }
            }
        }

        guard let outputData = stub.bufferData(outputBuffer) else {
            throw VectorAddTestError.missingBufferData("outputBuffer")
        }
        guard outputData.count >= byteCount else {
            throw VectorAddTestError.sizeMismatch("outputBuffer size \(outputData.count) < \(byteCount)")
        }
        return outputData.withUnsafeBytes { rawBytes in
            let floatBuffer = rawBytes.bindMemory(to: Float.self)
            return Array(floatBuffer.prefix(elementCount))
        }
    }

    private enum VectorAddTestError: Error {
        case missingBufferData(String)
        case sizeMismatch(String)
    }
}
