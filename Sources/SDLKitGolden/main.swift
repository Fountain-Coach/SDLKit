import Foundation
import SDLKit

@main
@MainActor
struct SDLKitGoldenCLI {
    static func main() {
        let args = CommandLine.arguments.dropFirst()
        var backendOverride: String? = nil
        var width = 256, height = 256
        var material = SDLKitConfigStore.defaultMaterial()
        var write = false

        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--backend", "-b": backendOverride = it.next()
            case "--size", "-s":
                if let wh = it.next(), let x = Int(wh.split(separator: "x").first ?? ""), let y = Int(wh.split(separator: "x").last ?? "") { width = x; height = y }
            case "--material", "-m": material = it.next() ?? material
            case "--write", "-w": write = true
            case "--help", "-h": printUsage(); return
            default: break
            }
        }

        do {
            let window = SDLWindow(config: .init(title: "SDLKitGolden", width: width, height: height))
            try window.open(); defer { window.close() }
            try window.show()

            let backend = try RenderBackendFactory.makeBackend(window: window, override: backendOverride ?? SettingsStore.getString("render.backend.override"))
            guard let cap = backend as? GoldenImageCapturable else {
                print("Backend does not support capture; aborting.")
                return
            }

            // Build scene
            let scene = try makeScene(backend: backend, material: material, width: width, height: height)

            cap.requestCapture()
            try SceneGraphRenderer.updateAndRender(scene: scene, backend: backend)
            let hash = try cap.takeCaptureHash()
            let backendName = backendOverride ?? RenderBackendFactory.defaultChoice().rawValue
            let key = GoldenRefs.key(backend: backendName, width: width, height: height, material: material)

            if write {
                GoldenRefs.setExpected(hash, for: key)
                print("Wrote golden hash: \(hash) key=\(key)")
            } else if let expected = GoldenRefs.getExpected(for: key) {
                if expected == hash {
                    print("Golden OK: \(hash) key=\(key)")
                } else {
                    print("Golden MISMATCH: actual=\(hash) expected=\(expected) key=\(key)")
                    exit(1)
                }
            } else {
                print("Golden hash (no reference): \(hash) key=\(key)")
            }
        } catch {
            print("SDLKitGolden error: \(error)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        Usage: sdlkit-golden [--backend metal|vulkan|d3d12] [--size WxH] [--material unlit|basic_lit] [--write]

          --backend, -b   Override backend
          --size, -s      Window size (e.g. 256x256)
          --material, -m  Shader/material (unlit or basic_lit)
          --write, -w     Persist current hash as golden via FountainStore
        """)
    }

    static func makeScene(backend: RenderBackend, material: String, width: Int, height: Int) throws -> Scene {
        let root = SceneNode(name: "Root")
        if material == "unlit" {
            struct V { var p:(Float,Float,Float); var c:(Float,Float,Float) }
            let verts:[V] = [ .init(p:(-0.6,-0.5,0),c:(1,0,0)), .init(p:(0,0.6,0),c:(0,1,0)), .init(p:(0.6,-0.5,0),c:(0,0,1)) ]
            let vb = try verts.withUnsafeBytes { try backend.createBuffer(bytes: $0.baseAddress, length: $0.count, usage: .vertex) }
            let mesh = Mesh(vertexBuffer: vb, vertexCount: verts.count)
            let mat = Material(shader: ShaderID("unlit_triangle"), params: .init(baseColor: (1,1,1,1)))
            let node = SceneNode(name: "Unlit", transform: .identity, mesh: mesh, material: mat)
            root.addChild(node)
        } else {
            let mesh = try MeshFactory.makeLitCube(backend: backend, size: 1.0)
            let mat = Material(shader: ShaderID("basic_lit"), params: .init(lightDirection: (0.3,-0.5,0.8), baseColor: (1,1,1,1)))
            let node = SceneNode(name: "Lit", transform: .identity, mesh: mesh, material: mat)
            root.addChild(node)
        }

        let aspect = Float(width) / Float(max(1,height))
        let cam = Camera(view: float4x4.lookAt(eye:(0,0,2.2), center:(0,0,0), up:(0,1,0)), projection: float4x4.perspective(fovYRadians: .pi/3, aspect: aspect, zNear: 0.1, zFar: 100))
        return Scene(root: root, camera: cam, lightDirection: (0.3,-0.5,0.8))
    }
}
