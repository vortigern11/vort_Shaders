#pragma once
#include "Includes/vort_Defs.fxh"

texture2D BlueNoiseTexVort < source = "vort_BlueNoise.png"; > { Width = 32; Height = 32; TEX_RGBA8 };
sampler2D sBlueNoiseTexVort { Texture = BlueNoiseTexVort; SAM_POINT SAM_WRAP };

float3 GetBlueNoise(float2 vpos) { return tex2Dfetch(sBlueNoiseTexVort, uint2(vpos) % 32).xyz; }
