import * as THREE from 'three';
import { GlyphPoints, glyphMaterial, makeGlyphField } from '../glyph/GlyphField.js';
import { fbm, mulberry32, smoothstep } from '../utils/math.js';
import { FIRE, getHeight, islandRadiusAt, pondMetric } from './layout.js';
import { MAT } from './shared.js';

// 浮空小岛地形：网格高度 + 顶点色 + 地表类型（aKind），岛外三角形被裁掉以露出星空
export function createTerrain() {
  const size = 46;
  const seg = 184;
  const geo = new THREE.PlaneGeometry(size, size, seg, seg);
  geo.rotateX(-Math.PI / 2);

  const pos = geo.attributes.position;
  const colors = new Float32Array(pos.count * 3);
  const inside = new Uint8Array(pos.count);

  const grassA = new THREE.Color(0x1a3320);
  const grassB = new THREE.Color(0x2e4a24);
  const dirt = new THREE.Color(0x4d3522);
  const mud = new THREE.Color(0x2a2822);
  const rock = new THREE.Color(0x3a3e4a);
  const rockDark = new THREE.Color(0x101118);
  const c = new THREE.Color();

  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const z = pos.getZ(i);
    const r = Math.hypot(x, z);
    const R = islandRadiusAt(Math.atan2(z, x));
    let h;
    if (r < R + 0.2) {
      inside[i] = 1;
      h = getHeight(x, z);
    } else {
      h = -3.5 - fbm(x * 0.5, z * 0.5) * 5;
    }
    pos.setY(i, h);

    const dirtW = smoothstep(3.4, 1.2, Math.hypot(x - FIRE.x, z - FIRE.z));
    const mudW = smoothstep(1.4, 1.0, pondMetric(x, z));
    const cliff = h < -0.9 && r > R - 1.5;
    c.copy(grassA).lerp(grassB, fbm(x * 0.3, z * 0.3));
    c.lerp(dirt, dirtW);
    c.lerp(mud, mudW);
    if (cliff) c.copy(rock).lerp(rockDark, Math.min(-h / 7, 1));
    colors[i * 3] = c.r;
    colors[i * 3 + 1] = c.g;
    colors[i * 3 + 2] = c.b;
  }

  // 只保留至少一个顶点在岛内的三角形（边缘三角形自然形成断崖）
  const src = geo.index.array;
  const kept = [];
  for (let i = 0; i < src.length; i += 3) {
    const a = src[i], b = src[i + 1], d = src[i + 2];
    if (inside[a] || inside[b] || inside[d]) kept.push(a, b, d);
  }
  geo.setIndex(kept);
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geo.computeVertexNormals();

  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, metalness: 0 });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.add(createTerrainGlyphs());
  return mesh;
}

// 地表字符：规则网格（等距视角下形成整齐的斜向点阵）+ 断崖竖墙 + 岛屿边缘轮廓
function createTerrainGlyphs() {
  const pts = new GlyphPoints();
  const rand = mulberry32(99);
  const step = 0.3;
  const e = 0.05;
  for (let x = -19; x <= 19; x += step) {
    for (let z = -19; z <= 19; z += step) {
      const r = Math.hypot(x, z);
      const R = islandRadiusAt(Math.atan2(z, x));
      if (r > R - 0.9 || pondMetric(x, z) < 1.02) continue;
      const h = getHeight(x, z);
      const n = new THREE.Vector3(getHeight(x - e, z) - getHeight(x + e, z), 2 * e, getHeight(x, z - e) - getHeight(x, z + e)).normalize();
      let kind = MAT.GROUND;
      if (pondMetric(x, z) < 1.4) kind = MAT.MUD;
      else if (Math.hypot(x - FIRE.x, z - FIRE.z) < 2.6) kind = MAT.PATH;
      pts.add([x, h + 0.02, z], n.toArray(), kind, { seed: rand() });
    }
  }

  // 断崖：沿岛屿边缘一圈竖向排列，顶边用方向字符勾出轮廓
  const segs = 520;
  for (let i = 0; i < segs; i++) {
    const a = (i / segs) * Math.PI * 2;
    const R = islandRadiusAt(a) - 0.6;
    const x = Math.cos(a) * R;
    const z = Math.sin(a) * R;
    const top = getHeight(x, z);
    const out = [Math.cos(a), 0.15, Math.sin(a)];
    const a2 = a + 0.01;
    const R2 = islandRadiusAt(a2) - 0.6;
    const t = new THREE.Vector3(Math.cos(a2) * R2 - x, 0, Math.sin(a2) * R2 - z).normalize();
    pts.add([x, top, z], out, MAT.CLIFF, { seed: rand(), dir: t.toArray() });
    if (i % 2) continue;
    // 沿地形真实的断崖剖面按弧长取点，点落在实体表面上才不会被深度遮挡
    const c = Math.cos(a), s = Math.sin(a);
    let prevR = R;
    let prevY = top;
    let acc = 0;
    for (let rr = R + 0.03; rr < R + 0.8; rr += 0.03) {
      const y = getHeight(c * rr, s * rr);
      acc += Math.hypot(rr - prevR, y - prevY);
      prevR = rr;
      prevY = y;
      if (acc < 0.3) continue;
      acc = 0;
      pts.add([c * rr, y, s * rr], out, MAT.CLIFF, { seed: rand() });
    }
  }
  return makeGlyphField(pts, glyphMaterial('static'));
}
