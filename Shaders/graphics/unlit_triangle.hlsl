struct VSInput {
    float3 position : POSITION;
    float3 color : COLOR0;
};

struct VSOutput {
    float4 position : SV_Position;
    float3 color : COLOR0;
};

VSOutput unlit_triangle_vs(VSInput input) {
    VSOutput output;
    output.position = float4(input.position, 1.0f);
    output.color = input.color;
    return output;
}

float4 unlit_triangle_ps(VSOutput input) : SV_Target0 {
    return float4(input.color, 1.0f);
}
