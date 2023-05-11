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

#ifndef V_ENABLE_BLOOM
    #define V_ENABLE_BLOOM 1
#endif

#ifndef V_ENABLE_SHARPEN
    #define V_ENABLE_SHARPEN 1
#endif

#ifndef V_ENABLE_COLOR_GRADING
    #define V_ENABLE_COLOR_GRADING 1
#endif

#ifndef V_BLOOM_MANUAL_PASSES
    #define V_BLOOM_MANUAL_PASSES 0 // if 0 -> auto select depending on the resolution, else -> 2 <= X <= 9
#endif

#ifndef V_BLOOM_DEBUG
    #define V_BLOOM_DEBUG 0
#endif

#ifndef V_USE_AUTO_EXPOSURE
    #define V_USE_AUTO_EXPOSURE 1
#endif

#ifndef V_SHOW_ONLY_HDR_COLORS
    #define V_SHOW_ONLY_HDR_COLORS 0
#endif

#if IS_SRGB
    #define CAT_TONEMAP "Tonemap"

    UI_LIST(CAT_TONEMAP, UI_CC_Tonemapper, "Tonemapper", "The function on which tonemapping is based", "Lottes\0ACES\0", 1)
    UI_FLOAT(CAT_TONEMAP, UI_CC_LottesMod, "Lottes Modifier", "Lower values increase the color range, but can introduce clipping.", 1.001, 1.5, 1.05)
#endif

#define CAT_COL_STUDIO "Color Studio"

#if V_USE_AUTO_EXPOSURE
    UI_FLOAT(CAT_COL_STUDIO, UI_CC_AutoExpAdaptTime, "Exposure Adaption Time", "Higher values equal longer adaption time", 0.0, 1.0, 0.9)
    UI_FLOAT(CAT_COL_STUDIO, UI_CC_AutoExpMinAvg, "Exposure Min Average", "The minimum value used for the averaging of the scene", 0.0, 0.5, 0.07)
#endif

UI_FLOAT(CAT_COL_STUDIO, UI_CC_ManualExp, "Manual Exposure", "Changes the exposure of the scene", -5.0, 5.0, 1.5)

#if V_ENABLE_COLOR_GRADING
    UI_FLOAT(CAT_COL_STUDIO, UI_CC_WBTemp, "White Balance Temp", "Changes the temp of the whites.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_COL_STUDIO, UI_CC_WBTint, "White Balance Tint", "Changes the tint of the whites.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_COL_STUDIO, UI_CC_Saturation, "Saturation", "Changes the saturation of the image", -1.0, 1.0, 0.0)
    UI_FLOAT(CAT_COL_STUDIO, UI_CC_Contrast, "Contrast", "Changes the contrast of the image", -1.0, 1.0, 0.0)
    UI_COLOR(CAT_COL_STUDIO, UI_CC_Lift, "Lift(Shadows)", "Change the color of the shadows.", 0.0, 1.0, 0.5)
    UI_COLOR(CAT_COL_STUDIO, UI_CC_Gamma, "Gamma(Midtones)", "Change the color of the midtones.", 0.0, 1.0, 0.5)
    UI_COLOR(CAT_COL_STUDIO, UI_CC_Gain, "Gain(Highlights)", "Changes the color of the highlights.", 0.0, 1.0, 0.5)
#endif

#if V_ENABLE_BLOOM
    #define CAT_BLOOM "Bloom"

    UI_FLOAT(CAT_BLOOM, UI_Bloom_Intensity, "Bloom Intensity", "Controls the amount of bloom", 0.0, 1.0, 0.15)
    UI_FLOAT(CAT_BLOOM, UI_Bloom_Radius, "Bloom Radius", "Affects the size/scale of the bloom", 0.0, 1.0, 0.8)
    UI_FLOAT(CAT_BLOOM, UI_Bloom_DitherStrength, "Dither Strength", "How much noise to add.", 0.0, 1.0, 0.05)
#endif

#if V_ENABLE_SHARPEN
    #define CAT_SHARP "Sharpen"

    UI_BOOL(CAT_SHARP, UI_CC_ShowSharpening, "Show only Sharpening", "", false)
    UI_FLOAT(CAT_SHARP, UI_CC_SharpenLimit, "Sharpen Limit", "Control which pixel to be sharpened", 0.0, 0.1, 0.005)
    UI_FLOAT(CAT_SHARP, UI_CC_SharpenStrength, "Sharpening Strength", "Controls the shaprening strength.", 0.0, 1.0, 0.8)
    UI_FLOAT(CAT_SHARP, UI_CC_UnsharpenStrength, "Unsharpening Strength", "Controls the unsharpness strength.", 0.0, 1.0, 1.0)
    UI_FLOAT(CAT_SHARP, UI_CC_SharpenSwitchPoint, "Switch Point", "When to switch from sharpening to unsharpening", 0.0, 1.0, 0.1)
#endif

UI_HELP(
_vort_HDR_Help_,
"V_ENABLE_BLOOM - 0 or 1\n"
"Toggles the bloom effect.\n"
"\n"
"V_ENABLE_SHARPEN - 0 or 1\n"
"Toggless the sharpening and far blur.\n"
"\n"
"V_ENABLE_COLOR_GRADING - 0 or 1\n"
"Toggless all the color granding effects\n"
"\n"
"V_BLOOM_MANUAL_PASSES - from 2 to 9. Defaults to 8 for 1080p and 9 for 4K.\n"
"How many downsample/upsamples of the image to do in order to perform the bloom.\n"
"\n"
"V_BLOOM_DEBUG - 0 or 1\n"
"Shows 4 bright squares to see the bloom effect and make UI adjustments if you want.\n"
"\n"
"V_USE_AUTO_EXPOSURE - 0 or 1\n"
"Toggles the Auto-Exposure(Eye Adaption) effect\n"
"\n"
"V_SHOW_ONLY_HDR_COLORS - 0 or 1\n"
"If 1, shows only the HDR colors before the tonemapping in gray\n"
"\n"
"V_USE_HW_LIN - 0 or 1\n"
"Toggles hardware linearization. Disable if you use REST addon version older than 1.2.1\n"
)
