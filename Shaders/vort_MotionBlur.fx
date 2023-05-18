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
#include "Includes/vort_MotionVectors.fxh"
#include "Includes/vort_MotVectTex.fxh"
#include "Includes/vort_LDRTex.fxh"

namespace MotBlur {

/*******************************************************************************
    Globals
*******************************************************************************/

#ifndef V_MOT_BLUR_DEBUG
    #define V_MOT_BLUR_DEBUG 0
#endif

#define CAT_MOT_BLUR "Motion Blur"

UI_FLOAT(CAT_MOT_BLUR, UI_MB_Amount, "Blur Amount", "The amount of motion blur.", 0.0, 1.0, 0.5)

UI_HELP(
_vort_HDR_Help_,
"V_MOT_BLUR_DEBUG - 0 or 1\n"
"Shows the motion in colors. Gray means there is no motion, other colors show the direction and amount of motion.\n"
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

void PS_Blur(PS_ARGS4)
{
    float2 motion = Sample(sMotVectTexVort, i.uv).xy * UI_MB_Amount;

    // discard if less than 1 pixel diff
    if(length(motion * BUFFER_SCREEN_SIZE) < 1.0) discard;

    static const uint half_samples = 6;
    float inv_samples = RCP(half_samples * 2.0);
    float rand = GetNoise(i.uv);
    float3 color = 0;

    motion *= inv_samples;

    [unroll]for(uint j = 0; j < half_samples; j++)
    {
        color += GetColor(i.uv - motion * (float(j) - rand + 1.0));
        color += GetColor(i.uv + motion * (float(j) + rand));
    }

    o = float4(ApplyGammaCurve(color * inv_samples), 1);
}

void PS_Debug(PS_ARGS3) { o = MotVect::Debug(i.uv, UI_MB_Amount); }

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
    PASS_MOT_VECT

    #if V_MOT_BLUR_DEBUG
        PASS_MOT_BLUR_DEBUG
    #else
        PASS_MOT_BLUR
    #endif
}
