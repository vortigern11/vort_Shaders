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
#include "Includes/vort_BlueNoise.fxh"
#include "Includes/vort_Tonemap.fxh"
#include "Includes/vort_Motion_UI.fxh"
#include "Includes/vort_MotionUtils.fxh"

namespace MotBlur {

/*******************************************************************************
    Globals
*******************************************************************************/

// scale the tile number (40px at 1080p)
#define K (BUFFER_HEIGHT / 27)
#define TILE_WIDTH  (BUFFER_WIDTH / K)
#define TILE_HEIGHT (BUFFER_HEIGHT / K)

// compute shaders group size
#define GS 16 // best performance tested

// tonemap modifier
#define T_MOD 1.5

// max length of motion (2 * tile size)
static const float ML = float(K * 2);

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D TileFstTexVort  { Width = TILE_WIDTH; Height = BUFFER_HEIGHT; TEX_RG16 };
texture2D TileSndTexVort  { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };
texture2D NeighMaxTexVort { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };
texture2D InfoTexVort     { TEX_SIZE(0) TEX_RGBA16 };

sampler2D sTileFstTexVort  { Texture = TileFstTexVort; SAM_POINT };
sampler2D sTileSndTexVort  { Texture = TileSndTexVort; SAM_POINT };
sampler2D sNeighMaxTexVort { Texture = NeighMaxTexVort; SAM_POINT };
sampler2D sInfoTexVort     { Texture = InfoTexVort; };

/*******************************************************************************
    Functions
*******************************************************************************/

float3 InColor(float2 uv)
{
    float3 c = SampleLinColor(uv);

#if IS_SRGB
    c = Tonemap::InverseReinhardMax(c, T_MOD);
#endif

    return c;
}

float3 OutColor(float3 c)
{
#if IS_SRGB
    c = Tonemap::ApplyReinhardMax(c, T_MOD);
#endif

    return ApplyGammaCurve(c);
}

#if DEBUG_BLUR
float2 GetDebugMotion(float2 uv)
{
    // % of max motion length
    float2 motion = 2.0 * ML * (UI_MB_DebugLen * 0.01);

    if(UI_MB_DebugZCen > 0.0)
    {
        float z = GetDepth(uv);
        float z_cent = UI_MB_DebugZCen;
        float z_range = UI_MB_DebugZRange;
        float min_z = saturate(z_cent - z_range);
        float max_z = saturate(z_cent + z_range);

        if(z < min_z) motion = 0;
        if(z > max_z) motion = UI_MB_DebugRev ? -motion : 0;
    }

    return motion * BUFFER_PIXEL_SIZE;
}
#endif

float2 GetMotion(float2 uv)
{
    // motion must be in pixel units
    float2 motion = SampleMotion(uv) * BUFFER_SCREEN_SIZE;

#if DEBUG_BLUR
    motion = GetDebugMotion(uv) * BUFFER_SCREEN_SIZE;
#endif

    return motion;
}

float3 LimitMotionAndLen(float2 motion)
{
    float blur_mod = 0.5 * UI_MB_Mult; // halve, because we sample in 2 dirs

    // limit the motion like in the paper
    float old_mot_len = length(motion);
    float new_mot_len = min(old_mot_len * blur_mod, ML);

    motion *= new_mot_len * RCP(old_mot_len);

    // ignore less than 1px movement
    float3 mot_and_len = old_mot_len < 1.0 ? 0.0 : float3(motion, new_mot_len);

    return mot_and_len;
}

float2 GetTileOffs(float2 pos)
{
    float tiles_noise = (GetBlueNoise(pos).x - 0.5) * 0.25; // -0.125 to 0.125
    float2 tiles_inv_size = K * BUFFER_PIXEL_SIZE;
    float2 tiles_uv_offs = tiles_noise * tiles_inv_size;

    // don't randomize diagonally
    tiles_uv_offs *= Dither(pos, 0.25) < 0.0 ? float2(1, 0) : float2(0, 1);

    return tiles_uv_offs;
}

float4 CalcBlur(VSOUT i)
{
    float3 cen_color = InColor(i.uv);
    float2 max_motion = Sample(sNeighMaxTexVort, i.uv + GetTileOffs(i.vpos.xy)).xy;
    float max_mot_len = length(max_motion);

    // must use the same uv here as the samples in the loop
    // x = motion px len, y = depth, zw = normalized motion
    float4 cen_info = Sample(sInfoTexVort, i.uv);
    float cen_mot_len = cen_info.x;
    float cen_z = cen_info.y;
    float2 cen_motion = cen_info.zw * cen_mot_len;

    // due to tile randomization center motion might be greater
    if(max_mot_len < cen_mot_len) { max_mot_len = cen_mot_len; max_motion = cen_motion; }

#if DEBUG_TILES
    if(1) { return float4(DebugMotion(max_motion * BUFFER_PIXEL_SIZE), 1); }
#endif

    // early out when less than 2px movement
    if(max_mot_len < 1.0) return float4(OutColor(cen_color), 1.0);

    uint half_samples = clamp(ceil(max_mot_len), 3, max(3, UI_MB_MaxSamples));

    // odd amount of samples so max motion gets 1 more sample than center motion
    if(half_samples % 2 == 0) half_samples += 1;

    float2 max_mot_norm = max_motion * RCP(max_mot_len);
    float2 cen_mot_norm = cen_motion * RCP(cen_mot_len);

    // xy = norm motion (direction), z = how parallel to center dir
    float3 max_main = float3(max_mot_norm, cen_mot_len < 1.0 ? 1.0 : abs(dot(cen_mot_norm, max_mot_norm)));

    // don't lose half the samples when there is no center px motion
    // helps when an object is moving but the background isn't
    float3 cen_main = cen_mot_len < 1.0 ? max_main : float3(cen_mot_norm, 1.0);

    // dither looks better than IGN
    float2 sample_noise = Dither(i.vpos.xy, 0.25) * float2(1, -1); // negated in second direction to remove visible gap
    float2 z_scales = Z_FAR_PLANE * float2(1, -1); // touch only if you change depth_cmp
    float inv_half_samples = rcp(float(half_samples));
    float steps_to_px = inv_half_samples * max_mot_len;

    float4 bg_acc = 0;
    float4 fg_acc = 0;

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // switch between max and center
        float3 m = j % 2 == 0 ? max_main : cen_main;

        float2 step = float(j) + 0.5 + sample_noise;
        float2 pn = m.xy * BUFFER_PIXEL_SIZE;
        float2 sample_uv1 = i.uv - (step.x * steps_to_px) * pn;
        float2 sample_uv2 = i.uv + (step.y * steps_to_px) * pn;

        // x = motion px len, y = depth, zw = norm motion
        float4 sample_info1 = Sample(sInfoTexVort, sample_uv1);
        float4 sample_info2 = Sample(sInfoTexVort, sample_uv2);

        float sample_mot_len1 = sample_info1.x;
        float sample_mot_len2 = sample_info2.x;

        float sample_z1 = sample_info1.y;
        float sample_z2 = sample_info2.y;

        float2 sample_mot_norm1 = sample_info1.zw;
        float2 sample_mot_norm2 = sample_info2.zw;

        // x = bg, y = fg
        float2 depth_cmp1 = saturate(0.5 + z_scales * (sample_z1 - cen_z));
        float2 depth_cmp2 = saturate(0.5 + z_scales * (sample_z2 - cen_z));

        // the `max` is to remove potential artifacts
        float2 spread_cmp1 = saturate(float2(cen_mot_len, sample_mot_len1) - max(0.0, step.x - 1.0) * steps_to_px);
        float2 spread_cmp2 = saturate(float2(cen_mot_len, sample_mot_len2) - max(0.0, step.y - 1.0) * steps_to_px);

        // check for mismatch between motion directions
        float2 dir_w1 = float2(m.z, abs(dot(sample_mot_norm1, m.xy)));
        float2 dir_w2 = float2(m.z, abs(dot(sample_mot_norm2, m.xy)));

        // x = bg weight, y = fg weight
        float2 sample_w1 = (depth_cmp1 * spread_cmp1) * dir_w1;
        float2 sample_w2 = (depth_cmp2 * spread_cmp2) * dir_w2;

        float3 sample_color1 = InColor(sample_uv1);
        float3 sample_color2 = InColor(sample_uv2);

        bool2 mir = bool2(sample_z1 > sample_z2, sample_mot_len2 > sample_mot_len1);
        sample_w1 = all(mir) ? sample_w2 : sample_w1;
        sample_w2 = any(mir) ? sample_w2 : sample_w1;

        bg_acc += float4(sample_color1, 1.0) * sample_w1.x;
        fg_acc += float4(sample_color1, 1.0) * sample_w1.y;

        bg_acc += float4(sample_color2, 1.0) * sample_w2.x;
        fg_acc += float4(sample_color2, 1.0) * sample_w2.y;
    }

