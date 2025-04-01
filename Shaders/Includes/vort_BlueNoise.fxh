#pragma once
#include "Includes/vort_Defs.fxh"

namespace BlueNoise {
    texture2D BlueNoiseTex < source = "vort_BlueNoise.png"; > { Width = 256; Height = 256; TEX_RGBA8 };
    sampler2D sBlueNoiseTex { Texture = BlueNoiseTex; SAM_POINT SAM_WRAP };
}

float4 GetBlueNoise(float2 vpos) { return tex2Dfetch(BlueNoise::sBlueNoiseTex, uint2(vpos) % 256); }
