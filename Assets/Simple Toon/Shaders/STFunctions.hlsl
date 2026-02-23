#ifndef STFUNCTIONS_INCLUDED
#define STFUNCTIONS_INCLUDED

float clamp01(float value) { return saturate(value); }
float rev(float value)     { return 1.0 - value; }
float rev01(float value)   { return saturate(rev(value)); }
float posz(float value)    { return value >= 0 ? 1 : 0; }
float negz(float value)    { return value <= 0 ? 1 : 0; }

float lerp01(float from, float to, float value) {
    return saturate(lerp(from, to, value));
}

float invLerp(float from, float to, float value, float equal) {
    float val = (value - from) / (to - from);
    return from == to ? equal : val;
}

float invLerp01(float from, float to, float value, float equal) {
    float val = invLerp(from, to, value, equal);
    return from == to ? val : saturate(val);
}

// smoothstep overload with equal fallback (avoids shadowing HLSL built-in)
float smoothstep_eq(float from, float to, float value, float equal) {
    float val = smoothstep(from, to, value);
    return from == to ? equal : val;
}

float smoothlerp(float from, float to, float value) {
    float val = -(2.0 / ((value + 0.34) * 4.7)) + 1.3;
    return lerp01(from, to, val);
}

float4 ColorBlend(float4 tcol, float4 dcol, float blendf) {
    return lerp(tcol, dcol, blendf);
}

#endif
