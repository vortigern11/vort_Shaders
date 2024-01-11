/*******************************************************************************
    Author: Vortigern
    Sources:
    https://www.shadertoy.com/view/DsfGWX
    https://alextardif.com/TAA.html
    https://www.elopezr.com/temporal-aa-and-the-quest-for-the-holy-trail/
    and various other places

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
#include "Includes/vort_LDRTex.fxh"
#include "Includes/vort_Motion_UI.fxh"
#include "Includes/vort_Depth.fxh"

namespace TAA {

/*******************************************************************************
    Globals
*******************************************************************************/

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture CurrColorTexVort { TEX_SIZE(0) TEX_RGBA16 };
sampler sCurrColorTexVort { Texture = CurrColorTexVort; };

texture PrevColorTexVort { TEX_SIZE(0) TEX_RGBA8 };
sampler sPrevColorTexVort { Texture = PrevColorTexVort; SRGB_READ_ENABLE };

/*******************************************************************************
    Functions
*******************************************************************************/

float4 GetUVJitter()
{
    /* static const float2 offs[4] = { */
    /*     float2(-0.5, -0.25), float2(-0.25, 0.5), float2(0.5, 0.25), float2(0.25, -0.5) */
    /* }; */

    float4 jitter = 0;

    if(frame_count > 0)
    {
        // doesn't move the image if only history is sampled, but maybe that isn't needed?
        /* jitter = float4(offs[frame_count % 4], offs[(frame_count - 1) % 4]); */

        jitter = float4(Halton2(frame_count % 16 + 1), Halton2((frame_count - 1) % 16 + 1)) * 2.0 - 1.0;
        jitter = float4(jitter.xy * BUFFER_PIXEL_SIZE, jitter.zw * BUFFER_PIXEL_SIZE);
    }

    return jitter * UI_TAA_Jitter;
}

float3 ClipToAABB(float3 old_c, float3 new_c, float3 avg, float3 sigma)
{
    float3 r = old_c - new_c;
    float3 m = (avg + sigma) - new_c;
    float3 n = (avg - sigma) - new_c;
    static const float eps = 1e-4;

    if (r.x > m.x + eps) r *= (m.x / r.x);
    if (r.y > m.y + eps) r *= (m.y / r.y);
    if (r.z > m.z + eps) r *= (m.z / r.z);

    if (r.x < n.x - eps) r *= (n.x / r.x);
    if (r.y < n.y - eps) r *= (n.y / r.y);
    if (r.z < n.z - eps) r *= (n.z / r.z);

    return new_c + r;
}

float MitchellFilter(float x)
{
    static const float b = A_THIRD;

    float y = 0.0;
    float x2 = x * x;
    float x3 = x * x * x;

    if(x < 1.0)
    {
        y = (12.0 - 9.0 * b - 6.0 * b) * x3 +
            (-18.0 + 12.0 * b + 6.0 * b) * x2 +
            (6.0 - 2.0 * b);
    }
    else if(x <= 2.0)
    {
        y = (-b - 6.0 * b) * x3 +
            (6.0 * b + 30.0 * b) * x2 +
            (-12.0 * b - 48.0 * b) * x +
            (8.0 * b + 24.0 * b);
    }

    return y / 6.0;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Main(PS_ARGS3)
{
    // .xy is curr offset, .zw is prev offset
    float4 jitter = GetUVJitter();
    float2 new_uv = saturate(i.uv + jitter.xy);

    float4 curr_info = Sample(sCurrColorTexVort, new_uv);
    float3 curr_c = curr_info.rgb;
    float curr_z = curr_info.a;

    // use mitchell filter on the center color
    static const float init_w = MitchellFilter(0);

    float4 sum_c = float4(curr_c * init_w, init_w);
    float3 avg_c = curr_c;
    float3 var_c = curr_c * curr_c;
    float3 closest = float3(0, 0, curr_z);

    static const float inv_samples = 1.0 / 9.0;
    static const float2 offs[8] = {
        float2(-1,  1), float2(0,  1), float2(1,  1),
        float2(-1,  0),                float2(1,  0),
        float2(-1, -1), float2(0, -1), float2(1, -1)
    };

    [loop]for(int j = 0; j < 8; j++)
    {
        float2 uv_offs = offs[j] * BUFFER_PIXEL_SIZE;
        float2 sample_uv = saturate(new_uv + uv_offs);
        float4 sample_info = Sample(sCurrColorTexVort, sample_uv);
        float3 sample_c = sample_info.rgb;
        float sample_z = sample_info.z;
        float sample_w = MitchellFilter(length(offs[j]));

        sum_c += float4(sample_c * sample_w, sample_w);

        avg_c += sample_c;
        var_c += sample_c * sample_c;

        if(sample_z < closest.z) closest = float3(uv_offs, sample_z);
    }

    // motion is sampled without the jitter
    float2 prev_offset = jitter.zw - jitter.xy;
    float2 motion = SampleMotion(i.uv + prev_offset + closest.xy).xy;
    float2 prev_uv = new_uv + motion.xy;

    bool is_first = Sample(sPrevColorTexVort, new_uv).a < 1.0;
    bool is_outside_screen = !all(saturate(prev_uv - prev_uv * prev_uv));

    // no prev color yet or motion leads to outside of screen coords
    if(is_first || is_outside_screen) discard;

    // try to reduce judder
    curr_c = sum_c.rgb * RCP(sum_c.w);

    float3 prev_c = SampleBicubic(sPrevColorTexVort, prev_uv).rgb;

    prev_c = RGBToYCoCg(ApplyLinearCurve(prev_c));

    avg_c *= inv_samples;
    var_c *= inv_samples;

    float3 sigma = sqrt(abs(var_c - avg_c * avg_c));
    float3 min_c = avg_c - sigma;
    float3 max_c = avg_c + sigma;

    prev_c = ClipToAABB(prev_c, clamp(avg_c, min_c, max_c), avg_c, sigma);

    curr_c = lerp(prev_c, curr_c, UI_TAA_Alpha);

    curr_c = ApplyGammaCurve(YCoCgToRGB(curr_c));

    o = curr_c;
}

void PS_WriteCurrColor(PS_ARGS4)
{
    float3 c = Sample(sLDRTexVort, i.uv).rgb;

    c = RGBToYCoCg(ApplyLinearCurve(c));

    o = float4(c, GetLinearizedDepth(i.uv));
}

void PS_WritePrevColor(PS_ARGS4)
{
    float3 c = Sample(sLDRTexVort, i.uv).rgb;

    o = float4(c, 1.0);
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define PASS_TAA \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_WriteCurrColor; RenderTarget = TAA::CurrColorTexVort; } \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_Main; SRGB_WRITE_ENABLE } \
    pass { VertexShader = PostProcessVS; PixelShader = TAA::PS_WritePrevColor; RenderTarget = TAA::PrevColorTexVort; SRGB_WRITE_ENABLE }

} // namespace end
