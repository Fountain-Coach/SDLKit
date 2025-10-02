import XCTest
@testable import SDLKit

final class ShaderArtifactsTests: XCTestCase {
    private struct Module {
        let name: String
        let expectedArtifacts: [URL]
    }

    private struct ComputeModule {
        let name: String
        let expectedArtifacts: [URL]
    }

    @MainActor
    func testCompiledShadersArePresentAndUpToDate() async throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ShaderArtifactsTests.swift
            .deletingLastPathComponent() // SDLKitTests
            .deletingLastPathComponent() // Tests

        let generatedRoot = packageRoot
            .appendingPathComponent("Sources/SDLKit/Generated", isDirectory: true)

        let graphicsModules: [Module] = [
            Module(
                name: "unlit_triangle",
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("dxil/unlit_triangle_vs.dxil"),
                    generatedRoot.appendingPathComponent("dxil/unlit_triangle_ps.dxil"),
                    generatedRoot.appendingPathComponent("spirv/unlit_triangle.vert.spv"),
                    generatedRoot.appendingPathComponent("spirv/unlit_triangle.frag.spv"),
                    generatedRoot.appendingPathComponent("metal/unlit_triangle.metallib"),
                ]
            ),
            Module(
                name: "basic_lit",
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("dxil/basic_lit_vs.dxil"),
                    generatedRoot.appendingPathComponent("dxil/basic_lit_ps.dxil"),
                    generatedRoot.appendingPathComponent("spirv/basic_lit.vert.spv"),
                    generatedRoot.appendingPathComponent("spirv/basic_lit.frag.spv"),
                    generatedRoot.appendingPathComponent("metal/basic_lit.metallib"),
                ]
            ),
            Module(
                name: "directional_lit",
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("dxil/directional_lit_vs.dxil"),
                    generatedRoot.appendingPathComponent("dxil/directional_lit_ps.dxil"),
                    generatedRoot.appendingPathComponent("spirv/directional_lit.vert.spv"),
                    generatedRoot.appendingPathComponent("spirv/directional_lit.frag.spv"),
                    generatedRoot.appendingPathComponent("metal/directional_lit.metallib"),
                ]
            ),
            Module(
                name: "pbr_forward",
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("dxil/pbr_forward_vs.dxil"),
                    generatedRoot.appendingPathComponent("dxil/pbr_forward_ps.dxil"),
                    generatedRoot.appendingPathComponent("spirv/pbr_forward.vert.spv"),
                    generatedRoot.appendingPathComponent("spirv/pbr_forward.frag.spv"),
                    generatedRoot.appendingPathComponent("metal/pbr_forward.metallib"),
                ]
            ),
        ]

        let computeModules: [ComputeModule] = [
            ComputeModule(
                name: "vector_add",
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("dxil/vector_add_cs.dxil"),
                    generatedRoot.appendingPathComponent("spirv/vector_add.comp.spv"),
                    generatedRoot.appendingPathComponent("metal/vector_add.metallib"),
                ]
            ),
            ComputeModule(
                name: "scenegraph_wave",
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("spirv/scenegraph_wave.comp.spv"),
                    generatedRoot.appendingPathComponent("metal/scenegraph_wave.metallib"),
                ]
            ),
            ComputeModule(
                name: "ibl_prefilter_env",
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("dxil/ibl_prefilter_env_cs.dxil"),
                    generatedRoot.appendingPathComponent("spirv/ibl_prefilter_env.comp.spv"),
                    generatedRoot.appendingPathComponent("metal/ibl_prefilter_env.metallib"),
                ]
            ),
            ComputeModule(
                name: "ibl_brdf_lut",
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("dxil/ibl_brdf_lut_cs.dxil"),
                    generatedRoot.appendingPathComponent("spirv/ibl_brdf_lut.comp.spv"),
                    generatedRoot.appendingPathComponent("metal/ibl_brdf_lut.metallib"),
                ]
            ),
        ]

        let fm = FileManager.default

        for module in graphicsModules {
            try verifyArtifacts(for: module.expectedArtifacts, fileManager: fm)

            do {
                _ = try await MainActor.run {
                    try ShaderLibrary.shared.module(for: ShaderID(module.name))
                }
            } catch {
                XCTFail("ShaderLibrary missing module \(module.name): \(error)")
            }
        }

        for module in computeModules {
            try verifyArtifacts(for: module.expectedArtifacts, fileManager: fm)

            do {
                _ = try await MainActor.run {
                    try ShaderLibrary.shared.computeModule(for: ShaderID(module.name))
                }
            } catch {
                XCTFail("ShaderLibrary missing compute module \(module.name): \(error)")
            }
        }
    }

    private func verifyArtifacts(for artifacts: [URL], fileManager: FileManager) throws {
        try ShaderArtifactMaterializer.materializeArtifactsIfNeeded(at: artifacts)

        for artifactURL in artifacts {
            let path = artifactURL.path
            XCTAssertTrue(fileManager.fileExists(atPath: path), "Missing shader artifact: \(path)")

            let artifactData = try Data(contentsOf: artifactURL)
            let base64URL = artifactURL.appendingPathExtension("b64")

            XCTAssertTrue(fileManager.fileExists(atPath: base64URL.path), "Missing committed shader payload: \(base64URL.path)")
            let base64String = try String(contentsOf: base64URL, encoding: .utf8)
            let stripped = base64String.filter { !$0.isWhitespace }
            let decodedData = Data(base64Encoded: stripped)
            XCTAssertNotNil(decodedData, "Committed shader payload for \(base64URL.path) is not valid base64")
            if let decodedData {
                XCTAssertEqual(artifactData, decodedData, "Materialized shader artifact does not match committed payload: \(path)")
            }
        }
    }
}
