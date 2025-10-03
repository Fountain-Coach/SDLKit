import XCTest
@testable import SDLKit

final class ComputeVectorAddParityTests: XCTestCase {
    private func runVectorAddParity(backendOverride: String) async throws {
        try await MainActor.run {
            let window = SDLWindow(config: .init(title: "VectorAdd", width: 64, height: 64))
            try window.open(); defer { window.close() }
            try window.show()

            let backend = try RenderBackendFactory.makeBackend(window: window, override: backendOverride)
            let module = try ShaderLibrary.shared.computeModule(for: ShaderID("vector_add"))
            let pipeline = try backend.makeComputePipeline(ComputePipelineDescriptor(label: "vector_add", shader: module.id))

            // Prepare input data
            let count = 1024
            var inputA = (0..<count).map { Float($0) * 0.5 }
            var inputB = (0..<count).map { Float($0) * 1.5 + 1.0 }
            var zeros = [Float](repeating: 0, count: count)

            let bufA = try inputA.withUnsafeBytes { bytes in
                try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
            }
            let bufB = try inputB.withUnsafeBytes { bytes in
                try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
            }
            let bufC = try zeros.withUnsafeBytes { bytes in
                try backend.createBuffer(bytes: bytes.baseAddress, length: bytes.count, usage: .storage)
            }

            try backend.beginFrame()
            defer { try? backend.endFrame() }

            var bindings = BindingSet()
            bindings.setBuffer(bufA, at: 0)
            bindings.setBuffer(bufB, at: 1)
            bindings.setBuffer(bufC, at: 2)

            // Push constants: elementCount (uint32) + padding
            var constants = Data(count: MemoryLayout<UInt32>.size * 4)
            constants.withUnsafeMutableBytes { raw in
                if let base = raw.bindMemory(to: UInt32.self).baseAddress {
                    base[0] = UInt32(count)
                    base[1] = 0; base[2] = 0; base[3] = 0
                }
            }
            bindings.materialConstants = BindingSet.MaterialConstants(data: constants)

            // Dispatch: use ceil(count / 64) groups
            let groupsX = (count + module.threadgroupSize.0 - 1) / module.threadgroupSize.0
            try backend.dispatchCompute(pipeline, groupsX: groupsX, groupsY: 1, groupsZ: 1, bindings: bindings)

            try backend.endFrame()
            try backend.waitGPU()

            // Read back output
            var out = [Float](repeating: 0, count: count)
            out.withUnsafeMutableBytes { bytes in
                if let base = bytes.baseAddress {
                    try? backend.readback(buffer: bufC, into: base, length: bytes.count)
                }
            }

            for i in 0..<count {
                let expected = inputA[i] + inputB[i]
                XCTAssertEqual(out[i], expected, accuracy: 1e-5, "Mismatch at index \(i)")
            }
        }
    }

    func testVectorAddParity_Metal() async throws {
        #if os(macOS)
        do { try await runVectorAddParity(backendOverride: "metal") }
        catch AgentError.sdlUnavailable { throw XCTSkip("SDL unavailable; skipping") }
        catch AgentError.invalidArgument(let msg) { throw XCTSkip(msg) }
        #else
        throw XCTSkip("Metal test only on macOS")
        #endif
    }

    func testVectorAddParity_Vulkan() async throws {
        #if os(Linux)
        do { try await runVectorAddParity(backendOverride: "vulkan") }
        catch AgentError.sdlUnavailable { throw XCTSkip("SDL unavailable; skipping") }
        catch AgentError.missingDependency(_) { throw XCTSkip("Vulkan headers/loader unavailable; skipping") }
        catch AgentError.invalidArgument(let msg) { throw XCTSkip(msg) }
        #else
        throw XCTSkip("Vulkan test only on Linux")
        #endif
    }
}
