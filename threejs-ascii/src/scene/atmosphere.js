import * as THREE from 'three';
import { GlyphPoints, glyphMaterial, makeGlyphField } from '../glyph/GlyphField.js';
import { mulberry32 } from '../utils/math.js';
import { getHeight, islandRadiusAt } from './layout.js';
import { MAT, globalUniforms } from './shared.js';

// 萤火虫：围绕各自的家点游荡并呼吸闪烁
export function createFireflies(count = 60) {
  const rand = mulberry32(7);
  const pos = new Float32Array(count * 3);
  const seeds = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    const a = rand() * Math.PI * 2;
    const r = 3 + rand() * (islandRadiusAt(a) - 4);
    const x = Math.cos(a) * r;
    const z = Math.sin(a) * r;
    pos.set([x, getHeight(x, z), z], i * 3);
    seeds[i] = rand();
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('aSeed', new THREE.BufferAttribute(seeds, 1));

  const material = new THREE.ShaderMaterial({
    uniforms: { uTime: globalUniforms.uTime, uPxPerUnit: globalUniforms.uPxPerUnit },
    vertexShader: /* glsl */ `
      uniform float uTime;
      uniform float uPxPerUnit;
      attribute float aSeed;
      varying float vBlink;
      void main() {
        float s = aSeed * 50.0;
        vec3 p = position + vec3(
          sin(uTime * 0.35 + s) * 1.6 + sin(uTime * 1.1 + s * 2.0) * 0.3,
          0.7 + sin(uTime * 0.8 + s * 3.0) * 0.45,
          cos(uTime * 0.3 + s * 1.7) * 1.6);
        vBlink = pow(0.5 + 0.5 * sin(uTime * (1.5 + aSeed) + s * 7.0), 3.0);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
        gl_PointSize = uPxPerUnit * (0.1 + 0.12 * vBlink);
      }`,
    fragmentShader: /* glsl */ `
      varying float vBlink;
      void main() {
        float r = length(gl_PointCoord - 0.5);
        if (r > 0.5 || vBlink < 0.12) discard;
        gl_FragColor = vec4(vec3(0.7, 1.0, 0.35) * vBlink * 3.0, 1.0);
      }`,
  });
  const points = new THREE.Points(geo, material);
  points.frustumCulled = false;

  // 3D 字符模式：同样的游荡与呼吸闪烁，用 · + * 表现
  const gp = new GlyphPoints();
  for (let i = 0; i < count; i++) gp.add([pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]], [0, 1, 0], MAT.FIREFLY, { seed: seeds[i] });
  const glyphs = makeGlyphField(gp, glyphMaterial('firefly'));
  return { points, glyphs };
}

// 贴地薄雾：漂移的噪声层，靠近篝火时染上暖色
export function createMist() {
  const geo = new THREE.PlaneGeometry(44, 44, 1, 1);
  geo.rotateX(-Math.PI / 2);
  const material = new THREE.ShaderMaterial({
    uniforms: {
      uTime: globalUniforms.uTime,
      uFirePos: globalUniforms.uFirePos,
      uFireI: globalUniforms.uFireI,
    },
    vertexShader: /* glsl */ `
      varying vec3 vWorld;
      void main() {
        vec4 wp = modelMatrix * vec4(position, 1.0);
        vWorld = wp.xyz;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }`,
    fragmentShader: /* glsl */ `
      uniform float uTime;
      uniform vec3 uFirePos;
      uniform float uFireI;
      varying vec3 vWorld;
      float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      float noise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
      }
      float fbm(vec2 p) {
        float s = 0.0, a = 0.5;
        for (int i = 0; i < 4; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
        return s;
      }
      void main() {
        vec2 p = vWorld.xz * 0.12;
        float n = fbm(p + vec2(uTime * 0.04, uTime * 0.025));
        n = fbm(p * 1.3 + n * 1.5 - vec2(uTime * 0.03, 0.0));
        float mask = smoothstep(18.0, 12.0, length(vWorld.xz));
        float a = smoothstep(0.45, 0.85, n) * mask * 0.22;
        float fd = distance(vWorld.xz, uFirePos.xz);
        vec3 col = mix(vec3(0.1, 0.14, 0.28), vec3(0.9, 0.4, 0.15) * uFireI, smoothstep(4.5, 1.0, fd) * 0.6);
        gl_FragColor = vec4(col, a);
      }`,
    transparent: true,
    depthWrite: false,
  });
  const mesh = new THREE.Mesh(geo, material);
  mesh.position.y = 0.3;
  mesh.renderOrder = 2;
  return mesh;
}