    // don't sum total weight, use total samples to prevent artifacts
    float total_samples = float(half_samples) * 2.0;

    // better than only depending on samples amount
    float cen_weight = saturate(0.05 * float(half_samples) * rcp(max(0.5, cen_mot_len)));

    // add center color and weight to background
    bg_acc += float4(cen_color, 1.0) * cen_weight;
    total_samples += 1.0;

    float3 fill_col = bg_acc.rgb * RCP(bg_acc.w);
    float4 sum_acc = (bg_acc + fg_acc) * RCP(total_samples);

    // fill the missing data with background + center color
    // instead of only center in order to prevent artifacts
    float3 c = sum_acc.rgb + saturate(1.0 - sum_acc.w) * fill_col;

    return float4(OutColor(c), 1.0);
}

float2 CalcTileDownHor(VSOUT i)
{
    float3 max_motion = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        float2 sample_uv = float2(floor(i.vpos.x) * K + 0.5 + x, i.vpos.y) * BUFFER_PIXEL_SIZE;
        float2 motion = GetMotion(sample_uv);
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);
    }

    return max_motion.xy;
}

float2 CalcTileDownVert(VSOUT i)
{
    float3 max_motion = 0;

    [loop]for(uint y = 0; y < K; y++)
    {
        float2 sample_pos = float2(i.vpos.x, floor(i.vpos.y) * K + 0.5 + y);
        float2 motion = Fetch(sTileFstTexVort, sample_pos).xy;
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);
    }

    return max_motion.xy;
}

