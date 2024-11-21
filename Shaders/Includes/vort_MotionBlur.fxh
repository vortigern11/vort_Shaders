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

// max length of motion (2 * tile size)
static const float ML = float(K * 2);

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D TileFstTexVort  { Width = TILE_WIDTH; Height = BUFFER_HEIGHT; TEX_RG16 };
texture2D TileSndTexVort  { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };
texture2D NeighMaxTexVort { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };
texture2D PrevMVTexVort   { TEX_SIZE(0) TEX_RGBA16 };
texture2D NextMVTexVort   { TEX_SIZE(0) TEX_RGBA16 };
texture2D PrevInfoTexVort { TEX_SIZE(0) TEX_RGBA16 };
texture2D NextInfoTexVort { TEX_SIZE(0) TEX_RGBA16 };
texture2D BlurTexVort     { TEX_SIZE(0) TEX_RGBA16 };
texture2D PrevFeatTexVort { TEX_SIZE(0) TEX_RGBA16 };

sampler2D sTileFstTexVort  { Texture = TileFstTexVort; SAM_POINT };
sampler2D sTileSndTexVort  { Texture = TileSndTexVort; SAM_POINT };
sampler2D sNeighMaxTexVort { Texture = NeighMaxTexVort; SAM_POINT };
sampler2D sPrevMVTexVort   { Texture = PrevMVTexVort; SAM_POINT };
sampler2D sNextMVTexVort   { Texture = NextMVTexVort; SAM_POINT };
sampler2D sPrevInfoTexVort { Texture = PrevInfoTexVort; };
sampler2D sNextInfoTexVort { Texture = NextInfoTexVort; };
sampler2D sBlurTexVort     { Texture = BlurTexVort; SAM_POINT };
sampler2D sPrevFeatTexVort { Texture = PrevFeatTexVort; };

storage2D stNextMVTexVort   { Texture = NextMVTexVort; };

/*******************************************************************************
    Functions
*******************************************************************************/

float3 InColor(float2 uv)
{
    return Sample(sPrevFeatTexVort, uv).rgb;
}

float3 OutColor(float3 c)
{
#if IS_SRGB
    c = Tonemap::ApplyReinhardMax(c, T_MOD);
#endif

    return ApplyGammaCurve(c);
}

#if DEBUG_BLUR
static const float2 circle_offs[8] = {
    float2(1, 0), float2(1, 1), float2(0, 1), float2(-1, 1),
    float2(-1, 0), float2(-1, -1), float2(0, -1), float2(1, -1)
};
static const float2 line_offs[2] = { float2(1, 0), float2(-1, 0) };
static const float2 long_line_offs[4] = { float2(1, 0), float2(1, 0), float2(-1, 0), float2(-1, 0) };

