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
  float v = 0.0, a = 0.52;
  for (int i = 0; i < 4; i++) { v += noise2(p) * a; p = p * 2.02 + 17.1; a *= 0.47; }
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
  float bass = clamp(uBass, 0.0, 1.0), mids = clamp(uMids, 0.0, 1.0), highs = clamp(uHighs, 0.0, 1.0);
  float energy = clamp(uEnergy, 0.0, 1.0);
  vec2 p = vec2((uv.x - 0.5) * 2.0, (uv.y - 0.5) * 1.86);
  float broad = fbm(p * 2.6 + vec2(t * 0.035, -t * 0.026));
  float middle = fbm(p * 6.0 - vec2(t * 0.027, t * 0.031));
  float fine = fbm(p * 13.0 + vec2(middle, -broad));
  float envelope = pow(max(0.0, 1.0 - pow(abs(p.x), 3.2)), 0.44);
  float centerLine = 0.055 * sin(p.x * 4.0 + t * 0.045) + 0.025 * sin(p.x * 10.0 - t * 0.035);
  centerLine += (broad - 0.5) * 0.10 + (middle - 0.5) * 0.035;
  float localBand = spectrumAt(uv.x);
  float thickness = envelope * (0.66 + 0.055 * sin(p.x * 7.0 + t * 0.04) + bass * 0.045 + localBand * 0.035);
  float folded = (fine - 0.5) * 0.09 + (middle - 0.5) * 0.055;
  float signedSurface = abs(p.y - centerLine - folded) - thickness;
  float edge = 1.0 - smoothstep(-0.025, 0.055, signedSurface);
  float interior = 1.0 - smoothstep(-0.48, -0.05, signedSurface);
  float surfaceHeight = centerLine + folded + (broad - 0.5) * 0.06 + sin(p.x * 12.0 + middle * 4.0) * 0.018;
  // Analytic slope approximation keeps the lighting portable across Flutter
  // runtime shader backends without relying on derivative extensions.
  float slopeX = cos(p.x * 12.0 + middle * 4.0) * 0.22 +
                 cos(p.x * 7.0 + t * 0.04) * 0.11;
  float slopeY = cos(p.y * 10.0 + fine * 3.0) * 0.08;
  vec3 normal = normalize(vec3(-slopeX, -slopeY, 1.0));
  vec3 lightDir = normalize(vec3(-0.42, -0.52, 0.74));
  vec3 viewDir = vec3(0.0, 0.0, 1.0);
  vec3 halfDir = normalize(lightDir + viewDir);
  float diffuse = max(dot(normal, lightDir), 0.0);
  float specular = pow(max(dot(normal, halfDir), 0.0), 34.0) * (0.35 + highs * 0.55);
  float rim = exp(-abs(signedSurface) * (34.0 + bass * 10.0));
  float folds = exp(-abs(sin(p.x * 11.0 + middle * 5.0 + p.y * 4.0)) * 12.0);
  float veins = pow(max(0.0, sin(p.x * 19.0 + fine * 13.0 - p.y * 9.0)), 16.0);
  float caustic = pow(max(0.0, sin((broad * 2.4 + middle) * 22.0 - t * 0.18)), 18.0);
  vec3 base = max(uTint.rgb, vec3(0.02));
  vec3 deep = mix(base * 0.20, vec3(0.025, 0.06, 0.13), 0.24);
  vec3 bodyColor = mix(deep, base, 0.46 + middle * 0.30);
  bodyColor = mix(bodyColor, vec3(0.52, 0.80, 0.98), folds * 0.18 + veins * 0.08);
  bodyColor *= 0.42 + diffuse * 0.72 + interior * 0.20;
  bodyColor += vec3(0.62, 0.88, 1.0) * (specular * 0.92 + rim * (0.22 + uTransient * 0.36));
  bodyColor += vec3(0.50, 0.70, 1.0) * (caustic * 0.12 + veins * 0.10);
  bodyColor -= deep * (1.0 - folds) * interior * 0.12;
  float sideFade = smoothstep(0.0, 0.10, uv.x) * (1.0 - smoothstep(0.90, 1.0, uv.x));
  float verticalFade = smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.88, 1.0, uv.y));
  float alpha = edge * (0.56 + interior * 0.24) + rim * 0.20 + specular * edge * 0.22;
  alpha *= sideFade * verticalFade * (0.72 + energy * 0.22);
  alpha = clamp(alpha, 0.0, 0.96);
  fragColor = vec4(clamp(bodyColor, 0.0, 1.35) * alpha, alpha);
}
