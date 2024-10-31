#pragma once
#include "Includes/vort_Defs.fxh"

texture2D ColorTexVort : COLOR;
sampler2D sColorTexVort { Texture = ColorTexVort; };

float3 SampleLinColor(float2 uv) { return ApplyLinCurve(Sample(sColorTexVort, uv).rgb); }
float3 FetchLinColor(float2 pos) { return ApplyLinCurve(Fetch(sColorTexVort, pos).rgb); }

float3 SampleGammaColor(float2 uv) { return Sample(sColorTexVort, uv).rgb; }
float3 FetchGammaColor(float2 pos) { return Fetch(sColorTexVort, pos).rgb; }
