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

#pragma once

/*******************************************************************************
    Globals
*******************************************************************************/

#define PHI (1.6180339887498)
#define INV_PHI (0.6180339887498)
#define EPSILON (1e-8)
#define PI (3.14159265359)
#define HALF_PI (1.57079632679)
#define DOUBLE_PI (6.28318530718)
#define FLOAT_MAX (65504.0)
#define FLOAT_MIN (-65504.0)
#define IS_SRGB (BUFFER_COLOR_SPACE == 1 || BUFFER_COLOR_SPACE == 0)
#define IS_SCRGB (BUFFER_COLOR_SPACE == 2)
#define IS_HDR_PQ (BUFFER_COLOR_SPACE == 3)
#define IS_HDR_HLG (BUFFER_COLOR_SPACE == 4)
#define IS_8BIT (BUFFER_COLOR_BIT_DEPTH == 8)
#define IS_DX9 (__RENDERER__ < 0xA000)
#define CAN_COMPUTE (__RENDERER__ >= 0xB000)

static const float A_THIRD = 1.0 / 3.0;

// ordering matters in some situations
static const uint S_BOX_OFFS1 = 9;
static const float2 BOX_OFFS1[S_BOX_OFFS1] = {
    float2(0, 0),
    float2(1, 0), float2( 0, 1), float2(-1, 0), float2(0, -1),
    float2(1, 1), float2(-1,-1), float2(-1, 1), float2(1, -1)
};
static const uint S_BOX_OFFS2 = 25;
static const float2 BOX_OFFS2[S_BOX_OFFS2] = {
    float2(0, 0),
    float2(1, 0), float2( 0,  1), float2(-1,  0), float2( 0, -1),
    float2(1, 1), float2(-1, -1), float2(-1,  1), float2( 1, -1),
    float2(2, 0), float2( 0,  2), float2(-2,  0), float2( 0, -2),
    float2(2, 1), float2( 2, -1), float2(-2,  1), float2(-2, -1),
    float2(1, 2), float2(-1,  2), float2( 1, -2), float2(-1, -2),
    float2(2, 2), float2(-2, -2), float2(-2,  2), float2( 2, -2)
};

// Check out a bunch of possible substitutions on:
// https://github.com/crosire/reshade-shaders/wiki/Shader-Tips,-Tricks-and-Optimizations

// There is no point in manually typing out substitutions of built-in functions.
// The compiler already does it and no performance will be saved unless in very rare cases,
// where part of the computation is already done for something else.

// safer versions of built-in functions
// https://www.hillelwayne.com/post/divide-by-zero/
#define RCP(_x) ((_x) == 0.0 ? 0.0 : rcp(_x))
#define RSQRT(_x) ((_x) == 0.0 ? 0.0 : rsqrt(_x))
#define POW(_b, _e) (pow(max(0.0, (_b)), (_e))) // doesn't handle both inputs being 0
#define NORM(_x) ((_x) * RSQRT(dot((_x), (_x))))
#define LOG(_x) (log(max(EPSILON, (_x))))
#define LOG2(_x) (log2(max(EPSILON, (_x))))
#define LOG10(_x) (log10(max(EPSILON, (_x))))
#define exp10(_x) (exp2(3.3219281 * (_x))) // approximate

// call TO_STR(ANOTHER_MACRO)
#define _TO_STR(x) #x
#define TO_STR(x) _TO_STR(x)

#define CEIL_DIV(_x, _y) ((((_x) - 1) / (_y)) + 1)

#if !defined(__RESHADE__) || __RESHADE__ < 30000
    #error "ReShade 3.0+ is required to use this header file"
#endif
#ifndef RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
    #define RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN 0
#endif
#ifndef RESHADE_DEPTH_INPUT_IS_REVERSED
    #define RESHADE_DEPTH_INPUT_IS_REVERSED 1
#endif
#ifndef RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
    #define RESHADE_DEPTH_INPUT_IS_LOGARITHMIC 0
#endif
#ifndef RESHADE_DEPTH_MULTIPLIER
    #define RESHADE_DEPTH_MULTIPLIER 1
#endif
#ifndef RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
    #define RESHADE_DEPTH_LINEARIZATION_FAR_PLANE 1000.0
