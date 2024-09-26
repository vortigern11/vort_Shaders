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

// older graphics cards get worse performance
#define MB_USE_COMPUTE CAN_COMPUTE && V_ENABLE_MOT_BLUR == 2

// scale the tile number (40px at 1080p)
#define K (BUFFER_HEIGHT / 27)
#define TILE_WIDTH  (BUFFER_WIDTH / K)
#define TILE_HEIGHT (BUFFER_HEIGHT / K)

// compute shaders group size
#define GS 16 // best performance tested

#define DEG_45 0.7854
#define DEG_20 0.35

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

#if IS_SRGB
    texture2D BlurTexVort { TEX_SIZE(0) TEX_RGBA8 };
#else
    texture2D BlurTexVort { TEX_SIZE(0) TEX_RGBA16 };
#endif

texture2D PrevFeatTexVort { TEX_SIZE(0) TEX_RGBA16 };
texture2D InfoTexVort { TEX_SIZE(0) TEX_RGBA16 };
texture2D TileFstTexVort { Width = TILE_WIDTH; Height = BUFFER_HEIGHT; TEX_RG16 };
texture2D TileSndTexVort { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };
texture2D NeighMaxTexVort { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };

sampler2D sBlurTexVort { Texture = BlurTexVort; };
sampler2D sPrevFeatTexVort { Texture = PrevFeatTexVort; };
sampler2D sInfoTexVort { Texture = InfoTexVort; SAM_POINT };
sampler2D sTileFstTexVort { Texture = TileFstTexVort; SAM_POINT };
sampler2D sTileSndTexVort { Texture = TileSndTexVort; SAM_POINT };
sampler2D sNeighMaxTexVort { Texture = NeighMaxTexVort; SAM_POINT };

#if MB_USE_COMPUTE
    storage2D stInfoTexVort { Texture = InfoTexVort; };
    storage2D stTileFstTexVort { Texture = TileFstTexVort; };
    storage2D stTileSndTexVort { Texture = TileSndTexVort; };
    storage2D stNeighMaxTexVort { Texture = NeighMaxTexVort; };
    storage2D stBlurTexVort { Texture = BlurTexVort; };
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float3 InColor(float3 c)
{
    c = ForceLinearCurve(c);

#if IS_SRGB
    c = Tonemap::InverseReinhardMax(c, 1.1);
#endif

    return c;
}

float3 OutColor(float3 c)
{
#if IS_SRGB
    c = Tonemap::ApplyReinhardMax(c, 1.1);
#endif

    return ForceGammaCurve(c);
}

float2 GetMotion(float2 uv)
{
    // motion must be in pixel units
    // and halved because of 2 sampling directions
    float2 motion = (SampleMotion(uv).xy * 0.5) * (UI_MB_Length * BUFFER_SCREEN_SIZE);

    // for debugging
    if(dot(UI_MB_DebugLen, 1) > 0) motion = float2(UI_MB_DebugLen);

    // not sure if needed, so commented out for now
    // limit motion max to tile size
    /* float old_mot_len = length(motion); */
    /* float new_mot_len = min(old_mot_len, float(K)); */

    /* if(old_mot_len > float(K)) motion *= new_mot_len / old_mot_len; */

    return motion;
}

float GetRelAngle(float2 v1, float2 v2)
{
    // var. 1: ACOS(dot(v1, v2) * RSQRT(dot(v1, v1) * dot(v2, v2)))
    // var. 2: ACOS(dot(v1, v2) * RCP(length(v1) * length(v2))
    // var. 3: ACOS(dot(NORM(v1), NORM(v2)));

    return ACOS(dot(v1, v2) * RSQRT(dot(v1, v1) * dot(v2, v2)));
}

float GetDirWeight(float angle1, float angle2, float max_diff)
{
    // custom value > PI means vector length was 0
    if(angle1 > 3.5 || angle2 > 3.5) return 1.0;

    float rel_angle = abs(angle1 - angle2);

    if(rel_angle > PI) rel_angle = DOUBLE_PI - rel_angle;

    float ratio = max(0.0, rel_angle - 0.1) / max(0.1, max_diff - 0.1);

    // rel_angle < 6deg -> full weight
    // rel_angle > max_diff -> no weight
    return saturate(1.0 - ratio);
}

