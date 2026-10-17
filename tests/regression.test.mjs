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

test('materials: gradient follows the axis, triplanar projects every face, bump bakes a normal map', async () => {
  // degradê: base na cor da forma, topo em color2
  let run = runScript('show(cylinder(0.25, 1).color("#102030").texture("gradient", color2="#f0e0d0"))');
  assert.equal(run.ok, true, run.error?.toString());
  let fns = buildSceneFns(run.scene.shapes[0]);
  const at = (y) => surfaceColor(fns.mat(0.25, y, 0), [1, 0, 0]);
  const bottom = at(-0.45), top = at(0.45);
  assert.ok(top[0] > bottom[0] + 0.3 && top[1] > bottom[1] + 0.3, 'o topo do degradê deve ser bem mais claro que a base');

  // triplanar: o topo de um bloco de tijolos tem argamassa, a projeção normal só tem listras
  const tri = (flag) => {
    const r = runScript(`show(box(1).color("#a8553a").texture("bricks", size=0.3, triplanar=${flag}))`);
    const f = buildSceneFns(r.scene.shapes[0]);
    const colors = new Set();
    for (let i = 0; i < 40; i++) colors.add(surfaceColor(f.mat(-0.45 + i * 0.0231, 0.5, -0.45 + i * 0.0173), [0, 1, 0]).map((c) => c.toFixed(2)).join(','));
    return colors.size;
  };
  assert.ok(tri('True') > tri('False'), 'o topo com triplanar mostra mais variação (tijolos) que com a projeção normal');

  // relevo: o GLB ganha normalTexture, e o PNG de normais tem inclinações (não é tudo azul liso)
  run = runScript('show(box(1).color("#a8553a").texture("bricks", size=0.3, bump=0.6))');
  const { glb } = await exportGLB(run.scene, { res: 24 });
  const dv = new DataView(glb.buffer, glb.byteOffset, glb.byteLength);
  const jsonLen = dv.getUint32(12, true);
  const json = JSON.parse(new TextDecoder().decode(glb.subarray(20, 20 + jsonLen)));
  const material = json.materials.find((m) => m.normalTexture);
  assert.ok(material, 'o material com bump deve ter normalTexture');
  const image = json.images[json.textures[material.normalTexture.index].source];
  const view = json.bufferViews[image.bufferView];
  const binStart = 20 + jsonLen + 8;
  const png = glb.subarray(binStart + view.byteOffset, binStart + view.byteOffset + view.byteLength);
  assert.deepEqual(Array.from(png.subarray(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10]);
  const pdv = new DataView(png.buffer, png.byteOffset, png.byteLength);
  const width = pdv.getUint32(16), height = pdv.getUint32(20);
  const idat = [];
  for (let o = 8; o < png.length;) {
    const len = pdv.getUint32(o), type = new TextDecoder().decode(png.subarray(o + 4, o + 8));
    if (type === 'IDAT') idat.push(png.subarray(o + 8, o + 8 + len));
    o += 12 + len;
  }
  const raw = new Uint8Array(await new Response(new Blob(idat).stream().pipeThrough(new DecompressionStream('deflate'))).arrayBuffer());
  let tilted = 0;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const at = y * (width * 4 + 1) + 1 + x * 4;
    if (raw[at + 3] === 255 && (Math.abs(raw[at] - 128) > 20 || Math.abs(raw[at + 1] - 128) > 20)) tilted++;
  }
  assert.ok(tilted > 50, `o normal map deve ter texels inclinados (achou ${tilted})`);
});