#endif
// Above 1 expands coordinates, below 1 contracts and 1 is equal to no scaling on any axis
#ifndef RESHADE_DEPTH_INPUT_Y_SCALE
    #define RESHADE_DEPTH_INPUT_Y_SCALE 1
#endif
#ifndef RESHADE_DEPTH_INPUT_X_SCALE
    #define RESHADE_DEPTH_INPUT_X_SCALE 1
#endif
// An offset to add to the Y coordinate, (+) = move up, (-) = move down
#ifndef RESHADE_DEPTH_INPUT_Y_OFFSET
    #define RESHADE_DEPTH_INPUT_Y_OFFSET 0
#endif
#ifndef RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
    #define RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET 0
#endif
// An offset to add to the X coordinate, (+) = move right, (-) = move left
#ifndef RESHADE_DEPTH_INPUT_X_OFFSET
    #define RESHADE_DEPTH_INPUT_X_OFFSET 0
#endif
#ifndef RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
    #define RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET 0
#endif

#define BUFFER_PIXEL_SIZE float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)
#define BUFFER_SCREEN_SIZE float2(BUFFER_WIDTH, BUFFER_HEIGHT)
#define BUFFER_ASPECT_RATIO (BUFFER_WIDTH * BUFFER_RCP_HEIGHT)

#if defined(__RESHADE_FXC__)
    float GetAspectRatio() { return BUFFER_WIDTH * BUFFER_RCP_HEIGHT; }
    float2 GetPixelSize() { return float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT); }
    float2 GetScreenSize() { return float2(BUFFER_WIDTH, BUFFER_HEIGHT); }
    #define AspectRatio GetAspectRatio()
    #define PixelSize GetPixelSize()
    #define ScreenSize GetScreenSize()
#else
    // These are deprecated and will be removed eventually.
    static const float AspectRatio = BUFFER_WIDTH * BUFFER_RCP_HEIGHT;
    static const float2 PixelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    static const float2 ScreenSize = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
#endif

uniform uint frame_count < source = "framecount"; >;
uniform float frame_time < source = "frametime"; >;
uniform float timer < source = "timer"; >;

#if !IS_SRGB
    #ifndef V_HDR_WHITE_LVL
        #define V_HDR_WHITE_LVL 203
    #endif
#endif

#define UI_FLOAT(_category, _name, _label, _descr, _min, _max, _default) \
    uniform float _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_min = _min; \
        ui_max = _max; \
        ui_tooltip = _descr; \
        ui_step = 1e-4; \
        ui_type = "slider"; \
    > = _default;

#define UI_FLOAT2(_category, _name, _label, _descr, _min, _max, _default) \
    uniform float2 _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_min = _min; \
        ui_max = _max; \
        ui_tooltip = _descr; \
        ui_step = 1e-4; \
        ui_type = "slider"; \
    > = _default;

#define UI_FLOAT3(_category, _name, _label, _descr, _min, _max, _default) \
    uniform float3 _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_min = _min; \
        ui_max = _max; \
        ui_tooltip = _descr; \
        ui_step = 1e-4; \
        ui_type = "slider"; \
    > = _default;

#define UI_FLOAT4(_category, _name, _label, _descr, _min, _max, _default) \
    uniform float4 _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_min = _min; \
        ui_max = _max; \
        ui_tooltip = _descr; \
        ui_step = 1e-4; \
        ui_type = "slider"; \
    > = _default;

#define UI_INT(_category, _name, _label, _descr, _min, _max, _default) \
    uniform int _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_min = _min; \
        ui_max = _max; \
        ui_tooltip = _descr; \
        ui_step = 1; \
        ui_type = "slider"; \
    > = _default;

#define UI_INT2(_category, _name, _label, _descr, _min, _max, _default) \
    uniform int2 _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_min = _min; \
        ui_max = _max; \
        ui_tooltip = _descr; \
        ui_step = 1; \
        ui_type = "slider"; \
    > = _default;

#define UI_BOOL(_category, _name, _label, _descr, _default) \
    uniform bool _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_tooltip = _descr; \
        ui_type = "radio"; \
    > = _default;

#define UI_LIST(_category, _name, _label, _descr, _items, _default) \
    uniform int _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_items = _items; \
        ui_tooltip = _descr; \
        ui_type = "combo"; \
    > = _default;

