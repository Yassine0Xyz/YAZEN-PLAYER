#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy;
uniform vec4 uTint;
uniform float uBass;
uniform float uMids;
uniform float uHighs;
uniform float uTransient;

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.52;
  for (int i = 0; i < 4; i++) {
    value += noise2(p) * amplitude;
    p = p * 2.02 + vec2(13.7, 9.1);
    amplitude *= 0.48;
  }
  return value;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv - 0.5;
  p.x *= uSize.x / max(uSize.y, 1.0);
  float t = uTime;
  float bass = clamp(uBass, 0.0, 1.0);
  float mids = clamp(uMids, 0.0, 1.0);
  float highs = clamp(uHighs, 0.0, 1.0);
  float hit = clamp(uTransient, 0.0, 1.0);
  float energy = clamp(uEnergy, 0.0, 1.0);

  // A large, continuous liquid body with two counter-rotating folds.
  vec2 warp = vec2(
    fbm(p * 2.8 + vec2(t * 0.075, -t * 0.052)),
    fbm(p * 3.1 + vec2(-t * 0.061, t * 0.083))
  );
  vec2 q = p * 2.15 + (warp - 0.5) * (1.12 + mids * 0.28);
  float broad = fbm(q * 2.1 + vec2(t * 0.10, -t * 0.065));
  float middle = fbm(q * 4.0 - vec2(t * 0.072, t * 0.095));
  float fine = fbm(q * 7.2 + vec2(middle, -broad) * 1.55);
  float marble = broad * 0.52 + middle * 0.31 + fine * 0.17;

  float foldA = abs(p.y - (0.11 * sin(p.x * 3.6 - t * 0.32) + (broad - 0.5) * 0.28));
  float foldB = abs(p.y - (-0.13 * sin(p.x * 5.1 + t * 0.24) + (middle - 0.5) * 0.31));
  float foldC = abs(p.y - (0.035 * sin(p.x * 8.2 - t * 0.19) + (fine - 0.5) * 0.19));
  float ridgeA = exp(-foldA * (13.0 + bass * 5.0));
  float ridgeB = exp(-foldB * 17.0);
  float ridgeC = exp(-foldC * 25.0);
  float body = smoothstep(0.31 - bass * 0.045, 0.72, marble + ridgeA * 0.18 + ridgeB * 0.12);
  float edge = pow(clamp(ridgeA * 0.56 + ridgeB * 0.34 + ridgeC * 0.24, 0.0, 1.0), 1.35);

  // Palette is derived from the active artwork color; no fixed cyan/magenta theme.
  vec3 base = max(uTint.rgb, vec3(0.015));
  vec3 deep = mix(base, vec3(dot(base, vec3(0.30, 0.42, 0.28))), 0.38);
  vec3 lightTone = mix(base, vec3(1.0), 0.46);
  vec3 shadowTone = mix(deep, base * 0.34, 0.48);
  float hueFlow = clamp(uv.x * 0.46 + broad * 0.34 + fine * 0.20, 0.0, 1.0);
  vec3 palette = mix(shadowTone, base, smoothstep(0.08, 0.58, hueFlow));
  palette = mix(palette, lightTone, smoothstep(0.54, 0.96, hueFlow) * 0.76);

  float caustic = pow(max(0.0, sin((broad * 1.8 + middle) * 19.0 - t * 0.48)), 14.0);
  float microLight = pow(max(0.0, sin(uv.x * 28.0 + fine * 13.0 - t * 0.61)), 17.0);
  float rim = edge * (0.36 + mids * 0.24 + hit * 0.38);
  float specular = caustic * (0.12 + highs * 0.22) + microLight * 0.11;
  float volume = body * (0.22 + bass * 0.15) + ridgeB * 0.085;
  float sideFade = smoothstep(0.0, 0.075, uv.x) * (1.0 - smoothstep(0.925, 1.0, uv.x));
  float verticalFade = smoothstep(0.0, 0.10, uv.y) * (1.0 - smoothstep(0.91, 1.0, uv.y));
  float alpha = clamp((volume + rim * 0.70 + specular * 0.56) * sideFade * verticalFade, 0.0, 0.90) * uTint.a;
  vec3 color = palette * (0.32 + volume * 1.42);
  color += lightTone * (rim * 0.72 + specular * 0.92);
  color += deep * (ridgeC * 0.12 + energy * edge * 0.08);
  color = clamp(color, vec3(0.0), vec3(1.35));
  fragColor = vec4(color * alpha, alpha);
}
