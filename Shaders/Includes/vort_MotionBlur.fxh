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

#define MB_MOTION_MOD (UI_MB_Amount * 0.5 * BUFFER_SCREEN_SIZE)

// Whether to use the new motion blur implementation by Jimenez
#define MB_USE_NEW_METHOD 1

// scale the tile number (30px at 1080p)
#define K (BUFFER_HEIGHT / 36)

// Converting the samples to HDR and back yields worse results.
// Bright colors overshadow others and the result seems fake.

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D InfoTexVort { TEX_SIZE(0) TEX_RGBA16 };
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
    float mot_len = length(motion);

    // limit the motion like in the paper
    float new_mot_len = clamp(mot_len, 0.5, float(K));
    motion *= new_mot_len * RCP(mot_len);

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

// debug the max neighour tiles
#if V_ENABLE_MOT_BLUR == 2
    if(1) // bypass unreachable code bug
    {
        float2 motion = max_motion * BUFFER_PIXEL_SIZE;
        float angle = atan2(motion.y, motion.x);
        float3 rgb = saturate(3 * abs(2 * frac(angle / DOUBLE_PI + float3(0, -1.0/3.0, 1.0/3.0)) - 1) - 1);
        o = lerp(0.5, rgb, saturate(length(motion) * 100));
        return;
    }
#endif

    // 1 for each side besides the center
    if(max_mot_len < 2.0) discard;

    // xy = normalized motion, z = depth, w = motion px length
    float4 cen_info = Sample(sInfoTexVort, i.uv);
    float2 cen_motion = cen_info.xy * cen_info.w;

    // perpendicular to max_motion
    float2 max_mot_norm = max_motion / max_mot_len;
    float2 wp = max_mot_norm.yx * float2(-1, 1);

    // redirect to point in the same direction as cen_motion
    if(dot(wp, cen_motion) < 0.0) wp = -wp;

    // alternative sampling direction
    float2 wc = NORM(lerp(wp, cen_info.xy, saturate((cen_info.w - 0.5) / 1.5)));

    float wa_max = abs(dot(wc, max_motion));
    float wa_cen = abs(dot(wc, cen_motion));

    static const int half_samples = 8;
    static const float inv_half_samples = rcp(float(half_samples));
    static const float depth_scale = 1000.0;

    float sample_units_scale = float(half_samples) * RCP(max_mot_len);
    float4 color = 0.0;

    [loop]for(uint j = 0; j < half_samples; j++)
    {
        // use max motion on even steps, use center motion on odd steps
        float2 m = max_motion; float wa = wa_max;
        [flatten]if(j % 2 == 1) { m = cen_motion; wa = wa_cen; }

        float step = float(j) + 0.5 + sample_dither;
        float2 offs = m * (step * inv_half_samples) * BUFFER_PIXEL_SIZE;

        float2 sample_uv1 = saturate(i.uv + offs);
        float2 sample_uv2 = saturate(i.uv - offs);

        float4 sample_info1 = Sample(sInfoTexVort, sample_uv1);
        float4 sample_info2 = Sample(sInfoTexVort, sample_uv2);

        float2 depthcmp1 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info1.z - cen_info.z));
        float2 depthcmp2 = saturate(0.5 + float2(depth_scale, -depth_scale) * (sample_info2.z - cen_info.z));

        float2 w_ab1 = float2(wa, abs(dot(sample_info1.xy, m)));
        float2 w_ab2 = float2(wa, abs(dot(sample_info2.xy, m)));

    #if MB_USE_NEW_METHOD
        step = max(0.0, step - 1.0);
        float2 spreadcmp1 = saturate(sample_units_scale * float2(cen_info.w, sample_info1.w) - step) * w_ab1;
        float2 spreadcmp2 = saturate(sample_units_scale * float2(cen_info.w, sample_info2.w) - step) * w_ab2;
    #else
        float offs_len = max(1.0, step / sample_units_scale);
        float2 spreadcmp1 = saturate(1.0 - offs_len * RCP(float2(cen_info.w, sample_info1.w))) * w_ab1;
        float2 spreadcmp2 = saturate(1.0 - offs_len * RCP(float2(cen_info.w, sample_info2.w))) * w_ab2;
    #endif

        float weight1 = dot(depthcmp1, spreadcmp1);
        float weight2 = dot(depthcmp2, spreadcmp2);

    #if MB_USE_NEW_METHOD
        // mirror filter to better guess the background
        bool2 mirror = bool2(sample_info1.z > sample_info2.z, sample_info2.w > sample_info1.w);
        weight1 = all(mirror) ? weight2 : weight1;
        weight2 = any(mirror) ? weight2 : weight1;
    #endif

        color += float4(SampleLinColor(sample_uv1) * weight1, weight1);
        color += float4(SampleLinColor(sample_uv2) * weight2, weight2);
    }

#if MB_USE_NEW_METHOD
    color *= RCP(color.w); // instead of dividing by total samples, in order to remove artifacts
    color.rgb += (1.0 - color.w) * SampleLinColor(i.uv); // for when color.w is 0
#else
    float cen_weight = (float(half_samples) * 2.0) * RCP(cen_info.w * K);
    color += float4(SampleLinColor(i.uv), 1.0) * cen_weight;
    color.rgb *= RCP(color.w);
#endif

    o = ApplyGammaCurve(color.rgb);
}

void PS_WriteInfo(PS_ARGS4)
{
    // xy = motion in pixels, z = motion px len
    float3 mot_info = GetDilatedMotionAndLen(i.vpos.xy);
    float motion_len = mot_info.z;
    float2 motion_norm = mot_info.xy / motion_len;

    o.xy = motion_norm;
    o.z = GetLinearizedDepth(i.uv);
    o.w = motion_len;
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

        // if offset and motion are in opposite directions
        // then the motion is directed at center
        bool is_mot_in_center_dir = dot(float2(x, y), motion) < 0.0;
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
