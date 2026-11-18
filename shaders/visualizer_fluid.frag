#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy;
uniform vec4 uTint;
uniform float uBass;
uniform float uMids;
uniform float uHighs;
uniform float uTransient;
uniform vec4 uPaletteA;
uniform vec4 uPaletteB;
uniform vec4 uPaletteC;

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
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 4; i++) { v += noise2(p) * a; p = p * 2.02 + vec2(17.1, 9.2); a *= 0.5; }
  return v;
}
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv - 0.5;
  p.x *= uSize.x / max(uSize.y, 1.0);
  float t = uTime, bass = clamp(uBass,0.0,1.0), mids = clamp(uMids,0.0,1.0);
  float highs = clamp(uHighs,0.0,1.0), hit = clamp(uTransient,0.0,1.0);
  float energy = clamp(uEnergy,0.0,1.0);

  // Two offset flow fields create a folded, asymmetric liquid volume.
  vec2 warp = vec2(fbm(p*3.1 + vec2(t*.10,-t*.07)), fbm(p*3.4 + vec2(-t*.08,t*.09)));
  vec2 q = p*2.65 + (warp-.5)*(1.25 + mids*.35);
  float a = fbm(q*2.2 + vec2(t*.12,-t*.08));
  float b = fbm(q*3.9 - vec2(t*.09,t*.11));
  float c = fbm(q*6.8 + vec2(b,-a)*1.7);
  float marble = a*.46 + b*.34 + c*.20;
  float ridge = exp(-abs(marble - (.48 + .035*sin(q.x*5.0-t*.25)))*(17.0+bass*8.0));
  float ridge2 = exp(-abs(b - (.48 + .06*sin(q.x*3.2+t*.2)))*22.0);
  float filament = exp(-abs(c-.52)*42.0);
  float volume = smoothstep(.34-bass*.05,.73,marble + ridge*.16 + ridge2*.10);
  float edge = clamp(ridge*.55 + ridge2*.35 + filament*.24,0.0,1.0);

  vec3 palette = mix(uPaletteA.rgb,uPaletteB.rgb,smoothstep(.08,.78,uv.x*.62+a*.38));
  palette = mix(palette,uPaletteC.rgb,smoothstep(.34,.92,uv.x*.48+b*.52)*.72);
  palette = mix(palette,uTint.rgb,.12);
  float caustic = pow(max(0.0,sin((a*2.0+b)*21.0-t*.62)),14.0);
  float glint = pow(max(0.0,sin(uv.x*39.0+c*13.0-t*.8)),20.0);
  float rim = edge*(.35+mids*.22+hit*.38) + caustic*(.10+highs*.20) + glint*.10;
  float depth = volume*(.18+bass*.16) + ridge2*.08;
  float side = smoothstep(0.0,.10,uv.x)*(1.0-smoothstep(.90,1.0,uv.x));
  float vertical = smoothstep(0.0,.13,uv.y)*(1.0-smoothstep(.91,1.0,uv.y));
  // A soft irregular silhouette keeps the material from reading as a rectangle.
  float silhouette = smoothstep(.02,.20,volume + edge*.13) * (1.0-smoothstep(.88,1.0,uv.y + (a-.5)*.10));
  float alpha = clamp((depth + rim*.72)*side*vertical*silhouette,0.0,.88)*uTint.a;
  vec3 light = mix(uPaletteB.rgb,vec3(1.0),.48);
  vec3 color = palette*(.30+depth*1.35) + light*rim*.72;
  color += uPaletteC.rgb*(filament*.18 + hit*edge*.14);
  color *= 1.0 + energy*.08;
  fragColor = vec4(color*alpha,alpha);
}
