#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy;
uniform vec4 uTint;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float x = uv.x;
  float energy = clamp(uEnergy, 0.0, 1.0);

  float driftA = sin(x * 5.2 - uTime * 0.46 + sin(x * 2.1 + uTime * 0.18) * 0.72);
  float driftB = sin(x * 7.0 + uTime * 0.31 + cos(x * 2.8 - uTime * 0.16) * 0.58);
  float driftC = sin(x * 3.7 - uTime * 0.23 + sin(x * 6.3 + uTime * 0.12) * 0.42);

  float surfaceA = 0.43 + driftA * 0.105 - energy * 0.075;
  float surfaceB = 0.63 + driftB * 0.082 - energy * 0.045;
  float surfaceC = 0.81 + driftC * 0.052 - energy * 0.025;

  float bodyA = 1.0 - smoothstep(surfaceA, surfaceA + 0.34, uv.y);
  float bodyB = 1.0 - smoothstep(surfaceB, surfaceB + 0.28, uv.y);
  float bodyC = 1.0 - smoothstep(surfaceC, surfaceC + 0.20, uv.y);
  float crestA = exp(-abs(uv.y - surfaceA) * 78.0);
  float crestB = exp(-abs(uv.y - surfaceB) * 92.0);
  float crestC = exp(-abs(uv.y - surfaceC) * 108.0);

  vec3 teal = mix(uTint.rgb, vec3(0.16, 0.84, 0.82), 0.43);
  vec3 blue = mix(uTint.rgb, vec3(0.25, 0.50, 0.96), 0.40);
  vec3 violet = mix(uTint.rgb, vec3(0.68, 0.42, 0.98), 0.48);
  float hueFlow = clamp(x * 0.72 + driftA * 0.12 + 0.12, 0.0, 1.0);
  vec3 base = mix(teal, blue, hueFlow);
  base = mix(base, violet, clamp(driftC * 0.18 + x * 0.28, 0.0, 0.48));

  float body = bodyA * 0.22 + bodyB * 0.13 + bodyC * 0.075;
  float highlights = crestA * 0.26 + crestB * 0.20 + crestC * 0.12;
  float sheen = pow(max(0.0, sin(x * 13.0 - uTime * 0.22 + driftB)), 18.0)
      * bodyA * 0.09;
  vec3 color = base + vec3(0.58, 0.76, 0.91) * (highlights + sheen);
  float alpha = clamp(body + highlights + sheen, 0.0, 0.66);

  fragColor = vec4(color, alpha * uTint.a);
}
