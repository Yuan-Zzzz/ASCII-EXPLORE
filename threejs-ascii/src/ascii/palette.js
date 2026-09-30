// 限定调色板（显示空间 sRGB）：夜色蓝为底，只有火光暖色与月光冷白作为强调
export const PALETTE = {
  night0: '#04060d',
  night1: '#0a1024',
  night2: '#16213f',
  night3: '#2b3c68',
  moon0: '#8095cc',
  moon1: '#e4ecff',
  fire0: '#2c0b06',
  fire1: '#8c2614',
  fire2: '#e2672a',
  fire3: '#ffc36a',
  fire4: '#fff3d4',
  green0: '#0b211b',
  green1: '#1e4a35',
  green2: '#4f8f5c',
  brown0: '#22150e',
  brown1: '#5f3e27',
  red: '#d6392b',
  glow: '#d8ff8c',
};

// 火光照亮时替换的暖色梯度（5 级前景色）
export const WARM_RAMP = ['fire1', 'fire1', 'fire2', 'fire3', 'fire4'];

export function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
