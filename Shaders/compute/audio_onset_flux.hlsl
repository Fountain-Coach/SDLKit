struct AudioOnsetParams
{
    uint melBands;
    uint frames;
    uint hasPrev; // 1 if prev provided
    uint _pad;
};

[[vk::push_constant]] ConstantBuffer<AudioOnsetParams> Params : register(b0);

// Input mel energies: frames contiguous blocks of length melBands
[[vk::binding(0, 0)]] StructuredBuffer<float> InMel : register(t0);
// Optional previous mel (length melBands) used for first frame delta when hasPrev == 1
[[vk::binding(1, 0)]] StructuredBuffer<float> PrevMel : register(t1);
// Output onset per frame (spectral flux)
[[vk::binding(2, 0)]] RWStructuredBuffer<float> OutOnset : register(u2);

[numthreads(1, 1, 1)]
void audio_onset_flux_cs(uint3 tid : SV_DispatchThreadID)
{
    uint frameIndex = tid.x; // one thread per frame
    if (frameIndex >= Params.frames) { return; }
    float flux = 0.0f;
    uint base = frameIndex * Params.melBands;
    if (frameIndex == 0 && Params.hasPrev != 0)
    {
        for (uint i = 0; i < Params.melBands; ++i)
        {
            float d = InMel[base + i] - PrevMel[i];
            if (d > 0.0f) { flux += d; }
        }
    }
    else if (frameIndex > 0)
    {
        uint prevBase = (frameIndex - 1) * Params.melBands;
        for (uint i = 0; i < Params.melBands; ++i)
        {
            float d = InMel[base + i] - InMel[prevBase + i];
            if (d > 0.0f) { flux += d; }
        }
    }
    OutOnset[frameIndex] = flux;
}