#define UI_COLOR(_category, _name, _label, _descr, _default) \
    uniform float3 _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = _label; \
        ui_min = 0.0; \
        ui_max = 1.0; \
        ui_tooltip = _descr; \
        ui_step = 0.001; \
        ui_type = "color"; \
        ui_closed = true; \
    > = _default;

#define UI_HELP(_name, _descr) \
    uniform int _name < \
        ui_category = "Preprocessor Help"; \
        ui_category_closed = true; \
        ui_label = " "; \
        ui_text = _descr; \
        ui_type = "radio"; \
    >;

#define UI_TIP(_category, _name, _descr) \
    uniform int _name < \
        ui_category = _category; \
        ui_category_closed = true; \
        ui_label = " "; \
        ui_text = _descr; \
        ui_type = "radio"; \
    >;

#define TEX_SIZE(_bit) Width = BUFFER_WIDTH >> _bit; Height = BUFFER_HEIGHT >> _bit;
#define TEX_RGBA8 Format = RGBA8;
#define TEX_RGBA16 Format = RGBA16F;
#define TEX_RGBA32 Format = RGBA32F;
#define TEX_RGB10A2 Format = RGB10A2;
#define TEX_R8 Format = R8;
#define TEX_RG8 Format = RG8;
#define TEX_R16 Format = R16F;
#define TEX_R32 Format = R32F;
#define TEX_RG16 Format = RG16F;
#define TEX_RG32 Format = RG32F;

#define SAM_POINT  MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;
#define SAM_MIRROR AddressU = MIRROR; AddressV = MIRROR;
#define SAM_WRAP   AddressU = WRAP;   AddressV = WRAP;
#define SAM_REPEAT AddressU = REPEAT; AddressV = REPEAT;
#define SAM_BORDER AddressU = BORDER; AddressV = BORDER;

struct VSOUT { float4 vpos : SV_POSITION; float2 uv : TEXCOORD0; };
struct PSOUT2 { float4 t0 : SV_Target0, t1 : SV_Target1; };
struct CSIN {
    uint3 id : SV_DispatchThreadID; // range [0 .. groups * threads).xyz
    uint3 gid : SV_GroupID;         // range [0 .. groups).xyz
    uint3 tid : SV_GroupThreadID;   // range [0 .. threads).xyz
    uint gidx : SV_GroupIndex;      // range [0 .. total_threads_amount)
};

#define PS_ARGS1 in VSOUT i, out float  o : SV_Target0
#define PS_ARGS2 in VSOUT i, out float2 o : SV_Target0
#define PS_ARGS3 in VSOUT i, out float3 o : SV_Target0
#define PS_ARGS4 in VSOUT i, out float4 o : SV_Target0

#define CS_ARGS in CSIN i

#define VS_ARGS \
    in uint id : SV_VertexID, out float4 vpos : SV_Position, out float2 uv : TEXCOORD

#define VS_VPOS_FROM_UV \
    vpos = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);

#define VS_SMALL_TRIANGLE(_num) \
    float k = rcp(1 << _num); \
    uv.x = (id == 2) ? k * 2.0 : 0.0; \
    uv.y = (id == 1) ? 1.0 : (1 - k); \
    VS_VPOS_FROM_UV

/*******************************************************************************
    Functions
*******************************************************************************/

