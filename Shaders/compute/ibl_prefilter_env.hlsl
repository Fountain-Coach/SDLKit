static const float PI = 3.14159265359;

struct PrefilterParams
{
    float roughness;
    float mipLevel;
    uint faceIndex;
    uint sampleCount;
};

[[vk::push_constant]] ConstantBuffer<PrefilterParams> PrefilterCB : register(b0);

[[vk::binding(0, 0)]] TextureCube<float4> EnvironmentMap : register(t0);
[[vk::binding(0, 0)]] SamplerState EnvironmentSampler : register(s0);
[[vk::binding(1, 0)]] RWTexture2DArray<float4> OutputTexture : register(u1);

float3 ImportanceSampleGGX(float2 xi, float roughness)
{
    float a = roughness * roughness;
    float phi = 2.0 * PI * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
    return float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
}

float3 SampleDirection(uint faceIndex, float2 uv)
{
    uv = uv * 2.0 - 1.0;
    switch (faceIndex)
    {
    case 0: return normalize(float3(1.0, -uv.y, -uv.x));
    case 1: return normalize(float3(-1.0, -uv.y, uv.x));
    case 2: return normalize(float3(uv.x, 1.0, uv.y));
    case 3: return normalize(float3(uv.x, -1.0, -uv.y));
    case 4: return normalize(float3(uv.x, -uv.y, 1.0));
    default: return normalize(float3(-uv.x, -uv.y, -1.0));
    }
}

[numthreads(8, 8, 1)]
void ibl_prefilter_env_cs(uint3 dispatchID : SV_DispatchThreadID)
{
    uint width, height, layers;
    OutputTexture.GetDimensions(width, height, layers);
    if (dispatchID.x >= width || dispatchID.y >= height)
    {
        return;
    }

    float2 uv = (float2(dispatchID.xy) + 0.5) / float2(width, height);
    float3 N = SampleDirection(PrefilterCB.faceIndex, uv);
    float3 R = N;
    float3 V = R;

    uint sampleCount = max(PrefilterCB.sampleCount, 1u);
    float3 prefilteredColor = 0.0;
    float totalWeight = 0.0;

    for (uint i = 0u; i < sampleCount; ++i)
    {
        float2 xi = float2((float)i / sampleCount, frac((float)i * 2.61803398875));
        float3 H = ImportanceSampleGGX(xi, PrefilterCB.roughness);
        float3 L = normalize(2.0 * dot(V, H) * H - V);
        float NoL = saturate(dot(N, L));
        if (NoL > 0.0)
        {
            prefilteredColor += EnvironmentMap.SampleLevel(EnvironmentSampler, L, PrefilterCB.mipLevel).rgb * NoL;
            totalWeight += NoL;
        }
    }

    prefilteredColor = totalWeight > 0.0 ? prefilteredColor / totalWeight : EnvironmentMap.SampleLevel(EnvironmentSampler, N, PrefilterCB.mipLevel).rgb;
    OutputTexture[uint3(dispatchID.xy, PrefilterCB.faceIndex)] = float4(prefilteredColor, 1.0);
}
