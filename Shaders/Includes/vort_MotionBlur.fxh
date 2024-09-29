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

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RGBA16 };
texture2D TileFstTexVort { Width = TILE_WIDTH; Height = BUFFER_HEIGHT; TEX_RG16 };
texture2D TileSndTexVort { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };
texture2D NeighMaxTexVort { Width = TILE_WIDTH; Height = TILE_HEIGHT; TEX_RG16 };

sampler2D sInfoTexVort { Texture = InfoTexVort; SAM_POINT };
sampler2D sTileFstTexVort { Texture = TileFstTexVort; SAM_POINT };
sampler2D sTileSndTexVort { Texture = TileSndTexVort; SAM_POINT };
sampler2D sNeighMaxTexVort { Texture = NeighMaxTexVort; SAM_POINT };

#if MB_USE_COMPUTE
    #if IS_SRGB
        texture2D BlurTexVort { TEX_SIZE(0) TEX_RGBA8 };
    #else
        texture2D BlurTexVort { TEX_SIZE(0) TEX_RGBA16 };
    #endif

    sampler2D sBlurTexVort { Texture = BlurTexVort; };

    storage2D stInfoTexVort { Texture = InfoTexVort; };
    storage2D stTileFstTexVort { Texture = TileFstTexVort; };
    storage2D stTileSndTexVort { Texture = TileSndTexVort; };
    storage2D stNeighMaxTexVort { Texture = NeighMaxTexVort; };
    storage2D stBlurTexVort { Texture = BlurTexVort; };
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float3 InColor(float2 uv)
{
    float3 c = SampleLinColor(uv);

#if IS_SRGB
    c = Tonemap::InverseReinhardMax(c, 1.4);
#endif

    return c;
}

float3 OutColor(float3 c)
{
#if IS_SRGB
    c = Tonemap::ApplyReinhardMax(c, 1.4);
#endif

#if MB_USE_COMPUTE
    return ForceGammaCurve(c);
#else
    return ApplyGammaCurve(c);
#endif
}

#if V_ENABLE_MOT_BLUR == 7
float2 GetDebugMotion(float2 uv, bool use_prev_z)
{
    float2 motion = float2(UI_MB_DebugLen) * BUFFER_PIXEL_SIZE;

    if (UI_MB_DebugZCen > 0.0)
    {
        float2 z_uv = uv;

        if(use_prev_z) z_uv = uv - motion;

        float z = GetDepth(z_uv);
        float z_cent = UI_MB_DebugZCen;
        float z_range = UI_MB_DebugZRange;
        float min_z = saturate(z_cent - z_range);
        float max_z = saturate(z_cent + z_range);

        if(z < min_z) motion = 0;
        if(z > max_z) motion = UI_MB_DebugRev ? -motion : 0;
    }

    return motion;
}
#endif

float2 GetMotion(float2 uv)
{
    // motion must be in pixel units
    float2 motion = SampleMotion(uv).xy * BUFFER_SCREEN_SIZE;

#if V_ENABLE_MOT_BLUR == 7
    motion = GetDebugMotion(uv, false) * BUFFER_SCREEN_SIZE;
#endif

    return motion;
}

float3 LimitMotionAndLen(float2 motion)
{
    // use half, because we sample in 2 dirs
    motion *= 0.5 * UI_MB_Mult;

    // limit the motion like in the paper
    float old_mot_len = length(motion);
    float new_mot_len = min(old_mot_len, float(K));

    motion *= new_mot_len * RCP(old_mot_len);

    float3 mot_and_len = old_mot_len < 0.5 ? 0.0 : float3(motion, new_mot_len);

    return mot_and_len;
}

float GetCosAngle(float2 v1, float2 v2)
{
    // var. 1: dot(v1, v2) * RSQRT(dot(v1, v1) * dot(v2, v2))
    // var. 2: dot(v1, v2) * RCP(length(v1) * length(v2)
    // var. 3: dot(NORM(v1), NORM(v2))

    return dot(v1, v2) * RSQRT(dot(v1, v1) * dot(v2, v2));
}

float4 Calc_Info(float2 pos)
{
    float2 uv = pos * BUFFER_PIXEL_SIZE;
    float3 closest = float3(uv, GetDepth(uv));

    static const float2 offs[8] = {
        float2(1,1), float2(-1,-1), float2(-1,1), float2(1,-1),
        float2(1,0), float2(0,1), float2(-1,0), float2(0,-1)
    };

    // apply min filter to remove some artifacts
    [loop]for(uint j = 0; j < 8; j++)
    {
        float2 sample_uv = uv + offs[j] * BUFFER_PIXEL_SIZE;
        float sample_z = GetDepth(sample_uv);

        if(sample_z < closest.z) closest = float3(sample_uv, sample_z);
    }

    float3 mot_and_len = LimitMotionAndLen(GetMotion(closest.xy));
    float2 mot_norm = mot_and_len.xy * RCP(mot_and_len.z);

    // x = motion px len, y = depth, zw = norm motion
    return float4(mot_and_len.z, closest.z, mot_norm);
}

