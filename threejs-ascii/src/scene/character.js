import * as THREE from 'three';
import { POND, getHeight, islandRadiusAt } from './layout.js';
import { attachGlyphs } from '../glyph/GlyphField.js';
import { MAT, PART } from './shared.js';

const RADIUS = 0.32;

// 圆形障碍 + 池塘椭圆 + 岛屿边界的推出式碰撞
function resolveCollision(pos, colliders) {
  for (const c of colliders) {
    const dx = pos.x - c.x;
    const dz = pos.z - c.z;
    const d = Math.hypot(dx, dz);
    const min = c.r + RADIUS;
    if (d < min && d > 1e-6) {
      pos.x = c.x + (dx / d) * min;
      pos.z = c.z + (dz / d) * min;
    }
  }
  const ax = POND.rx * 1.0 + RADIUS;
  const az = POND.rz * 1.0 + RADIUS;
  const ex = (pos.x - POND.x) / ax;
  const ez = (pos.z - POND.z) / az;
  const e = Math.hypot(ex, ez);
  if (e < 1 && e > 1e-6) {
    pos.x = POND.x + (ex / e) * ax;
    pos.z = POND.z + (ez / e) * az;
  }
  const d = Math.hypot(pos.x, pos.z);
  const R = islandRadiusAt(Math.atan2(pos.z, pos.x)) - 1.2;
  if (d > R) {
    pos.x *= R / d;
    pos.z *= R / d;
  }
}

