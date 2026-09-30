import * as THREE from 'three';
import { globalUniforms } from './shared.js';

// 冷色月光（带阴影，跟随角色）+ 半球环境光
export function createLights(scene) {
  const hemi = new THREE.HemisphereLight(0x4a5f9a, 0x10101a, 1.8);
  scene.add(hemi);

  const moon = new THREE.DirectionalLight(0x9db2ff, 2.8);
  moon.castShadow = true;
  moon.shadow.mapSize.set(2048, 2048);
  const s = moon.shadow.camera;
  s.left = -22;
  s.right = 22;
  s.top = 22;
  s.bottom = -22;
  s.near = 1;
  s.far = 80;
  moon.shadow.bias = -0.0008;
  moon.shadow.normalBias = 0.03;
  scene.add(moon, moon.target);

  const dir = globalUniforms.uMoonDir.value;
  function update(focus) {
    moon.target.position.copy(focus);
    moon.position.copy(focus).addScaledVector(dir, 35);
    moon.target.updateMatrixWorld();
  }
  update(new THREE.Vector3());
  return { moon, hemi, update };
}
