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
#include "Includes/vort_Defs.fxh"
#include "Includes/vort_HDR_UI.fxh"

#if V_ENABLE_LUT

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

#if !V_LOAD_ALL_LUTS
    texture3D CubeTexVort < source = TO_STR(V_LUT_FILE) ".cube"; >
    { Width = V_LUT_SIZE; Height = V_LUT_SIZE; Depth = V_LUT_SIZE; TEX_RGBA32 };
    sampler3D sCubeTexVort { Texture = CubeTexVort; };
#else
    #define MAKE_LUT_TS(x) \
        texture3D CubeTexVort##x < source = TO_STR(x) ".cube"; > \
        { Width = V_LUT_SIZE; Height = V_LUT_SIZE; Depth = V_LUT_SIZE; TEX_RGBA32 }; \
        sampler3D sCubeTexVort##x { Texture = CubeTexVort##x; };

    #if V_LOAD_ALL_LUTS == 1
        MAKE_LUT_TS(1)
        MAKE_LUT_TS(2)
        MAKE_LUT_TS(3)
        MAKE_LUT_TS(4)
        MAKE_LUT_TS(5)
        MAKE_LUT_TS(6)
        MAKE_LUT_TS(7)
        MAKE_LUT_TS(8)
        MAKE_LUT_TS(9)
        MAKE_LUT_TS(10)
        MAKE_LUT_TS(11)
        MAKE_LUT_TS(12)
        MAKE_LUT_TS(13)
        MAKE_LUT_TS(14)
        MAKE_LUT_TS(15)
        MAKE_LUT_TS(16)
        MAKE_LUT_TS(17)
        MAKE_LUT_TS(18)
        MAKE_LUT_TS(19)
        MAKE_LUT_TS(20)
        MAKE_LUT_TS(21)
        MAKE_LUT_TS(22)
        MAKE_LUT_TS(23)
        MAKE_LUT_TS(24)
        MAKE_LUT_TS(25)
        MAKE_LUT_TS(26)
        MAKE_LUT_TS(27)
        MAKE_LUT_TS(28)
        MAKE_LUT_TS(29)
        MAKE_LUT_TS(30)
        MAKE_LUT_TS(31)
        MAKE_LUT_TS(32)
        MAKE_LUT_TS(33)
        MAKE_LUT_TS(34)
        MAKE_LUT_TS(35)
        MAKE_LUT_TS(36)
        MAKE_LUT_TS(37)
        MAKE_LUT_TS(38)
        MAKE_LUT_TS(39)
        MAKE_LUT_TS(40)
        MAKE_LUT_TS(41)
        MAKE_LUT_TS(42)
        MAKE_LUT_TS(43)
        MAKE_LUT_TS(44)
        MAKE_LUT_TS(45)
        MAKE_LUT_TS(46)
        MAKE_LUT_TS(47)
        MAKE_LUT_TS(48)
        MAKE_LUT_TS(49)
        MAKE_LUT_TS(50)
    #else
        MAKE_LUT_TS(51)
        MAKE_LUT_TS(52)
        MAKE_LUT_TS(53)
        MAKE_LUT_TS(54)
        MAKE_LUT_TS(55)
        MAKE_LUT_TS(56)
        MAKE_LUT_TS(57)
        MAKE_LUT_TS(58)
        MAKE_LUT_TS(59)
        MAKE_LUT_TS(60)
        MAKE_LUT_TS(61)
        MAKE_LUT_TS(62)
        MAKE_LUT_TS(63)
        MAKE_LUT_TS(64)
        MAKE_LUT_TS(65)
        MAKE_LUT_TS(66)
        MAKE_LUT_TS(67)
        MAKE_LUT_TS(68)
        MAKE_LUT_TS(69)
        MAKE_LUT_TS(70)
        MAKE_LUT_TS(71)
        MAKE_LUT_TS(72)
        MAKE_LUT_TS(73)
        MAKE_LUT_TS(74)
        MAKE_LUT_TS(75)
        MAKE_LUT_TS(76)
        MAKE_LUT_TS(77)
        MAKE_LUT_TS(78)
        MAKE_LUT_TS(79)
        MAKE_LUT_TS(80)
        MAKE_LUT_TS(81)
        MAKE_LUT_TS(82)
        MAKE_LUT_TS(83)
        MAKE_LUT_TS(84)
        MAKE_LUT_TS(85)
        MAKE_LUT_TS(86)
        MAKE_LUT_TS(87)
        MAKE_LUT_TS(88)
        MAKE_LUT_TS(89)
        MAKE_LUT_TS(90)
        MAKE_LUT_TS(91)
        MAKE_LUT_TS(92)
        MAKE_LUT_TS(93)
        MAKE_LUT_TS(94)
        MAKE_LUT_TS(95)
        MAKE_LUT_TS(96)
        MAKE_LUT_TS(97)
        MAKE_LUT_TS(98)
        MAKE_LUT_TS(99)
        MAKE_LUT_TS(100)
    #endif
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float3 ApplyLUT(float3 c)
{
    float3 orig_c = c;

    c = LinToSRGB(c);

    // remap the color depending on the LUT size
    c = (c - 0.5) * ((V_LUT_SIZE - 1.0) / V_LUT_SIZE) + 0.5;

#if !V_LOAD_ALL_LUTS
    c = tex3D(sCubeTexVort, c).rgb;
#else
    switch(UI_CC_LUTName)
    {
    #if V_LOAD_ALL_LUTS == 1
        case  1: c = tex3D(sCubeTexVort1,  c).rgb; break;
        case  2: c = tex3D(sCubeTexVort2,  c).rgb; break;
        case  3: c = tex3D(sCubeTexVort3,  c).rgb; break;
        case  4: c = tex3D(sCubeTexVort4,  c).rgb; break;
        case  5: c = tex3D(sCubeTexVort5,  c).rgb; break;
        case  6: c = tex3D(sCubeTexVort6,  c).rgb; break;
        case  7: c = tex3D(sCubeTexVort7,  c).rgb; break;
        case  8: c = tex3D(sCubeTexVort8,  c).rgb; break;
        case  9: c = tex3D(sCubeTexVort9,  c).rgb; break;
        case 10: c = tex3D(sCubeTexVort10, c).rgb; break;
        case 11: c = tex3D(sCubeTexVort11, c).rgb; break;
        case 12: c = tex3D(sCubeTexVort12, c).rgb; break;
        case 13: c = tex3D(sCubeTexVort13, c).rgb; break;
        case 14: c = tex3D(sCubeTexVort14, c).rgb; break;
        case 15: c = tex3D(sCubeTexVort15, c).rgb; break;
        case 16: c = tex3D(sCubeTexVort16, c).rgb; break;
        case 17: c = tex3D(sCubeTexVort17, c).rgb; break;
        case 18: c = tex3D(sCubeTexVort18, c).rgb; break;
        case 19: c = tex3D(sCubeTexVort19, c).rgb; break;
        case 20: c = tex3D(sCubeTexVort20, c).rgb; break;
        case 21: c = tex3D(sCubeTexVort21, c).rgb; break;
        case 22: c = tex3D(sCubeTexVort22, c).rgb; break;
        case 23: c = tex3D(sCubeTexVort23, c).rgb; break;
        case 24: c = tex3D(sCubeTexVort24, c).rgb; break;
        case 25: c = tex3D(sCubeTexVort25, c).rgb; break;
        case 26: c = tex3D(sCubeTexVort26, c).rgb; break;
        case 27: c = tex3D(sCubeTexVort27, c).rgb; break;
        case 28: c = tex3D(sCubeTexVort28, c).rgb; break;
        case 29: c = tex3D(sCubeTexVort29, c).rgb; break;
        case 30: c = tex3D(sCubeTexVort30, c).rgb; break;
        case 31: c = tex3D(sCubeTexVort31, c).rgb; break;
        case 32: c = tex3D(sCubeTexVort32, c).rgb; break;
        case 33: c = tex3D(sCubeTexVort33, c).rgb; break;
        case 34: c = tex3D(sCubeTexVort34, c).rgb; break;
        case 35: c = tex3D(sCubeTexVort35, c).rgb; break;
        case 36: c = tex3D(sCubeTexVort36, c).rgb; break;
        case 37: c = tex3D(sCubeTexVort37, c).rgb; break;
        case 38: c = tex3D(sCubeTexVort38, c).rgb; break;
        case 39: c = tex3D(sCubeTexVort39, c).rgb; break;
        case 40: c = tex3D(sCubeTexVort40, c).rgb; break;
        case 41: c = tex3D(sCubeTexVort41, c).rgb; break;
        case 42: c = tex3D(sCubeTexVort42, c).rgb; break;
        case 43: c = tex3D(sCubeTexVort43, c).rgb; break;
        case 44: c = tex3D(sCubeTexVort44, c).rgb; break;
        case 45: c = tex3D(sCubeTexVort45, c).rgb; break;
        case 46: c = tex3D(sCubeTexVort46, c).rgb; break;
        case 47: c = tex3D(sCubeTexVort47, c).rgb; break;
        case 48: c = tex3D(sCubeTexVort48, c).rgb; break;
        case 49: c = tex3D(sCubeTexVort49, c).rgb; break;
        case 50: c = tex3D(sCubeTexVort50, c).rgb; break;
    #else
        case  1: c = tex3D(sCubeTexVort51, c).rgb; break;
        case  2: c = tex3D(sCubeTexVort52, c).rgb; break;
        case  3: c = tex3D(sCubeTexVort53, c).rgb; break;
        case  4: c = tex3D(sCubeTexVort54, c).rgb; break;
        case  5: c = tex3D(sCubeTexVort55, c).rgb; break;
        case  6: c = tex3D(sCubeTexVort56, c).rgb; break;
        case  7: c = tex3D(sCubeTexVort57, c).rgb; break;
        case  8: c = tex3D(sCubeTexVort58, c).rgb; break;
        case  9: c = tex3D(sCubeTexVort59, c).rgb; break;
        case 10: c = tex3D(sCubeTexVort60, c).rgb; break;
        case 11: c = tex3D(sCubeTexVort61, c).rgb; break;
        case 12: c = tex3D(sCubeTexVort62, c).rgb; break;
        case 13: c = tex3D(sCubeTexVort63, c).rgb; break;
        case 14: c = tex3D(sCubeTexVort64, c).rgb; break;
        case 15: c = tex3D(sCubeTexVort65, c).rgb; break;
        case 16: c = tex3D(sCubeTexVort66, c).rgb; break;
        case 17: c = tex3D(sCubeTexVort67, c).rgb; break;
        case 18: c = tex3D(sCubeTexVort68, c).rgb; break;
        case 19: c = tex3D(sCubeTexVort69, c).rgb; break;
        case 20: c = tex3D(sCubeTexVort70, c).rgb; break;
        case 21: c = tex3D(sCubeTexVort71, c).rgb; break;
        case 22: c = tex3D(sCubeTexVort72, c).rgb; break;
        case 23: c = tex3D(sCubeTexVort73, c).rgb; break;
        case 24: c = tex3D(sCubeTexVort74, c).rgb; break;
        case 25: c = tex3D(sCubeTexVort75, c).rgb; break;
        case 26: c = tex3D(sCubeTexVort76, c).rgb; break;
        case 27: c = tex3D(sCubeTexVort77, c).rgb; break;
        case 28: c = tex3D(sCubeTexVort78, c).rgb; break;
        case 29: c = tex3D(sCubeTexVort79, c).rgb; break;
        case 30: c = tex3D(sCubeTexVort80, c).rgb; break;
        case 31: c = tex3D(sCubeTexVort81, c).rgb; break;
        case 32: c = tex3D(sCubeTexVort82, c).rgb; break;
        case 33: c = tex3D(sCubeTexVort83, c).rgb; break;
        case 34: c = tex3D(sCubeTexVort84, c).rgb; break;
        case 35: c = tex3D(sCubeTexVort85, c).rgb; break;
        case 36: c = tex3D(sCubeTexVort86, c).rgb; break;
        case 37: c = tex3D(sCubeTexVort87, c).rgb; break;
        case 38: c = tex3D(sCubeTexVort88, c).rgb; break;
        case 39: c = tex3D(sCubeTexVort89, c).rgb; break;
        case 40: c = tex3D(sCubeTexVort90, c).rgb; break;
        case 41: c = tex3D(sCubeTexVort91, c).rgb; break;
        case 42: c = tex3D(sCubeTexVort92, c).rgb; break;
        case 43: c = tex3D(sCubeTexVort93, c).rgb; break;
        case 44: c = tex3D(sCubeTexVort94, c).rgb; break;
        case 45: c = tex3D(sCubeTexVort95, c).rgb; break;
        case 46: c = tex3D(sCubeTexVort96, c).rgb; break;
        case 47: c = tex3D(sCubeTexVort97, c).rgb; break;
        case 48: c = tex3D(sCubeTexVort98, c).rgb; break;
        case 49: c = tex3D(sCubeTexVort99, c).rgb; break;
        case 50: c = tex3D(sCubeTexVort100, c).rgb; break;
    #endif
    }
#endif

    c = SRGBToLin(c);

    float3 factor = float3(UI_CC_LUTLuma, UI_CC_LUTChroma, UI_CC_LUTChroma);
    orig_c = OKColors::RGBToOKLAB(orig_c); c = OKColors::RGBToOKLAB(c);
    c = OKColors::OKLABToRGB(lerp(orig_c, c, factor));

    return c;
}

#endif // V_ENABLE_LUT
