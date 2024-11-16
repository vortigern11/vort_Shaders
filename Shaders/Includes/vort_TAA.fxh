/*******************************************************************************
    Author: Vortigern
    Sources:
    https://www.shadertoy.com/view/DsfGWX
    https://alextardif.com/TAA.html
    https://www.elopezr.com/temporal-aa-and-the-quest-for-the-holy-trail/
    and various other places

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
#include "Includes/vort_Depth.fxh"
#include "Includes/vort_ColorTex.fxh"
#include "Includes/vort_Motion_UI.fxh"
#include "Includes/vort_MotionUtils.fxh"

namespace TAA {

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture TAAMVTexVort { TEX_SIZE(0) TEX_RG16 };
sampler sTAAMVTexVort { Texture = TAAMVTexVort; SAM_POINT };

texture PrevColorTexVort { TEX_SIZE(0) TEX_RGBA16 };
sampler sPrevColorTexVort { Texture = PrevColorTexVort; };

/*******************************************************************************
    Functions
*******************************************************************************/

// completely wrong, but users keep asking for it, so I guess it stays.
float4 GetJitter()
{
    static const float2 offs[4] = {
        float2(-0.5, -0.25), float2(-0.25, 0.5), float2(0.5, 0.25), float2(0.25, -0.5)
    };

    float4 jitter = 0;

    if(frame_count > 0)
        jitter = float4(offs[frame_count % 4], offs[(frame_count - 1) % 4]) * BUFFER_PIXEL_SIZE.xyxy;

    // reduce jitter to make it unnoticable and to have sharper result
    return jitter * UI_TAA_Jitter;
}

float3 ClipToAABB(float3 old_c, float3 new_c, float3 avg, float3 sigma)
{
    float3 r = old_c - new_c;
    float3 m = (avg + sigma) - new_c;
    float3 n = (avg - sigma) - new_c;
    static const float eps = 1e-4;

    r *= (r > m + eps) ? (m / r) : 1.0;
    r *= (r < n - eps) ? (n / r) : 1.0;

    return new_c + r;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Main(PS_ARGS3)
{
    float3 curr_c = RGBToYCoCg(SampleLinColor(i.uv));
    float3 avg_c = curr_c;
    float3 var_c = curr_c * curr_c;

    static const float inv_samples = 1.0 / 5.0;
    static const float2 offs[4] = { float2(0, 1), float2(-1, 0), float2(1, 0), float2(0, -1) };

    [loop]for(int j = 0; j < 4; j++)
    {
        float2 uv_offs = offs[j] * BUFFER_PIXEL_SIZE;
        float3 sample_c = RGBToYCoCg(SampleLinColor(i.uv + uv_offs));

        avg_c += sample_c;
        var_c += sample_c * sample_c;
    }

    float2 prev_uv = i.uv - GetJitter().zw;
    float2 motion = Sample(sTAAMVTexVort, prev_uv).xy;

    prev_uv += motion;

    bool is_first = Sample(sPrevColorTexVort, prev_uv).a < 1.0;

    // no prev color yet or motion leads to outside of screen coords
    if(is_first || !ValidateUV(prev_uv)) discard;

    float4 prev_info = SampleBicubic(sPrevColorTexVort, prev_uv);
    float3 prev_c = RGBToYCoCg(ApplyLinCurve(prev_info.rgb));

    avg_c *= inv_samples;
    var_c *= inv_samples;

    // sharpen
    curr_c = lerp(curr_c, curr_c + curr_c - avg_c, UI_TAA_Sharpen);

    float3 sigma = sqrt(abs(var_c - avg_c * avg_c));
    float3 min_c = avg_c - sigma;
    float3 max_c = avg_c + sigma;

    prev_c = ClipToAABB(prev_c, clamp(avg_c, min_c, max_c), avg_c, sigma);
    curr_c = lerp(prev_c, curr_c, UI_TAA_Alpha);
    curr_c = ApplyGammaCurve(YCoCgToRGB(curr_c));

    o = curr_c;
}

void PS_WriteMV(PS_ARGS2)
{
    float3 closest = float3(i.uv, GetDepth(i.uv));

    // apply min filter to remove some artifacts
    [loop]for(uint j = 1; j < S_BOX_OFFS1; j++)
    {
        float2 sample_uv = i.uv + BOX_OFFS1[j] * BUFFER_PIXEL_SIZE;
        float sample_z = GetDepth(sample_uv);

        if(sample_z < closest.z) closest = float3(sample_uv, sample_z);
    }

    float2 motion = SampleMotion(closest.xy);
    float2 px_motion = motion * BUFFER_SCREEN_SIZE;
    float sq_len = dot(px_motion, px_motion);

    // remove subpixel results
    o.xy = motion * (sq_len >= 1.0);
}

void PS_WritePrevColor(PS_ARGS4) { o = float4(SampleGammaColor(i.uv + GetJitter().xy).rgb, 1.0); }

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_TAA \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_WriteMV; RenderTarget = TAA::TAAMVTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_Main; } \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_WritePrevColor; RenderTarget = TAA::PrevColorTexVort; }

} // namespace end
