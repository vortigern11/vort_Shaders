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
#include "Includes/vort_Filters.fxh"
#include "Includes/vort_Motion_UI.fxh"

namespace MotVect {

/*******************************************************************************
    Globals
*******************************************************************************/

#define MAX_MIP 6

#if V_MV_USE_HQ
    #define MIN_MIP 0
#else
    #define MIN_MIP 1
#endif

static const int block_samples = 9;
static const float2 block_offs[block_samples] =
{
    float2(0, 0),
    float2(-1, -1), float2(1, 1), float2(-1, 1), float2(1, -1),
    float2(0, -2), float2(0, 2), float2(-2, 0), float2(2, 0)
};

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D CurrFeatTexVort { TEX_SIZE(MIN_MIP) TEX_RG16 MipLevels = 1 + MAX_MIP - MIN_MIP; };
texture2D PrevFeatTexVort { TEX_SIZE(MIN_MIP) TEX_RG16 MipLevels = 1 + MAX_MIP - MIN_MIP; };

sampler2D sCurrFeatTexVort { Texture = CurrFeatTexVort; };
sampler2D sPrevFeatTexVort { Texture = PrevFeatTexVort; };

texture2D MotionTexVort1 { TEX_SIZE(1) TEX_RG16 };
texture2D MotionTexVortA { TEX_SIZE(3) TEX_RG16 };
texture2D MotionTexVortB { TEX_SIZE(3) TEX_RG16 };

sampler2D sMotionTexVort1 { Texture = MotionTexVort1; SAM_POINT };
sampler2D sMotionTexVortA { Texture = MotionTexVortA; SAM_POINT };
sampler2D sMotionTexVortB { Texture = MotionTexVortB; SAM_POINT };

#if IS_DX9
    #define MotionTexVort2 MotionTexVortA
    #define sMotionTexVort2 sMotionTexVortA
#else
    texture2D MotionTexVort2 { TEX_SIZE(2) TEX_RG16 };
    sampler2D sMotionTexVort2 { Texture = MotionTexVort2; SAM_POINT };
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float2 CalcLayer(VSOUT i, int mip, float2 total_motion)
{
    // one mip lower on purpose for better results
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(max(0, mip - 1));
    uint feature_mip = max(0, mip - MIN_MIP);

    float2 moments_local = 1e-6;
    float2 moments_search = 1e-6;
    float2 moments_cov = 1e-6;

    [loop]for(int j = 0; j < block_samples; j++)
    {
        float2 tuv = i.uv + block_offs[j] * texelsize;
        float2 t_local = Sample(sCurrFeatTexVort, saturate(tuv), feature_mip).xy;
        float2 t_search = Sample(sPrevFeatTexVort, saturate(tuv + total_motion), feature_mip).xy;

        moments_local += t_local * t_local;
        moments_search += t_search * t_search;
        moments_cov += t_local * t_search;
    }

    float2 cossim = moments_cov * rsqrt(moments_local * moments_search);
    float best_sim = saturate(min(cossim.x, cossim.y));
    static const float max_sim = 0.999999;

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

            moments_search = 1e-6;
            moments_cov = 1e-6;

            [loop]for(int j = 0; j < block_samples; j++)
            {
                float2 tuv = i.uv + block_offs[j] * texelsize;
                float2 t_local = Sample(sCurrFeatTexVort, saturate(tuv), feature_mip).xy;
                float2 t_search = Sample(sPrevFeatTexVort, saturate(tuv + total_motion + search_offset), feature_mip).xy;

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

float2 AtrousUpscale(VSOUT i, int mip, sampler mot_samp)
{
    uint feature_mip = max(0, mip - MIN_MIP); // lower for better results
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(mip + 1); // independent of mot_samp size
    float2 scale = texelsize * (mip > 0 ? UI_MV_SCALE : 1.0);
    float2 qrand = GetR2(GetBlueNoise(i.vpos.xy).xy, mip + 1) - 0.5;
    float center_z = Sample(sCurrFeatTexVort, i.uv, feature_mip).y;

    if(mip < MIN_MIP) center_z = GetDepth(i.uv);

    float wsum = 0;
    float2 motion_sum = 0;

    [loop]for(int j = 0; j < block_samples; j++)
    {
        float2 sample_uv = i.uv + (block_offs[j] + qrand) * scale;
        float2 sample_mot = Sample(mot_samp, sample_uv).xy;
        float sample_z = Sample(sCurrFeatTexVort, sample_uv, feature_mip).y;

        float wz = abs(center_z - sample_z) * RCP(max(center_z, sample_z)) * 5.0; // depth delta
        float wm = dot(sample_mot, sample_mot) * 250.0; // long motion
        float weight = exp2(-(wz + wm) * 4.0) + 1e-6;

        weight *= all(saturate(sample_uv - sample_uv * sample_uv));
        wsum += weight;
        motion_sum += sample_mot * weight;
    }

    return motion_sum / wsum;
    /* return Sample(mot_samp, i.uv).xy; */
}

float2 EstimateMotion(VSOUT i, int mip, sampler mot_samp)
{
    float2 motion = 0;

    if(mip < MAX_MIP)
        motion = AtrousUpscale(i, mip, mot_samp);

    if(mip >= MIN_MIP)
        motion = CalcLayer(i, mip, motion);

    return motion;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_WriteFeature(PS_ARGS2)
{
#if MIN_MIP > 0
    float3 c = Filter8Taps(sGammaColorTexVort, i.uv, 0).rgb;
#else
    float3 c = SampleGammaColor(i.uv);
#endif

#if !IS_SRGB
    float2 range = GetHDRRange();

    c = clamp(c, 0.0, range.y) / range.y;
#endif

    o.x = dot(c, float3(0.299, 0.587, 0.114));
    o.y = GetDepth(i.uv);
}

void PS_Motion6(PS_ARGS2) { o = EstimateMotion(i, 6, sMotionTexVortB); } // samp doesn't matter here
void PS_Motion5(PS_ARGS2) { o = EstimateMotion(i, 5, sMotionTexVortB); }
void PS_Motion4(PS_ARGS2) { o = EstimateMotion(i, 4, sMotionTexVortB); }
void PS_Motion3(PS_ARGS2) { o = EstimateMotion(i, 3, sMotionTexVortB); }
void PS_Motion2(PS_ARGS2) { o = EstimateMotion(i, 2, sMotionTexVortB); }
void PS_Motion1(PS_ARGS2) { o = EstimateMotion(i, 1, sMotionTexVort2); }
void PS_Motion0(PS_ARGS2) { o = EstimateMotion(i, 0, sMotionTexVort1); }

void PS_Filter5(PS_ARGS2) { o = AtrousUpscale(i, 5, sMotionTexVortA); }
void PS_Filter4(PS_ARGS2) { o = AtrousUpscale(i, 4, sMotionTexVortA); }
void PS_Filter3(PS_ARGS2) { o = AtrousUpscale(i, 3, sMotionTexVortA); }
void PS_Filter2(PS_ARGS2) { o = AtrousUpscale(i, 2, sMotionTexVortA); }

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MV \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::CurrFeatTexVort; } \
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
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion0;      RenderTarget = MV_TEX; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::PrevFeatTexVort; }

} // namespace end