test('grass generator: every kind x style compiles, seed is deterministic, bad arguments explain themselves', () => {
  const kinds = ['lawn', 'meadow', 'tall', 'dry', 'tufts', 'wheat', 'clover'];
  const styles = ['lowpoly', 'stylized', 'realistic'];
  for (const kind of kinds) for (const style of styles) {
    const run = runScript(`show(grass(1, 1, kind="${kind}", style="${style}", seed=3))`);
    assert.equal(run.ok, true, `${kind}/${style}: ${run.error?.toString()}`);
    const out = compileScene(run.scene);
    assert.ok(out.leaves > 0 && out.leaves < 200, `${kind}/${style} deve ser leve (achou ${out.leaves} primitivas)`);
  }
  const glsl = (src) => compileScene(runScript(src).scene).glsl;
  assert.equal(glsl('show(grass(1, seed=9))'), glsl('show(grass(1, seed=9))'));
  assert.notEqual(glsl('show(grass(1, seed=9))'), glsl('show(grass(1, seed=10))'));
  // sem seed próprio, o seed() da cena controla o resultado
  assert.equal(glsl('seed(4)\nshow(grass(1))'), glsl('seed(4)\nshow(grass(1))'));
  const bad = runScript('show(grass(1, kind="gramado"))');
  assert.equal(bad.ok, false);
  assert.match(bad.error.hint ?? bad.error.toString(), /lawn|meadow/);
  assert.equal(runScript('show(grass(1, style="x"))').ok, false);
  assert.equal(runScript('show(grass(1, density=0))').ok, false);
});

test('plant and tree generators: every kind x style compiles light, seed is deterministic, bad arguments hint', () => {
  const styles = ['lowpoly', 'stylized', 'realistic'];
  const cases = [
    ['plant', ['flower', 'daisy', 'lavender', 'fern', 'bush', 'cactus', 'mushroom']],
    ['tree', ['oak', 'pine', 'birch', 'palm', 'willow', 'dead', 'round', 'bonsai']],
  ];
  for (const [fn, kinds] of cases) for (const kind of kinds) for (const style of styles) {
    const run = runScript(`show(${fn}(kind="${kind}", style="${style}", seed=3))`);
    assert.equal(run.ok, true, `${fn} ${kind}/${style}: ${run.error?.toString()}`);
    const out = compileScene(run.scene);
    assert.ok(out.leaves > 0 && out.leaves < 90, `${fn} ${kind}/${style} deve ser leve (achou ${out.leaves} primitivas)`);
    assert.ok(Number.isFinite(run.scene.shapes[0].bbox.max[1]) && run.scene.shapes[0].bbox.max[1] > 0, `${fn} ${kind}/${style} deve ter altura`);
  }
  const glsl = (src) => JSON.stringify(compileScene(runScript(src).scene).data ?? compileScene(runScript(src).scene).glsl);
  assert.equal(glsl('show(tree(kind="oak", seed=7))'), glsl('show(tree(kind="oak", seed=7))'));
  assert.notEqual(glsl('show(tree(kind="oak", seed=7))'), glsl('show(tree(kind="oak", seed=8))'));
  assert.equal(glsl('show(plant(kind="fern", seed=2))'), glsl('show(plant(kind="fern", seed=2))'));
  // altura pedida é respeitada (copas e hastes podem passar um pouco)
  const tall = runScript('show(tree(kind="pine", height=10))').scene.shapes[0].bbox;
  assert.ok(tall.max[1] > 8 && tall.max[1] < 13, `pinheiro de 10 m mediu ${tall.max[1]}`);
  for (const bad of ['tree(kind="carvalho")', 'plant(kind="rosa")', 'tree(style="x")', 'plant(density=0)', 'tree(height=0)']) {
    assert.equal(runScript(`show(${bad})`).ok, false, bad);
  }
  assert.match(runScript('show(tree(kind="carvalho"))').error.toString(), /oak|pine/);
});

