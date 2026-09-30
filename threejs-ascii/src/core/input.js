import * as THREE from 'three';

// 等距相机下：屏幕“上”对应世界 (-1,0,-1)，屏幕“右”对应 (1,0,-1)
const SCREEN_UP = new THREE.Vector2(-1, -1).normalize();
const SCREEN_RIGHT = new THREE.Vector2(1, -1).normalize();

const MOVE_KEYS = {
  KeyW: 'up', ArrowUp: 'up',
  KeyS: 'down', ArrowDown: 'down',
  KeyA: 'left', ArrowLeft: 'left',
  KeyD: 'right', ArrowRight: 'right',
};

export class Input {
  constructor(onAction) {
    this.held = new Set();
    this.running = false;
    this.move = new THREE.Vector2();

    window.addEventListener('keydown', (e) => {
      if (MOVE_KEYS[e.code]) {
        this.held.add(MOVE_KEYS[e.code]);
        e.preventDefault();
      } else if (!e.repeat) {
        onAction?.(e.code, e);
      }
      if (e.code === 'ShiftLeft' || e.code === 'ShiftRight') this.running = true;
    });
    window.addEventListener('keyup', (e) => {
      if (MOVE_KEYS[e.code]) this.held.delete(MOVE_KEYS[e.code]);
      if (e.code === 'ShiftLeft' || e.code === 'ShiftRight') this.running = false;
    });
    window.addEventListener('blur', () => {
      this.held.clear();
      this.running = false;
    });
  }

  // 返回世界 xz 平面上的单位移动向量
  getMove() {
    const sx = (this.held.has('right') ? 1 : 0) - (this.held.has('left') ? 1 : 0);
    const sy = (this.held.has('up') ? 1 : 0) - (this.held.has('down') ? 1 : 0);
    this.move.set(0, 0).addScaledVector(SCREEN_RIGHT, sx).addScaledVector(SCREEN_UP, sy);
    if (this.move.lengthSq() > 1) this.move.normalize();
    return this.move;
  }
}
