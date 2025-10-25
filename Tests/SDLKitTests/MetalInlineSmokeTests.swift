import XCTest

#if canImport(Metal)
import Metal

final class MetalInlineSmokeTests: XCTestCase {
    func testInlineMetalCompilationAndPipeline() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available on this host")
        }

        // Locate the native Metal source for the unlit triangle
        let testFile = URL(fileURLWithPath: #filePath)
        let pkgRoot = testFile
            .deletingLastPathComponent() // MetalInlineSmokeTests.swift
            .deletingLastPathComponent() // SDLKitTests
            .deletingLastPathComponent() // Tests
        let metalURL = pkgRoot.appendingPathComponent("Shaders/graphics/unlit_triangle.metal")
        let source = try String(contentsOf: metalURL, encoding: .utf8)

        let opts = MTLCompileOptions()
        if #available(macOS 12.0, *) { opts.languageVersion = .version3_0 }
        let lib = try device.makeLibrary(source: source, options: opts)
        XCTAssertNotNil(lib.makeFunction(name: "unlit_triangle_vs"))
        XCTAssertNotNil(lib.makeFunction(name: "unlit_triangle_ps"))

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "unlit_triangle_vs")
        desc.fragmentFunction = lib.makeFunction(name: "unlit_triangle_ps")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        _ = try device.makeRenderPipelineState(descriptor: desc)
    }
}
#endif