float2 CalcNeighbourMax(VSOUT i)
{
    float3 max_motion = 0;

    [loop]for(uint j = 0; j < S_BOX_OFFS2; j++)
    {
        float2 offs = BOX_OFFS2[j];
        float2 sample_pos = i.vpos.xy + offs;
        float2 motion = Fetch(sTileSndTexVort, sample_pos).xy;
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z)
        {
            bool is_diag = (offs.x * offs.y) != 0;
            bool should_contrib = true;

            if(is_diag)
            {
                float rel_angle = ACOS(GetCosAngle(-offs, motion));

                // 45 and 135 deg
                should_contrib = rel_angle < 0.7854 || rel_angle > 2.3561;
            }

            if(should_contrib) max_motion = float3(motion, sq_len);
        }
    }

    return LimitMotionAndLen(max_motion.xy).xy;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Info(PS_ARGS4)
{
    float3 closest = float3(i.uv, GetDepth(i.uv));

    if(UI_MB_UseMinFilter)
    {
        // apply min filter to remove some artifacts
        [loop]for(uint j = 1; j < S_BOX_OFFS1; j++)
        {
            float2 sample_uv = i.uv + BOX_OFFS1[j] * BUFFER_PIXEL_SIZE;
            float sample_z = GetDepth(sample_uv);

            if(sample_z < closest.z) closest = float3(sample_uv, sample_z);
        }
    }

    float3 mot_and_len = LimitMotionAndLen(GetMotion(closest.xy));
    float2 mot_norm = mot_and_len.xy * RCP(mot_and_len.z);

    // x = motion px len, y = depth, zw = norm motion
    o = float4(mot_and_len.z, closest.z, mot_norm);
}

void PS_TileDownHor(PS_ARGS2)  { o = CalcTileDownHor(i);  }
void PS_TileDownVert(PS_ARGS2) { o = CalcTileDownVert(i); }
void PS_NeighbourMax(PS_ARGS2) { o = CalcNeighbourMax(i); }
void PS_BlurAndDraw(PS_ARGS3)  { o = CalcBlur(i).rgb; }

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MOT_BLUR \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor;  RenderTarget = MotBlur::TileFstTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Info;         RenderTarget = MotBlur::InfoTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_BlurAndDraw; }

} // namespace end
