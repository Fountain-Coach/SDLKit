#include <metal_stdlib>
using namespace metal;

struct VSIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float3 color    [[attribute(2)]];
};

struct VSOut {
    float4 position [[position]];
    float3 normal;
    float3 color;
};

struct Uniforms {
    float4x4 uMVP;
    float4   lightDir;
};

vertex VSOut basic_lit_vs(VSIn in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
    VSOut o;
    o.position = u.uMVP * float4(in.position, 1.0);
    o.color = in.color;
    o.normal = in.normal;
    return o;
}

fragment float4 basic_lit_ps(VSOut in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
    float3 N = normalize(in.normal);
    float3 L = normalize(u.lightDir.xyz);
    float ndotl = max(dot(N, L), 0.0);
    float3 lit = in.color * (0.15 + 0.85 * ndotl);
    return float4(lit, 1.0);
}

