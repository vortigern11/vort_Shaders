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

#if V_MV_MODE == 1
    #ifndef V_MV_USE_HQ
        #define V_MV_USE_HQ 0
    #endif
#endif

#ifndef V_MV_USE_REST
    #define V_MV_USE_REST 0
#endif

#ifndef V_ENABLE_MOT_BLUR
    #define V_ENABLE_MOT_BLUR 0
#endif

#ifndef V_ENABLE_TAA
    #define V_ENABLE_TAA 0
#endif

#if V_MV_MODE == 1
    #define CAT_MV "Motion Vectors"

    UI_FLOAT(CAT_MV, UI_MV_Scale, "Filter Scale", "Small details vs smoothness", 1.0, 5.0, 2.0)
#endif

#if V_ENABLE_MOT_BLUR
    #define CAT_MB "Motion Blur"

    UI_FLOAT(CAT_MB, UI_MB_Mult, "Blur Mult", "Decrease/increase motion blur length", 0, 2, 1)

    #if CAN_COMPUTE && (V_MV_MODE > 0)
        UI_FLOAT(CAT_MB, UI_MB_Diff, "MV Correctness", "Only change if you know how to debug Motion Vectors", 0, 1, 0)
    #endif

    #if V_ENABLE_MOT_BLUR == 7
        #if CAN_COMPUTE
            UI_LIST(CAT_MB, UI_MB_DebugUseRepeat, "DB Use Repeating Pattern", "", "None\0Circle\0Long Line\0Short Line\0", 0)
        #endif

        UI_INT2(CAT_MB, UI_MB_DebugLen, "DB Length", "", -100, 100, 0)
        UI_FLOAT(CAT_MB, UI_MB_DebugZCen, "DB Depth Center", "", 0.0, 1.0, 0.0)
        UI_FLOAT(CAT_MB, UI_MB_DebugZRange, "DB Depth Range", "", 0.0, 1.0, 0.5)
        UI_BOOL(CAT_MB, UI_MB_DebugRev, "DB Reverse Background Blur", "", false)
    #endif
#endif

#if V_ENABLE_TAA
    #define CAT_TAA "Temporal AA"

    UI_FLOAT(CAT_TAA, UI_TAA_Alpha, "Frame Blend", "Higher values reduce blur, but reduce AA as well", 0.05, 1.0, 0.2)
    UI_FLOAT(CAT_TAA, UI_TAA_Sharpen, "Sharpening", "The amount of sharpening applied", 0.0, 1.0, 0.5)
#endif

UI_HELP(
_vort_MotionEffects_Help_,
"V_MV_MODE - [0 - 3]\n"
"0 - don't calculate motion vectors\n"
"1 - auto include my motion vectors (highly recommended)\n"
"2 - manually use iMMERSE motion vectors\n"
"3 - manually use other motion vectors (qUINT_of, qUINT_motionvectors, DRME, etc.)\n"
"\n"
"V_MV_USE_REST - [0 - 3]\n"
"0 - don't use REST addon for velocity\n"
"1 - use REST addon to get velocity in Unreal Engine games\n"
"2 - use REST addon to get velocity in CryEngine games\n"
"3 - use REST addon to get velocity in generic games\n"
"\n"
"V_MV_USE_HQ - 0 or 1\n"
"Enable high quality motion vectors at the cost of performance\n"
"\n"
"V_ENABLE_MOT_BLUR - 0 or 1\n"
"1 - enable Motion Blur\n"
"7 - debug motion blur\n"
"8 - debug tiles\n"
"9 - debug motion vectors\n"
"\n"
"V_ENABLE_TAA - 0 or 1\n"
"1 - enable TAA\n"
"9 - debug motion vectors\n"
"\n"
"V_USE_HW_LIN - 0 or 1\n"
"Toggle hardware linearization (better performance).\n"
"Disable if you have color issues due to some bug (like older REST versions).\n"
)
