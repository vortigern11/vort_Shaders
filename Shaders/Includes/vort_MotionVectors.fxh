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
#include "Includes/vort_MotVectTex.fxh"
#include "Includes/vort_LDRTex.fxh"
#include "Includes/vort_OKColors.fxh"

namespace MotVect {

/*******************************************************************************
    Globals
*******************************************************************************/

#ifndef V_MV_DEBUG
    #define V_MV_DEBUG 0
#endif

#ifndef V_MV_EXTRA_QUALITY
    #define V_MV_EXTRA_QUALITY 0
#endif

#define MAX_MIP 6

#if BUFFER_HEIGHT >= 2160
    #define MIN_MIP (2 - V_MV_EXTRA_QUALITY)
#else
    #define MIN_MIP (1 - V_MV_EXTRA_QUALITY)
#endif

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture2D CurrFeatureTexVort { TEX_SIZE(MIN_MIP) TEX_RG16 MipLevels = 1 + MAX_MIP - MIN_MIP; };
texture2D PrevFeatureTexVort { TEX_SIZE(MIN_MIP) TEX_RG16 MipLevels = 1 + MAX_MIP - MIN_MIP; };

sampler2D sCurrFeatureTexVort { Texture = CurrFeatureTexVort; };
sampler2D sPrevFeatureTexVort { Texture = PrevFeatureTexVort; };

// don't need all textures from vort_DownTex
texture2D DownTexVort1 { TEX_SIZE(1) TEX_RGBA16 };
texture2D DownTexVort2 { TEX_SIZE(2) TEX_RGBA16 };
texture2D DownTexVort3 { TEX_SIZE(3) TEX_RGBA16 };
texture2D DownTexVort4 { TEX_SIZE(4) TEX_RGBA16 };
texture2D DownTexVort5 { TEX_SIZE(5) TEX_RGBA16 };
texture2D DownTexVort6 { TEX_SIZE(6) TEX_RGBA16 };

sampler2D sDownTexVort1 { Texture = DownTexVort1; };
sampler2D sDownTexVort2 { Texture = DownTexVort2; };
sampler2D sDownTexVort3 { Texture = DownTexVort3; };
sampler2D sDownTexVort4 { Texture = DownTexVort4; };
sampler2D sDownTexVort5 { Texture = DownTexVort5; };
sampler2D sDownTexVort6 { Texture = DownTexVort6; };

/*******************************************************************************
    Functions
*******************************************************************************/

float2 Rotate2D(float2 v, float4 r) { return float2(dot(v, r.xy), dot(v, r.zw)); }

float4 CalcLayer(VSOUT i, int mip, float2 total_motion)
{
    uint feature_mip = max(0, mip - MIN_MIP);
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(mip);

    // reduced DX9 compile time and better performance
    uint block_size = mip > MIN_MIP ? 3 : 2;
    uint block_area = block_size * block_size;
    float2 local_block[9]; // just use max size possible

    float2 moments_local = 0;
    float2 moments_search = 0;
    float2 moments_cov = 0;

    //since we only use to sample the blocks now, offset by half a block so we can do it easier inline
    i.uv -= texelsize * (block_size * 0.5);

    [unroll]for(uint k = 0; k < block_area; k++)
    {
        float2 tuv = i.uv + float2(k % block_size, k / block_size) * texelsize;
        float2 t_local = Sample(sCurrFeatureTexVort, saturate(tuv), feature_mip).xy;
        float2 t_search = Sample(sPrevFeatureTexVort, saturate(tuv + total_motion), feature_mip).xy;

        local_block[k] = t_local;

        moments_local += t_local * t_local;
        moments_search += t_search * t_search;
        moments_cov += t_local * t_search;
    }

    float variance = dot(sqrt(abs(moments_local * (block_area - 1) * rcp(block_area * block_area))), 1);
    float2 cossim = moments_cov * RSQRT(moments_local * moments_search);
    float best_sim = saturate(min(cossim.x, cossim.y));
    static const float max_best_sim = 0.999999;

    if(variance < exp(-32.0) || best_sim > max_best_sim)
        return float4(total_motion, 0, 0);

    float randseed = frac(GetNoise(i.uv) + (mip + MIN_MIP) * INV_PHI);
    float2 randdir; sincos(randseed * HALF_PI, randdir.x, randdir.y); randdir *= 0.5;
    int searches = mip > MIN_MIP ? 4 : 2;

    [loop]while(searches-- > 0 && best_sim < max_best_sim)
    {
        float2 local_motion = 0;
        int samples = 4;

        [loop]while(samples-- > 0 && best_sim < max_best_sim)
        {
            //rotate by 90 degrees
            randdir = float2(randdir.y, -randdir.x);

            float2 search_offset = randdir * texelsize;
            float2 search_center = i.uv + total_motion + search_offset;

            moments_search = 0;
            moments_cov = 0;

            [loop]for(uint k = 0; k < block_area; k++)
            {
                float2 tuv = search_center + float2(k % block_size, k / block_size) * texelsize;
                float2 t = Sample(sPrevFeatureTexVort, saturate(tuv), feature_mip).xy;

                moments_search += t * t;
                moments_cov += t * local_block[k];
            }

            cossim = moments_cov * RSQRT(moments_local * moments_search);
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

    float similarity = saturate(1.0 - acos(best_sim) * PI);

    return float4(total_motion, variance, similarity);
}

float2 AtrousUpscale(VSOUT i, int mip, sampler mot_samp)
{
    uint feature_mip = max(0, mip - MIN_MIP);
    float2 texelsize = rcp(tex2Dsize(mot_samp));
    float randseed = frac(GetNoise(i.uv) + (mip + MIN_MIP) * INV_PHI);
    float2 rsc; sincos(randseed * HALF_PI, rsc.x, rsc.y);
    float4 rotator = float4(rsc.y, rsc.x, -rsc.x, rsc.y) * (mip + 2.0);
    float center_z = Sample(sCurrFeatureTexVort, i.uv, feature_mip).y;

    // xy = motion, z = weight
    float3 gbuffer = 0;
    int rad = mip > MIN_MIP ? 2 : 1;

    [loop]for(int x = -rad; x <= rad; x++)
    [loop]for(int y = -rad; y <= rad; y++)
    {
        float2 sample_uv = i.uv + Rotate2D(float2(x, y), rotator) * texelsize;
        float4 sample_gbuf = Sample(mot_samp, sample_uv);
        float sample_z = Sample(sCurrFeatureTexVort, sample_uv, feature_mip).y;

        float wz = abs(sample_z - center_z) * RCP(max(center_z, sample_z)) * 3.0; // depth delta
        float wm = dot(sample_gbuf.xy, sample_gbuf.xy) * 1250.0; // long motion
        float wf = saturate(1.0 - (sample_gbuf.z * 128.0)); // small variance
        float ws = saturate(1.0 - sample_gbuf.w); ws *= ws; // bad block matching
        float weight = exp2(-(wz + wm + wf + ws) * 4.0);

        weight *= all(saturate(sample_uv - sample_uv * sample_uv));
        gbuffer += float3(sample_gbuf.xy * weight, weight);
    }

    return gbuffer.xy * RCP(gbuffer.z);
}

float4 EstimateMotion(VSOUT i, int mip, sampler mot_samp)
{
    float2 motion = 0;

    if(mip < MAX_MIP)
        motion = AtrousUpscale(i, mip, mot_samp);

    if(mip >= MIN_MIP)
        return CalcLayer(i, mip, motion);
    else
        return float4(motion.xy, 0, 0);
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_WriteFeature(PS_ARGS2)
{
    float3 color = ApplyLinearCurve(Sample(sLDRTexVort, i.uv, MIN_MIP).rgb);

    o.x = OKColors::RGBToOKLAB(color).x;
    o.y = GetLinearizedDepth(i.uv);
}

void PS_Motion6(PS_ARGS4) { o = EstimateMotion(i, 6, sMotVectTexVort); }
void PS_Motion5(PS_ARGS4) { o = EstimateMotion(i, 5, sDownTexVort6); }
void PS_Motion4(PS_ARGS4) { o = EstimateMotion(i, 4, sDownTexVort5); }
void PS_Motion3(PS_ARGS4) { o = EstimateMotion(i, 3, sDownTexVort4); }
void PS_Motion2(PS_ARGS4) { o = EstimateMotion(i, 2, sDownTexVort3); }
void PS_Motion1(PS_ARGS4) { o = EstimateMotion(i, 1, sDownTexVort2); }
void PS_Motion0(PS_ARGS4) { o = EstimateMotion(i, 0, sDownTexVort1); }

void PS_Debug(PS_ARGS3)
{
    float2 motion = Sample(sMotVectTexVort, i.uv).xy;
    float angle = atan2(motion.y, motion.x);
    float3 rgb = saturate(3 * abs(2 * frac(angle / DOUBLE_PI + float3(0, -1.0/3.0, 1.0/3.0)) - 1) - 1);

    o = lerp(0.5, rgb, saturate(length(motion) * 100));
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_MV_DEBUG \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Debug; }

#define PASS_MV \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::CurrFeatureTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion6; RenderTarget = MotVect::DownTexVort6; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion5; RenderTarget = MotVect::DownTexVort5; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion4; RenderTarget = MotVect::DownTexVort4; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion3; RenderTarget = MotVect::DownTexVort3; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion2; RenderTarget = MotVect::DownTexVort2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion1; RenderTarget = MotVect::DownTexVort1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion0; RenderTarget = MotVectTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::PrevFeatureTexVort; }

} // namespace end
