import * as THREE from 'three';
import './style.css';
import { CameraRig } from './core/cameraRig.js';
import { Input } from './core/input.js';
import { createFireflies, createMist } from './scene/atmosphere.js';
import { createCampfire } from './scene/campfire.js';
import { Character } from './scene/character.js';
import { GlyphRenderer } from './glyph/GlyphRenderer.js';
import { createGrass, createGrassGlyphs } from './scene/grass.js';
import { createLights } from './scene/lights.js';
import { globalUniforms } from './scene/shared.js';
import { createTerrain } from './scene/terrain.js';
import { createForest } from './scene/trees.js';
import { createWater } from './scene/water.js';
import { createParams } from './params.js';
import { Hud } from './ui/hud.js';
import { Panel } from './ui/panel.js';

const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance' });
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
document.getElementById('app').appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0x080d1c, 44, 85);

// --- 场景搭建 ---
const lights = createLights(scene);
scene.add(createTerrain());
const forest = createForest();
scene.add(forest.group);
const campfire = createCampfire();
scene.add(campfire.group);
const colliders = [...forest.colliders, campfire.collider];
const grass = createGrass(colliders);
scene.add(grass, createGrassGlyphs(colliders));
scene.add(createWater());
const fireflies = createFireflies();
scene.add(fireflies.points, fireflies.glyphs);
const mist = createMist();
scene.add(mist);

const player = new Character(colliders);
scene.add(player.root);

const rig = new CameraRig(17);
// 草叶、粒子、薄雾不参与深度预渲染，否则会挡住它们后面的字符
const glyphs = new GlyphRenderer(renderer, scene, [grass, mist, fireflies.points, ...campfire.particles]);
const hud = new Hud(document.getElementById('hud'));
const params = createParams();

// 把参数写进渲染器、角色和相机
function applyParams() {
  glyphs.glyphSize = params.glyphSize;
  glyphs.edges = params.edges;
  glyphs.spacing = params.spacing;
  glyphs.edgeDisk = params.edgeDisk;
  glyphs.edgeBias = params.edgePriority;
  glyphs.dither = params.glyphDither;
  glyphs.colorMode = params.amber ? 1 : 0;
  player.turnDirs = params.turnDirs;
  player.turnInterval = params.turnInterval;
  rig.zoomTarget = params.zoom;
}
applyParams();
const panel = new Panel(document.getElementById('panel'), params, () => applyParams());

// 视图：3D 字符（默认）/ 原始模型
const VIEWS = ['glyph', 'raw'];
let view = 'glyph';
function setView(v) {
  view = v;
}
setView('glyph');

// --- 输入 ---
const input = new Input((code) => {
  if (code === 'KeyT') setView(VIEWS[(VIEWS.indexOf(view) + 1) % VIEWS.length]);
  else if (code === 'KeyE') params.edges = !params.edges;
  else if (code === 'KeyF') params.spacing = !params.spacing;
  else if (code === 'KeyC') params.amber = !params.amber;
  else if (code === 'KeyH') hud.toggleHelp();
  else if (code === 'KeyP') panel.toggle();
  else if (code === 'BracketLeft' || code === 'BracketRight') {
    const d = code === 'BracketLeft' ? -1 : 1;
    params.glyphSize = THREE.MathUtils.clamp(params.glyphSize + d, 6, 24);
  }
  else return;
  applyParams();
  panel.refresh();
});
window.addEventListener(
  'wheel',
  (e) => {
    rig.zoomBy(e.deltaY > 0 ? 0.9 : 1.1);
    params.zoom = rig.zoomTarget;
    panel.refresh('zoom');
  },
  { passive: true }
);

function resize() {
  const w = window.innerWidth;
  const h = window.innerHeight;
  const dpr = Math.min(window.devicePixelRatio, 1.5);
  renderer.setPixelRatio(dpr);
  renderer.setSize(w, h, false);
  glyphs.setSize(w, h, dpr);
  rig.resize(w / h);
}
window.addEventListener('resize', resize);
resize();

// --- 主循环 ---
const start = performance.now();
let last = start;
let first = true;
renderer.setAnimationLoop(() => {
  const now = performance.now();
  const dt = Math.min((now - last) / 1000, 0.05);
  last = now;
  const t = (now - start) / 1000;
  globalUniforms.uTime.value = t;

  player.update(dt, input.getMove(), input.running, t);
  globalUniforms.uPlayer.value.copy(player.position);
  campfire.update(t);
  lights.update(rig.target);

  const heightPx = renderer.domElement.height;
  rig.update(dt, player.position, 0, first);
  first = false;
  globalUniforms.uPxPerUnit.value = rig.pxPerUnit(heightPx);

  hud.update(dt, { view, glyphs });
  if (view === 'glyph') glyphs.render(rig.camera, t);
  else {
    renderer.setRenderTarget(null);
    renderer.setClearColor(0x04060d, 1);
    renderer.render(scene, rig.camera);
  }
});

// 调试入口（便于自动化测试）
window.__game = { player, glyphs, rig, input, setView };
