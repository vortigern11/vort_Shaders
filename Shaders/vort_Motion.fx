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

#include "Includes/vort_Defs.fxh"
#include "Includes/vort_Motion_UI.fxh"
#include "Includes/vort_MotionUtils.fxh"

#if V_MV_MODE == 1
    #include "Includes/vort_MotionVectors.fxh"
#endif

#if V_ENABLE_MOT_BLUR
    #if USE_HQ_MB
        #include "Includes/vort_MotionBlur.fxh"
    #else
        #include "Includes/vort_MotionBlur_DX9.fxh"
    #endif
#endif

#if V_ENABLE_TAA
    #include "Includes/vort_TAA.fxh"
#endif

/*******************************************************************************
    Techniques
*******************************************************************************/

technique vort_Motion
{
    #if V_MV_MODE == 1
        PASS_MV
    #endif

    #if V_MV_DEBUG
        PASS_MV_DEBUG
    #else
        #if V_ENABLE_MOT_BLUR
            PASS_MOT_BLUR
        #endif

        #if V_ENABLE_TAA
            PASS_TAA
        #endif
    #endif
}
