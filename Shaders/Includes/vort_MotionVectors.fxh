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
#include "Includes/vort_Motion_UI.fxh"
#include "Includes/vort_MotionUtils.fxh"

namespace MV {

/*******************************************************************************
    Globals
*******************************************************************************/

// tested in many different scenarios in many different games
// Sponza, RoR2, Deep Rock and other third person games

// motion calculation must be with both color and depth, because
// fg vs bg color are sometimes too similar and cause issues (RoR2)

#if BUFFER_HEIGHT < 2160
    #define MAX_MIP 8
#else
    #define MAX_MIP 9
#endif

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
texture2D CurrFeatTex8 { TEX_SIZE(8) TEX_RG16 };

texture2D PrevFeatTex1 { TEX_SIZE(1) TEX_RG16 };
texture2D PrevFeatTex2 { TEX_SIZE(2) TEX_RG16 };
texture2D PrevFeatTex3 { TEX_SIZE(3) TEX_RG16 };
texture2D PrevFeatTex4 { TEX_SIZE(4) TEX_RG16 };
texture2D PrevFeatTex5 { TEX_SIZE(5) TEX_RG16 };
texture2D PrevFeatTex6 { TEX_SIZE(6) TEX_RG16 };
texture2D PrevFeatTex7 { TEX_SIZE(7) TEX_RG16 };
texture2D PrevFeatTex8 { TEX_SIZE(8) TEX_RG16 };

sampler2D sCurrFeatTex1 { Texture = CurrFeatTex1; };
sampler2D sCurrFeatTex2 { Texture = CurrFeatTex2; };
sampler2D sCurrFeatTex3 { Texture = CurrFeatTex3; };
sampler2D sCurrFeatTex4 { Texture = CurrFeatTex4; };
sampler2D sCurrFeatTex5 { Texture = CurrFeatTex5; };
sampler2D sCurrFeatTex6 { Texture = CurrFeatTex6; };
sampler2D sCurrFeatTex7 { Texture = CurrFeatTex7; };
sampler2D sCurrFeatTex8 { Texture = CurrFeatTex8; };

sampler2D sPrevFeatTex1 { Texture = PrevFeatTex1; };
sampler2D sPrevFeatTex2 { Texture = PrevFeatTex2; };
sampler2D sPrevFeatTex3 { Texture = PrevFeatTex3; };
sampler2D sPrevFeatTex4 { Texture = PrevFeatTex4; };
sampler2D sPrevFeatTex5 { Texture = PrevFeatTex5; };
sampler2D sPrevFeatTex6 { Texture = PrevFeatTex6; };
sampler2D sPrevFeatTex7 { Texture = PrevFeatTex7; };
sampler2D sPrevFeatTex8 { Texture = PrevFeatTex8; };

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

float4 FilterMV(VSOUT i, int mot_mip, sampler mot_samp, float cen_z)
{
    float4 cen_mot_info = Sample(mot_samp, i.uv);
    /* return cen_mot_info; */

    float cen_mot_sq_len = dot(cen_mot_info.xy, cen_mot_info.xy);
    float rand = GetR1(GetBlueNoise(i.vpos.xy).x, 16);
    float2 scale = rcp(tex2Dsize(mot_samp)) * (mot_mip > 0 ? 4.0 : 2.0);
    float4 rot = GetRotator(rand * HALF_PI);
    int max_idx = mot_mip > 0 ? 25 : 9;
    float4 mot_info_acc = 0;

    static const float2 FILTER_OFFS[25] = {
        float2(0, 0),
        float2(1, 0), float2( 0,  1), float2(-1,  0), float2( 0, -1),
        float2(2, 0), float2( 0,  2), float2(-2,  0), float2( 0, -2),
        float2(1, 1), float2(-1, -1), float2(-1,  1), float2( 1, -1),
        float2(2, 1), float2( 2, -1), float2(-2,  1), float2(-2, -1),
        float2(1, 2), float2(-1,  2), float2( 1, -2), float2(-1, -2),
        float2(2, 2), float2(-2, -2), float2(-2,  2), float2( 2, -2)
    };

    [loop]for(int j = 0; j < max_idx; j++)
    {
        float2 tap_uv = i.uv + Rotate(FILTER_OFFS[j], rot) * scale;
        float4 tap_mot_info = Sample(mot_samp, tap_uv);
        float tap_z = tap_mot_info.w;
        float tap_dissim = tap_mot_info.z;
        float tap_mot_sq_len = dot(tap_mot_info.xy, tap_mot_info.xy);

        float wz = abs(cen_z - tap_z) * rcp(max(1e-15, min(cen_z, tap_z))) * 10.0;
        float ws = min(10.0, tap_dissim * 30.0); // don't remove the limit

        // helps with large but brief errors
        // the mult at the end is a compromise between correctness and having some motion (even if wrong)
        // increasing it would leave too many pixels without motion
        float wm = saturate(tap_mot_sq_len * rcp(max(1e-8, cen_mot_sq_len)) - 1.0) * 2.0;

        float weight = max(1e-8, exp2(-(wz + wm + ws))) * ValidateUV(tap_uv); // don't change the min value

        mot_info_acc += float4(tap_mot_info.xyz, 1.0) * weight;
    }

    mot_info_acc.xyz /= mot_info_acc.w;

    return float4(mot_info_acc.xyz, cen_z);
}

float4 CalcMV(VSOUT i, int mot_mip, sampler mot_samp, sampler curr_feat_samp, sampler prev_feat_samp)
{
    // don't change those values, artifacts arise otherwise
    // must prevent searching for pixel if center is already similar enough
    static const float eps = 1e-6;
    static const float max_sim = 1.0 - eps;

    float2 texel_size = rcp(tex2Dsize(curr_feat_samp));
    float depth = Sample(curr_feat_samp, i.uv).y;
    float2 local_taps[DIAMOND_S];
    float2 m_local = eps;
    float2 m_search = eps;
    float2 m_cov = eps;
    float2 total_motion = 0;

    if(mot_mip < MAX_MIP)
    {
        float4 prev_mip_mot_info = FilterMV(i, mot_mip, mot_samp, depth);

        //reverse the pow(x, 0.25) below
        prev_mip_mot_info.z *= prev_mip_mot_info.z;
        prev_mip_mot_info.z *= prev_mip_mot_info.z;

        float prev_mip_sim = 1.0 - prev_mip_mot_info.z;

        // apply a curve (might change in the future to ^2 or ^4)
        prev_mip_sim *= prev_mip_sim * prev_mip_sim;

        // use prev mip's similarity to check if the fg hasn't moved as much as the bg
        // graph: https://www.desmos.com/calculator/vwhierm95j
        total_motion.xy = prev_mip_mot_info.xy * prev_mip_sim;
    }

    // negligible performance boost to do the below loop here,
    // but maybe there's more at 4k resolution?
    // alternatively can be put inside the main loop below to shorten the code

#if IS_DX9
    [unroll] // needed for dx9
#else
    [loop] // faster compile speed
#endif
    for(int j = 0; j < DIAMOND_S; j++)
    {
        float2 tap_uv = i.uv + DIAMOND_OFFS[j] * texel_size;
        float2 tap_l = Sample(curr_feat_samp, tap_uv).xy;
        float2 tap_s = Sample(prev_feat_samp, tap_uv + total_motion).xy;

        local_taps[j] = tap_l;
        m_local += tap_l * tap_l;
        m_search += tap_s * tap_s;
        m_cov += tap_s * tap_l;
    }

    float best_sim = saturate(Min2(m_cov * rsqrt(m_local * m_search)));
    float rand = GetR1(GetBlueNoise(i.vpos.xy).x, 16);
    float2 randdir; sincos(rand * DOUBLE_PI, randdir.x, randdir.y);

    // the below settings have been tested to give best quality for high perf
    int searches = mot_mip > 3 ? 4 : 2;
    static const int rotations = 4; //mot_mip > 3 ? 6 : 4;
    static const float4 rot = GetRotator(DOUBLE_PI / float(rotations));

    [loop]for(int s = 0; s < searches; s++)
    {
        if(best_sim > max_sim) break;

        float2 local_motion = 0;
        float2 search_offs = 0;

        [loop]for(int k = 0; k < rotations; k++)
        {
            if(best_sim > max_sim) break;

            randdir = Rotate(randdir, rot);
            search_offs = randdir * texel_size;
            m_search = eps;
            m_cov = eps;

            [loop]for(int j = 0; j < DIAMOND_S; j++)
            {
                float2 tap_uv = i.uv + DIAMOND_OFFS[j] * texel_size + total_motion + search_offs;
                float2 tap_s = Sample(prev_feat_samp, tap_uv).xy;
                float2 tap_l = local_taps[j];

                m_search += tap_s * tap_s;
                m_cov += tap_s * tap_l;
            }

            float sim = saturate(Min2(m_cov * rsqrt(m_local * m_search)));

            if(sim > best_sim)
            {
                best_sim = sim;
                local_motion = search_offs;
            }
        }

        total_motion += local_motion;
        randdir *= 0.25; // tested best value
    }

    // NB: if changing the code below, change the code above as well
    // expand the range of best_sim before converting to dissimilarity
    // better to use pow(1 - x, 0.25) than (1 - x^4) cuz of texture precision
    float dissim = POW(1.0 - saturate((best_sim - 0.5) * 2.0), 0.25);

    return float4(total_motion, dissim, depth);
}

float2 DownsampleFeat(float2 uv, sampler feat_samp)
{
    float2 texel_size = rcp(tex2Dsize(feat_samp));
    float2 acc = 0;

    [loop]for(int j = 0; j < DIAMOND_S; j++)
        acc += Sample(feat_samp, uv + DIAMOND_OFFS[j] * texel_size).xy;

    return acc / 9.0;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_WriteFeat(PS_ARGS2)
{
    float3 c = SampleGammaColor(i.uv);

#if !IS_SRGB
    c = ApplyLinCurve(c);
    c = Tonemap::ApplyReinhardMax(c, 1.0);
#endif

    o = float2(dot(c, A_THIRD), GetDepth(i.uv));
}

void PS_DownFeat2(PS_ARGS2) { o = DownsampleFeat(i.uv, sCurrFeatTex1); }
void PS_DownFeat3(PS_ARGS2) { o = DownsampleFeat(i.uv, sCurrFeatTex2); }
void PS_DownFeat4(PS_ARGS2) { o = DownsampleFeat(i.uv, sCurrFeatTex3); }
void PS_DownFeat5(PS_ARGS2) { o = DownsampleFeat(i.uv, sCurrFeatTex4); }
void PS_DownFeat6(PS_ARGS2) { o = DownsampleFeat(i.uv, sCurrFeatTex5); }
void PS_DownFeat7(PS_ARGS2) { o = DownsampleFeat(i.uv, sCurrFeatTex6); }
void PS_DownFeat8(PS_ARGS2) { o = DownsampleFeat(i.uv, sCurrFeatTex7); }

void PS_CopyFeat1(PS_ARGS2) { o = Sample(sCurrFeatTex1, i.uv).xy; }
void PS_CopyFeat2(PS_ARGS2) { o = Sample(sCurrFeatTex2, i.uv).xy; }
void PS_CopyFeat3(PS_ARGS2) { o = Sample(sCurrFeatTex3, i.uv).xy; }
void PS_CopyFeat4(PS_ARGS2) { o = Sample(sCurrFeatTex4, i.uv).xy; }
void PS_CopyFeat5(PS_ARGS2) { o = Sample(sCurrFeatTex5, i.uv).xy; }
void PS_CopyFeat6(PS_ARGS2) { o = Sample(sCurrFeatTex6, i.uv).xy; }
void PS_CopyFeat7(PS_ARGS2) { o = Sample(sCurrFeatTex7, i.uv).xy; }
void PS_CopyFeat8(PS_ARGS2) { o = Sample(sCurrFeatTex8, i.uv).xy; }

// feature samplers are higher res for better quality
void PS_Motion9(PS_ARGS4) { o = CalcMV(i, 9, sMotionTexB, sCurrFeatTex8, sPrevFeatTex8); }
void PS_Motion8(PS_ARGS4) { o = CalcMV(i, 8, sMotionTexB, sCurrFeatTex7, sPrevFeatTex7); }
void PS_Motion7(PS_ARGS4) { o = CalcMV(i, 7, sMotionTexB, sCurrFeatTex6, sPrevFeatTex6); }
void PS_Motion6(PS_ARGS4) { o = CalcMV(i, 6, sMotionTexB, sCurrFeatTex5, sPrevFeatTex5); }
void PS_Motion5(PS_ARGS4) { o = CalcMV(i, 5, sMotionTexB, sCurrFeatTex4, sPrevFeatTex4); }
void PS_Motion4(PS_ARGS4) { o = CalcMV(i, 4, sMotionTexB, sCurrFeatTex3, sPrevFeatTex3); }
void PS_Motion3(PS_ARGS4) { o = CalcMV(i, 3, sMotionTexB, sCurrFeatTex2, sPrevFeatTex2); }
void PS_Motion2(PS_ARGS4) { o = CalcMV(i, 2, sMotionTexB, sCurrFeatTex1, sPrevFeatTex1); }
void PS_Motion1(PS_ARGS4) { o = CalcMV(i, 1, sMotionTex2, sCurrFeatTex1, sPrevFeatTex1); }

// extra filtering for quality increase at nearly no perf cost
void PS_Filter8(PS_ARGS4) { o = FilterMV(i, 8, sMotionTexA, Sample(sCurrFeatTex7, i.uv).y); }
void PS_Filter7(PS_ARGS4) { o = FilterMV(i, 7, sMotionTexA, Sample(sCurrFeatTex6, i.uv).y); }
void PS_Filter6(PS_ARGS4) { o = FilterMV(i, 6, sMotionTexA, Sample(sCurrFeatTex5, i.uv).y); }
void PS_Filter5(PS_ARGS4) { o = FilterMV(i, 5, sMotionTexA, Sample(sCurrFeatTex4, i.uv).y); }
void PS_Filter4(PS_ARGS4) { o = FilterMV(i, 4, sMotionTexA, Sample(sCurrFeatTex3, i.uv).y); }
void PS_Filter3(PS_ARGS4) { o = FilterMV(i, 3, sMotionTexA, Sample(sCurrFeatTex2, i.uv).y); }
void PS_Filter2(PS_ARGS4) { o = FilterMV(i, 2, sMotionTexA, Sample(sCurrFeatTex1, i.uv).y); }

void PS_Filter0(PS_ARGS2) { o = FilterMV(i, 0, sMotionTex1, GetDepth(i.uv)).xy; }

/*******************************************************************************
    Passes
*******************************************************************************/

#if BUFFER_HEIGHT < 2160
    #define PASS_MV_EXTRA
#else
    #define PASS_MV_EXTRA \
        pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion9; RenderTarget = MV::MotionTexA; } \
        pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter8; RenderTarget = MV::MotionTexB; }
