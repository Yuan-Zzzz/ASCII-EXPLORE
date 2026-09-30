import * as THREE from 'three';
import { mulberry32 } from '../utils/math.js';
import { FIRE, getHeight, islandRadiusAt, pondMetric } from './layout.js';
import { attachGlyphs } from '../glyph/GlyphField.js';
import { MAT, applyWind } from './shared.js';

// 风摆参数 [强度, 起始高度]：实体网格和字符点必须一致，否则字符会和深度遮挡错位
const WIND = { trunk: [0.004, 0.2], pine: [0.012, 0.4], leaf: [0.014, 0.4] };

// 树木 + 岩石 + 篝火边的原木长凳，返回碰撞圆
export function createForest() {
  const group = new THREE.Group();
  const colliders = [];
  const rand = mulberry32(20260929);

  const std = (color, rough) => new THREE.MeshStandardMaterial({ color, roughness: rough, flatShading: true });
  const trunkMat = applyWind(std(0x5e4029, 1), ...WIND.trunk);
  const pineMats = [0x2b5c3d, 0x357046, 0x244e35].map((c) => applyWind(std(c, 0.95), ...WIND.pine));
  const leafMat = applyWind(std(0x467f38, 0.9), ...WIND.leaf);
  const rockMat = std(0x5a5f6c, 1);
  const logMat = std(0x5b3b24, 1);

  const add = (mesh, parent) => {
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    parent.add(mesh);
    return mesh;
  };

  // --- 树 ---
  const trees = [];
  for (let tries = 0; trees.length < 30 && tries < 3000; tries++) {
    const a = rand() * Math.PI * 2;
    const r = 4 + rand() * 13;
    const x = Math.cos(a) * r;
    const z = Math.sin(a) * r;
    if (r > islandRadiusAt(a) - 1.8) continue;
    if (pondMetric(x, z) < 1.6) continue;
    if (Math.hypot(x - FIRE.x, z - FIRE.z) < 4.5) continue;
    if (trees.some((t) => Math.hypot(t.x - x, t.z - z) < 2.5)) continue;
    trees.push({ x, z, pine: rand() < 0.65, s: 0.8 + rand() * 0.6, rot: rand() * Math.PI * 2 });
  }

  for (const t of trees) {
    const tree = new THREE.Group();
    tree.position.set(t.x, getHeight(t.x, t.z) - 0.05, t.z);
    tree.rotation.y = t.rot;
    tree.scale.setScalar(t.s);
    const glyphSeed = Math.floor(rand() * 1e6);
    if (t.pine) {
      const trunk = add(new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.22, 1.2, 6), trunkMat), tree);
      trunk.position.y = 0.6;
      attachGlyphs(trunk, MAT.TRUNK, { spacing: 0.22, edgeStep: 0.18, wind: WIND.trunk, seed: glyphSeed });
      for (let i = 0; i < 3; i++) {
        const cone = add(new THREE.Mesh(new THREE.ConeGeometry(1.25 - i * 0.32, 1.5, 7), pineMats[i % 3]), tree);
        cone.position.y = 1.35 + i * 0.8;
        cone.rotation.y = i * 0.7;
        attachGlyphs(cone, MAT.PINE, { spacing: 0.32, edgeStep: 0.17, wind: WIND.pine, seed: glyphSeed + i + 1 });
      }
    } else {
      const trunk = add(new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.26, 1.8, 6), trunkMat), tree);
      trunk.position.y = 0.9;
      attachGlyphs(trunk, MAT.TRUNK, { spacing: 0.22, edgeStep: 0.18, wind: WIND.trunk, seed: glyphSeed });
      const blobs = [
        [0, 2.3, 0, 1.15],
        [0.55, 1.95, 0.3, 0.75],
        [-0.5, 2.0, -0.25, 0.8],
      ];
      blobs.forEach(([bx, by, bz, br], i) => {
        const blob = add(new THREE.Mesh(new THREE.IcosahedronGeometry(br, 0), leafMat), tree);
        blob.position.set(bx, by, bz);
        attachGlyphs(blob, MAT.LEAF, { spacing: 0.3, edgeStep: 0.17, wind: WIND.leaf, seed: glyphSeed + i + 1 });
      });
    }
    group.add(tree);
    colliders.push({ x: t.x, z: t.z, r: 0.42 * t.s });
  }

  // --- 岩石 ---
  for (let tries = 0, n = 0; n < 9 && tries < 800; tries++) {
    const a = rand() * Math.PI * 2;
    const r = 3.5 + rand() * 12;
    const x = Math.cos(a) * r;
    const z = Math.sin(a) * r;
    if (r > islandRadiusAt(a) - 1.2 || pondMetric(x, z) < 1.3) continue;
    if (colliders.some((c) => Math.hypot(c.x - x, c.z - z) < c.r + 1.5)) continue;
    const s = 0.35 + rand() * 0.5;
    const rockMesh = add(new THREE.Mesh(new THREE.DodecahedronGeometry(s, 0), rockMat), group);
    rockMesh.position.set(x, getHeight(x, z) + s * 0.35, z);
    rockMesh.scale.set(1, 0.7 + rand() * 0.4, 1 + rand() * 0.3);
    rockMesh.rotation.set(rand(), rand() * 6, rand());
    attachGlyphs(rockMesh, MAT.ROCK, { spacing: 0.24, edgeStep: 0.15, seed: tries + 7 });
    colliders.push({ x, z, r: s * 1.05 });
    n++;
  }
  // 池塘边的几块小石头（纯装饰）
  for (let i = 0; i < 7; i++) {
    const a = rand() * Math.PI * 2;
    const x = 5.2 + Math.cos(a) * 4.2 * 1.08;
    const z = 4.6 + Math.sin(a) * 3.0 * 1.08;
    const s = 0.12 + rand() * 0.18;
    const pebble = add(new THREE.Mesh(new THREE.DodecahedronGeometry(s, 0), rockMat), group);
    pebble.position.set(x, getHeight(x, z) + s * 0.3, z);
    attachGlyphs(pebble, MAT.ROCK, { surface: false, edgeStep: 0.14, seed: 300 + i });
  }

  // --- 原木长凳 ---
  for (const [ang, len] of [
    [-2.4, 1.8],
    [0.9, 1.5],
  ]) {
    const x = FIRE.x + Math.cos(ang) * 2.3;
    const z = FIRE.z + Math.sin(ang) * 2.3;
    const log = add(new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.24, len, 8), logMat), group);
    log.position.set(x, getHeight(x, z) + 0.2, z);
    log.rotation.z = Math.PI / 2;
    log.rotation.y = -ang + Math.PI / 2;
    attachGlyphs(log, MAT.LOG, { spacing: 0.2, edgeStep: 0.16, threshold: 40, seed: 500 + len * 10 });
    colliders.push({ x, z, r: 0.55 });
    colliders.push({ x: x + Math.sin(ang) * len * 0.35, z: z - Math.cos(ang) * len * 0.35, r: 0.4 });
    colliders.push({ x: x - Math.sin(ang) * len * 0.35, z: z + Math.cos(ang) * len * 0.35, r: 0.4 });
  }

  return { group, colliders };
}
