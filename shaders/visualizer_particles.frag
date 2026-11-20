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
  p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y);
}
float noise2(vec2 p) {
  vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 4; i++) { v += noise2(p) * a; p = p * 2.03 + vec2(13.1); a *= 0.48; }
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
  vec2 p = (uv - 0.5) * vec2(1.0, 1.72);
  float t = uTime;
  float bass = clamp(uBass, 0.0, 1.0), mids = clamp(uMids, 0.0, 1.0), highs = clamp(uHighs, 0.0, 1.0);
  float angle = atan(p.y, p.x);
  float radius = length(p);
  float turbulence = fbm(p * 8.0 + vec2(t * 0.025, -t * 0.018));
  float spiral = sin(angle * 3.0 - log(radius + 0.12) * 5.8 + t * 0.055 + turbulence * 2.2);
  float arm = exp(-abs(spiral) * (2.8 + radius * 2.0));
  float disk = exp(-pow((p.y + 0.035 * sin(p.x * 5.0 + t * 0.03)) * 8.0, 2.0)) * (1.0 - smoothstep(0.20, 0.76, abs(p.x)));
  float localBand = spectrumAt(fract(angle / 6.2831853));
  float core = exp(-radius * (13.0 - bass * 2.0));
  float nebula = fbm(p * 5.5 + vec2(t * 0.018, -t * 0.014));
  float dustLane = exp(-abs(sin(angle * 3.0 - log(radius + 0.15) * 5.8 + turbulence)) * 16.0) * smoothstep(0.12, 0.42, radius);
  vec3 base = max(uTint.rgb, vec3(0.025));
  vec3 violet = mix(base, vec3(0.54, 0.32, 1.0), 0.58);
  vec3 cyan = mix(base, vec3(0.20, 0.82, 1.0), 0.55);
  vec3 cloudColor = mix(violet, cyan, smoothstep(0.18, 0.82, uv.x + nebula * 0.2));
  float cloud = (arm * (0.30 + localBand * 0.18) + disk * 0.25 + nebula * 0.12) * (1.0 - smoothstep(0.12, 0.95, radius));
  vec3 color = cloudColor * cloud * (0.42 + mids * 0.35);
  color += cloudColor * dustLane * (0.12 + highs * 0.16);
  color += vec3(1.0, 0.78, 0.52) * core * (0.62 + bass * 0.32);
  color += vec3(0.44, 0.70, 1.0) * exp(-radius * 5.0) * 0.12;

  // Deterministic multi-scale star catalogue: fine dust, medium stars, rare giants.
  vec2 fineGrid = uv * vec2(142.0, 40.0);
  vec2 fineCell = floor(fineGrid);
  float fineHash = hash21(fineCell);
  float fineRadius = mix(0.055, 0.20, hash21(fineCell + 8.7));
  float fineDot = 1.0 - smoothstep(fineRadius, fineRadius + 0.045,
                                   length(fract(fineGrid) - 0.5));
  float fineStar = fineDot * smoothstep(0.994, 1.0, fineHash);
  vec2 midGrid = uv * vec2(58.0, 16.0);
  vec2 midCell = floor(midGrid);
  float midHash = hash21(midCell + 31.4);
  float midRadius = mix(0.07, 0.20, hash21(midCell + 14.2));
  float midDot = 1.0 - smoothstep(midRadius, midRadius + 0.055,
                                  length(fract(midGrid) - 0.5));
  float midStar = midDot * smoothstep(0.986, 1.0, midHash);
  float twinkle = 0.62 + 0.38 * sin(t * (0.8 + midHash * 1.8) + midHash * 80.0);
  float star = fineStar * 0.36 + midStar * twinkle;
  float flare = pow(max(0.0, 1.0 - length((uv - vec2(0.5, 0.5)) * vec2(1.2, 2.0)) * 5.0), 8.0);
  color += vec3(0.72, 0.86, 1.0) * star * (0.55 + highs * 0.28);
  color += vec3(1.0, 0.92, 0.76) * flare * (0.35 + uTransient * 0.28);
  float alpha = clamp(cloud * 0.76 + core * 0.50 + star * 0.72 + flare * 0.18, 0.0, 0.96);
  alpha *= 0.72 + uEnergy * 0.24;
  fragColor = vec4(color * alpha, alpha);
}
