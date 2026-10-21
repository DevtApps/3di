#!/usr/bin/env node
// Exporta um script .3di para .glb (glTF binário), com malhas, texturas PNG, esqueleto e animação.
// Uso: node scripts/export.mjs cena.3di [saida.glb] [--res 128]
// --res: células na maior dimensão de cada peça (mais = mais detalhe e arquivo maior)
// THREEDI_SERIAL=1 malha num núcleo só (para comparar ou depurar)
import { readFileSync, writeFileSync } from 'node:fs';
import { runScript } from '../src/interp.js';
import { exportGLB } from '../src/export.js';
import { nodePartRunner } from '../src/parallel-node.js';
const PARTS_WORKER = new URL('../src/parts-worker-node.js', import.meta.url);

const args = process.argv.slice(2);
const resIdx = args.indexOf('--res');
const res = resIdx >= 0 ? Number(args[resIdx + 1]) : 128;
const files = args.filter((a, i) => !a.startsWith('--') && (resIdx < 0 || i !== resIdx + 1));
const [input, output = input?.replace(/\.3di$/, '') + '.glb'] = files;
if (!input) {
  console.error('uso: node scripts/export.mjs cena.3di [saida.glb] [--res 128]');
  process.exit(2);
}

const code = readFileSync(input, 'utf8');
const run = runScript(code);
for (const l of run.logs) console.log(`print: ${l}`);
if (!run.ok) {
  console.error(`ERRO ${run.error.toString()}`);
  process.exit(1);
}
const { glb, stats } = await exportGLB(run.scene, {
  res,
  // as peças são malhadas em paralelo, uma por núcleo
  runParts: process.env.THREEDI_SERIAL ? null : nodePartRunner({ code, res, workerUrl: PARTS_WORKER }),
  onProgress: (i, n) => process.stderr.write(`\rmalha ${i + 1}/${n}`),
});
process.stderr.write('\n');
writeFileSync(output, glb);
console.log(`ok: ${output} (${(stats.bytes / 1024).toFixed(0)} KB) · ${stats.parts} partes · ${stats.vertices} vértices · ${stats.triangles} triângulos` +
  `${stats.bones ? ` · ${stats.bones} ossos` : ''}${stats.animated ? ' · animado' : ''} · ${(stats.ms / 1000).toFixed(1)} s`);
for (const w of stats.warnings) console.log(`aviso: ${w}`);
