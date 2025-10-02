static const float PI = 3.14159265359;

struct BRDFParams
{
    uint sampleCount;
    float padding[3];
};

[[vk::push_constant]] ConstantBuffer<BRDFParams> BRDFCB : register(b0);

[[vk::binding(0, 0)]] RWTexture2D<float2> OutputLUT : register(u0);

float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;
}

float2 Hammersley(uint i, uint N)
{
    return float2(float(i) / float(N), RadicalInverse_VdC(i));
}

float3 ImportanceSampleGGX(float2 xi, float roughness)
{
    float a = roughness * roughness;
    float phi = 2.0 * PI * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
    return float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / max(NdotV * (1.0 - k) + k, 1e-4);
}

float GeometrySmith(float NdotV, float NdotL, float roughness)
{
    return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
}

[numthreads(16, 16, 1)]
void ibl_brdf_lut_cs(uint3 dispatchID : SV_DispatchThreadID)
{
    uint width, height;
    OutputLUT.GetDimensions(width, height);
    if (dispatchID.x >= width || dispatchID.y >= height)
    {
        return;
    }

    float2 uv = (float2(dispatchID.xy) + 0.5) / float2(width, height);
    float NoV = uv.x;
    float roughness = uv.y;

    float3 V = float3(sqrt(1.0 - NoV * NoV), 0.0, NoV);
    float A = 0.0;
    float B = 0.0;

    uint sampleCount = max(BRDFCB.sampleCount, 1u);
    for (uint i = 0u; i < sampleCount; ++i)
    {
        float2 xi = Hammersley(i, sampleCount);
        float3 H = ImportanceSampleGGX(xi, roughness);
        float3 L = normalize(2.0 * dot(V, H) * H - V);
        float NoL = saturate(L.z);
        float NoH = saturate(H.z);
        float VoH = saturate(dot(V, H));
        if (NoL > 0.0)
        {
            float G = GeometrySmith(NoV, NoL, roughness);
            float GVis = (G * VoH) / max(NoH * NoV, 1e-4);
            float Fc = pow(1.0 - VoH, 5.0);
            A += (1.0 - Fc) * GVis;
            B += Fc * GVis;
        }
    }

    A /= sampleCount;
    B /= sampleCount;
    OutputLUT[dispatchID.xy] = float2(A, B);
}
