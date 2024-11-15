#pragma once
#include "Includes/vort_Defs.fxh"

texture2D BlueNoiseTexVort < source = "vort_BlueNoise.png"; > { Width = 256; Height = 256; TEX_RGBA8 };
sampler2D sBlueNoiseTexVort { Texture = BlueNoiseTexVort; SAM_POINT SAM_WRAP };

float4 GetBlueNoise(float2 vpos) { return tex2Dfetch(sBlueNoiseTexVort, uint2(vpos) % 256); }
