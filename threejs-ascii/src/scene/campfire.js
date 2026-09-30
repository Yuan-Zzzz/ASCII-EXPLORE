import * as THREE from 'three';
import { GlyphPoints, attachGlyphs, glyphMaterial, makeGlyphField } from '../glyph/GlyphField.js';
import { mulberry32, valueNoise } from '../utils/math.js';
import { FIRE, getHeight } from './layout.js';
import { MAT, globalUniforms } from './shared.js';

// 粒子全部在 GPU 中按 (时间 + 种子) 计算生命周期，CPU 不逐帧更新
const particleVertex = /* glsl */ `
uniform float uTime;
uniform float uPxPerUnit;
uniform float uSpeed;
uniform float uHeight;
uniform float uSpread;
uniform float uSizeA;
uniform float uSizeB;
uniform float uDrift;
attribute float aSeed;
varying float vLife;

void main() {
  float speed = uSpeed * (0.7 + fract(aSeed * 13.7) * 0.6);
  float life = fract(uTime * speed + aSeed);
  float ang = aSeed * 62.83 + uTime * (1.0 + fract(aSeed * 7.1)) * 1.5;
  float rad = uSpread * (0.5 + 0.5 * fract(aSeed * 3.1)) * (1.0 - life * 0.8);
  vec3 p = vec3(cos(ang) * rad, life * uHeight * (0.6 + 0.6 * fract(aSeed * 5.3)), sin(ang) * rad);
  p.x += sin(uTime * 3.0 + aSeed * 20.0) * 0.1 * life + uDrift * life * life;
  p.z += cos(uTime * 2.3 + aSeed * 11.0) * 0.1 * life + uDrift * 0.6 * life * life;
  vLife = life;
  vec4 mv = modelViewMatrix * vec4(p, 1.0);
  gl_Position = projectionMatrix * mv;
  gl_PointSize = uPxPerUnit * mix(uSizeA, uSizeB, life);
}
`;

// 不透明圆点粒子，供深度预渲染之外的原始画面使用
const particleFragment = /* glsl */ `
uniform vec3 uColA;
uniform vec3 uColB;
uniform vec3 uColC;
uniform float uIntensity;
varying float vLife;

void main() {
  float fade = (1.0 - vLife) * smoothstep(0.0, 0.08, vLife);
  float r = length(gl_PointCoord - 0.5);
  if (r > 0.5 * sqrt(fade) + 0.08 || fade < 0.08) discard;
  vec3 col = mix(uColA, uColB, smoothstep(0.0, 0.45, vLife));
  col = mix(col, uColC, smoothstep(0.45, 1.0, vLife));
  gl_FragColor = vec4(col * uIntensity * (0.4 + 0.6 * fade), 1.0);
}
`;

function createParticles(count, params) {
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(count * 3), 3));
  const seeds = new Float32Array(count);
  for (let i = 0; i < count; i++) seeds[i] = Math.random();
  geo.setAttribute('aSeed', new THREE.BufferAttribute(seeds, 1));

  const u = (v) => ({ value: v });
  const material = new THREE.ShaderMaterial({
    uniforms: {
      uTime: globalUniforms.uTime,
      uPxPerUnit: globalUniforms.uPxPerUnit,
      uSpeed: u(params.speed),
      uHeight: u(params.height),
      uSpread: u(params.spread),
      uSizeA: u(params.sizeA),
      uSizeB: u(params.sizeB),
      uDrift: u(params.drift ?? 0),
      uColA: u(new THREE.Color(...params.colA)),
      uColB: u(new THREE.Color(...params.colB)),
      uColC: u(new THREE.Color(...params.colC)),
      uIntensity: u(params.intensity),
    },
    vertexShader: particleVertex,
    fragmentShader: particleFragment,
  });
  const points = new THREE.Points(geo, material);
  points.frustumCulled = false;
  return points;
}

