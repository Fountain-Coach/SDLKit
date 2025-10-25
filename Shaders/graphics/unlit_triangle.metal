// Native Metal version of the unlit triangle shader used for the demo path
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

vertex VSOut unlit_triangle_vs(uint vid [[vertex_id]],
                               const device VSIn *inVerts [[buffer(0)]]) {
    VSOut out;
    VSIn v = inVerts[vid];
    out.position = float4(v.position, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 unlit_triangle_ps(VSOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}

