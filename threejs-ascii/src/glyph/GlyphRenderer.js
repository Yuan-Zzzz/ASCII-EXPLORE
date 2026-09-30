import * as THREE from 'three';
import { LEVELS, VARIANTS } from '../ascii/glyphs.js';
import { PALETTE } from '../ascii/palette.js';
import { MAT } from '../scene/shared.js';
import { GLYPH_LAYER, glyphUniforms, spaceVariant } from './GlyphField.js';

// 天空：按字符格画星点与月亮，只在深度仍为清屏值（无实体）处绘制
const skyFragment = /* glsl */ `
uniform sampler2D tGlyphs;
uniform sampler2D tColors;
uniform sampler2D tAtlas;
uniform vec2 uAtlasGrid;
uniform float uAtlasPx;
uniform vec2 uResolution;
uniform float uGlyphPx;
uniform float uTime;
varying vec2 vUv;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 frag = vUv * uResolution;
  vec2 cell = floor(frag / uGlyphPx);
  vec2 cuv = (cell + 0.5) * uGlyphPx / uResolution;
  vec2 mp = (cuv - vec2(0.84, 0.82)) * vec2(uResolution.x / uResolution.y, 1.0);
  float r = length(mp);
  float R = 0.07;
  int row = 0;
  if (r < R) {
    row = hash12(floor((mp + 1.0) * 38.0)) > 0.72 ? 2 : 4;
  } else if (r < R * 1.7) {
    row = hash12(cell + 7.1) > 0.6 ? 1 : 0;
  } else {
    float h = hash12(cell);
    if (h > 0.97) {
      float tw = 0.5 + 0.5 * sin(uTime * (1.5 + h * 4.0) + h * 80.0);
      row = 1 + int(fract(h * 37.0) * 1.999 + tw * 0.999);
    }
  }
  if (row == 0) discard;
  int v = int(hash12(cell * 1.37) * 3.999);
  float gi = texelFetch(tGlyphs, ivec2(row * VARIANTS + v, M_SKY), 0).r * 255.0;
  vec2 local = fract(frag / uGlyphPx);
  vec2 g = vec2(mod(gi, uAtlasGrid.x), floor(gi / uAtlasGrid.x));
  vec2 uv = vec2((g.x + local.x) / uAtlasGrid.x, 1.0 - (g.y + 1.0 - local.y) / uAtlasGrid.y);
  float m = textureLod(tAtlas, uv, max(log2(uAtlasPx / uGlyphPx) - 0.5, 0.0)).r;
  if (m < 0.35) discard;
  gl_FragColor = vec4(texelFetch(tColors, ivec2(row, M_SKY), 0).rgb * smoothstep(0.35, 0.75, m), 1.0);
}
`;

