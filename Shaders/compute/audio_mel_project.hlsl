struct AudioMelParams
{
    uint nBins;      // spectrum bins (N/2+1)
    uint melBands;   // number of mel bands
    uint frames;     // batch of frames
    uint _pad;
};

[[vk::push_constant]] ConstantBuffer<AudioMelParams> Params : register(b0);

// Input power spectra: frames contiguous blocks of length nBins
[[vk::binding(0, 0)]] StructuredBuffer<float> InputPower : register(t0);
// Mel weights: row-major [mel][bin] with length melBands * nBins
[[vk::binding(1, 0)]] StructuredBuffer<float> MelWeights : register(t1);
// Output mel energies: frames contiguous blocks of length melBands
[[vk::binding(2, 0)]] RWStructuredBuffer<float> OutputMel : register(u2);

[numthreads(64, 1, 1)]
void audio_mel_project_cs(uint3 tid : SV_DispatchThreadID)
{
    uint total = Params.frames * Params.melBands;
    uint g = tid.x;
    if (g >= total) { return; }
    uint frameIndex = g / Params.melBands;
    uint melIndex = g % Params.melBands;

    float acc = 0.0f;
    uint powerBase = frameIndex * Params.nBins;
    uint wBase = melIndex * Params.nBins;
    [loop]
    for (uint k = 0; k < Params.nBins; ++k)
    {
        acc += MelWeights[wBase + k] * InputPower[powerBase + k];
    }
    OutputMel[frameIndex * Params.melBands + melIndex] = acc;
}

