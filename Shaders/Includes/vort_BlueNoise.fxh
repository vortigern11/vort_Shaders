#pragma once
#include "Includes/vort_Defs.fxh"

texture2D BlueNoiseTexVort < source = "vort_BlueNoise.png"; > { Width = 32; Height = 32; TEX_RGBA8 };
sampler2D sBlueNoiseTexVort { Texture = BlueNoiseTexVort; SAM_POINT SAM_WRAP };

float3 GetBlueNoise(uint2 vpos) { return tex2Dfetch(sBlueNoiseTexVort, vpos % 32).xyz; }