// Vertex shader generating a triangle covering the entire screen
void PostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
{
    texcoord.x = (id == 2) ? 2.0 : 0.0;
    texcoord.y = (id == 1) ? 2.0 : 0.0;
    position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// to be used instead of tex2D and tex2Dlod
float4 Sample(sampler samp, float2 uv)                     { return tex2Dlod(samp, float4(uv, 0, 0)); }
float4 Sample(sampler samp, float2 uv, int mip)            { return tex2Dlod(samp, float4(uv, 0, mip)); }
float4 Sample(sampler samp, float2 uv, int2 offs)          { return tex2Dlod(samp, float4(uv, 0, 0), offs); }
float4 Sample(sampler samp, float2 uv, int mip, int2 offs) { return tex2Dlod(samp, float4(uv, 0, mip), offs); }

// to be used instead of tex2Dfetch
float4 Fetch(sampler samp, float2 pos)          { return tex2Dfetch(samp, pos); }
float4 Fetch(sampler samp, float2 pos, int mip) { return tex2Dfetch(samp, pos, mip); }

float3 SRGBToLin(float3 c)
{
    return (c < 0.04045) ? c / 12.92 : POW((c + 0.055) / 1.055, 2.4);
}

float3 LinToSRGB(float3 c)
{
    return (c < 0.0031308) ? 12.92 * c : 1.055 * POW(c, 0.41666666) - 0.055;
}

float3 PQToLin(float3 c)
{
    static const float c1 = 0.8359375;
    static const float c2 = 18.8515625;
    static const float c3 = 18.6875;

    c = POW(c, 32.0 / 2523.0);
    c = max(0.0, c - c1) * RCP(c2 - c3 * c);

    return POW(c, 8192.0 / 1305.0);
}

float3 LinToPQ(float3 c)
{
    static const float c1 = 0.8359375;
    static const float c2 = 18.8515625;
    static const float c3 = 18.6875;

    c = POW(c, 1305.0 / 8192.0);
    c = (c1 + c2 * c) * RCP(1.0 + c3 * c);

    return POW(c, 2523.0 / 32.0);
}

float3 HLGToLin(float3 c)
{
    static const float c1 = 0.17883277;
    static const float c2 = 0.28466892;
    static const float c3 = 0.55991073;

    c = c < 0.5 ? ((c * c) / 3.0) : ((exp((c - c3) / c1) + c2) / 12.0);

    return c;
}

float3 LinToHLG(float3 c)
{
    static const float c1 = 0.17883277;
    static const float c2 = 0.28466892;
    static const float c3 = 0.55991073;

    c = c <= (1.0 / 12.0) ? sqrt(c * 3.0) : (LOG(c * 12 - c2) * c1 + c3);

    return c;
}

float3 ApplyLinCurve(float3 c)
{
#if IS_SRGB
    c = SRGBToLin(c);
#elif IS_SCRGB
    c = c * (80.0 / V_HDR_WHITE_LVL);
#elif IS_HDR_PQ
    c = PQToLin(c);
#elif IS_HDR_HLG
    c = HLGToLin(c);
#endif

    return c;
}

float3 ApplyGammaCurve(float3 c)
{
#if IS_SRGB
    c = LinToSRGB(c);
#elif IS_SCRGB
    c = c * (V_HDR_WHITE_LVL / 80.0);
#elif IS_HDR_PQ
    c = LinToPQ(c);
#elif IS_HDR_HLG
    c = LinToHLG(c);
#endif

    return c;
}

// gamma color -> luma
// linear color -> luminance
// same fuction, just different input

float RGBToYCbCrLuma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float RGBToYCoCgLuma(float3 c)
{
    return dot(c, float3(0.25, 0.5, 0.25));
}

float3 RGBToYCoCg(float3 rgb)
{
    return float3(
        RGBToYCoCgLuma(rgb),
        dot(rgb, float3(0.5, 0.0, -0.5)),
        dot(rgb, float3(-0.25, 0.5, -0.25))
    );
}

float3 YCoCgToRGB(float3 ycc)
{
    return float3(
        dot(ycc, float3(1.0, 1.0, -1.0)),
        dot(ycc, float3(1.0, 0.0, 1.0)),
        dot(ycc, float3(1.0, -1.0, -1.0))
    );
}

float3 RGBToYCbCr(float3 rgb)
{
    float y = RGBToYCbCrLuma(rgb);

    return float3(y, (rgb.b - y) * 0.565, (rgb.r - y) * 0.713);
}

float3 YCbCrToRGB(float3 ycc)
{
    return float3(
        ycc.x + 1.403 * ycc.z,
        ycc.x - 0.344 * ycc.y - 0.714 * ycc.z,
        ycc.x + 1.770 * ycc.y
    );
}

float3 RGBToHSV(float3 c)
{
    static const float4 K = float4(0.0, (-1.0 / 3.0), (2.0 / 3.0), -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);

    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + EPSILON)), d / (q.x + EPSILON), q.x);
}

float3 HSVToRGB(float3 c)
{
    static const float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);

    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float3 RGBToXYZ(float3 col)
{
    return float3(
        dot(float3(0.4124, 0.3576, 0.1805), col),
        dot(float3(0.4124, 0.3576, 0.1805), col),
        dot(float3(0.0193, 0.1192, 0.9505), col)
    );
}

float3 XYZToRGB(float3 col)
{
    return float3(
        dot(float3(3.2406, -1.5372, -0.4986), col),
        dot(float3(-0.9689, 1.8758, 0.0415), col),
        dot(float3(0.0557, -0.2040, 1.0570), col)
    );
}

