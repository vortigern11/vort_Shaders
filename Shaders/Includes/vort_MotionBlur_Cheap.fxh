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
// better perf on my GPU than 16x16 or 8x8 groups
#define GS_X 256
#define GS_Y 1

// tonemap modifier
#define T_MOD 1.5

// max length of motion
static const float ML = float(K * 2);

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D TileFstTex  { Width = TILE_WIDTH; Height = BUFFER_HEIGHT; TEX_RG16 };
texture2D TileSndTex  { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };
texture2D NeighMaxTex { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };
texture2D InfoTex     { TEX_SIZE(0) TEX_RGBA16 };

sampler2D sTileFstTex  { Texture = TileFstTex; SAM_POINT };
sampler2D sTileSndTex  { Texture = TileSndTex; SAM_POINT };
sampler2D sNeighMaxTex { Texture = NeighMaxTex; SAM_POINT };
sampler2D sInfoTex     { Texture = InfoTex; };

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
    // % of max motion length (round for perfect pixel movement)
    float2 motion = round(2.0 * ML * (UI_MB_DebugLen * 0.01));

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
    else if(UI_MB_DebugPoint)
    {
        motion = NORM(float2(0.5,0.5) - uv) * BUFFER_SCREEN_SIZE;
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
    // limit the motion like in the paper
    float old_mot_len = length(motion);
    float max_len = round(ML * UI_MB_MaxBlurMult);

    // halve, because we sample in 2 dirs
    float new_mot_len = min(old_mot_len * 0.5, max_len);

    motion *= new_mot_len * rcp(max(1e-15, old_mot_len));

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

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_BlurAndDraw(PS_ARGS3)
{
    float3 cen_color = InColor(i.uv);
    float2 max_motion = Sample(sNeighMaxTex, i.uv + GetTileOffs(i.vpos.xy)).xy;
    float max_mot_len = length(max_motion);

    // must use the same uv here as the samples in the loop
    // x = motion px len, y = depth, zw = normalized motion
    float4 cen_info = Sample(sInfoTex, i.uv);
    float cen_mot_len = cen_info.x;
    float cen_z = cen_info.y;
    float2 cen_motion = cen_info.zw * cen_mot_len;

#if DEBUG_TILES
    if(1) { o = DebugMotion(max_motion * BUFFER_PIXEL_SIZE); return; }
#endif

    // early out when less than 2px movement
    if(max_mot_len < 1.0) { o = OutColor(cen_color); return; }

    // don't change without solid reason
    uint half_samples = clamp(ceil(max_mot_len * 0.5), 3, max(3, UI_MB_MaxSamples));

    // odd amount of samples so max motion gets 1 more sample than center motion
    if(half_samples % 2 == 0) half_samples += 1;

    float2 max_norm_mot = max_motion * rcp(max(1e-15, max_mot_len));
    float2 cen_norm_mot = cen_motion * rcp(max(1e-15, cen_mot_len));

    // xy = norm motion (direction), z = motion length, w = how parallel to center dir
    float4 max_main = float4(max_norm_mot, max_mot_len, cen_mot_len < 1.0 ? 1.0 : abs(dot(cen_norm_mot, max_norm_mot)));

    // don't lose half the samples when there is no center px motion
    // helps when an object is moving but the background isn't
    float4 cen_main = cen_mot_len < 1.0 ? max_main : float4(cen_norm_mot, cen_mot_len, 1.0);

    // negated in second direction to remove visible gap
    float2 tap_noise = (GetIGN(i.vpos.xy, 63) - 0.5) * float2(1, -1);
    float2 z_scales = 100.0 * float2(1, -1); // controls blending
    float inv_half_samples = rcp(float(half_samples));
    float px_to_step = rcp(inv_half_samples * max_mot_len);

    float4 bg_acc = 0;
    float4 fg_acc = 0;

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // switch between max and center
        float4 m = j % 2 == 0 ? max_main : cen_main;

        float2 st = float(j) + 0.5 + tap_noise;
        float2 step_to_offs = inv_half_samples * (m.xy * m.zz) * BUFFER_PIXEL_SIZE;
        float2 tap_uv0 = i.uv - st.x * step_to_offs;
        float2 tap_uv1 = i.uv + st.y * step_to_offs;

        // x = motion px len, y = depth, zw = norm motion
        float4 tap_info0 = Sample(sInfoTex, tap_uv0);
        float4 tap_info1 = Sample(sInfoTex, tap_uv1);

        float tap_mot_len0 = tap_info0.x;
        float tap_mot_len1 = tap_info1.x;

        float tap_z0 = tap_info0.y;
        float tap_z1 = tap_info1.y;

        float2 tap_norm_mot0 = tap_info0.zw;
        float2 tap_norm_mot1 = tap_info1.zw;

        // x = bg, y = fg
        float2 depth_cmp0 = saturate(0.5 + z_scales * (tap_z0 - cen_z));
        float2 depth_cmp1 = saturate(0.5 + z_scales * (tap_z1 - cen_z));

        float2 spread_cmp0 = saturate(float2(cen_mot_len, tap_mot_len0) * px_to_step - max(0.0, st.x - 1.0));
        float2 spread_cmp1 = saturate(float2(cen_mot_len, tap_mot_len1) * px_to_step - max(0.0, st.y - 1.0));

        // check for mismatch between motion directions
        float2 dir_w0 = float2(m.w, abs(dot(tap_norm_mot0, m.xy)));
        float2 dir_w1 = float2(m.w, abs(dot(tap_norm_mot1, m.xy)));

        // x = bg weight, y = fg weight
        float2 tap_w0 = (depth_cmp0 * spread_cmp0) * dir_w0;
        float2 tap_w1 = (depth_cmp1 * spread_cmp1) * dir_w1;

        float3 tap_color0 = InColor(tap_uv0);
        float3 tap_color1 = InColor(tap_uv1);

        bool2 mir = bool2(tap_z0 > tap_z1, tap_mot_len1 > tap_mot_len0);
        tap_w0 = all(mir) ? tap_w1 : tap_w0;
        tap_w1 = any(mir) ? tap_w1 : tap_w0;

        bg_acc += float4(tap_color0, 1.0) * tap_w0.x;
        fg_acc += float4(tap_color0, 1.0) * tap_w0.y;

        bg_acc += float4(tap_color1, 1.0) * tap_w1.x;
        fg_acc += float4(tap_color1, 1.0) * tap_w1.y;
    }

    // don't sum total weight, use total samples to prevent artifacts
    float total_samples = float(half_samples) * 2.0;

    // better than only depending on samples amount
    float cen_weight = saturate(0.05 * float(half_samples) * rcp(max(0.5, cen_mot_len)));

    // add center color and weight to background
    bg_acc += float4(cen_color, 1.0) * cen_weight;
    total_samples += 1.0;

    float3 fill_col = bg_acc.rgb * rcp(bg_acc.w);
    float4 acc = (bg_acc + fg_acc) * rcp(total_samples);

    // fill the missing data with background + center color
    // instead of only center in order to prevent artifacts
    acc.rgb += saturate(1.0 - acc.w) * fill_col;

    o = OutColor(acc.rgb);
}

