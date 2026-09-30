import * as THREE from 'three';
import { GlyphPoints, glyphMaterial, makeGlyphField } from '../glyph/GlyphField.js';
import { mulberry32 } from '../utils/math.js';
import { POND } from './layout.js';
import { MAT, fogUniforms, globalUniforms } from './shared.js';

const common = /* glsl */ `
uniform float uTime;
float waveH(vec2 p) {
  float t = uTime;
  return sin(p.x * 1.3 + t * 1.1) * 0.05
       + sin(p.y * 1.7 - t * 1.4 + p.x * 0.4) * 0.04
       + sin((p.x + p.y) * 3.1 + t * 2.3) * 0.02
       + sin((p.x - p.y) * 5.3 - t * 2.9) * 0.012;
}
`;

const vertexShader = /* glsl */ `
#include <common>
#include <fog_pars_vertex>
${common}
varying vec3 vWorld;
void main() {
  vec4 wp = modelMatrix * vec4(position, 1.0);
  wp.y += waveH(wp.xz);
  vWorld = wp.xyz;
  vec4 mvPosition = viewMatrix * wp;
  gl_Position = projectionMatrix * mvPosition;
  #include <fog_vertex>
}
`;

const fragmentShader = /* glsl */ `
#include <common>
#include <fog_pars_fragment>
${common}
uniform vec3 uFirePos;
uniform float uFireI;
uniform vec3 uFireColor;
uniform vec3 uMoonReflDir;
uniform vec3 uPlayer;
uniform vec2 uCenter;
uniform vec2 uRadii;
varying vec3 vWorld;

void main() {
  vec2 p = vWorld.xz;
  float e = 0.06;
  vec3 n = normalize(vec3(
    (waveH(p - vec2(e, 0.0)) - waveH(p + vec2(e, 0.0))) * 1.2,
    2.0 * e,
    (waveH(p - vec2(0.0, e)) - waveH(p + vec2(0.0, e))) * 1.2));
  vec3 V = normalize(vec3(1.0));
  vec3 R = reflect(-V, n);
  float fres = pow(1.0 - max(dot(n, V), 0.0), 3.0);

  vec3 col = mix(vec3(0.001, 0.005, 0.025), vec3(0.004, 0.02, 0.08), clamp(fres * 1.5 + 0.25, 0.0, 1.0));

  // 月光：碎裂的镜面高光（方向对准画面右上角的月亮，而非真实光照方向）
  float md = max(dot(R, uMoonReflDir), 0.0);
  vec2 sc = floor(p * 5.0 + vec2(uTime * 0.7, 0.0));
  float sparkle = step(0.6, fract(sin(dot(sc, vec2(12.9898, 78.233))) * 43758.5453));
  col += vec3(0.65, 0.78, 1.0) * (pow(md, 260.0) * 3.0 * sparkle + pow(md, 16.0) * 0.04);

  // 火光倒影：朝镜头方向拉长的抖动光带 + 近处暖色
  vec2 ff = p - uFirePos.xz;
  float fd = length(ff);
  float lateral = abs(ff.x - ff.y) * 0.7071;
  float ahead = step(0.0, ff.x + ff.y);
  float width = 0.35 + fd * 0.06;
  float streak = exp(-lateral * lateral / (width * width)) * ahead;
  float shimmer = smoothstep(0.1, 1.0, sin(p.x * 7.0 + p.y * 7.0 + uTime * 3.0 + n.x * 25.0) * 0.5 + 0.5 + n.z * 2.0);
  col += uFireColor * uFireI * (streak * shimmer * 2.4 + 0.05) / (1.0 + fd * fd * 0.06);

  // 同心涟漪 + 岸边泡沫
  vec2 q = (p - uCenter) / uRadii;
  float em = length(q);
  float ring = sin(em * 22.0 - uTime * 2.2);
  col += vec3(0.01, 0.04, 0.12) * smoothstep(0.93, 1.0, ring) * (1.0 - em);
  col += vec3(0.04, 0.08, 0.16) * smoothstep(0.86, 1.02, em) * (0.6 + 0.4 * sin(uTime * 1.5 + atan(q.y, q.x) * 9.0));

  // 角色靠近时的涟漪
  float pd = distance(p, uPlayer.xz);
  col += vec3(0.1, 0.16, 0.3) * smoothstep(0.8, 1.0, sin(pd * 10.0 - uTime * 6.0)) * smoothstep(2.2, 0.8, pd) * 0.6;

  gl_FragColor = vec4(col, 1.0);
  #include <fog_fragment>
}
`;

export function createWater() {
  const geo = new THREE.PlaneGeometry(POND.rx * 2.5, POND.rz * 2.5, 90, 70);
  geo.rotateX(-Math.PI / 2);
  const material = new THREE.ShaderMaterial({
    uniforms: {
      ...fogUniforms(),
      uTime: globalUniforms.uTime,
      uFirePos: globalUniforms.uFirePos,
      uFireI: globalUniforms.uFireI,
      uFireColor: globalUniforms.uFireColor,
      uMoonReflDir: { value: new THREE.Vector3(-0.25, 0.75, -0.6).normalize() },
      uPlayer: globalUniforms.uPlayer,
      uCenter: { value: new THREE.Vector2(POND.x, POND.z) },
      uRadii: { value: new THREE.Vector2(POND.rx * 1.08, POND.rz * 1.08) },
    },
    vertexShader,
    fragmentShader,
    fog: true,
  });
  const mesh = new THREE.Mesh(geo, material);
  mesh.position.set(POND.x, POND.level, POND.z);
  mesh.add(createWaterGlyphs());
  return mesh;
}

// 水面字符：椭圆内的规则点阵（局部坐标），波高与 ~ - = 相位在着色器里计算
function createWaterGlyphs() {
  const pts = new GlyphPoints();
  const rand = mulberry32(77);
  const step = 0.28;
  const rx = POND.rx * 1.06;
  const rz = POND.rz * 1.06;
  for (let x = -rx; x <= rx; x += step) {
    for (let z = -rz; z <= rz; z += step) {
      if ((x / rx) ** 2 + (z / rz) ** 2 > 1) continue;
      pts.add([x, 0.02, z], [0, 1, 0], MAT.WATER, { seed: rand() });
    }
  }
  return makeGlyphField(pts, glyphMaterial('water'));
}
