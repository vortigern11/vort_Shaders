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
#include "Includes/vort_BlueNoise.fxh"
#include "Includes/vort_Motion_UI.fxh"

namespace MotVect {

/*******************************************************************************
    Globals
*******************************************************************************/

#define MAX_MIP 6

#if BUFFER_HEIGHT >= 2160
    #define MIN_MIP 2
    #define WORK_MIP 4
#else
    #define MIN_MIP 1
    #define WORK_MIP 3
#endif

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

// linear color gives worse results, hence:
texture2D ColorTexVort : COLOR;
sampler2D sColorTexVort { Texture = ColorTexVort; };

// .x = curr lumi .y = prev lumi
texture2D FeatureTexVort    { TEX_SIZE(MIN_MIP) TEX_RG8 MipLevels = 1 + MAX_MIP - MIN_MIP; };
sampler2D sFeatureTexVort   { Texture = FeatureTexVort; };

// .x = curr depth .y = prev depth
texture2D DownDepthTexVort  { TEX_SIZE(WORK_MIP) TEX_RG16 };
sampler2D sDownDepthTexVort { Texture = DownDepthTexVort; SAM_POINT };

texture2D MotionTexVortA    { TEX_SIZE(WORK_MIP) TEX_RGBA16 };
sampler2D sMotionTexVortA   { Texture = MotionTexVortA; SAM_POINT };

texture2D MotionTexVortB    { TEX_SIZE(WORK_MIP) TEX_RGBA16 };
sampler2D sMotionTexVortB   { Texture = MotionTexVortB; SAM_POINT };

/*******************************************************************************
    Functions
*******************************************************************************/

float4 CalcLayer(VSOUT i, int mip, float2 total_motion)
{
    mip = max(mip - 1, MIN_MIP); // better quality

    uint feature_mip = max(0, mip - MIN_MIP);
    float2 texelsize = rcp(tex2Dsize(sFeatureTexVort, feature_mip));

    static const int block_area = 9;
    static const float inv_block_area = 1.0 / float(block_area);
    static const float2 block_offs[9] =
    {
        float2(0,  0),
        float2(0, -1), float2(0, 1), float2(-1, 0), float2(1, 0),
        float2(0, -2), float2(0, 2), float2(-2, 0), float2(2, 0)
    };

    float2 moments_local = 0;
    float2 moments_search = 0;
    float moments_cov = 0;

    [loop]for(uint k = 0; k < block_area; k++)
    {
        float2 tuv = i.uv + block_offs[k] * texelsize;
        float t_local = Sample(sFeatureTexVort, saturate(tuv), feature_mip).x;
        float t_search = Sample(sFeatureTexVort, saturate(tuv + total_motion), feature_mip).y;

        moments_local += float2(t_local, t_local * t_local);
        moments_search += float2(t_search, t_search * t_search);
        moments_cov += t_local * t_search;
    }

    moments_local *= inv_block_area;
    moments_search *= inv_block_area;
    moments_cov *= inv_block_area;

    float local_variance = abs(moments_local.y - moments_local.x * moments_local.x);
    float search_variance = abs(moments_search.y - moments_search.x * moments_search.x);
    float cov_variance = moments_cov - moments_local.x * moments_search.x;
    float best_sim = cov_variance * RSQRT(local_variance * search_variance);

    if(local_variance < exp(-16.0) || best_sim > 0.999999)
        return float4(total_motion, 0, 0);

    float randseed = GetR1(GetBlueNoise(i.vpos.xy).x, mip);
    float2 randdir; sincos(randseed * HALF_PI, randdir.x, randdir.y);
    int searches = mip > 3 ? 4 : 2;

    while(searches-- > 0)
    {
        float2 local_motion = 0;
        int samples = 4;

        while(samples-- > 0)
        {
            //rotate by 90 degrees
            randdir = float2(randdir.y, -randdir.x);

            float2 search_offset = randdir * texelsize;

            moments_search = 0;
            moments_cov = 0;

            [loop]for(uint k = 0; k < block_area; k++)
            {
                float2 tuv = i.uv + block_offs[k] * texelsize;
                float t_local = Sample(sFeatureTexVort, saturate(tuv), feature_mip).x;
                float t_search = Sample(sFeatureTexVort, saturate(tuv + total_motion + search_offset), feature_mip).y;

                moments_search += float2(t_search, t_search * t_search);
                moments_cov += t_search * t_local;
            }

            moments_search *= inv_block_area;
            moments_cov *= inv_block_area;

            cov_variance = moments_cov - moments_local.x * moments_search.x;
            search_variance = abs(moments_search.y - moments_search.x * moments_search.x);

            float sim = cov_variance * RSQRT(local_variance * search_variance);

            if(sim > best_sim)
            {
                best_sim = sim;
                local_motion = search_offset;
            }
        }

        total_motion += local_motion;
        randdir *= 0.5;
    }

    float prev_z = Sample(sDownDepthTexVort, i.uv + total_motion).y;
    float similarity = 1.0 - sqrt(saturate(best_sim * 0.5 + 0.5));

    return float4(total_motion, prev_z, similarity);
}

float4 AtrousUpscale(VSOUT i, int mip, sampler mot_samp)
{
    if(mip > 0) mip = WORK_MIP;

    float2 texelsize = rcp(tex2Dsize(mot_samp)) * (mip > 0 ? 5.0 : 1.5);
    float2 blue_noise = GetBlueNoise(i.vpos.xy).xy;
    float center_z = 0;

    if (mip == 0)
        center_z = GetLinearizedDepth(i.uv);
    else
        center_z = Sample(sDownDepthTexVort, i.uv).x;

    float wsum = 0.001;
    float4 gbuffer = 0;

    [loop]for(int x = -2; x <= 1; x++)
    [loop]for(int y = -2; y <= 1; y++)
    {
        float2 sample_uv = i.uv + (float2(x, y) + blue_noise) * texelsize;
        float4 sample_gbuf = Sample(mot_samp, sample_uv);
        float sample_z_c = Sample(sDownDepthTexVort, sample_uv).x;
        float sample_z_p = sample_gbuf.z;

        // too costly to sample depth again at mip 0

        float wz_c = abs(center_z - sample_z_c) * RCP(max(center_z, sample_z_c)); wz_c *= wz_c * 100.0; // curr depth delta
        float wz_p = abs(center_z - sample_z_p) * RCP(max(center_z, sample_z_p)); wz_p *= wz_p; // prev depth delta
        float wm = dot(sample_gbuf.xy, sample_gbuf.xy) * 200.0; // long motion
        float ws = sample_gbuf.w; // similarity
        float weight = exp2(-(wz_c + wz_p + wm + ws) * 4.0) + 0.001;

        weight *= all(saturate(sample_uv - sample_uv * sample_uv));
        wsum += weight;
        gbuffer += sample_gbuf * weight;
    }

    return gbuffer / wsum;
}

float4 EstimateMotion(VSOUT i, int mip, sampler mot_samp)
{
    float4 motion = 0;

    if(mip < MAX_MIP)
        motion = AtrousUpscale(i, mip, mot_samp);

    if(mip >= MIN_MIP)
        motion = CalcLayer(i, mip, motion.xy);

    return motion;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_WriteFeature(PS_ARGS2) { o.xy = dot(float3(0.299, 0.587, 0.114), Sample(sColorTexVort, i.uv).rgb); }
void PS_WriteDepth(PS_ARGS2) { o.xy = GetLinearizedDepth(i.uv); }

void PS_Motion6(PS_ARGS4) { o = EstimateMotion(i, 6, sMotionTexVortB); }
void PS_Motion5(PS_ARGS4) { o = EstimateMotion(i, 5, sMotionTexVortB); }
void PS_Motion4(PS_ARGS4) { o = EstimateMotion(i, 4, sMotionTexVortB); }
void PS_Motion3(PS_ARGS4) { o = EstimateMotion(i, 3, sMotionTexVortB); }
void PS_Motion2(PS_ARGS4) { o = EstimateMotion(i, 2, sMotionTexVortB); }
void PS_Motion1(PS_ARGS4) { o = EstimateMotion(i, 1, sMotionTexVortB); }
void PS_Motion0(PS_ARGS4) { o = EstimateMotion(i, 0, sMotionTexVortB); }

// yo dawg I heard you like filtering, so here is a filter on top of the filter :)
void PS_Filter6(PS_ARGS4) { o = AtrousUpscale(i, 6, sMotionTexVortA); }
void PS_Filter5(PS_ARGS4) { o = AtrousUpscale(i, 5, sMotionTexVortA); }
void PS_Filter4(PS_ARGS4) { o = AtrousUpscale(i, 4, sMotionTexVortA); }
void PS_Filter3(PS_ARGS4) { o = AtrousUpscale(i, 3, sMotionTexVortA); }
void PS_Filter2(PS_ARGS4) { o = AtrousUpscale(i, 2, sMotionTexVortA); }
void PS_Filter1(PS_ARGS4) { o = AtrousUpscale(i, 1, sMotionTexVortA); }

void PS_Debug(PS_ARGS3)
{
    float2 motion = Sample(MV_SAMP, i.uv).xy;
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
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::FeatureTexVort;   RenderTargetWriteMask = 1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteDepth;   RenderTarget = MotVect::DownDepthTexVort; RenderTargetWriteMask = 1; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion6;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter6;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion5;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter5;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion4;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter4;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion3;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter3;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion2;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter2;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion1;      RenderTarget = MotVect::MotionTexVortA; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Filter1;      RenderTarget = MotVect::MotionTexVortB; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_Motion0;      RenderTarget = MV_TEX; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteFeature; RenderTarget = MotVect::FeatureTexVort;   RenderTargetWriteMask = 2; } \
    pass { VertexShader = PostProcessVS; PixelShader = MotVect::PS_WriteDepth;   RenderTarget = MotVect::DownDepthTexVort; RenderTargetWriteMask = 2; }

} // namespace end
