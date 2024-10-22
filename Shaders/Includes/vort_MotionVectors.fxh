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
#include "Includes/vort_MotionUtils.fxh"

namespace MotVect {

/*******************************************************************************
    Globals
*******************************************************************************/

#define MAX_MIP 8
#define MIN_MIP 1

static const uint BLOCK_SAMPLES = 9;
static const float INV_BLOCK_SAMPLES = 1.0 / float(BLOCK_SAMPLES);
static const float2 BLOCK_OFFS[BLOCK_SAMPLES] =
{
    float2(0, 0),
    float2(-1, -1), float2(1, 1), float2(-1, 1), float2(1, -1),
    float2(0, -2), float2(0, 2), float2(-2, 0), float2(2, 0)
};

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D FeatTexVort { TEX_SIZE(MIN_MIP) TEX_RGBA16 MipLevels = 1 + MAX_MIP - MIN_MIP; };
sampler2D sFeatTexVort { Texture = FeatTexVort; };

texture2D MotionTexVort1 { TEX_SIZE(1) TEX_RG16 };
texture2D MotionTexVort2 { TEX_SIZE(2) TEX_RG16 };
texture2D MotionTexVortA { TEX_SIZE(3) TEX_RG16 };
texture2D MotionTexVortB { TEX_SIZE(3) TEX_RG16 };

// DON'T FUCKING USE POINT SAMPLERS HERE
// only combining frames looks correct, frame by frame it doesn't
sampler2D sMotionTexVort1 { Texture = MotionTexVort1; };
sampler2D sMotionTexVort2 { Texture = MotionTexVort2; };
sampler2D sMotionTexVortA { Texture = MotionTexVortA; };
sampler2D sMotionTexVortB { Texture = MotionTexVortB; };

/*******************************************************************************
    Functions
*******************************************************************************/

float GetGrayscale(float3 c)
{
#if !IS_SRGB
    float2 range = GetHDRRange();

    c = clamp(c, 0.0, range.y) / range.y;
#endif

    return dot(c, A_THIRD);
}

float2 CalcLayer(VSOUT i, int mip, float2 total_motion)
{
    // one mip lower on purpose for better results
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(max(0, mip - 1));
    uint feature_mip = max(0, mip - MIN_MIP);
    float diff_acc = 0; // sum of abs diffs

    [loop]for(uint j = 0; j < BLOCK_SAMPLES; j++)
    {
        float2 tuv = i.uv + BLOCK_OFFS[j] * texelsize;
        float2 t_local = Sample(sFeatTexVort, tuv, feature_mip).xy;
        float2 t_search = Sample(sFeatTexVort, tuv + total_motion, feature_mip).zw;
        float2 t_diff = abs(t_local - t_search);

        diff_acc += max(t_diff.x, t_diff.y);
    }

    diff_acc *= INV_BLOCK_SAMPLES;

    float best_diff = diff_acc;
    float qrand = GetR1(GetBlueNoise(i.vpos.xy).x, mip);
    float2 randdir = Rotate(float2(0, 1), GetRotator(HALF_PI * qrand));
    int searches = mip > 3 ? 4 : 2;

    static const float eps = 1e-6;

    [loop]while(searches-- > 0 && best_diff > eps)
    {
        float2 local_motion = 0;
        int samples = 4; // 360deg / 90deg = 4

        [loop]while(samples-- > 0 && best_diff > eps)
        {
            randdir = float2(randdir.y, -randdir.x); //rotate by 90 degrees
            diff_acc = 0;

            float2 search_offset = randdir * texelsize;

            [loop]for(uint j = 0; j < BLOCK_SAMPLES; j++)
            {
                float2 tuv = i.uv + BLOCK_OFFS[j] * texelsize;
                float2 t_local = Sample(sFeatTexVort, tuv, feature_mip).xy;
                float2 t_search = Sample(sFeatTexVort, tuv + total_motion + search_offset, feature_mip).zw;
                float2 t_diff = abs(t_local - t_search);

                diff_acc += max(t_diff.x, t_diff.y);
            }

            diff_acc *= INV_BLOCK_SAMPLES;

            if(diff_acc < best_diff)
            {
                best_diff = diff_acc;
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
    float2 scale = texelsize * (mip > 0 ? UI_MV_Scale : 1.0);
    float2 qrand = GetR2(GetBlueNoise(i.vpos.xy).xy, mip + 1) - 0.5;
    float2 cen_motion = Sample(mot_samp, i.uv).xy;
    float cen_sq_len = dot(cen_motion, cen_motion);
    float center_z = Sample(sFeatTexVort, i.uv, feature_mip).y;

    if(mip < MIN_MIP) center_z = GetDepth(i.uv);

    float3 motion_acc = 0;

    [loop]for(uint j = 0; j < BLOCK_SAMPLES; j++)
    {
        float2 sample_uv = i.uv + (BLOCK_OFFS[j] + qrand) * scale;
        float2 sample_mot = Sample(mot_samp, sample_uv).xy;
        float sample_z = Sample(sFeatTexVort, sample_uv, feature_mip).y;
        float sample_sq_len = dot(sample_mot, sample_mot);
        float cos_angle = dot(cen_motion, sample_mot) * RSQRT(cen_sq_len * sample_sq_len);

        float wz = abs(center_z - sample_z) * RCP(min(center_z, sample_z)) * 20.0;
        float wm = sample_sq_len * BUFFER_WIDTH * 0.75; // needed when MAX_MIP > 6
        float wd = saturate(0.5 * (0.5 + cos_angle)) * 2.0; // tested - opposite gives better results
        float weight = exp2(-(wz + wm + wd));

        // don't use samples without motion or outside screen
        weight *= (sample_sq_len > 0.0) * ValidateUV(sample_uv);
        motion_acc += float3(sample_mot, 1.0) * weight;
    }

    return motion_acc.xy * RCP(motion_acc.z);
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

void PS_WriteFeature(PS_ARGS4)
{
#if MIN_MIP > 0
    float3 c = Filters::Wronski(sGammaColorTexVort, i.uv, 0).rgb;
#else
    float3 c = SampleGammaColor(i.uv);
#endif

    o = float2(GetGrayscale(c), GetDepth(i.uv)).xyxy;
}

void PS_Motion8(PS_ARGS2) { o = EstimateMotion(i, 8, sMotionTexVortB); } // samp doesn't matter here
void PS_Motion7(PS_ARGS2) { o = EstimateMotion(i, 7, sMotionTexVortA); }
void PS_Motion6(PS_ARGS2) { o = EstimateMotion(i, 6, sMotionTexVortB); }
void PS_Motion5(PS_ARGS2) { o = EstimateMotion(i, 5, sMotionTexVortA); }
void PS_Motion4(PS_ARGS2) { o = EstimateMotion(i, 4, sMotionTexVortB); }
void PS_Motion3(PS_ARGS2) { o = EstimateMotion(i, 3, sMotionTexVortA); }
void PS_Motion2(PS_ARGS2) { o = EstimateMotion(i, 2, sMotionTexVortB); }
void PS_Motion1(PS_ARGS2) { o = EstimateMotion(i, 1, sMotionTexVort2); }
void PS_Motion0(PS_ARGS2) { o = EstimateMotion(i, 0, sMotionTexVort1); }

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MV \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::FeatTexVort; RenderTargetWriteMask = 3; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion8;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion7;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion6;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion5;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion4;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion3;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion2;      RenderTarget = MotVect::MotionTexVort2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion1;      RenderTarget = MotVect::MotionTexVort1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion0;      RenderTarget = MotVectTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::FeatTexVort; RenderTargetWriteMask = 12; }

} // namespace end
