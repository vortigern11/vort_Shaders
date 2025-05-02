/*******************************************************************************
    Original authors: Jakob Wapenhensch (Jak0bW) and Pascal Gilcher / Marty McFly
    Modifications by: Vortigern

    License:
    Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)
    https://creativecommons.org/licenses/by-nc/4.0/

    Links to projects this was based on:
    https://github.com/JakobPCoder/ReshadeMotionEstimation
    https://gist.github.com/martymcmodding/69c775f844124ec2c71c37541801c053
*******************************************************************************/

#pragma once
#include "Includes/vort_Defs.fxh"
#include "Includes/vort_Depth.fxh"
#include "Includes/vort_ColorTex.fxh"
#include "Includes/vort_BlueNoise.fxh"
#include "Includes/vort_Tonemap.fxh"
#include "Includes/vort_Filters.fxh"
#include "Includes/vort_Motion_UI.fxh"
#include "Includes/vort_MotionUtils.fxh"

namespace MV {

/*******************************************************************************
    Globals
*******************************************************************************/

// don't increase further
#if BUFFER_HEIGHT < 2160
    #define MAX_MIP 7
#else
    #define MAX_MIP 8
#endif

#define MIN_MIP 1

static const uint DIAMOND_S = 9;
static const float2 DIAMOND_OFFS[DIAMOND_S] =
{
    float2(0, 0),
    float2(-1, -1), float2(1, 1), float2(-1, 1), float2(1, -1),
    float2(0, -2), float2(0, 2), float2(-2, 0), float2(2, 0)
};

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D CurrFeatTex1 { TEX_SIZE(1) TEX_RG16 };
texture2D CurrFeatTex2 { TEX_SIZE(2) TEX_RG16 };
texture2D CurrFeatTex3 { TEX_SIZE(3) TEX_RG16 };
texture2D CurrFeatTex4 { TEX_SIZE(4) TEX_RG16 };
texture2D CurrFeatTex5 { TEX_SIZE(5) TEX_RG16 };
texture2D CurrFeatTex6 { TEX_SIZE(6) TEX_RG16 };
texture2D CurrFeatTex7 { TEX_SIZE(7) TEX_RG16 };

texture2D PrevFeatTex1 { TEX_SIZE(1) TEX_RG16 };
texture2D PrevFeatTex2 { TEX_SIZE(2) TEX_RG16 };
texture2D PrevFeatTex3 { TEX_SIZE(3) TEX_RG16 };
texture2D PrevFeatTex4 { TEX_SIZE(4) TEX_RG16 };
texture2D PrevFeatTex5 { TEX_SIZE(5) TEX_RG16 };
texture2D PrevFeatTex6 { TEX_SIZE(6) TEX_RG16 };
texture2D PrevFeatTex7 { TEX_SIZE(7) TEX_RG16 };

sampler2D sCurrFeatTex1 { Texture = CurrFeatTex1; SAM_MIRROR };
sampler2D sCurrFeatTex2 { Texture = CurrFeatTex2; SAM_MIRROR };
sampler2D sCurrFeatTex3 { Texture = CurrFeatTex3; SAM_MIRROR };
sampler2D sCurrFeatTex4 { Texture = CurrFeatTex4; SAM_MIRROR };
sampler2D sCurrFeatTex5 { Texture = CurrFeatTex5; SAM_MIRROR };
sampler2D sCurrFeatTex6 { Texture = CurrFeatTex6; SAM_MIRROR };
sampler2D sCurrFeatTex7 { Texture = CurrFeatTex7; SAM_MIRROR };

sampler2D sPrevFeatTex1 { Texture = PrevFeatTex1; SAM_MIRROR };
sampler2D sPrevFeatTex2 { Texture = PrevFeatTex2; SAM_MIRROR };
sampler2D sPrevFeatTex3 { Texture = PrevFeatTex3; SAM_MIRROR };
sampler2D sPrevFeatTex4 { Texture = PrevFeatTex4; SAM_MIRROR };
sampler2D sPrevFeatTex5 { Texture = PrevFeatTex5; SAM_MIRROR };
sampler2D sPrevFeatTex6 { Texture = PrevFeatTex6; SAM_MIRROR };
sampler2D sPrevFeatTex7 { Texture = PrevFeatTex7; SAM_MIRROR };

texture2D MotionTex1 { TEX_SIZE(1) TEX_RGBA16 };
texture2D MotionTex2 { TEX_SIZE(2) TEX_RGBA16 };
texture2D MotionTexA { TEX_SIZE(3) TEX_RGBA16 };
texture2D MotionTexB { TEX_SIZE(3) TEX_RGBA16 };

sampler2D sMotionTex1 { Texture = MotionTex1; SAM_POINT };
sampler2D sMotionTex2 { Texture = MotionTex2; SAM_POINT };
sampler2D sMotionTexA { Texture = MotionTexA; SAM_POINT };
sampler2D sMotionTexB { Texture = MotionTexB; SAM_POINT };

/*******************************************************************************
    Functions
*******************************************************************************/

float4 FilterMotion(VSOUT i, int mip, sampler mot_samp, sampler feat_samp)
{
    float4 cen_motion = Sample(mot_samp, i.uv);
    /* return cen_motion; */

    // tested in many different scenarios in many different games
    // Sponza, RoR2, Deep Rock, other third person games

    // in the end correct filtering improves the result much more than
    // small improvements to the raw calculation (so far)

    float2 scale = rcp(tex2Dsize(mot_samp)) * (mip > 1 ? 4.0 : 2.0);
    float rand = GetR1(GetBlueNoise(i.vpos.xy).x, mip + 1);
    float4 rot = GetRotator(rand * HALF_PI);
    float cen_depth = Sample(feat_samp, i.uv).y;
    float cen_mot_sq_len = dot(cen_motion.xy, cen_motion.xy);

    if(mip == 0) cen_depth = GetDepth(i.uv);

    float4 motion_acc = 0;
    int r = min(mip + 1, 2);

    [loop]for(int x = -r; x <= r; x++)
    [loop]for(int y = -r; y <= r; y++)
    {
        float2 tap_uv = i.uv + Rotate(float2(x, y), rot) * scale;
        float4 tap_mot = Sample(mot_samp, tap_uv);
        float tap_mot_sq_len = dot(tap_mot.xy, tap_mot.xy);
        float cos_angle = dot(cen_motion.xy, tap_mot.xy) * rsqrt(max(1e-15, cen_mot_sq_len * tap_mot_sq_len));

        float wz = abs(cen_depth - tap_mot.w) * rcp(max(1e-15, min(cen_depth, tap_mot.w))) * 20.0;
        float wd = saturate(cos_angle) * 2.0; // samples with diff dir than center are better
        float ws = tap_mot.z * 40.0; // sharpens small motion and more uniform big motion
        float weight = max(1e-8, exp2(-(wz + wd + ws))) * ValidateUV(tap_uv); // don't change the min value

        motion_acc += float4(tap_mot.xyz, 1.0) * weight;
    }

    motion_acc.xyz /= motion_acc.w;

    return float4(motion_acc.xyz, cen_depth);
}

float4 CalcMotion(VSOUT i, int mip, sampler mot_samp, sampler curr_feat_samp, sampler prev_feat_samp)
{
    // don't change those values, artifacts arise otherwise
    // must prevent searching for pixel if center is already similar enough
    static const float eps = 1e-6;
    static const float max_sim = 1.0 - eps;

    float2 texel_size = rcp(tex2Dsize(curr_feat_samp));
    float2 local_samples[DIAMOND_S];
    float2 moments_local = eps;
    float2 moments_search = eps;
    float2 moments_cov = eps;
    float2 total_motion = 0;

    if(mip < MAX_MIP) total_motion = FilterMotion(i, mip, mot_samp, curr_feat_samp).xy;

    // negligible performance boost to do the below loop here,
    // but maybe there's more at 4k resolution?
    // alternatively can be put inside the main loop below to shorten the code

#if IS_DX9
    [unroll] // needed for dx9
#else
    [loop] // faster compile speed
#endif
    for(uint j = 0; j < DIAMOND_S; j++)
    {
        float2 tap_uv = i.uv + DIAMOND_OFFS[j] * texel_size;
        float2 tap_l = Sample(curr_feat_samp, tap_uv).xy;
        float2 tap_s = Sample(prev_feat_samp, tap_uv + total_motion).xy;

        local_samples[j] = tap_l;
        moments_local += tap_l * tap_l;
        moments_search += tap_s * tap_s;
        moments_cov += tap_s * tap_l;
    }

    float2 cossim = moments_cov * rsqrt(moments_local * moments_search);
    float best_sim = saturate(min(cossim.x, cossim.y));
    float rand = GetR1(GetBlueNoise(i.vpos.xy).x, mip + 1);
    float2 randdir; sincos(rand * HALF_PI, randdir.x, randdir.y);
    int searches = mip > 3 ? 4 : 2;

    [loop]while(searches-- > 0 && best_sim < max_sim)
    {
        float2 local_motion = 0;
        float2 search_offs = 0;
        int samples = 4; // 360deg / 90deg = 4

        [loop]while(samples-- > 0 && best_sim < max_sim)
        {
            randdir = float2(randdir.y, -randdir.x); //rotate by 90 degrees
            search_offs = randdir * texel_size;
            moments_search = eps;
            moments_cov = eps;

            [loop]for(uint j = 0; j < DIAMOND_S; j++)
            {
                float2 tap_uv = i.uv + DIAMOND_OFFS[j] * texel_size + total_motion + search_offs;
                float2 tap_s = Sample(prev_feat_samp, tap_uv).xy;
                float2 tap_l = local_samples[j];

                moments_search += tap_s * tap_s;
                moments_cov += tap_s * tap_l;
            }

            cossim = moments_cov * rsqrt(moments_local * moments_search);
            float sim = saturate(min(cossim.x, cossim.y));

            if(sim > best_sim)
            {
                best_sim = sim;
                local_motion = search_offs;
            }
        }

        total_motion += local_motion;
        randdir *= 0.25;
    }

    float depth = Sample(curr_feat_samp, i.uv).y;

    return float4(total_motion, ACOS(best_sim) / HALF_PI, depth);
}

float2 DownsampleFeature(float2 uv, sampler feat_samp)
{
    float2 texel_size = rcp(tex2Dsize(feat_samp));
    float3 acc = 0;

    [loop]for(int x = 0; x <= 3; x++)
    [loop]for(int y = 0; y <= 3; y++)
    {
        float2 offs = float2(x, y) - 1.5;
        float2 tap = Sample(feat_samp, uv + offs * texel_size).xy;
        float weight = exp(-0.1 * dot(offs, offs));

        acc += float3(tap, 1.0) * weight;
    }

    return acc.xy / acc.z;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_WriteFeature(PS_ARGS2)
{
#if MIN_MIP > 0
    float3 c = Filters::Wronski(Color::sColorTex, i.uv, 0).rgb;
#else
    float3 c = SampleGammaColor(i.uv);
#endif

#if !IS_SRGB
    c = ApplyLinCurve(c);
    c = Tonemap::ApplyReinhardMax(c, 1.0);
#endif

    o = float2(dot(c, A_THIRD), GetDepth(i.uv));
}

void PS_DownFeat2(PS_ARGS2) { o = DownsampleFeature(i.uv, sCurrFeatTex1); }
void PS_DownFeat3(PS_ARGS2) { o = DownsampleFeature(i.uv, sCurrFeatTex2); }
void PS_DownFeat4(PS_ARGS2) { o = DownsampleFeature(i.uv, sCurrFeatTex3); }
void PS_DownFeat5(PS_ARGS2) { o = DownsampleFeature(i.uv, sCurrFeatTex4); }
void PS_DownFeat6(PS_ARGS2) { o = DownsampleFeature(i.uv, sCurrFeatTex5); }
void PS_DownFeat7(PS_ARGS2) { o = DownsampleFeature(i.uv, sCurrFeatTex6); }

void PS_CopyFeat1(PS_ARGS2) { o = Sample(sCurrFeatTex1, i.uv).xy; }
void PS_CopyFeat2(PS_ARGS2) { o = Sample(sCurrFeatTex2, i.uv).xy; }
void PS_CopyFeat3(PS_ARGS2) { o = Sample(sCurrFeatTex3, i.uv).xy; }
void PS_CopyFeat4(PS_ARGS2) { o = Sample(sCurrFeatTex4, i.uv).xy; }
void PS_CopyFeat5(PS_ARGS2) { o = Sample(sCurrFeatTex5, i.uv).xy; }
void PS_CopyFeat6(PS_ARGS2) { o = Sample(sCurrFeatTex6, i.uv).xy; }
void PS_CopyFeat7(PS_ARGS2) { o = Sample(sCurrFeatTex7, i.uv).xy; }

// feature samplers are 1 mip higher for better quality
void PS_Motion8(PS_ARGS4) { o = CalcMotion(i, 8, sMotionTexB, sCurrFeatTex7, sPrevFeatTex7); }
void PS_Motion7(PS_ARGS4) { o = CalcMotion(i, 7, sMotionTexB, sCurrFeatTex6, sPrevFeatTex6); }
void PS_Motion6(PS_ARGS4) { o = CalcMotion(i, 6, sMotionTexB, sCurrFeatTex5, sPrevFeatTex5); }
void PS_Motion5(PS_ARGS4) { o = CalcMotion(i, 5, sMotionTexB, sCurrFeatTex4, sPrevFeatTex4); }
void PS_Motion4(PS_ARGS4) { o = CalcMotion(i, 4, sMotionTexB, sCurrFeatTex3, sPrevFeatTex3); }
void PS_Motion3(PS_ARGS4) { o = CalcMotion(i, 3, sMotionTexB, sCurrFeatTex2, sPrevFeatTex2); }
void PS_Motion2(PS_ARGS4) { o = CalcMotion(i, 2, sMotionTexB, sCurrFeatTex1, sPrevFeatTex1); }
void PS_Motion1(PS_ARGS4) { o = CalcMotion(i, 1, sMotionTex2, sCurrFeatTex1, sPrevFeatTex1); }

// slight quality increase for nearly no perf cost
void PS_Filter7(PS_ARGS4) { o = FilterMotion(i, 7, sMotionTexA, sCurrFeatTex6); }
void PS_Filter6(PS_ARGS4) { o = FilterMotion(i, 6, sMotionTexA, sCurrFeatTex5); }
void PS_Filter5(PS_ARGS4) { o = FilterMotion(i, 5, sMotionTexA, sCurrFeatTex4); }
void PS_Filter4(PS_ARGS4) { o = FilterMotion(i, 4, sMotionTexA, sCurrFeatTex3); }
void PS_Filter3(PS_ARGS4) { o = FilterMotion(i, 3, sMotionTexA, sCurrFeatTex2); }
void PS_Filter2(PS_ARGS4) { o = FilterMotion(i, 2, sMotionTexA, sCurrFeatTex1); }
void PS_Filter0(PS_ARGS4) { o = FilterMotion(i, 0, sMotionTex1, sCurrFeatTex1); }

/*******************************************************************************
    Passes
*******************************************************************************/

#if BUFFER_HEIGHT < 2160
    #define PASS_MV_EXTRA
#else
    #define PASS_MV_EXTRA \
        pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion8; RenderTarget = MV::MotionTexA; } \
        pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter7; RenderTarget = MV::MotionTexB; }
