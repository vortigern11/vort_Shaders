#pragma once
#include "Includes/vort_Defs.fxh"

// the names used in qUINT_of, qUINT_motionvectors and other older implementations
texture2D texMotionVectors { TEX_SIZE(0) TEX_RG16 };
sampler2D sMotionVectorTex { Texture = texMotionVectors; };

#define MOT_VECT_TEX texMotionVectors
#define MOT_VECT_SAMP sMotionVectorTex

float3 DebugMotion(float2 uv, sampler mot_samp)
{
    float2 motion = Sample(mot_samp, uv).xy;
    float angle = atan2(motion.y, motion.x);
    float3 rgb = saturate(3 * abs(2 * frac(angle / DOUBLE_PI + float3(0, -1.0/3.0, 1.0/3.0)) - 1) - 1);

    return lerp(0.5, rgb, saturate(length(motion) * 100));
}
