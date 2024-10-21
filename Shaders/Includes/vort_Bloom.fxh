/*******************************************************************************
    Author: Vortigern

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

// base idea from https://www.froyok.fr/blog/2021-12-ue4-custom-bloom/

#pragma once
#include "Includes/vort_Defs.fxh"
#include "Includes/vort_HDR_UI.fxh"
#include "Includes/vort_Filters.fxh"
#include "Includes/vort_DownTex.fxh"
#include "Includes/vort_HDRTexA.fxh"
#include "Includes/vort_HDRTexB.fxh"

namespace Bloom {

/*******************************************************************************
    Globals
*******************************************************************************/

#define BLOOM_IN_TEX HDRTexVortA
#define BLOOM_IN_SAMP sHDRTexVortA
#define BLOOM_OUT_TEX HDRTexVortB

/*******************************************************************************
    Functions
*******************************************************************************/

float4 Downsample(VSOUT i, sampler prev_samp, int prev_mip)
{
    float3 c = Filters::DualKawase(prev_samp, i.uv, prev_mip).rgb;

    return float4(c, 1);
}

float4 Upsample(VSOUT i, sampler prev_samp, int curr_mip)
{
    float3 c = Filters::Tent(prev_samp, i.uv, curr_mip + 1).rgb;

    return float4(c * UI_Bloom_Radius, 1);
}

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Debug(PS_ARGS4)
{
    static const int off = 20;
    static const int2 f = int2(BUFFER_SCREEN_SIZE.x * 0.2, BUFFER_SCREEN_SIZE.y * 0.5);
    float2 vpos = i.vpos.xy;
    float3 max_c = GetHDRRange().y;
    float3 c = 0.0;

    float3 colors[4] = {
        float3(max_c.r, 0, 0),
        float3(0, max_c.g, 0),
        float3(0, 0, max_c.b),
        max_c
    };

    bool is_square = false;

    for(int j = 0; j < 4; j++)
    {
        int2 fs = int2(f.x * (j + 1), f.y);
        is_square = all(int2(vpos >= (fs - off) && vpos <= fs));

        if(is_square) { c = colors[j]; break; }
    }

    if(!is_square) discard;

    o = float4(c, 1);
}

void PS_Down0(PS_ARGS4) { o = Downsample(i, BLOOM_IN_SAMP, 0); }
void PS_Down1(PS_ARGS4) { o = Downsample(i, sDownTexVort1, 1); }
void PS_Down2(PS_ARGS4) { o = Downsample(i, sDownTexVort2, 2); }
void PS_Down3(PS_ARGS4) { o = Downsample(i, sDownTexVort3, 3); }
void PS_Down4(PS_ARGS4) { o = Downsample(i, sDownTexVort4, 4); }
void PS_Down5(PS_ARGS4) { o = Downsample(i, sDownTexVort5, 5); }
void PS_Down6(PS_ARGS4) { o = Downsample(i, sDownTexVort6, 6); }
void PS_Down7(PS_ARGS4) { o = Downsample(i, sDownTexVort7, 7); }
void PS_Down8(PS_ARGS4) { o = Downsample(i, sDownTexVort8, 8); }

#if BUFFER_HEIGHT >= 2160
    void PS_Up8(PS_ARGS4) { o = Upsample(i, sDownTexVort9, 8); }
    void PS_Up7(PS_ARGS4) { o = Upsample(i, sDownTexVort8, 7); }
#else
    void PS_Up7(PS_ARGS4) { o = Upsample(i, sDownTexVort8, 7); }
#endif

void PS_Up6(PS_ARGS4) { o = Upsample(i, sDownTexVort7, 6); }
void PS_Up5(PS_ARGS4) { o = Upsample(i, sDownTexVort6, 5); }
void PS_Up4(PS_ARGS4) { o = Upsample(i, sDownTexVort5, 4); }
void PS_Up3(PS_ARGS4) { o = Upsample(i, sDownTexVort4, 3); }
void PS_Up2(PS_ARGS4) { o = Upsample(i, sDownTexVort3, 2); }
void PS_Up1(PS_ARGS4) { o = Upsample(i, sDownTexVort2, 1); }

void PS_Up0(PS_ARGS4)
{
    float3 src = Sample(BLOOM_IN_SAMP, i.uv).rgb;
    float3 bloom = src + Upsample(i, sDownTexVort1, 0).rgb;

    o = float4(lerp(src, bloom, UI_Bloom_Intensity), 1.0);
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define BLOOM_BLEND BlendEnable = true; BlendOp = ADD; SrcBlend = ONE; DestBlend = ONE;

#define PASS_BLOOM_DEBUG \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Debug; RenderTarget = BLOOM_IN_TEX; }

#if BUFFER_HEIGHT >= 2160
    #define PASS_BLOOM_DEFAULT \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down7; RenderTarget = DownTexVort8; } \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down8; RenderTarget = DownTexVort9; } \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up8;   RenderTarget = DownTexVort8; BLOOM_BLEND } \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up7;   RenderTarget = DownTexVort7; BLOOM_BLEND }
#else
    #define PASS_BLOOM_DEFAULT \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down7; RenderTarget = DownTexVort8; } \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up7; RenderTarget = DownTexVort7; BLOOM_BLEND }
#endif

#define PASS_BLOOM \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down0; RenderTarget = DownTexVort1; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down1; RenderTarget = DownTexVort2; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down2; RenderTarget = DownTexVort3; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down3; RenderTarget = DownTexVort4; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down4; RenderTarget = DownTexVort5; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down5; RenderTarget = DownTexVort6; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down6; RenderTarget = DownTexVort7; } \
    PASS_BLOOM_DEFAULT \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up6; RenderTarget = DownTexVort6; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up5; RenderTarget = DownTexVort5; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up4; RenderTarget = DownTexVort4; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up3; RenderTarget = DownTexVort3; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up2; RenderTarget = DownTexVort2; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up1; RenderTarget = DownTexVort1; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up0; RenderTarget = BLOOM_OUT_TEX; }

} // namespace end