export function createCampfire() {
  const group = new THREE.Group();
  const baseY = getHeight(FIRE.x, FIRE.z);
  group.position.set(FIRE.x, baseY, FIRE.z);

  // 石圈
  const stoneMat = new THREE.MeshStandardMaterial({ color: 0x6b6e78, roughness: 1, flatShading: true });
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2;
    const s = 0.18 + Math.random() * 0.08;
    const stone = new THREE.Mesh(new THREE.DodecahedronGeometry(s, 0), stoneMat);
    stone.position.set(Math.cos(a) * 0.78, s * 0.5, Math.sin(a) * 0.78);
    stone.rotation.set(Math.random(), Math.random(), Math.random());
    stone.castShadow = true;
    stone.receiveShadow = true;
    group.add(stone);
    attachGlyphs(stone, MAT.ROCK, { surface: false, edgeStep: 0.16, seed: 40 + i });
  }

  // 交叉的木柴（带余烬自发光）
  const logMat = new THREE.MeshStandardMaterial({
      color: 0x3a2416,
      roughness: 1,
      flatShading: true,
      emissive: new THREE.Color(1.0, 0.3, 0.05),
      emissiveIntensity: 0.4,
  });
  for (let i = 0; i < 4; i++) {
    const log = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.09, 1.1, 6), logMat);
    const a = (i / 4) * Math.PI * 2;
    log.position.set(Math.cos(a) * 0.18, 0.28, Math.sin(a) * 0.18);
    log.rotation.set(0, -a, 0);
    log.rotateZ(1.0);
    log.castShadow = true;
    group.add(log);
    attachGlyphs(log, MAT.LOG, { spacing: 0.14, edgeStep: 0.12, threshold: 40, seed: 60 + i });
  }

  // 余烬床
  const bed = new THREE.Mesh(
    new THREE.CircleGeometry(0.5, 16),
    new THREE.MeshBasicMaterial({ color: new THREE.Color(2.2, 0.55, 0.08) })
  );
  bed.rotation.x = -Math.PI / 2;
  bed.position.y = 0.04;
  group.add(bed);
  attachGlyphs(bed, MAT.FIRE, { spacing: 0.24, edges: false, row: 2, seed: 80 });

  // 火焰与火星
  const flames = createParticles(180, {
    speed: 1.1,
    height: 1.7,
    spread: 0.38,
    sizeA: 0.6,
    sizeB: 0.12,
    colA: [1.0, 0.9, 0.55],
    colB: [1.0, 0.4, 0.06],
    colC: [0.6, 0.06, 0.02],
    intensity: 2.6,
  });
  flames.position.y = 0.1;
  const sparks = createParticles(70, {
    speed: 0.28,
    height: 4.5,
    spread: 0.5,
    sizeA: 0.26,
    sizeB: 0.16,
    drift: 0.9,
    colA: [1.0, 0.8, 0.4],
    colB: [1.0, 0.45, 0.1],
    colC: [0.9, 0.2, 0.05],
    intensity: 4.0,
  });
  sparks.position.y = 0.3;
  group.add(flames, sparks);

  // 3D 字符模式的火焰 / 火星：同一套粒子运动，按生命周期选 @ # * ^ ' .
  const particleGlyphs = (count, matId, params, y, seed) => {
    const pts = new GlyphPoints();
    const rand = mulberry32(seed);
    for (let i = 0; i < count; i++) pts.add([0, 0, 0], [0, 1, 0], matId, { seed: rand() });
    const field = makeGlyphField(pts, glyphMaterial('particle', { particle: params }));
    field.position.y = y;
    group.add(field);
  };
  particleGlyphs(140, MAT.FIRE, { speed: 1.1, height: 1.7, spread: 0.38 }, 0.1, 11);
  particleGlyphs(40, MAT.EMBER, { speed: 0.28, height: 4.5, spread: 0.5, drift: 0.9 }, 0.3, 12);

  // 闪烁点光源
  const light = new THREE.PointLight(0xff8a3a, 45, 18, 1.6);
  light.position.set(0, 1.1, 0);
  group.add(light);

  globalUniforms.uFirePos.value.set(FIRE.x, baseY + 0.8, FIRE.z);

  function update(t) {
    const n = valueNoise(t * 7, 3.7) * 0.6 + valueNoise(t * 17, 9.1) * 0.4;
    const flicker = 0.72 + 0.4 * n + 0.05 * Math.sin(t * 31);
    light.intensity = 45 * flicker;
    light.position.x = (valueNoise(t * 5, 1) - 0.5) * 0.15;
    light.position.z = (valueNoise(t * 5, 8) - 0.5) * 0.15;
    logMat.emissiveIntensity = 0.3 + 0.35 * n;
    globalUniforms.uFireI.value = flicker;
  }

  return { group, update, particles: [flames, sparks], collider: { x: FIRE.x, z: FIRE.z, r: 1.0 } };
}
