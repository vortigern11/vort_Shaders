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

namespace MotBlur {

/*******************************************************************************
    Globals
*******************************************************************************/

// Toggles the neight max motion gathering logic
#define MB_USE_MAX_NEIGH 1

#if MB_USE_MAX_NEIGH
    // scale the tile number
    #define K (BUFFER_HEIGHT / 36)
#endif

// Converting the samples to HDR and back yields worse results.
// Bright colors overshadow others and the result seems fake.

// The sampling contribution in CoD: AW has more background visibility
// but it can introduce artifacts due to the guessing of background.
// Enabled with V_USE_NEW_MB

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RG16 };
sampler2D sInfoTexVort { Texture = InfoTexVort; SAM_POINT };

#if MB_USE_MAX_NEIGH
texture2D TileFstTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT; TEX_RGBA16 };
sampler2D sTileFstTexVort { Texture = TileFstTexVort; SAM_POINT };

texture2D TileSndTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT / K; TEX_RGBA16 };
sampler2D sTileSndTexVort { Texture = TileSndTexVort; SAM_POINT };

texture2D NeighMaxTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT / K; TEX_RGBA16 };
sampler2D sNeighMaxTexVort { Texture = NeighMaxTexVort; SAM_POINT };
#endif

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Blur(PS_ARGS3)
{
    float2 motion = SampleMotion(i.uv).xy * UI_MB_Amount;

#if MB_USE_MAX_NEIGH
    // .xy is max in "sand clock" direction, .zw is max in "fallen sand clock" direction
    float4 neigh_motion = Sample(sNeighMaxTexVort, i.uv);

    motion = (abs(motion.x) < abs(motion.y)) ? neigh_motion.xy : neigh_motion.zw;
#endif

    float motion_pix_len = length(motion * BUFFER_SCREEN_SIZE);

    // 1 for each side besides the center
    if(motion_pix_len < 2.0) discard;

    static const int half_samples = 8;
    static const float inv_samples = rcp(float(half_samples) * 2.0);
    static const float depth_scale = 1000.0;

    // x = motion pixel length, y = depth
    float2 center_info = Sample(sInfoTexVort, i.uv).xy;
    float2 motion_per_sample = motion * inv_samples;
    float sample_units_scale = float(half_samples) * RCP(motion_pix_len);
    float sample_dither = Dither(i.vpos.xy, 0.25); // -0.25 or 0.25
    float4 color = 0;

    [loop]for(int j = 0; j < half_samples; j++)
    {
        float step = float(j) + 0.5 + sample_dither;
        float2 offs = motion_per_sample * step;

        float2 sample_uv1 = saturate(i.uv + offs);
        float2 sample_uv2 = saturate(i.uv - offs);

        // x = motion pixel length, y = depth
        float2 sample_info1 = Sample(sInfoTexVort, sample_uv1).xy;
        float2 sample_info2 = Sample(sInfoTexVort, sample_uv2).xy;

        float2 depthcmp1 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info1.y - center_info.y));
        float2 depthcmp2 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info2.y - center_info.y));

    #if V_USE_NEW_MB
        step = max(0.0, float(j) - 1.0);
        float2 spreadcmp1 = saturate(sample_units_scale * float2(center_info.x, sample_info1.x) - step);
        float2 spreadcmp2 = saturate(sample_units_scale * float2(center_info.x, sample_info2.x) - step);
    #else
        float offs_len = max(1.0, step / sample_units_scale);
        float2 spreadcmp1 = saturate(1.0 - offs_len * RCP(float2(center_info.x, sample_info1.x)));
        float2 spreadcmp2 = saturate(1.0 - offs_len * RCP(float2(center_info.x, sample_info2.x)));
    #endif

        float weight1 = dot(depthcmp1, spreadcmp1);
        float weight2 = dot(depthcmp2, spreadcmp2);

    #if V_USE_NEW_MB
        // mirror filter to better guess the background
        bool2 mirror = bool2(sample_info1.y > sample_info2.y, sample_info2.x > sample_info1.x);
        weight1 = all(mirror) ? weight2 : weight1;
        weight2 = any(mirror) ? weight2 : weight1;
    #endif

        color += float4(SampleLinColor(sample_uv1) * weight1, weight1);
        color += float4(SampleLinColor(sample_uv2) * weight2, weight2);
    }