float4 Calc_Blur(float2 pos)
{
    float2 uv = pos * BUFFER_PIXEL_SIZE;

// debug motion vectors
#if V_ENABLE_MOT_BLUR == 9
    if(1) { return float4(DebugMotion(SampleMotion(uv)), 1); }
#endif

    float rand = GetR1(GetBlueNoise(pos).x, frame_count % 3 + 1);
    float2 sample_noise = (rand - 0.5) * float2(1, -1);
    float2 tiles_inv_size = K * BUFFER_PIXEL_SIZE;
    float2 tiles_uv_offs = (rand * 0.5 - 0.25) * tiles_inv_size;

    // don't randomize diagonally
    tiles_uv_offs *= sample_noise.x < 0.0 ? float2(1, 0) : float2(0, 1);

    float2 max_motion = Sample(sNeighMaxTexVort, uv + tiles_uv_offs).xy;
    float max_mot_len = length(max_motion);

    // x = motion px len, y = motion angle, z = curr depth, w = prev depth
    float4 cen_info = Sample(sInfoTexVort, uv);
    float2 cen_motion = GetMotion(uv);

    // due to tile randomization center motion might be greater
    if(max_mot_len < cen_info.x) { max_mot_len = cen_info.x; max_motion = cen_motion; }

// debug tiles
#if V_ENABLE_MOT_BLUR == 8
    if(1) { return float4(DebugMotion(max_motion * BUFFER_PIXEL_SIZE), 1); }
#endif

    // early out
    if(max_mot_len < 1.0) return 0;

    uint half_samples = clamp(floor(max_mot_len * 0.5), 3, 9);

    // odd amount of samples so max motion gets 1 more sample than center motion
    half_samples += half_samples % 2 == 0 ? 1 : 0;

    float inv_half_samples = rcp(float(half_samples));
    float2 z_scales = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE * float2(1, -1);

    float4 max_main;
    float4 cen_main;

    // xy = motion per sample in uv units
    max_main.xy = float2(inv_half_samples * (max_motion * BUFFER_PIXEL_SIZE));
    cen_main.xy = float2(inv_half_samples * (cen_motion * BUFFER_PIXEL_SIZE));

    // z = step to pixels scale, w = motion angle
    max_main.zw = float2(inv_half_samples * max_mot_len, atan2(max_motion.y, max_motion.x));
    cen_main.zw = float2(inv_half_samples * cen_info.x, cen_info.y);

    float4 bg_acc = 0.0;
    float4 fg_acc = 0.0;
    float total_weight = 0.0;

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // switch between max and center
        // xy = motion per sample in uv units
        // z = step to pixels scale, w = motion angle
        float4 m = j % 2 == 0 ? max_main : cen_main;

        // negated dither in the second direction
        // to remove the otherwise visible gap
        float2 step = float(j) + 0.5 + sample_noise;
        float4 uv_offs = step.xxyy * m.xyxy;

        float2 sample_uv1 = uv - uv_offs.xy;
        float2 sample_uv2 = uv + uv_offs.zw;

        // x = motion px len, y = motion angle, z = curr depth, w = prev depth
        float4 sample_info1 = Sample(sInfoTexVort, sample_uv1);
        float4 sample_info2 = Sample(sInfoTexVort, sample_uv2);

        float2 depthcmp1 = saturate(0.5 + z_scales * (sample_info1.z - cen_info.z));
        float2 depthcmp2 = saturate(0.5 + z_scales * (sample_info2.w - cen_info.w));

        // the `max` is to remove potential artifacts
        float2 spreadcmp1 = saturate(float2(cen_info.x, sample_info1.x) - max(0.0, step.x - 1.0) * m.z);
        float2 spreadcmp2 = saturate(float2(cen_info.x, sample_info2.x) - max(0.0, step.y - 1.0) * m.z);

        // don't contribute if sample's motion is in different direction
        float dir_w1 = GetDirWeight(m.w, sample_info1.y, DEG_20);
        float dir_w2 = GetDirWeight(m.w, sample_info2.y, DEG_20);

        // x = bg weight, y = fg weight
        float2 sample_w1 = (depthcmp1 * spreadcmp1) * dir_w1;
        float2 sample_w2 = (depthcmp2 * spreadcmp2) * dir_w2;

        float3 sample_color1 = InColor(SampleGammaColor(sample_uv1));
        float3 sample_color2 = InColor(Sample(sPrevFeatTexVort, sample_uv2).rgb);

        bg_acc += float4(sample_color1, 1.0) * sample_w1.x;
        fg_acc += float4(sample_color1, 1.0) * sample_w1.y;

        bg_acc += float4(sample_color2, 1.0) * sample_w2.x;
        fg_acc += float4(sample_color2, 1.0) * sample_w2.y;

        total_weight += dir_w1 + dir_w2;
    }

    // add center color and weight to background
    bg_acc += float4(InColor(SampleGammaColor(uv)), 1.0) * (inv_half_samples * 0.01);
    total_weight += 1.0;

    float3 bg_col = bg_acc.rgb * RCP(bg_acc.w);
    float4 sum_acc = bg_acc + fg_acc;

    // normalize
    sum_acc /= total_weight;

    // fill the missing data with background color
    // instead of center in order to counteract artifacts in some cases
    float3 c = sum_acc.rgb + saturate(1.0 - sum_acc.w) * bg_col;

    return float4(OutColor(c), 1.0);
}