float4 Calc_Blur(float2 pos)
{
    float2 uv = pos * BUFFER_PIXEL_SIZE;

// debug motion vectors
#if V_ENABLE_MOT_BLUR == 9
    if(1) { return float4(DebugMotion(SampleMotion(uv)), 1); }
#endif

    float rand = GetGradNoise(pos); // blue noise is distracting
    float2 sample_noise = (rand - 0.5) * float2(1, -1);
    float2 tiles_inv_size = K * BUFFER_PIXEL_SIZE;
    float2 tiles_uv_offs = (rand * 0.5 - 0.25) * tiles_inv_size;

    // don't randomize diagonally
    tiles_uv_offs *= sample_noise.x < 0.0 ? float2(1, 0) : float2(0, 1);

    float2 max_motion = Sample(sNeighMaxTexVort, uv + tiles_uv_offs).xy;
    float max_mot_len = length(max_motion);

    // center must not use min filter to prevent artifacts
    // around objects when only they are blurred
    float3 cen_mot_and_len = LimitMotionAndLen(GetMotion(uv));
    float2 cen_info = float2(cen_mot_and_len.z, GetDepth(uv));
    float2 cen_motion = cen_mot_and_len.xy;

    // due to tile randomization center motion might be greater
    if(max_mot_len < cen_info.x) { max_mot_len = cen_info.x; max_motion = cen_motion; }

// debug tiles
#if V_ENABLE_MOT_BLUR == 8
    if(1) { return float4(DebugMotion(max_motion * BUFFER_PIXEL_SIZE), 1); }
#endif

    // early out when less than 2px movement
    if(max_mot_len < 1.0) return 0;

    uint half_samples = clamp(round(max_mot_len * A_THIRD), 3, 9);

    // odd amount of samples so max motion gets 1 more sample than center motion
    if(half_samples % 2 == 0) half_samples += 1;

    float inv_half_samples = rcp(float(half_samples));
    float2 z_scales = Z_FAR_PLANE * float2(1, -1); // touch only if you change depthcmp

    float2 max_mot_norm = max_motion * RCP(max_mot_len);
    float2 cen_mot_norm = cen_motion * RCP(cen_info.x);

    // how parallel to center direction
    float wa_max = cen_info.x < 1.0 ? 0.0 : abs(dot(cen_mot_norm, max_mot_norm));
    float wa_cen = cen_info.x < 1.0 ? 0.0 : 1.0;

    // xy = norm motion (direction), z = wa
    float3 max_main = float3(max_mot_norm, wa_max);

    // don't lose half the samples when there is no center px motion
    // helps when an object is moving but the background isn't
    float3 cen_main = cen_info.x < 1.0 ? max_main : float3(cen_mot_norm, wa_cen);

    float steps_to_px = inv_half_samples * max_mot_len;
    float px_to_steps = rcp(steps_to_px);

    float4 bg_acc = 0;
    float4 fg_acc = 0;

    // TODO: try sampling 2 full motion directions and rejecting samples which are
    // in the wrong direction (object moving 1 dir, background another)

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // switch between max and center
        float3 m = j % 2 == 0 ? max_main : cen_main;

        // negated dither in the second direction
        // to remove the otherwise visible gap
        float2 step = float(j) + 0.5 + sample_noise;
        float2 norm_uv_mot = m.xy * BUFFER_PIXEL_SIZE;
        float4 uv_offs = (step.xxyy * steps_to_px) * norm_uv_mot.xyxy;

        float2 sample_uv1 = uv + uv_offs.xy;
        float2 sample_uv2 = uv - uv_offs.zw;

        // x = motion px len, y = depth, zw = norm motion
        float4 sample_info1 = Sample(sInfoTexVort, sample_uv1);
        float4 sample_info2 = Sample(sInfoTexVort, sample_uv2);

        float2 depthcmp1 = saturate(0.5 + z_scales * (sample_info1.y - cen_info.y));
        float2 depthcmp2 = saturate(0.5 + z_scales * (sample_info2.y - cen_info.y));

        // the `max` is to remove potential artifacts
        float2 spreadcmp1 = saturate(float2(cen_info.x, sample_info1.x) * px_to_steps - max(0.0, step.x - 1.0));
        float2 spreadcmp2 = saturate(float2(cen_info.x, sample_info2.x) * px_to_steps - max(0.0, step.y - 1.0));

        // x = bg_weight * wa, y = fg_weight * wb
        float2 sample_w1 = (depthcmp1 * spreadcmp1) * float2(m.z, abs(dot(sample_info1.zw, m.xy)));
        float2 sample_w2 = (depthcmp2 * spreadcmp2) * float2(m.z, abs(dot(sample_info2.zw, m.xy)));

        float3 sample_color1 = InColor(sample_uv1);
        float3 sample_color2 = InColor(sample_uv2);

        bg_acc += float4(sample_color1, 1.0) * sample_w1.x;
        fg_acc += float4(sample_color1, 1.0) * sample_w1.y;

        bg_acc += float4(sample_color2, 1.0) * sample_w2.x;
        fg_acc += float4(sample_color2, 1.0) * sample_w2.y;
    }

    float total_weight = float(half_samples) * 2.0;

    // add center color and weight to background
    bg_acc += float4(InColor(uv), 1.0) * (inv_half_samples * 0.01);
    total_weight += 1.0;

    float3 fill_col = bg_acc.rgb * RCP(bg_acc.w);
    float4 sum_acc = bg_acc + fg_acc;

    // normalize
    sum_acc /= total_weight;

    // fill the missing data with background + center color
    // instead of only center in order to prevent artifacts
    float3 c = sum_acc.rgb + saturate(1.0 - sum_acc.w) * fill_col;

    return float4(OutColor(c), 1.0);
}