#endif

#define PASS_MV \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_WriteFeature; RenderTarget = MV::CurrFeatTex1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat2;    RenderTarget = MV::CurrFeatTex2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat3;    RenderTarget = MV::CurrFeatTex3; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat4;    RenderTarget = MV::CurrFeatTex4; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat5;    RenderTarget = MV::CurrFeatTex5; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat6;    RenderTarget = MV::CurrFeatTex6; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat7;    RenderTarget = MV::CurrFeatTex7; } \
    PASS_MV_EXTRA \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion7;      RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter6;      RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion6;      RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter5;      RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion5;      RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter4;      RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion4;      RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter3;      RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion3;      RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter2;      RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion2;      RenderTarget = MV::MotionTex2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion1;      RenderTarget = MV::MotionTex1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter0;      RenderTarget = MotVectTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat1;    RenderTarget = MV::PrevFeatTex1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat2;    RenderTarget = MV::PrevFeatTex2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat3;    RenderTarget = MV::PrevFeatTex3; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat4;    RenderTarget = MV::PrevFeatTex4; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat5;    RenderTarget = MV::PrevFeatTex5; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat6;    RenderTarget = MV::PrevFeatTex6; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat7;    RenderTarget = MV::PrevFeatTex7; }

} // namespace end
