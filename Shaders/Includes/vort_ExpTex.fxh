#pragma once
#include "Includes/vort_Defs.fxh"

texture2D ExpTexVort { Width = 256; Height = 256; MipLevels = 9; TEX_R32 };
sampler2D sExpTexVort { Texture = ExpTexVort; };