#if V_USE_NEW_MB
    color *= inv_samples;
    color.rgb += (1.0 - color.w) * SampleLinColor(i.uv);
#else
    color += float4(SampleLinColor(i.uv), 1.0) * RCP(center_info.x);
    color.rgb *= RCP(color.w);
#endif

    o = ApplyGammaCurve(color.rgb);
}

void PS_WriteInfo(PS_ARGS2)
{
    float mot_len = length(SampleMotion(i.uv).xy * UI_MB_Amount * BUFFER_SCREEN_SIZE);

#if MB_USE_MAX_NEIGH
    mot_len = min(mot_len, float(K));
#endif

    o.x = mot_len;
    o.y = GetLinearizedDepth(i.uv);
}

#if MB_USE_MAX_NEIGH
void PS_TileDownHor(PS_ARGS4)
{
    float3 max_motion_1 = 0;
    float3 max_motion_2 = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        int2 pos = int2(floor(i.vpos.x) * K + x, i.vpos.y);
        float2 motion = FetchMotion(pos).xy * UI_MB_Amount;

        // limit the motion like in the paper
        float mot_len = length(motion * BUFFER_SCREEN_SIZE);
        motion *= min(mot_len, float(K)) * RCP(mot_len);

        // if there was a circle with it's center at (0, 0),
        // this check is whether the motion direction is pointing
        // from 325deg to 45deg or from 225deg to 135deg
        bool is_sand_clock = abs(motion.x) < abs(motion.y);
        float sq_len = dot(motion, motion);

        if ( is_sand_clock && sq_len > max_motion_1.z) max_motion_1 = float3(motion, sq_len);
        if (!is_sand_clock && sq_len > max_motion_2.z) max_motion_2 = float3(motion, sq_len);
    }

    o = float4(max_motion_1.xy, max_motion_2.xy);
}

void PS_TileDownVert(PS_ARGS4)
{
    float3 max_motion_1 = 0;
    float3 max_motion_2 = 0;

    [loop]for(uint y = 0; y < K; y++)
    {
        int2 pos = int2(i.vpos.x, floor(i.vpos.y) * K + y);
        float4 motion_12 = Fetch(sTileFstTexVort, pos);
        float sq_len_1 = dot(motion_12.xy, motion_12.xy);
        float sq_len_2 = dot(motion_12.zw, motion_12.zw);

        if (sq_len_1 > max_motion_1.z) max_motion_1 = float3(motion_12.xy, sq_len_1);
        if (sq_len_2 > max_motion_2.z) max_motion_2 = float3(motion_12.zw, sq_len_2);
    }

    o = float4(max_motion_1.xy, max_motion_2.xy);
}

void PS_NeighbourMax(PS_ARGS4)
{
    float3 max_motion_1 = 0;
    float3 max_motion_2 = 0;

    [loop]for(int x = -1; x <= 1; x++)
    [loop]for(int y = -1; y <= 1; y++)
    {
        int2 pos = int2(i.vpos.xy) + int2(x, y);
        float4 motion_12 = Fetch(sTileSndTexVort, pos);
        float sq_len_1 = dot(motion_12.xy, motion_12.xy);
        float sq_len_2 = dot(motion_12.zw, motion_12.zw);

        if (sq_len_1 > max_motion_1.z) max_motion_1 = float3(motion_12.xy, sq_len_1);
        if (sq_len_2 > max_motion_2.z) max_motion_2 = float3(motion_12.zw, sq_len_2);
    }

    o = float4(max_motion_1.xy, max_motion_2.xy);
}
#endif // MB_USE_MAX_NEIGH

/*******************************************************************************
    Passes
*******************************************************************************/

#if MB_USE_MAX_NEIGH
    #define PASS_MOT_BLUR_MAX_NEIGH \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor;  RenderTarget = MotBlur::TileFstTexVort;  } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTexVort;  } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTexVort; }
#else
    #define PASS_MOT_BLUR_MAX_NEIGH
#endif

#define PASS_MOT_BLUR \
    PASS_MOT_BLUR_MAX_NEIGH \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo; RenderTarget = MotBlur::InfoTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }

} // namespace end
