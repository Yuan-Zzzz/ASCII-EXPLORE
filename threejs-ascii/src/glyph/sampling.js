import * as THREE from 'three';
import { MeshSurfaceSampler } from 'three/examples/jsm/math/MeshSurfaceSampler.js';

// 沿模型的特征棱（相邻面夹角 > threshold）等距取点，记录棱方向，用于选 | / - \ 字符
export function sampleEdges(geometry, step, thresholdDeg = 25) {
  const edges = new THREE.EdgesGeometry(geometry, thresholdDeg);
  const p = edges.attributes.position;
  const pos = [];
  const dir = [];
  const a = new THREE.Vector3();
  const b = new THREE.Vector3();
  const d = new THREE.Vector3();
  for (let i = 0; i < p.count; i += 2) {
    a.fromBufferAttribute(p, i);
    b.fromBufferAttribute(p, i + 1);
    d.subVectors(b, a);
    const len = d.length();
    if (len < 1e-5) continue;
    d.divideScalar(len);
    const n = Math.max(1, Math.round(len / step));
    for (let k = 0; k <= n; k++) {
      pos.push(a.x + d.x * len * (k / n), a.y + d.y * len * (k / n), a.z + d.z * len * (k / n));
      dir.push(d.x, d.y, d.z);
    }
  }
  edges.dispose();
  return dedupe({ pos, dir }, step * 0.45);
}

// 表面按面积随机取点，再用空间哈希剔除过近的点（近似泊松分布，字符不扎堆）
export function sampleSurface(geometry, spacing, rand = Math.random) {
  const mesh = new THREE.Mesh(geometry);
  const sampler = new MeshSurfaceSampler(mesh).setRandomGenerator(rand).build();
  let area = 0;
  const idx = geometry.index;
  const p = geometry.attributes.position;
  const tri = new THREE.Triangle();
  const triCount = idx ? idx.count / 3 : p.count / 3;
  for (let i = 0; i < triCount; i++) {
    const [i0, i1, i2] = idx ? [idx.getX(i * 3), idx.getX(i * 3 + 1), idx.getX(i * 3 + 2)] : [i * 3, i * 3 + 1, i * 3 + 2];
    tri.a.fromBufferAttribute(p, i0);
    tri.b.fromBufferAttribute(p, i1);
    tri.c.fromBufferAttribute(p, i2);
    area += tri.getArea();
  }
  const candidates = Math.ceil((area / (spacing * spacing)) * 2.2);
  const hash = new Map();
  const cell = spacing;
  const key = (x, y, z) => `${Math.floor(x / cell)},${Math.floor(y / cell)},${Math.floor(z / cell)}`;
  const pos = [];
  const nrm = [];
  const v = new THREE.Vector3();
  const n = new THREE.Vector3();
  const min2 = spacing * spacing * 0.8;
  for (let i = 0; i < candidates; i++) {
    sampler.sample(v, n);
    const cx = Math.floor(v.x / cell), cy = Math.floor(v.y / cell), cz = Math.floor(v.z / cell);
    let ok = true;
    for (let dx = -1; dx <= 1 && ok; dx++)
      for (let dy = -1; dy <= 1 && ok; dy++)
        for (let dz = -1; dz <= 1 && ok; dz++) {
          const list = hash.get(`${cx + dx},${cy + dy},${cz + dz}`);
          if (list) for (const q of list) if (v.distanceToSquared(q) < min2) { ok = false; break; }
        }
    if (!ok) continue;
    const k = key(v.x, v.y, v.z);
    if (!hash.has(k)) hash.set(k, []);
    hash.get(k).push(v.clone());
    pos.push(v.x, v.y, v.z);
    nrm.push(n.x, n.y, n.z);
  }
  return { pos, nrm };
}

// 合并棱交点处重复的点
function dedupe({ pos, dir }, eps) {
  const seen = new Map();
  const out = { pos: [], dir: [] };
  for (let i = 0; i < pos.length; i += 3) {
    const k = `${Math.round(pos[i] / eps)},${Math.round(pos[i + 1] / eps)},${Math.round(pos[i + 2] / eps)}`;
    if (seen.has(k)) continue;
    seen.set(k, true);
    out.pos.push(pos[i], pos[i + 1], pos[i + 2]);
    out.dir.push(dir[i], dir[i + 1], dir[i + 2]);
  }
  return out;
}
