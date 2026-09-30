import * as THREE from 'three';

// 各自定义着色器共享的全局 uniform（引用同一对象，改一处全部生效）
export const globalUniforms = {
  uTime: { value: 0 },
  uPxPerUnit: { value: 40 },
  uPlayer: { value: new THREE.Vector3() },
  uFirePos: { value: new THREE.Vector3(0, 0.6, 0) },
  uFireI: { value: 1 },
  uFireColor: { value: new THREE.Color(1.0, 0.42, 0.12) },
  uMoonDir: { value: new THREE.Vector3(-0.35, 0.75, 0.6).normalize() },
  uMoonColor: { value: new THREE.Color(0.5, 0.62, 1.0) },
  uWindDir: { value: new THREE.Vector2(0.8, 0.6).normalize() },
};

// 物体类型 ID：写入 MRT 第二个缓冲的 r 通道，ASCII pass 据此选字符与配色（0 为天空/清屏值）
export const MAT = {
  SKY: 0,
  GROUND: 1,
  PATH: 2,
  MUD: 3,
  CLIFF: 4,
  GRASS: 5,
  WATER: 6,
  TRUNK: 7,
  PINE: 8,
  LEAF: 9,
  ROCK: 10,
  LOG: 11,
  FIRE: 12,
  EMBER: 13,
  PLAYER: 14,
  FIREFLY: 15,
};
export const MAT_COUNT = 16;

// 角色部位，决定该部位用字符表的哪一行
export const PART = { HEAD: 0, HAT: 1, CLOAK: 2, LEGS: 3, LANTERN: 4 };

export function fogUniforms() {
  return THREE.UniformsUtils.clone(THREE.UniformsLib.fog);
}

// 给标准材质注入风摆：按世界高度的平方偏移，基于物体位置错开相位
export function applyWind(material, strength, base = 0.3) {
  material.onBeforeCompile = (shader) => {
    shader.uniforms.uTime = globalUniforms.uTime;
    shader.uniforms.uWindDir = globalUniforms.uWindDir;
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nuniform float uTime;\nuniform vec2 uWindDir;')
      .replace(
        '#include <project_vertex>',
        `
        vec4 swayWorld = modelMatrix * vec4(transformed, 1.0);
        float swayH = max(swayWorld.y - ${base.toFixed(3)}, 0.0);
        float swayPh = uTime * 1.3 + modelMatrix[3].x * 0.35 + modelMatrix[3].z * 0.27;
        float swayS = sin(swayPh) + 0.35 * sin(swayPh * 2.7 + 1.3) + 0.6;
        swayWorld.xz += uWindDir * swayS * ${strength.toFixed(4)} * swayH * swayH;
        swayWorld.x += cos(swayPh * 0.7) * ${(strength * 0.4).toFixed(4)} * swayH * swayH;
        vec4 mvPosition = viewMatrix * swayWorld;
        gl_Position = projectionMatrix * mvPosition;
        `
      );
  };
  material.customProgramCacheKey = () => `wind_${strength}_${base}`;
  return material;
}
