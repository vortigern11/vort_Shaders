#pragma once
#include "Includes/vort_Defs.fxh"

texture2D LDRTexVort : COLOR;
sampler2D sLDRTexVort { Texture = LDRTexVort; SRGB_READ_ENABLE };
