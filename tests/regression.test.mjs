import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, symlink, rm, readFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { startIdeServer } from '../tools/ideserver.mjs';
import { runScript } from '../src/interp.js';
import { compileScene } from '../src/compiler.js';
import { exportGLB } from '../src/export.js';
import { buildSceneFns, surfaceColor } from '../src/sdf.js';

test('examples compile and representative scenes export', async () => {
  for (const name of await readdir(new URL('../examples/', import.meta.url))) {
    const run = runScript(await readFile(new URL(`../examples/${name}`, import.meta.url), 'utf8'));
    assert.equal(run.ok, true, name);
    assert.ok(compileScene(run.scene).glsl.length);
    if (!['mesa.3di', 'boneco.3di'].includes(name)) continue;
    const { glb, stats } = await exportGLB(run.scene, { res: 24 });
    const view = new DataView(glb.buffer, glb.byteOffset, glb.byteLength);
    assert.equal(view.getUint32(0, true), 0x46546c67);
    assert.equal(view.getUint32(8, true), glb.length);
    const length = view.getUint32(12, true);
    const json = JSON.parse(new TextDecoder().decode(glb.subarray(20, 20 + length)));
    assert.ok(json.meshes.length);
    if (name === 'boneco.3di') { assert.equal(stats.bones, 11); assert.ok(json.skins.length); assert.ok(json.animations.length); }
  }
});

test('invalid export parameters fail immediately', async () => {
  const scene = runScript('show(sphere())').scene;
  for (const res of [Infinity, NaN, 0, -1, 1.5, 2049, '128']) await assert.rejects(exportGLB(scene, { res }), /res deve/);
  scene.anim = { duration: -1, fps: 30 };
  await assert.rejects(exportGLB(scene), /animação/);
});

