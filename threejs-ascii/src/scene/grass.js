import * as THREE from 'three';
import { GlyphPoints, glyphMaterial, makeGlyphField } from '../glyph/GlyphField.js';
import { fbm, mulberry32 } from '../utils/math.js';
import { FIRE, POND, getHeight, islandRadiusAt, pondMetric } from './layout.js';
import { MAT, fogUniforms, globalUniforms } from './shared.js';

const vertexShader = /* glsl */ `
#include <common>
#include <fog_pars_vertex>
uniform float uTime;
uniform vec3 uPlayer;
uniform vec2 uWindDir;
attribute float aRand;
varying float vTip;
varying float vRand;
varying float vGust;
varying vec3 vWorld;

void main() {
  float tip = position.y;
  mat4 m = modelMatrix * instanceMatrix;
  vec3 root = (m * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
  vec4 wp = m * vec4(position, 1.0);
  float bladeH = length(vec3(instanceMatrix[1]));

  // 风：基础摆动 + 大范围阵风波
  float sway = sin(uTime * 1.9 + root.x * 0.45 + root.z * 0.3 + aRand * 6.28) * 0.5
             + sin(uTime * 3.3 + root.x * 1.3 - root.z * 0.7) * 0.15;
  float gust = smoothstep(0.2, 1.0, sin(uTime * 0.7 - dot(root.xz, uWindDir) * 0.25)) * 0.9;
  vec2 bend = uWindDir * (sway + gust + 0.3) * 0.32;

  // 角色经过时向外推开
  vec2 away = root.xz - uPlayer.xz;
  float dist = length(away);
  float push = smoothstep(1.4, 0.15, dist);
  bend += (away / max(dist, 1e-3)) * push * 1.3;

  float t2 = tip * tip;
  wp.xz += bend * t2 * bladeH;
  wp.y -= length(bend) * t2 * bladeH * 0.4;

  // 屏幕空间的倾斜方向留给字符着色器；这里只推动草叶
  vTip = tip;
  vRand = aRand;
  vGust = gust;
  vWorld = wp.xyz;
  vec4 mvPosition = viewMatrix * wp;
  gl_Position = projectionMatrix * mvPosition;
  #include <fog_vertex>
}
`;

const fragmentShader = /* glsl */ `
#include <common>
#include <fog_pars_fragment>
uniform vec3 uFirePos;
uniform float uFireI;
uniform vec3 uFireColor;
uniform vec3 uMoonColor;
uniform vec3 uPlayer;
varying float vTip;
varying float vRand;
varying float vGust;
varying vec3 vWorld;

void main() {
  vec3 base = mix(vec3(0.015, 0.04, 0.025), vec3(0.11, 0.24, 0.09), vTip);
  base *= (0.75 + vRand * 0.5) * (0.75 + 0.25 * sin(vWorld.x * 0.7) * sin(vWorld.z * 0.6));
  // 阵风掠过时草尖泛起月光
  vec3 col = base * (0.3 + uMoonColor * (0.9 + vGust * 0.9) * vTip);
  float fd = distance(vWorld, uFirePos);
  col += base * uFireColor * uFireI * 3.2 / (1.0 + fd * fd * 0.22) * (0.4 + vTip);
  // 角色提灯的暖光
  float pd = distance(vWorld, uPlayer + vec3(0.0, 0.9, 0.0));
  col += base * vec3(1.0, 0.75, 0.4) * 1.3 / (1.0 + pd * pd * 0.9);
  gl_FragColor = vec4(col, 1.0);
  #include <fog_fragment>
}
`;

// 大量实例化草叶，GPU 端做风摆与角色推开
export function createGrass(colliders, count = 16000) {
  const blade = new THREE.PlaneGeometry(0.1, 1, 1, 4);
  blade.translate(0, 0.5, 0);
  const p = blade.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const y = p.getY(i);
    p.setX(i, p.getX(i) * (1 - y * 0.9));
  }

  const uniforms = {
    ...fogUniforms(),
    uTime: globalUniforms.uTime,
    uPlayer: globalUniforms.uPlayer,
    uWindDir: globalUniforms.uWindDir,
    uFirePos: globalUniforms.uFirePos,
    uFireI: globalUniforms.uFireI,
    uFireColor: globalUniforms.uFireColor,
    uMoonColor: globalUniforms.uMoonColor,
  };
  const material = new THREE.ShaderMaterial({
    uniforms,
    vertexShader,
    fragmentShader,
    side: THREE.DoubleSide,
    fog: true,
  });

  const mesh = new THREE.InstancedMesh(blade, material, count);
  const rands = new Float32Array(count);
  const rand = mulberry32(42);
  const dummy = new THREE.Object3D();
  let placed = 0;

  for (let i = 0; placed < count && i < count * 5; i++) {
    const x = (rand() * 2 - 1) * 18.5;
    const z = (rand() * 2 - 1) * 18.5;
    const r = Math.hypot(x, z);
    if (r > islandRadiusAt(Math.atan2(z, x)) - 0.5) continue;
    const h = getHeight(x, z);
    if (pondMetric(x, z) < 1.18 || h < POND.level + 0.1) continue;
    const df = Math.hypot(x - FIRE.x, z - FIRE.z);
    if (df < 1.5 || (df < 3.2 && rand() > (df - 1.5) / 1.7)) continue;
    if (colliders.some((c) => Math.hypot(c.x - x, c.z - z) < c.r * 0.8)) continue;

    const clump = 0.45 + fbm(x * 0.22 + 3, z * 0.22) * 1.1;
    dummy.position.set(x, h - 0.02, z);
    dummy.rotation.set(0, rand() * Math.PI, 0);
    dummy.scale.set(0.8 + rand() * 0.8, (0.35 + rand() * 0.55) * clump, 1);
    dummy.updateMatrix();
    mesh.setMatrixAt(placed, dummy.matrix);
    rands[placed] = rand();
    placed++;
  }

  mesh.count = placed;
  blade.setAttribute('aRand', new THREE.InstancedBufferAttribute(rands, 1));
  mesh.instanceMatrix.needsUpdate = true;
  mesh.frustumCulled = false;
  return mesh;
}

// 3D 字符模式的草：抖动网格上的字符点，风和角色推开在着色器里改变 \ | / 朝向
export function createGrassGlyphs(colliders) {
  const pts = new GlyphPoints();
  const rand = mulberry32(4242);
  const step = 0.3;
  for (let gx = -18.5; gx <= 18.5; gx += step) {
    for (let gz = -18.5; gz <= 18.5; gz += step) {
      const x = gx + (rand() - 0.5) * step * 0.8;
      const z = gz + (rand() - 0.5) * step * 0.8;
      if (Math.hypot(x, z) > islandRadiusAt(Math.atan2(z, x)) - 1.0) continue;
      if (pondMetric(x, z) < 1.25) continue;
      const df = Math.hypot(x - FIRE.x, z - FIRE.z);
      if (df < 1.8 || (df < 3.4 && rand() > (df - 1.8) / 1.6)) continue;
      if (colliders.some((c) => Math.hypot(c.x - x, c.z - z) < c.r * 0.9)) continue;
      // 按噪声成片分布，留出空地
      if (fbm(x * 0.22 + 3, z * 0.22) < 0.38 + rand() * 0.12) continue;
      pts.add([x, getHeight(x, z), z], [0, 1, 0], MAT.GRASS, { seed: rand() });
    }
  }
  return makeGlyphField(pts, glyphMaterial('grass'));
}
