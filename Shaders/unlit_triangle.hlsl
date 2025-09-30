// HLSL reference for unlit triangle with transform
struct VSInput {
    float3 POSITION : POSITION;
    float3 COLOR    : COLOR;
};

struct VSOutput {
    float4 position : SV_Position;
    float3 color    : COLOR;
};

cbuffer SceneCB : register(b0)
{
    float4x4 uMVP;
};

VSOutput unlit_triangle_vs(VSInput input) {
    VSOutput o;
    o.position = mul(float4(input.POSITION, 1.0), uMVP);
    o.color = input.COLOR;
    return o;
}

float4 unlit_triangle_ps(VSOutput input) : SV_Target {
    return float4(input.color, 1.0);
}

