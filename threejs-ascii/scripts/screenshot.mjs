// 自动截图 / 冒烟测试：需先 npm run dev，并本机装有 Chrome（可用 CHROME_PATH 指定）
import { mkdirSync } from 'node:fs';
import puppeteer from 'puppeteer-core';

const url = process.env.URL || 'http://localhost:5173/';
const out = 'screenshots';
mkdirSync(out, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: 'new',
  args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist', '--enable-unsafe-swiftshader'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 720 });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
await page.goto(url, { waitUntil: 'networkidle0' });
await sleep(2500);
await page.screenshot({ path: `${out}/01-ascii.png` });

// 关掉字符最小间距，对照原始的 3D 字符密度
await page.keyboard.press('KeyF');
await sleep(300);
await page.screenshot({ path: `${out}/01b-no-spacing.png` });
await page.keyboard.press('KeyF');

const pos = () => page.evaluate(() => window.__game.player.position.toArray().map((v) => +v.toFixed(2)));
const hold = async (key, ms) => {
  await page.keyboard.down(key);
  await sleep(ms);
  await page.keyboard.up(key);
};

const start = await pos();
await hold('KeyD', 1200);
await page.keyboard.down('KeyW');
await sleep(700);
await page.screenshot({ path: `${out}/02-walking.png` });
await page.keyboard.up('KeyW');
const walked = await pos();

// T 切换：3D 字符 -> 原始模型 -> 3D 字符
await page.keyboard.press('KeyT');
await sleep(400);
await page.screenshot({ path: `${out}/03-raw.png` });
await page.keyboard.press('KeyT');

await page.keyboard.press('KeyC');
await sleep(400);
await page.screenshot({ path: `${out}/04-mono.png` });
await page.keyboard.press('KeyC');

// 朝池塘走（屏幕下方 = 世界 +x+z），应被岸边挡住
await hold('KeyS', 3500);
const pond = await pos();
await page.screenshot({ path: `${out}/05-pond.png` });

// 靠近篝火放大，截取画面中心 1:1 细节
await hold('KeyW', 1200);
await page.evaluate(() => window.__game.rig.zoomBy(1.6));
await sleep(1500);
await page.screenshot({ path: `${out}/06-closeup.png`, clip: { x: 320, y: 180, width: 640, height: 360 } });
await page.screenshot({ path: `${out}/07-zoom3x.png`, clip: { x: 560, y: 250, width: 200, height: 120, scale: 3 } });

const status = await page.evaluate(() => document.querySelector('#hud .status').textContent);
console.log(JSON.stringify({ start, walked, pond, status }));
console.log(logs.join('\n'));
await browser.close();
