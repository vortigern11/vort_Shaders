#pragma once
#include "Includes/vort_Defs.fxh"

texture2D ColorTexVort : COLOR;
sampler2D sColorTexVort { Texture = ColorTexVort; SRGB_READ_ENABLE };

float3 SampleLinColor(float2 uv) { return ApplyLinearCurve(Sample(sColorTexVort, uv).rgb); }

float3 FetchLinColor(int2 pos) { return ApplyLinearCurve(Fetch(sColorTexVort, pos).rgb); }
