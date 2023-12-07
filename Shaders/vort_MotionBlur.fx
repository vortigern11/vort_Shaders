/*******************************************************************************
    Author: Vortigern
    Sources:
         https://github.com/Kink3d/kMotion/blob/master/Shaders/MotionBlur.shader
         "A Reconstruction Filter for Plausible Motion Blur" by McGuire et al.

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
#include "Includes/vort_MotVectUtils.fxh"
#include "Includes/vort_LDRTex.fxh"

#ifndef V_MOT_BLUR_VECTORS_MODE
    #define V_MOT_BLUR_VECTORS_MODE 0
#endif

#if V_MOT_BLUR_VECTORS_MODE <= 1
    #if V_MOT_BLUR_VECTORS_MODE == 0
        #include "Includes/vort_MotionVectors.fxh"
    #else
        #include "Includes/vort_MotVectTex.fxh"
    #endif

    #define MOT_VECT_SAMP sMotVectTexVort
#elif V_MOT_BLUR_VECTORS_MODE == 2
    namespace Deferred {
        texture MotionVectorsTex { TEX_SIZE(0) TEX_RG16 };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex; };
    }

    #define MOT_VECT_SAMP Deferred::sMotionVectorsTex
#else
    // the names used in qUINT_of, qUINT_motionvectors and other older implementations
    texture2D texMotionVectors { TEX_SIZE(0) TEX_RG16 };
    sampler2D sMotionVectorTex { Texture = texMotionVectors; };

    #define MOT_VECT_SAMP sMotionVectorTex
#endif

namespace MotBlur {

/*******************************************************************************
    Globals
*******************************************************************************/

#define CAT_MOT_BLUR "Motion Blur"

UI_FLOAT(CAT_MOT_BLUR, UI_MB_Amount, "Blur Amount", "Modifies the blur length.", 0.0, 1.0, 0.75)

UI_HELP(
_vort_MotBlur_Help_,
"V_MOT_VECT_DEBUG - 0 or 1\n"
"Shows the motion in colors. Gray means there is no motion, other colors show the direction and amount of motion.\n"
"\n"
"V_MOT_BLUR_VECTORS_MODE - [0 - 3]\n"
"0 - auto include my motion vectors (highly recommended)\n"
"1 - manually use vort_MotionEstimation\n"
"2 - manually use iMMERSE motion vectors\n"
"3 - manually use older motion vectors (qUINT_of, qUINT_motionvectors, etc.)\n"
"\n"
"V_HAS_DEPTH - 0 or 1\n"
"Whether the game has depth (2D or 3D)\n"
"\n"
"V_USE_HW_LIN - 0 or 1\n"
"Toggles hardware linearization. Disable if you use REST addon version older than 1.2.1\n"
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

float Cone(float xy_len, float v_len)
{
    return saturate(1.0 - xy_len * rcp(v_len + EPSILON));
}

float Cylinder(float xy_len, float v_len)
{
    return 1.0 - smoothstep(0.95 * v_len, 1.05 * v_len + EPSILON, xy_len);
}

float2 SoftDepthCompare(float zf, float zb)
{
    static const float rcp_z_extent = 1000.0; // best results
    float x = (zf - zb) * rcp_z_extent;

    // we use positive depth, unlike the research paper
    return saturate(1.0 + float2(x, -x));
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Blur(PS_ARGS3)
{
    // x = motion pixel length, y = linear depth
    float2 center_info = Sample(sInfoTexVort, i.uv).xy;

    if(center_info.x < 1.0) discard;

    static const uint samples = 8;
    float3 center_color = GetColor(i.uv);
    float rand = GetNoise(i.uv) * 0.5;
    float4 color = 0.0;

    // add center color
    color.w = rcp(center_info.x);
    color.rgb = center_color * color.w;

    // faster than dividing `j` inside the loop
    float2 motion = Sample(MOT_VECT_SAMP, i.uv).xy * UI_MB_Amount * rcp(samples);

    // due to circular movement looking bad otherwise,
    // only areas behind the pixel are included in the blur
    [unroll]for(uint j = 1; j <= samples; j++)
    {
        float2 sample_uv = saturate(i.uv - motion * (float(j) - rand));
        float2 sample_info = Sample(sInfoTexVort, sample_uv).xy;
        float2 fb = SoftDepthCompare(center_info.y, sample_info.y);
        float uv_dist = length((sample_uv - i.uv) * BUFFER_SCREEN_SIZE);
        float weight = 0;

        weight += fb.x * Cone(uv_dist, sample_info.x);
        weight += fb.y * Cone(uv_dist, center_info.x);
        weight += 2.0 * (Cylinder(uv_dist, sample_info.x) * Cylinder(uv_dist, center_info.x));

        color += float4(GetColor(sample_uv) * weight, weight);
    }

    o = ApplyGammaCurve(color.rgb * rcp(color.w));
}

void PS_WriteInfo(PS_ARGS2)
{
    o.x = length(Sample(MOT_VECT_SAMP, i.uv).xy * UI_MB_Amount * BUFFER_SCREEN_SIZE);
    o.y = GetLinearizedDepth(i.uv);
}

void PS_Debug(PS_ARGS3) { o = MotVectUtils::Debug(i.uv, MOT_VECT_SAMP, UI_MB_Amount); }

} // namespace end

/*******************************************************************************
    Techniques
*******************************************************************************/

technique vort_MotionBlur
{
    #if V_MOT_BLUR_VECTORS_MODE == 0
        PASS_MOT_VECT
    #endif

    #if V_MOT_VECT_DEBUG
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Debug; }
    #else
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo; RenderTarget = MotBlur::InfoTexVort; }
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }
    #endif
}
