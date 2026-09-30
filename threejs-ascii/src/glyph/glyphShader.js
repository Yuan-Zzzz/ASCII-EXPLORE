// 3D 字符点：每个实例是一个固定像素大小、始终正对屏幕的字符方块
// aInfo = (物体ID, 固定行(-1 为按光照), 随机种子, 是否棱边点)
export const glyphVertex = /* glsl */ `
#include <common>
attribute vec3 aPos;
attribute vec3 aNrm;
attribute vec3 aDir;
attribute vec4 aInfo;

uniform float uTime;
uniform vec2 uWindDir;
uniform vec3 uMoonDir;
uniform vec3 uFirePos;
uniform float uFireI;
uniform vec3 uPlayer;
uniform vec2 uResolution;
uniform float uGlyphPx;
uniform float uDepthBias;
uniform float uEdgeBias;
uniform float uSpacing;
uniform float uEdgeDisk;
uniform float uDither;
uniform float uShowEdges;
uniform vec4 uEdgeGlyphs;
uniform sampler2D tGlyphs;
uniform sampler2D tColors;
uniform sampler2D tSpacing;
uniform float uWindStrength;
uniform float uWindBase;
uniform float uSpeed;
uniform float uHeight;
uniform float uSpread;
uniform float uDrift;

flat varying float vGlyph;
flat varying vec3 vColor;
flat varying float vEdge;
varying vec2 vLocal;

vec3 tableColor(int x, int id) { return texelFetch(tColors, ivec2(x, id), 0).rgb; }
float tableGlyph(int row, int v, int id) { return texelFetch(tGlyphs, ivec2(row * VARIANTS + v, id), 0).r * 255.0; }

float waveH(vec2 p) {
  float t = uTime;
  return sin(p.x * 1.3 + t * 1.1) * 0.05
       + sin(p.y * 1.7 - t * 1.4 + p.x * 0.4) * 0.04
       + sin((p.x + p.y) * 3.1 + t * 2.3) * 0.02
       + sin((p.x - p.y) * 5.3 - t * 2.9) * 0.012;
}

void main() {
  int id = int(aInfo.x + 0.5);
  float seed = aInfo.z;
  bool edge = aInfo.w > 0.5;
  bool hidden = edge && uShowEdges < 0.5;
  vec3 local = aPos;
  float sem = 0.0;

#ifdef MODE_PARTICLE
  float speed = uSpeed * (0.7 + fract(seed * 13.7) * 0.6);
  float life = fract(uTime * speed + seed);
  float ang = seed * 62.83 + uTime * (1.0 + fract(seed * 7.1)) * 1.5;
  float rad = uSpread * (0.5 + 0.5 * fract(seed * 3.1)) * (1.0 - life * 0.8);
  local = vec3(cos(ang) * rad, life * uHeight * (0.6 + 0.6 * fract(seed * 5.3)), sin(ang) * rad);
  local.x += sin(uTime * 3.0 + seed * 20.0) * 0.1 * life + uDrift * life * life;
  local.z += cos(uTime * 2.3 + seed * 11.0) * 0.1 * life + uDrift * 0.6 * life * life;
  float fade = (1.0 - life) * smoothstep(0.0, 0.08, life);
  hidden = hidden || fade < 0.1;
  sem = life;
#endif

  vec4 wp = modelMatrix * vec4(local, 1.0);

#ifdef MODE_FIREFLY
  float s = seed * 50.0;
  wp.xyz += vec3(
    sin(uTime * 0.35 + s) * 1.6 + sin(uTime * 1.1 + s * 2.0) * 0.3,
    0.7 + sin(uTime * 0.8 + s * 3.0) * 0.45,
    cos(uTime * 0.3 + s * 1.7) * 1.6);
  float blink = pow(0.5 + 0.5 * sin(uTime * (1.5 + seed) + s * 7.0), 3.0);
  hidden = hidden || blink < 0.15;
  sem = blink;
#endif

#ifdef WIND
  float swayH = max(wp.y - uWindBase, 0.0);
  float swayPh = uTime * 1.3 + modelMatrix[3].x * 0.35 + modelMatrix[3].z * 0.27;
  float swayS = sin(swayPh) + 0.35 * sin(swayPh * 2.7 + 1.3) + 0.6;
  wp.xz += uWindDir * swayS * uWindStrength * swayH * swayH;
  wp.x += cos(swayPh * 0.7) * uWindStrength * 0.4 * swayH * swayH;
#endif

#ifdef MODE_GRASS
  vec3 root = wp.xyz;
  float sway = sin(uTime * 1.9 + root.x * 0.45 + root.z * 0.3 + seed * 6.28) * 0.5
             + sin(uTime * 3.3 + root.x * 1.3 - root.z * 0.7) * 0.15;
  float gust = smoothstep(0.2, 1.0, sin(uTime * 0.7 - dot(root.xz, uWindDir) * 0.25)) * 0.9;
  vec2 bend = uWindDir * (sway + gust + 0.3) * 0.32;
  vec2 away = root.xz - uPlayer.xz;
  float dist = length(away);
  bend += (away / max(dist, 1e-3)) * smoothstep(1.4, 0.15, dist) * 1.3;
  wp.xz += bend * 0.35;
  wp.y += 0.22;
  sem = clamp((viewMatrix * vec4(bend.x, 0.0, bend.y, 0.0)).x * 1.6, -1.0, 1.0);
#endif

#ifdef MODE_WATER
  float wh = waveH(wp.xz);
  wp.y += wh;
  sem = fract(wp.x * 0.55 + wp.z * 0.35 - uTime * 0.45 + wh * 5.0);
#endif

  // 光照：月光（法线）+ 篝火 + 角色提灯，全部离散到 5 级
  vec3 n = normalize(mat3(modelMatrix) * aNrm);
  float moon = max(dot(n, uMoonDir), 0.0);
  float fd = distance(wp.xyz, uFirePos);
  float fire = uFireI * 2.4 / (1.0 + fd * fd * 0.2);
  float pd = distance(wp.xyz, uPlayer + vec3(0.0, 0.9, 0.0));
  float lamp = 0.8 / (1.0 + pd * pd * 0.9);
  float L = 0.08 + moon * 0.5 + fire + lamp;

#ifdef MODE_WATER
  vec2 ff = wp.xz - uFirePos.xz;
  float lateral = abs(ff.x - ff.y) * 0.7071;
  float streak = exp(-lateral * lateral / 0.3) * step(0.0, ff.x + ff.y) / (1.0 + dot(ff, ff) * 0.05);
  float glint = step(0.8, fract(sin(dot(floor(wp.xz * 4.0 + vec2(uTime * 0.7, 0.0)), vec2(12.9898, 78.233))) * 43758.5453));
  fire += uFireI * streak * (0.6 + 0.6 * sin(wp.x * 7.0 + wp.z * 7.0 + uTime * 3.0));
  L = 0.3 + smoothstep(0.02, 0.09, wh) * 0.35 + glint * 0.45 + fire;
#endif

  // 暖光既要占主导，也要足够强，远处被月光照着的物体保持冷色
  float warm = (fire + lamp) / L * smoothstep(0.2, 0.45, fire + lamp);
  int row = clamp(int(smoothstep(0.06, 1.1, L) * float(LEVELS) + (seed - 0.5) * 0.7 + (edge ? 1.0 : 0.0)), 0, LEVELS - 1);
  int v = int(seed * 3.999);
  bool special = false;

  if (id == M_FIRE || id == M_EMBER || id == M_FIREFLY) {
    row = clamp(int(sem * float(LEVELS)), 0, LEVELS - 1);
    if (id == M_FIRE) v = int(fract(seed * 7.0 + floor(uTime * 10.0) * 0.37) * 3.999);
    special = true;
  }
  if (id == M_GRASS) {
    v = abs(sem) < 0.22 ? 1 : (sem > 0.0 ? 2 : 0);
    if (seed > 0.86) v = 3;
  }
  if (id == M_WATER) v = int(fract(sem + seed * 0.12) * 3.999);
  if (aInfo.y > -0.5) {
    row = int(aInfo.y + 0.5);
    special = true;
  }

  float glyph;
  if (edge) {
    vec2 sd = (viewMatrix * vec4(mat3(modelMatrix) * aDir, 0.0)).xy;
    float a = mod(atan(sd.y, sd.x) + PI, PI);
    int e = int(mod(floor(a / (PI * 0.25) + 0.5), 4.0));
    glyph = uEdgeGlyphs[e];
  } else {
    glyph = tableGlyph(row, v, id);
  }
  vec3 col = tableColor(row, id);
  if (!special && warm > 0.55 + (seed - 0.5) * 0.3) col = tableColor(row, WARM_ROW);

  vGlyph = glyph;
  vColor = col;
  vEdge = edge ? 1.0 : 0.0;
  if (hidden || glyph < 0.5) {
    gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
    return;
  }

  // 正交相机 w=1：向镜头偏移深度以通过实体深度预渲染；中心吸附到像素，字符保持锐利
  vec4 clip = projectionMatrix * viewMatrix * wp;
#ifdef SPACE_PASS
  // 间距 pass：表面字符占一个字符宽，棱边按 uEdgeDisk 缩小，轮廓字符可以更密；棱边额外靠前以在重叠处胜出
  clip.xy += position.xy * uGlyphPx * (edge ? uEdgeDisk : 1.0) / uResolution;
  clip.z -= uDepthBias + (edge ? uEdgeBias : 0.0);
#else
  vec2 px = floor((clip.xy * 0.5 + 0.5) * uResolution);
  clip.xy = (px + position.xy * uGlyphPx) / uResolution * 2.0 - 1.0;
  clip.z -= uDepthBias;
#endif
  vLocal = position.xy + 0.5;
  gl_Position = clip;
}
`;

