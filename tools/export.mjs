#!/usr/bin/env node
// Exporta um script .3di para .glb (glTF binário), com malhas, texturas PNG, esqueleto e animação.
// Uso: node tools/export.mjs cena.3di [saida.glb] [--res 128]
// --res: células na maior dimensão da cena (mais = mais detalhe e arquivo maior)
import { readFileSync, writeFileSync } from 'node:fs';
import { runScript } from '../src/interp.js';
import { exportGLB } from '../src/export.js';

const args = process.argv.slice(2);
const resIdx = args.indexOf('--res');
const res = resIdx >= 0 ? Number(args[resIdx + 1]) : 128;
const files = args.filter((a, i) => !a.startsWith('--') && (resIdx < 0 || i !== resIdx + 1));
const [input, output = input?.replace(/\.3di$/, '') + '.glb'] = files;
if (!input) {
  console.error('uso: node tools/export.mjs cena.3di [saida.glb] [--res 128]');
  process.exit(2);
}

const run = runScript(readFileSync(input, 'utf8'));
for (const l of run.logs) console.log(`print: ${l}`);
if (!run.ok) {
  console.error(`ERRO ${run.error.toString()}`);
  process.exit(1);
}
const { glb, stats } = await exportGLB(run.scene, {
  res,
  onProgress: (i, n) => process.stderr.write(`\rmalha ${i + 1}/${n}`),
});
process.stderr.write('\n');
writeFileSync(output, glb);
console.log(`ok: ${output} (${(stats.bytes / 1024).toFixed(0)} KB) · ${stats.parts} partes · ${stats.vertices} vértices · ${stats.triangles} triângulos` +
  `${stats.bones ? ` · ${stats.bones} ossos` : ''}${stats.animated ? ' · animado' : ''} · ${(stats.ms / 1000).toFixed(1)} s`);
for (const w of stats.warnings) console.log(`aviso: ${w}`);
