#!/usr/bin/env node
// Renderiza uma cena .3di em 4 vistas (frente, lado, topo e perspectiva) numa imagem PNG,
// para conferir visualmente o que foi montado. Roda o editor (index.html) num Chrome headless.
// Uso: node scripts/render.mjs cena.3di saida.png [--t segundos] [--size px] [--cpu]
// O Chrome é procurado em $CHROME, nos caminhos comuns e no cache do Playwright. Usa a GPU;
// sem WebGL2 na GPU (ou com --cpu) cai para o SwiftShader, que é bem mais lento.
import { readFileSync, writeFileSync } from 'node:fs';
import { openEditor } from './headless.mjs';

const USAGE = 'uso: node scripts/render.mjs cena.3di saida.png [--t segundos] [--size px] [--cpu]';

// ---------- argumentos ----------

const args = process.argv.slice(2);
const pos = [];
const opt = { t: null, size: 512, cpu: false };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--t' || a === '--size') {
    const v = Number(args[++i]);
    if (!Number.isFinite(v)) fail(`${a} precisa de um número\n${USAGE}`, 2);
    opt[a.slice(2)] = v;
  } else if (a === '--cpu') {
    opt.cpu = true;
  } else if (a === '-h' || a === '--help') {
    console.log(USAGE);
    process.exit(0);
  } else pos.push(a);
}
if (pos.length !== 2) fail(USAGE, 2);
const [input, output] = pos;
let src;
try {
  src = readFileSync(input, 'utf8');
} catch (e) {
  fail(`não consegui ler ${input}: ${e.message}`, 2);
}
opt.size = Math.round(Math.min(2048, Math.max(64, opt.size)));

function fail(msg, code = 1) {
  console.error(msg);
  process.exit(code);
}

async function main() {
  const b = await openEditor(src, { cpu: opt.cpu });

  const status = await b.evaluate(`window.tdi.load(${JSON.stringify(src)})`);
  if (!status.startsWith('✓')) {
    await b.close();
    fail(status.replace(/^✗\s*/, 'ERRO '));
  }
  const t = opt.t ?? 0;
  const dataUrl = await b.evaluate(`window.tdi.views({ size: ${opt.size}, t: ${t} })`);
  writeFileSync(output, Buffer.from(dataUrl.slice(dataUrl.indexOf(',') + 1), 'base64'));
  await b.close();
  console.log(`${status.split('\n')[0]}\nimagem: ${output} (${opt.size * 2}x${opt.size * 2}: frente, lado, topo, perspectiva${status.includes('animado') ? `; t = ${t} s` : ''})`);
}

main().then(() => process.exit(0), (e) => fail(`ERRO ${e.message}`));
