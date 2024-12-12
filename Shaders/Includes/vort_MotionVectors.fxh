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

// don't raise MAX_MIP higher!

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

#if IS_DX9
    texture2D FeatTexVort1 { TEX_SIZE(MIN_MIP) TEX_RGBA16 MipLevels = 1 + MAX_MIP - MIN_MIP; };
    #define FeatTexVort2 FeatTexVort1
    #define FeatTexVort3 FeatTexVort1
    #define FeatTexVort4 FeatTexVort1
    #define FeatTexVort5 FeatTexVort1
    #define FeatTexVort6 FeatTexVort1
    #define FeatTexVort7 FeatTexVort1

    sampler2D sFeatTexVort1 { Texture = FeatTexVort1; SAM_MIRROR };
    #define sFeatTexVort2 sFeatTexVort1
    #define sFeatTexVort3 sFeatTexVort1
    #define sFeatTexVort4 sFeatTexVort1
    #define sFeatTexVort5 sFeatTexVort1
    #define sFeatTexVort6 sFeatTexVort1
    #define sFeatTexVort7 sFeatTexVort1
#else
    texture2D FeatTexVort1 { TEX_SIZE(1) TEX_RGBA16 };
    texture2D FeatTexVort2 { TEX_SIZE(2) TEX_RGBA16 };
    texture2D FeatTexVort3 { TEX_SIZE(3) TEX_RGBA16 };
    texture2D FeatTexVort4 { TEX_SIZE(4) TEX_RGBA16 };
    texture2D FeatTexVort5 { TEX_SIZE(5) TEX_RGBA16 };
    texture2D FeatTexVort6 { TEX_SIZE(6) TEX_RGBA16 };
    texture2D FeatTexVort7 { TEX_SIZE(7) TEX_RGBA16 };

    sampler2D sFeatTexVort1  { Texture = FeatTexVort1; SAM_MIRROR };
    sampler2D sFeatTexVort2  { Texture = FeatTexVort2; SAM_MIRROR };
    sampler2D sFeatTexVort3  { Texture = FeatTexVort3; SAM_MIRROR };
    sampler2D sFeatTexVort4  { Texture = FeatTexVort4; SAM_MIRROR };
    sampler2D sFeatTexVort5  { Texture = FeatTexVort5; SAM_MIRROR };
    sampler2D sFeatTexVort6  { Texture = FeatTexVort6; SAM_MIRROR };
    sampler2D sFeatTexVort7  { Texture = FeatTexVort7; SAM_MIRROR };
#endif

texture2D MotionTexVort1 { TEX_SIZE(1) TEX_RG16 };
texture2D MotionTexVort2 { TEX_SIZE(2) TEX_RG16 };
texture2D MotionTexVortA { TEX_SIZE(3) TEX_RG16 };
texture2D MotionTexVortB { TEX_SIZE(3) TEX_RG16 };

// DON'T FUCKING USE POINT SAMPLERS HERE
sampler2D sMotionTexVort1 { Texture = MotionTexVort1; };
sampler2D sMotionTexVort2 { Texture = MotionTexVort2; };
sampler2D sMotionTexVortA { Texture = MotionTexVortA; };
sampler2D sMotionTexVortB { Texture = MotionTexVortB; };

/*******************************************************************************
    Functions
*******************************************************************************/

