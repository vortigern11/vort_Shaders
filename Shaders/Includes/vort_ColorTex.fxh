#pragma once
#include "Includes/vort_Defs.fxh"

namespace Color {
    texture2D ColorTex : COLOR;
    sampler2D sColorTex { Texture = ColorTex; };
}

float3 SampleLinColor(float2 uv) { return ApplyLinCurve(Sample(Color::sColorTex, uv).rgb); }
float3 FetchLinColor(float2 pos) { return ApplyLinCurve(Fetch(Color::sColorTex, pos).rgb); }

float3 SampleGammaColor(float2 uv) { return Sample(Color::sColorTex, uv).rgb; }
float3 FetchGammaColor(float2 pos) { return Fetch(Color::sColorTex, pos).rgb; }