// 低多边形小巫师：斗篷 + 尖帽 + 提灯
export class Character {
  constructor(colliders) {
    this.colliders = colliders;
    this.position = new THREE.Vector3(-2.2, 0, 1.6);
    this.position.y = getHeight(this.position.x, this.position.z);
    this.velocity = new THREE.Vector3();
    this.heading = Math.PI * 0.25;
    this.walkPhase = 0;
    this.moveAmount = 0;

    const std = (part, color, extra = {}) => {
      const m = new THREE.MeshStandardMaterial({ color, roughness: 0.85, flatShading: true, ...extra });
      m.userData.part = part;
      return m;
    };
    // 轻微自发光，保证夜里角色在字符画中依然醒目
    const cloak = std(PART.CLOAK, 0xd4402f, { emissive: 0x5a0c06 });
    const dark = std(PART.LEGS, 0x3a2a24, { emissive: 0x120806 });
    const skin = std(PART.HEAD, 0xf2c79a, { emissive: 0x3a2412 });
    const hatMat = std(PART.HAT, 0x3550c0, { emissive: 0x0c1850 });

    const root = new THREE.Group();
    const body = new THREE.Group();
    root.add(body);
    this.root = root;
    this.body = body;

    const mesh = (geo, mat, parent, x, y, z) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z);
      m.castShadow = true;
      parent.add(m);
      // 角色字符更密，每个部位固定一行字符（帽 ^、头 @、斗篷 #M、腿 |、提灯 *）
      if (mat.userData.part !== undefined) {
        attachGlyphs(m, MAT.PLAYER, { spacing: 0.13, edgeStep: 0.12, threshold: 35, row: mat.userData.part, seed: ++glyphSeed });
      }
      return m;
    };
    let glyphSeed = 900;

    mesh(new THREE.CylinderGeometry(0.2, 0.34, 0.62, 7), cloak, body, 0, 0.78, 0);
    mesh(new THREE.IcosahedronGeometry(0.2, 1), skin, body, 0, 1.25, 0);
    const hat = mesh(new THREE.ConeGeometry(0.28, 0.55, 7), hatMat, body, 0, 1.6, 0);
    hat.rotation.z = -0.18;
    mesh(new THREE.CylinderGeometry(0.34, 0.34, 0.04, 10), hatMat, body, 0, 1.36, 0);
    // 眼睛让朝向更易辨认
    const eyeMat = new THREE.MeshBasicMaterial({ color: 0x111111 });
    eyeMat.userData.part = PART.HEAD;
    mesh(new THREE.SphereGeometry(0.03, 6, 4), eyeMat, body, 0.07, 1.28, 0.18);
    mesh(new THREE.SphereGeometry(0.03, 6, 4), eyeMat, body, -0.07, 1.28, 0.18);

    const limb = (w, h, mat, x, y) => {
      const pivot = new THREE.Group();
      pivot.position.set(x, y, 0);
      mesh(new THREE.BoxGeometry(w, h, w), mat, pivot, 0, -h / 2, 0);
      body.add(pivot);
      return pivot;
    };
    this.legL = limb(0.13, 0.48, dark, 0.11, 0.5);
    this.legR = limb(0.13, 0.48, dark, -0.11, 0.5);
    this.armL = limb(0.1, 0.45, cloak, 0.3, 1.02);
    this.armR = limb(0.1, 0.45, cloak, -0.3, 1.02);

    // 右手提灯
    const lantern = new THREE.Group();
    lantern.position.set(0, -0.5, 0.06);
    this.armR.add(lantern);
    mesh(
      new THREE.BoxGeometry(0.12, 0.16, 0.12),
      Object.assign(new THREE.MeshBasicMaterial({ color: new THREE.Color(2.4, 1.6, 0.6) }), {
        userData: { part: PART.LANTERN },
      }),
      lantern,
      0,
      -0.08,
      0
    );
    const lampLight = new THREE.PointLight(0xffc36b, 6, 6, 1.5);
    lampLight.position.y = -0.08;
    lantern.add(lampLight);
    this.lampLight = lampLight;
  }

  update(dt, move, running, t) {
    const speed = running ? 6.2 : 3.6;
    const target = new THREE.Vector3(move.x, 0, move.y).multiplyScalar(speed);
    this.velocity.lerp(target, 1 - Math.exp(-dt * 12));

    const next = this.position.clone().addScaledVector(this.velocity, dt);
    resolveCollision(next, this.colliders);
    // 实际位移（被挡住后）用于驱动动画
    const moved = Math.hypot(next.x - this.position.x, next.z - this.position.z) / Math.max(dt, 1e-4);
    this.position.x = next.x;
    this.position.z = next.z;
    const groundY = getHeight(next.x, next.z);
    this.position.y += (groundY - this.position.y) * (1 - Math.exp(-dt * 20));

    // 量化转向：目标朝向吸附到等分角度，再以固定步长逐档转过去（方向数与间隔由参数面板控制）
    if (move.lengthSq() > 0.01) {
      const want = Math.atan2(move.x, move.y);
      const step = (Math.PI * 2) / (this.turnDirs ?? 16);
      const snapped = Math.round(want / step) * step;
      let delta = snapped - this.heading;
      while (delta > Math.PI) delta -= Math.PI * 2;
      while (delta < -Math.PI) delta += Math.PI * 2;
      this.turnAcc = (this.turnAcc ?? 0) + dt;
      if (Math.abs(delta) > step * 0.5 && this.turnAcc >= (this.turnInterval ?? 0.09)) {
        this.heading += Math.sign(delta) * step;
        this.turnAcc = 0;
      }
    }

    const amt = Math.min(moved / 3.6, 1.5);
    this.moveAmount += (amt - this.moveAmount) * (1 - Math.exp(-dt * 10));
    this.walkPhase += dt * (4 + moved * 2.2);

    const swing = Math.sin(this.walkPhase) * 0.75 * this.moveAmount;
    this.legL.rotation.x = swing;
    this.legR.rotation.x = -swing;
    this.armL.rotation.x = -swing * 0.8;
    this.armR.rotation.x = swing * 0.5 - 0.15;
    this.armL.rotation.z = 0.1;
    this.armR.rotation.z = -0.1;

    const idle = Math.sin(t * 2.0) * 0.015 * (1 - Math.min(this.moveAmount, 1));
    this.body.position.y = Math.abs(Math.sin(this.walkPhase)) * 0.09 * this.moveAmount + idle;
    this.body.rotation.x = this.moveAmount * 0.12;

    this.lampLight.intensity = 6 + Math.sin(t * 9) * 0.4;
    this.root.position.copy(this.position);
    this.root.rotation.y = this.heading;
  }
}
