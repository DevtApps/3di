#!/usr/bin/env node
// Valida um script .3di sem navegador: executa, compila e mostra as peças e medidas.
// Uso: node scripts/check.mjs arquivo.3di [--glsl]
import { readFileSync } from 'node:fs';
import { runScript } from '../src/interp.js';
import { compileScene } from '../src/compiler.js';
import { fmtNum } from '../src/runtime.js';
import { ScriptError } from '../src/parser.js';
import { collectBones } from '../src/rig.js';

const file = process.argv[2];
if (!file) {
  console.error('uso: node scripts/check.mjs arquivo.3di [--glsl]');
  process.exit(2);
}
const src = readFileSync(file, 'utf8');
const res = runScript(src);
for (const l of res.logs) console.log(`print: ${l}`);
if (!res.ok) {
  console.error(`ERRO ${res.error.toString()}`);
  process.exit(1);
}
let out;
try {
  out = compileScene(res.scene);
} catch (e) {
  console.error(`ERRO ${e instanceof ScriptError ? e.toString() : e.stack}`);
  process.exit(1);
}
const v = (a) => `(${a.map(fmtNum).join(', ')})`;
const b = out.bbox;
console.log(`ok: ${out.leaves} primitivas${out.instances ? ` (${out.instances} como dados na BVH, ${out.codeLeaves} como código)` : ''}, ${res.scene.shapes.length} formas mostradas${out.hasPlane ? ' + chão' : ''}`);
console.log(`cena: de ${v(b.min)} até ${v(b.max)}`);
for (const p of out.parts) {
  const sz = p.bbox.max.map((x, i) => x - p.bbox.min[i]);
  console.log(`  ${p.name}: tamanho ${v(sz)}, de ${v(p.bbox.min)} até ${v(p.bbox.max)}`);
}
const bones = collectBones(res.scene.shapes);
if (bones.length) {
  console.log(`esqueleto ${bones[0].skel.name}: ${bones.length} ossos${bones.some((b) => b.animated) ? ' (animados)' : ''}`);
  for (const b of bones) console.log(`  ${b.name}: cabeça ${v(b.head)}${b.parent ? `, pai ${b.parent.name}` : ''}`);
}
if (process.argv.includes('--glsl')) console.log(out.glsl);
