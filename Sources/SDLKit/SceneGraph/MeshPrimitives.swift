import Foundation

@MainActor
public enum MeshFactory {
    public static func makeLitPlane(backend: RenderBackend, size: Float = 1.0) throws -> Mesh {
        let hs = size * 0.5
        struct V { var px: Float; var py: Float; var pz: Float; var nx: Float; var ny: Float; var nz: Float; var r: Float; var g: Float; var b: Float }
        let verts: [V] = [
            V(px: -hs, py: -hs, pz: 0, nx: 0, ny: 0, nz: 1, r: 1, g: 1, b: 1),
            V(px:  hs, py: -hs, pz: 0, nx: 0, ny: 0, nz: 1, r: 1, g: 1, b: 1),
            V(px:  hs, py:  hs, pz: 0, nx: 0, ny: 0, nz: 1, r: 1, g: 1, b: 1),
            V(px: -hs, py: -hs, pz: 0, nx: 0, ny: 0, nz: 1, r: 1, g: 1, b: 1),
            V(px:  hs, py:  hs, pz: 0, nx: 0, ny: 0, nz: 1, r: 1, g: 1, b: 1),
            V(px: -hs, py:  hs, pz: 0, nx: 0, ny: 0, nz: 1, r: 1, g: 1, b: 1)
        ]
        let vb = try verts.withUnsafeBytes { buf in
            try backend.createBuffer(bytes: buf.baseAddress, length: buf.count, usage: .vertex)
        }
        return Mesh(vertexBuffer: vb, vertexCount: verts.count)
    }

    public static func makeLitCube(backend: RenderBackend, size: Float = 1.0) throws -> Mesh {
        let hs = size * 0.5
        // 6 faces, each with 2 triangles, 6 vertices per face => 36
        struct V { var px: Float; var py: Float; var pz: Float; var nx: Float; var ny: Float; var nz: Float; var r: Float; var g: Float; var b: Float }
        var verts: [V] = []
        func face(_ nx: Float, _ ny: Float, _ nz: Float, _ corners: [(Float, Float, Float)], _ color: (Float, Float, Float)) {
            let (r,g,b) = color
            // Two triangles: 0-1-2, 0-2-3
            let v0 = corners[0], v1 = corners[1], v2 = corners[2], v3 = corners[3]
            verts.append(V(px: v0.0, py: v0.1, pz: v0.2, nx: nx, ny: ny, nz: nz, r: r, g: g, b: b))
            verts.append(V(px: v1.0, py: v1.1, pz: v1.2, nx: nx, ny: ny, nz: nz, r: r, g: g, b: b))
            verts.append(V(px: v2.0, py: v2.1, pz: v2.2, nx: nx, ny: ny, nz: nz, r: r, g: g, b: b))
            verts.append(V(px: v0.0, py: v0.1, pz: v0.2, nx: nx, ny: ny, nz: nz, r: r, g: g, b: b))
            verts.append(V(px: v2.0, py: v2.1, pz: v2.2, nx: nx, ny: ny, nz: nz, r: r, g: g, b: b))
            verts.append(V(px: v3.0, py: v3.1, pz: v3.2, nx: nx, ny: ny, nz: nz, r: r, g: g, b: b))
        }
        // +Z face
        face(0,0,1, [(-hs,-hs, hs),(hs,-hs, hs),(hs,hs, hs),(-hs,hs, hs)], (1,0,0))
        // -Z face
        face(0,0,-1, [(-hs,-hs,-hs),(-hs,hs,-hs),(hs,hs,-hs),(hs,-hs,-hs)], (0,1,0))
        // +X face
        face(1,0,0, [(hs,-hs,-hs),(hs,hs,-hs),(hs,hs,hs),(hs,-hs,hs)], (0,0,1))
        // -X face
        face(-1,0,0, [(-hs,-hs,-hs),(-hs,-hs,hs),(-hs,hs,hs),(-hs,hs,-hs)], (1,1,0))
        // +Y face
        face(0,1,0, [(-hs,hs,-hs),(-hs,hs,hs),(hs,hs,hs),(hs,hs,-hs)], (1,0,1))
        // -Y face
        face(0,-1,0, [(-hs,-hs,-hs),(hs,-hs,-hs),(hs,-hs,hs),(-hs,-hs,hs)], (0,1,1))

        let vb = try verts.withUnsafeBytes { buf in
            try backend.createBuffer(bytes: buf.baseAddress, length: buf.count, usage: .vertex)
        }
        return Mesh(vertexBuffer: vb, vertexCount: verts.count)
    }
}