float2 CalcLayer(VSOUT i, int mip, float2 total_motion, sampler feat_samp)
{
    // one mip lower on purpose for better results
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(max(0, mip - 1));
    uint feature_mip = IS_DX9 ? max(0, mip - (MIN_MIP + 1)) : 0; // better results

    static const float eps = 1e-6;
    static const float max_sim = 1.0 - eps;

    float2 moments_local = eps;
    float2 moments_search = eps;
    float2 moments_cov = eps;

    [loop]for(uint j = 0; j < DIAMOND_S; j++)
    {
        float2 tuv = i.uv + DIAMOND_OFFS[j] * texelsize;
        float2 t_local = Sample(feat_samp, tuv, feature_mip).xy;
        float2 t_search = Sample(feat_samp, tuv + total_motion, feature_mip).zw;

        moments_local += t_local * t_local;
        moments_search += t_search * t_search;
        moments_cov += t_local * t_search;
    }

    float2 cossim = moments_cov * rsqrt(moments_local * moments_search);
    float best_sim = saturate(min(cossim.x, cossim.y));

    // we use 4 samples so we will rotate by 90 degrees to make a full circle
    // therefore we do sincos(rand * 90deg, r.x, r.y)
    float qrand = GetR1(GetBlueNoise(i.vpos.xy).x, mip);
    float2 randdir; sincos(qrand * HALF_PI, randdir.x, randdir.y);
    int searches = mip > 3 ? 4 : 2;

    [loop]while(searches-- > 0 && best_sim < max_sim)
    {
        float2 local_motion = 0;
        int samples = 4; // 360deg / 90deg = 4

        [loop]while(samples-- > 0 && best_sim < max_sim)
        {
            //rotate by 90 degrees
            randdir = float2(randdir.y, -randdir.x);

            float2 search_offset = randdir * texelsize;

            moments_search = eps;
            moments_cov = eps;

            [loop]for(uint j = 0; j < DIAMOND_S; j++)
            {
                float2 tuv = i.uv + DIAMOND_OFFS[j] * texelsize;
                float2 t_local = Sample(feat_samp, tuv, feature_mip).xy;
                float2 t_search = Sample(feat_samp, tuv + total_motion + search_offset, feature_mip).zw;

                moments_search += t_search * t_search;
                moments_cov += t_search * t_local;
            }

            cossim = moments_cov * rsqrt(moments_local * moments_search);
            float sim = saturate(min(cossim.x, cossim.y));

            if(sim > best_sim)
            {
                best_sim = sim;
                local_motion = search_offset;
            }
        }

        total_motion += local_motion;
        randdir *= 0.5;
    }

    return total_motion;
}

float2 AtrousUpscale(VSOUT i, int mip, sampler mot_samp, sampler feat_samp)
{
    // tested in lots of scenarios, in different games, with and without MB
    float2 scale = rcp(tex2Dsize(mot_samp)) * (mip > 3 ? 4.0 : 2.0);

    uint feature_mip = IS_DX9 ? max(0, mip - MIN_MIP) : 0; // better results
    float2 qrand = GetR2(GetBlueNoise(i.vpos.xy).xy, mip + 1) - 0.5;
    float center_z = Sample(feat_samp, i.uv, feature_mip).y;
    float2 cen_motion = Sample(mot_samp, i.uv).xy;
    float cen_sq_len = dot(cen_motion, cen_motion);

    if(mip < MIN_MIP) center_z = GetDepth(i.uv);

    float3 motion_acc = 0;

    [loop]for(uint j = 0; j < DIAMOND_S; j++)
    {
        float2 sample_uv = i.uv + (DIAMOND_OFFS[j] + qrand) * scale;
        float2 sample_mot = Sample(mot_samp, sample_uv).xy;
        float sample_z = Sample(feat_samp, sample_uv, feature_mip).y;
        float sample_sq_len = dot(sample_mot, sample_mot);
        float cos_angle = dot(cen_motion, sample_mot) * RSQRT(cen_sq_len * sample_sq_len);

        float wz = abs(center_z - sample_z) * RCP(min(center_z, sample_z)) * 20.0;
        float wm = sample_sq_len * BUFFER_WIDTH; // don't change this, can notice the diff when using MB
        float wd = saturate(0.5 * (0.5 + cos_angle)) * 2.0; // tested - opposite gives better results
        float weight = max(EPSILON, exp2(-(wz + wm + wd))); // don't change the min value

        // don't use samples without motion or outside screen
        weight *= (sample_sq_len > 0.0) * ValidateUV(sample_uv);
        motion_acc += float3(sample_mot, 1.0) * weight;
    }

    return motion_acc.xy * RCP(motion_acc.z);
    /* return Sample(mot_samp, i.uv).xy; */
}

float2 EstimateMotion(VSOUT i, int mip, sampler mot_samp, sampler feat_samp)
{
    float2 motion = 0;

    if(mip < MAX_MIP)
        motion = AtrousUpscale(i, mip, mot_samp, feat_samp);

    if(mip >= MIN_MIP)
        motion = CalcLayer(i, mip, motion, feat_samp);

    return motion;
}