void PS_TileDownHor(PS_ARGS2)
{
    float3 max_motion = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        float2 tap_uv = float2(floor(i.vpos.x) * K + 0.5 + x, i.vpos.y) * BUFFER_PIXEL_SIZE;
        float2 motion = GetMotion(tap_uv);
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);
    }

    o = max_motion.xy;
}

void PS_TileDownVert(PS_ARGS2)
{
    float3 max_motion = 0;

    [loop]for(uint y = 0; y < K; y++)
    {
        float2 tap_pos = float2(i.vpos.x, floor(i.vpos.y) * K + 0.5 + y);
        float2 motion = Fetch(sTileFstTex, tap_pos).xy;
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);
    }

    o = max_motion.xy;
}

void PS_NeighbourMax(PS_ARGS2)
{
    float3 max_motion = 0;

    [loop]for(uint j = 0; j < 25; j++)
    {
        float2 offs = BOX_OFFS[j];
        float2 tap_pos = i.vpos.xy + offs;
        float2 motion = Fetch(sTileSndTex, tap_pos).xy;
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z)
        {
            bool is_diag = abs(offs.x * offs.y) > 0.0;
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

    o = LimitMotionAndLen(max_motion.xy).xy;
}

// better performance to always store in the texture
// the HQ implementation is the other way around
void PS_Info(PS_ARGS4)
{
    float3 uv_and_z = float3(i.uv, GetDepth(i.uv));

#if V_MB_USE_MIN_FILTER
    // apply min filter to remove some artifacts
    [loop]for(uint j = 1; j < 9; j++)
    {
        float2 tap_uv = i.uv + BOX_OFFS[j] * BUFFER_PIXEL_SIZE;
        float tap_z = GetDepth(tap_uv);

        if(tap_z < uv_and_z.z) uv_and_z = float3(tap_uv, tap_z);
    }
#endif

    float3 mot_and_len = LimitMotionAndLen(GetMotion(uv_and_z.xy));
    float2 norm_mot = mot_and_len.xy * rcp(max(1e-15, mot_and_len.z));

    // x = motion px len, y = depth, zw = norm motion
    o = float4(mot_and_len.z, uv_and_z.z, norm_mot);
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MOT_BLUR \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor;  RenderTarget = MotBlur::TileFstTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Info;         RenderTarget = MotBlur::InfoTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_BlurAndDraw; }

} // namespace end
