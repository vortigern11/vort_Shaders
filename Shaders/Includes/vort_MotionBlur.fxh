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
#include "Includes/vort_Tonemap.fxh"
#include "Includes/vort_Motion_UI.fxh"

namespace MotBlur {

/*******************************************************************************
    Globals
*******************************************************************************/

// older graphics cards get worse performance
#define MB_USE_COMPUTE CAN_COMPUTE && V_MOT_BLUR_USE_COMPUTE

// scale the tile number (30px at 1080p)
#define K (BUFFER_HEIGHT / 36)
#define TILE_WIDTH  (BUFFER_WIDTH / K)
#define TILE_HEIGHT (BUFFER_HEIGHT / K)

#define GS 16 // compute shaders group size

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

float3 GetColor(float2 uv)
{
    float3 c = SampleLinColor(uv);

#if IS_SRGB
    c = InverseReinhardMax(c);
#endif

    return c;
}

float3 PutColor(float3 c)
{
#if IS_SRGB
    c = ApplyReinhardMax(c);
#endif

#if MB_USE_COMPUTE
    return ForceGammaCurve(c);
#else
    return ApplyGammaCurve(c);
#endif
}

// motion must be in pixel units
float3 GetDilatedMotionAndLen(float2 uv)
{
    float2 motion = (SampleMotion(uv).xy * 0.5) * (UI_MB_Length * BUFFER_SCREEN_SIZE);

    // for debugging
    if(UI_MB_Debug) motion = float2(UI_MB_DebugLen);

    // limit the motion like in the paper
    float old_mot_len = max(0.5, length(motion));
    float new_mot_len = min(old_mot_len, float(K));
    motion *= new_mot_len * RCP(old_mot_len);

    return float3(motion, new_mot_len);
}

float2 GetTilesUVOffs(float2 pos)
{
    // randomize max neighbour lookup near borders to reduce tile visibility
    float2 tiles_inv_size = K * BUFFER_PIXEL_SIZE;
    float2 tiles_border_dist = abs(frac(pos * tiles_inv_size) - 0.5) * 2.0;
    float rand = GetWhiteNoise(pos).x - 0.5;

    // don't randomize diagonally
    tiles_border_dist *= rand < 0.0 ? float2(1.0, 0.0) : float2(0.0, 1.0);

    // uv offset
    return (tiles_border_dist * rand) * tiles_inv_size;
}

float4 Calc_Blur(float2 pos)
{
    float2 uv = pos * BUFFER_PIXEL_SIZE;

// debug motion vectors
#if V_ENABLE_MOT_BLUR == 9
    if(1) { return float4(DebugMotion(uv), 1); }
#endif

    float2 sample_dither = Dither(pos, 0.25) * float2(1, -1); // -0.25 or 0.25
    float2 tiles_uv_offs = GetTilesUVOffs(pos);

    float2 max_motion = Sample(sNeighMaxTexVort, uv + tiles_uv_offs).xy;
    float max_mot_len = length(max_motion);

    if(max_mot_len < 1.0) return 0;

    static const int half_samples = 7;
    static const float inv_half_samples = rcp(float(half_samples));
    static const float depth_scale = 1000.0;

    // xy = normalized motion, z = depth, w = motion px length
    float4 cen_info = Sample(sInfoTexVort, uv);
    float2 cen_motion = cen_info.xy * cen_info.w;

    float2 max_mot_norm = max_motion * RCP(max_mot_len);
    float2 cen_mot_norm = cen_info.xy;

    // perpendicular to max_motion
    float2 wp = max_mot_norm.yx * float2(-1, 1);

    // redirect if necessary
    if(dot(wp, cen_info.xy) < 0.0) wp = -wp;

    // alternative sampling direction
    float2 wc = NORM(lerp(wp, cen_mot_norm, saturate((cen_info.w - 0.5) / 1.5)));

    // precalculated weight modifiers
    float wa_max = abs(dot(wc, max_mot_norm));
    float wa_cen = abs(dot(wc, cen_mot_norm));

    // xy = motion per sample in uv units, zw = normalized motion
    float4 max_main = float4(inv_half_samples * (max_motion * BUFFER_PIXEL_SIZE), max_mot_norm);
    float4 cen_main = float4(inv_half_samples * (cen_motion * BUFFER_PIXEL_SIZE), cen_mot_norm);

    // x = step to pixels scale, y = wa
    float2 max_others = float2(inv_half_samples * max_mot_len, wa_max);
    float2 cen_others = float2(inv_half_samples * cen_info.w, wa_cen);

    float4 bg_acc = 0.0;
    float4 fg_acc = 0.0;

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // switch between max and center
        float4 m_main = max_main; float2 m_others = max_others;
        [flatten]if(j % 2 == 1) { m_main = cen_main; m_others = cen_others; }

        // negated dither in the second direction
        // to remove the otherwise visible gap
        float2 step = float(j) + 0.5 + sample_dither;
        float4 uv_offs = step.xxyy * m_main.xyxy;

        float2 sample_uv1 = saturate(uv + uv_offs.xy);
        float2 sample_uv2 = saturate(uv - uv_offs.zw);

        // xy = normalized motion, z = depth, w = motion px length
        float4 sample_info1 = Sample(sInfoTexVort, sample_uv1);
        float4 sample_info2 = Sample(sInfoTexVort, sample_uv2);

        float2 depthcmp1 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info1.z - cen_info.z));
        float2 depthcmp2 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info2.z - cen_info.z));

        // the `max` is to remove potential artifacts
        float2 spreadcmp1 = saturate(float2(cen_info.w, sample_info1.w) - max(0.0, step.x - 1.0) * m_others.x);
        float2 spreadcmp2 = saturate(float2(cen_info.w, sample_info2.w) - max(0.0, step.y - 1.0) * m_others.x);

        float2 w_ab1 = float2(m_others.y, abs(dot(sample_info1.xy, m_main.zw)));
        float2 w_ab2 = float2(m_others.y, abs(dot(sample_info2.xy, m_main.zw)));

        // .x = bg weight, .y = fg weight
        float2 sample_w1 = (depthcmp1 * spreadcmp1) * w_ab1;
        float2 sample_w2 = (depthcmp2 * spreadcmp2) * w_ab2;

        float3 sample_color1 = GetColor(sample_uv1);
        float3 sample_color2 = GetColor(sample_uv2);

        // bg/fg for first sample
        bg_acc += float4(sample_color1 * sample_w1.x, sample_w1.x);
        fg_acc += float4(sample_color1 * sample_w1.y, sample_w1.y);

        // bg/fg for second sample
        bg_acc += float4(sample_color2 * sample_w2.x, sample_w2.x);
        fg_acc += float4(sample_color2 * sample_w2.y, sample_w2.y);
    }

    float total_samples = float(half_samples) * 2.0;

    // preserve thin features like in the paper
    float cen_weight = saturate(total_samples * RCP(cen_info.w * 40.0));

    // add center color to background
    bg_acc += float4(GetColor(uv) * cen_weight, cen_weight);
    total_samples += 1.0;

    float3 bg_col = bg_acc.rgb * RCP(bg_acc.w);
    float4 sum_acc = bg_acc + fg_acc;

    // normalize
    sum_acc /= total_samples;

    // fill the missing data with background color
    // instead of center in order to counteract artifacts in some cases
    float3 c = sum_acc.rgb + saturate(1.0 - sum_acc.w) * bg_col;

    return float4(PutColor(c), 1.0);
}

