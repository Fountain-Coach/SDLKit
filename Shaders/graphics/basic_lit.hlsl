// Minimal directional light (Lambert) with hard-coded light direction
struct VSInput {
    float3 POSITION : POSITION;
    float3 NORMAL   : NORMAL;
    float3 COLOR    : COLOR;
};

struct VSOutput {
    float4 position : SV_Position;
    float3 color    : COLOR;
    float3 normal   : NORMAL;
};

// Vulkan SPIR-V path: mark as push constants; ignored on DXIL path
[[vk::push_constant]] cbuffer SceneCB : register(b0)
{
    float4x4 uMVP;
    float4   lightDir; // xyz = direction
};

VSOutput basic_lit_vs(VSInput input) {
    VSOutput o;
    o.position = mul(float4(input.POSITION, 1.0), uMVP);
    o.color = input.COLOR;
    o.normal = input.NORMAL;
    return o;
}

float4 basic_lit_ps(VSOutput input) : SV_Target {
    float3 N = normalize(input.normal);
    float3 L = normalize(lightDir.xyz);
    float ndotl = max(dot(N, L), 0.0);
    float3 lit = input.color * (0.15 + 0.85 * ndotl);
    return float4(lit, 1.0);
}
