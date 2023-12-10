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

#define K 20 // same value as in the paper

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
"Toggle hardware linearization (better performance).\n"
"Disable if you have color issues due to some bug (like older REST versions).\n"
)

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RG16 };
sampler2D sInfoTexVort { Texture = InfoTexVort; };

// Too many samplers for DX9
#if !IS_DX9
texture2D TileFstTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT; TEX_RG16 };
sampler2D sTileFstTexVort { Texture = TileFstTexVort; };

texture2D TileSndTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT / K; TEX_RG16 };
sampler2D sTileSndTexVort { Texture = TileSndTexVort; };

texture2D NeighMaxTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT / K; TEX_RG16 };
sampler2D sNeighMaxTexVort { Texture = NeighMaxTexVort; SAM_POINT };
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float3 GetColor(float2 uv)
{
    return ApplyLinearCurve(Sample(sLDRTexVort, uv).rgb);
}

float Cone(float xy_len, float v_len)
{
    return saturate(1.0 - xy_len * RCP(v_len));
}

float2 SoftDepthCompare(float zf, float zb)
{
    static const float rcp_z_extent = 100.0;
    float x = (zf - zb) * rcp_z_extent;

    // we use positive depth, unlike the research paper
    return saturate(1.0 + float2(x, -x));
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Blur(PS_ARGS3)
{
#if IS_DX9
    float2 motion = Sample(MOT_VECT_SAMP, i.uv).xy;
#else
    float2 motion = Sample(sNeighMaxTexVort, i.uv).xy;
#endif

    float motion_pix_len = length(motion * BUFFER_SCREEN_SIZE);

    if(motion_pix_len < 1.0) discard;

    static const uint samples = 8;
    float3 center_color = GetColor(i.uv);
    float rand = GetNoise(i.uv) * 0.5;
    float4 color = 0.0;

    // x = motion pixel length, y = linear depth
    float2 center_info = Sample(sInfoTexVort, i.uv).xy;

    // add center color
    color.w = RCP(center_info.x);
    color.rgb = center_color * color.w;

    // faster than dividing `j` inside the loop
    motion *= rcp(samples);

    // due to circular movement looking bad otherwise,
    // only areas behind the pixel are included in the blur
    [loop]for(uint j = 1; j <= samples; j++)
    {
        float2 sample_uv = saturate(i.uv - motion * (float(j) - rand));
        float2 sample_info = Sample(sInfoTexVort, sample_uv).xy;
        float2 fb = SoftDepthCompare(center_info.y, sample_info.y);
        float uv_dist = length((sample_uv - i.uv) * BUFFER_SCREEN_SIZE);
        float weight = 0;

        weight += fb.x * Cone(uv_dist, sample_info.x);
        weight += fb.y * Cone(uv_dist, center_info.x);

        color += float4(GetColor(sample_uv) * weight, weight);
    }

    o = ApplyGammaCurve(color.rgb * rcp(color.w));
}

void PS_WriteInfo(PS_ARGS2)
{
    float motion_len = length(Sample(MOT_VECT_SAMP, i.uv).xy * BUFFER_SCREEN_SIZE);

#if IS_DX9
    o.x = motion_len;
#else
    o.x = min(motion_len, K); // limit the motion like in the paper
#endif

    o.y = GetLinearizedDepth(i.uv);
}

#if !IS_DX9
void PS_TileDownHor(PS_ARGS2)
{
    // xy = motion, z = weight
    float3 max_motion = 0;
    float3 avg_motion = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        float2 pos = float2(floor(i.vpos.x) * K + x, i.vpos.y);
        float2 motion = Sample(MOT_VECT_SAMP, pos * BUFFER_PIXEL_SIZE).xy;

        // limit the motion like in the paper
        float mot_len = length(motion * BUFFER_SCREEN_SIZE);
        motion *= min(mot_len, K) * RCP(mot_len);

        float sq_len = dot(motion, motion); // squared to prevent outlier influence

        max_motion = sq_len > max_motion.z ? float3(motion, sq_len) : max_motion;
        avg_motion += float3(motion * sq_len, sq_len);
    }

    avg_motion.xy *= RCP(avg_motion.z);

    float cos_angle = dot(NORMALIZE(avg_motion.xy), NORMALIZE(max_motion.xy));

    o = lerp(avg_motion.xy, max_motion.xy, saturate(1.0 - cos_angle * 10.0));
}

void PS_TileDownVert(PS_ARGS2)
{
    // xy = motion, z = weight
    float3 max_motion = 0;
    float3 avg_motion = 0;

    [loop]for(uint y = 0; y < K; y++)
    {
        float2 pos = float2(i.vpos.x, floor(i.vpos.y) * K + y);
        float2 motion = tex2Dfetch(sTileFstTexVort, pos).xy;
        float sq_len = dot(motion, motion); // squared to prevent outlier influence

        max_motion = sq_len > max_motion.z ? float3(motion, sq_len) : max_motion;
        avg_motion += float3(motion * sq_len, sq_len);
    }

    avg_motion.xy *= RCP(avg_motion.z);

    float cos_angle = dot(NORMALIZE(avg_motion.xy), NORMALIZE(max_motion.xy));

    o = lerp(avg_motion.xy, max_motion.xy, saturate(1.0 - cos_angle * 10.0));
}

void PS_NeighbourMax(PS_ARGS2)
{
    // xy = motion, z = weight
    float3 max_motion = 0;

    [unroll]for(int x = -1; x <= 1; x++)
    [unroll]for(int y = -1; y <= 1; y++)
    {
        float2 motion = tex2Doffset(sTileSndTexVort, i.uv, int2(x, y)).xy;
        float sq_len = dot(motion, motion); // squared to prevent outlier influence

        max_motion = sq_len > max_motion.z ? float3(motion, sq_len) : max_motion;
    }

    o = max_motion.xy;
}
#endif // not IS_DX9

void PS_Debug(PS_ARGS3) { o = MotVectUtils::Debug(i.uv, MOT_VECT_SAMP, 1.0); }

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
        #if !IS_DX9
            pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor; RenderTarget = MotBlur::TileFstTexVort; }
            pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTexVort; }
            pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTexVort; }
        #endif

        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo; RenderTarget = MotBlur::InfoTexVort; }
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }
    #endif
}
