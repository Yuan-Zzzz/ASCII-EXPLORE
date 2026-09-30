import * as THREE from 'three';

// 用 canvas 动态生成网格字符图集（白字黑底，每格留边距避免 mipmap 串色）
export function createGlyphAtlas(chars, size = 64, cols = 16) {
  const list = [...chars];
  const rows = Math.ceil(list.length / cols);
  const canvas = document.createElement('canvas');
  canvas.width = size * cols;
  canvas.height = size * rows;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = '#fff';
  ctx.font = `bold ${Math.floor(size * 0.86)}px Consolas, "DejaVu Sans Mono", "Courier New", monospace`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  list.forEach((ch, i) => {
    const x = (i % cols) * size + size / 2;
    const y = Math.floor(i / cols) * size + size / 2 + size * 0.04;
    ctx.fillText(ch, x, y);
  });

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.NoColorSpace;
  texture.minFilter = THREE.LinearMipmapLinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.generateMipmaps = true;
  return { texture, count: list.length, cols, rows, size, canvas };
}
