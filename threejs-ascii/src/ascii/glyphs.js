import * as THREE from 'three';
import { MAT, MAT_COUNT } from '../scene/shared.js';
import { createGlyphAtlas } from './atlas.js';
import { PALETTE, WARM_RAMP, hexToRgb } from './palette.js';

export const LEVELS = 5;
export const VARIANTS = 4;

// 每种物体：5 行（按亮度等级，或按 g 通道语义）× 4 个变体字符，外加每行的前景色（字符无背景）
// 草的 4 个变体固定为 [左倾, 直立, 右倾, 草簇]；火/火星按生命周期分行；角色按部位分行
const SPECS = {
  [MAT.SKY]: {
    rows: ['    ', '..·.', '+.+·', '*+*+', '@O@0'],
    fg: ['night0', 'night3', 'moon0', 'moon1', 'moon1'],
  },
  [MAT.GROUND]: {
    rows: ['    ', '  . ', ' ,. ', ".,',", ",'.\""],
    fg: ['green0', 'green1', 'green1', 'green2', 'green2'],
  },
  [MAT.PATH]: {
    rows: ['  . ', ' . :', '.:.·', ':·.:', '·:·:'],
    fg: ['brown0', 'brown1', 'brown1', 'moon0', 'moon1'],
  },
  [MAT.MUD]: {
    rows: ['    ', ' .  ', '.~. ', '~.,~', '~,~.'],
    fg: ['brown0', 'brown1', 'brown1', 'night3', 'moon0'],
  },
  [MAT.CLIFF]: {
    rows: [' . |', '|.:|', '|:#|', '#|/\\', '#/\\#'],
    fg: ['night2', 'night3', 'night3', 'moon0', 'moon0'],
  },
  [MAT.GRASS]: {
    rows: [',.,.', "\\'/,", '\\|/"', '\\|/v', '\\|/Y'],
    fg: ['green0', 'green1', 'green1', 'green2', 'green2'],
  },
  [MAT.WATER]: {
    rows: ['  - ', ' -~ ', '~-~=', '~≈~=', '≈*~*'],
    fg: ['night3', 'night3', 'moon0', 'moon0', 'moon1'],
  },
  [MAT.TRUNK]: {
    rows: ['|:|!', '|!|:', '|H!|', 'H|#|', '#H|H'],
    fg: ['brown1', 'brown1', 'brown1', 'moon0', 'moon1'],
  },
  // 没有底色块，树冠靠更密的字符保持完整剪影
  [MAT.PINE]: {
    rows: ['^:^A', '^A^^', 'A^AM', 'AMAM', 'AMA^'],
    fg: ['green1', 'green1', 'green2', 'green2', 'moon1'],
  },
  [MAT.LEAF]: {
    rows: ['%o%&', '%&o%', '&%&@', '&@%&', '@&%&'],
    fg: ['green1', 'green1', 'green2', 'green2', 'moon1'],
  },
  [MAT.ROCK]: {
    rows: [' .:.', '.o:o', 'oOo0', 'O0#O', '0#@0'],
    fg: ['night2', 'night3', 'night3', 'moon0', 'moon1'],
  },
  [MAT.LOG]: {
    rows: [' -.-', '-=-=', '=-==', '=#==', '#=#='],
    fg: ['brown0', 'brown1', 'brown1', 'moon0', 'moon1'],
  },
  [MAT.FIRE]: {
    rows: ['@#@&', '#*#&', '*^*+', "^'^*", "'.`'"],
    fg: ['fire4', 'fire3', 'fire2', 'fire2', 'fire1'],
  },
  [MAT.EMBER]: {
    rows: ['*+*+', "+'*'", "'.'`", ".`.'", '. . '],
    fg: ['fire4', 'fire3', 'fire2', 'fire1', 'fire1'],
  },
  [MAT.PLAYER]: {
    rows: ['@@@@', '^^A^', '#M#W', '||!|', '*o*O'],
    fg: ['fire4', 'moon0', 'red', 'brown1', 'fire3'],
  },
  [MAT.FIREFLY]: {
    rows: ['..··', '·+·+', '+*+*', '*+**', '****'],
    fg: ['green1', 'green2', 'glow', 'glow', 'glow'],
  },
};

// 生成字符图集 + 两张查找表（texelFetch 读取）：
// tGlyphs: (行*4+变体, 物体ID) -> 图集下标；tColors: (行, 物体ID) -> 前景色，最后一行为暖光梯度
// 棱边字符，按屏幕方向 0°/45°/90°/135° 排列
export const EDGE_CHARS = ['-', '/', '|', '\\'];

let cached = null;
export function getGlyphTables() {
  if (!cached) cached = buildGlyphTables();
  return cached;
}

function buildGlyphTables() {
  const chars = [' ', ...EDGE_CHARS];
  for (const spec of Object.values(SPECS)) {
    for (const row of spec.rows) for (const ch of row) if (!chars.includes(ch)) chars.push(ch);
  }
  const atlas = createGlyphAtlas(chars.join(''), 64);

  const gw = LEVELS * VARIANTS;
  const glyphData = new Uint8Array(gw * MAT_COUNT * 4);
  const colorRows = MAT_COUNT + 1;
  const colorData = new Uint8Array(LEVELS * colorRows * 4);
  const putColor = (x, y, name) => {
    const [r, g, b] = hexToRgb(PALETTE[name]);
    colorData.set([r, g, b, 255], (y * LEVELS + x) * 4);
  };

  for (let id = 0; id < MAT_COUNT; id++) {
    const spec = SPECS[id];
    if (!spec) throw new Error(`缺少物体 ${id} 的字符定义`);
    spec.rows.forEach((row, r) => {
      if ([...row].length !== VARIANTS) throw new Error(`物体 ${id} 第 ${r} 行需要 ${VARIANTS} 个字符`);
      [...row].forEach((ch, v) => {
        glyphData[(id * gw + r * VARIANTS + v) * 4] = chars.indexOf(ch);
      });
      putColor(r, id, spec.fg[r]);
    });
  }
  WARM_RAMP.forEach((name, r) => putColor(r, MAT_COUNT, name));

  const dataTex = (data, w, h) => {
    const t = new THREE.DataTexture(data, w, h, THREE.RGBAFormat, THREE.UnsignedByteType);
    t.minFilter = t.magFilter = THREE.NearestFilter;
    t.needsUpdate = true;
    return t;
  };
  return {
    atlas,
    glyphTex: dataTex(glyphData, gw, MAT_COUNT),
    colorTex: dataTex(colorData, LEVELS, colorRows),
    edgeGlyphs: EDGE_CHARS.map((c) => chars.indexOf(c)),
    palette: PALETTE,
  };
}