float2 Calc_TileDownHor(float2 pos)
{
    float3 max_motion = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        float2 sample_uv = float2(floor(pos.x) * K + 0.5 + x, pos.y) * BUFFER_PIXEL_SIZE;
        float2 motion = GetMotion(sample_uv);
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);
    }

    return max_motion.xy;
}

float2 Calc_TileDownVert(float2 pos)
{
    float3 max_motion = 0;

    [loop]for(uint y = 0; y < K; y++)
    {
        float2 sample_pos = float2(pos.x, floor(pos.y) * K + 0.5 + y);
        float2 motion = Fetch(sTileFstTexVort, sample_pos).xy;
        float sq_len = dot(motion, motion);

        if(sq_len > max_motion.z) max_motion = float3(motion, sq_len);
    }

    return max_motion.xy;
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

        if(sq_len > max_motion.z)
        {
            float rel_angle = ACOS(GetCosAngle(float2(-x, -y), motion));
            bool is_diag = (x * y) != 0;
            bool should_contrib = true;

            // 45 and 135 deg
            if(is_diag) should_contrib = rel_angle < 0.7854 || rel_angle > 2.3561;

            if(should_contrib) max_motion = float3(motion, sq_len);
        }
    }

    return LimitMotionAndLen(max_motion.xy).xy;
}

void Draw(float4 c, out float3 o) { if(c.a < 1.0) discard; o = c.rgb; }

/*******************************************************************************
    Shaders
*******************************************************************************/

#if MB_USE_COMPUTE
    void CS_WriteInfo(CS_ARGS)    { tex2Dstore(stInfoTexVort,     i.id.xy, Calc_Info(i.id.xy + 0.5));   }
    void CS_TileDownHor(CS_ARGS)  { tex2Dstore(stTileFstTexVort,  i.id.xy, Calc_TileDownHor(i.id.xy + 0.5).xyxy);  }
    void CS_TileDownVert(CS_ARGS) { tex2Dstore(stTileSndTexVort,  i.id.xy, Calc_TileDownVert(i.id.xy + 0.5).xyxy); }
    void CS_NeighbourMax(CS_ARGS) { tex2Dstore(stNeighMaxTexVort, i.id.xy, Calc_NeighbourMax(i.id.xy + 0.5).xyxy); }
    void CS_Blur(CS_ARGS)         { tex2Dstore(stBlurTexVort,     i.id.xy, Calc_Blur(i.id.xy + 0.5));              }
    void PS_Draw(PS_ARGS3)        { Draw(Sample(sBlurTexVort, i.uv), o); }
#else
    void PS_WriteInfo(PS_ARGS4)    { o = Calc_Info(i.vpos.xy); }
    void PS_TileDownHor(PS_ARGS2)  { o = Calc_TileDownHor(i.vpos.xy);  }
    void PS_TileDownVert(PS_ARGS2) { o = Calc_TileDownVert(i.vpos.xy); }
    void PS_NeighbourMax(PS_ARGS2) { o = Calc_NeighbourMax(i.vpos.xy); }
    void PS_BlurAndDraw(PS_ARGS3)  { Draw(Calc_Blur(i.vpos.xy), o); }
#endif

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
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_Draw; }
#else
    #define PASS_MOT_BLUR \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_WriteInfo;    RenderTarget = MotBlur::InfoTexVort;     } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownHor;  RenderTarget = MotBlur::TileFstTexVort;  } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_TileDownVert; RenderTarget = MotBlur::TileSndTexVort;  } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_NeighbourMax; RenderTarget = MotBlur::NeighMaxTexVort; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotBlur::PS_BlurAndDraw; SRGB_WRITE_ENABLE }
#endif

} // namespace end
