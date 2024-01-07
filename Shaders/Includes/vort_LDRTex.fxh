#pragma once
#include "Includes/vort_Defs.fxh"

texture2D LDRTexVort : COLOR;
sampler2D sLDRTexVort { Texture = LDRTexVort; SRGB_READ_ENABLE };

float3 SampleLinColor(float2 uv) { return ApplyLinearCurve(Sample(sLDRTexVort, uv).rgb); }

float3 FetchLinColor(int2 pos) { return ApplyLinearCurve(Fetch(sLDRTexVort, pos).rgb); }
