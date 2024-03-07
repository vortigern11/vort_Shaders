#pragma once
#include "Includes/vort_Defs.fxh"

texture2D ColorTexVort : COLOR;
sampler2D sColorTexVort { Texture = ColorTexVort; SRGB_READ_ENABLE };
sampler2D sGammaColorTexVort { Texture = ColorTexVort; };

float3 SampleLinColor(float2 uv) { return ApplyLinearCurve(Sample(sColorTexVort, uv).rgb); }
float3 FetchLinColor(float2 pos) { return ApplyLinearCurve(Fetch(sColorTexVort, pos).rgb); }

float3 SampleGammaColor(float2 uv) { return Sample(sGammaColorTexVort, uv).rgb; }
float3 FetchGammaColor(float2 pos) { return Fetch(sGammaColorTexVort, pos).rgb; }
