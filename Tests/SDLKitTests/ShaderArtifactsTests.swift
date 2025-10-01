import XCTest
@testable import SDLKit

final class ShaderArtifactsTests: XCTestCase {
    private struct Module {
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

        let modules: [Module] = [
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
        ]

        let fm = FileManager.default

        for module in modules {
            try ShaderArtifactMaterializer.materializeArtifactsIfNeeded(at: module.expectedArtifacts)

            for artifactURL in module.expectedArtifacts {
                let path = artifactURL.path
                XCTAssertTrue(fm.fileExists(atPath: path), "Missing shader artifact: \(path)")

                let artifactData = try Data(contentsOf: artifactURL)
                let base64URL = artifactURL.appendingPathExtension("b64")

                XCTAssertTrue(fm.fileExists(atPath: base64URL.path), "Missing committed shader payload: \(base64URL.path)")
                let base64String = try String(contentsOf: base64URL, encoding: .utf8)
                let stripped = base64String.filter { !$0.isWhitespace }
                let decodedData = Data(base64Encoded: stripped)
                XCTAssertNotNil(decodedData, "Committed shader payload for \(base64URL.path) is not valid base64")
                if let decodedData {
                    XCTAssertEqual(artifactData, decodedData, "Materialized shader artifact does not match committed payload: \(path)")
                }
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