test('person and vehicle generators: every combination compiles light, sizes are honored, seed is deterministic, bad arguments hint', () => {
  const styles = ['lowpoly', 'stylized', 'realistic'];
  for (const build of ['slim', 'average', 'stocky', 'child', 'elder']) for (const style of styles) {
    const run = runScript(`show(person(style="${style}", build="${build}", seed=3))`);
    assert.equal(run.ok, true, `person ${build}/${style}: ${run.error?.toString()}`);
    const leaves = compileScene(run.scene).leaves;
    assert.ok(leaves > 10 && leaves < 70, `person ${build}/${style} deve ser leve (achou ${leaves})`);
  }
  for (const pose of ['stand', 'walk', 'sit', 'arms_up']) for (const outfit of ['casual', 'suit', 'sport', 'dress', 'uniform']) for (const hair of ['short', 'long', 'bald', 'ponytail', 'curly', 'bun']) {
    assert.equal(runScript(`show(person(pose="${pose}", outfit="${outfit}", hair="${hair}", seed=5))`).ok, true, `${pose}/${outfit}/${hair}`);
  }
  const h = (src) => { const b = runScript(src).scene.shapes[0].bbox; return b.max[1] - b.min[1]; };
  assert.ok(Math.abs(h('show(person(height=1.8))') - 1.8) < 0.1, 'a pessoa deve ter a altura pedida');
  assert.ok(Math.abs(h('show(person(build="child"))') - 1.1) < 0.08, 'a criança tem 1,1 m por padrão');
  assert.ok(h('show(person(pose="arms_up"))') > h('show(person())') + 0.1, 'braços para cima aumentam a altura total');

  for (const kind of ['car', 'hatch', 'suv', 'pickup', 'van', 'bus', 'truck', 'tractor', 'bike', 'motorbike']) for (const style of styles) {
    const run = runScript(`show(vehicle(kind="${kind}", style="${style}", seed=3))`);
    assert.equal(run.ok, true, `vehicle ${kind}/${style}: ${run.error?.toString()}`);
    const out = compileScene(run.scene);
    assert.ok(out.leaves > 8 && out.leaves < 80, `vehicle ${kind}/${style} deve ser leve (achou ${out.leaves})`);
    const b = run.scene.shapes[0].bbox;
    assert.ok(Math.abs(b.min[1]) < 0.02, `vehicle ${kind}/${style} deve apoiar as rodas no chão`);
  }
  const len = (src) => { const b = runScript(src).scene.shapes[0].bbox; return b.max[2] - b.min[2]; };
  assert.ok(Math.abs(len('show(vehicle(kind="car", length=3))') - 3) < 0.05, 'length deve redimensionar o veículo');
  assert.ok(len('show(vehicle(kind="bus"))') > len('show(vehicle(kind="car"))') * 2, 'o ônibus é bem mais longo que o carro');
  const spin = compileScene(runScript('show(vehicle(wheels_angle=time * 90))').scene);
  assert.equal(spin.animated, true, 'wheels_angle com time deve animar a cena');

  const glsl = (src) => JSON.stringify(compileScene(runScript(src).scene).data ?? compileScene(runScript(src).scene).glsl);
  assert.equal(glsl('show(person(seed=4))'), glsl('show(person(seed=4))'));
  assert.notEqual(glsl('show(person(seed=4))'), glsl('show(person(seed=5))'));
  assert.equal(glsl('show(vehicle(seed=4))'), glsl('show(vehicle(seed=4))'));
  for (const bad of ['person(build="gigante")', 'person(pose="voar")', 'person(outfit="x")', 'person(hair="x")', 'person(height=0)', 'vehicle(kind="navio")', 'vehicle(style="x")', 'vehicle(length=0)']) {
    assert.equal(runScript(`show(${bad})`).ok, false, bad);
  }
  assert.match(runScript('show(vehicle(kind="carro"))').error.toString(), /car|bus/);
});

