struct AudioDFTParams
{
    uint frameSize;   // N (power of two typically)
    uint nBins;       // N/2 + 1
    uint frames;      // number of frames in batch
    uint _pad;
};

[[vk::push_constant]] ConstantBuffer<AudioDFTParams> Params : register(b0);

// Input samples: frames contiguous blocks of length frameSize (mono, windowed)
[[vk::binding(0, 0)]] StructuredBuffer<float> InputSamples : register(t0);
// Output power spectra: frames contiguous blocks of length nBins
[[vk::binding(1, 0)]] RWStructuredBuffer<float> OutputPower : register(u1);

// Each thread computes one (frame, bin) pair
[numthreads(64, 1, 1)]
void audio_dft_power_cs(uint3 tid : SV_DispatchThreadID)
{
    uint globalIndex = tid.x;
    uint total = Params.frames * Params.nBins;
    if (globalIndex >= total) { return; }

    uint frameIndex = globalIndex / Params.nBins;
    uint binIndex = globalIndex % Params.nBins;

    float re = 0.0f;
    float im = 0.0f;
    const float twoPiOverN = 6.28318530717958647692f / (float)Params.frameSize;
    uint base = frameIndex * Params.frameSize;
    for (uint n = 0; n < Params.frameSize; ++n)
    {
        float x = InputSamples[base + n];
        float angle = twoPiOverN * (float)(binIndex * n);
        float s, c;
        s = sin(angle);
        c = cos(angle);
        re += x * c;
        im -= x * s;
    }
    float power = re * re + im * im;
    OutputPower[frameIndex * Params.nBins + binIndex] = power;
}

