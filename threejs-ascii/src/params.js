// 可调参数：面板、快捷键和渲染器共用这一份；defaults 在创建时冻结，恢复默认不会被后续修改污染
export function createParams() {
  const params = {
    glyphSize: 12,
    edges: true,
    spacing: true,
    edgeDisk: 0.5,
    edgePriority: 0.3,
    glyphDither: 0.55,
    turnDirs: 16,
    turnInterval: 0.09,
    amber: false,
    zoom: 1,
  };
  const snapshot = { ...params };
  params.defaults = () => ({ ...snapshot });
  return params;
}
