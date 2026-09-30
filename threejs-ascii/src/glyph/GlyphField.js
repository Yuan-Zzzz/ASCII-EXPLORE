import * as THREE from 'three';
import { LEVELS, VARIANTS, getGlyphTables } from '../ascii/glyphs.js';
import { MAT, MAT_COUNT, globalUniforms } from '../scene/shared.js';
import { mulberry32 } from '../utils/math.js';
import { glyphFragment, glyphVertex } from './glyphShader.js';
import { sampleEdges, sampleSurface } from './sampling.js';

export const GLYPH_LAYER = 1;

const tables = getGlyphTables();

// 所有字符点材质共享的 uniform，由 GlyphRenderer 每帧更新
export const glyphUniforms = {
  tGlyphs: { value: tables.glyphTex },
  tColors: { value: tables.colorTex },
  tAtlas: { value: tables.atlas.texture },
  uAtlasGrid: { value: new THREE.Vector2(tables.atlas.cols, tables.atlas.rows) },
  uAtlasPx: { value: tables.atlas.size },
  uEdgeGlyphs: { value: new THREE.Vector4(...tables.edgeGlyphs) },
  uResolution: { value: new THREE.Vector2(1, 1) },
  uGlyphPx: { value: 12 },
  uDepthBias: { value: 0.01 },
  uEdgeBias: { value: 0.01 },
  uSpacing: { value: 1 },
  uEdgeDisk: { value: 0.5 },
  uDither: { value: 0.55 },
  tSpacing: { value: new THREE.DataTexture(new Float32Array(4), 1, 1, THREE.RGBAFormat, THREE.FloatType) },
  uShowEdges: { value: 1 },
  uAmber: { value: 0 },
};

const defines = { LEVELS, VARIANTS, WARM_ROW: MAT_COUNT };
for (const [k, v] of Object.entries(MAT)) defines[`M_${k}`] = v;

const materialCache = new Map();

// mode: static | grass | water | particle | firefly；wind = [强度, 起始高度]（与 applyWind 保持一致）
export function glyphMaterial(mode = 'static', { wind = null, particle = null } = {}) {
  const key = `${mode}|${wind}|${particle ? JSON.stringify(particle) : ''}`;
  if (materialCache.has(key)) return materialCache.get(key);
  const d = { ...defines, [`MODE_${mode.toUpperCase()}`]: 1 };
  if (wind) d.WIND = 1;
  const material = new THREE.ShaderMaterial({
    defines: d,
    uniforms: {
      ...glyphUniforms,
      uTime: globalUniforms.uTime,
      uWindDir: globalUniforms.uWindDir,
      uMoonDir: globalUniforms.uMoonDir,
      uFirePos: globalUniforms.uFirePos,
      uFireI: globalUniforms.uFireI,
      uPlayer: globalUniforms.uPlayer,
      uWindStrength: { value: wind ? wind[0] : 0 },
      uWindBase: { value: wind ? wind[1] : 0 },
      uSpeed: { value: particle?.speed ?? 0 },
      uHeight: { value: particle?.height ?? 0 },
      uSpread: { value: particle?.spread ?? 0 },
      uDrift: { value: particle?.drift ?? 0 },
    },
    vertexShader: glyphVertex,
    fragmentShader: glyphFragment,
  });
  materialCache.set(key, material);
  return material;
}

// 间距 pass 版本：同一套 uniform 引用，只多一个 SPACE_PASS 定义
const spaceCache = new WeakMap();
export function spaceVariant(material) {
  let m = spaceCache.get(material);
  if (!m) {
    m = material.clone();
    m.uniforms = material.uniforms;
    m.defines = { ...material.defines, SPACE_PASS: 1 };
    spaceCache.set(material, m);
  }
  return m;
}

const quad = new THREE.PlaneGeometry(1, 1);

// 把点数据打包成实例化字符网格（放在字符层，只在 3D 字符模式下渲染）
export function makeGlyphField(points, material) {
  const n = points.info.length / 4;
  const geo = new THREE.InstancedBufferGeometry();
  geo.index = quad.index;
  geo.setAttribute('position', quad.attributes.position);
  geo.setAttribute('uv', quad.attributes.uv);
  const attr = (arr, size, fill) =>
    new THREE.InstancedBufferAttribute(arr ? new Float32Array(arr) : new Float32Array(n * size).fill(fill), size);
  geo.setAttribute('aPos', attr(points.pos, 3, 0));
  geo.setAttribute('aNrm', attr(points.nrm, 3, 0));
  geo.setAttribute('aDir', attr(points.dir, 3, 0));
  geo.setAttribute('aInfo', attr(points.info, 4, 0));
  geo.instanceCount = n;
  const mesh = new THREE.Mesh(geo, material);
  mesh.frustumCulled = false;
  mesh.layers.set(GLYPH_LAYER);
  return mesh;
}

// 点数据构建器
export class GlyphPoints {
  constructor() {
    this.pos = [];
    this.nrm = [];
    this.dir = [];
    this.info = [];
  }

  add(p, n, matId, { row = -1, seed = Math.random(), dir = null } = {}) {
    this.pos.push(p[0], p[1], p[2]);
    this.nrm.push(n[0], n[1], n[2]);
    this.dir.push(...(dir ?? [0, 0, 0]));
    this.info.push(matId, row, seed, dir ? 1 : 0);
  }

  get count() {
    return this.info.length / 4;
  }
}

// 给网格贴上字符：特征棱上密集的方向字符勾出形状，表面稀疏的材质字符表现明暗
export function attachGlyphs(
  mesh,
  matId,
  { spacing = 0.3, edgeStep = 0.2, edges = true, surface = true, threshold = 25, row = -1, wind = null, seed = 1 } = {}
) {
  const geo = mesh.geometry;
  const rand = mulberry32(seed);
  geo.computeBoundingBox();
  const center = geo.boundingBox.getCenter(new THREE.Vector3());
  const pts = new GlyphPoints();
  if (surface) {
    const s = sampleSurface(geo, spacing, rand);
    for (let i = 0; i < s.pos.length; i += 3) {
      pts.add([s.pos[i], s.pos[i + 1], s.pos[i + 2]], [s.nrm[i], s.nrm[i + 1], s.nrm[i + 2]], matId, { row, seed: rand() });
    }
  }
  if (edges) {
    const e = sampleEdges(geo, edgeStep, threshold);
    const n = new THREE.Vector3();
    for (let i = 0; i < e.pos.length; i += 3) {
      n.set(e.pos[i] - center.x, e.pos[i + 1] - center.y, e.pos[i + 2] - center.z).normalize();
      pts.add([e.pos[i], e.pos[i + 1], e.pos[i + 2]], n.toArray(), matId, {
        row,
        seed: rand(),
        dir: [e.dir[i], e.dir[i + 1], e.dir[i + 2]],
      });
    }
  }
  const field = makeGlyphField(pts, glyphMaterial('static', { wind }));
  mesh.add(field);
  return field;
}
