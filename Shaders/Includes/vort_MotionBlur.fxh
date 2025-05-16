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

// Main difference in performance between this variant and the cheap one
// comes from the compute shader which is used to write next motion vectors

// Besides the perf improvement, prev color texture must be the exact
// same format as the color texture otherwise the discarding logic breaks

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
texture2D PrevMVTex   { TEX_SIZE(0) TEX_RG16 };
texture2D NextMVTex   { TEX_SIZE(0) TEX_RG16 };
texture2D PrevMaxTex  { TEX_SIZE(0) TEX_RG16 };
texture2D NextMaxTex  { TEX_SIZE(0) TEX_RG16 };
texture2D BlurTex     { TEX_SIZE(0) TEX_COLOR_FMT };
texture2D PrevCTex    { TEX_SIZE(0) TEX_COLOR_FMT }; // must match backbuffer format
texture2D PrevZTex    { TEX_SIZE(0) TEX_R16 };

sampler2D sTileFstTex  { Texture = TileFstTex; SAM_POINT };
sampler2D sTileSndTex  { Texture = TileSndTex; SAM_POINT };
sampler2D sNeighMaxTex { Texture = NeighMaxTex; SAM_POINT };
sampler2D sPrevMVTex   { Texture = PrevMVTex; SAM_POINT };
sampler2D sNextMVTex   { Texture = NextMVTex; SAM_POINT };
sampler2D sPrevMaxTex  { Texture = PrevMaxTex; SAM_POINT };
sampler2D sNextMaxTex  { Texture = NextMaxTex; SAM_POINT };
sampler2D sBlurTex     { Texture = BlurTex; SAM_POINT };
sampler2D sPrevCTex    { Texture = PrevCTex; };
sampler2D sPrevZTex    { Texture = PrevZTex; };

storage2D stNextMVTex { Texture = NextMVTex; };
storage2D stNextMaxTex { Texture = NextMaxTex; };

