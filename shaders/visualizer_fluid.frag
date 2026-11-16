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
  float amplitude = 0.5;
  for (int i = 0; i < 4; i++) {
    value += noise2(p) * amplitude;
    p = p * 2.03 + vec2(17.1, 9.2);
    amplitude *= 0.5;
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

  // Layered advection: the two counter-rotating fields create fluid-like folds.
  vec2 flow = vec2(
    fbm(p * 3.0 + vec2(t * 0.10, -t * 0.06)),
    fbm(p * 3.2 + vec2(-t * 0.07, t * 0.09))
  );
  vec2 q = p * (2.7 + bass * 0.32) + (flow - 0.5) * (1.1 + mids * 0.35);
  float fieldA = fbm(q * 2.2 + vec2(t * 0.13, -t * 0.08));
  float fieldB = fbm(q * 3.8 - vec2(t * 0.09, t * 0.12));
  float folds = fbm(q * 6.0 + vec2(fieldB, -fieldA) * 1.8);
  float marbling = fieldA * 0.48 + fieldB * 0.34 + folds * 0.18;

  float ribbon1 = exp(-abs(p.y - (0.13 * sin(p.x * 4.0 - t * 0.45) + (fieldA - 0.5) * 0.25)) * (12.0 + bass * 7.0));
  float ribbon2 = exp(-abs(p.y - (-0.08 * sin(p.x * 5.0 + t * 0.31) + (fieldB - 0.5) * 0.28)) * 18.0);
  float ribbon3 = exp(-abs(p.y - (0.02 * sin(p.x * 8.0 - t * 0.22) + (folds - 0.5) * 0.20)) * 26.0);
  float body = smoothstep(0.30 - bass * 0.06, 0.76, marbling + ribbon1 * 0.22 + ribbon2 * 0.13);
  float edge = pow(clamp(ribbon1 * 0.55 + ribbon2 * 0.34 + ribbon3 * 0.25, 0.0, 1.0), 1.45);

  vec3 cyan = vec3(0.015, 0.72, 1.0);
  vec3 azure = vec3(0.08, 0.30, 1.0);
  vec3 violet = vec3(0.55, 0.08, 1.0);
  vec3 magenta = vec3(1.0, 0.08, 0.72);
  float hue = clamp(uv.x * 0.72 + fieldA * 0.28 + 0.08 * sin(t * 0.18), 0.0, 1.0);
  vec3 palette = mix(cyan, azure, smoothstep(0.05, 0.62, hue));
  palette = mix(palette, violet, smoothstep(0.42, 0.82, hue) * 0.88);
  palette = mix(palette, magenta, smoothstep(0.78, 1.0, hue) * 0.70);
  palette = mix(palette, uTint.rgb, 0.16);

  float caustic = pow(max(0.0, sin((fieldA * 2.0 + fieldB) * 18.0 - t * 0.65)), 13.0);
  float shimmer = pow(max(0.0, sin(uv.x * 31.0 + folds * 11.0 - t * 0.8)), 18.0);
  float light = edge * (0.42 + mids * 0.22 + hit * 0.35) + caustic * (0.10 + highs * 0.18) + shimmer * 0.12;
  float depth = body * (0.18 + bass * 0.14) + ribbon2 * 0.10;
  float sideFade = smoothstep(0.0, 0.12, uv.x) * (1.0 - smoothstep(0.88, 1.0, uv.x));
  float verticalFade = smoothstep(0.0, 0.16, uv.y) * (1.0 - smoothstep(0.90, 1.0, uv.y));
  float alpha = clamp((depth + light * 0.72) * sideFade * verticalFade, 0.0, 0.88) * uTint.a;
  vec3 color = palette * (0.30 + depth * 1.25) + vec3(0.35, 0.72, 1.0) * light;
  color += vec3(0.35, 0.10, 0.65) * (ribbon3 * 0.18 + hit * edge * 0.16);
  fragColor = vec4(color * alpha, alpha);
}
