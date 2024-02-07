/*******************************************************************************
    Author: Vortigern
    Sources:
    "A Reconstruction Filter for Plausible Motion Blur" by McGuire et al.
    Next-Generation-Post-Processing-in-Call-of-Duty-Advanced-Warfare-v18

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
#include "Includes/vort_ColorTex.fxh"
#include "Includes/vort_Motion_UI.fxh"
#include "Includes/vort_Tonemap.fxh"

namespace MotBlur {

/*******************************************************************************
    Globals
*******************************************************************************/

// tried with max neighbour tiles, but there were issues either
// due to implementation or imperfect motion vectors

/* MAX_NEIGHBOUR
#if BUFFER_HEIGHT >= 2160
    #define K 60
#else
    #define K 30 // scaled to 1080p from 720p
#endif
*/

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RG16 };
sampler2D sInfoTexVort { Texture = InfoTexVort; };

/* MAX_NEIGHBOUR
texture2D TileFstTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT; TEX_RG16 };
sampler2D sTileFstTexVort { Texture = TileFstTexVort; SAM_POINT };

texture2D TileSndTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT / K; TEX_RG16 };
sampler2D sTileSndTexVort { Texture = TileSndTexVort; SAM_POINT };

texture2D NeighMaxTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT / K; TEX_RG16 };
sampler2D sNeighMaxTexVort { Texture = NeighMaxTexVort; SAM_POINT };
*/

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Blur(PS_ARGS3)
{
    /* MAX_NEIGHBOUR
    float2 motion = Sample(sNeighMaxTexVort, i.uv).xy;

    if(length(motion * BUFFER_SCREEN_SIZE) < 1.0) discard;
    */

    // x = motion pixel length, y = depth
    float2 center_info = Sample(sInfoTexVort, i.uv).xy;

    if(center_info.x < 1.0) discard;

    float2 motion = SampleMotion(i.uv).xy * UI_MB_Amount;

    int half_samples = clamp(floor(center_info.x * 0.5), 2, 16);
    float inv_half_samples = rcp(float(half_samples));
    float rand = Dither(i.vpos.xy, 0.25);
    float4 color = 0;

    static const float depth_scale = 1000.0;

    [loop]for(int j = 1; j <= half_samples; j++)
    {
        float2 offs = motion * (float(j) - rand) * inv_half_samples;

        // remove artifacts by ensuring offs is min 1 pixel
        float offs_len = max(1.0, length(offs * BUFFER_SCREEN_SIZE));

        float2 sample_uv1 = saturate(i.uv + offs);
        float2 sample_uv2 = saturate(i.uv - offs);

        float2 sample_info1 = Sample(sInfoTexVort, sample_uv1).xy;
        float2 sample_info2 = Sample(sInfoTexVort, sample_uv2).xy;

        float2 depthcmp1 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info1.y - center_info.y));
        float2 depthcmp2 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info2.y - center_info.y));

        float2 spreadcmp1 = saturate(1.0 - offs_len * RCP(float2(center_info.x, sample_info1.x)));
        float2 spreadcmp2 = saturate(1.0 - offs_len * RCP(float2(center_info.x, sample_info2.x)));

        float weight1 = dot(depthcmp1, spreadcmp1);
        float weight2 = dot(depthcmp2, spreadcmp2);

        color += float4(SampleLinColor(sample_uv1) * weight1, weight1);
        color += float4(SampleLinColor(sample_uv2) * weight2, weight2);
    }

    // Converting the samples to HDR and back yields worse results.
    // Bright colors overshadow others and the result seems fake.

    // The sampling contribution in CoD: AW has more background visibility
    // but it introduces annoying artifacts due to the guessing of background
    // in certain cases. Instead I use the solution in McGuire's paper which
    // doesn't have this issue. The spread comparison above is changed accordingly.

    color += float4(SampleLinColor(i.uv), 1.0) * RCP(center_info.x);
    color.rgb *= RCP(color.w);

    o = ApplyGammaCurve(color.rgb);
}

void PS_WriteInfo(PS_ARGS2)
{
    float mot_len = length(SampleMotion(i.uv).xy * UI_MB_Amount * BUFFER_SCREEN_SIZE);

    /* MAX_NEIGHBOUR o.x = min(mot_len, float(K)); */
    o.x = mot_len;
    o.y = GetLinearizedDepth(i.uv);
}

/* MAX_NEIGHBOUR
void PS_TileDownHor(PS_ARGS2)
{
    float3 max_motion = 0;
    float3 avg_motion = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        int2 pos = int2(floor(i.vpos.x) * K + x, i.vpos.y);
        float2 motion = FetchMotion(pos).xy * UI_MB_Amount;

        // limit the motion like in the paper
        float mot_len = length(motion * BUFFER_SCREEN_SIZE);
        motion *= min(mot_len, float(K)) * RCP(mot_len);

        float sq_len = dot(motion, motion);
        max_motion = sq_len > max_motion.z ? float3(motion, sq_len) : max_motion;
        avg_motion += float3(motion * sq_len, sq_len);
    }

    avg_motion.xy *= RCP(avg_motion.z);

    float cos_angle = dot(NORMALIZE(avg_motion.xy), NORMALIZE(max_motion.xy));

    o = lerp(avg_motion.xy, max_motion.xy, saturate(1.0 - cos_angle * 10.0));
}

void PS_TileDownVert(PS_ARGS2)
{
    float3 max_motion = 0;
    float3 avg_motion = 0;

    [loop]for(uint y = 0; y < K; y++)
    {
        int2 pos = int2(i.vpos.x, floor(i.vpos.y) * K + y);
        float2 motion = Fetch(sTileFstTexVort, pos).xy;

        float sq_len = dot(motion, motion);
        max_motion = sq_len > max_motion.z ? float3(motion, sq_len) : max_motion;
        avg_motion += float3(motion * sq_len, sq_len);
    }

    avg_motion.xy *= RCP(avg_motion.z);

    float cos_angle = dot(NORMALIZE(avg_motion.xy), NORMALIZE(max_motion.xy));

    o = lerp(avg_motion.xy, max_motion.xy, saturate(1.0 - cos_angle * 10.0));
}

void PS_NeighbourMax(PS_ARGS2)
{
    float3 max_motion = 0;

    [loop]for(int x = -1; x <= 1; x++)
    [loop]for(int y = -1; y <= 1; y++)
    {
        float2 motion = Fetch(sTileSndTexVort, i.uv + int2(x, y)).xy;

        float sq_len = dot(motion, motion);
        max_motion = sq_len > max_motion.z ? float3(motion, sq_len) : max_motion;
    }

    o = max_motion.xy;
}
*/

/*******************************************************************************
    Passes
*******************************************************************************/

/* MAX_NEIGHBOUR
#define PASS_MOT_BLUR_MAX_NEIGH \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor; RenderTarget = MotBlur::TileFstTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTexVort; }
*/

#define PASS_MOT_BLUR \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo; RenderTarget = MotBlur::InfoTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }

} // namespace end
