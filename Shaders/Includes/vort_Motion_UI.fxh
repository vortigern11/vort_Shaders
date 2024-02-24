/*******************************************************************************
    Author: Vortigern

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

/*******************************************************************************
    Globals
*******************************************************************************/

#ifndef V_MV_MODE
    #define V_MV_MODE 0
#endif

#ifndef V_ENABLE_MOT_BLUR
    #define V_ENABLE_MOT_BLUR 0
#endif

#ifndef V_ENABLE_TAA
    #define V_ENABLE_TAA 0
#endif

#define CAT_MOT "Motion Effects"

#if V_ENABLE_MOT_BLUR
    UI_BOOL(CAT_MOT, UI_MB_Debug, "Debug Motion Blur", "", false)
    UI_FLOAT(CAT_MOT, UI_MB_Length, "Motion Blur Length", "Controls the amount of blur.", 0.0, 2.0, 1.0)
#endif

#if V_ENABLE_TAA
    UI_FLOAT(CAT_MOT, UI_TAA_Alpha, "TAA Frame Blend", "Higher values reduce blur, but reduce AA as well", 0.05, 1.0, 0.333)
#endif

UI_HELP(
_vort_MotionEffects_Help_,
"V_MV_MODE - [0 - 3]\n"
"0 - auto include my motion vectors (highly recommended)\n"
"1 - manually use iMMERSE motion vectors\n"
"2 - manually use other motion vectors (qUINT_of, qUINT_motionvectors, DRME, etc.)\n"
"3 - manually setup in-game's motion vectors using the REST addon\n"
"\n"
"V_ENABLE_MOT_BLUR - 0 or 1\n"
"Toggle Motion Blur off or on\n"
"\n"
"V_ENABLE_TAA - 0 or 1\n"
"Toggle TAA off or on\n"
"Make sure some type of AA is enabled (like FXAA, SMAA, CMAA, etc.)\n"
"You could use Marty's iMMERSE_SMAA or LoL's CMAA_2\n"
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

#if V_MV_MODE == 0
    texture2D MotVectTexVort { TEX_SIZE(0) TEX_RG16 };
    sampler2D sMotVectTexVort { Texture = MotVectTexVort; SAM_POINT };

    #define MV_TEX MotVectTexVort
    #define MV_SAMP sMotVectTexVort
#elif V_MV_MODE == 1
    namespace Deferred {
        texture MotionVectorsTex { TEX_SIZE(0) TEX_RG16 };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex; SAM_POINT };
    }

    #define MV_TEX Deferred::MotionVectorsTex
    #define MV_SAMP Deferred::sMotionVectorsTex
#elif V_MV_MODE == 2
    texture2D texMotionVectors { TEX_SIZE(0) TEX_RG16 };
    sampler2D sMotionVectorTex { Texture = texMotionVectors; SAM_POINT };

    #define MV_TEX texMotionVectors
    #define MV_SAMP sMotionVectorTex
#elif V_MV_MODE == 3
    texture2D RESTMVTexVort : MOTIONVECTORS;
    sampler2D sRESTMVTexVort { Texture = RESTMVTexVort; SAM_POINT };

    #define MV_TEX RESTMVTexVort
    #define MV_SAMP sRESTMVTexVort
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float2 SampleMotion(float2 uv)
{
    float2 motion = Sample(MV_SAMP, uv).xy;

#if V_MV_MODE == 3
    // fix the in-game motion vectors
    motion *= float2(-1,1) * 0.5;
#endif

    return motion;
}

float2 FetchMotion(int2 pos)
{
    float2 motion = Fetch(MV_SAMP, pos).xy;

#if V_MV_MODE == 3
    // fix the in-game motion vectors
    motion *= float2(-1,1) * 0.5;
#endif

    return motion;
}

float3 DebugMotion(float2 uv)
{
    float2 motion = SampleMotion(uv);
    float angle = atan2(motion.y, motion.x);
    float3 rgb = saturate(3.0 * abs(2.0 * frac(angle / DOUBLE_PI + float3(0.0, -A_THIRD, A_THIRD)) - 1.0) - 1.0);

    return lerp(0.5, rgb, saturate(length(motion) * 100));
}