#if V_MB_USE_MIN_FILTER
    texture2D PrevInfoTex { TEX_SIZE(0) TEX_RGBA16 };
    texture2D NextInfoTex { TEX_SIZE(0) TEX_RGBA16 };
    sampler2D sPrevInfoTex { Texture = PrevInfoTex; };
    sampler2D sNextInfoTex { Texture = NextInfoTex; };
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float3 InColor(float2 uv)
{
    float3 c = ApplyLinCurve(Sample(sPrevCTex, uv).rgb);

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
static const float2 CIRCLE_OFFS[8] = {
    float2(1, 0), float2(1, 1), float2(0, 1), float2(-1, 1),
    float2(-1, 0), float2(-1, -1), float2(0, -1), float2(1, -1)
};
static const float2 LINE_OFFS[2] = { float2(1, 1), float2(-1, -1) };
static const float2 LONG_LINE_OFFS[4] = { float2(1, 1), float2(1, 1), float2(-1, -1), float2(-1, -1) };

float2 GetDebugMotion(float2 uv)
{
    // % of max motion length (round for perfect pixel movement)
    float2 motion = round(2.0 * ML * (UI_MB_DebugLen * 0.01));

    if(UI_MB_DebugUseRepeat)
    {
        switch(UI_MB_DebugUseRepeat)
        {
            case 1: { motion = motion.xx * CIRCLE_OFFS[frame_count % 8]; break; }
            case 2: { motion *= LONG_LINE_OFFS[frame_count % 4]; break; }
            case 3: { motion *= LINE_OFFS[frame_count % 2]; break; }
        }
    }
    else if(UI_MB_DebugPoint)
    {
        motion = NORM(float2(0.5,0.5) - uv) * BUFFER_SCREEN_SIZE;
    }
    else if(UI_MB_DebugZCen > 0.0)
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

float4 CalcInfo(float3 uv_and_z, sampler mot_samp)
{
    float2 motion = Sample(mot_samp, uv_and_z.xy).xy; // already limited
    float mot_len = length(motion);
    float2 norm_mot = motion * rcp(max(1e-15, mot_len));

#if V_MB_USE_MIN_FILTER
    float depth = uv_and_z.z;
#else
    float depth = Sample(sPrevZTex, uv_and_z.xy).x;
#endif

    return float4(mot_len, depth, norm_mot);
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Blur(PS_ARGS4)
{
    // use prev frame as current one

    // 1 = prev, 2 = next
    // motion vectors are already scaled and in correct units and direction

    float3 cen_color = InColor(i.uv);
    float2 max_motion0 = Sample(sPrevMaxTex, i.uv).xy;
    float2 max_motion1 = Sample(sNextMaxTex, i.uv).xy;
    float max_mot_len0 = length(max_motion0);
    float max_mot_len1 = length(max_motion1);

    // must use the same uv here as the samples in the loop
    // x = motion px len, y = depth, zw = normalized motion
#if V_MB_USE_MIN_FILTER
    float4 cen_info0 = Sample(sPrevInfoTex, i.uv);
    float4 cen_info1 = Sample(sNextInfoTex, i.uv);
#else
    float4 cen_info0 = CalcInfo(float3(i.uv, 0), sPrevMVTex);
    float4 cen_info1 = CalcInfo(float3(i.uv, 0), sNextMVTex);
#endif

    float cen_mot_len0 = cen_info0.x;
    float cen_mot_len1 = cen_info1.x;
    float cen_z = cen_info0.y; // doesn't matter prev or next
    float2 cen_motion0 = cen_info0.zw * cen_mot_len0;
    float2 cen_motion1 = cen_info1.zw * cen_mot_len1;

#if DEBUG_TILES
    if(1) { o = float4(DebugMotion(-max_motion1 * BUFFER_PIXEL_SIZE), 1); return; }
#endif

#if DEBUG_NEXT_MV
    if(1) { o = float4(DebugMotion(-cen_motion1 * BUFFER_PIXEL_SIZE), 1); return; }
#endif

    // early out when less than 2px movement
    if(max_mot_len0 < 1.0 && max_mot_len1 < 1.0) { o = float4(OutColor(cen_color), 1.0); return; }

    // don't change without solid reason
    uint half_samples = clamp(ceil(max(max_mot_len0, max_mot_len1) * 0.5), 3, max(3, UI_MB_MaxSamples));

    // odd amount of samples so max motion gets 1 more sample than center motion
    if(half_samples % 2 == 0) half_samples += 1;

    float2 max_norm_mot0 = max_motion0 * rcp(max(1e-15, max_mot_len0));
    float2 cen_norm_mot0 = cen_motion0 * rcp(max(1e-15, cen_mot_len0));

    float2 max_norm_mot1 = max_motion1 * rcp(max(1e-15, max_mot_len1));
    float2 cen_norm_mot1 = cen_motion1 * rcp(max(1e-15, cen_mot_len1));

    // xy = norm motion (direction), z = motion length, w = how parallel to center dir
    float4 max_main0 = float4(max_norm_mot0, max_mot_len0, cen_mot_len0 < 1.0 ? 1.0 : abs(dot(cen_norm_mot0, max_norm_mot0)));
    float4 max_main1 = float4(max_norm_mot1, max_mot_len1, cen_mot_len1 < 1.0 ? 1.0 : abs(dot(cen_norm_mot1, max_norm_mot1)));

    // don't lose half the samples when there is no center px motion
    // helps when an object is moving but the background isn't
    float4 cen_main0 = cen_mot_len0 < 1.0 ? max_main0 : float4(cen_norm_mot0, cen_mot_len0, 1.0);
    float4 cen_main1 = cen_mot_len1 < 1.0 ? max_main1 : float4(cen_norm_mot1, cen_mot_len1, 1.0);

    // negated in second direction to remove visible gap
    float2 tap_noise = (GetIGN(i.vpos.xy, 63) - 0.5) * float2(1, -1);
    float2 z_scales = 100.0 * float2(1, -1); // controls blending
    float inv_half_samples = rcp(float(half_samples));
    float px_to_step0 = rcp(inv_half_samples * max_mot_len0);
    float px_to_step1 = rcp(inv_half_samples * max_mot_len1);

    float4 bg_acc = 0;
    float4 fg_acc = 0;

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // switch between max and center
        bool use_max = j % 2 == 0;
        float4 m0 = use_max ? max_main0 : cen_main0;
        float4 m1 = use_max ? max_main1 : cen_main1;

        float2 st = float(j) + 0.5 + tap_noise;
        float2 motion0 = m0.xy * m0.zz * BUFFER_PIXEL_SIZE;
        float2 motion1 = m1.xy * m1.zz * BUFFER_PIXEL_SIZE;
        float2 tap_uv0 = i.uv - (st.x * inv_half_samples) * motion0;
        float2 tap_uv1 = i.uv - (st.y * inv_half_samples) * motion1;

        // x = motion px len, y = depth, zw = norm motion
    #if V_MB_USE_MIN_FILTER
        float4 tap_info0 = Sample(sPrevInfoTex, tap_uv0);
        float4 tap_info1 = Sample(sNextInfoTex, tap_uv1);
    #else
        float4 tap_info0 = CalcInfo(float3(tap_uv0, 0), sPrevMVTex);
        float4 tap_info1 = CalcInfo(float3(tap_uv1, 0), sNextMVTex);
    #endif

        float tap_mot_len0 = tap_info0.x;
        float tap_mot_len1 = tap_info1.x;

        float tap_z0 = tap_info0.y;
        float tap_z1 = tap_info1.y;

        float2 tap_norm_mot0 = tap_info0.zw;
        float2 tap_norm_mot1 = tap_info1.zw;

        // x = bg, y = fg
        float2 depth_cmp0 = saturate(0.5 + z_scales * (tap_z0 - cen_z));
        float2 depth_cmp1 = saturate(0.5 + z_scales * (tap_z1 - cen_z));

        float2 spread_cmp0 = saturate(float2(cen_mot_len0, tap_mot_len0) * px_to_step0 - max(0.0, st.x - 1.0));
        float2 spread_cmp1 = saturate(float2(cen_mot_len1, tap_mot_len1) * px_to_step1 - max(0.0, st.y - 1.0));

        // check for mismatch between motion directions
        float2 dir_w0 = float2(m0.w, abs(dot(tap_norm_mot0, m0.xy)));
        float2 dir_w1 = float2(m1.w, abs(dot(tap_norm_mot1, m1.xy)));

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
    float cen_weight = saturate(0.05 * float(half_samples) * rcp(Max3(0.5, cen_mot_len0, cen_mot_len1)));

    // add center color and weight to background
    bg_acc += float4(cen_color, 1.0) * cen_weight;
    total_samples += 1.0;

    float3 fill_col = bg_acc.rgb * rcp(bg_acc.w);
    float4 acc = (bg_acc + fg_acc) * rcp(total_samples);

    // fill the missing data with background + center color
    // instead of only center in order to prevent artifacts
    acc.rgb += saturate(1.0 - acc.w) * fill_col;

    o = float4(OutColor(acc.rgb), 1.0);
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

void PS_PrevFeat(VSOUT i, out PSOUT2 o)
{
    o.t0 = float4(SampleGammaColor(i.uv), 1);
    o.t1 = GetDepth(i.uv);
}

void PS_PrevMV(VSOUT i, out PSOUT4 o)
{
    // store prev motion and max motion in px and correct direction
    o.t0 = LimitMotionAndLen(GetMotion(i.uv)).xy;
    o.t1 = Sample(sNeighMaxTex, i.uv + GetTileOffs(i.vpos.xy)).xy;

    // reset next_mv to -prev_mv not 0
    // because it's better to have wrong motion than no motion
    // massive help with disocclusions due to vectors being estimated
    // if in-game velocity is used (both static and dynamic objects)
    // then this can safely be changed to 0
    o.t2 = -o.t0;
    o.t3 = -o.t1;
}

void CS_NextMV(CS_ARGS)
{
    float2 pos = i.id.xy + 0.5;
    float2 uv = pos * BUFFER_PIXEL_SIZE;
    float2 next_mv = GetMotion(uv);
    float2 prev_uv = uv + (next_mv * BUFFER_PIXEL_SIZE);

#if DEBUG_BLUR
    if(!UI_MB_DebugUseRepeat) prev_uv = uv;
#endif

    float3 prev_c = Sample(sPrevCTex, prev_uv).rgb;
    float3 next_c = SampleGammaColor(uv);

    float2 prev_cz = float2(dot(A_THIRD, prev_c), Sample(sPrevZTex, prev_uv).x);
    float2 next_cz = float2(dot(A_THIRD, next_c), GetDepth(uv));
    float2 diff = abs(prev_cz - next_cz);
    bool is_correct_mv = diff.x < 1e-6 || diff.y < 1e-3; //tested

    if(ValidateUV(uv) && ValidateUV(prev_uv) && is_correct_mv)
    {
        // that `round` is mandatory, so much debugging....
        uint2 new_id = round(prev_uv * BUFFER_SCREEN_SIZE - 0.5);
        float2 next_max = Sample(sNeighMaxTex, uv + GetTileOffs(pos)).xy;

        // store next motion and max motion in px and correct direction
        tex2Dstore(stNextMVTex, new_id, float4(-LimitMotionAndLen(next_mv).xy,1,1));
        tex2Dstore(stNextMaxTex, new_id, float4(-next_max,1,1));
    }
}

#if DEBUG_BLUR
void PS_WriteNewFrame(PS_ARGS3)
{
    float3 result = SampleGammaColor(i.uv);

    if(UI_MB_DebugUseRepeat)
    {
        float2 prev_uv = i.uv + GetDebugMotion(i.uv);
        float4 prev = Sample(sPrevCTex, prev_uv);

        if(prev.a > 0.0) result = prev.rgb;
    }

    o = result;
}
#endif

#if V_MB_USE_MIN_FILTER
void PS_Info(VSOUT i, out PSOUT2 o)
{
    float3 uv_and_z = float3(i.uv, Sample(sPrevZTex, i.uv).x);

    // apply min filter to remove some artifacts
    [loop]for(uint j = 1; j < 9; j++)
    {
        float2 tap_uv = i.uv + BOX_OFFS[j] * BUFFER_PIXEL_SIZE;
        float tap_z = Sample(sPrevZTex, tap_uv).x;

        if(tap_z < uv_and_z.z) uv_and_z = float3(tap_uv, tap_z);
    }

    o.t0 = CalcInfo(uv_and_z, sPrevMVTex);
    o.t1 = CalcInfo(uv_and_z, sNextMVTex);
}
#endif

void PS_Draw(PS_ARGS3) { o = Sample(sBlurTex, i.uv).rgb; }

/*******************************************************************************
    Passes
*******************************************************************************/

#if DEBUG_BLUR
    #define PASS_MB_DEBUG pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteNewFrame; }
#else
    #define PASS_MB_DEBUG
#endif

#if V_MB_USE_MIN_FILTER
    #define PASS_MB_INFO \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Info; RenderTarget0 = MotBlur::PrevInfoTex; RenderTarget1 = MotBlur::NextInfoTex; }
#else
    #define PASS_MB_INFO
#endif

#define PASS_MOT_BLUR \
    PASS_MB_DEBUG \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor; RenderTarget = MotBlur::TileFstTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTex; } \
    pass { ComputeShader = MotBlur::CS_NextMV<GS_X, GS_Y>; DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, GS_X); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, GS_Y); } \
    PASS_MB_INFO \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; RenderTarget = MotBlur::BlurTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_PrevFeat; RenderTarget0 = MotBlur::PrevCTex; RenderTarget1 = MotBlur::PrevZTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_PrevMV; RenderTarget0 = MotBlur::PrevMVTex; RenderTarget1 = MotBlur::PrevMaxTex; RenderTarget2 = MotBlur::NextMVTex; RenderTarget3 = MotBlur::NextMaxTex; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Draw; }

} // namespace end