float2 GetDebugMotion(float2 uv)
{
    // % of max motion length
    float2 motion = 2.0 * ML * (UI_MB_DebugLen * 0.01);

    if(UI_MB_DebugUseRepeat)
    {
        float2 curr_offs = 0;

        switch(UI_MB_DebugUseRepeat)
        {
            case 1: { curr_offs = circle_offs[frame_count % 8]; break; }
            case 2: { curr_offs = long_line_offs[frame_count % 4]; break; }
            case 3: { curr_offs = line_offs[frame_count % 2]; break; }
        }

        motion = motion.xx * curr_offs;
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
    // use prev frame as current one

    // 1 = prev, 2 = next
    // motion vectors are already scaled and in correct units and direction

    float3 cen_color = InColor(i.uv);
    float2 max_motion1 = Sample(sPrevMVTexVort, i.uv).zw;
    float2 max_motion2 = Sample(sNextMVTexVort, i.uv).zw;
    float max_mot_len1 = length(max_motion1);
    float max_mot_len2 = length(max_motion2);

    // must use the same uv here as the samples in the loop
    // x = motion px len, y = depth, zw = normalized motion
    float4 cen_info1 = Sample(sPrevInfoTexVort, i.uv);
    float4 cen_info2 = Sample(sNextInfoTexVort, i.uv);
    float cen_mot_len1 = cen_info1.x;
    float cen_mot_len2 = cen_info2.x;
    float cen_z = cen_info1.y; // doesn't matter prev or next
    float2 cen_motion1 = cen_info1.zw * cen_mot_len1;
    float2 cen_motion2 = cen_info2.zw * cen_mot_len2;

    // due to tile randomization center motion might be greater
    if(max_mot_len1 < cen_mot_len1) { max_mot_len1 = cen_mot_len1; max_motion1 = cen_motion1; }
    if(max_mot_len2 < cen_mot_len2) { max_mot_len2 = cen_mot_len2; max_motion2 = cen_motion2; }

#if DEBUG_TILES
    if(1) { return float4(DebugMotion(-max_motion2 * BUFFER_PIXEL_SIZE), 1); }
#endif

#if DEBUG_NEXT_MV
    if(1) { return float4(DebugMotion(-cen_motion2 * BUFFER_PIXEL_SIZE), 1); }
#endif

    // early out when less than 2px movement
    if(max_mot_len1 < 1.0 && max_mot_len2 < 1.0) return float4(OutColor(cen_color), 1.0);

    // don't change without solid reason
    uint half_samples = clamp(ceil(max(max_mot_len1, max_mot_len2)), 3, max(3, UI_MB_MaxSamples));

    // odd amount of samples so max motion gets 1 more sample than center motion
    if(half_samples % 2 == 0) half_samples += 1;

    float2 max_mot_norm1 = max_motion1 * RCP(max_mot_len1);
    float2 cen_mot_norm1 = cen_motion1 * RCP(cen_mot_len1);

    float2 max_mot_norm2 = max_motion2 * RCP(max_mot_len2);
    float2 cen_mot_norm2 = cen_motion2 * RCP(cen_mot_len2);

    // xy = norm motion (direction), z = how parallel to center dir
    float3 max_main1 = float3(max_mot_norm1, cen_mot_len1 < 1.0 ? 1.0 : abs(dot(cen_mot_norm1, max_mot_norm1)));
    float3 max_main2 = float3(max_mot_norm2, cen_mot_len2 < 1.0 ? 1.0 : abs(dot(cen_mot_norm2, max_mot_norm2)));

    // don't lose half the samples when there is no center px motion
    // helps when an object is moving but the background isn't
    float3 cen_main1 = cen_mot_len1 < 1.0 ? max_main1 : float3(cen_mot_norm1, 1.0);
    float3 cen_main2 = cen_mot_len2 < 1.0 ? max_main2 : float3(cen_mot_norm2, 1.0);

    // dither looks better than IGN
    float2 sample_noise = Dither(i.vpos.xy, 0.25) * float2(1, -1); // negated in second direction to remove visible gap
    float2 z_scales = Z_FAR_PLANE * float2(1, -1); // touch only if you change depth_cmp
    float inv_half_samples = rcp(float(half_samples));
    float steps_to_px1 = inv_half_samples * max_mot_len1;
    float steps_to_px2 = inv_half_samples * max_mot_len2;

    float4 bg_acc = 0;
    float4 fg_acc = 0;

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // switch between max and center
        bool use_max = j % 2 == 0;
        float3 m1 = use_max ? max_main1 : cen_main1;
        float3 m2 = use_max ? max_main2 : cen_main2;

        float2 step = float(j) + 0.5 + sample_noise;
        float2 sample_uv1 = i.uv - (step.x * steps_to_px1) * (m1.xy * BUFFER_PIXEL_SIZE);
        float2 sample_uv2 = i.uv - (step.y * steps_to_px2) * (m2.xy * BUFFER_PIXEL_SIZE);

        // x = motion px len, y = depth, zw = norm motion
        float4 sample_info1 = Sample(sPrevInfoTexVort, sample_uv1);
        float4 sample_info2 = Sample(sNextInfoTexVort, sample_uv2);

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
        float2 spread_cmp1 = saturate(float2(cen_mot_len1, sample_mot_len1) - max(0.0, step.x - 1.0) * steps_to_px1);
        float2 spread_cmp2 = saturate(float2(cen_mot_len2, sample_mot_len2) - max(0.0, step.y - 1.0) * steps_to_px2);

        // check for mismatch between motion directions
        float2 dir_w1 = float2(m1.z, abs(dot(sample_mot_norm1, m1.xy)));
        float2 dir_w2 = float2(m2.z, abs(dot(sample_mot_norm2, m2.xy)));

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
    float cen_weight = saturate(0.05 * float(half_samples) * rcp(Max3(0.5, cen_mot_len1, cen_mot_len2)));

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

float4 CalcPrevFeat(VSOUT i)
{
    float3 c = SampleLinColor(i.uv);

#if IS_SRGB
    // store in HDR for perf
    c = Tonemap::InverseReinhardMax(c, T_MOD);
#endif

    return float4(c, GetDepth(i.uv));
}

float4 CalcPrevMV(VSOUT i)
{
    float2 prev_max_mot = Sample(sNeighMaxTexVort, i.uv + GetTileOffs(i.vpos.xy)).xy;
    float2 prev_cen_mot = LimitMotionAndLen(GetMotion(i.uv)).xy;

    // store prev motion and max motion in px, scaled and correct direction
    return float4(prev_cen_mot, prev_max_mot);
}

void StoreNextMV(uint2 id)
{
    float2 pos = id + 0.5;
    float2 uv = pos * BUFFER_PIXEL_SIZE;

    float4 next_mv; // xy = center, zw = max

    next_mv.xy = GetMotion(uv);
    next_mv.zw = Sample(sNeighMaxTexVort, uv + GetTileOffs(pos)).xy;

    float2 prev_uv = uv + (next_mv.xy * BUFFER_PIXEL_SIZE);

#if DEBUG_BLUR
    if(!UI_MB_DebugUseRepeat) prev_uv = uv;
#endif

    float4 prev_feat = Sample(sPrevFeatTexVort, prev_uv);
    float3 prev_c = prev_feat.rgb;
    float3 next_c = SampleLinColor(uv);

#if IS_SRGB
    prev_c = Tonemap::ApplyReinhardMax(prev_c, T_MOD);
#endif

    float2 prev_cz = float2(dot(A_THIRD, prev_c), prev_feat.a);
    float2 next_cz = float2(dot(A_THIRD, next_c), GetDepth(uv));
    float2 diff = abs(prev_cz - next_cz);
    bool is_correct_mv = min(diff.x, diff.y) < max(EPSILON, UI_MB_Thresh);

    if(ValidateUV(uv) && ValidateUV(prev_uv) && is_correct_mv)
    {
        next_mv.xy = LimitMotionAndLen(next_mv.xy).xy;
        next_mv = -next_mv;

        // that `round` is mandatory, so much debugging....
        uint2 new_id = round(prev_uv * BUFFER_SCREEN_SIZE - 0.5);

        // store next motion and max motion in px, scaled and correct direction
        tex2Dstore(stNextMVTexVort, new_id, next_mv);
    }
}

/*******************************************************************************
    Shaders
*******************************************************************************/

#if DEBUG_BLUR
void PS_WriteNew(PS_ARGS3) {
    float3 result = SampleGammaColor(i.uv);

    if(UI_MB_DebugUseRepeat)
    {
        float2 prev_uv = i.uv + GetDebugMotion(i.uv);
        float4 prev = Sample(sPrevFeatTexVort, prev_uv);

        if(prev.a > 0.0) result = OutColor(prev.rgb);
    }

    o = result;
}
#endif

void PS_Info(VSOUT i, out PSOUT2 o)
{
    float3 closest = float3(i.uv, Sample(sPrevFeatTexVort, i.uv).a);

    if(UI_MB_UseMinFilter)
    {
        // apply min filter to remove some artifacts
        [loop]for(uint j = 1; j < S_BOX_OFFS1; j++)
        {
            float2 sample_uv = i.uv + BOX_OFFS1[j] * BUFFER_PIXEL_SIZE;
            float sample_z = Sample(sPrevFeatTexVort, sample_uv).a;

            if(sample_z < closest.z) closest = float3(sample_uv, sample_z);
        }
    }

    float2 prev_motion = Sample(sPrevMVTexVort, closest.xy).xy;
    float2 next_motion = Sample(sNextMVTexVort, closest.xy).xy;

    float prev_mot_len = length(prev_motion);
    float next_mot_len = length(next_motion);

    float2 prev_mot_norm = prev_motion * RCP(prev_mot_len);
    float2 next_mot_norm = next_motion * RCP(next_mot_len);

    // x = motion px len, y = depth, zw = norm motion
    o.t0 = float4(prev_mot_len, closest.z, prev_mot_norm);
    o.t1 = float4(next_mot_len, closest.z, next_mot_norm);
}

void PS_TileDownHor(PS_ARGS2)  { o = CalcTileDownHor(i);  }
void PS_TileDownVert(PS_ARGS2) { o = CalcTileDownVert(i); }
void PS_NeighbourMax(PS_ARGS2) { o = CalcNeighbourMax(i); }
void CS_NextMV(CS_ARGS)        { StoreNextMV(i.id.xy); }
void PS_Blur(PS_ARGS4)         { o = CalcBlur(i); }
void PS_PrevFeat(PS_ARGS4)     { o = CalcPrevFeat(i); }
void PS_Draw(PS_ARGS3)         { o = Sample(sBlurTexVort, i.uv).rgb; }

// reset next_mv to -prev_mv not 0
// because it's better to have wrong motion than no motion
// already tested with custom reset logic:
// in order to discard motion which is incorrect,
// a whole lot of "correct" motion goes away with it
void PS_PrevMV(VSOUT i, out PSOUT2 o) { o.t0 = CalcPrevMV(i); o.t1 = -o.t0; }

/*******************************************************************************
    Passes
*******************************************************************************/

#if DEBUG_BLUR
    #define PASS_MB_DEBUG pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteNew; }
#else
    #define PASS_MB_DEBUG
#endif

#define PASS_MOT_BLUR \
    PASS_MB_DEBUG \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor; RenderTarget = MotBlur::TileFstTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTexVort; } \
    pass { ComputeShader = MotBlur::CS_NextMV<GS_X, GS_Y>; DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, GS_X); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, GS_Y); } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Info; RenderTarget0 = MotBlur::PrevInfoTexVort; RenderTarget1 = MotBlur::NextInfoTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur; RenderTarget = MotBlur::BlurTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_PrevFeat; RenderTarget = MotBlur::PrevFeatTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_PrevMV; RenderTarget0 = MotBlur::PrevMVTexVort; RenderTarget1 = MotBlur::NextMVTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Draw; }

} // namespace end
