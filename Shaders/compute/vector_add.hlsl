struct VectorAddParams
{
    uint elementCount;
    float padding[3];
};

[[vk::push_constant]] ConstantBuffer<VectorAddParams> Params : register(b0);

[[vk::binding(0, 0)]] StructuredBuffer<float> InputA : register(t0);
[[vk::binding(1, 0)]] StructuredBuffer<float> InputB : register(t1);
[[vk::binding(2, 0)]] RWStructuredBuffer<float> OutputC : register(u2);

[numthreads(64, 1, 1)]
void vector_add_cs(uint3 groupID : SV_DispatchThreadID)
{
    uint index = groupID.x;
    if (index >= Params.elementCount)
    {
        return;
    }
    OutputC[index] = InputA[index] + InputB[index];
}
