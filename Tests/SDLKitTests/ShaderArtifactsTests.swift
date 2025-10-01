import XCTest
@testable import SDLKit

final class ShaderArtifactsTests: XCTestCase {
    private struct Module {
        let name: String
        let source: URL
        let expectedArtifacts: [URL]
    }

    @MainActor
    func testCompiledShadersArePresentAndUpToDate() async throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ShaderArtifactsTests.swift
            .deletingLastPathComponent() // SDLKitTests
            .deletingLastPathComponent() // Tests

        let shaderRoot = packageRoot.appendingPathComponent("Shaders/graphics", isDirectory: true)
        let generatedRoot = packageRoot
            .appendingPathComponent("Sources/SDLKit/Generated", isDirectory: true)

        let modules: [Module] = [
            Module(
                name: "unlit_triangle",
                source: shaderRoot.appendingPathComponent("unlit_triangle.hlsl"),
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
                source: shaderRoot.appendingPathComponent("basic_lit.hlsl"),
                expectedArtifacts: [
                    generatedRoot.appendingPathComponent("dxil/basic_lit_vs.dxil"),
                    generatedRoot.appendingPathComponent("dxil/basic_lit_ps.dxil"),
                    generatedRoot.appendingPathComponent("spirv/basic_lit.vert.spv"),
                    generatedRoot.appendingPathComponent("spirv/basic_lit.frag.spv"),
                    generatedRoot.appendingPathComponent("metal/basic_lit.metallib"),
                ]
            ),
        ]

        let fm = FileManager.default

        for module in modules {
            try ShaderArtifactMaterializer.materializeArtifactsIfNeeded(at: module.expectedArtifacts)

            let shaderAttributes = try fm.attributesOfItem(atPath: module.source.path)
            let shaderTimestamp = try XCTUnwrap(shaderAttributes[.modificationDate] as? Date, "Missing modification date for \(module.source.path)")

            for artifactURL in module.expectedArtifacts {
                let path = artifactURL.path
                XCTAssertTrue(fm.fileExists(atPath: path), "Missing shader artifact: \(path)")

                let attributes = try fm.attributesOfItem(atPath: path)
                let artifactTimestamp = try XCTUnwrap(attributes[.modificationDate] as? Date, "Missing modification date for \(path)")
                XCTAssertGreaterThanOrEqual(artifactTimestamp, shaderTimestamp, "Shader artifact outdated: \(path)")
            }

            do {
                _ = try await MainActor.run {
                    try ShaderLibrary.shared.module(for: ShaderID(module.name))
                }
            } catch {
                XCTFail("ShaderLibrary missing module \(module.name): \(error)")
            }
        }
    }
}
