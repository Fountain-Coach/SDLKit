// HLSL reference for unlit triangle with transform (moved under Shaders/graphics for plugin)
struct VSInput {
    float3 POSITION : POSITION;
    float3 COLOR    : COLOR;
};

struct VSOutput {
    float4 position : SV_Position;
    float3 color    : COLOR;
};

// Vulkan SPIR-V path: mark as push constants; ignored on DXIL path
struct SceneConstants
{
    float4x4 uMVP;
    float4   lightDir; // unused here
    float4   baseColor;
};

[[vk::push_constant]] ConstantBuffer<SceneConstants> SceneCB : register(b0);

VSOutput unlit_triangle_vs(VSInput input) {
    VSOutput o;
    o.position = mul(float4(input.POSITION, 1.0), SceneCB.uMVP);
    o.color = input.COLOR;
    return o;
}

float4 unlit_triangle_ps(VSOutput input) : SV_Target {
    float3 c = input.color * SceneCB.baseColor.rgb;
    return float4(c, 1.0);
}
