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
#include "Includes/vort_ColorTex.fxh"
#include "Includes/vort_HDRTex.fxh"
#include "Includes/vort_Static_UI.fxh"
#include "Includes/vort_Filters.fxh"

namespace Bloom {

/*******************************************************************************
    Globals
*******************************************************************************/

texture2D BloomTex { TEX_SIZE(0) TEX_RGBA16 };
sampler2D sBloomTex { Texture = BloomTex; };

texture2D DownTex1 { TEX_SIZE(1) TEX_RGBA16 };
texture2D DownTex2 { TEX_SIZE(2) TEX_RGBA16 };
texture2D DownTex3 { TEX_SIZE(3) TEX_RGBA16 };
texture2D DownTex4 { TEX_SIZE(4) TEX_RGBA16 };
texture2D DownTex5 { TEX_SIZE(5) TEX_RGBA16 };
texture2D DownTex6 { TEX_SIZE(6) TEX_RGBA16 };
texture2D DownTex7 { TEX_SIZE(7) TEX_RGBA16 };
texture2D DownTex8 { TEX_SIZE(8) TEX_RGBA16 };

sampler2D sDownTex1 { Texture = DownTex1; };
sampler2D sDownTex2 { Texture = DownTex2; };
sampler2D sDownTex3 { Texture = DownTex3; };
sampler2D sDownTex4 { Texture = DownTex4; };
sampler2D sDownTex5 { Texture = DownTex5; };
sampler2D sDownTex6 { Texture = DownTex6; };
sampler2D sDownTex7 { Texture = DownTex7; };
sampler2D sDownTex8 { Texture = DownTex8; };

#if BUFFER_HEIGHT >= 2160
    texture2D DownTex9 { TEX_SIZE(9) TEX_RGBA16 };
    sampler2D sDownTex9 { Texture = DownTex9; };
#endif

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
#if DEBUG_BLOOM
void PS_Debug(PS_ARGS4)
{
    static const int off = 20;
    static const int2 f = int2(BUFFER_SCREEN_SIZE.x * 0.2, BUFFER_SCREEN_SIZE.y * 0.5);
    float2 vpos = i.vpos.xy;
    float3 max_c = GetHDRRange().y * UI_Bloom_MaxC;
    float3 colors[4] = { float3(max_c.r, 0, 0), float3(0, max_c.g, 0), float3(0, 0, max_c.b), max_c };
    float3 c = 0;

    [loop]for(int j = 0; j < 4; j++)
    {
        int2 fs = int2(f.x * (j + 1), f.y);
        bool is_in_square = all(int2(vpos >= (fs - off) && vpos <= fs));

        if(is_in_square) { c = colors[j]; break; }
    }

    o = float4(c, 1);
}
#endif

void PS_Down0(PS_ARGS4) { o = Downsample(i, HDR::sColorTex, 0); }
void PS_Down1(PS_ARGS4) { o = Downsample(i, sDownTex1, 1); }
void PS_Down2(PS_ARGS4) { o = Downsample(i, sDownTex2, 2); }
void PS_Down3(PS_ARGS4) { o = Downsample(i, sDownTex3, 3); }
void PS_Down4(PS_ARGS4) { o = Downsample(i, sDownTex4, 4); }
void PS_Down5(PS_ARGS4) { o = Downsample(i, sDownTex5, 5); }
void PS_Down6(PS_ARGS4) { o = Downsample(i, sDownTex6, 6); }
void PS_Down7(PS_ARGS4) { o = Downsample(i, sDownTex7, 7); }
void PS_Down8(PS_ARGS4) { o = Downsample(i, sDownTex8, 8); }

#if BUFFER_HEIGHT >= 2160
    void PS_Up8(PS_ARGS4) { o = Upsample(i, sDownTex9, 8); }
    void PS_Up7(PS_ARGS4) { o = Upsample(i, sDownTex8, 7); }
#else
    void PS_Up7(PS_ARGS4) { o = Upsample(i, sDownTex8, 7); }
#endif

void PS_Up6(PS_ARGS4) { o = Upsample(i, sDownTex7, 6); }
void PS_Up5(PS_ARGS4) { o = Upsample(i, sDownTex6, 5); }
void PS_Up4(PS_ARGS4) { o = Upsample(i, sDownTex5, 4); }
void PS_Up3(PS_ARGS4) { o = Upsample(i, sDownTex4, 3); }
void PS_Up2(PS_ARGS4) { o = Upsample(i, sDownTex3, 2); }
void PS_Up1(PS_ARGS4) { o = Upsample(i, sDownTex2, 1); }

void PS_Up0(PS_ARGS4)
{
    float3 src = Sample(HDR::sColorTex, i.uv).rgb;
    float3 bloom = src + Upsample(i, sDownTex1, 0).rgb;

    o = float4(lerp(src, bloom, UI_Bloom_Intensity), 1.0);
}

/*******************************************************************************
    Passes
*******************************************************************************/

#define BLOOM_BLEND BlendEnable = true; BlendOp = ADD; SrcBlend = ONE; DestBlend = ONE;

#if DEBUG_BLOOM
    #define PASS_BLOOM_DEBUG \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Debug; RenderTarget = HDR::ColorTex; }
#endif

#if BUFFER_HEIGHT >= 2160
    #define PASS_BLOOM_DEFAULT \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down7; RenderTarget = Bloom::DownTex8; } \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down8; RenderTarget = Bloom::DownTex9; } \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up8;   RenderTarget = Bloom::DownTex8; BLOOM_BLEND } \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up7;   RenderTarget = Bloom::DownTex7; BLOOM_BLEND }
#else
    #define PASS_BLOOM_DEFAULT \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down7; RenderTarget = Bloom::DownTex8; } \
        pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up7; RenderTarget = Bloom::DownTex7; BLOOM_BLEND }
#endif

#define PASS_BLOOM \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down0; RenderTarget = Bloom::DownTex1; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down1; RenderTarget = Bloom::DownTex2; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down2; RenderTarget = Bloom::DownTex3; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down3; RenderTarget = Bloom::DownTex4; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down4; RenderTarget = Bloom::DownTex5; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down5; RenderTarget = Bloom::DownTex6; } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Down6; RenderTarget = Bloom::DownTex7; } \
    PASS_BLOOM_DEFAULT \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up6; RenderTarget = Bloom::DownTex6; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up5; RenderTarget = Bloom::DownTex5; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up4; RenderTarget = Bloom::DownTex4; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up3; RenderTarget = Bloom::DownTex3; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up2; RenderTarget = Bloom::DownTex2; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up1; RenderTarget = Bloom::DownTex1; BLOOM_BLEND } \
    pass { VertexShader = PostProcessVS; PixelShader = Bloom::PS_Up0; RenderTarget = Bloom::BloomTex; }

} // namespace end
