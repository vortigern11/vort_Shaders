/*******************************************************************************
    Author: Vortigern
    Sources:
    "A Reconstruction Filter for Plausible Motion Blur" by McGuire et al. 2012
    "A Fast and Stable Feature-Aware Motion Blur Filter" by Guertin et al. 2014
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

#define MB_MOTION_MOD (UI_MB_Length * 0.5 * BUFFER_SCREEN_SIZE)

// Whether to use the new motion blur implementation by Jimenez
// Prevents the foreground from leaking in the background
#define MB_USE_NEW_METHOD 1

// scale the tile number (30px at 1080p)
#define K (BUFFER_HEIGHT / 36)

// Converting the samples to HDR and back yields worse results.
// Bright colors overshadow others and the result seems fake.

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RG16 };
sampler2D sInfoTexVort { Texture = InfoTexVort; SAM_POINT };

texture2D TileFstTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT; TEX_RG16 };
sampler2D sTileFstTexVort { Texture = TileFstTexVort; SAM_POINT };

texture2D TileSndTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT / K; TEX_RG16 };
sampler2D sTileSndTexVort { Texture = TileSndTexVort; SAM_POINT };

texture2D NeighMaxTexVort { Width = BUFFER_WIDTH / K; Height = BUFFER_HEIGHT / K; TEX_RG16 };
sampler2D sNeighMaxTexVort { Texture = NeighMaxTexVort; SAM_POINT };

/*******************************************************************************
    Functions
*******************************************************************************/

// motion must be in pixel units
float3 GetDilatedMotionAndLen(int2 pos)
{
    float2 motion = FetchMotion(pos).xy * MB_MOTION_MOD;

    // limit the motion like in the paper
    float old_mot_len = max(0.5, length(motion));
    float new_mot_len = min(old_mot_len, float(K));
    motion *= new_mot_len * RCP(old_mot_len);

    return float3(motion, new_mot_len);
}

float2 GetTilesOffs(float2 vpos, bool only_horiz)
{
    // randomize max neighbour lookup near borders to reduce tile visibility
    float2 tiles_inv_size = K * BUFFER_PIXEL_SIZE;
    float2 tile_border_dist = abs(frac(vpos * tiles_inv_size) - 0.5) * 2.0;
    float rand = GetGoldNoise(vpos) - 0.5;

    // don't randomize diagonally
    tile_border_dist *= only_horiz ? float2(1.0, 0.0) : float2(0.0, 1.0);

    float2 uv_offset = (tile_border_dist * tiles_inv_size) * rand;

    return uv_offset;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Blur(PS_ARGS3)
{
    float sample_dither = Dither(i.vpos.xy, 0.25); // -0.25 or 0.25
    float2 tiles_uv_offs = GetTilesOffs(i.vpos.xy, sample_dither < 0.0);

    float2 max_motion = Sample(sNeighMaxTexVort, i.uv + tiles_uv_offs).xy;
    float max_mot_len = length(max_motion);

    // if there are less than 2 pixels movement, no point to blur
    if(max_mot_len < 2.0) discard;

    // x = motion px length, y = depth
    float2 cen_info = Sample(sInfoTexVort, i.uv).xy;
    float2 cen_motion = GetDilatedMotionAndLen(i.vpos.xy).xy;

    // logic from
    // https://github.com/RomkoSI/G3D/blob/master/data-files/shader/MotionBlur/MotionBlur_gather.pix
    float2 alt_dir = (cen_motion * RCP(cen_info.x)) * max_mot_len;
    float2 max_dir = cen_info.x > 5.0 ? alt_dir : max_motion;
    float2 cen_dir = cen_info.x < 1.5 ? max_motion : alt_dir;

    static const int half_samples = 6;
    static const float inv_half_samples = rcp(float(half_samples));

    // xy = motion direction, z = px scale
    float3 even_info = float3(max_dir * BUFFER_PIXEL_SIZE, inv_half_samples * length(max_dir));
    float3 odd_info = float3(cen_dir * BUFFER_PIXEL_SIZE, inv_half_samples * length(cen_dir));

    float total_samples = float(half_samples) * 2.0;
    float4 bg_acc = 0.0;
    float4 fg_acc = 0.0;

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // switch between max and center
        float3 m = even_info;
        [flatten]if(j % 2 == 1) m = odd_info;

        float step = float(j) + 0.5 + sample_dither;
        float2 uv_offs = (step * inv_half_samples) * m.xy;

        float2 sample_uv1 = saturate(i.uv + uv_offs);
        float2 sample_uv2 = saturate(i.uv - uv_offs);

        // x = motion px length, y = depth
        float2 sample_info1 = Sample(sInfoTexVort, sample_uv1).xy;
        float2 sample_info2 = Sample(sInfoTexVort, sample_uv2).xy;

        float2 depthcmp1 = saturate(0.5 + float2(1.0, -1.0) * (sample_info1.y - cen_info.y));
        float2 depthcmp2 = saturate(0.5 + float2(1.0, -1.0) * (sample_info2.y - cen_info.y));

        // the `max` is to make sure that the furthest sample still contributes
        float offs_len = max(0.0, step - 1.0) * m.z;

    #if MB_USE_NEW_METHOD
        float2 spreadcmp1 = saturate(float2(cen_info.x, sample_info1.x) - offs_len);
        float2 spreadcmp2 = saturate(float2(cen_info.x, sample_info2.x) - offs_len);
    #else
        float2 spreadcmp1 = saturate(1.0 - offs_len * RCP(float2(cen_info.x, sample_info1.x)));
        float2 spreadcmp2 = saturate(1.0 - offs_len * RCP(float2(cen_info.x, sample_info2.x)));
    #endif

        // .x = bg weight, .y = fg weight
        float2 sample_w1 = depthcmp1 * spreadcmp1;
        float2 sample_w2 = depthcmp2 * spreadcmp2;

        float3 sample_color1 = SampleLinColor(sample_uv1);
        float3 sample_color2 = SampleLinColor(sample_uv2);

        // bg/fg for first sample
        bg_acc += float4(sample_color1, 1.0) * sample_w1.x;
        fg_acc += float4(sample_color1, 1.0) * sample_w1.y;

        // bg/fg for second sample
        bg_acc += float4(sample_color2, 1.0) * sample_w2.x;
        fg_acc += float4(sample_color2, 1.0) * sample_w2.y;
    }

    // preserve thin features like in the paper
    float cen_weight = saturate(total_samples * RCP(cen_info.x * 40.0));

#if MB_USE_NEW_METHOD
    // add center color to background
    bg_acc += float4(SampleLinColor(i.uv), 1.0) * cen_weight;
    total_samples += 1.0;

    float3 bg_col = bg_acc.rgb * RCP(bg_acc.w);
    float4 sum_acc = bg_acc + fg_acc;

    // normalize
    sum_acc /= total_samples;

    // fill the missing data with background color
    // instead of center in order to counteract artifacts in some cases
    float3 color = sum_acc.rgb + saturate(1.0 - sum_acc.w) * bg_col;
#else
    float4 sum_acc = bg_acc + fg_acc;

    // add center color
    sum_acc += float4(SampleLinColor(i.uv), 1.0) * cen_weight;

    float3 color = sum_acc.rgb * RCP(sum_acc.w);
#endif

    o = ApplyGammaCurve(color);
}

