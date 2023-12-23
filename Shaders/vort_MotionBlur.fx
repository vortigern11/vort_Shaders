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

#include "Includes/vort_Defs.fxh"
#include "Includes/vort_Depth.fxh"
#include "Includes/vort_LDRTex.fxh"

#ifndef V_MB_VECTORS_MODE
    #define V_MB_VECTORS_MODE 0
#endif

#if V_MB_VECTORS_MODE <= 1
    #if V_MB_VECTORS_MODE == 0
        #include "Includes/vort_MotionVectors.fxh"
    #else
        #include "Includes/vort_MotVectTex.fxh"
    #endif

    #define MV_SAMP sMotVectTexVort
#elif V_MB_VECTORS_MODE == 2
    namespace Deferred {
        texture MotionVectorsTex { TEX_SIZE(0) TEX_RG16 };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex; };
    }

    #define MV_SAMP Deferred::sMotionVectorsTex
#else
    // the names used in qUINT_of, qUINT_motionvectors and other older implementations
    texture2D texMotionVectors { TEX_SIZE(0) TEX_RG16 };
    sampler2D sMotionVectorTex { Texture = texMotionVectors; };

    #define MV_SAMP sMotionVectorTex
#endif

namespace MotBlur {

/*******************************************************************************
    Globals
*******************************************************************************/

#define CAT_MB "Motion Blur"

UI_FLOAT(CAT_MB, UI_MB_BlurAmount, "Blur Amount", "Changes the amount of blur.", 0.0, 5.0, 1.0)

UI_HELP(
_vort_MotBlur_Help_,
"V_MV_DEBUG - 0 or 1\n"
"Shows the motion in colors. Gray means there is no motion, other colors show the direction and amount of motion.\n"
"\n"
"V_MV_EXTRA_QUALITY - 0 or 1\n"
"If set to 1, will sacrifice performance for higher quality vectors.\n"
"Isn't needed, but if you have RTX 9999 GPU, might as well :).\n"
"\n"
"V_MB_VECTORS_MODE - [0 - 3]\n"
"0 - auto include my motion vectors (highly recommended)\n"
"1 - manually use vort_MotionEstimation\n"
"2 - manually use iMMERSE motion vectors\n"
"3 - manually use older motion vectors (qUINT_of, qUINT_motionvectors, etc.)\n"
"\n"
"V_HAS_DEPTH - 0 or 1\n"
"Whether the game has depth (2D or 3D)\n"
"\n"
"V_USE_HW_LIN - 0 or 1\n"
"Toggle hardware linearization (better performance).\n"
"Disable if you have color issues due to some bug (like older REST versions).\n"
)

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RG16 };
sampler2D sInfoTexVort { Texture = InfoTexVort; };

/*******************************************************************************
    Functions
*******************************************************************************/

float3 GetColor(float2 uv)
{
    return ApplyLinearCurve(Sample(sLDRTexVort, uv).rgb);
}

float SmoothCone(float xy_len, float v_len)
{
    float w = saturate(1.0 - xy_len * RCP(v_len));

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

    float samples = min(center_info.x, 16.0);
    int half_samples = floor(samples * 0.5);
    float3 center_color = GetColor(i.uv);
    float rand = GetNoise(i.uv) * 0.5;
    float2 motion = Sample(MV_SAMP, i.uv).xy * UI_MB_BlurAmount;
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
        float2 sample_uv = saturate(i.uv + motion * m * (float(j) - rand));
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
    o.x = length(Sample(MV_SAMP, i.uv).xy * UI_MB_BlurAmount * BUFFER_SCREEN_SIZE);
    o.y = GetLinearizedDepth(i.uv);
}

} // namespace end

/*******************************************************************************
    Techniques
*******************************************************************************/

technique vort_MotionBlur
{
    #if V_MB_VECTORS_MODE == 0
        PASS_MV
    #endif

    #if V_MB_VECTORS_MODE == 0 && V_MV_DEBUG
        PASS_MV_DEBUG
    #else
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo; RenderTarget = MotBlur::InfoTexVort; }
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }
    #endif
}
