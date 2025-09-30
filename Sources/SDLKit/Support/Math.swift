import Foundation

public extension float4x4 {
    static func translation(x: Float, y: Float, z: Float) -> float4x4 {
        return float4x4(
            (1, 0, 0, 0),
            (0, 1, 0, 0),
            (0, 0, 1, 0),
            (x, y, z, 1)
        )
    }

    static func rotationZ(_ radians: Float) -> float4x4 {
        let c = cosf(radians)
        let s = sinf(radians)
        return float4x4(
            ( c, s, 0, 0),
            (-s, c, 0, 0),
            ( 0, 0, 1, 0),
            ( 0, 0, 0, 1)
        )
    }

    static func *(lhs: float4x4, rhs: float4x4) -> float4x4 {
        let a = lhs.columns
        let b = rhs.columns
        func dot(_ a: float4x4.Column, _ b: float4x4.Column) -> Float {
            return a.0*b.0 + a.1*b.1 + a.2*b.2 + a.3*b.3
        }
        // Column-major multiplication
        let c0 = (
            dot((a.0.0, a.1.0, a.2.0, a.3.0), b.0),
            dot((a.0.1, a.1.1, a.2.1, a.3.1), b.0),
            dot((a.0.2, a.1.2, a.2.2, a.3.2), b.0),
            dot((a.0.3, a.1.3, a.2.3, a.3.3), b.0)
        )
        let c1 = (
            dot((a.0.0, a.1.0, a.2.0, a.3.0), b.1),
            dot((a.0.1, a.1.1, a.2.1, a.3.1), b.1),
            dot((a.0.2, a.1.2, a.2.2, a.3.2), b.1),
            dot((a.0.3, a.1.3, a.2.3, a.3.3), b.1)
        )
        let c2 = (
            dot((a.0.0, a.1.0, a.2.0, a.3.0), b.2),
            dot((a.0.1, a.1.1, a.2.1, a.3.1), b.2),
            dot((a.0.2, a.1.2, a.2.2, a.3.2), b.2),
            dot((a.0.3, a.1.3, a.2.3, a.3.3), b.2)
        )
        let c3 = (
            dot((a.0.0, a.1.0, a.2.0, a.3.0), b.3),
            dot((a.0.1, a.1.1, a.2.1, a.3.1), b.3),
            dot((a.0.2, a.1.2, a.2.2, a.3.2), b.3),
            dot((a.0.3, a.1.3, a.2.3, a.3.3), b.3)
        )
        return float4x4(c0, c1, c2, c3)
    }

    func toFloatArray() -> [Float] {
        let c = columns
        return [c.0.0, c.0.1, c.0.2, c.0.3,
                c.1.0, c.1.1, c.1.2, c.1.3,
                c.2.0, c.2.1, c.2.2, c.2.3,
                c.3.0, c.3.1, c.3.2, c.3.3]
    }
}

