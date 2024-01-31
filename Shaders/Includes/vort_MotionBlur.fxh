/*******************************************************************************
    Author: Vortigern
    Sources:
    "A Reconstruction Filter for Plausible Motion Blur" by McGuire et al.
    Next-Generation-Post-Processing-in-Call-of-Duty-Advanced-Warfare-v18

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
#include "Includes/vort_LDRTex.fxh"
#include "Includes/vort_Motion_UI.fxh"
#include "Includes/vort_Tonemap.fxh"

namespace MotBlur {

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RG16 };
sampler2D sInfoTexVort { Texture = InfoTexVort; };

// tried with max neighbour tiles, but there were issues either
// due to implementation or imperfect motion vectors

/*******************************************************************************
    Functions
*******************************************************************************/

float3 GetColor(float2 uv)
{
    float3 c = SampleLinColor(uv);

#if IS_SRGB
    c = InverseLottes(c);
#endif

    return c;
}

float3 PutColor(float3 c)
{
#if IS_SRGB
    c = ApplyLottes(c);
#endif

    return ApplyGammaCurve(c);
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Blur(PS_ARGS3)
{
    // x = motion pixel length, y = depth
    float2 center_info = Sample(sInfoTexVort, i.uv).xy;

    if(center_info.x < 1.0) discard; // changing to higher can worsen result

    int half_samples = clamp(floor(center_info.x * 0.5), 4, 16); // for perf reasons
    float inv_half_samples = rcp(float(half_samples));
    static const float depth_scale = 1000.0;

    float2 motion = SampleMotion(i.uv).xy * UI_MB_Amount;
    float rand = GetInterGradNoise(i.vpos.xy + frame_count % 16) * 0.5; // don't touch
    float4 color = 0;

    [loop]for(int j = 1; j <= half_samples; j++)
    {
        float2 offs = motion * (float(j) - rand) * inv_half_samples;
        float offs_len = length(offs * BUFFER_SCREEN_SIZE);

        float2 sample_uv1 = saturate(i.uv + offs);
        float2 sample_uv2 = saturate(i.uv - offs);

        float2 sample_info1 = Sample(sInfoTexVort, sample_uv1).xy;
        float2 sample_info2 = Sample(sInfoTexVort, sample_uv2).xy;

        float2 depthcmp1 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info1.y - center_info.y));
        float2 depthcmp2 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info2.y - center_info.y));

        offs_len = max(0.0, offs_len - 1.0); // modify for spreadcmp
        float2 spreadcmp1 = saturate(float2(center_info.x, sample_info1.x) - offs_len);
        float2 spreadcmp2 = saturate(float2(center_info.x, sample_info2.x) - offs_len);

        float weight1 = dot(depthcmp1, spreadcmp1);
        float weight2 = dot(depthcmp2, spreadcmp2);

        // mirror filter to better guess the background
        bool2 mirror = bool2(sample_info1.y > sample_info2.y, sample_info2.x > sample_info1.x);
        weight1 = all(mirror) ? weight2 : weight1;
        weight2 = any(mirror) ? weight2 : weight1;

        color += weight1 * float4(GetColor(sample_uv1), 1.0);
        color += weight2 * float4(GetColor(sample_uv2), 1.0);
    }

    color *= inv_half_samples * 0.5;
    color.rgb += (1.0 - color.w) * GetColor(i.uv);

    o = PutColor(color.rgb);
}

void PS_WriteInfo(PS_ARGS2)
{
    o.x = length(SampleMotion(i.uv).xy * UI_MB_Amount * BUFFER_SCREEN_SIZE);
    o.y = GetLinearizedDepth(i.uv);
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MOT_BLUR \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo; RenderTarget = MotBlur::InfoTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }

} // namespace end
