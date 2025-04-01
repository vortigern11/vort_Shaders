#pragma once
#include "Includes/vort_Defs.fxh"

namespace HDR {
    texture2D ColorTex { TEX_SIZE(0) TEX_RGBA16 };
    sampler2D sColorTex { Texture = ColorTex; };
}