void PS_WriteInfo(PS_ARGS2)
{
    static const float depth_scale = 1000.0;

    float scaled_depth = GetLinearizedDepth(i.uv) * depth_scale;
    float mot_len = GetDilatedMotionAndLen(i.vpos.xy).z;

    o.x = mot_len;
    o.y = scaled_depth;
}

void PS_TileDownHor(PS_ARGS2)
{
    float3 max_motion = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        int2 pos = int2(floor(i.vpos.x) * K + x, i.vpos.y);

        // xy = motion in pixels, z = motion px length
        float3 mot_info = GetDilatedMotionAndLen(pos);

        if(mot_info.z > max_motion.z) max_motion = mot_info;
    }

    o = max_motion.xy;
}

void PS_TileDownVert(PS_ARGS2)
{
    float3 max_motion = 0;

    [loop]for(uint y = 0; y < K; y++)
    {
        int2 pos = int2(i.vpos.x, floor(i.vpos.y) * K + y);
        float2 motion = Fetch(sTileFstTexVort, pos).xy;
        float sq_len = dot(motion.xy, motion.xy);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);
    }

    o = max_motion.xy;
}

void PS_NeighbourMax(PS_ARGS2)
{
    float3 max_motion = 0;

    [loop]for(int x = -1; x <= 1; x++)
    [loop]for(int y = -1; y <= 1; y++)
    {
        int2 pos = int2(i.vpos.xy) + int2(x, y);
        float2 motion = Fetch(sTileSndTexVort, pos).xy;

        static const float COS_ANGLE_45 = 0.7071;
        float2 rev_offs = -float2(x, y);
        float abs_cos_angle = abs(dot(rev_offs, motion) * RCP(length(rev_offs) * length(motion)));
        bool is_mot_in_center_dir = abs_cos_angle < COS_ANGLE_45;
        bool is_center = x == 0 && y == 0;

        if(is_center || is_mot_in_center_dir)
        {
            float sq_len = dot(motion, motion);

            if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);
        }
    }

    o = max_motion.xy;
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MOT_BLUR \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo;    RenderTarget = MotBlur::InfoTexVort;     } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor;  RenderTarget = MotBlur::TileFstTexVort;  } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTexVort;  } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; SRGB_WRITE_ENABLE }

} // namespace end
