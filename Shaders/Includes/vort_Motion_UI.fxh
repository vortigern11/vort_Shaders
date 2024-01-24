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

#if V_MV_MODE == 0
    #ifndef V_MV_DEBUG
        #define V_MV_DEBUG 0
    #endif
#endif

#if V_ENABLE_MOT_BLUR
    UI_FLOAT(CAT_MOT, UI_MB_Amount, "Motion Blur Length", "Values above 1.0 can be used for testing", 0.0, 1.0, 0.5)
#endif

#if V_ENABLE_TAA
    UI_FLOAT(CAT_MOT, UI_TAA_Jitter, "TAA Static AA", "How much to shift every pixel position each frame", 0.0, 1.0, 0.25)
    UI_FLOAT(CAT_MOT, UI_TAA_Alpha, "TAA Frame Blend", "Higher values reduce blur, but reduce AA as well", 0.0, 1.0, 0.5)
#endif

UI_HELP(
_vort_MotionEffects_Help_,
"V_MV_MODE - [0 - 3]\n"
"0 - auto include my motion vectors (highly recommended)\n"
"1 - manually use iMMERSE motion vectors\n"
"2 - manually use other motion vectors (qUINT_of, qUINT_motionvectors, DRME, etc.)\n"
"\n"
"V_MV_DEBUG - 0 or 1\n"
"Shows the motion in colors. Gray means there is no motion, other colors show the direction and amount of motion.\n"
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
    sampler2D sMotVectTexVort { Texture = MotVectTexVort; };

    #define MV_TEX MotVectTexVort
    #define MV_SAMP sMotVectTexVort
#elif V_MV_MODE == 1
    namespace Deferred {
        texture MotionVectorsTex { TEX_SIZE(0) TEX_RG16 };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex; };
    }

    #define MV_TEX Deferred::MotionVectorsTex
    #define MV_SAMP Deferred::sMotionVectorsTex
#else
    texture2D texMotionVectors { TEX_SIZE(0) TEX_RG16 };
    sampler2D sMotionVectorTex { Texture = texMotionVectors; };

    #define MV_TEX texMotionVectors
    #define MV_SAMP sMotionVectorTex
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float2 SampleMotion(float2 uv)
{
    float2 motion = Sample(MV_SAMP, uv).xy;

    // negate the random noise
    return motion * (length(motion * BUFFER_SCREEN_SIZE) > 2.0);
}

float2 FetchMotion(int2 pos)
{
    float2 motion = Fetch(MV_SAMP, pos).xy;

    // negate the random noise
    return motion * (length(motion * BUFFER_SCREEN_SIZE) > 2.0);
}
