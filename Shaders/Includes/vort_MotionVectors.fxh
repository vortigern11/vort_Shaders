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
#include "Includes/vort_Filters.fxh"
#include "Includes/vort_Depth.fxh"
#include "Includes/vort_DownTex.fxh"
#include "Includes/vort_MotVectTex.fxh"
#include "Includes/vort_LDRTex.fxh"

namespace MotVect {

/*******************************************************************************
    Globals
*******************************************************************************/

#define MAX_MIP 6
#define MIN_MIP 1

#define CAT_MOT_VECT "Motion Vectors"

UI_FLOAT(
    CAT_MOT_VECT, UI_MV_WZMult, "Depth Weight",
    "Enable Debug View and start rotating the camera\n"
    "Increase this value if your character/weapon is being covered by color",
    0.0, 10.0, 2.0
)
UI_FLOAT(
    CAT_MOT_VECT, UI_MV_WMMult, "Long Motion Weight",
    "Enable Debug View and start rotating the camera\n"
    "The more you increase this value, the less moving objects blend with surroundings.",
    0.0, 10.0, 2.0
)

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D CurrFeatureTexVort { TEX_SIZE(MIN_MIP) TEX_RG16 MipLevels = 1 + MAX_MIP - MIN_MIP; };
texture2D PrevFeatureTexVort { TEX_SIZE(MIN_MIP) TEX_RG16 MipLevels = 1 + MAX_MIP - MIN_MIP; };

sampler2D sCurrFeatureTexVort { Texture = CurrFeatureTexVort; };
sampler2D sPrevFeatureTexVort { Texture = PrevFeatureTexVort; };

/*******************************************************************************
    Functions
*******************************************************************************/

float4 CalcLayer(VSOUT i, float4 coarse_layer, int mip)
{
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(mip);
    float2 local_block[16]; // just use max size possible
    uint feature_mip = max(0, mip - MIN_MIP);
    uint blocksize = mip > 1 ? 4 : 2;
    uint blockarea = blocksize * blocksize;

    float2 total_motion = coarse_layer.xy;

    float2 moments_local = 0;
    float2 moments_search = 0;
    float2 moments_cov = 0;
    float2 best_motion = 0;

    //since we only use to sample the blocks now, offset by half a block so we can do it easier inline
    i.uv -= texelsize * (blocksize / 2);

    [unroll]for(uint k = 0; k < blockarea; k++)
    {
        float2 tuv = i.uv + float2(k / blocksize, k % blocksize) * texelsize;
        float2 t_local = Sample(sCurrFeatureTexVort, saturate(tuv), feature_mip).xy;
        float2 t_search = Sample(sPrevFeatureTexVort, saturate(tuv + total_motion), feature_mip).xy;

        local_block[k] = t_local;

        moments_local += t_local * t_local;
        moments_search += t_search * t_search;
        moments_cov += t_local * t_search;
    }

    float2 cossim = moments_cov * RSQRT(moments_local * moments_search);
    float best_sim = saturate(min(cossim.x, cossim.y));
    float rand = frac(GetNoise(i.uv) + (mip + MIN_MIP) * GOLDEN_RATIO) * DOUBLE_PI;

    //modifies randdir.x and randdir.y in-place
    float2 randdir; sincos(rand, randdir.x, randdir.y);

    float exit = 1 - 1e-3;

    [loop]for(uint searches = (mip > 1 ? 4 : 2); searches > 0 && best_sim < exit; searches--)
    {
        [loop]for(uint samples = 4; samples > 0 && best_sim < exit; samples--)
        {
            randdir = mul(randdir, float2x2(-0.7373688, 0.6754903, -0.6754903, -0.7373688));

            float2 search_offset = randdir * texelsize;
            float2 search_center = i.uv + total_motion + search_offset;

            moments_search = 0;
            moments_cov = 0;

            [loop]for(uint k = 0; k < blockarea; k++)
            {
                float2 tuv = search_center + float2(k / blocksize, k % blocksize) * texelsize;
                float2 t = Sample(sPrevFeatureTexVort, saturate(tuv), feature_mip).xy;

                moments_search += t * t;
                moments_cov += t * local_block[k];
            }

            cossim = moments_cov * RSQRT(moments_local * moments_search);
            float sim = saturate(min(cossim.x, cossim.y));

            if(sim > best_sim)
            {
                best_sim = sim;
                best_motion = search_offset;
            }
        }

        total_motion += best_motion;
        randdir *= 0.5;
        best_motion = 0;
    }

    moments_local /= blockarea;

    return float4(total_motion, dot(sqrt(abs(moments_local - (moments_local / blockarea))), 1), saturate(1 - acos(best_sim) / HALF_PI));
}

float4 AtrousUpscale(VSOUT i, sampler mot_samp, int mip)
{
    float2 texelsize = RCP(tex2Dsize(mot_samp));
    float rand = frac(GetNoise(i.uv) + (mip + MIN_MIP) * GOLDEN_RATIO) * HALF_PI;
    float2x2 rotm = float2x2(cos(rand), -sin(rand), sin(rand), cos(rand)) * 3.0;
    static const float4 gauss = float4(1, 0.85, 0.65, 0.45);
    uint feature_mip = max(0, mip - MIN_MIP + 1);
    float center_z = Sample(sCurrFeatureTexVort, i.uv, feature_mip).y;
    float4 gbuffer_sum = 0;
    float wsum = 1e-3;
    int rad = floor((mip + 2) * 0.5);

    [loop]for(int x = -rad; x <= rad; x++)
    [loop]for(int y = -rad; y <= rad; y++)
    {
        float2 sample_uv = i.uv + mul(float2(x, y), rotm) * texelsize;
        float4 sample_gbuf = Sample(mot_samp, sample_uv);
        float sample_z = Sample(sCurrFeatureTexVort, sample_uv, feature_mip).y;

        float wz = saturate(abs(sample_z - center_z) * 4 * max(1, 32 * UI_MV_WZMult));
        float wm = saturate(dot(sample_gbuf.xy, sample_gbuf.xy) * 4 * max(1, 100 * UI_MV_WMMult));
        float wf = saturate(1.0 - sample_gbuf.z * 128.0);
        float ws = saturate((1.0 - sample_gbuf.w) * 5.0);
        float weight = exp2(-(wz + wm + wf + ws) * 4) * gauss[abs(x)] * gauss[abs(y)];

        // no need to use saturate in Sample, because we do it here
        weight *= all(saturate(sample_uv - sample_uv * sample_uv));
        gbuffer_sum += sample_gbuf * weight;
        wsum += weight;
    }

    return gbuffer_sum / wsum;
}

float4 EstimateMotion(in VSOUT i, sampler mot_samp, int mip)
{
    float4 layer = 0;

    if(mip == MAX_MIP)
        layer = Sample(mot_samp, i.uv);
    else
        layer = AtrousUpscale(i, mot_samp, mip);

    if(mip >= MIN_MIP)
        return CalcLayer(i, layer, mip);
    else
        return layer;
}

float3 Debug(float2 uv, float modifier)
{
    float2 motion = Sample(sMotVectTexVort, uv).xy * modifier;
    float angle = atan2(motion.y, motion.x);
    float3 rgb = saturate(3 * abs(2 * frac(angle / DOUBLE_PI + float3(0, -1.0/3.0, 1.0/3.0)) - 1) - 1);

    return lerp(0.5, rgb, saturate(length(motion) * 100));
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_WriteFeature(PS_ARGS2)
{
    float3 color = Filter8Taps(i.uv, sLDRTexVort, MIN_MIP);

    o.x = RGBToYCoCgLumi(color);
    o.y = GetLinearizedDepth(i.uv);
}

void PS_Motion6(PS_ARGS4) { o = EstimateMotion(i, sMotVectTexVort, 6); }
void PS_Motion5(PS_ARGS4) { o = EstimateMotion(i, sDownTexVort6, 5); }
void PS_Motion4(PS_ARGS4) { o = EstimateMotion(i, sDownTexVort5, 4); }
void PS_Motion3(PS_ARGS4) { o = EstimateMotion(i, sDownTexVort4, 3); }
void PS_Motion2(PS_ARGS4) { o = EstimateMotion(i, sDownTexVort3, 2); }
void PS_Motion1(PS_ARGS4) { o = EstimateMotion(i, sDownTexVort2, 1); }
void PS_Motion0(PS_ARGS4) { o = EstimateMotion(i, sDownTexVort1, 0); }

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MOT_VECT \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::CurrFeatureTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion6; RenderTarget = DownTexVort6; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion5; RenderTarget = DownTexVort5; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion4; RenderTarget = DownTexVort4; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion3; RenderTarget = DownTexVort3; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion2; RenderTarget = DownTexVort2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion1; RenderTarget = DownTexVort1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion0; RenderTarget = MotVectTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::PrevFeatureTexVort; }

} // namespace end
