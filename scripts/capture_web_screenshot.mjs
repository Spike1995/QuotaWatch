// capture_web_screenshot.mjs - 用本机 Edge 无头模式给网页截图（真实等待，避免虚拟时间导致白屏）
//
// 用法（需要先用任意静态服务器托管页面，例如 python -m http.server 8899）：
//   node scripts/capture_web_screenshot.mjs <url> <输出png> [宽] [高] [等待毫秒]
// 示例：
//   node scripts/capture_web_screenshot.mjs http://localhost:8899/ shot.png 1440 900 8000
//
// 原理：启动带远程调试端口的无头 Edge，通过 CDP（Chrome DevTools Protocol）
// 导航到目标地址，真实等待页面渲染完成后再抓帧，因此 Flutter Web 也能截到内容。
// 无任何 npm 依赖：Node 18+ 内置 fetch，Node 22+ 内置 WebSocket。

import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const EDGE =
  process.env.EDGE_PATH ||
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

const [, , url, out = 'shot.png', width = '1440', height = '900', waitMs = '8000'] =
  process.argv;

if (!url) {
  console.error('缺少目标 URL');
  process.exit(1);
}

// --remote-debugging-port=0 让系统分配空闲端口，端口从 stderr 的
// "DevTools listening on ws://..." 一行解析出来。
const edge = spawn(EDGE, [
  '--headless=new',
  '--disable-gpu',
  '--remote-debugging-port=0',
  `--window-size=${width},${height}`,
  '--user-data-dir=' + process.env.TEMP + `\\edge-cdp-profile-${Date.now()}`,
  'about:blank',
]);

const wsUrl = await new Promise((resolve, reject) => {
  let buffer = '';
  edge.stderr.on('data', (chunk) => {
    buffer += chunk;
    const match = buffer.match(/DevTools listening on (ws:\/\/\S+)/);
    if (match) resolve(match[1]);
  });
  edge.on('exit', () => reject(new Error('Edge 提前退出：' + buffer)));
  setTimeout(() => reject(new Error('等待 DevTools 端口超时')), 15000);
});

// 浏览器级 WebSocket 换页面级：/json/list 里取 about:blank 标签页的调试地址。
const port = new URL(wsUrl).port;
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const page = targets.find((t) => t.type === 'page');

const ws = new WebSocket(page.webSocketDebuggerUrl);
let seq = 0;
const pending = new Map();
function send(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
}

const loaded = new Promise((resolve) => {
  ws.addEventListener('message', (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id).resolve(msg.result);
      pending.delete(msg.id);
    }
    if (msg.method === 'Page.loadEventFired') resolve();
  });
});

await new Promise((resolve) => ws.addEventListener('open', resolve));
await send('Page.enable');
await send('Page.navigate', { url });
await loaded;
// load 事件只代表骨架就绪；Flutter 首帧在引擎初始化后，再真实等待一段时间。
await new Promise((resolve) => setTimeout(resolve, Number(waitMs)));

const shot = await send('Page.captureScreenshot', { format: 'png' });
writeFileSync(out, Buffer.from(shot.data, 'base64'));
console.log('已保存截图：' + out);

ws.close();
edge.kill();
process.exit(0);
