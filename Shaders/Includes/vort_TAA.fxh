/*******************************************************************************
  Author: Vortigern
  Adapted from: https://www.shadertoy.com/view/DsfGWX

  License: MIT, Copyright (c) 2023 Vortigern

  MIT License

  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the "Software"),
  to deal in the Software without restriction, including without limitation
  the rights to use, copy, modify, merge, publish, distribute, sublicense,
  and/or sell copies of the Software, and to permit persons to whom the
  Software is furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.
*******************************************************************************/

#pragma once
#include "Includes/vort_Defs.fxh"
#include "Includes/vort_LDRTex.fxh"
#include "Includes/vort_Motion_UI.fxh"

namespace TAA {

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture FeatureTexVort { TEX_SIZE(0) TEX_RGBA16 };
sampler sFeatureTexVort { Texture = FeatureTexVort; };

texture PrevFeatureTexVort { TEX_SIZE(0) TEX_RGBA16 };
sampler sPrevFeatureTexVort { Texture = PrevFeatureTexVort; };

/*******************************************************************************
    Functions
*******************************************************************************/

float3 GetLinColor(float2 uv)
{
    return ApplyLinearCurve(Sample(sLDRTexVort, uv).rgb);
}

float3 ClipToAABB(float3 old_c, float3 new_c, float3 avg, float3 sigma)
{
    float3 r = old_c - new_c;
    float3 m = (avg + sigma) - new_c;
    float3 n = (avg - sigma) - new_c;
    static const float eps = 1e-4;

    if (r.x > m.x + eps) r *= (m.x / r.x);
    if (r.y > m.y + eps) r *= (m.y / r.y);
    if (r.z > m.z + eps) r *= (m.z / r.z);

    if (r.x < n.x - eps) r *= (n.x / r.x);
    if (r.y < n.y - eps) r *= (n.y / r.y);
    if (r.z < n.z - eps) r *= (n.z / r.z);

    return new_c + r;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_WriteFeature(PS_ARGS3) { o = RGBToYCoCg(GetLinColor(i.uv)); }

void PS_CopyColor(PS_ARGS3) { o = GetLinColor(i.uv); }

void PS_Main(PS_ARGS3)
{
    int seed = frame_count % 8 + 1;

    float2 jitter = Halton2(seed) - 0.5;;
    float3 curr = Sample(sFeatureTexVort, saturate(i.uv - jitter * BUFFER_PIXEL_SIZE)).rgb;
    float3 avg_c = curr;
    float3 var_c = curr * curr;

    static const float fifth = 1.0 / 5.0;
    static const int2 offs[4] = { int2(1, 0), int2(0, -1), int2(0, 1), int2(-1, 0) };

    [unroll]for(int j = 0; j < 4; j++)
    {
        float3 sample_c = Fetch(sFeatureTexVort, i.vpos.xy + offs[j]).rgb;

        avg_c += sample_c;
        var_c += sample_c * sample_c;
    }

    avg_c *= fifth;
    var_c *= fifth;

    float3 sigma = sqrt(max(0.0, var_c - avg_c * avg_c));
    float3 min_c = avg_c - sigma;
    float3 max_c = avg_c + sigma;

    float2 min_mot = BUFFER_PIXEL_SIZE * 0.5;
    float2 small_noise = lerp(-min_mot, min_mot, QRand(GetBlueNoise(i.vpos.xy), seed).xy);
    float2 motion = Sample(MV_SAMP, i.uv).xy * UI_TAA_MotLen + small_noise;
    float3 hist = SampleBicubic(sPrevFeatureTexVort, i.uv + motion).rgb;

    hist = RGBToYCoCg(hist);
    hist = ClipToAABB(hist, clamp(avg_c, min_c, max_c), avg_c, sigma);
    hist = YCoCgToRGB(lerp(hist, curr, UI_TAA_Alpha));

    o = ApplyGammaCurve(hist);
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_TAA \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_WriteFeature; RenderTarget = TAA::FeatureTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_Main; SRGB_WRITE_ENABLE } \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_CopyColor; RenderTarget = TAA::PrevFeatureTexVort; }

} // namespace end

technique TAA_Prepass < hidden = true; enabled = true; timeout = 1; >
{
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_CopyColor; RenderTarget = TAA::PrevFeatureTexVort; }
}