float4 DownsampleFeature(float2 uv, sampler feat_samp)
{
    float2 texelsize = rcp(tex2Dsize(feat_samp));
    float4 acc = 0;
    float acc_w = 0;

    [loop]for(int x = 0; x <= 3; x++)
    [loop]for(int y = 0; y <= 3; y++)
    {
        float2 offs = float2(x, y) - 1.5;
        float4 sample_feat = Sample(feat_samp, uv + offs * texelsize);
        float weight = exp(-0.1 * dot(offs, offs));

        acc += sample_feat * weight;
        acc_w += weight;
    }

    return acc / acc_w;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_DownFeat2(PS_ARGS4) { o = DownsampleFeature(i.uv, sFeatTexVort1); }
void PS_DownFeat3(PS_ARGS4) { o = DownsampleFeature(i.uv, sFeatTexVort2); }
void PS_DownFeat4(PS_ARGS4) { o = DownsampleFeature(i.uv, sFeatTexVort3); }
void PS_DownFeat5(PS_ARGS4) { o = DownsampleFeature(i.uv, sFeatTexVort4); }
void PS_DownFeat6(PS_ARGS4) { o = DownsampleFeature(i.uv, sFeatTexVort5); }
void PS_DownFeat7(PS_ARGS4) { o = DownsampleFeature(i.uv, sFeatTexVort6); }

void PS_WriteFeature(PS_ARGS4)
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

    o = float2(dot(c, A_THIRD), GetDepth(i.uv)).xyxy;
}

void PS_Motion8(PS_ARGS2) { o = EstimateMotion(i, 8, sMotionTexVortB, sFeatTexVort7); }
void PS_Motion7(PS_ARGS2) { o = EstimateMotion(i, 7, sMotionTexVortB, sFeatTexVort6); }
void PS_Motion6(PS_ARGS2) { o = EstimateMotion(i, 6, sMotionTexVortB, sFeatTexVort5); }
void PS_Motion5(PS_ARGS2) { o = EstimateMotion(i, 5, sMotionTexVortB, sFeatTexVort4); }
void PS_Motion4(PS_ARGS2) { o = EstimateMotion(i, 4, sMotionTexVortB, sFeatTexVort3); }
void PS_Motion3(PS_ARGS2) { o = EstimateMotion(i, 3, sMotionTexVortB, sFeatTexVort2); }
void PS_Motion2(PS_ARGS2) { o = EstimateMotion(i, 2, sMotionTexVortB, sFeatTexVort1); }
void PS_Motion1(PS_ARGS2) { o = EstimateMotion(i, 1, sMotionTexVort2, sFeatTexVort1); }
void PS_Motion0(PS_ARGS2) { o = EstimateMotion(i, 0, sMotionTexVort1, sFeatTexVort1); }

// slight quality increase for nearly no perf cost
void PS_Filter7(PS_ARGS2) { o = AtrousUpscale(i, 7, sMotionTexVortA, sFeatTexVort7); }
void PS_Filter6(PS_ARGS2) { o = AtrousUpscale(i, 6, sMotionTexVortA, sFeatTexVort6); }
void PS_Filter5(PS_ARGS2) { o = AtrousUpscale(i, 5, sMotionTexVortA, sFeatTexVort5); }
void PS_Filter4(PS_ARGS2) { o = AtrousUpscale(i, 4, sMotionTexVortA, sFeatTexVort4); }
void PS_Filter3(PS_ARGS2) { o = AtrousUpscale(i, 3, sMotionTexVortA, sFeatTexVort3); }
void PS_Filter2(PS_ARGS2) { o = AtrousUpscale(i, 2, sMotionTexVortA, sFeatTexVort2); }

/*******************************************************************************
    Passes
*******************************************************************************/

#if IS_DX9
    #define PASS_MV_EXTRA_1
#else
    #define PASS_MV_EXTRA_1 \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat2; RenderTarget = MotVect::FeatTexVort2; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat3; RenderTarget = MotVect::FeatTexVort3; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat4; RenderTarget = MotVect::FeatTexVort4; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat5; RenderTarget = MotVect::FeatTexVort5; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat6; RenderTarget = MotVect::FeatTexVort6; }
#endif

#if (IS_DX9) || (BUFFER_HEIGHT < 2160)
    #define PASS_MV_EXTRA_2
#else
    #define PASS_MV_EXTRA_2 \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_DownFeat7; RenderTarget = MotVect::FeatTexVort7; }
#endif

#if BUFFER_HEIGHT < 2160
    #define PASS_MV_EXTRA_3
#else
    #define PASS_MV_EXTRA_3 \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion8; RenderTarget = MotVect::MotionTexVortA; } \
        pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter7; RenderTarget = MotVect::MotionTexVortB; }
#endif

#define PASS_MV \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::FeatTexVort1; RenderTargetWriteMask = 3; } \
    PASS_MV_EXTRA_1 \
    PASS_MV_EXTRA_2 \
    PASS_MV_EXTRA_3 \
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
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::FeatTexVort1; RenderTargetWriteMask = 12; }

} // namespace end
