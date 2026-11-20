#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy;
uniform vec4 uTint;
uniform float uBass;
uniform float uMids;
uniform float uHighs;
uniform float uTransient;
uniform vec4 uBands0;
uniform vec4 uBands1;
uniform vec4 uBands2;
out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float noise2(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 4; i++) { v += noise2(p) * a; p = p * 2.02 + vec2(17.7); a *= 0.48; }
  return v;
}
float bandAt(int index) {
  if (index == 0) return uBands0.x;
  if (index == 1) return uBands0.y;
  if (index == 2) return uBands0.z;
  if (index == 3) return uBands0.w;
  if (index == 4) return uBands1.x;
  if (index == 5) return uBands1.y;
  if (index == 6) return uBands1.z;
  if (index == 7) return uBands1.w;
  if (index == 8) return uBands2.x;
  if (index == 9) return uBands2.y;
  if (index == 10) return uBands2.z;
  return uBands2.w;
}
float spectrumAt(float x) {
  float position = clamp(x, 0.0, 0.999) * 12.0;
  int index = int(floor(position));
  int nextIndex = index + 1;
  if (nextIndex > 11) nextIndex = 11;
  return mix(bandAt(index), bandAt(nextIndex), fract(position));
}
void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  float t = uTime;
  float bass = clamp(uBass, 0.0, 1.0);
  float mids = clamp(uMids, 0.0, 1.0);
  float highs = clamp(uHighs, 0.0, 1.0);
  vec3 base = max(uTint.rgb, vec3(0.02));
  vec3 cool = mix(base, vec3(0.22, 0.82, 0.96), 0.42);
  vec3 warm = mix(base, vec3(0.78, 0.43, 1.0), 0.34);
  float n = fbm(vec2(uv.x * 3.2, uv.y * 2.5 + t * 0.035));
  float sway = sin(uv.x * 8.5 + n * 3.2 - t * 0.10) * 0.055 +
               sin(uv.x * 17.0 - t * 0.065) * 0.018;
  float curtainPhase = uv.x * 23.0 + sin(uv.x * 5.0 + t * 0.07) * 2.0 + n * 2.4;
  float folds = 0.5 + 0.5 * sin(curtainPhase + t * 0.045);
  float ridges = exp(-abs(sin(curtainPhase * 0.72 + uv.y * 1.8)) * (8.0 + highs * 2.0));
  float curtainTop = 0.10 + 0.12 * sin(uv.x * 5.0 + t * 0.055) + sway * 0.35;
  float curtainBottom = 0.91 + 0.035 * sin(uv.x * 7.0 - t * 0.04);
  float upperFade = smoothstep(curtainTop, curtainTop + 0.20, uv.y);
  float lowerFade = 1.0 - smoothstep(curtainBottom - 0.12, curtainBottom, uv.y);
  float vertical = upperFade * lowerFade;
  float localBand = spectrumAt(uv.x);
  float body = vertical * (0.20 + folds * 0.28 + ridges * 0.42 + n * 0.13 + localBand * 0.16);
  float filament = exp(-abs(sin(curtainPhase * 1.45 + uv.y * 2.2)) * 42.0) * vertical;
  float shaft = exp(-pow((uv.x - (0.18 + 0.64 * folds)) * 15.0, 2.0)) * (1.0 - uv.y) * 0.20;
  float horizon = exp(-pow((uv.y - 0.91) * 22.0, 2.0)) * 0.22;
  float glow = exp(-length(vec2((uv.x - 0.5) * 0.72, (uv.y - 0.82) * 2.2)) * 4.0);
  vec3 color = mix(cool, warm, smoothstep(0.08, 0.92, uv.x + n * 0.18));
  color *= 0.55 + folds * 0.48;
  color += vec3(0.32, 0.72, 1.0) * (filament * (0.32 + highs * 0.25) + shaft * 0.35);
  color += vec3(0.58, 0.36, 1.0) * ridges * vertical * 0.18;
  color += base * (glow * (0.18 + bass * 0.12) + horizon * 0.28);
  color += vec3(0.78, 0.91, 1.0) * uTransient * filament * 0.32;
  vec2 starGrid = uv * vec2(92.0, 24.0);
  vec2 starCell = floor(starGrid);
  vec2 starLocal = fract(starGrid) - 0.5;
  float starSeed = hash21(starCell);
  float starRadius = mix(0.045, 0.15, hash21(starCell + 7.3));
  float starDot = 1.0 - smoothstep(starRadius, starRadius + 0.045, length(starLocal));
  float star = starDot * smoothstep(0.992, 1.0, starSeed) *
      (0.35 + 0.65 * sin(t * 0.5 + starSeed * 80.0));
  float alpha = clamp(body * 0.82 + filament * (0.36 + uTransient * 0.12) + shaft * 0.18 + horizon * 0.24 + star * 0.55, 0.0, 0.94);
  alpha *= 0.72 + uEnergy * 0.22;
  color += vec3(0.82, 0.94, 1.0) * star * 0.8;
  fragColor = vec4(color * alpha, alpha);
}
