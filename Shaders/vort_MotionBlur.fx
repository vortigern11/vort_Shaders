/*******************************************************************************
    Author: Vortigern
    Based on: https://github.com/Kink3d/kMotion/blob/master/Shaders/MotionBlur.shader

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
#include "Includes/vort_MotVectTex.fxh"
#include "Includes/vort_LDRTex.fxh"

#ifndef V_MOT_BLUR_VECTORS_MODE
    #define V_MOT_BLUR_VECTORS_MODE 0
#endif

#if V_MOT_BLUR_VECTORS_MODE <= 1
    #if V_MOT_BLUR_VECTORS_MODE == 0
        #include "Includes/vort_MotionVectors.fxh"
    #endif

    #define MB_MOT_VECT_SAMP MOT_VECT_SAMP
#elif V_MOT_BLUR_VECTORS_MODE == 2
    namespace Deferred {
        texture MotionVectorsTex { TEX_SIZE(0) TEX_RG16 };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex; };
    }

    #define MB_MOT_VECT_SAMP Deferred::sMotionVectorsTex
#endif

namespace MotBlur {

/*******************************************************************************
    Globals
*******************************************************************************/

#ifndef V_MOT_BLUR_DEBUG
    #define V_MOT_BLUR_DEBUG 0
#endif

#define CAT_MOT_BLUR "Motion Blur"

UI_FLOAT(CAT_MOT_BLUR, UI_MB_Amount, "Blur Amount", "If motion vectors are setup correctly, leave at 1.0", 0.0, 2.0, 1.0)

UI_HELP(
_vort_MotBlur_Help_,
"V_MOT_BLUR_DEBUG - 0 or 1\n"
"Shows the motion in colors. Gray means there is no motion, other colors show the direction and amount of motion.\n"
"\n"
"V_MOT_BLUR_VECTORS_MODE - [0 - 3]\n"
"0 - auto include my motion vectors (highly recommended)\n"
"1 - manually use motion vectors (mine, qUINT_motionvectors, etc.)\n"
"2 - manually use iMMERSE motion vectors\n"
"\n"
"V_USE_HW_LIN - 0 or 1\n"
"Toggles hardware linearization. Disable if you use REST addon version older than 1.2.1\n"
)

/*******************************************************************************
    Functions
*******************************************************************************/

float3 GetColor(float2 uv)
{
    return ApplyLinearCurve(Sample(sLDRTexVort, uv).rgb);
}

/*******************************************************************************
    Shaders
*******************************************************************************/

// due to circular movement looking bad otherwise,
// only areas behind the pixel are included in the blur
void PS_Blur(PS_ARGS4)
{
    float2 motion = Sample(MB_MOT_VECT_SAMP, i.uv).xy * UI_MB_Amount;
    float motion_pixel_length = length(motion * BUFFER_SCREEN_SIZE);

    if(motion_pixel_length < 1.0) discard;

    static const uint samples = 15;
    float rand = -GetNoise(i.uv); // -1.0 <-> 0
    float3 center_color = GetColor(i.uv);
    float center_z = GetLinearizedDepth(i.uv);
    float3 color = center_color;

    // faster than dividing `j` inside the loop
    motion *= rcp(samples);

    [unroll]for(uint j = 1; j <= samples; j++)
    {
        float2 uv = i.uv - motion * (j + rand);
        float sample_z = GetLinearizedDepth(uv);

        // don't use pixels which are closer to the camera than the center pixel
        color += ((center_z - sample_z) > 0.005) ? center_color : GetColor(uv);
    }

    // divide by samples + 1, because center_color is used too
    o = float4(ApplyGammaCurve(color * rcp(samples + 1)), 1);
}

void PS_Debug(PS_ARGS3) { o = DebugMotion(i.uv, MB_MOT_VECT_SAMP); }

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MOT_BLUR \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }

#define PASS_MOT_BLUR_DEBUG \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Debug; }

} // namespace end

/*******************************************************************************
    Techniques
*******************************************************************************/

technique vort_MotionBlur
{
    #if V_MOT_BLUR_VECTORS_MODE == 0
        PASS_MOT_VECT
    #endif

    #if V_MOT_BLUR_DEBUG
        PASS_MOT_BLUR_DEBUG
    #else
        PASS_MOT_BLUR
    #endif
}
