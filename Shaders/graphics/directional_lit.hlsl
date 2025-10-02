struct VSInput {
    float3 POSITION : POSITION;
    float3 NORMAL   : NORMAL;
    float2 TEXCOORD : TEXCOORD0;
};

struct VSOutput {
    float4 position    : SV_Position;
    float3 worldNormal : NORMAL;
    float3 worldPos    : POSITION0;
    float2 uv          : TEXCOORD0;
    float4 shadowCoord : TEXCOORD1;
};

struct SceneConstants
{
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float4x4 lightViewProjectionMatrix;
    float4   lightDirectionIntensity; // xyz = direction (toward surface), w = intensity
    float4   lightColor;              // rgb = directional light color, a unused
    float4   ambientColor;            // rgb = ambient color, a unused
};

[[vk::push_constant]] ConstantBuffer<SceneConstants> SceneCB : register(b0);

[[vk::binding(10, 0)]] Texture2D<float4> AlbedoTexture : register(t10);
[[vk::binding(20, 0)]] Texture2D<float> ShadowMap : register(t20);
[[vk::binding(10, 0)]] SamplerState MaterialSampler : register(s10);
[[vk::binding(20, 0)]] SamplerComparisonState ShadowSampler : register(s20);

VSOutput directional_lit_vs(VSInput input)
{
    VSOutput o;
    float4 worldPosition = mul(float4(input.POSITION, 1.0), SceneCB.modelMatrix);
    o.position = mul(worldPosition, SceneCB.viewProjectionMatrix);
    float3 worldNormal = mul((float3x3)SceneCB.modelMatrix, input.NORMAL);
    o.worldNormal = normalize(worldNormal);
    o.worldPos = worldPosition.xyz;
    o.uv = input.TEXCOORD;
    o.shadowCoord = mul(worldPosition, SceneCB.lightViewProjectionMatrix);
    return o;
}

float3 DecodeShadowCoords(float4 shadowCoord)
{
    float3 proj = shadowCoord.xyz / max(shadowCoord.w, 0.0001);
    float2 uv = proj.xy * 0.5 + 0.5;
    float depth = proj.z * 0.5 + 0.5;
    return float3(uv, depth);
}

float4 directional_lit_ps(VSOutput input) : SV_Target
{
    float3 N = normalize(input.worldNormal);
    float3 L = normalize(SceneCB.lightDirectionIntensity.xyz);
    float NoL = saturate(dot(N, L));

    float4 albedo = AlbedoTexture.Sample(MaterialSampler, input.uv);
    float3 litColor = SceneCB.ambientColor.rgb * albedo.rgb;
    if (SceneCB.lightDirectionIntensity.w > 0.0)
    {
        float3 shadowCoords = DecodeShadowCoords(input.shadowCoord);
        float2 shadowUV = shadowCoords.xy;
        float depth = shadowCoords.z - 0.001 * (1.0 - NoL);
        float shadow = ShadowMap.SampleCmpLevelZero(ShadowSampler, shadowUV, depth);
        float lightContribution = SceneCB.lightDirectionIntensity.w * NoL * shadow;
        litColor += albedo.rgb * SceneCB.lightColor.rgb * lightContribution;
    }

    return float4(litColor, albedo.a);
}