export const glyphFragment = /* glsl */ `
uniform sampler2D tAtlas;
uniform sampler2D tSpacing;
uniform vec2 uAtlasGrid;
uniform float uAtlasPx;
uniform float uGlyphPx;
uniform vec2 uResolution;
uniform float uAmber;
uniform float uSpacing;
uniform float uDither;
flat varying float vGlyph;
flat varying vec3 vColor;
flat varying float vEdge;
varying vec2 vLocal;

// 4x4 Bayer 矩阵，值域 0~1
float bayer4(ivec2 p) {
  int i = (p.x & 3) + (p.y & 3) * 4;
  float v = 0.3125;
  if (i == 0) v = 0.0;
  else if (i == 1) v = 0.5;
  else if (i == 2) v = 0.125;
  else if (i == 3) v = 0.625;
  else if (i == 4) v = 0.75;
  else if (i == 5) v = 0.25;
  else if (i == 6) v = 0.875;
  else if (i == 7) v = 0.375;
  else if (i == 8) v = 0.1875;
  else if (i == 9) v = 0.6875;
  else if (i == 10) v = 0.0625;
  else if (i == 11) v = 0.5625;
  else if (i == 12) v = 0.9375;
  else if (i == 13) v = 0.4375;
  else if (i == 14) v = 0.8125;
  return v;
}

void main() {
#ifdef SPACE_PASS
  // 圆盘外不占位置；r 记录优先级（棱边 1、表面 0）
  if (length(vLocal - 0.5) > 0.5) discard;
  gl_FragColor = vec4(vEdge, 0.0, 0.0, 1.0);
  return;
#endif
  if (uSpacing > 0.5) {
    // 这块地方被更优先的字符占了就让位（自己占的位置优先级等于自己）
    if (texture(tSpacing, gl_FragCoord.xy / uResolution).r > vEdge + 0.5) discard;
  }
  vec2 g = vec2(mod(vGlyph, uAtlasGrid.x), floor(vGlyph / uAtlasGrid.x));
  vec2 uv = vec2((g.x + vLocal.x) / uAtlasGrid.x, 1.0 - (g.y + 1.0 - vLocal.y) / uAtlasGrid.y);
  float lod = max(log2(uAtlasPx / uGlyphPx) - 0.5, 0.0);
  float m = textureLod(tAtlas, uv, lod).r;
  if (m < 0.35) discard;
  vec3 c = vColor;
  if (uAmber > 0.5) c = vec3(1.0, 0.64, 0.2) * (0.2 + dot(c, vec3(0.299, 0.587, 0.114)) * 1.1);
  // 4x4 Bayer 抖动：字符边缘按像素有无来过渡，而不是灰度抗锯齿；uDither 为 0 时退回固定阈值
  float bayer = bayer4(ivec2(gl_FragCoord.xy));
  if (m < 0.3 + bayer * uDither) discard;
  gl_FragColor = vec4(c, 1.0);
}
`;
