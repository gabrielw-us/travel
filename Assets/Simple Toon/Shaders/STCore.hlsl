#ifndef STCORE_INCLUDED
#define STCORE_INCLUDED

#include "STFunctions.hlsl"

TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

// Single CBUFFER for all shared properties.
// Shaders that include this file must NOT redeclare these in their own CBUFFER.
CBUFFER_START(UnityPerMaterial)
    float4 _MainTex_ST;
    float4 _Color;
    float  _AmbientCol;
    float  _ColIntense;
    float  _ColBright;
    float  _Segmented;
    float  _Steps;
    float  _StpSmooth;
    float  _Offset;
    float  _Clipped;
    float  _MinLight;
    float  _MaxLight;
    float  _Lumin;
    float4 _ShnColor;
    float  _ShnOverlap;
    float  _ShnIntense;
    float  _ShnRange;
    float  _ShnSmooth;
    float4 _OtlColor;
    float  _OtlWidth;
CBUFFER_END

// ----------------------------------------------------------------------------
// Toon shading function — computes a 0..1 light value with stepped shading
// ----------------------------------------------------------------------------
float Toon(float ndotl, float atten, float maxAtten)
{
    float maxLight  = max(_MinLight, _MaxLight);
    float steps     = _Segmented > 0.5 ? _Steps : 1.0;
    float stpSmooth = _Segmented > 0.5 ? _StpSmooth : 1.0;

    float offset   = clamp(_Offset, -1.0, 1.0);
    float delta    = maxLight - _MinLight;

    // intensity
    float ints_pls = ndotl + offset;
    float ints_max = 1.0 + offset;
    float intense  = saturate(ints_pls / ints_max);

    // stepped lit value
    float step_sz = 1.0 / floor(steps);
    int   lit_num = (int)ceil(intense / step_sz);
    float lit     = lit_num * step_sz;

    // smoothing
    float reduce_v   = _Offset - 1.0;
    float reduce_res = 1.0 - saturate(reduce_v / 0.1);
    float reduce     = lit_num == 1 ? reduce_res : 1.0;

    float smth_start = lit - step_sz;
    float smth_end   = smth_start + step_sz * stpSmooth;

    float smth_lrp = invLerp01(smth_end, smth_start, intense, 0.0);
    float smth_stp = smoothstep_eq(smth_end, smth_start, intense, 0.0);

    float smooth_v = smoothlerp(smth_stp, smth_lrp, stpSmooth);
    float smooth   = saturate(lit - smooth_v * reduce * step_sz);

    // shadow attenuation
    float atten_inv = clamp(atten, 1.0 - maxAtten, 1.0);
    float dimLit    = smooth * atten_inv;
    float dim_dlt   = dimLit - _MinLight;

    // luminosity
    float lumLight = maxLight + _Lumin;
    float lum_dlt  = lumLight - _MinLight;

    // clipped mode
    float litd_clmp = saturate(dim_dlt);
    float clip_cf   = litd_clmp / max(delta, 0.0001);
    float clip_uncl = _MinLight + clip_cf * lum_dlt;
    float clip_v    = clamp(clip_uncl, _MinLight, lumLight);

    // relative mode
    float relate_v = _MinLight + lum_dlt * dimLit;

    return _Clipped > 0.5 ? clip_v : relate_v;
}

// ----------------------------------------------------------------------------
// Shine (specular highlight)
// ----------------------------------------------------------------------------
void PostShine(inout float4 col, float ndotl, float atten, float maxAtten)
{
    float pos_v    = abs(ndotl - 1.0);
    float len      = _ShnRange * 2.0;
    float smth_end = len * (1.0 - _ShnSmooth);

    float shine  = posz(len - pos_v);
    float smooth = smoothstep_eq(len, smth_end, pos_v, 1.0);
    float overlap = _ShnOverlap > 0.5 ? 1.0 : 0.0;
    float dim    = 1.0 - maxAtten * rev(atten) * rev(overlap);

    float blend = _ShnIntense * shine * smooth * dim;
    col = ColorBlend(col, _ShnColor, blend);
}

float4 PostEffects(float4 col, float toon, float atten, float maxAtten,
                   float NdotL, float NdotH, float VdotN, float FdotV)
{
    PostShine(col, NdotL, atten, maxAtten);
    return col;
}

#endif