float3 XYZToYXY(float3 col)
{
    float inv = 1.0 / dot(col, 1.0);

    return float3(col.y, col.x * inv, col.y * inv);
}

float3 YXYToXYZ(float3 col)
{
    return float3(
        col.x * col.y / col.z,
        col.x,
        col.x * (1.0 - col.y - col.z) / col.z
    );
}

float3 RGBToYXY(float3 col)
{
    return XYZToYXY(RGBToXYZ(col));
}

float3 YXYToRGB(float3 col)
{
    return XYZToRGB(YXYToXYZ(col));
}

float3 XYZToLAB(float3 c)
{
    float3 n = c / float3(0.95047, 1.0, 1.08883);
    float3 v = n > 0.008856 ? POW(n, 1.0 / 3.0) : (7.787 * n) + (16.0 / 116.0);
    float3 lab = float3((116.0 * v.y) - 16.0, 500.0 * (v.x - v.y), 200.0 * (v.y - v.z));

    return float3(lab.x / 100.0, 0.5 + 0.5 * (lab.y / 127.0), 0.5 + 0.5 * (lab.z / 127.0));
}

float3 LABToXYZ(float3 c)
{
    float3 lab = float3(100.0 * c.x, 2.0 * 127.0 * (c.y - 0.5), 2.0 * 127.0 * (c.z - 0.5));
    float3 v;

    v.y = (lab.x + 16.0) / 116.0;
    v.x = lab.y / 500.0 + v.y;
    v.z = v.y - lab.z / 200.0;

    return float3(0.95047, 1.0, 1.08883) * (v > 0.206897 ? v * (v * v) : (v - 16.0 / 116.0) / 7.787);
}

float3 RGBToLAB(float3 c)
{
    return XYZToLAB(RGBToXYZ(c));
}

float3 LABToRGB(float3 c)
{
    return XYZToRGB(LABToXYZ(c));
}

float3 OverlayBlend(float3 a, float3 b)
{
    return a < 0.5 ? (2.0 * a * b) : (1.0 - 2.0 * (1.0 - a) * (1.0 - b));
}

float3 SoftLightBlend(float3 a, float3 b)
{
    // pegtop version
    return (1.0 - 2.0 * b) * a * a + 2.0 * b * a;
}

float Max2(float2 f) { return max(f.x, f.y); }
float Max3(float3 f) { return max(f.x, max(f.y, f.z)); }
float Max4(float4 f) { return max(f.x, max(f.y, max(f.z, f.w))); }
float Max3(float a, float b, float c) { return max(a, max(b, c)); }
float2 Max3(float2 a, float2 b, float2 c) { return max(a, max(b, c)); }
float3 Max3(float3 a, float3 b, float3 c) { return max(a, max(b, c)); }
float4 Max3(float4 a, float4 b, float4 c) { return max(a, max(b, c)); }

float Min2(float2 f) { return min(f.x, f.y); }
float Min3(float3 f) { return min(f.x, min(f.y, f.z)); }
float Min4(float4 f) { return min(f.x, min(f.y, min(f.z, f.w))); }
float Min3(float a, float b, float c) { return min(a, min(b, c)); }
float2 Min3(float2 a, float2 b, float2 c) { return min(a, min(b, c)); }
float3 Min3(float3 a, float3 b, float3 c) { return min(a, min(b, c)); }
float4 Min3(float4 a, float4 b, float4 c) { return min(a, min(b, c)); }

// interleaved gradiant noise from:
// http://www.iryoku.com/downloads/Next-Generation-Post-Processing-in-Call-of-Duty-Advanced-Warfare-v18.pptx
float GetIGN(float2 pos, uint seed)
{
    float idx = 5.588238 * float(min(seed, 63));

    return frac(52.9829189 * frac(dot(pos + idx, float2(0.06711056, 0.00583715))));
}

float3 GetWhiteNoise(float2 vpos)
{
    float seed = timer * 0.001;
    float n = frac(tan(length(vpos) * seed) * vpos.x);

    // tan can produce NaNs at certain inputs
    n = isnan(n) ? 0.0 : n;

    return float3(n, frac(n + 0.1), frac(n + 0.3));
}

