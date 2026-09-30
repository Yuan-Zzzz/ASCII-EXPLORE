import { fbm, smoothstep } from '../utils/math.js';

// 场景布局：浮空小岛、篝火在中心、池塘在篝火前方（朝向镜头）
export const FIRE = { x: 0, z: 0 };
export const POND = { x: 5.2, z: 4.6, rx: 4.2, rz: 3.0, level: -0.28 };

export function islandRadiusAt(angle) {
  return (
    17 +
    1.6 * Math.sin(3 * angle + 0.5) +
    0.9 * Math.sin(7 * angle + 1.3) +
    0.5 * Math.sin(11 * angle + 2.1)
  );
}

// 池塘椭圆度量：<1 在椭圆内
export function pondMetric(x, z) {
  const dx = (x - POND.x) / POND.rx;
  const dz = (z - POND.z) / POND.rz;
  return Math.sqrt(dx * dx + dz * dz);
}

export function getHeight(x, z) {
  const r = Math.hypot(x, z);
  const R = islandRadiusAt(Math.atan2(z, x));
  let h = (fbm(x * 0.12 + 10, z * 0.12 - 4) - 0.45) * 0.9;
  // 篝火周围压平
  const dFire = Math.hypot(x - FIRE.x, z - FIRE.z);
  h *= 0.2 + 0.8 * smoothstep(1.5, 5, dFire);
  // 池塘凹陷
  h -= smoothstep(1.35, 0.55, pondMetric(x, z)) * 1.1;
  // 岛屿边缘断崖
  const edge = smoothstep(R - 0.8, R + 0.2, r);
  return h * (1 - edge) - edge * 3.0;
}
