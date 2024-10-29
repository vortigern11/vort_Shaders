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
#include "Includes/vort_Depth.fxh"
#include "Includes/vort_Motion_UI.fxh"

/*******************************************************************************
    Globals
*******************************************************************************/

#if V_MV_USE_REST > 0
    uniform float4x4 matInvViewProj < source = "mat_InvViewProj"; >;
    uniform float4x4 matPrevViewProj < source = "mat_PrevViewProj"; >;
#endif

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

#if V_MV_MODE == 1
    texture2D MotVectTexVort { TEX_SIZE(0) TEX_RG16 };
    sampler2D sMotVectTexVort { Texture = MotVectTexVort; };

    #define MV_SAMP sMotVectTexVort
#elif V_MV_MODE == 2
    namespace Deferred {
        texture MotionVectorsTex { TEX_SIZE(0) TEX_RG16 };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex; };
    }

    #define MV_SAMP Deferred::sMotionVectorsTex
#elif V_MV_MODE == 3
    texture2D texMotionVectors { TEX_SIZE(0) TEX_RG16 };
    sampler2D sMotionVectorTex { Texture = texMotionVectors; };

    #define MV_SAMP sMotionVectorTex
#endif

#if V_MV_USE_REST > 0
    texture2D RESTMVTexVort : MOTION;
    sampler2D sRESTMVTexVort { Texture = RESTMVTexVort; };
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

#if V_MV_USE_REST > 0
float2 GetCameraVelocity(float2 uv)
{
    // TODO: maybe switch
    /* float depth = GetRawDepth(uv); */
    float depth = GetDepth(uv);
    float2 curr_screen = (uv * 2.0 - 1.0) * float2(1, -1);
    float4 curr_clip = float4(curr_screen, depth, 1);

    float4x4 mat_clip_to_prev_clip = mul(matInvViewProj, matPrevViewProj);
    float4 prev_clip = mul(curr_clip, mat_clip_to_prev_clip);

    float2 prev_screen = prev_clip.xy * RCP(prev_clip.w);
    float2 v = curr_screen - prev_screen;

    // normalize
    v *= float2(-0.5, 0.5);

    return v;
}

float2 DecodeVelocity(float2 alt_motion, float2 uv)
{
    float2 v = Sample(sRESTMVTexVort, uv).xy;

#if V_MV_USE_REST == 1 // Generic
    v *= float2(-0.5, 0.5);
#elif V_MV_USE_REST == 2 // Unreal Engine games
    // whether there is velocity stored because the object is dynamic
    // or we have to compute static velocity
    if(v.x > 0.0)
    {
        // uncomment if velocity is stored as uint
        /* v /= 65535.0; */

        static const float inv_div = 1.0 / (0.499 * 0.5);
        static const float h = 32767.0 / 65535.0;

        v = (v - h) * inv_div;

        // uncoment if gamma was encoded
        /* v = (v * abs(v)) * 0.5; */

        // normalize
        v *= float2(-0.5, 0.5);
    }
    else
    {
    #ifdef MV_SAMP
        v = alt_motion;
    #else
        v = GetCameraVelocity(uv);
    #endif
    }
#elif V_MV_USE_REST == 3 // CryEngine games
    if(v.x != 0)
    {
        v = (v - 127.0 / 255.0) * 2.0;
        v = (v * v) * (v > 0.0 ? float2(1, 1) : float2(-1, -1));
    }
    else
    {
    #ifdef MV_SAMP
        v = alt_motion;
    #else
        v = GetCameraVelocity(uv);
    #endif
    }
#endif

    return v;
}
#endif

float2 SampleMotion(float2 uv)
{
    float2 motion = 0;

#ifdef MV_SAMP
    motion = Sample(MV_SAMP, uv).xy;
#endif

#if V_MV_USE_REST > 0
    motion = DecodeVelocity(motion, uv);
#endif

    return motion;
}

float3 DebugMotion(float2 motion)
{
    float angle = atan2(motion.y, motion.x);
    float3 rgb = saturate(3.0 * abs(2.0 * frac(angle / DOUBLE_PI + float3(0.0, -A_THIRD, A_THIRD)) - 1.0) - 1.0);

    return lerp(0.5, rgb, saturate(log(1 + length(motion) * 400.0  / frame_time)));
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_DebugMV(PS_ARGS3) { o = DebugMotion(SampleMotion(i.uv)); }

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MV_DEBUG \
    pass { VertexShader = PostProcessVS; PixelShader = PS_DebugMV; }
