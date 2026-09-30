// 右上角参数面板：改一处，3D 字符与网格 ASCII 两种模式同时生效
const GROUPS = [
  {
    title: '字符',
    items: [
      { key: 'glyphSize', label: '字符大小', min: 6, max: 24, step: 1, unit: 'px' },
      { key: 'edges', label: '棱边字符', type: 'toggle' },
      { key: 'spacing', label: '最小间距', type: 'toggle' },
      { key: 'edgeDisk', label: '棱边占位比例', min: 0.2, max: 1, step: 0.05 },
      { key: 'edgePriority', label: '棱边优先距离', min: 0, max: 1, step: 0.05 },
    ],
  },
  {
    title: '抖动',
    items: [
      { key: 'glyphDither', label: '字符边缘抖动', min: 0, max: 1, step: 0.05 },
    ],
  },
  {
    title: '转向',
    items: [
      { key: 'turnDirs', label: '转向方向数', min: 4, max: 32, step: 4 },
      { key: 'turnInterval', label: '每档间隔', min: 0.02, max: 0.3, step: 0.01, unit: 's' },
    ],
  },
  {
    title: '画面',
    items: [
      { key: 'amber', label: '琥珀终端', type: 'toggle' },
      { key: 'zoom', label: '缩放', min: 0.6, max: 2.4, step: 0.1 },
    ],
  },
];

export class Panel {
  constructor(el, params, onChange) {
    this.el = el;
    this.params = params;
    this.onChange = onChange;
    this.inputs = new Map();

    el.innerHTML = GROUPS.map(
      (g) => `<div class="group"><div class="gtitle">${g.title}</div>${g.items
        .map((it) => this.row(it))
        .join('')}</div>`
    ).join('') + `<button class="reset" type="button">恢复默认</button>`;

    el.querySelectorAll('input').forEach((input) => {
      this.inputs.set(input.dataset.key, input);
      input.addEventListener('input', () => {
        const it = this.item(input.dataset.key);
        params[it.key] = it.type === 'toggle' ? input.checked : Number(input.value);
        this.refresh(it.key);
        onChange(it.key);
      });
    });
    el.querySelector('.reset').addEventListener('click', () => {
      Object.assign(params, params.defaults());
      this.refresh();
      onChange('*');
    });
    this.refresh();
  }

  item(key) {
    for (const g of GROUPS) for (const it of g.items) if (it.key === key) return it;
    return null;
  }

  row(it) {
    if (it.type === 'toggle') return `<label class="row"><span>${it.label}</span><input type="checkbox" data-key="${it.key}"></label>`;
    return `<label class="row"><span>${it.label}</span><input type="range" data-key="${it.key}" min="${it.min}" max="${it.max}" step="${it.step}"><b></b></label>`;
  }

  // 键盘快捷键改了参数后调用，让滑块跟着变
  refresh(only) {
    for (const [key, input] of this.inputs) {
      if (only && only !== key) continue;
      const it = this.item(key);
      if (it.type === 'toggle') input.checked = !!this.params[key];
      else {
        input.value = this.params[key];
        input.parentElement.querySelector('b').textContent = `${Number(this.params[key]).toFixed(it.step < 1 ? 2 : 0)}${it.unit ?? ''}`;
      }
    }
  }

  toggle() {
    this.el.classList.toggle('hidden');
  }
}