test('GLB export embeds procedural textures as PNG atlases with UVs', async () => {
  const run = runScript('show(sphere(1).color("white").texture("checker", color2="black", size=0.25))');
  assert.equal(run.ok, true);
  const shape = run.scene.shapes[0];
  const fns = buildSceneFns(shape);
  const colors = [[-0.8, 0.1, 0.2], [-0.6, 0.2, 0.1], [0.6, 0.1, 0.2], [0.8, 0.2, 0.1]]
    .map((point) => surfaceColor(fns.mat(...point)).map((v) => v.toFixed(3)).join(','));
  assert.equal(new Set(colors).size, 2);

  const { glb } = await exportGLB(run.scene, { res: 32 });
  const jsonLen = new DataView(glb.buffer, glb.byteOffset, glb.byteLength).getUint32(12, true);
  const json = JSON.parse(new TextDecoder().decode(glb.subarray(20, 20 + jsonLen)));
  assert.ok(json.images.length > 0);
  assert.equal(json.images[0].mimeType, 'image/png');
  assert.ok(json.textures.length > 0);
  assert.ok(json.materials.some((m) => m.pbrMetallicRoughness.baseColorTexture));
  const primitive = json.meshes[0].primitives[0];
  assert.ok(primitive.attributes.TEXCOORD_0 !== undefined);
  assert.equal(primitive.attributes.COLOR_0, undefined);
  const uv = json.accessors[primitive.attributes.TEXCOORD_0];
  const imageView = json.bufferViews[json.images[0].bufferView];
  const binStart = 20 + jsonLen + 8;
  const png = glb.subarray(binStart + imageView.byteOffset, binStart + imageView.byteOffset + imageView.byteLength);
  assert.deepEqual(Array.from(png.subarray(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.ok(uv.count > 0);
  const pngWidth = new DataView(png.buffer, png.byteOffset + 16, 4).getUint32(0);
  const pngHeight = new DataView(png.buffer, png.byteOffset + 20, 4).getUint32(0);
  const idat = [];
  for (let offset = 8; offset < png.length;) {
    const length = new DataView(png.buffer, png.byteOffset + offset, 4).getUint32(0);
    const type = new TextDecoder().decode(png.subarray(offset + 4, offset + 8));
    if (type === 'IDAT') idat.push(png.subarray(offset + 8, offset + 8 + length));
    offset += 12 + length;
    if (type === 'IEND') break;
  }
  const compressed = new Uint8Array(idat.reduce((sum, chunk) => sum + chunk.length, 0));
  let compressedOffset = 0;
  for (const chunk of idat) { compressed.set(chunk, compressedOffset); compressedOffset += chunk.length; }
  const decoded = new Uint8Array(await new Response(new Blob([compressed]).stream().pipeThrough(new DecompressionStream('deflate'))).arrayBuffer());
  assert.equal(decoded.length, pngHeight * (pngWidth * 4 + 1));
  const pixelColors = new Set();
  for (let y = 0; y < pngHeight; y++) {
    const row = y * (pngWidth * 4 + 1);
    assert.equal(decoded[row], 0, 'PNG usa scanlines sem filtro');
    for (let x = 0; x < pngWidth; x++) pixelColors.add(Array.from(decoded.subarray(row + 1 + x * 4, row + 4 + x * 4)).join(','));
  }
  assert.ok(pixelColors.size > 2, 'PNG deve conter cores baked, não só um pixel de cor sólida');
});

test('HTTP rejects escapes, malformed JSON and unauthorized bridge calls', async (t) => {
  const dir = await mkdtemp(join(tmpdir(), '3di-test-'));
  const root = join(dir, 'public');
  await mkdir(root);
  await mkdir(join(dir, 'public-private'));
  await writeFile(join(root, 'index.html'), 'IDE');
  await writeFile(join(dir, 'public-private', 'secret.3di'), 'secret');
  await symlink(join(dir, 'public-private', 'secret.3di'), join(root, 'escape.3di'));
  const ide = await startIdeServer({ root, port: 0, token: 'test-token' });
  t.after(async () => { ide.close(); await rm(dir, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${ide.port}`;
  const headers = { 'X-3DI-Token': 'test-token' };
  assert.equal((await fetch(base)).status, 200);
  assert.equal((await fetch(`${base}/%2e%2e%2fpublic-private%2fsecret.3di`)).status, 403);
  assert.equal((await fetch(`${base}/escape.3di`)).status, 403);
  assert.equal((await fetch(`${base}/%FF`)).status, 400);
  for (const path of ['/bridge/call', '/bridge/reply']) {
    assert.equal((await fetch(base + path, { method: 'POST', body: '{}' })).status, 403);
    for (const body of ['{', 'null', '[]']) assert.equal((await fetch(base + path, { method: 'POST', headers, body })).status, 400);
  }
  assert.equal((await fetch(`${base}/bridge/events`)).status, 403);
  assert.equal((await fetch(`${base}/bridge/session`)).status, 403);
  assert.equal((await fetch(`${base}/bridge/session`, { headers: { 'X-3DI-Client': 'ide', Origin: 'https://evil.example' } })).status, 403);
  const session = await fetch(`${base}/bridge/session`, { headers: { 'X-3DI-Client': 'ide' } });
  assert.equal((await session.json()).token, 'test-token');
  const ping = await fetch(`${base}/bridge/call`, { method: 'POST', headers, body: JSON.stringify({ cmd: 'ping' }) });
  assert.equal((await ping.json()).ok, true);
});

test('scene worker transfers compiled scenes, errors and GLB', async () => {
  const { Worker } = await import('node:worker_threads');
  const moduleURL = new URL('../src/scene-worker.js', import.meta.url).href;
  const job = (data) => new Promise((resolve, reject) => {
    const worker = new Worker(`const { parentPort } = require('node:worker_threads');
      globalThis.self = { postMessage: value => parentPort.postMessage(value) };
      import(${JSON.stringify(moduleURL)}).then(() => parentPort.on('message', data => self.onmessage({ data })));`, { eval: true });
    worker.once('message', value => { worker.terminate(); resolve(value); });
    worker.once('error', reject);
    worker.postMessage(data);
  });
  const code = await readFile(new URL('../examples/boneco.3di', import.meta.url), 'utf8');
  const compiled = await job({ task: 'compile', code, time: 1 });
  assert.ok(compiled.result?.out.glsl.length, JSON.stringify(compiled.error));
  const exported = await job({ task: 'export', code, res: 24 });
  assert.ok(exported.result?.glb instanceof Uint8Array, JSON.stringify(exported.error));
  assert.ok((await job({ task: 'compile', code: 'show(no_such_shape())' })).error.message);
});

test('GLB atlas UVs use the glTF top-left origin: each vertex samples its own surface color', async () => {
  const run = runScript('show(sphere(1).color("white").texture("checker", color2="black", size=0.25))');
  const fns = buildSceneFns(run.scene.shapes[0]);
  const { glb } = await exportGLB(run.scene, { res: 32 });
  const dv = new DataView(glb.buffer, glb.byteOffset, glb.byteLength);
  const jsonLen = dv.getUint32(12, true);
  const json = JSON.parse(new TextDecoder().decode(glb.subarray(20, 20 + jsonLen)));
  const binStart = 20 + jsonLen + 8;
  const view = (i) => json.bufferViews[i];
  const floats = (accessor) => {
    const bv = view(accessor.bufferView);
    const start = glb.byteOffset + binStart + (bv.byteOffset ?? 0) + (accessor.byteOffset ?? 0);
    return new Float32Array(glb.buffer.slice(start, start + accessor.count * (accessor.type === 'VEC3' ? 12 : 8)));
  };

  const prim = json.meshes[0].primitives[0];
  const imageView = view(json.images[json.textures[json.materials[prim.material].pbrMetallicRoughness.baseColorTexture.index].source].bufferView);
  const png = glb.subarray(binStart + imageView.byteOffset, binStart + imageView.byteOffset + imageView.byteLength);
  const pdv = new DataView(png.buffer, png.byteOffset, png.byteLength);
  const width = pdv.getUint32(16), height = pdv.getUint32(20);
  const idat = [];
  for (let o = 8; o < png.length;) {
    const len = pdv.getUint32(o), type = new TextDecoder().decode(png.subarray(o + 4, o + 8));
    if (type === 'IDAT') idat.push(png.subarray(o + 8, o + 8 + len));
    o += 12 + len;
  }
  const raw = new Uint8Array(await new Response(new Blob(idat).stream().pipeThrough(new DecompressionStream('deflate'))).arrayBuffer());
  const texel = (u, v) => {
    const x = Math.floor(u * width), y = Math.floor(v * height), at = y * (width * 4 + 1) + 1 + x * 4;
    return [raw[at], raw[at + 1], raw[at + 2]];
  };
  const srgb = (x) => Math.round(255 * (x <= 0.0031308 ? 12.92 * x : 1.055 * x ** (1 / 2.4) - 0.055));

  const pos = floats(json.accessors[prim.attributes.POSITION]);
  const uv = floats(json.accessors[prim.attributes.TEXCOORD_0]);
  let match = 0, total = 0;
  for (let i = 0; i < uv.length / 2; i += 7) {
    const want = surfaceColor(fns.mat(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])).map((c) => srgb(Math.max(0, Math.min(1, c))));
    const got = texel(uv[i * 2], uv[i * 2 + 1]);
    total++;
    if (want.every((w, k) => Math.abs(w - got[k]) < 12)) match++;
  }
  assert.ok(total > 50);
  assert.ok(match / total > 0.9, `só ${match} de ${total} vértices acharam a própria cor no atlas`);
});