test('new primitives, modifiers and implicit shapes: geometry is right on the CPU evaluator, errors explain themselves', async () => {
  const dist = (src, ...pts) => {
    const run = runScript(src);
    assert.equal(run.ok, true, `${src}: ${run.error?.toString()}`);
    compileScene(run.scene); // também precisa gerar GLSL
    const f = buildSceneFns(run.scene.shapes[0]);
    return pts.map((p) => f.dist(...p));
  };
  const bbox = (src) => runScript(src).scene.shapes[0].bbox;

  // polígono e estrela: dentro < 0, fora > 0, e as dimensões batem
  let [inside, outside] = dist('show(polygon(6, 0.5, 1))', [0, 0, 0], [1, 0, 0]);
  assert.ok(inside < -0.4 && outside > 0.4);
  // pontas em 0°, 72°...; os vales (raio interno 0.2) ficam em 36°, 108°...
  const star = dist('show(star(5, 0.5, inner=0.2, h=0.2))', [0.45, 0, 0], [0.3 * Math.cos(Math.PI / 5), 0, 0.3 * Math.sin(Math.PI / 5)]);
  assert.ok(star[0] < 0.01, 'a ponta da estrela está dentro');
  assert.ok(star[1] > 0.02, 'o vale entre as pontas está fora');
  assert.ok(Math.abs(bbox('show(polygon(6, 0.5, 2))').max[1] - 1) < 1e-9);

  // extrude côncavo (L) com os dois eixos
  const L = '[(0, 0), (1, 0), (1, 0.4), (0.4, 0.4), (0.4, 1), (0, 1)]';
  const [inArm, inHole] = dist(`show(extrude(${L}, h=0.2))`, [0.2, 0.8, 0], [0.8, 0.8, 0]);
  assert.ok(inArm < 0 && inHole > 0.1, 'o canto vazio do L fica fora');
  assert.ok(dist(`show(extrude(${L}, h=0.2, axis="y"))`, [0.2, 0, 0.8])[0] < 0, 'axis y usa (x, z)');

  // wedge: rampa sobe para +x
  const [lowX, highX] = dist('show(wedge(1, 1, 1))', [-0.4, 0.3, 0], [0.4, 0.3, 0]);
  assert.ok(lowX > 0 && highX < 0, 'a rampa é alta em +x e baixa em -x');

  // lathe: dentro do vaso < 0, no eixo (sem aresta falsa) e fora > 0; suavizar não passa do raio máximo
  const vase = 'show(lathe([(0, 0), (0.4, 0), (0.3, 0.6), (0.1, 1), (0, 1)], smooth=3))';
  const [onAxis, nearWall, far] = dist(vase, [0, 0.5, 0], [0.3, 0.2, 0], [0.9, 0.5, 0]);
  assert.ok(onAxis < -0.2 && nearWall < 0 && far > 0.4);
  assert.ok(bbox(vase).max[0] <= 0.41, 'o perfil suavizado não ultrapassa o raio máximo');

  // hemisphere e tube
  const [domeIn, domeBelow] = dist('show(hemisphere(0.5))', [0, 0.1, 0], [0, -0.4, 0]);
  assert.ok(domeIn < 0 && domeBelow > 0, 'a meia esfera só existe na metade de cima');
  assert.ok(dist('show(tube(0.5, 0.1, 1))', [0, 0, 0], [0.45, 0, 0]).every((d, i) => (i === 0 ? d > 0 : d < 0)), 'o cano é oco');

  // taper: a seção encolhe para o topo
  const [wideBase, narrowTop] = dist('show(cylinder(0.4, 2).taper(top=0.25))', [0.35, -0.9, 0], [0.35, 0.9, 0]);
  assert.ok(wideBase < 0 && narrowTop > 0, 'taper afina o topo');
  // bend: a ponta curva para +x
  const bent = dist('show(cylinder(0.1, 2).ground().bend(90))', [0, 1.95, 0], [0.9, 1.7, 0]);
  assert.ok(bent[0] > 0.1, 'a ponta saiu do eixo original');
  assert.ok(bbox('show(cylinder(0.1, 2).ground().bend(90))').max[0] > 0.5, 'a caixa acompanha a curva');
  // shear: o deslocamento cresce a partir da base (y = -0.5): em y = 0.4 a caixa fica em x de 0.25 a 0.65
  assert.ok(dist('show(box(0.4, 1, 0.4).shear(x=0.5))', [0.45, 0.4, 0], [-0.25, 0.4, 0]).every((d, i) => (i === 0 ? d < 0 : d > 0)));
  // polar: oito cópias em volta do eixo, uma por setor
  const ring = 'show(box(0.1, 0.1, 0.1).at(1, 0, 0).polar(8))';
  const around = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => dist(ring, [Math.cos((i * Math.PI) / 4), 0, Math.sin((i * Math.PI) / 4)])[0]);
  assert.ok(around.every((d) => d < 0), 'há uma cópia em cada um dos 8 setores');
  assert.ok(dist(ring, [Math.cos(Math.PI / 8), 0, Math.sin(Math.PI / 8)])[0] > 0, 'e há vazio entre elas');
  // elongate: esfera vira cápsula
  const [capMid, capEnd] = dist('show(sphere(0.3).elongate(y=1))', [0, 0.45, 0], [0, 0.9, 0]);
  assert.ok(capMid < 0 && capEnd > 0);
  assert.ok(Math.abs(bbox('show(sphere(0.3).elongate(y=1))').max[1] - 0.8) < 1e-9);

  // implicit: a fórmula vira distância na CPU e GLSL; respeita size e time anima
  const [core, surface] = dist('show(implicit(lambda x, y, z: hypot(x, y, z) - 0.5, size=1.4, lip=1))', [0, 0, 0], [0.5, 0, 0]);
  assert.ok(Math.abs(core + 0.5) < 1e-9 && Math.abs(surface) < 1e-9);
  assert.ok(Math.abs(bbox('show(implicit(lambda x, y, z: x, size=(2, 1, 3)))').max[2] - 1.5) < 1e-9);
  assert.equal(compileScene(runScript('show(implicit(lambda x, y, z: hypot(x, y, z) - 0.4 - 0.1 * sin(time), size=1))').scene).animated, true);
  const blobs = 'def f(x, y, z):\n    return -log(exp(-9 * (hypot(x - 0.2, y, z) - 0.2)) + exp(-9 * (hypot(x + 0.2, y, z) - 0.2))) / 9\nshow(implicit(f, size=1, lip=0.8))';
  assert.ok(dist(blobs, [0, 0, 0], [0.9, 0, 0]).every((d, i) => (i === 0 ? d < 0 : d > 0)), 'as metabolas se fundem no meio');

  // as formas novas exportam malha de verdade
  const { glb, stats } = await exportGLB(runScript('show(lathe([(0, 0), (0.4, 0), (0.1, 1), (0, 1)], smooth=2), star(5, 0.5).at(1.2, 0.3, 0), implicit(lambda x, y, z: hypot(x, y, z) - 0.4, size=1).at(-1.2, 0.5, 0))').scene, { res: 48 });
  assert.ok(glb.length > 5000 && stats.triangles > 500, `a exportação deve gerar malha (achou ${stats.triangles} triângulos)`);

  // erros com dica
  const errs = [
    ['polygon(2)', /sides/], ['star(2)', /points/], ['extrude([(0, 0), (1, 1)])', /pelo menos 3/], ['extrude(5)', /lista de pontos/],
    ['extrude([(0,0),(1,0),(0,1)], axis="x")', /axis/], ['lathe([(-1, 0), (1, 1)])', /negativo/], ['lathe([(0, 0)])', /pelo menos 2/],
    ['tube(0.5, 0.6)', /thickness/], ['cylinder(1, 1).taper(top=0)', /maiores que zero/], ['cylinder(1, 1).bend(30, axis="y", toward="y")', /outro eixo/],
    ['box(1).polar(1)', /inteiro/], ['sphere(1).elongate(x=-1)', /negativos/], ['implicit(5)', /função/], ['implicit(lambda x, y, z: 1.0)', /depender de x/],
    ['implicit(lambda x, y, z: x, lip=2)', /lip/], ['implicit(lambda x, y, z: x if x > 0 else y)', /comparar/],
  ];
  for (const [src, re] of errs) {
    const run = runScript(`show(${src})`);
    assert.equal(run.ok, false, src);
    assert.match(`${run.error.toString()} ${run.error.hint ?? ''}`, re, src);
  }
});