#endif

#define PASS_MV \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_WriteFeat; RenderTarget = MV::CurrFeatTex1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat2; RenderTarget = MV::CurrFeatTex2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat3; RenderTarget = MV::CurrFeatTex3; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat4; RenderTarget = MV::CurrFeatTex4; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat5; RenderTarget = MV::CurrFeatTex5; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat6; RenderTarget = MV::CurrFeatTex6; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat7; RenderTarget = MV::CurrFeatTex7; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_DownFeat8; RenderTarget = MV::CurrFeatTex8; } \
    PASS_MV_EXTRA \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion8;   RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter7;   RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion7;   RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter6;   RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion6;   RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter5;   RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion5;   RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter4;   RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion4;   RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter3;   RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion3;   RenderTarget = MV::MotionTexA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter2;   RenderTarget = MV::MotionTexB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion2;   RenderTarget = MV::MotionTex2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Motion1;   RenderTarget = MV::MotionTex1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_Filter0;   RenderTarget = MotVectTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat1; RenderTarget = MV::PrevFeatTex1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat2; RenderTarget = MV::PrevFeatTex2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat3; RenderTarget = MV::PrevFeatTex3; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat4; RenderTarget = MV::PrevFeatTex4; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat5; RenderTarget = MV::PrevFeatTex5; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat6; RenderTarget = MV::PrevFeatTex6; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat7; RenderTarget = MV::PrevFeatTex7; } \
    pass { VertexShader = PostProcessVS; PixelShader = MV::PS_CopyFeat8; RenderTarget = MV::PrevFeatTex8; }

} // namespace end
