/*******************************************************************************
    Original author: Björn Ottosson
    Rewritten for ReShade: Vortigern

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

namespace OKColors
{
    // OKLAB colors can be outside of sRGB gamut

    float3 RGBToOKLAB(float3 c)
    {
        static const float3x3 lms_mat = float3x3(
            0.4122214708, 0.5363325363, 0.0514459929,
            0.2119034982, 0.6806995451, 0.1073969566,
            0.0883024619, 0.2817188376, 0.6299787005
        );

        float3 lms = POW(mul(lms_mat, c), A_THIRD);

        return float3(
            (0.2104542553 * lms.x) + (0.7936177850 * lms.y) - (0.0040720468 * lms.z),
            (1.9779984951 * lms.x) - (2.4285922050 * lms.y) + (0.4505937099 * lms.z),
            (0.0259040371 * lms.x) + (0.7827717662 * lms.y) - (0.8086757660 * lms.z)
        );
    }

    float3 OKLABToRGB(float3 lab)
    {
        float3 lms = float3(
            lab.x + (0.3963377774 * lab.y) + (0.2158037573 * lab.z),
            lab.x - (0.1055613458 * lab.y) - (0.0638541728 * lab.z),
            lab.x - (0.0894841775 * lab.y) - (1.2914855480 * lab.z)
        );

        lms = lms * lms * lms;

        return float3(
            (+4.0767416621 * lms.x) - (3.3077115913 * lms.y) + (0.2309699292 * lms.z),
            (-1.2684380046 * lms.x) + (2.6097574011 * lms.y) - (0.3413193965 * lms.z),
            (-0.0041960863 * lms.x) - (0.7034186147 * lms.y) + (1.7076147010 * lms.z)
        );
    }

    float3 RGBToOKLCH(float3 c)
    {
        float3 lab = RGBToOKLAB(c);
        float chroma = length(lab.yz);
        float hue = chroma > 0.0 ? atan2(lab.z, lab.y) : 0.0;

        hue = (hue + PI) / DOUBLE_PI; // custom

        return float3(lab.x, chroma, hue);
    }

    float3 OKLCHToRGB(float3 lch)
    {
        float hue = lch.z * DOUBLE_PI - PI; // custom
        float chroma = lch.y;

        float a = chroma * cos(hue);
        float b = chroma * sin(hue);

        return OKLABToRGB(float3(lch.x, a, b));
    }

    /*******************************************************************************
       Color spaces for 1:1 conversion to sRGB and back

       | Property                 | OKHSV   | OKHSL |
       | -                        | -       | -     |
       | Orthogonal Lightness     | no      | yes   | (Hue/Chroma/Saturation can be altered, while keeping perceived Lightness constant)
       | Orthogonal Chroma        | no      | no    | (Lightness/Hue can be altered, while keeping perceived Chroma constant)
       | Orthogonal Saturation    | partial | no    | (Lightness/Hue can be altered, while keeping perceived Saturation constant)
       | Orthogonal Hue           | yes     | yes   | (Lightness/Chroma/Saturation can be altered, while keeping perceived Hue constant)
       | Simple Geometrical Shape | yes     | yes   | (Colors conversions can't lead to results outside of sRGB gamut)
       | Max Chroma at Edge       | yes     | no    | (The strongest color of a hue is at the shape's edge)
       | Varies Smoothly          | yes     | yes   | (No abrupt changes)
       | Varies Evenly            | no      | no    | (Uniform changes across all colors)
    *******************************************************************************/

    // Finds the maximum saturation possible for a given hue that fits in sRGB
    // Saturation here is defined as S = C/L
    // a and b must be normalized so a^2 + b^2 == 1

    float ComputeMaxSaturation(float a, float b)
    {
        float k0, k1, k2, k3, k4;
        float3 wlms;

        // Select different coefficients depending on which component goes below zero first
        if (-1.88170328 * a - 0.80936493 * b > 1.0)
        {
            // Red component
            k0 = +1.19086277; k1 = +1.76576728; k2 = +0.59662641; k3 = +0.75515197; k4 = +0.56771245;
            wlms = float3(+4.0767416621, -3.3077115913, +0.2309699292);
        }
        else if (1.81444104 * a - 1.19445276 * b > 1.0)
        {
            // Green component
            k0 = +0.73956515; k1 = -0.45954404; k2 = +0.08285427; k3 = +0.12541070; k4 = +0.14503204;
            wlms = float3(-1.2684380046, +2.6097574011, -0.3413193965);
        }
        else
        {
            // Blue component
            k0 = +1.35733652; k1 = -0.00915799; k2 = -1.15130210; k3 = -0.50559606; k4 = +0.00692167;
            wlms = float3(-0.0041960863, -0.7034186147, +1.7076147010);
        }

        // Approximate max saturation using a polynomial:
        float S = k0 + (k1 * a) + (k2 * b) + (k3 * a * a) + (k4 * a * b);

        // Do one step Halley's method to get closer
        // this gives an error less than 10e6, except for some blue hues where the dS/dh is close to infinite
        // this should be sufficient for most applications, otherwise do two/three steps

        float3 k_lms = float3(
            (+0.3963377774 * a) + (0.2158037573 * b),
            (-0.1055613458 * a) - (0.0638541728 * b),
            (-0.0894841775 * a) - (1.2914855480 * b)
        );

        float3 lms_pre = 1.0 + S * k_lms;
        float3 lms = lms_pre * (lms_pre * lms_pre);
        float3 lms_dS = (3.0 * k_lms) * (lms_pre * lms_pre);
        float3 lms_dS2 = (6.0 * k_lms) * (k_lms * lms_pre);

        float f = dot(wlms, lms);
        float f1 = dot(wlms, lms_dS);
        float f2 = dot(wlms, lms_dS2);

        S = S - f * f1 / (f1 * f1 - 0.5 * f * f2);

        return S;
    }

    // finds L_cusp and C_cusp for a given hue
    // a and b must be normalized so a^2 + b^2 == 1
    float2 FindCusp(float a, float b)
    {
        // First, find the maximum saturation (saturation S = C/L)
        float S_cusp = ComputeMaxSaturation(a, b);

        float3 rgb_at_max = OKLABToRGB(float3(1, S_cusp * a, S_cusp * b));
        float L_cusp = POW(RCP(Max3(rgb_at_max)), A_THIRD);

        return float2(L_cusp, L_cusp * S_cusp);
    }

    // Finds intersection of the line defined by
    // L = L0 * (1 - t) + t * L1;
    // C = t * C1;
    // a and b must be normalized so a^2 + b^2 == 1
    float FindGamutIntersect(float a, float b, float L1, float C1, float L0, float2 cusp)
    {
        // cusp.x = L cusp.y = C

        static const float3x3 rgb_mat = float3x3(
            +4.0767416621, -3.3077115913, +0.2309699292,
            -1.2684380046, +2.6097574011, -0.3413193965,
            -0.0041960863, -0.7034186147, +1.7076147010
        );

        // Find the intersection for upper and lower half seprately
        float t;

        if (((L1 - L0) * cusp.y - (cusp.x - L0) * C1) <= 0.0)
        {
            // Lower half

            t = cusp.y * L0 / (C1 * cusp.x + cusp.y * (L0 - L1));
        }
        else
        {
            // Upper half

            // First intersect with triangle
            t = cusp.y * (L0 - 1.0) / (C1 * (cusp.x - 1.0) + cusp.y * (L0 - L1));

            float2 dLC = float2(L1 - L0, C1);

            float3 k_lms = float3(
                +0.3963377774 * a + 0.2158037573 * b,
                -0.1055613458 * a - 0.0638541728 * b,
                -0.0894841775 * a - 1.2914855480 * b
            );

            float3 lms_dt = dLC.x + dLC.y * k_lms;

            float2 LC = float2(L0 * (1.0 - t) + t * L1, t * C1);
            float3 lms_pre = LC.x + LC.y * k_lms;
            float3 lms = lms_pre * lms_pre * lms_pre;
            float3 lmsdt = 3 * lms_dt * lms_pre;
            float3 lmsdt2 = 6 * lms_dt * lms_dt * lms_pre;

            float3 rgb = mul(rgb_mat, lms) - 1.0;
            float3 rgb1 = mul(rgb_mat, lmsdt);
            float3 rgb2 = mul(rgb_mat, lmsdt2);

            float3 u_rgb = rgb1 / (rgb1 * rgb1 - 0.5 * rgb * rgb2);
            float3 t_rgb = u_rgb >= 0.0 ? -rgb * u_rgb : FLOAT_MAX;

            t += Min3(t_rgb);
        }

        return t;
    }

    float Toe(float x)
    {
        static const float k_1 = 0.206;
        static const float k_2 = 0.03;
        static const float k_3 = (1.0 + k_1) / (1.0 + k_2);

        return 0.5 * (k_3 * x - k_1 + sqrt((k_3 * x - k_1) * (k_3 * x - k_1) + 4 * k_2 * k_3 * x));
    }

    float InvToe(float x)
    {
        static const float k_1 = 0.206;
        static const float k_2 = 0.03;
        static const float k_3 = (1.0 + k_1) / (1.0 + k_2);

        return (x * x + k_1 * x) / (k_3 * (x + k_2));
    }

    float2 ToST(float2 cusp)
    {
        return float2(cusp.y / cusp.x, cusp.y / (1.0 - cusp.x));
    }

    // Returns a smooth approximation of the location of the cusp
    // This polynomial was created by an optimization process
    // It has been designed so that S_mid < S_max and T_mid < T_max
    float2 GetSTMid(float a_pre, float b_pre)
    {
        float S = 0.11516993 + 1.0 / (
            +7.44778970 + 4.15901240 * b_pre
            + a_pre * (-2.19557347 + 1.75198401 * b_pre
            + a_pre * (-2.13704948 - 10.02301043 * b_pre
            + a_pre * (-4.24894561 + 5.38770819 * b_pre + 4.69891013 * a_pre
            ))));

        float T = 0.11239642 + 1.0 / (
            +1.61320320 - 0.68124379 * b_pre
            + a_pre * (+0.40370612 + 0.90148123 * b_pre
            + a_pre * (-0.27087943 + 0.61223990 * b_pre
            + a_pre * (+0.00299215 - 0.45399568 * b_pre - 0.14661872 * a_pre
            ))));

        return float2(S, T);
    }

    float3 GetCS(float L, float a_pre, float b_pre)
    {
        float2 cusp = FindCusp(a_pre, b_pre);

        float C_max = FindGamutIntersect(a_pre, b_pre, L, 1, L, cusp);
        float2 ST_max = ToST(cusp);
        float2 ST_mid = GetSTMid(a_pre, b_pre);
        float C_a = 0;
        float C_b = 0;

        // Scale factor to compensate for the curved part of gamut shape:
        float k = C_max / min((L * ST_max.x), (1 - L) * ST_max.y);

        // Use a soft minimum function, instead of a sharp triangle shape to get a smooth value for chroma.
        C_a = L * ST_mid.x;
        C_b = (1.0 - L) * ST_mid.y;

        float C_mid = 0.9 * k * sqrt(RSQRT(RCP(C_a * C_a * C_a * C_a) + RCP(C_b * C_b * C_b * C_b)));

        // for C_0, the shape is independent of hue, so ST are constant. Values picked to roughly be the average values of ST.
        C_a = L * 0.4;
        C_b = (1.0 - L) * 0.8;

        // Use a soft minimum function, instead of a sharp triangle shape to get a smooth value for chroma.
        float C_0 = RSQRT(RCP(C_a * C_a) + RCP(C_b * C_b));

        return float3(C_0, C_mid, C_max);
    }

    float3 OKHSLToRGB(float3 hsl)
    {
        if (hsl.z == 0.0 || hsl.z == 1.0) return hsl.zzz;

        float a_pre = cos(DOUBLE_PI * hsl.x);
        float b_pre = sin(DOUBLE_PI * hsl.x);
        float L = InvToe(hsl.z);

        float3 cs = GetCS(L, a_pre, b_pre);
        float C_0 = cs.x;
        float C_mid = cs.y;
        float C_max = cs.z;

        static const float mid = 0.8;
        static const float mid_inv = 1.25;

        float C;

        if (hsl.y < mid)
        {
            float t = mid_inv * hsl.y;
            float k_1 = mid * C_0;
            float k_2 = (1.0 - k_1 / C_mid);

            C = t * k_1 / (1.0 - k_2 * t);
        }
        else
        {
            float t = (hsl.y - mid)/ (1 - mid);
            float k_0 = C_mid;
            float k_1 = (1.0 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0;
            float k_2 = (1.0 - (k_1) / (C_max - C_mid));

            C = k_0 + t * k_1 / (1.0 - k_2 * t);
        }

        return OKLABToRGB(float3(L, C * a_pre, C * b_pre));
    }

    float3 RGBToOKHSL(float3 rgb)
    {
        float3 lab = RGBToOKLAB(rgb);

        float C = length(lab.yz);
        float a_pre = lab.y / C;
        float b_pre = lab.z / C;

        float L = lab.x;
        float h = 0.5 + 0.5 * atan2(-lab.z, -lab.y) / PI;

        float3 cs = GetCS(L, a_pre, b_pre);
        float C_0 = cs.x;
        float C_mid = cs.y;
        float C_max = cs.z;

        // Inverse of the interpolation in OKHSLToRGB:

        static const float mid = 0.8;
        static const float mid_inv = 1.25;

        float s;

        if (C < C_mid)
        {
            float k_1 = mid * C_0;
            float k_2 = (1.0 - k_1 / C_mid);
            float t = C / (k_1 + k_2 * C);

            s = t * mid;
        }
        else
        {
            float k_0 = C_mid;
            float k_1 = (1.0 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0;
            float k_2 = (1.0 - (k_1) / (C_max - C_mid));
            float t = (C - k_0) / (k_1 + k_2 * (C - k_0));

            s = mid + (1.0 - mid) * t;
        }

        float l = Toe(L);

        return float3(h, s, l);
    }

    float3 OKHSVToRGB(float3 hsv)
    {
        float a_pre = cos(DOUBLE_PI * hsv.x);
        float b_pre = sin(DOUBLE_PI * hsv.x);

        float2 cusp = FindCusp(a_pre, b_pre);
        float2 ST_max = ToST(cusp);
        float S_0 = 0.5;
        float k = 1 - S_0 / ST_max.x;

        // first we compute L and V as if the gamut is a perfect triangle:

        // L, C when v==1:
        float L_v = 1 -        hsv.y * S_0 / (S_0 + ST_max.y - ST_max.y * k * hsv.y);
        float C_v = hsv.y * ST_max.y * S_0 / (S_0 + ST_max.y - ST_max.y * k * hsv.y);

        float L = hsv.z * L_v;
        float C = hsv.z * C_v;

        // then we compensate for both toe and the curved top part of the triangle:
        float L_vt = InvToe(L_v);
        float C_vt = C_v * L_vt / L_v;

        float L_new = InvToe(L);
        C = C * L_new / L;
        L = L_new;

        float3 rgb_scale = OKLABToRGB(float3(L_vt, a_pre * C_vt, b_pre * C_vt));
        float scale_L = POW(RCP(max(0.0, Max3(rgb_scale))), A_THIRD);

        L = L * scale_L;
        C = C * scale_L;

        return OKLABToRGB(float3(L, C * a_pre, C * b_pre));
    }

    float3 RGBToOKHSV(float3 rgb)
    {
        float3 lab = RGBToOKLAB(rgb);

        float C = length(lab.yz);
        float a_pre = lab.y / C;
        float b_pre = lab.z / C;

        float L = lab.x;
        float h = 0.5 + 0.5 * atan2(-lab.z, -lab.y) / PI;

        float2 cusp = FindCusp(a_pre, b_pre);
        float2 ST_max = ToST(cusp);
        float S_0 = 0.5;
        float k = 1 - S_0 / ST_max.x;

        // first we find L_v, C_v, L_vt and C_vt

        float t = ST_max.y / (C + L * ST_max.y);
        float L_v = t * L;
        float C_v = t * C;

        float L_vt = InvToe(L_v);
        float C_vt = C_v * L_vt / L_v;

        // we can then use these to invert the step that compensates for the toe and the curved top part of the triangle:
        float3 rgb_scale = OKLABToRGB(float3(L_vt, a_pre * C_vt, b_pre * C_vt));
        float scale_L = POW(RCP(max(0.0, Max3(rgb_scale))), A_THIRD);

        L = L / scale_L;
        C = C / scale_L;

        float toe = Toe(L);

        C = C * toe / L;
        L = toe;

        // we can now compute v and s:

        float v = L / L_v;
        float s = (S_0 + ST_max.y) * C_v / ((ST_max.y * S_0) + ST_max.y * k * C_v);

        return float3(h, s, v);
    }
}
