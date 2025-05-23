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

#ifndef V_MV_MODE
    #define V_MV_MODE 1
#endif

#ifndef V_MV_DEBUG
    #define V_MV_DEBUG 0
#endif

#ifndef V_MV_USE_REST
    #define V_MV_USE_REST 0
#endif

#ifndef V_ENABLE_MOT_BLUR
    #define V_ENABLE_MOT_BLUR 0
#endif

#ifndef V_MB_USE_MIN_FILTER
    #define V_MB_USE_MIN_FILTER 0
#endif

#define USE_HQ_MB CAN_COMPUTE && V_ENABLE_MOT_BLUR != 1
#define DEBUG_BLUR (V_ENABLE_MOT_BLUR == 9)
#define DEBUG_TILES (V_ENABLE_MOT_BLUR == 8)
#define DEBUG_NEXT_MV (V_ENABLE_MOT_BLUR == 7)

#ifndef V_ENABLE_TAA
    #define V_ENABLE_TAA 0
#endif

#if V_ENABLE_MOT_BLUR
    #define CAT_MB "Motion Blur"

    UI_INT(CAT_MB, UI_MB_MaxSamples, "Max Samples", "Tradeoff between performance and quality.", 3, 100, 9)
    UI_TIP(CAT_MB, _vort_Blur_Help_, "Warning:\nRead the tooltips if you want to change the below settings.")
    UI_FLOAT(
        CAT_MB, UI_MB_BlurMult, "Blur Multiplier",
        "By default the blur covers frame gaps exactly.\n"
        "Lower this setting to reduce blur amount\n"
        "(simulate faster shutter speed of a camera).",
        0, 1, 1
    )

    #if USE_HQ_MB
        UI_TIP(CAT_MB, _vort_Blur_MV_Discard_,
            "Tip:\n"
            "If you notice that circular camera movement doesn't produce circles,\n"
            "you can try changing RESHADE_DEPTH_LINEARIZATION_FAR_PLANE to 10000."
        )
    #endif

    #if DEBUG_BLUR
        #if USE_HQ_MB
            UI_LIST(CAT_MB, UI_MB_DebugUseRepeat, "DB Use Repeating Pattern", "", "None\0Circle\0Long Line\0Short Line\0", 0)
        #endif

        UI_INT2(CAT_MB, UI_MB_DebugLen, "DB Length", "", -100, 100, 0)
        UI_FLOAT(CAT_MB, UI_MB_DebugZCen, "DB Depth Center", "", 0.0, 1.0, 0.0)
        UI_FLOAT(CAT_MB, UI_MB_DebugZRange, "DB Depth Range", "", 0.0, 1.0, 0.5)
        UI_BOOL(CAT_MB, UI_MB_DebugRev, "DB Reverse Background Blur", "", false)
        UI_BOOL(CAT_MB, UI_MB_DebugPoint, "DB Point To Center", "", false)
    #endif
#endif

#if V_ENABLE_TAA
    #define CAT_TAA "Temporal AA"

    UI_FLOAT(CAT_TAA, UI_TAA_Jitter, "Jitter Amount", "How much to shift every pixel position each frame", 0.0, 1.0, 0.0)
    UI_FLOAT(CAT_TAA, UI_TAA_Alpha, "Frame Blend", "Higher values reduce blur, but reduce AA as well", 0.05, 1.0, 0.2)
    UI_FLOAT(CAT_TAA, UI_TAA_Sharpen, "Sharpening", "The amount of sharpening applied", 0.0, 1.0, 0.5)
#endif

UI_HELP(
_vort_MotionEffects_Help_,
"V_ENABLE_MOT_BLUR\n"
"0 - disabled\n"
"1 - enable high performance Motion Blur\n"
"2 - enable high quality Motion Blur (recommended)\n"
"7 - debug next motion\n"
"8 - debug tiles\n"
"9 - debug motion blur\n"
"\n"
"V_MB_USE_MIN_FILTER\n"
"0 - disabled\n"
"1 - enabled\n"
"Many games don't have correct depth on object outlines.\n"
"Enable if you notice with the background blurred, but static character,\n"
"that the background blur is using pixels from the character.\n"
"\n"
"V_ENABLE_TAA\n"
"0 - disabled\n"
"1 - enable the TAA effect.\n"
"\n"
"V_MV_DEBUG\n"
"0 - disabled\n"
"1 - enable the debug view of the motion vectors\n"
"2 - blend the debug view with original color\n"
"\n"
"V_MV_MODE\n"
"0 - don't calculate motion vectors\n"
"1 - auto include my motion vectors (highly recommended)\n"
"2 - manually use iMMERSE motion vectors\n"
"3 - manually use other motion vectors (qUINT_of, qUINT_motionvectors, DRME, etc.)\n"
"\n"
"V_MV_USE_REST\n"
"0 - don't use REST addon for velocity\n"
"1 - use REST addon to get velocity in generic games\n"
"2 - use REST addon to get velocity in Unreal Engine games\n"
"3 - use REST addon to get velocity in CryEngine games\n"
)