float4 Calc_WriteInfo(float2 pos)
{
    float2 uv = pos * BUFFER_PIXEL_SIZE;
    float3 curr_uvz = float3(uv, 1.0);
    float prev_z = 1.0;

    // apply min filter to remove some artifacts
    [loop]for(int x = -1; x <= 1; x++)
    [loop]for(int y = -1; y <= 1; y++)
    {
        float2 sample_uv = uv + float2(x,y) * BUFFER_PIXEL_SIZE;
        float sample_curr_z = GetDepth(sample_uv);
        float sample_prev_z = Sample(sPrevFeatTexVort, sample_uv).a;

        if(sample_curr_z < curr_uvz.z) curr_uvz = float3(sample_uv, sample_curr_z);
        if(sample_prev_z < prev_z) prev_z = sample_prev_z;
    }

    float2 motion = GetMotion(curr_uvz.xy);
    float mot_len = length(motion);
    float mot_angle = mot_len > 0.0 ? atan2(motion.y, motion.x) : 5.0; // custom value

    // x = motion px len, y = motion angle, z = curr depth, w = prev depth
    return float4(mot_len, mot_angle, curr_uvz.z, prev_z);
}

float2 Calc_TileDownHor(float2 pos)
{
    float3 max_motion = 0;
    float3 avg_motion = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        float2 sample_uv = float2(floor(pos.x) * K + 0.5 + x, pos.y) * BUFFER_PIXEL_SIZE;
        float2 motion = GetMotion(sample_uv);
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);

        avg_motion += float3(motion, 1.0) * sq_len;
    }

    if(max_motion.z < 1.0) return 0;

    avg_motion.xy /= avg_motion.z;

    // max 45deg angle
    float rel_angle = GetRelAngle(avg_motion.xy, max_motion.xy);
    float dir_w = saturate(1.0 -  1.459 * max(0.0, rel_angle - 0.1));

    return lerp(avg_motion.xy, max_motion.xy, dir_w);
}

float2 Calc_TileDownVert(float2 pos)
{
    float3 max_motion = 0;
    float3 avg_motion = 0;

    [loop]for(uint y = 0; y < K; y++)
    {
        float2 sample_pos = float2(pos.x, floor(pos.y) * K + 0.5 + y);
        float2 motion = Fetch(sTileFstTexVort, sample_pos).xy;
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);

        avg_motion += float3(motion, 1.0) * sq_len;
    }

    if(max_motion.z < 1.0) return 0;

    avg_motion.xy /= avg_motion.z;

    // max 45deg angle
    float rel_angle = GetRelAngle(avg_motion.xy, max_motion.xy);
    float dir_w = saturate(1.0 -  1.459 * max(0.0, rel_angle - 0.1));

    return lerp(avg_motion.xy, max_motion.xy, dir_w);
}

