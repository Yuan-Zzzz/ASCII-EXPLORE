// 左上角操作说明与状态栏
export class Hud {
  constructor(el) {
    this.el = el;
    this.fps = 60;
    this.el.innerHTML = `<span class="title">~ ASCII 月夜篝火 ~</span>
<span class="help"><span class="key">WASD / 方向键</span>  移动（等距方向）
<span class="key">Shift</span>          奔跑
<span class="key">鼠标滚轮</span>       缩放
<span class="key">T</span>              3D 字符 / 原始模型
<span class="key">[  ]</span>           字符大小 - / +
<span class="key">E</span>              棱边字符开关
<span class="key">F</span>              字符最小间距开关
<span class="key">C</span>              夜色调色板 / 琥珀终端
<span class="key">P</span>              参数面板
<span class="key">H</span>              隐藏帮助</span>
<span class="dim status"></span>`;
    this.status = this.el.querySelector('.status');
    this.acc = 0;
  }

  toggleHelp() {
    this.el.classList.toggle('hidden');
  }

  update(dt, { view, glyphs }) {
    this.fps += (1 / Math.max(dt, 1e-4) - this.fps) * 0.05;
    this.acc += dt;
    if (this.acc < 0.25) return;
    this.acc = 0;
    const palette = glyphs.colorMode ? '琥珀' : '夜色';
    const text = view === 'glyph'
      ? `[3D 字符 · ${palette}] 字符 ${glyphs.glyphSize}px · 棱边 ${glyphs.edges ? '开' : '关'} · 间距 ${glyphs.spacing ? '开' : '关'}`
      : '[原始模型]';
    this.status.textContent = `${text} · ${this.fps.toFixed(0)} fps`;
  }
}
