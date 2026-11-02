// 使用官方网页的公开 WASM；worker 和 WASM 路径由命令行传入，不成为游戏运行依赖。
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const [workerPath, wasmPath] = process.argv.slice(2);
if (!workerPath || !wasmPath) throw new Error('请传入官方 worker.js 与法线生成器 .wasm 路径');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'assets/card_ui/shop/relief_sample');
let worker = fs.readFileSync(workerPath, 'utf8');
// 仅暴露官方闭包里的初始化及生成函数，法线算法完全使用下载的官方实现。
if (!worker.endsWith('})();\n') && !worker.endsWith('})();')) throw new Error('官方 worker 格式已改变，请核对后适配');
worker = worker.replace(/\}\)\(\);\s*$/, 'globalThis.spriteNormals = { init: z, generate: C };})();');
const context = vm.createContext({ console, TextDecoder, TextEncoder, WebAssembly, Uint8Array,
  FinalizationRegistry, URL, Response, Request, self: {} });
vm.runInContext(worker, context);
context.wasmBytes = new Uint8Array(fs.readFileSync(wasmPath));
await vm.runInContext('spriteNormals.init({module_or_path: wasmBytes})', context);
const settings = {
  body: { strength: 1.4, detail: 6.0, smoothing: 0.85, volume: 0, directx: false },
  gold: { strength: 1.0, detail: 0, smoothing: 0.6, volume: 0.5, directx: false },
};
for (const [part, options] of Object.entries(settings)) {
  const inputName = part === 'body' ? 'body_height_input.png' : 'gold_shape_input.png';
  context.inputBytes = new Uint8Array(fs.readFileSync(path.join(output, inputName)));
  context.optionsJson = JSON.stringify(options);
  const result = vm.runInContext('spriteNormals.generate(inputBytes, optionsJson)', context);
  try {
    fs.writeFileSync(path.join(output, `${part}_normal.png`), result.normal_png);
    console.log(part, result.metadata);
  } finally { result.free(); }
}
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
fs.writeFileSync(path.join(output, 'generation.json'), JSON.stringify({
  description: 'Sprite Normals 官方 WASM 生成；袋身使用用户原始高度图，不叠加自动轮廓体积或预设折痕；金纹保持独立。',
  tool: 'https://www.spritefusion.com/sprite-normals',
  wasm_url: 'https://www.spritefusion.com/_app/immutable/workers/assets/spritefusion_sprite_normals_bg-DtB4nPko.wasm',
  worker_url: 'https://www.spritefusion.com/_app/immutable/workers/worker-Cllu-FMn.js',
  wasm_sha256: hash(wasmPath), worker_sha256: hash(workerPath),
  source_sha256: hash(path.join(root, 'assets/card_ui/shop/ash_ledger_large.png')), settings,
  height_sha256: hash(path.join(output, 'body_height_input.png')),
}, null, 2) + '\n');
