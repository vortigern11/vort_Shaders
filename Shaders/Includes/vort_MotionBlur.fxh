/*******************************************************************************
    Author: Vortigern
    Source: "A Reconstruction Filter for Plausible Motion Blur" by McGuire et al.

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
#include "Includes/vort_BlueNoise.fxh"
#include "Includes/vort_Motion_UI.fxh"

namespace MotBlur {

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RG16 };
sampler2D sInfoTexVort { Texture = InfoTexVort; };

/*******************************************************************************
    Functions
*******************************************************************************/

float2 GetMotion(float2 uv)
{
    return Sample(MV_SAMP, uv).xy * UI_MB_MotLen;
}

float3 GetColor(float2 uv)
{
    return ApplyLinearCurve(Sample(sLDRTexVort, uv).rgb);
}

float SmoothCone(float xy_len, float v_len)
{
    float w = saturate(1.0 - xy_len * RCP(v_len));

    // reduce the weight the further the sample is from center
    return w * w;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Blur(PS_ARGS3)
{
    // x = motion pixel length, y = linear depth
    float2 center_info = Sample(sInfoTexVort, i.uv).xy;

    if(center_info.x < 2.0) discard;

    float samples = clamp(center_info.x * 0.5, 2.0, 16.0);
    int half_samples = floor(samples * 0.5);
    float3 center_color = GetColor(i.uv);
    float2 rand = GetBlueNoise(i.vpos.xy).xy;
    float2 motion = GetMotion(i.uv);
    float4 color = 0;

    // add center color
    color.w = RCP(center_info.x);
    color.rgb = center_color * color.w;

    // faster than dividing `j` inside the loop
    motion *= rcp(samples);

    // circular movement looks bad anyways
    // might as well blur in both directions
    [loop]for(int m = -1; m <= 1; m += 2)
    [loop]for(int j = 1; j <= half_samples; j++)
    {
        float2 sample_uv = saturate(i.uv + motion * m * (j - rand));
        float2 sample_info = Sample(sInfoTexVort, sample_uv).xy;
        float uv_dist = length((sample_uv - i.uv) * BUFFER_SCREEN_SIZE);
        float cmpl = center_info.y < sample_info.y ? center_info.x : sample_info.x;
        float weight = SmoothCone(uv_dist, cmpl);

        color += float4(GetColor(sample_uv) * weight, weight);
    }

    o = ApplyGammaCurve(color.rgb * rcp(color.w));
}

void PS_WriteInfo(PS_ARGS2)
{
    o.x = length(GetMotion(i.uv) * BUFFER_SCREEN_SIZE);
    o.y = GetLinearizedDepth(i.uv);
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MOT_BLUR \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo; RenderTarget = MotBlur::InfoTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }

} // namespace end