float Halton1(uint i, uint b)
{
    float f = 1.0;
    float r = 0.0;

    while(i > 0)
    {
        f /= float(b);
        r += f * float(i % b);
        i /= b;
    }

    return r;
}

float2 Halton2(uint seed)
{
    return float2(Halton1(seed, 2), Halton1(seed, 3));
}

// quasirandom showcased in https://www.shadertoy.com/view/mts3zN
// 0.38196601125 = 1 - (1 / PHI) = 2.0 - PHI
float  GetR1(float seed,  float idx) { return frac(seed + float(idx) * 0.38196601125); }
float2 GetR2(float2 seed, float idx) { return frac(seed + float(idx) * float2(0.245122333753, 0.430159709002)); }
float3 GetR3(float3 seed, float idx) { return frac(seed + float(idx) * float3(0.180827486604, 0.328956393296, 0.450299522098)); }

// bicubic sampling using fewer taps
float4 SampleBicubic(sampler2D lin_samp, float2 uv)
{
    float2 tex_size = tex2Dsize(lin_samp);
    float2 pix_size = rcp(tex_size);

    float2 sample_pos = uv * tex_size;
    float2 center_pos = floor(sample_pos - 0.5) + 0.5;
    float2 f = sample_pos - center_pos;
    float2 f2 = f * f;
    float2 f3 = f2 * f;

    float2 w0 = f2 - 0.5 * (f3 + f);
    float2 w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
    float2 w3 = 0.5 * (f3 - f2);
    float2 w2 = 1 - w0 - w1 - w3;
    float2 w12 = w1 + w2;

    float2 tc0 = (center_pos - 1.0) * pix_size;
    float2 tc3 = (center_pos + 2.0) * pix_size;
    float2 tc12 = (center_pos + w2 / w12) * pix_size;

    float4 A = Sample(lin_samp, float2(tc12.x, tc0.y));
    float4 B = Sample(lin_samp, float2(tc0.x, tc12.y));
    float4 C = Sample(lin_samp, float2(tc12.x,  tc12.y));
    float4 D = Sample(lin_samp, float2(tc3.x, tc12.y));
    float4 E = Sample(lin_samp, float2(tc12.x, tc3.y));

    float4 color = (0.5 * (A + B) * w0.x + A * w12.x + 0.5 * (A + B) * w3.x) * w0.y +
                   (B * w0.x + C * w12.x + D * w3.x) * w12.y +
                   (0.5 * (B + E) * w0.x + E * w12.x + 0.5 * (D + E) * w3.x) * w3.y;

    return color;
}

float Dither(float2 vpos, float scale)
{
    float2 s = float2(floor(vpos) % 2) * 2.0 - 1.0;

    return scale * s.x * s.y;
}

float2 GetHDRRange()
{
#if IS_SRGB
    return float2(0.0, FLOAT_MAX);
#elif IS_SCRGB
    return float2(-0.5, 10000.0 / V_HDR_WHITE_LVL);
#elif IS_HDR_PQ
    return float2(0.0, 10000.0 / V_HDR_WHITE_LVL);
#elif IS_HDR_HLG
    return float2(0.0, 1000.0 / V_HDR_WHITE_LVL);
#else
    return float2(0.0, 1.0);
#endif
}

// rotates counter clockwise
float4 GetRotator(float rads)
{
    float2 sc; sincos(rads, sc.x, sc.y);

    return float4(sc.y, sc.x, -sc.x, sc.y);
}

float2 Rotate(float2 v, float4 rot)
{
    return float2(dot(v, rot.xy), dot(v, rot.zw));
}

// check beforehand if both vectors are not 0
float GetCosAngle(float2 v1, float2 v2)
{
    // var. 1: dot(v1, v2) * RSQRT(dot(v1, v1) * dot(v2, v2))
    // var. 2: dot(v1, v2) * RCP(length(v1) * length(v2))
    // var. 3: dot(NORM(v1), NORM(v2))

    return dot(v1, v2) * RSQRT(dot(v1, v1) * dot(v2, v2));
}

float ACOS(float cos_rads)
{
    float abs_cr = abs(cos_rads);
    float rads = (-0.156583 * abs_cr + HALF_PI) * sqrt(1.0 - abs_cr);

    return cos_rads < 0.0 ? PI - rads : rads;
}

bool ValidateUV(float2 uv)
{
    float2 range = saturate(uv * uv - uv);

    return range.x == -range.y;
}