// 3D 字符渲染：实体深度预渲染（只写深度，负责遮挡）-> 天空 -> 字符点
export class GlyphRenderer {
  constructor(renderer, scene, hiddenInDepth = []) {
    this.renderer = renderer;
    this.scene = scene;
    this.glyphSize = 12;
    this.edges = true;
    this.colorMode = 0;
    this.spacing = true;
    this.edgeDisk = 0.5;
    this.dither = 0.55;
    this.hiddenInDepth = hiddenInDepth;
    this.bias = 0.25;
    // 棱边字符在间距竞争中向前的世界距离
    this.edgeBias = 0.3;
    this.clearColor = new THREE.Color(PALETTE.night0);

    this.skyMaterial = new THREE.ShaderMaterial({
      defines: { VARIANTS, LEVELS, M_SKY: MAT.SKY },
      uniforms: { ...glyphUniforms, uTime: { value: 0 } },
      vertexShader: /* glsl */ `
        varying vec2 vUv;
        void main() { vUv = uv; gl_Position = vec4(position.xy, 1.0, 1.0); }`,
      fragmentShader: skyFragment,
      depthFunc: THREE.LessEqualDepth,
      depthWrite: false,
    });
    const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.skyMaterial);
    quad.frustumCulled = false;
    this.skyScene = new THREE.Scene();
    this.skyScene.add(quad);
    this.skyCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  }

  setSize(width, height, dpr) {
    this.dpr = dpr;
    glyphUniforms.uResolution.value.set(Math.floor(width * dpr), Math.floor(height * dpr));
  }

  // 字符像素尺寸取偶数，保证方块四角落在整数像素上
  get glyphPx() {
    return Math.max(6, Math.round((this.glyphSize * this.dpr) / 2) * 2);
  }

  collectSolids() {
    this.solids = new Set();
    this.fields = [];
    this.scene.traverse((o) => {
      if (!o.isMesh) return;
      if (o.layers.isEnabled(GLYPH_LAYER)) this.fields.push(o);
      else if (o.layers.isEnabled(0) && !o.material.transparent) this.solids.add(o.material);
    });
  }

  depthPrepass(camera) {
    for (const o of this.hiddenInDepth) o.visible = false;
    for (const m of this.solids) m.colorWrite = false;
    camera.layers.set(0);
    this.renderer.render(this.scene, camera);
    for (const m of this.solids) m.colorWrite = true;
    for (const o of this.hiddenInDepth) o.visible = true;
  }

  // 间距 pass：每个字符点画成直径等于字符宽的圆盘，深度竞争决定每处留下谁（棱边优先、近处优先）
  renderSpacing(camera) {
    const { renderer, scene } = this;
    const res = glyphUniforms.uResolution.value;
    const step = Math.max(2, Math.round(this.glyphPx / 4));
    const w = Math.ceil(res.x / step);
    const h = Math.ceil(res.y / step);
    if (!this.spacingTarget) {
      this.spacingTarget = new THREE.WebGLRenderTarget(w, h, {
        type: THREE.HalfFloatType,
        minFilter: THREE.LinearFilter,
        magFilter: THREE.LinearFilter,
        depthBuffer: true,
      });
    } else if (this.spacingTarget.width !== w || this.spacingTarget.height !== h) {
      this.spacingTarget.setSize(w, h);
    }
    glyphUniforms.uEdgeBias.value = (2 * this.edgeBias) / (camera.far - camera.near);

    renderer.setRenderTarget(this.spacingTarget);
    renderer.setClearColor(0x000000, 0);
    renderer.clear();
    this.depthPrepass(camera);

    const saved = this.fields.map((f) => f.material);
    for (const f of this.fields) f.material = spaceVariant(f.material);
    camera.layers.set(GLYPH_LAYER);
    renderer.render(scene, camera);
    camera.layers.set(0);
    this.fields.forEach((f, i) => (f.material = saved[i]));

    renderer.setRenderTarget(null);
    glyphUniforms.tSpacing.value = this.spacingTarget.texture;
  }

  render(camera, time) {
    const { renderer, scene } = this;
    if (!this.solids) this.collectSolids();
    glyphUniforms.uGlyphPx.value = this.glyphPx;
    glyphUniforms.uDepthBias.value = (2 * this.bias) / (camera.far - camera.near);
    glyphUniforms.uShowEdges.value = this.edges ? 1 : 0;
    glyphUniforms.uSpacing.value = this.spacing ? 1 : 0;
    glyphUniforms.uEdgeDisk.value = this.edgeDisk;
    glyphUniforms.uDither.value = this.dither;
    glyphUniforms.uAmber.value = this.colorMode;
    this.skyMaterial.uniforms.uTime.value = time;

    const autoClear = renderer.autoClear;
    renderer.autoClear = false;
    renderer.setRenderTarget(null);
    renderer.setClearColor(this.colorMode ? 0x050300 : this.clearColor, 1);
    renderer.clear();

    if (this.spacing) this.renderSpacing(camera);
    this.depthPrepass(camera);

    renderer.render(this.skyScene, this.skyCamera);

    camera.layers.set(GLYPH_LAYER);
    renderer.render(scene, camera);
    camera.layers.set(0);
    renderer.autoClear = autoClear;
  }
}