float4 Calc_WriteInfo(float2 pos)
{
    float2 uv = pos * BUFFER_PIXEL_SIZE;

    // xy = closest uv, z = closest depth
    float3 closest = float3(uv, GetLinearizedDepth(uv));

    // instead of using a 3x3 kernel, take just the corners and center
    static const float2 offs[4] = { float2(-1,-1), float2(-1,1), float2(1,1), float2(1,-1) };

    // apply min filter to remove some artifacts
    [loop]for(int j = 0; j < 4; j++)
    {
        float2 sample_uv = saturate(uv + offs[j] * BUFFER_PIXEL_SIZE);
        float sample_z = GetLinearizedDepth(sample_uv);

        if(sample_z < closest.z) closest = float3(sample_uv, sample_z);
    }

    float3 mot_info = GetDilatedMotionAndLen(closest.xy);
    float2 mot_norm = mot_info.xy * RCP(mot_info.z);

    // xy = norm motion, z = closest depth, w = motion px len
    return float4(mot_norm, closest.z, mot_info.z);
}

float2 Calc_TileDownHor(float2 pos)
{
    float3 max_motion = 0;

    [loop]for(uint x = 0; x < K; x++)
    {
        float2 sample_pos = float2(floor(pos.x) * K + 0.5 + x, pos.y);

        // xy = motion in pixels, z = motion px length
        float3 mot_info = GetDilatedMotionAndLen(sample_pos * BUFFER_PIXEL_SIZE);

        if(mot_info.z > max_motion.z) max_motion = mot_info;
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
        float sq_len = dot(motion.xy, motion.xy);

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

    return max_motion.xy;
}

void Draw(float4 c, out float3 o) { if(c.a < 1.0) discard; o = c.rgb; }

/*******************************************************************************
    Shaders
*******************************************************************************/

#if MB_USE_COMPUTE
    void CS_WriteInfo(CS_ARGS)    { tex2Dstore(stInfoTexVort,     i.id.xy, Calc_WriteInfo(i.id.xy + 0.5));         }
    void CS_TileDownHor(CS_ARGS)  { tex2Dstore(stTileFstTexVort,  i.id.xy, Calc_TileDownHor(i.id.xy + 0.5).xyxy);  }
    void CS_TileDownVert(CS_ARGS) { tex2Dstore(stTileSndTexVort,  i.id.xy, Calc_TileDownVert(i.id.xy + 0.5).xyxy); }
    void CS_NeighbourMax(CS_ARGS) { tex2Dstore(stNeighMaxTexVort, i.id.xy, Calc_NeighbourMax(i.id.xy + 0.5).xyxy); }
    void CS_Blur(CS_ARGS)         { tex2Dstore(stBlurTexVort,     i.id.xy, Calc_Blur(i.id.xy + 0.5));              }
    void PS_Draw(PS_ARGS3)        { Draw(Sample(sBlurTexVort, i.uv), o); }
#else
    void PS_WriteInfo(PS_ARGS4)    { o = Calc_WriteInfo(i.vpos.xy);    }
    void PS_TileDownHor(PS_ARGS2)  { o = Calc_TileDownHor(i.vpos.xy);  }
    void PS_TileDownVert(PS_ARGS2) { o = Calc_TileDownVert(i.vpos.xy); }
    void PS_NeighbourMax(PS_ARGS2) { o = Calc_NeighbourMax(i.vpos.xy); }
    void PS_BlurAndDraw(PS_ARGS3)  { Draw(Calc_Blur(i.vpos.xy), o);    }
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
