#include <metal_stdlib>
using namespace metal;

struct VSIn {
    float3 position [[attribute(0)]];
    float3 color    [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float3 color;
};

struct Uniforms {
    float4x4 uMVP;
};

vertex VSOut unlit_triangle_vs(VSIn in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
    VSOut o;
    o.position = u.uMVP * float4(in.position, 1.0);
    o.color = in.color;
    return o;
}

fragment float4 unlit_triangle_ps(VSOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}

