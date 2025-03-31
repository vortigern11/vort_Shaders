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

namespace MotVect {

/*******************************************************************************
    Globals
*******************************************************************************/

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

texture2D CurrFeatTexVort1 { TEX_SIZE(1) TEX_RG16 };
texture2D CurrFeatTexVort2 { TEX_SIZE(2) TEX_RG16 };
texture2D CurrFeatTexVort3 { TEX_SIZE(3) TEX_RG16 };
texture2D CurrFeatTexVort4 { TEX_SIZE(4) TEX_RG16 };
texture2D CurrFeatTexVort5 { TEX_SIZE(5) TEX_RG16 };
texture2D CurrFeatTexVort6 { TEX_SIZE(6) TEX_RG16 };
texture2D CurrFeatTexVort7 { TEX_SIZE(7) TEX_RG16 };

texture2D PrevFeatTexVort1 { TEX_SIZE(1) TEX_RG16 };
texture2D PrevFeatTexVort2 { TEX_SIZE(2) TEX_RG16 };
texture2D PrevFeatTexVort3 { TEX_SIZE(3) TEX_RG16 };
texture2D PrevFeatTexVort4 { TEX_SIZE(4) TEX_RG16 };
texture2D PrevFeatTexVort5 { TEX_SIZE(5) TEX_RG16 };
texture2D PrevFeatTexVort6 { TEX_SIZE(6) TEX_RG16 };
texture2D PrevFeatTexVort7 { TEX_SIZE(7) TEX_RG16 };

sampler2D sCurrFeatTexVort1 { Texture = CurrFeatTexVort1; SAM_MIRROR };
sampler2D sCurrFeatTexVort2 { Texture = CurrFeatTexVort2; SAM_MIRROR };
sampler2D sCurrFeatTexVort3 { Texture = CurrFeatTexVort3; SAM_MIRROR };
sampler2D sCurrFeatTexVort4 { Texture = CurrFeatTexVort4; SAM_MIRROR };
sampler2D sCurrFeatTexVort5 { Texture = CurrFeatTexVort5; SAM_MIRROR };
sampler2D sCurrFeatTexVort6 { Texture = CurrFeatTexVort6; SAM_MIRROR };
sampler2D sCurrFeatTexVort7 { Texture = CurrFeatTexVort7; SAM_MIRROR };

sampler2D sPrevFeatTexVort1 { Texture = PrevFeatTexVort1; SAM_MIRROR };
sampler2D sPrevFeatTexVort2 { Texture = PrevFeatTexVort2; SAM_MIRROR };
sampler2D sPrevFeatTexVort3 { Texture = PrevFeatTexVort3; SAM_MIRROR };
sampler2D sPrevFeatTexVort4 { Texture = PrevFeatTexVort4; SAM_MIRROR };
sampler2D sPrevFeatTexVort5 { Texture = PrevFeatTexVort5; SAM_MIRROR };
sampler2D sPrevFeatTexVort6 { Texture = PrevFeatTexVort6; SAM_MIRROR };
sampler2D sPrevFeatTexVort7 { Texture = PrevFeatTexVort7; SAM_MIRROR };

texture2D MotionTexVort1 { TEX_SIZE(1) TEX_RGBA16 };
texture2D MotionTexVort2 { TEX_SIZE(2) TEX_RGBA16 };
texture2D MotionTexVortA { TEX_SIZE(3) TEX_RGBA16 };
texture2D MotionTexVortB { TEX_SIZE(3) TEX_RGBA16 };

sampler2D sMotionTexVort1 { Texture = MotionTexVort1; SAM_POINT };
sampler2D sMotionTexVort2 { Texture = MotionTexVort2; SAM_POINT };
sampler2D sMotionTexVortA { Texture = MotionTexVortA; SAM_POINT };
sampler2D sMotionTexVortB { Texture = MotionTexVortB; SAM_POINT };

/*******************************************************************************
    Functions
*******************************************************************************/

float4 FilterMotion(VSOUT i, int mip, sampler mot_samp, sampler feat_samp)
{
    float4 cen_motion = Sample(mot_samp, i.uv);
    /* return cen_motion; */

    float2 scale = rcp(tex2Dsize(mot_samp)) * 4.0;
    float rand = GetR1(GetBlueNoise(i.vpos.xy).x, mip + 1);
    float4 rot = GetRotator(rand * HALF_PI);
    float center_z = Sample(feat_samp, i.uv).y;
    float cen_mot_sq_len = dot(cen_motion.xy, cen_motion.xy);

    if(mip == 0) center_z = GetDepth(i.uv);

    float3 motion_acc = 0;
    int r = min(mip + 1, 2);

    [loop]for(int x = -r; x <= r; x++)
    [loop]for(int y = -r; y <= r; y++)
    {
        float2 sample_uv = i.uv + Rotate(float2(x, y), rot) * scale;
        float4 sample_mot = Sample(mot_samp, sample_uv);
        float sample_mot_sq_len = dot(sample_mot.xy, sample_mot.xy);
        float cos_angle = dot(cen_motion.xy, sample_mot.xy) * RSQRT(cen_mot_sq_len * sample_mot_sq_len);

        float wz = abs(center_z - sample_mot.z) * RCP(min(center_z, sample_mot.z)) * 20.0;
        float wm = 0.25 * sample_mot_sq_len * BUFFER_WIDTH; // notice the diff when using MB
        float wd = saturate(0.5 * (0.5 + cos_angle)) * 2.0; // tested - opposite gives better results
        float weight = max(1e-8, exp2(-(wz + wm + wd))) * ValidateUV(sample_uv); // don't change the min value

        motion_acc += float3(sample_mot.xy, 1.0) * weight;
    }

    return float4(motion_acc.xy * RCP(motion_acc.z), center_z, 1.0);
}

float4 CalcMotion(VSOUT i, int mip, sampler mot_samp, sampler curr_feat_samp, sampler prev_feat_samp)
{
    static const float eps = 1e-15;

    float2 texel_size = rcp(tex2Dsize(curr_feat_samp));
    float2 local_samples[DIAMOND_S];
    float2 moments_local = eps;
    float2 moments_search = eps;
    float2 moments_cov = eps;
    float2 total_motion = 0;

    if(mip < MAX_MIP) total_motion = FilterMotion(i, mip, mot_samp, curr_feat_samp).xy;

    // negligible performance boost to do the below loop here,
    // but maybe there's more at 4k resolution, whatever
    // alternatively can be put inside the main loop below to shorten the code

#if IS_DX9
    [unroll] // needed for dx9
#else
    [loop] // faster compile speed
#endif
    for(uint j = 0; j < DIAMOND_S; j++)
    {
        float2 sample_uv = i.uv + DIAMOND_OFFS[j] * texel_size;
        float2 sample_l = Sample(curr_feat_samp, sample_uv).xy;
        float2 sample_s = Sample(prev_feat_samp, sample_uv + total_motion).xy;

        local_samples[j] = sample_l;
        moments_local += sample_l * sample_l;
        moments_search += sample_s * sample_s;
        moments_cov += sample_s * sample_l;
    }

    float2 cossim = moments_cov * rsqrt(moments_local * moments_search);
    float best_sim = saturate(min(cossim.x, cossim.y));
    float rand = GetR1(GetBlueNoise(i.vpos.xy).x, mip + 1);
    float2 randdir; sincos(rand * HALF_PI, randdir.x, randdir.y);
    int searches = mip > 3 ? 4 : 2;

    [loop]while(searches-- > 0)
    {
        float2 local_motion = 0;
        float2 search_offs = 0;
        int samples = 4; // 360deg / 90deg = 4

        [loop]while(samples-- > 0)
        {
            randdir = float2(randdir.y, -randdir.x); //rotate by 90 degrees
            search_offs = randdir * texel_size;
            moments_search = eps;
            moments_cov = eps;

            [loop]for(uint j = 0; j < DIAMOND_S; j++)
            {
                float2 sample_uv = i.uv + DIAMOND_OFFS[j] * texel_size + total_motion + search_offs;
                float2 sample_s = Sample(prev_feat_samp, sample_uv).xy;
                float2 sample_l = local_samples[j];

                moments_search += sample_s * sample_s;
                moments_cov += sample_s * sample_l;
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

    return float4(total_motion, depth, 1.0);
}

void DownsampleFeature(float2 uv, out PSOUT2 o, sampler feat_samp0, sampler feat_samp1)
{
    float2 texel_size = rcp(tex2Dsize(feat_samp0));
    float acc_w = 0;
    o.t0 = o.t1 = 0;

    [loop]for(int x = 0; x <= 3; x++)
    [loop]for(int y = 0; y <= 3; y++)
    {
        float2 offs = float2(x, y) - 1.5;
        float weight = exp(-0.1 * dot(offs, offs));

        o.t0 += Sample(feat_samp0, uv + offs * texel_size).xy * weight;
        o.t1 += Sample(feat_samp1, uv + offs * texel_size).xy * weight;
        acc_w += weight;
    }

    o.t0 /= acc_w;
    o.t1 /= acc_w;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_DownFeat2(VSOUT i, out PSOUT2 o) { DownsampleFeature(i.uv, o, sCurrFeatTexVort1, sPrevFeatTexVort1); }
void PS_DownFeat3(VSOUT i, out PSOUT2 o) { DownsampleFeature(i.uv, o, sCurrFeatTexVort2, sPrevFeatTexVort2); }
void PS_DownFeat4(VSOUT i, out PSOUT2 o) { DownsampleFeature(i.uv, o, sCurrFeatTexVort3, sPrevFeatTexVort3); }
void PS_DownFeat5(VSOUT i, out PSOUT2 o) { DownsampleFeature(i.uv, o, sCurrFeatTexVort4, sPrevFeatTexVort4); }
void PS_DownFeat6(VSOUT i, out PSOUT2 o) { DownsampleFeature(i.uv, o, sCurrFeatTexVort5, sPrevFeatTexVort5); }
void PS_DownFeat7(VSOUT i, out PSOUT2 o) { DownsampleFeature(i.uv, o, sCurrFeatTexVort6, sPrevFeatTexVort6); }

void PS_WriteFeature(PS_ARGS2)
{
#if MIN_MIP > 0
    float3 c = Filters::Wronski(sColorTexVort, i.uv, 0).rgb;
#else
    float3 c = SampleGammaColor(i.uv);
#endif

#if !IS_SRGB
    c = ApplyLinCurve(c);
    c = Tonemap::ApplyReinhardMax(c, 1.0);
#endif

    o = float2(dot(c, A_THIRD), GetDepth(i.uv));
}

// feature samplers are 1 mip higher for better quality
void PS_Motion8(PS_ARGS4) { o =   CalcMotion(i, 8, sMotionTexVortB, sCurrFeatTexVort7, sPrevFeatTexVort7); }
void PS_Motion7(PS_ARGS4) { o =   CalcMotion(i, 7, sMotionTexVortB, sCurrFeatTexVort6, sPrevFeatTexVort6); }
void PS_Motion6(PS_ARGS4) { o =   CalcMotion(i, 6, sMotionTexVortB, sCurrFeatTexVort5, sPrevFeatTexVort5); }
void PS_Motion5(PS_ARGS4) { o =   CalcMotion(i, 5, sMotionTexVortB, sCurrFeatTexVort4, sPrevFeatTexVort4); }
void PS_Motion4(PS_ARGS4) { o =   CalcMotion(i, 4, sMotionTexVortB, sCurrFeatTexVort3, sPrevFeatTexVort3); }
void PS_Motion3(PS_ARGS4) { o =   CalcMotion(i, 3, sMotionTexVortB, sCurrFeatTexVort2, sPrevFeatTexVort2); }
void PS_Motion2(PS_ARGS4) { o =   CalcMotion(i, 2, sMotionTexVortB, sCurrFeatTexVort1, sPrevFeatTexVort1); }
void PS_Motion1(PS_ARGS4) { o =   CalcMotion(i, 1, sMotionTexVort2, sCurrFeatTexVort1, sPrevFeatTexVort1); }
void PS_Motion0(PS_ARGS4) { o = FilterMotion(i, 0, sMotionTexVort1, sCurrFeatTexVort1); }

// slight quality increase for nearly no perf cost
void PS_Filter7(PS_ARGS4) { o = FilterMotion(i, 7, sMotionTexVortA, sCurrFeatTexVort6); }
void PS_Filter6(PS_ARGS4) { o = FilterMotion(i, 6, sMotionTexVortA, sCurrFeatTexVort5); }
void PS_Filter5(PS_ARGS4) { o = FilterMotion(i, 5, sMotionTexVortA, sCurrFeatTexVort4); }
void PS_Filter4(PS_ARGS4) { o = FilterMotion(i, 4, sMotionTexVortA, sCurrFeatTexVort3); }
void PS_Filter3(PS_ARGS4) { o = FilterMotion(i, 3, sMotionTexVortA, sCurrFeatTexVort2); }
void PS_Filter2(PS_ARGS4) { o = FilterMotion(i, 2, sMotionTexVortA, sCurrFeatTexVort1); }

/*******************************************************************************
    Passes
*******************************************************************************/

#if BUFFER_HEIGHT < 2160
    #define PASS_MV_EXTRA
#else
    #define PASS_MV_EXTRA \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat7; RenderTarget0 = MotVect::CurrFeatTexVort7; RenderTarget1 = MotVect::PrevFeatTexVort7; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion8; RenderTarget = MotVect::MotionTexVortA; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter7; RenderTarget = MotVect::MotionTexVortB; }
#endif

#define PASS_MV \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::CurrFeatTexVort1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat2;    RenderTarget0 = MotVect::CurrFeatTexVort2; RenderTarget1 = MotVect::PrevFeatTexVort2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat3;    RenderTarget0 = MotVect::CurrFeatTexVort3; RenderTarget1 = MotVect::PrevFeatTexVort3; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat4;    RenderTarget0 = MotVect::CurrFeatTexVort4; RenderTarget1 = MotVect::PrevFeatTexVort4; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat5;    RenderTarget0 = MotVect::CurrFeatTexVort5; RenderTarget1 = MotVect::PrevFeatTexVort5; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat6;    RenderTarget0 = MotVect::CurrFeatTexVort6; RenderTarget1 = MotVect::PrevFeatTexVort6; } \
    PASS_MV_EXTRA \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion7;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter6;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion6;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter5;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion5;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter4;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion4;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter3;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion3;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter2;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion2;      RenderTarget = MotVect::MotionTexVort2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion1;      RenderTarget = MotVect::MotionTexVort1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion0;      RenderTarget = MotVectTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::PrevFeatTexVort1; }

} // namespace end
