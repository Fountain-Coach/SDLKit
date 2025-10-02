static const float PI = 3.14159265359;

struct VSInput {
    float3 POSITION : POSITION;
    float3 NORMAL   : NORMAL;
    float3 TANGENT  : TANGENT;
    float2 TEXCOORD : TEXCOORD0;
};

struct VSOutput {
    float4 position    : SV_Position;
    float3 worldPos    : POSITION0;
    float3 worldNormal : NORMAL0;
    float3 worldTangent : TANGENT0;
    float2 uv          : TEXCOORD0;
};

struct SceneParams
{
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float4x4 normalMatrix;
    float4   cameraPosition;
    float4   lightDirectionIntensity; // xyz = direction to light, w = intensity
    float4   lightColorExposure;      // rgb = light color, a = exposure
};

struct MaterialParams
{
    float4 baseColorFactor;
    float4 emissiveFactor;
    float2 uvScale;
    float2 uvOffset;
    float  metallicFactor;
    float  roughnessFactor;
    float  aoStrength;
    float  padding;
};

[[vk::push_constant]] ConstantBuffer<SceneParams> SceneCB : register(b0);
ConstantBuffer<MaterialParams> MaterialCB : register(b1);

[[vk::binding(10, 0)]] Texture2D<float4> AlbedoTexture : register(t10);
[[vk::binding(11, 0)]] Texture2D<float4> NormalTexture : register(t11);
[[vk::binding(12, 0)]] Texture2D<float4> MetallicRoughnessTexture : register(t12);
[[vk::binding(13, 0)]] Texture2D<float4> AmbientOcclusionTexture : register(t13);
[[vk::binding(14, 0)]] Texture2D<float4> EmissiveTexture : register(t14);
[[vk::binding(20, 0)]] TextureCube<float4> IrradianceMap : register(t20);
[[vk::binding(21, 0)]] TextureCube<float4> PrefilterMap : register(t21);
[[vk::binding(22, 0)]] Texture2D<float2> BRDFLUT : register(t22);

[[vk::binding(10, 0)]] SamplerState MaterialSampler : register(s10);
[[vk::binding(21, 0)]] SamplerState EnvironmentSampler : register(s21);
[[vk::binding(22, 0)]] SamplerState LutSampler : register(s22);

VSOutput pbr_forward_vs(VSInput input)
{
    VSOutput o;
    float4 world = mul(float4(input.POSITION, 1.0), SceneCB.modelMatrix);
    o.position = mul(world, SceneCB.viewProjectionMatrix);
    o.worldPos = world.xyz;
    float3 worldNormal = mul((float3x3)SceneCB.normalMatrix, input.NORMAL);
    o.worldNormal = normalize(worldNormal);
    float3 worldTangent = mul((float3x3)SceneCB.normalMatrix, input.TANGENT);
    o.worldTangent = normalize(worldTangent);
    o.uv = input.TEXCOORD * MaterialCB.uvScale + MaterialCB.uvOffset;
    return o;
}

float3 ImportanceSampleGGX(float2 xi, float roughness)
{
    float a = roughness * roughness;
    float phi = 2.0 * PI * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
    return float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
}

float3 ComputeNormal(float3 N, float3 T, float3 tangentNormal)
{
    T = normalize(T - N * dot(N, T));
    float3 B = cross(N, T);
    float3x3 TBN = float3x3(T, B, N);
    return normalize(mul(tangentNormal, TBN));
}

float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    return a2 / max(PI * denom * denom, 1e-4);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / max(NdotV * (1.0 - k) + k, 1e-4);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float ggx1 = GeometrySchlickGGX(max(dot(N, V), 0.0), roughness);
    float ggx2 = GeometrySchlickGGX(max(dot(N, L), 0.0), roughness);
    return ggx1 * ggx2;
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

float2 IntegrateBRDF(float roughness, float NoV)
{
    const uint SAMPLE_COUNT = 1024u;
    float3 V = float3(sqrt(1.0 - NoV * NoV), 0.0, NoV);
    float A = 0.0;
    float B = 0.0;
    for (uint i = 0u; i < SAMPLE_COUNT; ++i)
    {
        float2 xi = float2((float)i / SAMPLE_COUNT, frac((float)i * 2.61803398875));
        float3 H = ImportanceSampleGGX(xi, roughness);
        float3 L = normalize(2.0 * dot(V, H) * H - V);
        float NoL = saturate(L.z);
        float NoH = saturate(H.z);
        float VoH = saturate(dot(V, H));
        if (NoL > 0.0)
        {
            float G = GeometrySmith(float3(0.0, 0.0, 1.0), V, L, roughness);
            float GVis = (G * VoH) / max(NoH * NoV, 1e-4);
            float Fc = pow(1.0 - VoH, 5.0);
            A += (1.0 - Fc) * GVis;
            B += Fc * GVis;
        }
    }
    A /= SAMPLE_COUNT;
    B /= SAMPLE_COUNT;
    return float2(A, B);
}

float4 pbr_forward_ps(VSOutput input) : SV_Target
{
    float3 V = normalize(SceneCB.cameraPosition.xyz - input.worldPos);
    float3 baseNormal = normalize(input.worldNormal);
    float4 albedoSample = AlbedoTexture.Sample(MaterialSampler, input.uv);
    float4 normalSample = NormalTexture.Sample(MaterialSampler, input.uv);
    float3 tangentNormal = normalize(normalSample.xyz * 2.0 - 1.0);
    float3 N = ComputeNormal(baseNormal, input.worldTangent, tangentNormal);
    float4 mrSample = MetallicRoughnessTexture.Sample(MaterialSampler, input.uv);
    float metallic = saturate(mrSample.b * MaterialCB.metallicFactor);
    float roughness = saturate(mrSample.g * MaterialCB.roughnessFactor);
    float ao = lerp(1.0, AmbientOcclusionTexture.Sample(MaterialSampler, input.uv).r, MaterialCB.aoStrength);

    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedoSample.rgb, metallic);

    float3 L = normalize(SceneCB.lightDirectionIntensity.xyz);
    float3 H = normalize(V + L);
    float NoL = saturate(dot(N, L));
    float NoV = saturate(dot(N, V));
    float NoH = saturate(dot(N, H));
    float VoH = saturate(dot(V, H));

    float D = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);
    float3 F = FresnelSchlick(VoH, F0);

    float3 numerator = D * G * F;
    float denominator = max(4.0 * NoL * NoV, 1e-4);
    float3 specular = numerator / denominator;

    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float3 irradiance = IrradianceMap.Sample(EnvironmentSampler, N).rgb;
    float3 diffuse = irradiance * albedoSample.rgb;

    float3 prefiltered = PrefilterMap.SampleLevel(EnvironmentSampler, reflect(-V, N), roughness * 5.0).rgb;
    float2 brdf = BRDFLUT.Sample(LutSampler, float2(NoV, roughness)).rg;
    float3 specIBL = prefiltered * (F * brdf.x + brdf.y);

    float lightIntensity = SceneCB.lightDirectionIntensity.w * NoL;
    float3 direct = (kD * albedoSample.rgb / PI + specular) * SceneCB.lightColorExposure.rgb * lightIntensity;

    float exposure = SceneCB.lightColorExposure.a;
    float3 color = (direct + diffuse * kD + specIBL) * ao * exposure;
    float3 emissive = EmissiveTexture.Sample(MaterialSampler, input.uv).rgb * MaterialCB.emissiveFactor.rgb;
    color += emissive;

    color = color / (color + 1.0); // simple tonemap
    return float4(color, albedoSample.a * MaterialCB.baseColorFactor.a);
}