float2 Calc_NeighbourMax(float2 pos)
{
    float3 max_motion = 0;

    [loop]for(int x = -1; x <= 1; x++)
    [loop]for(int y = -1; y <= 1; y++)
    {
        float2 sample_pos = pos + float2(x, y);
        float2 motion = Fetch(sTileSndTexVort, sample_pos).xy;
        float sq_len = dot(motion, motion);

        if(sq_len < 1.0) continue;

        float rel_angle = GetRelAngle(float2(-x, -y), motion);
        bool is_mot_in_center_dir = rel_angle < DEG_45;
        bool is_center = x == 0 && y == 0;

        if((is_center || is_mot_in_center_dir) && sq_len > max_motion.z)
            max_motion = float3(motion, sq_len);
    }

    return max_motion.xy;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

#if MB_USE_COMPUTE
    void CS_WriteInfo(CS_ARGS)    { tex2Dstore(stInfoTexVort,     i.id.xy, Calc_WriteInfo(i.id.xy + 0.5));         }
    void CS_TileDownHor(CS_ARGS)  { tex2Dstore(stTileFstTexVort,  i.id.xy, Calc_TileDownHor(i.id.xy + 0.5).xyxy);  }
    void CS_TileDownVert(CS_ARGS) { tex2Dstore(stTileSndTexVort,  i.id.xy, Calc_TileDownVert(i.id.xy + 0.5).xyxy); }
    void CS_NeighbourMax(CS_ARGS) { tex2Dstore(stNeighMaxTexVort, i.id.xy, Calc_NeighbourMax(i.id.xy + 0.5).xyxy); }
    void CS_Blur(CS_ARGS)         { tex2Dstore(stBlurTexVort,     i.id.xy, Calc_Blur(i.id.xy + 0.5));              }
#else
    void PS_WriteInfo(PS_ARGS4)    { o = Calc_WriteInfo(i.vpos.xy);    }
    void PS_TileDownHor(PS_ARGS2)  { o = Calc_TileDownHor(i.vpos.xy);  }
    void PS_TileDownVert(PS_ARGS2) { o = Calc_TileDownVert(i.vpos.xy); }
    void PS_NeighbourMax(PS_ARGS2) { o = Calc_NeighbourMax(i.vpos.xy); }
    void PS_Blur(PS_ARGS4)         { o = Calc_Blur(i.vpos.xy);         }
#endif

void PS_WritePrevFeat(PS_ARGS4) { o = float4(SampleGammaColor(i.uv), GetDepth(i.uv)); }

void PS_Draw(PS_ARGS3)
{
    float4 blur = Sample(sBlurTexVort, i.uv);

    if(blur.a < 1.0) discard;

    o = blur.rgb;
}

/*******************************************************************************
    Passes
*******************************************************************************/

#if MB_USE_COMPUTE
    #define PASS_MOT_BLUR \
        pass { ComputeShader = MotBlur::CS_WriteInfo<GS, GS>;    DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, GS); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, GS); } \
        pass { ComputeShader = MotBlur::CS_TileDownHor<GS, GS>;  DispatchSizeX = CEIL_DIV(TILE_WIDTH, GS);   DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, GS); } \
        pass { ComputeShader = MotBlur::CS_TileDownVert<GS, GS>; DispatchSizeX = CEIL_DIV(TILE_WIDTH, GS);   DispatchSizeY = CEIL_DIV(TILE_HEIGHT, GS);   } \
        pass { ComputeShader = MotBlur::CS_NeighbourMax<GS, GS>; DispatchSizeX = CEIL_DIV(TILE_WIDTH, GS);   DispatchSizeY = CEIL_DIV(TILE_HEIGHT, GS);   } \
        pass { ComputeShader = MotBlur::CS_Blur<GS, GS>;         DispatchSizeX = CEIL_DIV(BUFFER_WIDTH, GS); DispatchSizeY = CEIL_DIV(BUFFER_HEIGHT, GS); } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WritePrevFeat; RenderTarget = MotBlur::PrevFeatTexVort; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Draw; }
#else
    #define PASS_MOT_BLUR \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo;     RenderTarget = MotBlur::InfoTexVort;     } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor;   RenderTarget = MotBlur::TileFstTexVort;  } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert;  RenderTarget = MotBlur::TileSndTexVort;  } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax;  RenderTarget = MotBlur::NeighMaxTexVort; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Blur;          RenderTarget = MotBlur::BlurTexVort;     } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WritePrevFeat; RenderTarget = MotBlur::PrevFeatTexVort; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Draw; }
#endif

} // namespace end
